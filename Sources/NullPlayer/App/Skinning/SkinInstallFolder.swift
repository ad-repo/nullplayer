import Foundation

/// One skin family's folder of installed skins in Application Support, and the one way a skin gets
/// into it: copied in beside its destination as a hidden `.incoming-<UUID>`, validated as that copy
/// (the bytes that get committed, not the source), then committed with one same-directory move or
/// replace, so a failed import leaves the installed skin untouched. Each family keeps its own file
/// test, loader, naming and selection (WMP's view id, `.wal`'s bundled fallback).
struct SkinInstallFolder {
    let url: URL
    let fileManager: FileManager

    /// `Application Support/NullPlayer/<name>`, unless a test passes its own folder.
    init(_ name: String, at url: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.url = url ?? (fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true))
            .appendingPathComponent("NullPlayer", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
    }

    func ensureExists() throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// Installs `source` as `destination` inside the folder. `suffix` ends the staging copy's name,
    /// for a loader that reads the extension.
    func commit(_ source: URL, to destination: URL, suffix: String = "",
                validate: (URL) async throws -> Void) async throws {
        let incoming = try stage(source, suffix: suffix)
        defer { try? fileManager.removeItem(at: incoming) }
        try await validate(incoming)
        try place(incoming, at: destination)
    }

    /// The same commit for a family that validated the source already and imports synchronously.
    func commit(_ source: URL, to destination: URL, suffix: String = "") throws {
        let incoming = try stage(source, suffix: suffix)
        defer { try? fileManager.removeItem(at: incoming) }
        try place(incoming, at: destination)
    }

    /// Deletes an installed skin off the main thread.
    func remove(_ installed: URL) async throws {
        try await Task.detached(priority: .userInitiated) { [fileManager] in
            try fileManager.removeItem(at: installed)
        }.value
    }

    private func stage(_ source: URL, suffix: String) throws -> URL {
        try ensureExists()
        let incoming = url.appendingPathComponent(".incoming-\(UUID().uuidString)\(suffix)")
        try fileManager.copyItem(at: source, to: incoming)
        return incoming
    }

    private func place(_ incoming: URL, at destination: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: incoming, backupItemName: nil, options: [])
        } else {
            try fileManager.moveItem(at: incoming, to: destination)
        }
    }
}
