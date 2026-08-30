import AppKit

enum ReeltoneMenuBuilder {
    static func buildModeMenuItem(
        activeMode: PlayerUIMode,
        discovery: ReeltoneDiscoveryResult? = nil,
        selectedIdentity: String? = ReeltoneSkinState.selectedSkinIdentity()
    ) -> NSMenuItem {
        let engine = ReeltoneSkinEngine.shared
        let result = discovery ?? engine.availableSkins
        let selected = selectedIdentity
        let parent = NSMenuItem(title: PlayerUIMode.reeltone.displayName, action: nil, keyEquivalent: "")
        let menu = NSMenu()
        menu.autoenablesItems = false

        if activeMode != .reeltone {
            let switchItem = NSMenuItem(
                title: "Switch to Reeltone" + (engine.currentInstallation.map { " (\($0.record.name))" } ?? ""),
                action: #selector(ReeltoneMenuActions.setReeltoneMode),
                keyEquivalent: ""
            )
            switchItem.target = ReeltoneMenuActions.shared
            menu.addItem(switchItem)
            menu.addItem(.separator())
        }

        let importItem = NSMenuItem(
            title: "Import Reeltone Skin…",
            action: #selector(ReeltoneMenuActions.importSkin),
            keyEquivalent: ""
        )
        importItem.target = ReeltoneMenuActions.shared
        menu.addItem(importItem)
        menu.addItem(.separator())

        let defaultItem = NSMenuItem(
            title: "Default Reeltone Theme",
            action: #selector(ReeltoneMenuActions.selectDefaultTheme),
            keyEquivalent: ""
        )
        defaultItem.target = ReeltoneMenuActions.shared
        if activeMode == .reeltone, selected == nil { defaultItem.state = .on }
        menu.addItem(defaultItem)

        if result.installations.isEmpty {
            let emptyItem = NSMenuItem(title: "No Reeltone skins installed", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for installation in result.installations {
                let item = NSMenuItem(
                    title: installation.record.name,
                    action: #selector(ReeltoneMenuActions.selectInstalledSkin(_:)),
                    keyEquivalent: ""
                )
                item.target = ReeltoneMenuActions.shared
                item.representedObject = installation.record.identity
                if activeMode == .reeltone, selected == installation.record.identity { item.state = .on }
                menu.addItem(item)
            }
        }

        if !result.diagnostics.isEmpty {
            menu.addItem(.separator())
            let diagnostics = NSMenuItem(
                title: "\(result.diagnostics.count) invalid installation\(result.diagnostics.count == 1 ? "" : "s") ignored",
                action: nil,
                keyEquivalent: ""
            )
            diagnostics.isEnabled = false
            menu.addItem(diagnostics)
        }

        parent.state = activeMode == .reeltone ? .on : .off
        parent.submenu = menu
        return parent
    }
}

final class ReeltoneMenuActions: NSObject {
    static let shared = ReeltoneMenuActions()

    @objc func setReeltoneMode() {
        switchToReeltoneIfNeeded()
    }

    @objc func importSkin() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.init(filenameExtension: "reeltone")!]
        panel.message = "Select a .reeltone skin archive"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            _ = try ReeltoneSkinEngine.shared.installAndSelect(archiveAt: url)
            applySelection()
        } catch {
            presentFailure(title: "Failed to Import Reeltone Skin", error: error)
        }
    }

    @objc func selectInstalledSkin(_ sender: NSMenuItem) {
        guard let identity = sender.representedObject as? String else { return }
        do {
            _ = try ReeltoneSkinEngine.shared.select(identity: identity)
            applySelection()
        } catch {
            presentFailure(title: "Failed to Load Reeltone Skin", error: error)
        }
    }

    @objc func selectDefaultTheme() {
        ReeltoneSkinEngine.shared.selectDefaultTheme()
        applySelection()
    }

    private func applySelection() {
        let windowManager = WindowManager.shared
        if windowManager.uiMode == .reeltone {
            ReeltoneThemeRuntime.activateCurrentTheme()
            (NSApp.delegate as? AppDelegate)?.rebuildMainMenu()
        } else {
            switchToReeltoneIfNeeded()
        }
    }

    private func switchToReeltoneIfNeeded() {
        let windowManager = WindowManager.shared
        guard windowManager.uiMode != .reeltone else { return }
        windowManager.reloadUI(to: .reeltone)
    }

    private func presentFailure(title: String, error: Error) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}
