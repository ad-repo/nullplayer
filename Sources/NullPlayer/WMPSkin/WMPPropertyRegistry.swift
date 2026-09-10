import Foundation

struct WMPPropertyTransactionOrigin: Hashable, Sendable { let id: UUID }

struct WMPBoundPropertyChange: Hashable, Sendable {
    let address: WMPScenePropertyAddress
    let value: WMPJSONValue
}

/// One registry owns both wmpprop: and wmpenabled:. Snapshot updates are coalesced into a single
/// transaction and an echoed origin is ignored to prevent script/host feedback loops.
struct WMPObservablePropertyRegistry: @unchecked Sendable {
    private struct Binding {
        let address: WMPScenePropertyAddress
        let kind: WMPBindingKind
        let path: String
    }
    private let bindings: [Binding]
    private var lastValues: [WMPScenePropertyAddress: WMPJSONValue] = [:]
    private var lastAppliedOrigin: WMPPropertyTransactionOrigin?

    init(graph: WMPObjectGraph) {
        bindings = graph.allNodes.flatMap { node -> [Binding] in
            let authored = node.attributes.compactMap { attribute -> Binding? in
                guard case let .binding(kind, path) = attribute.value else { return nil }
                return Binding(address: .init(stableID: node.stableID,
                    property: attribute.name.lowercased()), kind: kind, path: path)
            }
            return authored + Self.implicit(for: node, authored: authored)
        }
    }

    /// **A semantic slider tag is itself a binding, and this is where it becomes one.**
    ///
    /// `<SLIDER value="wmpprop:player.settings.balance">` says where the control reads; a
    /// `<BALANCESLIDER>` says the same thing by being one, which is why a skin that uses the tag
    /// authors no `value` at all. Measured over the 180-archive corpus: **`BALANCESLIDER` is 16
    /// uses across 16 skins and exactly one of them authors a `value`; `VOLUMESLIDER` is 31 / 23
    /// and none do; `SEEKSLIDER` is 18 / 15 and none do.** With no binding to resolve, every one of
    /// them fell to `WMPSceneBuilder.sliderMetrics`'s last resort — *the value of a slider nobody
    /// has told anything is its own minimum* — so 15 of the 16 balance sliders in the corpus drew
    /// their thumb hard left and stayed there, reported as "balance is fully to the left by default
    /// on all skins". Volume drew empty and seek drew at zero for the same reason; balance is the
    /// one where the wrong end of the track *means* something.
    ///
    /// Both halves of the seek slider are synthesized, because the position WMP puts on it is in
    /// seconds and the length of the track is what the far end of it stands for. The ranges are the
    /// other half of the same statement and live in `sliderMetrics`, where a slider's other WMP
    /// defaults already are.
    private static func implicit(for node: WMPNode, authored: [Binding]) -> [Binding] {
        guard let paths = implicitPaths[node.kind] ?? positionSliderPaths(for: node) else { return [] }
        return paths.compactMap { property, path in
            // An authored attribute always wins — one corpus `<BALANCESLIDER>` does author its
            // own `value`, and a skin that states something has not asked for WMP's default.
            guard node.attribute(named: property) == nil,
                  !authored.contains(where: { $0.address.property == property }) else { return nil }
            return Binding(address: .init(stableID: node.stableID, property: property),
                           kind: .property, path: path)
        }
    }

