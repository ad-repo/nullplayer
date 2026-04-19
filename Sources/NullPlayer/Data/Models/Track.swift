import Foundation
import AVFoundation

/// Media type for a track (audio or video)
enum MediaType: String, Codable {
    case audio
    case video
}

enum PlayHistorySource: String, CaseIterable, Sendable {
    case local
    case plex
    case subsonic
    case jellyfin
    case emby
    case radio

    var displayName: String {
        switch self {
        case .local: return "Local"
        case .plex: return "Plex"
        case .subsonic: return "Subsonic"
        case .jellyfin: return "Jellyfin"
        case .emby: return "Emby"
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

    /// Artwork identifier for casting (Plex thumb path or Subsonic coverArt ID)
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
    
    init(url: URL) {
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
                extractedDuration = Double(audioFile.length) / format.sampleRate
                
                // Estimate bitrate from file size and duration
                if let duration = extractedDuration, duration > 0 {
                    if let fileSize = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int {
                        // Bitrate = (file size in bits) / duration in seconds
                        let bitrateInBps = Double(fileSize * 8) / duration
                        extractedBitrate = Int(bitrateInBps / 1000)  // Convert to kbps
                    }
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
                if extractedBitrate == nil, let duration = extractedDuration, duration > 0, url.isFileURL {
                    if let fileSize = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int {
                        let bitrateInBps = Double(fileSize * 8) / duration
                        extractedBitrate = Int(bitrateInBps / 1000)
                    }
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
        
        // Detect media type by checking for video tracks in the asset
        let videoTracks = asset.tracks(withMediaType: .video)
        self.mediaType = videoTracks.isEmpty ? .audio : .video
        self.genre = extractedGenre
        self.playHistoryContentTypeOverride = nil
        self.contentType = nil  // Local files use URL extension detection
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
         contentType: String? = nil) {
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
    
    /// Formatted duration string (MM:SS)
    var formattedDuration: String {
        guard let duration = duration else { return "--:--" }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// True when this row is a state-restore placeholder awaiting URL refresh.
    var isStreamingPlaceholder: Bool {
        url.absoluteString == "about:blank"
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
        if !url.isFileURL { return .radio }
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
        case .local, .radio:
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
