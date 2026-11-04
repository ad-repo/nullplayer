import AppKit

// MARK: - AIMP skins actions

extension MenuActions {
    private var aimpController: AIMPSkinMainWindowController? {
        WindowManager.shared.mainWindowController as? AIMPSkinMainWindowController
    }

    @objc func setAIMPMode() {
        guard AppCapabilities.supports(.aimpSkinMode), WindowManager.shared.uiMode != .aimp else { return }
        WindowManager.shared.reloadUI(to: .aimp)
    }

    /// In place inside the family; otherwise the selection is saved and entering the family loads it.
    @objc func selectAIMPSkin(_ sender: NSMenuItem) {
        guard AppCapabilities.supports(.aimpSkinMode), let name = sender.representedObject as? String else { return }
        if let controller = aimpController {
            controller.selectSkin(named: name)
        } else {
            AIMPSkinImporter().selection.select(name)
            WindowManager.shared.reloadUI(to: .aimp)
        }
    }

    @objc func loadAIMPSkinFromFile() {
        guard AppCapabilities.supports(.aimpSkinMode) else { return }
        if let controller = aimpController {
            controller.importSkinFromPanel()
        } else {
            WindowManager.shared.reloadUI(to: .aimp) { [weak self] in self?.aimpController?.importSkinFromPanel() }
        }
    }

    @objc func getMoreAIMPSkins() {
        guard let url = URL(string: "https://www.aimp.ru/?do=catalog&os=windows&type=skins") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc func openAIMPSkinsFolder() {
        let importer = AIMPSkinImporter()
        do {
            try importer.folder.ensureExists()
            NSWorkspace.shared.open(importer.directoryURL)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func removeAIMPSkin(named name: String) {
        Task { @MainActor in
            do {
                try await AIMPSkinImporter().removeSkin(named: name)
                self.aimpController?.resetToUnskinned()
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }
}
