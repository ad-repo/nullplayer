import Foundation

public struct LocalDiscoveredMediaFile: Hashable, Sendable {
    public let url: URL
    public let path: String
    public let fileSize: Int64
    public let contentModificationDate: Date?

    public init(url: URL, path: String, fileSize: Int64, contentModificationDate: Date?) {
        self.url = url
        self.path = path
        self.fileSize = fileSize
        self.contentModificationDate = contentModificationDate
    }
}

public struct LocalFileDiscoveryResult: Sendable {
    public let audioFiles: [LocalDiscoveredMediaFile]
    public let videoFiles: [LocalDiscoveredMediaFile]

    public var allURLs: [URL] {
        audioFiles.map(\.url) + videoFiles.map(\.url)
    }

    public init(audioFiles: [LocalDiscoveredMediaFile], videoFiles: [LocalDiscoveredMediaFile]) {
        self.audioFiles = audioFiles
        self.videoFiles = videoFiles
    }
}

public enum LocalFileDiscovery {
    public static let playlistExtensions: Set<String> = ["m3u", "m3u8", "pls"]

    public static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    public static func isSupportedAudioFile(_ url: URL, includeLegacyWMA: Bool = false) -> Bool {
        let ext = url.pathExtension.lowercased()
        if includeLegacyWMA && ext == "wma" {
            return true
        }
        return AudioFileValidator.supportedExtensions.contains(ext)
    }

    public static func isSupportedVideoFile(_ url: URL) -> Bool {
        AudioFileValidator.supportedVideoExtensions.contains(url.pathExtension.lowercased())
    }

    public static func isSupportedPlaylistFile(_ url: URL) -> Bool {
        playlistExtensions.contains(url.pathExtension.lowercased())
    }

    public static func hasSupportedDropContent(
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

    public static func discoverMediaStreaming(
        from inputURLs: [URL],
        recursiveDirectories: Bool = true,
        includeVideo: Bool,
        includeLegacyWMA: Bool = false,
        audioBatchSize: Int = 500,
        onAudioBatch: ([LocalDiscoveredMediaFile]) -> Void
    ) -> LocalFileDiscoveryResult {
        let statKeys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        var seenPaths = Set<String>()
        var allAudio: [LocalDiscoveredMediaFile] = []
        var allVideo: [LocalDiscoveredMediaFile] = []
        var pendingAudio: [LocalDiscoveredMediaFile] = []
        var lastFlushTime = Date().timeIntervalSinceReferenceDate

        func processURL(_ url: URL) {
            let isAudio = isSupportedAudioFile(url, includeLegacyWMA: includeLegacyWMA)
            let isVideo = !isAudio && includeVideo && isSupportedVideoFile(url)
            guard isAudio || isVideo else { return }

            let path = url.path
            guard seenPaths.insert(path).inserted else { return }
            guard let values = try? url.resourceValues(forKeys: Set(statKeys)),
                  values.isRegularFile == true else { return }

            let file = LocalDiscoveredMediaFile(
                url: url,
                path: path,
                fileSize: Int64(values.fileSize ?? 0),
                contentModificationDate: values.contentModificationDate
            )

            if isAudio {
                allAudio.append(file)
                pendingAudio.append(file)

                let now = Date().timeIntervalSinceReferenceDate
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
                        for item in contents {
                            processURL(item)
                        }
                    }
                }
            } else {
                processURL(inputURL)
            }
        }

        if !pendingAudio.isEmpty {
            onAudioBatch(pendingAudio)
        }

        return LocalFileDiscoveryResult(audioFiles: allAudio, videoFiles: allVideo)
    }

    public static func discoverMedia(
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

    public static func discoverMediaURLsAsync(
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
            let urls = result.allURLs.sorted {
                $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
            }
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
        let path = url.path
        guard seenPaths.insert(path).inserted else { return }

        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
              values.isRegularFile == true else {
            return
        }

        let file = LocalDiscoveredMediaFile(
            url: url,
            path: path,
            fileSize: Int64(values.fileSize ?? 0),
            contentModificationDate: values.contentModificationDate
        )

        if isSupportedAudioFile(url, includeLegacyWMA: includeLegacyWMA) {
            audioFiles.append(file)
        } else if includeVideo && isSupportedVideoFile(url) {
            videoFiles.append(file)
        }
    }
}
