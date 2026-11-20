import Foundation

/// An installed skin of a family whose skin is one file.
struct InstalledSkinFile: Hashable {
    /// The file name without its extension.
    let name: String
    let url: URL
}

enum SkinFileCatalogueError: LocalizedError {
    case selectionMissing(family: String, name: String)
    case notInstalled(family: String, name: String)

    var errorDescription: String? {
        switch self {
        case let .selectionMissing(family, name):
            return "The selected \(family) skin “\(name)” is no longer installed. Load it again or choose another skin."
        case let .notInstalled(family, name):
            return "No \(family) skin named “\(name)” is installed."
        }
    }
}

/// A family whose skin is one file (Sonique's `.sgf`): its installed-skins folder, by name, and the
/// selection preference. The family keeps its own loader check and naming of what it imports;
/// `install` commits one file through `SkinInstallFolder`.
protocol SkinFileCatalogue {
    /// The family as its messages name it ("Sonique").
    static var family: String { get }
    /// A skin file's extension, lowercased.
    static var fileExtension: String { get }
    var folder: SkinInstallFolder { get }
    var selection: SkinSelection { get }
}

extension SkinFileCatalogue {
    func installedSkins() -> [InstalledSkinFile] {
        let suffix = "." + Self.fileExtension
        let names = (try? folder.fileManager.contentsOfDirectory(atPath: folder.url.path)) ?? []
        return names.filter { !$0.hasPrefix(".") && $0.lowercased().hasSuffix(suffix) }
            .map { InstalledSkinFile(name: String($0.dropLast(suffix.count)), url: folder.url.appendingPathComponent($0)) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The installed skin of that name; a name that is not a plain visible file name never resolves
    /// outside the directory.
    func skin(named name: String) -> InstalledSkinFile? {
        guard !name.isEmpty, !name.contains("/"), !name.hasPrefix(".") else { return nil }
        return installedSkins().first { $0.name == name }
    }

    /// The selected skin's file, nil when nothing is selected; throws when the selection is gone.
    func selectedSkinURL() throws -> URL? {
        guard let name = selection.name, !name.isEmpty else { return nil }
        guard let skin = skin(named: name) else { throw SkinFileCatalogueError.selectionMissing(family: Self.family, name: name) }
        return skin.url
    }

    /// Deletes an installed skin off the main thread; removing the selected one clears the selection.
    func removeSkin(named name: String) async throws {
        guard let skin = skin(named: name) else { throw SkinFileCatalogueError.notInstalled(family: Self.family, name: name) }
        try await folder.remove(skin.url)
        selection.forget(name)
    }

    /// Installs `file` under its own name with the family's extension, replacing one of that name, once
    /// `validate` passes the copy being committed. Selecting it is the caller's.
    static func install(_ file: URL, into folder: SkinInstallFolder,
                        validate: (URL) async throws -> Void) async throws -> InstalledSkinFile {
        let name = file.deletingPathExtension().lastPathComponent
        let destination = folder.url.appendingPathComponent(name + "." + fileExtension)
        try await folder.commit(file, to: destination, validate: validate)
        return InstalledSkinFile(name: name, url: destination)
    }
}
