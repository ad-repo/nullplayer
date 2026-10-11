import AVFoundation

/// One effect's nodes: the local graph's, and one per AudioStreaming player — each player runs its
/// own AVAudioEngine, and a node belongs to one engine. Streaming nodes are held weakly so a retired
/// crossfade player is not kept alive. Every node is made here and configured as it is made, so its
/// unit is always a `Unit`.
final class AudioUnitFanout<Unit: AUAudioUnit> {
    private final class WeakNode {
        weak var node: AVAudioUnitEffect?
        init(_ node: AVAudioUnitEffect) { self.node = node }
    }

    private(set) var localNode: AVAudioUnitEffect
    private var streams: [WeakNode] = []
    private let makeNode: () -> AVAudioUnitEffect
    private let configure: (Unit) -> Void

    init(makeNode: @escaping () -> AVAudioUnitEffect, configure: @escaping (Unit) -> Void) {
        self.makeNode = makeNode
        self.configure = configure
        localNode = makeNode()
        configure(Self.unit(of: localNode))
    }

    /// A fresh local node, for a replacement graph that reuses none of the failed one's units.
    func replaceLocalNode() {
        localNode = makeNode()
        configure(Self.unit(of: localNode))
    }

    func makeStreamingNode() -> AVAudioUnitEffect {
        let node = makeNode()
        streams.removeAll { $0.node == nil }
        streams.append(WeakNode(node))
        configure(Self.unit(of: node))
        return node
    }

    /// Run `configure` again on every live node, after the state it reads changed.
    func configureAll() {
        configure(Self.unit(of: localNode))
        streams.removeAll { $0.node == nil }
        for entry in streams {
            if let node = entry.node { configure(Self.unit(of: node)) }
        }
    }

    private static func unit(of node: AVAudioUnitEffect) -> Unit { node.auAudioUnit as! Unit }
}
