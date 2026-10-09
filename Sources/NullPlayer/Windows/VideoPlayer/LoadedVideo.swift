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
        /// A server movie or episode: its `Track` carries only the server's id.
        case plexItem(ratingKey: String)
        case jellyfinItem(id: String)
        case embyItem(id: String)
    }

    let source: Source
    let title: String
    /// The film's video track: the main window's artwork lookup, and what a cast sends.
    let track: Track
    /// The play event's content type ("video", "movie", "tv").
    let contentType: String

    var playHistorySource: PlayHistorySource {
        switch source {
        case .stream, .localFile: .local
        case .plexItem: .plex
        case .jellyfinItem: .jellyfin
        case .embyItem: .emby
        }
    }

    /// The server that hears this item's pause, resume, position and stop; nil for local playback.
    var reporter: VideoPlaybackReporting? {
        switch source {
        case .stream, .localFile: nil
        case .plexItem: PlexVideoPlaybackReporter.shared
        case .jellyfinItem: JellyfinVideoPlaybackReporter.shared
        case .embyItem: EmbyVideoPlaybackReporter.shared
        }
    }
}

extension LoadedVideo {
    /// A server film from the playlist, by the id its track carries; nil for a track with none.
    /// It takes its title and content type from that track.
    init?(serverTrack track: Track) {
        let source: Source
        if let ratingKey = track.plexRatingKey { source = .plexItem(ratingKey: ratingKey) }
        else if let id = track.jellyfinId { source = .jellyfinItem(id: id) }
        else if let id = track.embyId { source = .embyItem(id: id) }
        else { return nil }
        self.init(source: source, title: track.displayTitle, track: track,
                  contentType: track.playHistoryContentType)
    }

    /// Tells the film's server it started, which `reporter` then hears the rest of; nothing for
    /// local playback.
    func reportStart() {
        let duration = track.duration ?? 0
        let isEpisode = contentType == "tv"
        switch source {
        case .stream, .localFile:
            break
        case .plexItem(let ratingKey):
            PlexVideoPlaybackReporter.shared.videoTrackDidStart(
                ratingKey: ratingKey, title: title, durationSeconds: duration, isEpisode: isEpisode)
        case .jellyfinItem(let id):
            JellyfinVideoPlaybackReporter.shared.videoTrackDidStart(
                itemId: id, title: title, durationSeconds: duration, isEpisode: isEpisode)
        case .embyItem(let id):
            EmbyVideoPlaybackReporter.shared.videoTrackDidStart(
                itemId: id, title: title, durationSeconds: duration, isEpisode: isEpisode)
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
