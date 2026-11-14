import AppKit

/// The engine's own items in the shared visualization menu (`VisualizationContextMenu`), below
/// the presets and cycle every engine shares. The items target the engine, so a host needs no
/// AVS-specific actions.
extension AvsEngine {
    func addMenuItems(to menu: NSMenu) {
        menu.addItem(item("Edit Preset…", #selector(editPresetAction)))
        let beats = NSMenu(title: "Beat Detection")
        for (title, action, advanced) in [("Standard", #selector(standardBeatsAction), false),
                                          ("Advanced (Tracks the Beat)", #selector(advancedBeatsAction), true)] {
            let choice = item(title, action)
            choice.state = AvsPresets.advancedBeatDetection == advanced ? .on : .off
            beats.addItem(choice)
        }
        let beatsItem = NSMenuItem(title: "Beat Detection", action: nil, keyEquivalent: "")
        beatsItem.submenu = beats
        menu.addItem(beatsItem)
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

    @objc private func standardBeatsAction() { AvsPresets.advancedBeatDetection = false }
    @objc private func advancedBeatsAction() { AvsPresets.advancedBeatDetection = true }

    @objc private func choosePresetFolderAction() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder of AVS presets (.avs)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        AvsPresets.customFolderSetting.set(url)
        reloadPresets()
    }

    @objc private func clearPresetFolderAction() {
        AvsPresets.customFolderSetting.set(nil)
        reloadPresets()
    }
}
