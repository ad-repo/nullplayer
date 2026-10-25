import Foundation

struct AudionInstalledFace: Hashable {
    let name: String
    let url: URL
}

enum AudionFaceImportError: LocalizedError {
    case noFaceFound(String)
    case selectionMissing(String)
    case notInstalled(String)

    var errorDescription: String? {
        switch self {
        case let .noFaceFound(name):
            return "“\(name)” is not an Audion face: it holds no folder with an index.json."
        case let .selectionMissing(name):
            return "The selected Audion face “\(name)” is no longer installed. Load it again or choose another face."
        case let .notInstalled(name):
            return "No Audion face named “\(name)” is installed."
        }
    }
}

/// The installed-faces folder and the selection preference. Every face of an import is validated
/// through `AudionFaceLoader` off the main thread as it is committed (`SkinInstallFolder`).
struct AudionFaceImporter {
    let folder: SkinInstallFolder
    let selection: SkinSelection
    var directoryURL: URL { folder.url }
    private var fileManager: FileManager { folder.fileManager }

    init(directoryURL: URL? = nil, defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        selection = SkinSelection(key: "audionFaceName", defaults: defaults)
        folder = SkinInstallFolder("AudionFaces", at: directoryURL, fileManager: fileManager)
    }

    /// Every top-level folder holding an `index.json`, by name. Names keep their authored spaces.
    func installedFaces() -> [AudionInstalledFace] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directoryURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return [] }
        return urls.compactMap { url in
            guard fileManager.fileExists(atPath: url.appendingPathComponent("index.json").path) else { return nil }
            return AudionInstalledFace(name: url.lastPathComponent, url: url)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The installed face of that name, looked up directly; a name that is not a plain visible
    /// folder name (`installedFaces` skips hidden entries) never resolves outside the directory.
    func face(named name: String) -> AudionInstalledFace? {
        guard !name.isEmpty, !name.contains("/"), !name.hasPrefix(".") else { return nil }
        let url = directoryURL.appendingPathComponent(name, isDirectory: true)
        guard fileManager.fileExists(atPath: url.appendingPathComponent("index.json").path) else { return nil }
        return AudionInstalledFace(name: name, url: url)
    }

    /// The selected face's folder, nil when nothing is selected; throws when the selection is gone.
    func selectedFaceURL() throws -> URL? {
        guard let name = selection.name, !name.isEmpty else { return nil }
        guard let face = face(named: name) else { throw AudionFaceImportError.selectionMissing(name) }
        return face.url
    }

    /// Installs a face folder, or every face in a `.zip` (Panic's distribution format), replacing a
    /// face of the same name. Selects the first face installed and returns them all.
    @discardableResult
    func importFaces(from source: URL) async throws -> [AudionInstalledFace] {
        let installed = try await Task.detached(priority: .userInitiated) { [self] in
            let staging = fileManager.temporaryDirectory
                .appendingPathComponent("audion-import-\(UUID().uuidString)", isDirectory: true)
            defer { try? fileManager.removeItem(at: staging) }
            let folders = source.pathExtension.caseInsensitiveCompare("zip") == .orderedSame
                ? try AudionFaceZipImport.unpack(source, into: staging)
                : [source]
            guard !folders.isEmpty else { throw AudionFaceImportError.noFaceFound(source.lastPathComponent) }
            var installed: [AudionInstalledFace] = []
            for folder in folders {
                // A zip's top-level face unpacks into `staging` itself; it is named after the zip.
                let name = folder.standardizedFileURL == staging.standardizedFileURL
                    ? source.deletingPathExtension().lastPathComponent : folder.lastPathComponent
                installed.append(try await install(folder, as: name))
            }
            return installed
        }.value
        if let first = installed.first { selection.select(first.name) }
        return installed
    }

    private func install(_ face: URL, as name: String) async throws -> AudionInstalledFace {
        let destination = directoryURL.appendingPathComponent(name, isDirectory: true)
        try await folder.commit(face, to: destination) { _ = try await AudionFaceLoader.load(folder: $0) }
        return AudionInstalledFace(name: name, url: destination)
    }

    /// Deletes an installed face off the main thread; removing the selected one clears the selection.
    func removeFace(named name: String) async throws {
        guard let face = face(named: name) else { throw AudionFaceImportError.notInstalled(name) }
        try await folder.remove(face.url)
        selection.forget(name)
    }
}
