import Foundation

/// Disk staging and crash cleanup for local playback; no engine or transport state.
enum LocalAudioStaging {
    /// Keep a real reserve on the temp volume when staging NAS files locally.
    private static let minimumTemporaryCopyFreeSpaceReserveBytes: Int64 = 1 * 1024 * 1024 * 1024
    /// Filename prefix for staged NAS playback copies. Must stay specific to playback
    /// copies: `cleanupStaleCopies()` deletes every temp file with this
    /// prefix on launch, so a broad prefix (e.g. bare `nullplayer-`) would also wipe
    /// other subsystems' temp files (StreamRipper's `nullplayer-yt-*` / `nullplayer-rip-*`,
    /// YouTubeManager's `nullplayer-ytdlp-*`). Keep it distinct from those.
    private static let temporaryPlaybackCopyPrefix = "nullplayer-playbackcopy-"

    static func copyIfNeeded(
        for sourceURL: URL,
        logPrefix: String,
        displayName: String? = nil
    ) -> URL? {
        let fileManager = FileManager.default
        let name = displayName ?? sourceURL.lastPathComponent
        let isLocalVolume = (try? sourceURL.resourceValues(
            forKeys: [.volumeIsLocalKey]
        ))?.volumeIsLocal ?? true

        guard !isLocalVolume else { return nil }

        let fileSize = Int64((try? sourceURL.resourceValues(
            forKeys: [.fileSizeKey]
        ))?.fileSize ?? 0)
        let tempDirectory = fileManager.temporaryDirectory

        if fileSize > 0,
           let available = temporaryDirectoryAvailableCapacity(for: tempDirectory) {
            let required = fileSize + Self.minimumTemporaryCopyFreeSpaceReserveBytes
            guard available >= required else {
                NSLog(
                    "%@: Skipping NAS temp copy for '%@' (%lld MB); temp volume has %lld MB free",
                    logPrefix,
                    name,
                    fileSize / (1024 * 1024),
                    available / (1024 * 1024)
                )
                return nil
            }
        }

        let ext = sourceURL.pathExtension
        let filename = Self.temporaryPlaybackCopyPrefix + UUID().uuidString + (ext.isEmpty ? "" : ".\(ext)")
        let candidate = tempDirectory.appendingPathComponent(filename)
        let copyStart = CFAbsoluteTimeGetCurrent()

        do {
            try fileManager.copyItem(at: sourceURL, to: candidate)
            NSLog(
                "%@: Copied NAS '%@' to temp in %.3fs",
                logPrefix,
                name,
                CFAbsoluteTimeGetCurrent() - copyStart
            )
            return candidate
        } catch {
            try? fileManager.removeItem(at: candidate)
            NSLog(
                "%@: NAS temp copy failed for '%@': %@; falling back to original file",
                logPrefix,
                name,
                error.localizedDescription.redactingSensitiveURLQueryItems
            )
            return nil
        }
    }

    /// Remove leftover staged NAS playback copies on launch (files left behind by a crash
    /// or force-quit that skipped the normal teardown/replacement cleanup). Matches on
    /// `temporaryPlaybackCopyPrefix`, which is kept specific to playback copies so this does
    /// not touch other subsystems' temp files.
    static func cleanupStaleCopies() {
        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory
        guard let entries = try? fileManager.contentsOfDirectory(
            at: tempDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        var removedCount = 0
        for url in entries where url.lastPathComponent.hasPrefix(Self.temporaryPlaybackCopyPrefix) {
            let isRegularFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
            guard isRegularFile else { continue }

            do {
                try fileManager.removeItem(at: url)
                removedCount += 1
            } catch {
                NSLog(
                    "AudioEngine: Failed to remove stale temp playback copy '%@': %@",
                    url.lastPathComponent,
                    error.localizedDescription.redactingSensitiveURLQueryItems
                )
            }
        }

        if removedCount > 0 {
            NSLog("AudioEngine: Removed %d stale temp playback copy file(s)", removedCount)
        }
    }

    private static func temporaryDirectoryAvailableCapacity(for url: URL) -> Int64? {
        if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let capacity = values.volumeAvailableCapacityForImportantUsage {
            return capacity
        }

        if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
           let capacity = values.volumeAvailableCapacity {
            return Int64(capacity)
        }

        return nil
    }

}
