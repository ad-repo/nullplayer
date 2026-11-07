import AppKit

/// The engine's own items in the shared visualization menu (`VisualizationContextMenu`), below
/// the presets and cycle every engine shares. The items target the engine, so a host needs no
/// AVS-specific actions.
extension AvsEngine {
    func addMenuItems(to menu: NSMenu) {
        menu.addItem(item("Edit Preset…", #selector(editPresetAction)))
        menu.addItem(item("Choose AVS Preset Folder…", #selector(choosePresetFolderAction)))
        if AvsPresets.customFolder != nil {
            menu.addItem(item("Use Bundled AVS Presets Only", #selector(clearPresetFolderAction)))
        }
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func editPresetAction() { AvsEditorWindowController.show(for: self) }

    @objc private func choosePresetFolderAction() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder of AVS presets (.avs)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        AvsPresets.customFolder = url.path
        reloadPresets()
    }

    @objc private func clearPresetFolderAction() {
        AvsPresets.customFolder = nil
        reloadPresets()
    }
}
