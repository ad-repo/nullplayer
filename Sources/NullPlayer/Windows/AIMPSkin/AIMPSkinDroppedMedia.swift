import Foundation

/// Files, folders, playlists or cue sheets dropped on any of the skin's windows: whether a drop holds
/// any, and adding them. AIMP's own copy of what the classic and Modern main and playlist windows
/// each do on a drop (the AIMP guide § *Shared code*).
@MainActor
enum AIMPSkinDroppedMedia {
    /// Whether a drop holds anything the playlist takes: media, folders, playlists, cue sheets.
    nonisolated static func accepts(_ urls: [URL]) -> Bool {
        urls.contains { $0.pathExtension.lowercased() == "cue" } || LocalFileDiscovery.hasSupportedDropContent(urls, includeVideo: true)
    }

    /// Adds dropped files to the end of the playlist and plays the first of them, as the classic main
    /// and playlist windows' own copies of this do: a cue sheet (or one beside an audio file) expands into
    /// its tracks once, and folders and playlists are searched for media. Cue sheets are read, and
    /// folders searched, off the main thread; the tracks are added on it when found.
    static func appendAndPlay(_ urls: [URL], engine: AudioEngine) -> Bool {
        guard accepts(urls) else { return false }
        func add(_ added: [Track]) {
            let first = engine.playlist.count
            engine.appendTracks(added)
            if first < engine.playlist.count { engine.playTrack(at: first) }
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let tracks = files(urls)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let others = urls.filter { $0.pathExtension.lowercased() != "cue" }
                    guard !others.isEmpty else {
                        if !tracks.isEmpty { add(tracks) }
                        return
                    }
                    LocalFileDiscovery.discoverMediaURLsAsync(from: others, includeVideo: true) { found in
                        let expanded = Set(tracks.map(\.url))
                        add(tracks + found.filter { !expanded.contains($0) }.map { Track(url: $0) })
                    }
                }
            }
        }
        return true
    }

    /// The dropped cue sheets' tracks and the audio files' (a file with a cue sheet beside it, the
    /// sheet's), each sheet once. Reads the files: off the main thread.
    nonisolated private static func files(_ urls: [URL]) -> [Track] {
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
                if let expanded = AudioEngine.tracksForCueOrSibling(url: url), !expanded.isEmpty { appendCue(expanded) } else { tracks.append(Track(url: url)) }
            }
        }
        return tracks
    }
}
