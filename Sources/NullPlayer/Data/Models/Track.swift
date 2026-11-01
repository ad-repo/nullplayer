import Foundation
import AVFoundation

/// Media type for a track (audio or video)
enum MediaType: String, Codable, CaseIterable {
    case audio
    case video

    /// The row marker for this media type: a text glyph, so it takes the row's text color.
    var rowMarker: String {
        switch self {
        case .audio: return "♫"
        case .video: return "▶\u{FE0E}"
        }
    }
}

/// The pipeline a track plays through; see `Track.playbackRoute`.
enum PlaybackRoute: String {
    case unresolved  // state-restore placeholder awaiting its streaming URL
    case video       // its own window
    case streaming   // AudioStreaming
    case local       // the local AVAudioEngine graph
}

enum PlayHistorySource: String, CaseIterable, Sendable {
    case local
    case plex
    case subsonic
    case jellyfin
    case emby
    case youtube
    case radio

    var displayName: String {
        switch self {
        case .local: return "Local"
        case .plex: return "Plex"
        case .subsonic: return "Subsonic"
        case .jellyfin: return "Jellyfin"
        case .emby: return "Emby"
        case .youtube: return "YouTube"
        case .radio: return "Radio"
        }
    }

    static func displayName(for rawValue: String) -> String {
        PlayHistorySource(rawValue: rawValue)?.displayName ?? rawValue.capitalized
    }
}

