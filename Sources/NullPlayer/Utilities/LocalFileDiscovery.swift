import Foundation

struct LocalDiscoveredMediaFile: Hashable {
    let url: URL
    let path: String
    let fileSize: Int64
    let contentModificationDate: Date?
}

struct LocalFileDiscoveryResult {
    let audioFiles: [LocalDiscoveredMediaFile]
    let videoFiles: [LocalDiscoveredMediaFile]

    var allURLs: [URL] {
        (audioFiles.map(\.url) + videoFiles.map(\.url))
    }
}

enum LocalFileDiscovery {
    static let playlistExtensions: Set<String> = ["m3u", "m3u8", "pls"]

    static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    static func isSupportedAudioFile(_ url: URL, includeLegacyWMA: Bool = false) -> Bool {
        let ext = url.pathExtension.lowercased()
        if includeLegacyWMA && ext == "wma" {
            return true
        }
        return AudioFileValidator.supportedExtensions.contains(ext)
    }

    static func isSupportedVideoFile(_ url: URL) -> Bool {
        AudioFileValidator.supportedVideoExtensions.contains(url.pathExtension.lowercased())
    }

    static func isSupportedPlaylistFile(_ url: URL) -> Bool {
        playlistExtensions.contains(url.pathExtension.lowercased())
    }

    static func hasSupportedDropContent(
        _ urls: [URL],
        includeVideo: Bool,
        includePlaylists: Bool = false
    ) -> Bool {
        for url in urls {
            if isDirectory(url) { return true }
            if isSupportedAudioFile(url) { return true }
            if includeVideo && isSupportedVideoFile(url) { return true }
            if includePlaylists && isSupportedPlaylistFile(url) { return true }
        }
        return false
    }

    /// Streaming variant: calls `onAudioBatch` synchronously every `audioBatchSize` audio files
    /// discovered during traversal. Allows callers to process (insert, persist, notify) batches
    /// immediately rather than waiting for full enumeration to complete.
    /// Returns the full result after all files are enumerated.
    static func discoverMediaStreaming(
        from inputURLs: [URL],
        recursiveDirectories: Bool = true,
        includeVideo: Bool,
        includeLegacyWMA: Bool = false,
        audioBatchSize: Int = 500,
        onAudioBatch: ([LocalDiscoveredMediaFile]) -> Void
    ) -> LocalFileDiscoveryResult {
        // Only fetch the attributes we actually need, and only for files that pass extension check.
        // On NAS/SMB, fetching attributes for every enumerated file (directories, album art, NFO
        // files, etc.) causes thousands of extra network round-trips. By checking the extension
        // first (free — derived from the URL path string) we skip stat calls for all non-media
        // files, which can be the majority of files in a large music library.
        let statKeys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        var seenPaths = Set<String>()
        var allAudio: [LocalDiscoveredMediaFile] = []
        var allVideo: [LocalDiscoveredMediaFile] = []
        var pendingAudio: [LocalDiscoveredMediaFile] = []
        // Time-based flushing: on slow volumes (NAS/SMB), file enumeration can take seconds per
        // directory. Without a time limit we might wait minutes before flushing the first batch.
        // Flush whatever audio we have after 2 seconds regardless of batch size so tracks start
        // appearing in the library immediately.
        var lastFlushTime = CFAbsoluteTimeGetCurrent()

        func processURL(_ url: URL) {
            // Extension check is free (string operation, no syscall). Skip everything that
            // isn't a supported media file before paying for a network stat call.
            let isAudio = isSupportedAudioFile(url, includeLegacyWMA: includeLegacyWMA)
            let isVideo = !isAudio && includeVideo && isSupportedVideoFile(url)
            guard isAudio || isVideo else { return }

            let path = url.path
            guard seenPaths.insert(path).inserted else { return }

            // Stat only files that passed the extension filter.
            guard let values = try? url.resourceValues(forKeys: Set(statKeys)),
                  values.isRegularFile == true else { return }

            let file = LocalDiscoveredMediaFile(
                url: url, path: path,
                fileSize: Int64(values.fileSize ?? 0),
                contentModificationDate: values.contentModificationDate
            )
            if isAudio {
                allAudio.append(file)
                pendingAudio.append(file)
                let now = CFAbsoluteTimeGetCurrent()
                if pendingAudio.count >= audioBatchSize || (now - lastFlushTime) >= 2.0 {
                    onAudioBatch(pendingAudio)
                    pendingAudio.removeAll(keepingCapacity: true)
                    lastFlushTime = now
                }
            } else {
                allVideo.append(file)
            }
        }

        for inputURL in inputURLs {
            if isDirectory(inputURL) {
                if recursiveDirectories {
                    // Pass nil for includingPropertiesForKeys — we do selective stat calls in
                    // processURL after extension filtering, so pre-fetching for every file wastes
                    // network bandwidth on NAS.
                    if let enumerator = FileManager.default.enumerator(
                        at: inputURL,
                        includingPropertiesForKeys: nil,
                        options: [.skipsPackageDescendants, .skipsHiddenFiles]
                    ) {
                        while let next = enumerator.nextObject() as? URL {
                            processURL(next)
                        }
                    }
                } else {
                    if let contents = try? FileManager.default.contentsOfDirectory(
                        at: inputURL,
                        includingPropertiesForKeys: nil,
                        options: [.skipsPackageDescendants, .skipsHiddenFiles]
                    ) {
                        for item in contents { processURL(item) }
                    }
                }
            } else {
                processURL(inputURL)
            }
        }

        // Flush remaining audio that didn't fill a complete batch
        if !pendingAudio.isEmpty {
            onAudioBatch(pendingAudio)
        }
        return LocalFileDiscoveryResult(audioFiles: allAudio, videoFiles: allVideo)
    }

