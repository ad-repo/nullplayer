import Foundation

/// One finished job, as the Rip window's History lists it.
struct RipHistoryEntry: Codable, Equatable, Identifiable {
    let id: String
    let source: RipJob.Source
    let url: URL
    /// The rip's choices, for retry; nil for a YouTube download.
    let mode: StreamRipper.Mode?
    let summary: String
    let folder: String?
    let title: String
    let outcome: RipJob.Phase
    let startedAt: Date
    let finishedAt: Date
    let outputPath: String?
    let sizeBytes: Int64?
    let error: String?
}

/// Every finished rip and YouTube download, newest first, kept across relaunches in
/// `Application Support/NullPlayer/rip_history.json`. The full URL is stored because retry needs
/// it; it never goes to the log.
@MainActor
final class RipHistoryStore {
    static let shared = RipHistoryStore(fileURL: RipHistoryStore.defaultFileURL)
    static let limit = 500

    private let fileURL: URL?
    private(set) var entries: [RipHistoryEntry]
    /// Bumped on every change, so a view redraws the history only when it changed.
    private(set) var revision = 0

    init(fileURL: URL?) {
        self.fileURL = fileURL
        entries = []
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            entries = try JSONDecoder().decode([RipHistoryEntry].self, from: Data(contentsOf: fileURL))
        } catch {
            NSLog("RipHistoryStore: unreadable history, starting empty: %@", error.localizedDescription)
        }
    }

    private static var defaultFileURL: URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        let dir = support.appendingPathComponent("NullPlayer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        return dir.appendingPathComponent("rip_history.json")
    }

    func append(_ entry: RipHistoryEntry) {
        entries.insert(entry, at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
        save()
    }

    func remove(id: String) {
        entries.removeAll { $0.id == id }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    private func save() {
        revision += 1
        guard let fileURL else { return }
        do {
            try JSONEncoder().encode(entries).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("RipHistoryStore: could not save history: %@", error.localizedDescription)
        }
    }
}