    /// **A slider whose maximum is the media's duration is a position control, and WMP does not
    /// make a skin say so twice (W120).** `<CUSTOMSLIDER id="seek" min="0"
    /// max="wmpprop:player.currentMedia.duration" image="seek.png" positionImage="seek_map.png">`
    /// is the corpus's own seek bar — **73 of them across 61 of the 177 measurable archives author
    /// exactly that and no `value` at all**, 58 as `<CUSTOMSLIDER>` and 15 as `<SLIDER>`, and
    /// nothing in any of those skins' scripts ever writes the value either. W118 synthesized the
    /// binding for the `<SEEKSLIDER>` *tag*; this is the same statement made by the declared
    /// **range** instead, which is how the Plus!, Xbox, Alienware, BlueCrush, Halo and Catwoman
    /// families all write it. Without it the filmstrip stayed on frame 0 for the length of the
    /// track — `Catwoman/mainView` drew `seek.png crop=0,0` at 42 seconds into 137 — and every
    /// readout the skin chains off that value went with it: Catwoman's clock is four digit strips
    /// positioned by `value_onchange="drawSeekDigits(value)"`, so a value that never moves is a
    /// clock that never moves. Reported as "the clock does not work and seek does not work".
    ///
    /// The range is the evidence and the tag is not, so this applies to any slider kind: a skin
    /// that has told the control its far end is the end of the track has said what the control is.
    /// An authored `value` still wins, which is what the 112 sliders that state their own rely on.
    private static func positionSliderPaths(for node: WMPNode) -> [(String, String)]? {
        guard isSlider(node.kind), boundsMaximumToDuration(node) else { return nil }
        return [("value", "player.controls.currentPosition")]
    }

    private static func isSlider(_ kind: WMPElementKind) -> Bool {
        switch kind {
        case .slider, .seekSlider, .customSlider, .progressBar: return true
        default: return false
        }
    }

    private static func boundsMaximumToDuration(_ node: WMPNode) -> Bool {
        ["max", "maxValue"].contains {
            guard let attribute = node.attribute(named: $0),
                  case let .binding(kind, path) = attribute.value, kind == .property else { return false }
            return path.trimmingCharacters(in: .whitespaces).lowercased() == "player.currentmedia.duration"
        }
    }

    private static let implicitPaths: [WMPElementKind: [(String, String)]] = [
        .volumeSlider: [("value", "player.settings.volume")],
        .balanceSlider: [("value", "player.settings.balance")],
        .seekSlider: [("value", "player.controls.currentPosition"),
                      ("max", "player.currentMedia.duration")]
    ]

    mutating func changes(for snapshot: WMPHostSnapshot, origin: WMPPropertyTransactionOrigin? = nil)
        -> [WMPBoundPropertyChange] {
        if origin != nil && origin == lastAppliedOrigin { return [] }
        var changes: [WMPBoundPropertyChange] = []
        for binding in bindings {
            // **On `visible`, a path this engine cannot answer is not the answer "false".** `WoW`
            // authors `<PLAYLIST id="playlist1" visible="wmpprop:plMode.visible">`, and `plMode` is
            // not one of its elements — the skin is written against a name WMP's own object model
            // owns. Resolving that to the empty string committed a falsy `visible` override, and
            // the builder deletes a node whose `visible` override is false: the playlist control,
            // its rows and its widget were gone, so the playlist read empty however many tracks
            // were queued. Reported live as "adding to the playlist does not work".
            //
            // **The empty string stands for every other property**, deliberately. It is the honest
            // answer where the value is *content* — a `value="wmpprop:eq.currentPresetTitle"`
            // readout blanks rather than showing the authored placeholder for ever — and on
            // `enabled` a control this engine cannot drive should look disabled, which is what
            // `wmpenabled:` and `enabled="wmpprop:eq.enhancedAudio"` (101 uses across 33 skins)
            // have always done. Only `visible` destroys content by defaulting, so only `visible`
            // declines to.
            let resolved = Self.value(path: binding.path, kind: binding.kind, snapshot: snapshot)
            guard let value = resolved ?? Self.unansweredValue(for: binding) else { continue }
            guard lastValues[binding.address] != value else { continue }
            lastValues[binding.address] = value
            changes.append(.init(address: binding.address, value: value))
        }
        lastAppliedOrigin = origin
        return changes
    }

    /// The roots WMP's *host* object model owns. A `wmpprop:` path starting with one of these names
    /// a player property; anything else names an element in the skin's own graph — `plMode`,
    /// `mainModeVis`, `plCopySub` — which is a different kind of unanswerable and gets a different
    /// default. Both spellings of the same idea appear in the corpus, so this is matched on the
    /// first segment only.
    private static let hostRoots: Set<String> = [
        "player", "eq", "theme", "vidset", "mediacenter", "viseffects", "network", "settings",
        "controls", "wmpprop"
    ]

