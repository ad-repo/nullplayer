import Foundation

/// The installed-skins folder and the selection preference (`SkinFileCatalogue`). A skin is one
/// `.sgf` file (decision record § *Decisions*), validated through `SoniqueSkinLoader` off the main
/// thread as it is committed (`SkinInstallFolder`).
struct SoniqueSkinImporter: SkinFileCatalogue {
    static let family = "Sonique"
    static let fileExtension = "sgf"

    let folder: SkinInstallFolder
    let selection: SkinSelection

    init(directoryURL: URL? = nil, defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        selection = SkinSelection(key: "soniqueSkinName", defaults: defaults)
        folder = SkinInstallFolder("SoniqueSkins", at: directoryURL, fileManager: fileManager)
    }

    /// Installs an `.sgf`, replacing one of the same name, and selects it.
    @discardableResult
    func importSkin(from source: URL) async throws -> InstalledSkinFile {
        let installed = try await Task.detached(priority: .userInitiated) { [folder] in
            try await Self.install(source, into: folder) { _ = try SoniqueSkinLoader.load(contentsOf: $0) }
        }.value
        selection.select(installed.name)
        return installed
    }
}
