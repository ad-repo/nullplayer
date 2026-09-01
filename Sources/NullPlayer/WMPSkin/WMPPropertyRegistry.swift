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
            let value = Self.value(path: binding.path, kind: binding.kind, snapshot: snapshot)
            guard lastValues[binding.address] != value else { continue }
            lastValues[binding.address] = value
            changes.append(.init(address: binding.address, value: value))
        }
        lastAppliedOrigin = origin
        return changes
    }

    private static func value(path raw: String, kind: WMPBindingKind,
                              snapshot: WMPHostSnapshot) -> WMPJSONValue {
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
            default: enabled = false
            }
            return .bool(enabled)
        }
        switch path {
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
        default: return .string("")
        }
    }
}
