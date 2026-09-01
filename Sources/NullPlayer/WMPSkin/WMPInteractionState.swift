import Foundation

enum WMPVisualInteractionState: String, Codable { case normal, hover, down, disabled }

struct WMPInteractionState: Equatable {
    private(set) var hoveredNode: Int?
    private(set) var pressedNode: Int?
    private(set) var capturedNode: Int?
    private(set) var focusedNode: Int?
    private(set) var stickyDownNodes: Set<Int> = []
    private(set) var disabledNodes: Set<Int> = []
    var disabledNodesForScene: Set<Int> { disabledNodes }

    mutating func move(over target: WMPHitTarget?) -> Set<Int> {
        transition(\Self.hoveredNode, to: target?.stableID)
    }

    mutating func press(_ target: WMPHitTarget?) -> Set<Int> {
        guard let target, target.enabled, !disabledNodes.contains(target.stableID) else { return [] }
        var changed = transition(\Self.pressedNode, to: target.stableID)
        changed.formUnion(transition(\Self.capturedNode, to: target.stableID))
        changed.formUnion(transition(\Self.focusedNode, to: target.stableID))
        return changed
    }

    mutating func release(over target: WMPHitTarget?) -> (changed: Set<Int>, activated: Int?) {
        let captured = capturedNode
        let activate = captured != nil && target?.stableID == captured && !disabledNodes.contains(captured!)
            ? captured : nil
        var changed = transition(\Self.pressedNode, to: nil)
        changed.formUnion(transition(\Self.capturedNode, to: nil))
        if let activate, target?.sticky == true {
            if stickyDownNodes.contains(activate) { stickyDownNodes.remove(activate) }
            else { stickyDownNodes.insert(activate) }
            changed.insert(activate)
        }
        return (changed, activate)
    }

    mutating func cancelCapture() -> Set<Int> {
        var changed = transition(\Self.pressedNode, to: nil)
        changed.formUnion(transition(\Self.capturedNode, to: nil))
        return changed
    }

    mutating func setDisabled(_ disabled: Bool, node: Int) -> Set<Int> {
        let changed = disabled ? disabledNodes.insert(node).inserted : disabledNodes.remove(node) != nil
        if disabled, capturedNode == node { _ = cancelCapture() }
        return changed ? [node] : []
    }

    mutating func setStickyDown(_ down: Bool, node: Int) -> Set<Int> {
        let changed = down ? stickyDownNodes.insert(node).inserted : stickyDownNodes.remove(node) != nil
        return changed ? [node] : []
    }

    func visualState(for node: Int) -> WMPVisualInteractionState {
        if disabledNodes.contains(node) { return .disabled }
        if pressedNode == node || stickyDownNodes.contains(node) { return .down }
        if hoveredNode == node { return .hover }
        return .normal
    }

    private mutating func transition(_ keyPath: WritableKeyPath<Self, Int?>, to value: Int?) -> Set<Int> {
        let old = self[keyPath: keyPath]
        guard old != value else { return [] }
        self[keyPath: keyPath] = value
        return Set([old, value].compactMap { $0 })
    }
}
