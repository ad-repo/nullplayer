import AppKit

enum ReeltoneMenuBuilder {
    static let placeholderSkinIdentity = "phase1.original-placeholder"

    static func buildModeMenuItem(activeMode: PlayerUIMode) -> NSMenuItem {
        let parent = NSMenuItem(title: PlayerUIMode.reeltone.displayName, action: nil, keyEquivalent: "")
        let menu = NSMenu()
        menu.autoenablesItems = false

        if activeMode != .reeltone {
            let switchItem = NSMenuItem(
                title: "Switch to Reeltone",
                action: #selector(ReeltoneMenuActions.setReeltoneMode),
                keyEquivalent: ""
            )
            switchItem.target = ReeltoneMenuActions.shared
            menu.addItem(switchItem)
            menu.addItem(.separator())
        }

        let placeholder = NSMenuItem(
            title: "Original Placeholder",
            action: #selector(ReeltoneMenuActions.selectPlaceholderSkin),
            keyEquivalent: ""
        )
        placeholder.target = ReeltoneMenuActions.shared
        if activeMode == .reeltone,
           ReeltoneSkinState.selectedSkinIdentity() == placeholderSkinIdentity {
            placeholder.state = .on
        }
        menu.addItem(placeholder)

        menu.addItem(.separator())
        let importItem = NSMenuItem(title: "Import Reeltone Skin…", action: nil, keyEquivalent: "")
        importItem.isEnabled = false
        importItem.toolTip = "Secure Reeltone archive import is added in Phase 2."
        menu.addItem(importItem)

        parent.state = activeMode == .reeltone ? .on : .off
        parent.submenu = menu
        return parent
    }
}

final class ReeltoneMenuActions: NSObject {
    static let shared = ReeltoneMenuActions()

    @objc func setReeltoneMode() {
        selectPlaceholderSkin()
    }

    @objc func selectPlaceholderSkin() {
        ReeltoneSkinState.selectSkin(identity: ReeltoneMenuBuilder.placeholderSkinIdentity)
        let windowManager = WindowManager.shared
        if windowManager.uiMode != .reeltone {
            windowManager.reloadUI(to: .reeltone)
        }
    }
}
