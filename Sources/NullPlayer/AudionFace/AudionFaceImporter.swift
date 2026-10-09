import Foundation

struct AudionInstalledFace: Hashable {
    let name: String
    let url: URL
}

enum AudionFaceImportError: LocalizedError {
    case noFaceFound(String)
    case selectionMissing(String)

    var errorDescription: String? {
        switch self {
        case let .noFaceFound(name):
            return "“\(name)” is not an Audion face: it holds no folder with an index.json."
        case let .selectionMissing(name):
            return "The selected Audion face “\(name)” is no longer installed. Load it again or choose another face."
        }
    }
}

/// Owns the installed-faces directory and the selection preference. An import validates every face
/// through `AudionFaceLoader` off the main thread before anything is written, copies it beside the
/// destination as `.incoming-<UUID>`, and commits with one same-directory move.
struct AudionFaceImporter {
    static let selectedFaceNameKey = "audionFaceName"

    let directoryURL: URL
    let defaults: UserDefaults
    let fileManager: FileManager

    init(directoryURL: URL? = nil, defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        self.defaults = defaults
        self.fileManager = fileManager
        self.directoryURL = directoryURL ?? (fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true))
            .appendingPathComponent("NullPlayer", isDirectory: true)
            .appendingPathComponent("AudionFaces", isDirectory: true)
    }

    var selectedFaceName: String? { defaults.string(forKey: Self.selectedFaceNameKey) }

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

    func face(named name: String) -> AudionInstalledFace? {
        installedFaces().first { $0.name == name }
    }

    /// The selected face's folder, nil when nothing is selected; throws when the selection is gone.
    func selectedFaceURL() throws -> URL? {
        guard let name = selectedFaceName, !name.isEmpty else { return nil }
        guard let face = face(named: name) else { throw AudionFaceImportError.selectionMissing(name) }
        return face.url
    }

    func ensureDirectoryExists() throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func select(_ name: String) { defaults.set(name, forKey: Self.selectedFaceNameKey) }

    func resetSelection() { defaults.removeObject(forKey: Self.selectedFaceNameKey) }

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
            try ensureDirectoryExists()
            var installed: [AudionInstalledFace] = []
            for folder in folders {
                // A zip's top-level face unpacks into `staging` itself; it is named after the zip.
                let name = folder.standardizedFileURL == staging.standardizedFileURL
                    ? source.deletingPathExtension().lastPathComponent : folder.lastPathComponent
                installed.append(try await install(folder, as: name))
            }
            return installed
        }.value
        if let first = installed.first { select(first.name) }
        return installed
    }

    private func install(_ folder: URL, as name: String) async throws -> AudionInstalledFace {
        let destination = directoryURL.appendingPathComponent(name, isDirectory: true)
        let incoming = directoryURL.appendingPathComponent(".incoming-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: incoming) }
        try fileManager.copyItem(at: folder, to: incoming)
        // Validate the copied bytes, not the source: the copy is what gets committed.
        _ = try await AudionFaceLoader.load(folder: incoming)
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: incoming, backupItemName: nil, options: [])
        } else {
            try fileManager.moveItem(at: incoming, to: destination)
        }
        return AudionInstalledFace(name: name, url: destination)
    }

    /// Deletes an installed face off the main thread; removing the selected one clears the selection.
    func removeFace(named name: String) async throws {
        try await Task.detached(priority: .userInitiated) { [self] in
            guard let face = face(named: name) else { throw AudionFaceImportError.selectionMissing(name) }
            try fileManager.removeItem(at: face.url)
        }.value
        if selectedFaceName == name { resetSelection() }
    }
}
