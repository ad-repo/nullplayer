import CoreGraphics
import Foundation

/// The controls a skin shares with the host: sliders that read and drive the volume, seek, balance
/// and equalizer, the EQ on/off and Auto switches, and the positions Winamp posts to them. Split out
/// of `WinampModernScriptRuntime.swift`.
extension WinampModernScriptRuntime {
    /// The sliders Winamp posts a position to whenever the value they drive changes.
    enum PostedSlider: String {
        case seek, volume

        /// Stock Winamp Modern's off-screen slider for the value, kept for a skin that names one
        /// without declaring the action.
        var legacyID: String { self == .seek ? "HiddenSeek" : "HiddenVolume" }
    }

    /// Post `value` to every slider that drives `kind`, as Winamp does whenever it changes.
    ///
    /// The rule is the one `timeDependentRects` uses to decide what repaints from the clock: a seek
    /// slider is `action="SEEK"`, whatever it is named, and a volume slider `action="VOLUME"`. Posting
    /// to `HiddenSeek` alone meant a skin that names its seek slider anything else never heard the
    /// clock — ClassicPro engine "two" hangs its whole seek fill off `two.info.seeker.slider.0`, and
    /// in cPro2 Dark Aluminum the seek bar *is* the top panel, which never advanced while a track
    /// played. Posting to `HiddenVolume` alone left Anunaki's wheel LED arc and "Volume: n%" readout,
    /// both stepped from `hidevol`'s `onPostedPosition`, on their load-time value. The ids are
    /// deduplicated because stock declares both a `Seeker` and a `SeekerGhost`, and a doubled post
    /// is a doubled handler chain.
    func postPosition(_ value: Int32, to kind: PostedSlider) {
        for slider in postedSliders(kind) {
            _ = try? dispatch(object: slider, event: "onpostedposition", arguments: [.integer(value)])
        }
    }

    /// Cached per graph structure: the seek post runs ten times a second while a track plays.
    private func postedSliders(_ kind: PostedSlider) -> [WasabiObject] {
        let graph = loadedSkin.runtime.graph
        if let cached = postedSliderCache[kind], cached.generation == graph.structureGeneration {
            return cached.sliders
        }
        var seen: Set<WasabiObjectID> = []
        var found: [WasabiObject] = []
        func consider(_ object: WasabiObject) {
            if object.tag.is(.slider),
               object.attributes["action"]?.lowercased() == kind.rawValue,
               seen.insert(object.stableID).inserted {
                found.append(object)
            }
            object.children.forEach(consider)
        }
        graph.roots.forEach(consider)
        found += graph.objects(xmlID: kind.legacyID).filter { seen.insert($0.stableID).inserted }
        postedSliderCache[kind] = (graph.structureGeneration, found)
        return found
    }

    /// The engine's EQ on/off or Auto for an `EQ_TOGGLE` / `EQ_AUTO` button, or nil for any other
    /// object. In Winamp every such button *is* that switch, wherever it sits — Anunaki's main,
    /// stick, shade and Party! layouts each carry one.
    func equalizerSwitchState(of object: WasabiObject) -> Bool? {
        guard let eqSwitch = WinampModernEQSwitch.decode(action: object.attributes["action"]),
              let componentHost else { return nil }
        return eqSwitch.isOn(in: componentHost.equalizerSnapshot())
    }

    /// Tell every EQ switch button that disagrees with the engine, after either switch moved. Anunaki
    /// writes its "EQ ON/OFF" readout from the **main** layout's button's `onActivate`, so a click on
    /// the stick layout's own button turned the equalizer on while the readout stayed "EQ OFF". The
    /// clicked button already flipped itself, so it is not told twice.
    func syncEqualizerSwitches() {
        guard let snapshot = componentHost?.equalizerSnapshot() else { return }
        let switches = (enabled: snapshot.enabled, auto: snapshot.auto)
        guard announcedEqualizer.announce(switches: switches) else { return }
        for object in loadedSkin.runtime.graph.allObjectsUnordered
        where object.tag.is(.toggleButton) {
            guard let on = equalizerSwitchState(of: object),
                  (object.attributes["activated"] == "1") != on else { continue }
            _ = object.setAttribute("activated", value: on ? "1" : "0")
            notifyActivated(object, activated: on)
        }
    }