    static func discoverMedia(
        from inputURLs: [URL],
        recursiveDirectories: Bool = true,
        includeVideo: Bool,
        includeLegacyWMA: Bool = false
    ) -> LocalFileDiscoveryResult {
        var audioFiles: [LocalDiscoveredMediaFile] = []
        var videoFiles: [LocalDiscoveredMediaFile] = []
        var seenPaths = Set<String>()

        for inputURL in inputURLs {
            collectMedia(
                from: inputURL,
                recursiveDirectories: recursiveDirectories,
                includeVideo: includeVideo,
                includeLegacyWMA: includeLegacyWMA,
                seenPaths: &seenPaths,
                audioFiles: &audioFiles,
                videoFiles: &videoFiles
            )
        }

        return LocalFileDiscoveryResult(audioFiles: audioFiles, videoFiles: videoFiles)
    }

    static func discoverMediaURLsAsync(
        from inputURLs: [URL],
        includeVideo: Bool,
        includeLegacyWMA: Bool = false,
        completion: @escaping ([URL]) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = discoverMedia(
                from: inputURLs,
                recursiveDirectories: true,
                includeVideo: includeVideo,
                includeLegacyWMA: includeLegacyWMA
            )
            let urls = result.allURLs.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            DispatchQueue.main.async {
                completion(urls)
            }
        }
    }

    private static func collectMedia(
        from url: URL,
        recursiveDirectories: Bool,
        includeVideo: Bool,
        includeLegacyWMA: Bool,
        seenPaths: inout Set<String>,
        audioFiles: inout [LocalDiscoveredMediaFile],
        videoFiles: inout [LocalDiscoveredMediaFile]
    ) {
        if isDirectory(url) {
            if recursiveDirectories {
                collectRecursively(
                    in: url,
                    includeVideo: includeVideo,
                    includeLegacyWMA: includeLegacyWMA,
                    seenPaths: &seenPaths,
                    audioFiles: &audioFiles,
                    videoFiles: &videoFiles
                )
            } else {
                collectShallow(
                    in: url,
                    includeVideo: includeVideo,
                    includeLegacyWMA: includeLegacyWMA,
                    seenPaths: &seenPaths,
                    audioFiles: &audioFiles,
                    videoFiles: &videoFiles
                )
            }
            return
        }

        appendFileIfSupported(
            url: url,
            includeVideo: includeVideo,
            includeLegacyWMA: includeLegacyWMA,
            seenPaths: &seenPaths,
            audioFiles: &audioFiles,
            videoFiles: &videoFiles
        )
    }

    private static func collectRecursively(
        in rootURL: URL,
        includeVideo: Bool,
        includeLegacyWMA: Bool,
        seenPaths: inout Set<String>,
        audioFiles: inout [LocalDiscoveredMediaFile],
        videoFiles: inout [LocalDiscoveredMediaFile]
    ) {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsPackageDescendants, .skipsHiddenFiles]
        ) else {
            return
        }

        while let next = enumerator.nextObject() as? URL {
            appendFileIfSupported(
                url: next,
                includeVideo: includeVideo,
                includeLegacyWMA: includeLegacyWMA,
                seenPaths: &seenPaths,
                audioFiles: &audioFiles,
                videoFiles: &videoFiles
            )
        }
    }

    private static func collectShallow(
        in rootURL: URL,
        includeVideo: Bool,
        includeLegacyWMA: Bool,
        seenPaths: inout Set<String>,
        audioFiles: inout [LocalDiscoveredMediaFile],
        videoFiles: inout [LocalDiscoveredMediaFile]
    ) {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsPackageDescendants, .skipsHiddenFiles]
        ) else {
            return
        }

        for item in contents {
            appendFileIfSupported(
                url: item,
                includeVideo: includeVideo,
                includeLegacyWMA: includeLegacyWMA,
                seenPaths: &seenPaths,
                audioFiles: &audioFiles,
                videoFiles: &videoFiles
            )
        }
    }

    private static func appendFileIfSupported(
        url: URL,
        includeVideo: Bool,
        includeLegacyWMA: Bool,
        seenPaths: inout Set<String>,
        audioFiles: inout [LocalDiscoveredMediaFile],
        videoFiles: inout [LocalDiscoveredMediaFile]
    ) {
        // Extension check first — free string op, no syscall. Avoids stat calls for
        // directories, album art, NFO files, and other non-media content.
        let isAudio = isSupportedAudioFile(url, includeLegacyWMA: includeLegacyWMA)
        let isVideo = !isAudio && includeVideo && isSupportedVideoFile(url)
        guard isAudio || isVideo else { return }

        let path = url.path
        guard seenPaths.insert(path).inserted else { return }

        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
              values.isRegularFile == true else { return }

        let discovered = LocalDiscoveredMediaFile(
            url: url,
            path: path,
            fileSize: Int64(values.fileSize ?? 0),
            contentModificationDate: values.contentModificationDate
        )

        if isAudio {
            audioFiles.append(discovered)
        } else {
            videoFiles.append(discovered)
        }
    }
}
