import Foundation

/// Files, folders or cue sheets dropped on a window that plays them: whether a drop holds
/// any, and the tracks it stands for. What a window then does with the tracks (append and play,
/// replace the queue) is its own.
enum PlaylistDrop {
    /// Whether a drop holds anything playable: media, folders, cue sheets.
    private static func accepts(_ urls: [URL]) -> Bool {
        urls.contains { $0.pathExtension.lowercased() == "cue" } || LocalFileDiscovery.hasSupportedDropContent(urls, includeVideo: true)
    }

    /// The tracks the drop names itself: each cue sheet's, and each audio file's (one with a cue sheet
    /// beside it, the sheet's), each sheet once, so a `.cue` and its audio dropped together add the
    /// album once. Reads the files on the caller's thread: a drop's, the main thread.
    static func namedTracks(_ urls: [URL]) -> [Track] {
        var tracks: [Track] = []
        var cueSources = Set<String>()
        func appendCue(_ expanded: [Track]) {
            guard !expanded.isEmpty else { return }
            if let source = expanded.first?.cueSourceURL?.standardizedFileURL.path, !cueSources.insert(source).inserted { return }
            tracks.append(contentsOf: expanded)
        }
        for url in urls {
            let ext = url.pathExtension.lowercased()
            if ext == "cue" {
                if let expanded = AudioEngine.tracksForCueOrSibling(url: url) { appendCue(expanded) }
            } else if AudioFileValidator.supportedExtensions.contains(ext) {
                if let expanded = AudioEngine.tracksForCueOrSibling(url: url), !expanded.isEmpty {
                    appendCue(expanded)
                } else {
                    tracks.append(Track(url: url))
                }
            }
        }
        return tracks
    }

    /// The tracks a Finder open hands the app (`application(_:openFiles:)`): what `namedTracks` takes,
    /// then each video file and each playlist file's entries. Finder hands files, never folders, so
    /// nothing is searched and the tracks are ready at once, which a cold open needs: they must be
    /// parked before launch finishes, or the restored session plays instead.
    static func openedTracks(_ urls: [URL]) -> [Track] {
        namedTracks(urls) + urls.flatMap { url -> [Track] in
            if LocalFileDiscovery.isSupportedVideoFile(url) { return [Track(url: url)] }
            if LocalFileDiscovery.isSupportedPlaylistFile(url) { return LibraryPlayable.tracks(inPlaylistFile: url) }
            return []
        }
    }

    /// Takes a drop: false when it holds nothing playable. True means the drop was taken, not that it
    /// yields tracks: the tracks it names itself (`namedTracks`), then the media found in its other
    /// items, folders searched off the main thread, without the ones it named already. Call it on the
    /// main thread, as a drop arrives: `deliver` runs there once, with no tracks when the search found
    /// none; a drop of cue sheets alone is delivered at once, on the caller's thread, and not at all
    /// when they name no tracks.
    static func gather(_ urls: [URL], deliver: @escaping ([Track]) -> Void) -> Bool {
        guard accepts(urls) else { return false }
        let named = namedTracks(urls)
        let others = urls.filter { $0.pathExtension.lowercased() != "cue" }
        guard !others.isEmpty else {
            if !named.isEmpty { deliver(named) }
            return true
        }
        LocalFileDiscovery.discoverMediaURLsAsync(from: others, includeVideo: true) { found in
            let taken = Set(named.map(\.url))
            deliver(named + found.filter { !taken.contains($0) }.map { Track(url: $0) })
        }
        return true
    }
}
