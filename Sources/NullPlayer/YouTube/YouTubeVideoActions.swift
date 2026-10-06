import AppKit

/// A YouTube video row's actions, shared by both library browsers: **Audio ▸** and **Video ▸**
/// submenus carrying the library's track verbs, each fetching that form of the video first
/// when it isn't on disk, then Show in Finder and Remove Audio / Video File. Double-click and
/// Enter pop the same menu, so nothing is fetched without a choice.
@MainActor
final class YouTubeVideoActions: NSObject {
    private let search: YouTubeChannelSearch
    /// In-flight downloads by video and kind. A repeat request for one awaits it rather than
    /// running a second yt-dlp onto the same file.
    private var fetches: [YouTubeDownload.Key: Task<URL, Error>] = [:]
    /// Verbs waiting on a fetch, cancelled at teardown.
    private var pendingVerbs: [UUID: Task<Void, Never>] = [:]
    /// The waiting play verb, if any: a newer play supersedes it, so a stale result never
    /// starts playing.
    private var pendingPlay: UUID?

    /// Fired when a fetch starts or finishes, or a file is removed.
    var onChange: (() -> Void)?

    init(search: YouTubeChannelSearch) {
        self.search = search
    }

    func isFetching(_ videoId: String) -> Bool {
        fetches.keys.contains { $0.videoId == videoId }
    }

    var hasFetchesInFlight: Bool { !fetches.isEmpty }

    /// Cancel the waiting verbs. A running download still finishes and is recorded.
    func cancel() {
        pendingVerbs.values.forEach { $0.cancel() }
        pendingVerbs = [:]; pendingPlay = nil
    }

    // MARK: - Menu

    func addMenuItems(for video: YouTubeVideo, to menu: NSMenu) {
        for kind in YouTubeMediaKind.allCases {
            let submenu = NSMenu()
            for verb in Verb.allCases {
                let item = NSMenuItem(title: verb.title, action: #selector(performVerb(_:)), keyEquivalent: "")
                item.target = self; item.representedObject = VerbRequest(video: video, kind: kind, verb: verb)
                submenu.addItem(item)
            }
            let kindItem = NSMenuItem(title: kind.title, action: nil, keyEquivalent: "")
            kindItem.submenu = submenu
            menu.addItem(kindItem)
        }

        let files = YouTubeManager.shared.downloadedFiles(for: video.videoId)
        guard !files.isEmpty else { return }
        menu.addItem(.separator())
        let finderItem = NSMenuItem(title: "Show in Finder", action: #selector(showInFinder(_:)), keyEquivalent: "")
        finderItem.target = self; finderItem.representedObject = Array(files.values)
        menu.addItem(finderItem)
        for kind in YouTubeMediaKind.allCases where files[kind] != nil {
            let removeItem = NSMenuItem(title: "Remove \(kind.title) File", action: #selector(removeFile(_:)), keyEquivalent: "")
            removeItem.target = self; removeItem.representedObject = YouTubeDownload.Key(videoId: video.videoId, kind: kind)
            menu.addItem(removeItem)
        }
    }

    /// The row menu at the mouse location, for double-click and Enter.
    func popUpMenu(for video: YouTubeVideo, in view: NSView) {
        let menu = NSMenu()
        addMenuItems(for: video, to: menu)
        let location = view.convert(view.window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)
        menu.popUp(positioning: nil, at: location, in: view)
    }

    @objc private func performVerb(_ sender: NSMenuItem) {
        guard let request = sender.representedObject as? VerbRequest else { return }
        perform(request.verb, video: request.video, kind: request.kind)
    }

    @objc private func showInFinder(_ sender: NSMenuItem) {
        guard let urls = sender.representedObject as? [URL] else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    @objc private func removeFile(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? YouTubeDownload.Key else { return }
        YouTubeManager.shared.removeDownload(videoId: key.videoId, kind: key.kind)
        onChange?()
    }

    // MARK: - Verbs

    private struct VerbRequest {
        let video: YouTubeVideo
        let kind: YouTubeMediaKind
        let verb: Verb
    }

    /// The library's track verbs, with the engine calls its local-track handlers make.
    private enum Verb: CaseIterable {
        case play, playAndReplaceQueue, addToPlaylist, playNext, addToQueue

        var title: String {
            switch self {
            case .play: return "Play"
            case .playAndReplaceQueue: return "Play and Replace Queue"
            case .addToPlaylist: return "Add to Playlist"
            case .playNext: return "Play Next"
            case .addToQueue: return "Add to Queue"
            }
        }

        var startsPlayback: Bool { self == .play || self == .playAndReplaceQueue }

        func perform(_ track: Track) {
            let engine = WindowManager.shared.audioEngine
            switch self {
            case .play: engine.playNow([track])
            case .playAndReplaceQueue: engine.loadTracks([track])
            case .addToPlaylist: engine.appendTracks([track])
            case .playNext: engine.insertTracksAfterCurrent([track])
            case .addToQueue:
                let wasEmpty = engine.playlist.isEmpty
                engine.appendTracks([track])
                if wasEmpty { engine.playTrack(at: 0) }
            }
        }
    }

    private func perform(_ verb: Verb, video: YouTubeVideo, kind: YouTubeMediaKind) {
        if verb.startsPlayback, let previous = pendingPlay {
            pendingVerbs.removeValue(forKey: previous)?.cancel()
            pendingPlay = nil
        }
        if let url = YouTubeManager.shared.downloadedFiles(for: video.videoId)[kind] {
            verb.perform(Track(url: url, isYouTubeOrigin: true))
            return
        }
        let fetch = fetch(video, kind: kind)
        let id = UUID()
        pendingVerbs[id] = Task { [weak self] in
            defer {
                self?.pendingVerbs[id] = nil
                if self?.pendingPlay == id { self?.pendingPlay = nil }
            }
            // A failed fetch is logged where it runs; a cancelled verb does nothing.
            guard let url = try? await fetch.value, !Task.isCancelled else { return }
            verb.perform(Track(url: url, isYouTubeOrigin: true))
        }
        if verb.startsPlayback { pendingPlay = id }
    }

    private func fetch(_ video: YouTubeVideo, kind: YouTubeMediaKind) -> Task<URL, Error> {
        let key = YouTubeDownload.Key(videoId: video.videoId, kind: kind)
        if let existing = fetches[key] { return existing }
        let channelTitle = search.channelTitle(forVideo: video)
        let task = Task { [weak self] in
            defer { self?.fetches[key] = nil; self?.onChange?() }
            do {
                return try await YouTubeManager.shared.download(video: video, kind: kind, channelTitle: channelTitle)
            } catch {
                NSLog("Failed to download YouTube %@: %@", kind.rawValue, error.localizedDescription.redactingSensitiveURLQueryItems)
                throw error
            }
        }
        fetches[key] = task
        onChange?()
        return task
    }
}

private extension YouTubeMediaKind {
    var title: String {
        switch self {
        case .audio: return "Audio"
        case .video: return "Video"
        }
    }
}
