import AppKit

/// What the Skins menu does for a family whose skins are installed by name and loaded by a
/// `SingleCanvasMainWindow` (Audion, Sonique): switch to it, choose an installed skin, load one from a
/// file, open its folder, remove one. Each family's `MenuActions` entry points call these, so its menu
/// keeps its own selectors.
@MainActor
extension SingleCanvasMainWindow {
    private static var shown: Self? { WindowManager.shared.mainWindowController as? Self }

    static func switchToFamily() {
        guard AppCapabilities.supports(feature), WindowManager.shared.uiMode != mode else { return }
        WindowManager.shared.reloadUI(to: mode)
    }

    /// In place inside the family; otherwise the selection is saved and entering the family loads it.
    static func chooseSkin(named name: String) {
        guard AppCapabilities.supports(feature) else { return }
        if let shown {
            shown.selectSkin(named: name)
        } else {
            importer().selection.select(name)
            WindowManager.shared.reloadUI(to: mode)
        }
    }

    static func loadSkinFromFile() {
        guard AppCapabilities.supports(feature) else { return }
        if let shown {
            shown.importFromPanel()
        } else {
            WindowManager.shared.reloadUI(to: mode) { shown?.importFromPanel() }
        }
    }

    static func openSkinsFolder() {
        do {
            let folder = importer().folder
            try folder.ensureExists()
            NSWorkspace.shared.open(folder.url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    static func removeInstalledSkin(named name: String) {
        Task { @MainActor in
            do {
                try await importer().removeSkin(named: name)
                shown?.resetToUnskinned()
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }
}

extension AudionFaceMainWindowController {
    static let mode = PlayerUIMode.audion
    static let feature = AppFeature.audionFaceMode
    static func importer() -> AudionFaceImporter { AudionFaceImporter() }
}

extension SoniqueSkinMainWindowController {
    static let mode = PlayerUIMode.sonique
    static let feature = AppFeature.soniqueSkinMode
    static func importer() -> SoniqueSkinImporter { SoniqueSkinImporter() }
}

extension AudionFaceImporter: SkinFileImporting {
    func removeSkin(named name: String) async throws { try await removeFace(named: name) }
}
