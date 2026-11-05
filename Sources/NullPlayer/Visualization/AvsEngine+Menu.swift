import AppKit

/// The engine's own section of the shared visualization menu (`VisualizationContextMenu`). The
/// items target the engine, so a host needs no AVS-specific actions.
extension AvsEngine {
    func addMenuItems(to menu: NSMenu) {
        let current = NSMenuItem(title: "Preset: \(currentPresetName ?? "(none)")", action: nil, keyEquivalent: "")
        current.isEnabled = false
        menu.addItem(current)
        menu.addItem(.separator())
        menu.addItem(item("Next Preset", #selector(nextPresetAction)))
        menu.addItem(item("Previous Preset", #selector(previousPresetAction)))
        menu.addItem(item("Random Preset", #selector(randomPresetAction)))

        let list = NSMenu()
        for (index, url) in presets.enumerated() {
            let entry = item(url.deletingPathExtension().lastPathComponent, #selector(choosePresetAction(_:)))
            entry.tag = index
            entry.state = index == currentIndex ? .on : .off
            list.addItem(entry)
        }
        let listItem = NSMenuItem(title: "Presets", action: nil, keyEquivalent: "")
        listItem.submenu = list
        menu.addItem(listItem)
        menu.addItem(.separator())

        for (title, mode) in [("Hold Preset", VisualizationCycleMode.off), ("Auto-Cycle", .cycle), ("Auto-Random", .random)] {
            let entry = item(title, #selector(setCycleModeAction(_:)))
            entry.representedObject = mode.rawValue
            entry.state = AvsPresets.cycleMode == mode ? .on : .off
            menu.addItem(entry)
        }
        let intervals = NSMenu()
        for seconds in AvsPresets.cycleIntervals {
            let title = seconds < 60 ? "\(Int(seconds)) seconds" : "\(Int(seconds / 60)) minute\(seconds > 60 ? "s" : "")"
            let entry = item(title, #selector(setCycleIntervalAction(_:)))
            entry.tag = Int(seconds)
            entry.state = AvsPresets.cycleInterval == seconds ? .on : .off
            intervals.addItem(entry)
        }
        let intervalItem = NSMenuItem(title: "Cycle Interval", action: nil, keyEquivalent: "")
        intervalItem.submenu = intervals
        menu.addItem(intervalItem)
        menu.addItem(.separator())

        menu.addItem(item("Edit Preset…", #selector(editPresetAction)))
        menu.addItem(item("Choose AVS Preset Folder…", #selector(choosePresetFolderAction)))
        if AvsPresets.customFolder != nil {
            menu.addItem(item("Use Bundled AVS Presets Only", #selector(clearPresetFolderAction)))
        }
        menu.addItem(.separator())
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func nextPresetAction() { step(by: 1) }
    @objc private func previousPresetAction() { step(by: -1) }
    @objc private func randomPresetAction() { selectRandomPreset() }
    @objc private func choosePresetAction(_ sender: NSMenuItem) { selectPreset(at: sender.tag) }

    @objc private func setCycleModeAction(_ sender: NSMenuItem) {
        guard let mode = (sender.representedObject as? String).flatMap(VisualizationCycleMode.init) else { return }
        setCycleMode(mode)
    }

    @objc private func setCycleIntervalAction(_ sender: NSMenuItem) {
        AvsPresets.cycleInterval = TimeInterval(sender.tag)
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
