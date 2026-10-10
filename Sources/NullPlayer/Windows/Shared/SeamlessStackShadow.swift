import AppKit

/// **One drop shadow per docked stack in a seamless-docking Original skin.** Each window's own would
/// fall along every seam, across its neighbour, so one member casts the union of every member's
/// outline and the rest hide theirs. The main window casts when it is in the stack, else the lowest
/// window number. `WindowManager` hands over the stacks once per layout change, after every view has
/// taken the new layout, so a member needs no part in it — Stats and Sonos included.
final class SeamlessStackShadow {
    /// Every window given a stack role last time, so one that leaves its stack casts its own again.
    private let members = NSHashTable<NSWindow>.weakObjects()

    /// `stacks` are the docked groups to shadow as one; empty when the skin docks with visible
    /// seams, or outside Original mode, which hands every former member its own shadow back.
    func cast(stacks: [[NSWindow]], main: NSWindow?) {
        let previous = members.allObjects
        members.removeAllObjects()
        for stack in stacks {
            let shadowed = stack.filter(\.hasSkinShadow)
            guard let caster = shadowed.first(where: { $0 === main })
                    ?? shadowed.min(by: { $0.windowNumber < $1.windowNumber }) else { continue }
            for window in shadowed {
                window.castSkinShadow(window === caster ? .stack(stack) : .hidden(by: caster))
                members.add(window)
            }
        }
        for window in previous where !members.contains(window) { window.castSkinShadow(.solo) }
    }
}
