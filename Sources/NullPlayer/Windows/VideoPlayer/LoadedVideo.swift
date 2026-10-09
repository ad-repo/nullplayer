import Foundation
import NullPlayerCore

/// What `VideoPlayerWindowController` has loaded, held as one value so a new item replaces the
/// whole of the previous one and cannot inherit a stale field from it.
struct LoadedVideo {
    /// The media server a film is played from.
    enum Server {
        case plex, jellyfin, emby

        /// The server's reporter, which hears the film's start, pause, resume, position and stop.
        var reporter: VideoPlaybackReporting {
            switch self {
            case .plex: PlexVideoPlaybackReporter.shared
            case .jellyfin: JellyfinVideoPlaybackReporter.shared
            case .emby: EmbyVideoPlaybackReporter.shared
            }
        }

        var playHistorySource: PlayHistorySource {
            switch self {
            case .plex: .plex
            case .jellyfin: .jellyfin
            case .emby: .emby
            }
        }
    }

    /// Where the film comes from, which decides the server that hears its reports and how it is cast.
    enum Source {
        /// A stream with no server behind it and no file on disk.
        case stream
        case localFile(URL)
        /// A server movie or episode: its `Track` carries only the server's id (a Plex rating key).
        case serverItem(Server, id: String)
    }

    let source: Source
    let title: String
    /// The film's video track: the main window's artwork lookup, and what a cast sends.
    let track: Track
    /// The play event's content type ("video", "movie", "tv").
    let contentType: String

    var playHistorySource: PlayHistorySource {
        guard case .serverItem(let server, _) = source else { return .local }
        return server.playHistorySource
    }

    /// The server that hears this item's pause, resume, position and stop; nil for local playback.
    var reporter: VideoPlaybackReporting? {
        guard case .serverItem(let server, _) = source else { return nil }
        return server.reporter
    }
}

extension LoadedVideo {
    /// A server film from the playlist, by the id its track carries; nil for a track with none.
    /// It takes its title and content type from that track.
    init?(serverTrack track: Track) {
        let server: Server, id: String
        if let ratingKey = track.plexRatingKey { (server, id) = (.plex, ratingKey) }
        else if let jellyfinId = track.jellyfinId { (server, id) = (.jellyfin, jellyfinId) }
        else if let embyId = track.embyId { (server, id) = (.emby, embyId) }
        else { return nil }
        self.init(source: .serverItem(server, id: id), title: track.displayTitle, track: track,
                  contentType: track.playHistoryContentType)
    }

    /// Tells the film's server it started, which `reporter` then hears the rest of; nothing for
    /// local playback.
    func reportStart() {
        guard case .serverItem(let server, let id) = source else { return }
        server.reporter.videoTrackDidStart(itemId: id, title: title, durationSeconds: track.duration ?? 0,
                                           isEpisode: contentType == "tv")
    }
}

/// The playback events every server's video reporter takes in the same shape.
protocol VideoPlaybackReporting: AnyObject {
    func videoTrackDidStart(itemId: String, title: String, durationSeconds: TimeInterval, isEpisode: Bool)
    func videoDidPause(at position: TimeInterval)
    func videoDidResume(at position: TimeInterval)
    func updatePosition(_ position: TimeInterval)
    func videoDidStop(at position: TimeInterval, finished: Bool)
}

extension PlexVideoPlaybackReporter: VideoPlaybackReporting {}
extension JellyfinVideoPlaybackReporter: VideoPlaybackReporting {}
extension EmbyVideoPlaybackReporter: VideoPlaybackReporting {}
