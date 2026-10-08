import Foundation
import NullPlayerCore

/// What `VideoPlayerWindowController` has loaded, held as one value so a new item replaces the
/// whole of the previous one and cannot inherit a stale field from it.
struct LoadedVideo {
    /// Where the film comes from, which decides the server that hears its reports and how it is cast.
    enum Source {
        /// A stream with no server behind it and no file on disk.
        case stream
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
    }

    let source: Source
    let title: String
    /// Lightweight video track used by the main window for artwork lookup, and to cast anything
    /// that is not a server movie or episode.
    let artworkTrack: Track?
    /// The play event's content type ("video", "movie", "tv").
    let contentType: String

    var playHistorySource: PlayHistorySource {
        switch source {
        case .stream, .localFile: .local
        case .plexMovie, .plexEpisode, .plexItem: .plex
        case .jellyfinMovie, .jellyfinEpisode, .jellyfinItem: .jellyfin
        case .embyMovie, .embyEpisode, .embyItem: .emby
        }
    }

    /// The server that hears this item's pause, resume, position and stop; nil for local playback.
    var reporter: VideoPlaybackReporting? {
        switch source {
        case .stream, .localFile: nil
        case .plexMovie, .plexEpisode, .plexItem: PlexVideoPlaybackReporter.shared
        case .jellyfinMovie, .jellyfinEpisode, .jellyfinItem: JellyfinVideoPlaybackReporter.shared
        case .embyMovie, .embyEpisode, .embyItem: EmbyVideoPlaybackReporter.shared
        }
    }
}

extension LoadedVideo {
    /// A queued video, which takes its title and content type from its playlist track.
    init(source: Source, queuedTrack track: Track) {
        self.init(source: source, title: track.displayTitle, artworkTrack: track,
                  contentType: track.playHistoryContentType)
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
