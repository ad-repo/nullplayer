import Foundation

/// The library's track verbs, as their menus title them, with the engine calls the browsers'
/// local-track handlers make. The seed of one shared play menu for every source (MISC_TASKS M2).
enum TrackVerb: CaseIterable {
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

    /// Whether the verb replaces what is playing, so a newer one supersedes it.
    var startsPlayback: Bool { self == .play || self == .playAndReplaceQueue }

    @MainActor
    func perform(_ tracks: [Track]) {
        let engine = WindowManager.shared.audioEngine
        switch self {
        case .play: engine.playNow(tracks)
        case .playAndReplaceQueue: engine.loadTracks(tracks)
        case .addToPlaylist: engine.appendTracks(tracks)
        case .playNext: engine.insertTracksAfterCurrent(tracks)
        case .addToQueue:
            let wasEmpty = engine.playlist.isEmpty
            engine.appendTracks(tracks)
            if wasEmpty { engine.playTrack(at: 0) }
        }
    }
}
