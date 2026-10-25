import Foundation

struct SoniqueInstalledSkin: Hashable {
    /// The file name without `.sgf`.
    let name: String
    let url: URL
}

enum SoniqueSkinImportError: LocalizedError {
    case selectionMissing(String)
    case notInstalled(String)

    var errorDescription: String? {
        switch self {
        case let .selectionMissing(name):
            return "The selected Sonique skin “\(name)” is no longer installed. Load it again or choose another skin."
        case let .notInstalled(name):
            return "No Sonique skin named “\(name)” is installed."
        }
    }
}

/// The installed-skins folder and the selection preference. A skin is one `.sgf` file (decision
/// record § *Decisions*), validated through `SoniqueSkinLoader` off the main thread as it is
/// committed (`SkinInstallFolder`).
struct SoniqueSkinImporter {
    let folder: SkinInstallFolder
    let selection: SkinSelection
    var directoryURL: URL { folder.url }
    private var fileManager: FileManager { folder.fileManager }

    init(directoryURL: URL? = nil, defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        selection = SkinSelection(key: "soniqueSkinName", defaults: defaults)
        folder = SkinInstallFolder("SoniqueSkins", at: directoryURL, fileManager: fileManager)
    }

    func installedSkins() -> [SoniqueInstalledSkin] {
        let names = (try? fileManager.contentsOfDirectory(atPath: directoryURL.path)) ?? []
        return names.filter { !$0.hasPrefix(".") && $0.lowercased().hasSuffix(".sgf") }
            .map { SoniqueInstalledSkin(name: String($0.dropLast(4)), url: directoryURL.appendingPathComponent($0)) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The installed skin of that name; a name that is not a plain visible file name never resolves
    /// outside the directory.
    func skin(named name: String) -> SoniqueInstalledSkin? {
        guard !name.isEmpty, !name.contains("/"), !name.hasPrefix(".") else { return nil }
        return installedSkins().first { $0.name == name }
    }

    /// The selected skin's file, nil when nothing is selected; throws when the selection is gone.
    func selectedSkinURL() throws -> URL? {
        guard let name = selection.name, !name.isEmpty else { return nil }
        guard let skin = skin(named: name) else { throw SoniqueSkinImportError.selectionMissing(name) }
        return skin.url
    }

    /// Installs an `.sgf`, replacing one of the same name, and selects it.
    @discardableResult
    func importSkin(from source: URL) async throws -> SoniqueInstalledSkin {
        let installed = try await Task.detached(priority: .userInitiated) { [folder] in
            let name = source.deletingPathExtension().lastPathComponent
            let destination = folder.url.appendingPathComponent(name + ".sgf")
            try await folder.commit(source, to: destination) { _ = try SoniqueSkinLoader.load(contentsOf: $0) }
            return SoniqueInstalledSkin(name: name, url: destination)
        }.value
        selection.select(installed.name)
        return installed
    }

    /// Deletes an installed skin off the main thread; removing the selected one clears the selection.
    func removeSkin(named name: String) async throws {
        guard let skin = skin(named: name) else { throw SoniqueSkinImportError.notInstalled(name) }
        try await folder.remove(skin.url)
        selection.forget(name)
    }
}
