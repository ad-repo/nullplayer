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
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(resourceKeys),
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
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: Array(resourceKeys),
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
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
              values.isRegularFile == true else { return }

        let path = url.path
        guard seenPaths.insert(path).inserted else { return }

        let discovered = LocalDiscoveredMediaFile(
            url: url,
            path: path,
            fileSize: Int64(values.fileSize ?? 0),
            contentModificationDate: values.contentModificationDate
        )

        if isSupportedAudioFile(url, includeLegacyWMA: includeLegacyWMA) {
            audioFiles.append(discovered)
            return
        }

        if includeVideo && isSupportedVideoFile(url) {
            videoFiles.append(discovered)
        }
    }
}
