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
        bindings = graph.allNodes.flatMap { node in
            node.attributes.compactMap { attribute in
                guard case let .binding(kind, path) = attribute.value else { return nil }
                return Binding(address: .init(stableID: node.stableID,
                    property: attribute.name.lowercased()), kind: kind, path: path)
            }
        }
    }

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
