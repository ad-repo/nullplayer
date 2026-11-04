import AppKit

/// A menu item that runs a closure: for a menu built where its actions are (the skin's popups and
/// context menu), without a target object of its own.
final class AIMPSkinMenuItem: NSMenuItem {
    private let run: () -> Void

    init(title: String, run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(runAction), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func runAction() { run() }
}
