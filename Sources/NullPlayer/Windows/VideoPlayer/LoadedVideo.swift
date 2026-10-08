import Foundation
import NullPlayerCore

/// What `VideoPlayerWindowController` has loaded, held as one value so a new item replaces the
/// whole of the previous one and cannot inherit a stale field from it.
enum LoadedVideo {
    /// Nothing, or a stream with no server behind it and no file to cast.
    case none
    /// A local file, which is cast by its URL.
    case localFile(URL)
    case plexMovie(PlexMovie)
    case plexEpisode(PlexEpisode)
    /// A queued video: the `Track` carries only the server's id, not the full movie or episode.
    case plexItem(ratingKey: String)
    case jellyfinMovie(JellyfinMovie)
    case jellyfinEpisode(JellyfinEpisode)
    case jellyfinItem(id: String)
    case embyMovie(EmbyMovie)
    case embyEpisode(EmbyEpisode)
    case embyItem(id: String)

    var playHistorySource: PlayHistorySource {
        switch self {
        case .none, .localFile: .local
        case .plexMovie, .plexEpisode, .plexItem: .plex
        case .jellyfinMovie, .jellyfinEpisode, .jellyfinItem: .jellyfin
        case .embyMovie, .embyEpisode, .embyItem: .emby
        }
    }

    /// The server that hears this item's pause, resume, position and stop; nil for local playback.
    var reporter: VideoPlaybackReporting? {
        switch playHistorySource {
        case .plex: PlexVideoPlaybackReporter.shared
        case .jellyfin: JellyfinVideoPlaybackReporter.shared
        case .emby: EmbyVideoPlaybackReporter.shared
        default: nil
        }
    }
}

/// The playback events every server's video reporter takes in the same shape.
protocol VideoPlaybackReporting: AnyObject {
    func videoDidPause(at position: TimeInterval)
    func videoDidResume(at position: TimeInterval)
    func updatePosition(_ position: TimeInterval)
    func videoDidStop(at position: TimeInterval, finished: Bool)
}

extension PlexVideoPlaybackReporter: VideoPlaybackReporting {}
extension JellyfinVideoPlaybackReporter: VideoPlaybackReporting {}
extension EmbyVideoPlaybackReporter: VideoPlaybackReporting {}
