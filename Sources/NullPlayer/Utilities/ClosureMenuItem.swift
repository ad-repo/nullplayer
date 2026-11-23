import AppKit

/// A menu item that runs a closure when chosen: for a menu built where its actions are, with no
/// long-lived target object of its own. `NSMenuItem.target` is weak, so the item is its own target.
final class ClosureMenuItem: NSMenuItem {
    private let run: @MainActor () -> Void

    init(title: String, run: @escaping @MainActor () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(runAction), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Not `perform(_:)`: that name resolves to NSObject's `performSelector:` (`TrackVerbTests`).
    @MainActor @objc private func runAction() { run() }
}