    /// What an unanswerable binding commits, or `nil` to commit nothing and leave the markup's own
    /// value standing. See `changes(for:)`.
    ///
    /// **A host property this engine does not implement is genuinely off**, and saying so is
    /// honest: `xsn_sports` hangs its whole SRS WOW panel off `visible="wmpprop:eq.enhancedAudio"`,
    /// and this player has no SRS WOW, so showing the "SRS ON" badge would claim a feature that
    /// does nothing. **An element this skin never declared is not off — it is unknown**, and that
    /// is where defaulting destroys content: `WoW`'s playlist hangs off `wmpprop:plMode.visible`,
    /// a name WMP's own UI owns.
    private static func unansweredValue(for binding: Binding) -> WMPJSONValue? {
        if binding.kind == .enabled { return .bool(false) }
        guard binding.address.property == "visible" else { return .string("") }
        let root = binding.path.split(separator: ".").first.map { $0.lowercased() } ?? ""
        return hostRoots.contains(root) ? .string("") : nil
    }

    /// The host value a binding resolves to, or `nil` when this engine does not know the path — see
    /// `changes(for:)` for why the difference matters.
    private static func value(path raw: String, kind: WMPBindingKind,
                              snapshot: WMPHostSnapshot) -> WMPJSONValue? {
        let path = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if kind == .enabled {
            let enabled: Bool
            switch path {
            case "player.controls.play": enabled = snapshot.isEnabled(.play)
            case "player.controls.pause": enabled = snapshot.isEnabled(.pause)
            case "player.controls.stop": enabled = snapshot.isEnabled(.stop)
            case "player.controls.previous": enabled = snapshot.isEnabled(.previous)
            case "player.controls.next": enabled = snapshot.isEnabled(.next)
            case "player.controls.currentposition": enabled = snapshot.isEnabled(.seek)
            default: return nil
            }
            return .bool(enabled)
        }
        // The equaliser a `.wmz` shows is its own ten bound sliders, so these paths are what put a
        // thumb where the engine's gain actually is. 164 corpus skins author them.
        if let band = WMPTransportAction.eqBand(in: path) {
            return .number(snapshot.equalizer.gains.indices.contains(band) ? snapshot.equalizer.gains[band] : 0)
        }
        switch path {
        case "eq.enabled", "eq.enable": return .bool(snapshot.equalizer.enabled)
        case "eq.preamp": return .number(snapshot.equalizer.preamp)
        case "player.controls.currentposition": return .number(snapshot.currentTime)
        case "player.controls.currentpositionstring": return .string(snapshot.elapsedText)
        case "player.currentmedia.duration": return .number(snapshot.duration)
        case "player.currentmedia.imagesourcewidth": return .number(snapshot.video.width)
        case "player.currentmedia.imagesourceheight": return .number(snapshot.video.height)
        case "player.currentmedia.durationstring": return .string(snapshot.durationText)
        case "player.currentmedia.name", "player.currentmedia.getiteminfo('title')": return .string(snapshot.metadata.title)
        case "player.settings.volume": return .number(snapshot.volume * 100)
        case "player.settings.balance": return .number(snapshot.balance * 100)
        case "player.settings.mute": return .bool(snapshot.muted)
        case "player.currentplaylist.count": return .number(Double(snapshot.playlistCount))
        case "player.playstate": return .string(snapshot.state.rawValue)
        // 41 skins bind a seek bar's `foregroundProgress` to one of these, which is how a `.wmz`
        // draws its buffer bar. Both names appear; WMP scales them 0-100.
        case "player.network.downloadprogress", "player.network.bufferingprogress":
            return .number(snapshot.bufferingProgress)
        // 68 archives bind their `<EFFECTS>` rect's `currentEffectType` and `currentPreset` to
        // these two paths — the corpus's own selector for what the surface draws (W101).
        case "mediacenter.effecttype": return .string(snapshot.effects.type)
        case "mediacenter.effectpreset": return .number(Double(snapshot.effects.preset))
        default: return nil
        }
    }
}
