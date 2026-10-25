import Foundation

struct WMPInstalledSkin: Hashable {
    let name: String
    let url: URL
}

enum WMPSkinImportError: LocalizedError {
    case unsupportedExtension(String)
    case invalidFilename
    case selectionMissing(String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedExtension(ext):
            return "Expected a .wmz Windows Media Player skin, got .\(ext)."
        case .invalidFilename:
            return "The skin filename is empty or invalid."
        case let .selectionMissing(name):
            return "The selected Windows Media Player skin '\(name)' is no longer installed. Import it again or choose another skin."
        }
    }
}

/// WMP's installed-archives folder and selection preference. Import validates the complete hostile
/// archive before any destination is touched, and again as the copy that is committed
/// (`SkinInstallFolder`).
struct WMPSkinImporter {
    static let selectedSkinNameKey = "wmpSkinName"
    static let selectedViewIDKey = "wmpSkinViewID"

    let folder: SkinInstallFolder
    let selection: SkinSelection
    let defaults: UserDefaults
    let loader: WMPSkinLoader
    var directoryURL: URL { folder.url }
    private var fileManager: FileManager { folder.fileManager }

    init(
        directoryURL: URL? = nil,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        loader: WMPSkinLoader = WMPSkinLoader()
    ) {
        self.defaults = defaults
        selection = SkinSelection(key: Self.selectedSkinNameKey, defaults: defaults)
        self.loader = loader
        folder = SkinInstallFolder("WMPSkins", at: directoryURL, fileManager: fileManager)
    }

    var selectedViewID: String? {
        defaults.string(forKey: Self.selectedViewIDKey)
    }

    func installedSkins() -> [WMPInstalledSkin] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return urls.compactMap { url in
            guard url.pathExtension.caseInsensitiveCompare("wmz") == .orderedSame,
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) != false else { return nil }
            return WMPInstalledSkin(name: url.deletingPathExtension().lastPathComponent, url: url)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func selectedSkinURL() throws -> URL? {
        guard let name = selection.name, !name.isEmpty else { return nil }
        guard let installed = installedSkins().first(where: {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) else { throw WMPSkinImportError.selectionMissing(name) }
        return installed.url
    }

    @discardableResult
    func importSkin(from sourceURL: URL) async throws -> WMPInstalledSkin {
        let ext = sourceURL.pathExtension.lowercased()
        guard ext == "wmz" else {
            throw WMPSkinImportError.unsupportedExtension(ext.isEmpty ? "(none)" : ext)
        }
        let name = sourceURL.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != ".", name != ".." else { throw WMPSkinImportError.invalidFilename }

        let installed = try await Task.detached(priority: .userInitiated) { [folder, loader] in
            // Keep validation, directory enumeration, archive copy, and atomic commit away from
            // MainActor even when an AppKit controller initiated the import.
            _ = try await loader.load(from: sourceURL)
            try folder.ensureExists()
            let directoryURL = folder.url, fileManager = folder.fileManager
            let urls = try fileManager.contentsOfDirectory(
                at: directoryURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            let existing = urls.first {
                $0.pathExtension.caseInsensitiveCompare("wmz") == .orderedSame
                    && $0.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(name) == .orderedSame
            }
            let destination = existing
                ?? directoryURL.appendingPathComponent(name).appendingPathExtension("wmz")
            if sourceURL.standardizedFileURL == destination.standardizedFileURL {
                return WMPInstalledSkin(name: name, url: destination)
            }

            try await folder.commit(sourceURL, to: destination, suffix: ".wmz") { _ = try await loader.load(from: $0) }
            return WMPInstalledSkin(name: name, url: destination)
        }.value
        selection.select(name)
        return installed
    }

    func select(_ skin: WMPInstalledSkin, viewID: String? = nil) {
        selection.select(skin.name)
        if let viewID, !viewID.isEmpty {
            defaults.set(viewID, forKey: Self.selectedViewIDKey)
        } else {
            defaults.removeObject(forKey: Self.selectedViewIDKey)
        }
    }

    func resetSelection() {
        selection.reset()
        defaults.removeObject(forKey: Self.selectedViewIDKey)
    }

    /// Removes one installed archive off-main. Removing the selected skin also clears its view
    /// identity so the active WMP controller can recover to the app-authored unskinned player.
    func removeSkin(named name: String) async throws {
        guard let skin = installedSkins().first(where: {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) else { throw WMPSkinImportError.selectionMissing(name) }
        try await folder.remove(skin.url)
        if selection.name?.caseInsensitiveCompare(skin.name) == .orderedSame {
            resetSelection()
        }
    }
}
