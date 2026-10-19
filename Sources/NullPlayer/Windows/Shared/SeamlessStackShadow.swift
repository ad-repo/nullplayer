import AppKit

/// **One drop shadow per docked stack in a seamless-docking Original skin.** Each window's own would
/// fall along every seam, across its neighbour, so one member casts the union of every member's
/// outline and the rest hide theirs. The main window casts when it is in the stack, else the lowest
/// window number. `WindowManager` supplies the stacks, and casts once per layout change, after every
/// view has taken the new layout, so a member needs no part in it — Stats and Sonos included.
final class SeamlessStackShadow {
    /// The stacks to shadow as one, and the main window. `stacks` is empty when the skin docks with
    /// visible seams, or outside Original mode, which hands every former member its own shadow back.
    struct Layout {
        let stacks: [[NSWindow]]
        let main: NSWindow?
    }

    /// The current layout, or nil while it must stand — mid-move of a stack the drag carries whole.
    private let layout: () -> Layout?
    /// Every window given a stack role last time, so one that leaves its stack casts its own again.
    private let members = NSHashTable<NSWindow>.weakObjects()
    private var isCastScheduled = false

    init(layout: @escaping () -> Layout?) {
        self.layout = layout
    }

    func cast() {
        guard let layout = layout() else { return }
        let previous = members.allObjects
        members.removeAllObjects()
        for stack in layout.stacks {
            let shadowed = stack.filter(\.hasSkinShadow)
            guard let caster = shadowed.first(where: { $0 === layout.main })
                    ?? shadowed.min(by: { $0.windowNumber < $1.windowNumber }) else { continue }
            for window in shadowed {
                window.castSkinShadow(window === caster ? .stack(stack) : .hidden(by: caster))
                members.add(window)
            }
        }
        for window in previous where !members.contains(window) { window.castSkinShadow(.solo) }
    }

    /// **Cast a turn late, once however many moves ask.** A move is reported before it lands, and
    /// one that is no drag — the player carrying its docked children, a snap — posts no layout
    /// change at all. One turn later every frame, AppKit's carried children included, has landed.
    func setNeedsCast() {
        guard !isCastScheduled else { return }
        isCastScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.isCastScheduled = false
            self?.cast()
        }
    }
}
