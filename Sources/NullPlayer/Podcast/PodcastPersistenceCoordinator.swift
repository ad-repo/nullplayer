import Foundation

/// Serializes podcast persistence away from the main actor. The playback callback only reaches
/// this object for tracks carrying a podcast episode ID, and progress is throttled before a work
/// item is submitted.
final class PodcastPersistenceCoordinator: @unchecked Sendable {
    static let shared = PodcastPersistenceCoordinator()

    private let queue = DispatchQueue(label: "NullPlayer.PodcastPersistence", qos: .utility)
    private let progressLock = NSLock()
    private var lastProgressSubmission: [String: TimeInterval] = [:]
    private var submittedCompletion: Set<String> = []
    private var latestPlayback: [String: PlaybackProgress] = [:]
    private let progressInterval: TimeInterval = 10

    private struct PlaybackProgress: Sendable {
        let position: TimeInterval
        let duration: TimeInterval?
        let isPlayed: Bool
        let playedAt: Date
    }

    private init() {}

    func load(completion: @escaping @MainActor @Sendable (PodcastLibrarySnapshot) -> Void) {
        queue.async {
            // MediaLibrary owns the shared database connection. Initializing it here keeps schema
            // setup, the local-library load, and any legacy migration off the main thread.
            _ = MediaLibrary.shared
            var snapshot = MediaLibraryStore.shared.loadPodcastLibrary()

            if snapshot.subscriptions.isEmpty,
               snapshot.episodeStates.isEmpty,
               snapshot.knownEpisodes.isEmpty,
               let legacyURL = Self.legacySnapshotURL(),
               let data = try? Data(contentsOf: legacyURL),
               let legacy = try? JSONDecoder().decode(PodcastLibrarySnapshot.self, from: data),
               MediaLibraryStore.shared.savePodcastLibrary(legacy) {
                snapshot = MediaLibraryStore.shared.loadPodcastLibrary()
                Self.archiveMigratedSnapshot(at: legacyURL)
                NSLog("PodcastPersistenceCoordinator: migrated podcast library JSON into library.db")
            }

            let loadedSnapshot = snapshot
            DispatchQueue.main.async {
                completion(loadedSnapshot)
            }
        }
    }

    func save(_ snapshot: PodcastLibrarySnapshot) {
        queue.async {
            _ = MediaLibrary.shared
            var mergedSnapshot = snapshot
            self.progressLock.lock()
            let playback = self.latestPlayback
            self.progressLock.unlock()
            for (episodeID, progress) in playback {
                var state = mergedSnapshot.episodeStates[episodeID] ?? PodcastEpisodeState()
                state.position = progress.position
                state.duration = progress.duration ?? state.duration
                state.isPlayed = state.isPlayed || progress.isPlayed
                state.lastPlayedAt = progress.playedAt
                mergedSnapshot.episodeStates[episodeID] = state
            }
            if !MediaLibraryStore.shared.savePodcastLibrary(mergedSnapshot) {
                NSLog("PodcastPersistenceCoordinator: failed to persist podcast library in SQLite")
            }
        }
    }

    func recordPlayback(episodeID: String, current: TimeInterval, duration: TimeInterval) {
        let now = Date().timeIntervalSinceReferenceDate
        let completed = duration > 0 &&
            (current >= max(30, duration - 20) || current / duration >= 0.95)
        let playedAt = Date()

        progressLock.lock()
        latestPlayback[episodeID] = PlaybackProgress(
            position: max(0, current),
            duration: duration > 0 ? duration : nil,
            isPlayed: completed,
            playedAt: playedAt
        )
        if !completed {
            submittedCompletion.remove(episodeID)
        }
        let lastSubmission = lastProgressSubmission[episodeID] ?? 0
        let shouldSubmit = completed
            ? !submittedCompletion.contains(episodeID)
            : now - lastSubmission >= progressInterval
        if shouldSubmit {
            lastProgressSubmission[episodeID] = now
            if completed { submittedCompletion.insert(episodeID) }
        }
        progressLock.unlock()

        guard shouldSubmit else { return }
        queue.async {
            _ = MediaLibrary.shared
            MediaLibraryStore.shared.updatePodcastPlaybackProgress(
                episodeID: episodeID,
                current: current,
                duration: duration,
                playedAt: playedAt
            )
        }
    }

    private static func storageRoot() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent("NullPlayer/Podcasts", isDirectory: true)
    }

    private static func legacySnapshotURL() -> URL? {
        try? storageRoot().appendingPathComponent("library.json")
    }

    private static func archiveMigratedSnapshot(at url: URL) {
        let fileManager = FileManager.default
        var destination = url.appendingPathExtension("migrated")
        if fileManager.fileExists(atPath: destination.path) {
            destination = url.appendingPathExtension("migrated-\(Int(Date().timeIntervalSince1970))")
        }
        do {
            try fileManager.moveItem(at: url, to: destination)
        } catch {
            NSLog("PodcastPersistenceCoordinator: could not archive migrated JSON: %@", error.localizedDescription)
        }
    }
}
