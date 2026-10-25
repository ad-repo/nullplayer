import AppKit

// MARK: - Sonique skins actions

extension MenuActions {
    private var soniqueController: SoniqueSkinMainWindowController? {
        WindowManager.shared.mainWindowController as? SoniqueSkinMainWindowController
    }

    @objc func setSoniqueMode() {
        guard AppCapabilities.supports(.soniqueSkinMode), WindowManager.shared.uiMode != .sonique else { return }
        WindowManager.shared.reloadUI(to: .sonique)
    }

    /// In place inside the family; otherwise the selection is saved and entering the family loads it.
    @objc func selectSoniqueSkin(_ sender: NSMenuItem) {
        guard AppCapabilities.supports(.soniqueSkinMode), let name = sender.representedObject as? String else { return }
        if let controller = soniqueController {
            controller.selectSkin(named: name)
        } else {
            SoniqueSkinImporter().selection.select(name)
            WindowManager.shared.reloadUI(to: .sonique)
        }
    }

    @objc func setSoniqueWindowMode(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String, let mode = SoniqueSkin.Mode(rawValue: name) else { return }
        soniqueController?.mode = mode
    }

    @objc func loadSoniqueSkinFromFile() {
        guard AppCapabilities.supports(.soniqueSkinMode) else { return }
        if let controller = soniqueController {
            controller.importSkinFromPanel()
        } else {
            WindowManager.shared.reloadUI(to: .sonique) { [weak self] in self?.soniqueController?.importSkinFromPanel() }
        }
    }

    /// The Internet Archive's Sonique Media Player collection, after saying how to get the big archive
    /// on it: the page's torrent file, which pulls the whole thing far more reliably than the browser.
    @objc func getMoreSoniqueSkins() {
        guard let url = URL(string: "https://archive.org/details/sonique_media_player") else { return }
        let alert = NSAlert()
        alert.messageText = "Get More Sonique Skins"
        alert.informativeText = "This opens the Internet Archive's Sonique collection. For the large skin archive, "
            + "download it with the torrent file on that page.\n\n"
            + "Only the skins work with NullPlayer; Sonique's plugins are not supported."
        alert.addButton(withTitle: "Open Page")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        NSWorkspace.shared.open(url)
    }

    @objc func openSoniqueSkinsFolder() {
        let importer = SoniqueSkinImporter()
        do {
            try importer.folder.ensureExists()
            NSWorkspace.shared.open(importer.directoryURL)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func removeSoniqueSkin(named name: String) {
        Task { @MainActor in
            do {
                try await SoniqueSkinImporter().removeSkin(named: name)
                self.soniqueController?.resetToUnskinned()
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }
}
