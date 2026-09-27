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

/// Owns WMP's installed archive directory and selection preference. Import validates the complete
/// hostile archive before any destination is touched, then commits through one same-directory
/// atomic replacement.
struct WMPSkinImporter {
    static let selectedSkinNameKey = "wmpSkinName"
    static let selectedViewIDKey = "wmpSkinViewID"

    let directoryURL: URL
    let defaults: UserDefaults
    let fileManager: FileManager
    let loader: WMPSkinLoader

    init(
        directoryURL: URL? = nil,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        loader: WMPSkinLoader = WMPSkinLoader()
    ) {
        self.fileManager = fileManager
        self.defaults = defaults
        self.loader = loader
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            self.directoryURL = applicationSupport
                .appendingPathComponent("NullPlayer", isDirectory: true)
                .appendingPathComponent("WMPSkins", isDirectory: true)
        }
    }

    var selectedSkinName: String? {
        defaults.string(forKey: Self.selectedSkinNameKey)
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

    func ensureDirectoryExists() throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func selectedSkinURL() throws -> URL? {
        guard let name = selectedSkinName, !name.isEmpty else { return nil }
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

        let installed = try await Task.detached(priority: .userInitiated) {
            // Keep validation, directory enumeration, archive copy, and atomic commit away from
            // MainActor even when an AppKit controller initiated the import.
            _ = try await loader.load(from: sourceURL)
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
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

            let incoming = directoryURL.appendingPathComponent(".incoming-\(UUID().uuidString).wmz")
            defer { try? fileManager.removeItem(at: incoming) }
            try fileManager.copyItem(at: sourceURL, to: incoming)
            // Validate the exact copied bytes before commit, not just the source path.
            _ = try await loader.load(from: incoming)

            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: incoming,
                                                   backupItemName: nil, options: [])
            } else {
                try fileManager.moveItem(at: incoming, to: destination)
            }
            return WMPInstalledSkin(name: name, url: destination)
        }.value
        defaults.set(name, forKey: Self.selectedSkinNameKey)
        return installed
    }

    func select(_ skin: WMPInstalledSkin, viewID: String? = nil) {
        defaults.set(skin.name, forKey: Self.selectedSkinNameKey)
        if let viewID, !viewID.isEmpty {
            defaults.set(viewID, forKey: Self.selectedViewIDKey)
        } else {
            defaults.removeObject(forKey: Self.selectedViewIDKey)
        }
    }

    func resetSelection() {
        defaults.removeObject(forKey: Self.selectedSkinNameKey)
        defaults.removeObject(forKey: Self.selectedViewIDKey)
    }

    /// Removes one installed archive off-main. Removing the selected skin also clears its view
    /// identity so the active WMP controller can recover to the app-authored unskinned player.
    func removeSkin(named name: String) async throws {
        let skin = try await Task.detached(priority: .userInitiated) {
            guard let skin = installedSkins().first(where: {
                $0.name.caseInsensitiveCompare(name) == .orderedSame
            }) else { throw WMPSkinImportError.selectionMissing(name) }
            try fileManager.removeItem(at: skin.url)
            return skin
        }.value
        if selectedSkinName?.caseInsensitiveCompare(skin.name) == .orderedSame {
            resetSelection()
        }
    }
}
