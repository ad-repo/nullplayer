import AppKit

/// A YouTube video row's actions, shared by both library browsers: **Audio ▸** and **Video ▸**
/// submenus carrying the library's track verbs, each fetching that form of the video first
/// when it isn't on disk, then Show in Finder and Remove Audio / Video File. Double-click and
/// Enter (`activate`) play the one form on disk, or else pop the same menu, so nothing is
/// fetched or picked without a choice.
@MainActor
final class YouTubeVideoActions: NSObject {
    private let search: YouTubeChannelSearch
    /// In-flight downloads by video and kind. A repeat request for one awaits it rather than
    /// running a second yt-dlp onto the same file.
    private var fetches: [YouTubeDownload.Key: Task<URL, Error>] = [:]
    /// Bumped by `cancel()`: a verb still waiting on a fetch from an older epoch is dropped.
    private var epoch = 0

    /// A download started or finished: the row spinners changed.
    var onFetchesChanged: (() -> Void)?
    /// A file landed or was removed: the rows' downloaded state changed.
    var onFilesChanged: (() -> Void)?

    init(search: YouTubeChannelSearch) {
        self.search = search
    }

    func isFetching(_ videoId: String) -> Bool {
        fetches.keys.contains { $0.videoId == videoId }
    }

    var hasFetchesInFlight: Bool { !fetches.isEmpty }

    /// Drop the waiting verbs. A running download still finishes and is recorded.
    func cancel() {
        epoch += 1
    }

    // MARK: - Menu

    func addMenuItems(for video: YouTubeVideo, to menu: NSMenu) {
        for kind in MediaType.allCases {
            let submenu = NSMenu()
            TrackVerb.addMenuItems(to: submenu) { [weak self] in
                guard let self else { throw CancellationError() }
                return try await self.tracks(for: video, kind: kind)
            }
            let kindItem = NSMenuItem(title: kind.displayName, action: nil, keyEquivalent: "")
            kindItem.submenu = submenu
            menu.addItem(kindItem)
        }

        let files = YouTubeManager.shared.downloadedFiles(for: video.videoId)
        // The audio download only: video has no local graph to run a profile in, and assigning
        // never starts a download.
        if let audioFile = files[.audio] {
            EQProfileMenu.addAssignItem(to: menu, level: .track, tracks: [Track(url: audioFile, isYouTubeOrigin: true)])
        } else {
            EQProfileMenu.addUnavailableItem(to: menu, level: .track, reason: "Download the audio first")
        }
        guard !files.isEmpty else { return }
        menu.addItem(.separator())
        let finderItem = NSMenuItem(title: "Show in Finder", action: #selector(showInFinder(_:)), keyEquivalent: "")
        finderItem.target = self; finderItem.representedObject = Array(files.values)
        menu.addItem(finderItem)
        for kind in MediaType.allCases where files[kind] != nil {
            let removeItem = NSMenuItem(title: "Remove \(kind.displayName) File", action: #selector(removeFile(_:)), keyEquivalent: "")
            removeItem.target = self; removeItem.representedObject = YouTubeDownload.Key(videoId: video.videoId, kind: kind)
            menu.addItem(removeItem)
        }
    }

    /// Double-click and Enter: a video with one form on disk plays it; one with both, or
    /// neither, pops the row menu at the mouse location.
    func activate(_ video: YouTubeVideo, in view: NSView) {
        if let kind = Self.formToPlay(YouTubeManager.shared.downloadedFiles(for: video.videoId)) {
            TrackVerb.play.run { try await self.tracks(for: video, kind: kind) }
            return
        }
        let menu = NSMenu()
        addMenuItems(for: video, to: menu)
        let location = view.convert(view.window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)
        menu.popUp(positioning: nil, at: location, in: view)
    }

    /// The form `activate` plays: the only one on disk. nil — pop the menu — for both or neither.
    nonisolated static func formToPlay(_ files: [MediaType: URL]) -> MediaType? {
        files.count == 1 ? files.keys.first : nil
    }

    @objc private func showInFinder(_ sender: NSMenuItem) {
        guard let urls = sender.representedObject as? [URL] else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    @objc private func removeFile(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? YouTubeDownload.Key else { return }
        YouTubeManager.shared.removeDownload(key)
        onFilesChanged?()
    }

    // MARK: - Verbs

    /// The form on disk, or fetched first. A fetch outliving `cancel()` resolves to nothing.
    private func tracks(for video: YouTubeVideo, kind: MediaType) async throws -> [Track] {
        if let url = YouTubeManager.shared.downloadedFiles(for: video.videoId)[kind] {
            return [Track(url: url, isYouTubeOrigin: true)]
        }
        let epoch = self.epoch
        let url = try await fetch(video, kind: kind).value
        guard self.epoch == epoch else { throw CancellationError() }
        return [Track(url: url, isYouTubeOrigin: true)]
    }

    private func fetch(_ video: YouTubeVideo, kind: MediaType) -> Task<URL, Error> {
        let key = YouTubeDownload.Key(videoId: video.videoId, kind: kind)
        if let existing = fetches[key] { return existing }
        let channelTitle = search.channelTitle(forVideo: video)
        let task = Task { [weak self] in
            defer { self?.fetches[key] = nil; self?.onFetchesChanged?() }
            do {
                let url = try await YouTubeManager.shared.download(video: video, kind: kind, channelTitle: channelTitle)
                self?.onFilesChanged?()
                return url
            } catch {
                NSLog("Failed to download YouTube %@: %@", kind.rawValue, error.localizedDescription.redactingSensitiveURLQueryItems)
                throw error
            }
        }
        fetches[key] = task
        onFetchesChanged?()
        return task
    }
}