    /// Where a host-bound control stands, 0…1 — the script-side twin of the renderer's
    /// `normalizedValue(of:)`, and deliberately the same four families in the same order, so the
    /// number a skin reads back can never disagree with the thumb that is drawn for it. `nil` for
    /// everything else: a slider with no action, or one bound to a `cfgattrib`, keeps reading the
    /// setting or its own `value` exactly as before.
    func hostBoundValue(of object: WasabiObject) -> CGFloat? {
        switch object.attributes["action"]?.lowercased() {
        case "volume": return CGFloat(host.volume)
        case "seek": return host.duration > 0 ? CGFloat(host.currentTime / host.duration) : 0
        case let action where WinampModernPanAction.matches(action: action):
            return WinampModernPanAction.normalized(balance: host.balance)
        default:
            guard let eq = WinampModernEQAction.decode(action: object.attributes["action"],
                                                       parameter: object.attributes["param"]),
                  let snapshot = componentHost?.equalizerSnapshot() else { return nil }
            return eq.normalizedValue(in: snapshot)
        }
    }

    /// The inverse of `hostBoundValue`: move whatever a host-bound slider drives to a 0…1 position.
    /// A drag and a script's `setPosition` both land here, as both move the slider in Wasabi.
    /// Anunaki's wheel sets the balance with `hidebalance.setPosition(…)`; that stored a private
    /// copy, the balance never moved, and the next `getPosition()` read the host's centre back.
    /// Returns false for a slider that drives nothing in the host.
    @discardableResult
    func driveHost(from object: WasabiObject, normalized: CGFloat) -> Bool {
        let action = object.attributes["action"]
        if let eq = WinampModernEQAction.decode(action: action, parameter: object.attributes["param"]) {
            guard let componentHost else { return false }
            eq.apply(normalized: normalized, to: componentHost)
            refreshEqualizerState()
            return true
        }
        if WinampModernPanAction.matches(action: action) {
            host.balance = WinampModernPanAction.balance(normalized: normalized)
            return true
        }
        switch action?.lowercased() {
        case "seek": host.seek(to: host.duration * normalized)
        case "volume": host.volume = normalized
        default: return false
        }
        return true
    }

    /// A slider's `low…high`. Winamp's default is 0…255, but an `EQ_BAND`/`EQ_PREAMP` slider
    /// defaults to −127…127, the `onEqBandChanged` scale: Tristania's band fill sends the event value
    /// and the slider's own position through one routine that slices its map at `position + 128`, and
    /// multipass declares its EQ fillbars `range="-128,128"` against the slider position. On 0…255 the
    /// first drag pushed Tristania's threshold past 255 and flooded the whole track.
    static func sliderRange(of object: WasabiObject) -> (low: Double, high: Double) {
        let isEqualizer = WinampModernEQAction.decode(action: object.attributes["action"],
                                                      parameter: object.attributes["param"]) != nil
        return (Double(object.attributes["low"] ?? "") ?? (isEqualizer ? -127 : 0),
                Double(object.attributes["high"] ?? "") ?? (isEqualizer ? 127 : 255))
    }

    /// A position in the slider's own `low…high` unit as 0…1 — `sliderPosition`'s inverse.
    static func normalizedSliderPosition(_ position: Int32, of object: WasabiObject) -> CGFloat {
        let (low, high) = sliderRange(of: object)
        guard high != low else { return 0 }
        return CGFloat(max(0, min(1, (Double(position) - low) / (high - low))))
    }

    /// A 0…1 host reading in the slider's **own** `low…high` unit — the conversion the view's
    /// `notePosition` writes with too, so a script that reads a position and one that hears
    /// `onSetPosition` are handed the same number.
    static func sliderPosition(normalized: CGFloat, of object: WasabiObject) -> Int32 {
        let (low, high) = sliderRange(of: object)
        return Int32((low + Double(normalized) * (high - low)).rounded())
    }

    /// A slider position held inside the `low…high` the object declares. Untouched when it declares
    /// neither, so nothing that never stated a range changes behaviour.
    static func clampedSliderPosition(_ value: Int32, of object: WasabiObject) -> Int32 {
        let lowText = object.attributes["low"]
        let highText = object.attributes["high"]
        guard lowText != nil || highText != nil else { return value }
        let low = Int32(lowText ?? "") ?? 0
        let high = Int32(highText ?? "") ?? 255
        guard low <= high else { return value }
        return min(high, max(low, value))
    }
}
