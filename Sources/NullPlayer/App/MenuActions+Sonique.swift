import AppKit

// MARK: - Sonique skins actions

/// The Skins menu's Sonique entries; all but Mode and Get More are `SingleCanvasMainWindow`'s.
@MainActor
extension MenuActions {
    private var soniqueController: SoniqueSkinMainWindowController? {
        WindowManager.shared.mainWindowController as? SoniqueSkinMainWindowController
    }

    @objc func setSoniqueMode() { SoniqueSkinMainWindowController.switchToFamily() }

    @objc func selectSoniqueSkin(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        SoniqueSkinMainWindowController.chooseSkin(named: name)
    }

    @objc func setSoniqueWindowMode(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String, let mode = SoniqueSkin.Mode(rawValue: name) else { return }
        soniqueController?.mode = mode
    }

    @objc func loadSoniqueSkinFromFile() { SoniqueSkinMainWindowController.loadSkinFromFile() }

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

    @objc func openSoniqueSkinsFolder() { SoniqueSkinMainWindowController.openSkinsFolder() }

    func removeSoniqueSkin(named name: String) { SoniqueSkinMainWindowController.removeInstalledSkin(named: name) }
}