/// Represents a single audio or video track
struct Track: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let title: String
    let artist: String?
    let album: String?
    let duration: TimeInterval?
    let bitrate: Int?
    let sampleRate: Int?
    let channels: Int?
    
    /// Plex rating key for play tracking (nil for local files)
    let plexRatingKey: String?

    /// Plex server ID to identify which server the track belongs to
    let plexServerId: String?
    
    /// Subsonic song ID for scrobbling (nil for non-Subsonic tracks)
    let subsonicId: String?
    
    /// Subsonic server ID to identify which server the track belongs to
    let subsonicServerId: String?
    
    /// Jellyfin item ID for scrobbling (nil for non-Jellyfin tracks)
    let jellyfinId: String?

    /// Jellyfin server ID to identify which server the track belongs to
    let jellyfinServerId: String?

    /// Emby item ID for scrobbling (nil for non-Emby tracks)
    let embyId: String?

    /// Emby server ID to identify which server the track belongs to
    let embyServerId: String?

    /// Artwork identifier (Plex thumb path, Subsonic coverArt ID, or the Jellyfin/Emby item id whose image to show)
    let artworkThumb: String?
    
    /// Media type (audio or video)
    let mediaType: MediaType
    
    /// Genre metadata for Auto EQ
    let genre: String?

    /// Optional override when a generic video track actually represents a more
    /// specific analytics type such as a movie or TV episode.
    let playHistoryContentTypeOverride: String?
    
    /// MIME content type hint for casting (e.g. "audio/flac"). When nil, detected from URL extension.
    let contentType: String?

    /// Start offset within the backing file for cue sheet virtual tracks; nil for normal tracks
    let cueStartOffset: TimeInterval?

    /// End offset within the backing file for cue sheet virtual tracks; nil for last cue track or normal tracks
    let cueEndOffset: TimeInterval?

    /// Originating .cue file URL; nil for normal tracks (used to identify virtual cue tracks)
    let cueSourceURL: URL?

    /// True when this track originated from an internet radio context. Persists across
    /// transient `file://` URLs (e.g., recordings or temp-cached streams) so cast/local
    /// classification stays correct even when the playback URL is local.
    let isRadioOrigin: Bool

    /// True when this track originated from a YouTube download (a downloaded `file://`
    /// audio file). Lets play-history analytics attribute it to the YouTube source
    /// instead of generic local files. See `playHistorySource`.
    let isYouTubeOrigin: Bool

    init(url: URL, isYouTubeOrigin: Bool = false) {
        self.id = UUID()
        self.url = url
        
        // Extract metadata from the audio file
        var extractedTitle = url.deletingPathExtension().lastPathComponent
        var extractedArtist: String?
        var extractedAlbum: String?
        var extractedDuration: TimeInterval?
        var extractedBitrate: Int?
        var extractedSampleRate: Int?
        var extractedChannels: Int?
        var extractedGenre: String?
        
        // Try AVAudioFile first for local files (more reliable for audio format info)
        if url.isFileURL {
            do {
                let audioFile = try AVAudioFile(forReading: url)
                let format = audioFile.processingFormat
                extractedSampleRate = Int(format.sampleRate)
                extractedChannels = Int(format.channelCount)
                if audioFile.length > 0 {
                    extractedDuration = Double(audioFile.length) / format.sampleRate
                }
                
                if let duration = extractedDuration {
                    extractedBitrate = Self.estimatedBitrateKbps(of: url, duration: duration)
                }
            } catch {
                // Log the failure - this file will likely also fail during playback
                NSLog("Track: AVAudioFile failed for '%@': %@ (will try AVAsset fallback)", url.lastPathComponent, error.localizedDescription)
                // Fall through to AVAsset approach
            }
        }
        
        // Use AVAsset to extract metadata (and as fallback for format info)
        let asset = AVAsset(url: url)
        
        // Get duration if not already set
        if extractedDuration == nil {
            let durationTime = asset.duration
            if durationTime.timescale > 0 && !durationTime.seconds.isNaN {
                extractedDuration = CMTimeGetSeconds(durationTime)
            }
        }
        
        // Get audio format properties if not already set
        if extractedSampleRate == nil || extractedChannels == nil {
            let audioTracks = asset.tracks(withMediaType: .audio)
            if let audioTrack = audioTracks.first {
                // Get format descriptions
                let formatDescriptions = audioTrack.formatDescriptions as? [CMFormatDescription]
                if let formatDesc = formatDescriptions?.first {
                    // Get audio stream basic description
                    if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee {
                        if extractedSampleRate == nil {
                            extractedSampleRate = Int(asbd.mSampleRate)
                        }
                        if extractedChannels == nil {
                            extractedChannels = Int(asbd.mChannelsPerFrame)
                        }
                    }
                }
                
                // Estimate bitrate if not set
                if extractedBitrate == nil, let duration = extractedDuration, url.isFileURL {
                    extractedBitrate = Self.estimatedBitrateKbps(of: url, duration: duration)
                }
            }
        }
        
        // Try to get ID3/metadata tags
        let metadataFormats = asset.availableMetadataFormats
        for format in metadataFormats {
            let metadata = asset.metadata(forFormat: format)
            for item in metadata {
                if let commonKey = item.commonKey {
                    switch commonKey {
                    case .commonKeyTitle:
                        if let value = item.stringValue, !value.isEmpty {
                            extractedTitle = value
                        }
                    case .commonKeyArtist:
                        if let value = item.stringValue, !value.isEmpty {
                            extractedArtist = value
                        }
                    case .commonKeyAlbumName:
                        if let value = item.stringValue, !value.isEmpty {
                            extractedAlbum = value
                        }
                    default:
                        break
                    }
                }
                // Also check for genre in ID3 metadata (not exposed via commonKey)
                if let key = item.key as? String, (key == "TCON" || key == "©gen") {
                    if let value = item.stringValue, !value.isEmpty {
                        extractedGenre = value
                    }
                }
            }
        }
        
        self.title = extractedTitle
        self.artist = extractedArtist
        self.album = extractedAlbum
        self.duration = extractedDuration
        self.bitrate = extractedBitrate
        self.sampleRate = extractedSampleRate
        self.channels = extractedChannels
        self.plexRatingKey = nil  // Local files don't have Plex rating keys
        self.plexServerId = nil
        self.subsonicId = nil     // Local files don't have Subsonic IDs
        self.subsonicServerId = nil
        self.jellyfinId = nil     // Local files don't have Jellyfin IDs
        self.jellyfinServerId = nil
        self.embyId = nil         // Local files don't have Emby IDs
        self.embyServerId = nil
        self.artworkThumb = nil   // Local files use embedded artwork
        
        // Detect media type by checking for video tracks in the asset, falling back to the
        // file extension. AVFoundation can't parse containers like .mkv/.avi/.webm (the reason
        // the app uses VLCKit for playback), so asset.tracks(withMediaType:) returns empty for
        // them — without the extension fallback those files get misrouted to the audio engine.
        let videoTracks = asset.tracks(withMediaType: .video)
        self.mediaType = (!videoTracks.isEmpty || AudioFileValidator.isVideoFile(url: url)) ? .video : .audio
        self.genre = extractedGenre
        self.playHistoryContentTypeOverride = nil
        self.contentType = nil  // Local files use URL extension detection
        self.cueStartOffset = nil
        self.cueEndOffset = nil
        self.cueSourceURL = nil
        self.isRadioOrigin = false
        self.isYouTubeOrigin = isYouTubeOrigin
    }

    /// Fast path for bulk imports: avoid AVFoundation metadata parsing up-front.
    init(lightweightURL url: URL) {
        self.id = UUID()
        self.url = url
        self.title = url.deletingPathExtension().lastPathComponent
        self.artist = nil
        self.album = nil
        self.duration = nil
        self.bitrate = nil
        self.sampleRate = nil
        self.channels = nil
        self.plexRatingKey = nil
        self.plexServerId = nil
        self.subsonicId = nil
        self.subsonicServerId = nil
        self.jellyfinId = nil
        self.jellyfinServerId = nil
        self.embyId = nil
        self.embyServerId = nil
        self.artworkThumb = nil
        self.mediaType = AudioFileValidator.isVideoFile(url: url) ? .video : .audio
        self.genre = nil
        self.playHistoryContentTypeOverride = nil
        self.contentType = nil
        self.cueStartOffset = nil
        self.cueEndOffset = nil
        self.cueSourceURL = nil
        self.isRadioOrigin = false
        self.isYouTubeOrigin = false
    }

    init(id: UUID = UUID(),
         url: URL,
         title: String,
         artist: String? = nil,
         album: String? = nil,
         duration: TimeInterval? = nil,
         bitrate: Int? = nil,
         sampleRate: Int? = nil,
         channels: Int? = nil,
         plexRatingKey: String? = nil,
         plexServerId: String? = nil,
         subsonicId: String? = nil,
         subsonicServerId: String? = nil,
         jellyfinId: String? = nil,
         jellyfinServerId: String? = nil,
         embyId: String? = nil,
         embyServerId: String? = nil,
         artworkThumb: String? = nil,
         mediaType: MediaType = .audio,
         genre: String? = nil,
         playHistoryContentTypeOverride: String? = nil,
         contentType: String? = nil,
         cueStartOffset: TimeInterval? = nil,
         cueEndOffset: TimeInterval? = nil,
         cueSourceURL: URL? = nil,
         isRadioOrigin: Bool = false,
         isYouTubeOrigin: Bool = false) {
        self.id = id
        self.url = url
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.bitrate = bitrate
        self.sampleRate = sampleRate
        self.channels = channels
        self.plexRatingKey = plexRatingKey
        self.plexServerId = plexServerId
        self.subsonicId = subsonicId
        self.subsonicServerId = subsonicServerId
        self.jellyfinId = jellyfinId
        self.jellyfinServerId = jellyfinServerId
        self.embyId = embyId
        self.embyServerId = embyServerId
        self.artworkThumb = artworkThumb
        self.mediaType = mediaType
        self.genre = genre
        self.playHistoryContentTypeOverride = playHistoryContentTypeOverride
        self.contentType = contentType
        self.cueStartOffset = cueStartOffset
        self.cueEndOffset = cueEndOffset
        self.cueSourceURL = cueSourceURL
        self.isRadioOrigin = isRadioOrigin
        self.isYouTubeOrigin = isYouTubeOrigin
    }
    
    /// Display title (artist - title or just title)
    /// Sanitizes newlines and control characters for proper display
    var displayTitle: String {
        let result: String
        if let artist = artist, !artist.isEmpty {
            result = "\(artist) - \(title)"
        } else {
            result = title
        }
        // Remove newlines and other control characters that break playlist display
        return result.replacingOccurrences(of: "\n", with: " ")
                     .replacingOccurrences(of: "\r", with: " ")
                     .replacingOccurrences(of: "\t", with: " ")
    }

    /// The title a playlist row draws: a video is marked with its glyph, audio is not.
    var playlistTitle: String {
        mediaType == .video ? "\(mediaType.rowMarker) \(displayTitle)" : displayTitle
    }
    
    /// Formatted duration string (MM:SS)
    var formattedDuration: String {
        guard let duration = duration else { return "--:--" }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// What a file's own header says about it — everything `init(lightweightURL:)` leaves out to
    /// keep a bulk import fast, and the engine fills in afterwards.
    struct Format: Sendable {
        var duration: TimeInterval?
        var bitrate: Int?
        var sampleRate: Int?
        var channels: Int?

        /// Read from a local file, off the main thread. MPEG-4 Opus can fail to open natively or
        /// report zero frames; its asset still has the duration, and when the file would not open at
        /// all, the audio track's own sample rate and channels — without them the row would lack its
        /// format for good and be read again at every load.
        static func read(from url: URL) async -> Format {
            let file = try? AVAudioFile(forReading: url)
            var duration = file.map { Double($0.length) / $0.processingFormat.sampleRate } ?? 0
            var sampleRate = file.map { Int($0.processingFormat.sampleRate) }
            var channels = file.map { Int($0.processingFormat.channelCount) }
            if duration <= 0, LocalAudioFile.mayNeedFallbackDecode(url) {
                let asset = AVURLAsset(url: url)
                duration = (try? await asset.load(.duration).seconds) ?? 0
                if file == nil,
                   let track = try? await asset.loadTracks(withMediaType: .audio).first,
                   let description = try? await track.load(.formatDescriptions).first,
                   let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee {
                    sampleRate = Int(asbd.mSampleRate)
                    channels = Int(asbd.mChannelsPerFrame)
                }
            }
            return Format(duration: duration > 0 ? duration : nil,
                          bitrate: Track.estimatedBitrateKbps(of: url, duration: duration),
                          sampleRate: sampleRate, channels: channels)
        }
    }

    /// True while any field of `Format` is still unknown (a zero duration counts as unknown).
    var lacksFormat: Bool {
        (duration ?? 0) == 0 || bitrate == nil || sampleRate == nil || channels == nil
    }

    /// A copy with each unknown `Format` field taken from `format`; a field already known wins.
    func filling(_ format: Format) -> Track {
        Track(id: id, url: url, title: title, artist: artist, album: album,
              duration: (duration ?? 0) > 0 ? duration : format.duration,
              bitrate: bitrate ?? format.bitrate, sampleRate: sampleRate ?? format.sampleRate,
              channels: channels ?? format.channels,
              plexRatingKey: plexRatingKey, plexServerId: plexServerId,
              subsonicId: subsonicId, subsonicServerId: subsonicServerId,
              jellyfinId: jellyfinId, jellyfinServerId: jellyfinServerId,
              embyId: embyId, embyServerId: embyServerId, artworkThumb: artworkThumb,
              mediaType: mediaType, genre: genre,
              playHistoryContentTypeOverride: playHistoryContentTypeOverride,
              contentType: contentType, cueStartOffset: cueStartOffset, cueEndOffset: cueEndOffset,
              cueSourceURL: cueSourceURL, isRadioOrigin: isRadioOrigin, isYouTubeOrigin: isYouTubeOrigin)
    }

    /// The average bitrate a local file of this duration works out to, in kbps.
    static func estimatedBitrateKbps(of url: URL, duration: TimeInterval) -> Int? {
        guard duration > 0,
              let fileSize = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int
        else { return nil }
        return Int(Double(fileSize * 8) / duration / 1000)
    }

    /// True when this row is a state-restore placeholder awaiting URL refresh.
    var isStreamingPlaceholder: Bool {
        url.absoluteString == "about:blank"
    }

    /// Where `AudioEngine.loadTrack` sends this track. Paths that bypass `loadTrack` (gapless,
    /// Sweet Fades, graph-recovery gating) ask this too, so they cannot disagree with it.
    var playbackRoute: PlaybackRoute {
        if isStreamingPlaceholder { return .unresolved }
        if mediaType == .video { return .video }
        return url.scheme == "http" || url.scheme == "https" ? .streaming : .local
    }

    /// True when this track is a virtual cue sheet track (originated from .cue parsing)
    var isCueTrack: Bool {
        cueSourceURL != nil
    }

    /// True when this track is an internet radio stream. Honors the explicit
    /// `isRadioOrigin` flag (set at radio track creation) so radio tracks are
    /// correctly classified even when their playback URL is `file://` (e.g.,
    /// recordings or temp-cached streams). Falls back to the legacy heuristic
    /// for tracks constructed without the flag.
    var isRadioStream: Bool {
        if isRadioOrigin { return true }
        return plexRatingKey == nil &&
            subsonicId == nil &&
            jellyfinId == nil &&
            embyId == nil &&
            !url.isFileURL
    }

    /// True when this track has enough persisted service identity to be refreshed by ID.
    var isResolvableStreamingServiceTrack: Bool {
        if plexRatingKey != nil { return true }
        if subsonicId != nil && subsonicServerId != nil { return true }
        if jellyfinId != nil && jellyfinServerId != nil { return true }
        if embyId != nil && embyServerId != nil { return true }
        return false
    }

    /// Stable identity for retry guards across refreshed Track instances.
    var streamingServiceIdentity: String? {
        if let plexRatingKey {
            return "plex:\(plexServerId ?? ""):\(plexRatingKey)"
        }
        if let subsonicId {
            return "subsonic:\(subsonicServerId ?? ""):\(subsonicId)"
        }
        if let jellyfinId {
            return "jellyfin:\(jellyfinServerId ?? ""):\(jellyfinId)"
        }
        if let embyId {
            return "emby:\(embyServerId ?? ""):\(embyId)"
        }
        return nil
    }

    var playHistorySource: PlayHistorySource {
        if plexRatingKey != nil { return .plex }
        if subsonicId != nil { return .subsonic }
        if jellyfinId != nil { return .jellyfin }
        if embyId != nil { return .emby }
        if isRadioOrigin { return .radio }
        if !url.isFileURL { return .radio }
        // Either the explicit origin flag (set when played from the YouTube list) or the
        // file living under the YouTube download folder (covers downloads played from the
        // Library Browser, or restored from a saved state that predates the flag).
        if isYouTubeOrigin || YouTubeManager.isWithinDownloadRoot(url) { return .youtube }
        return .local
    }

    var playHistoryContentType: String {
        if let playHistoryContentTypeOverride {
            return playHistoryContentTypeOverride
        }
        if playHistorySource == .radio { return "radio" }
        if mediaType == .video { return "video" }
        return "music"
    }

    var playHistoryTrackIdentifier: String? {
        switch playHistorySource {
        case .plex:
            return plexRatingKey
        case .subsonic:
            return subsonicId
        case .jellyfin:
            return jellyfinId
        case .emby:
            return embyId
        case .local, .radio, .youtube:
            return nil
        }
    }
}

// MARK: - Hashable

extension Track: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
