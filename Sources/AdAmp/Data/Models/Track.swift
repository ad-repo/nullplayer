import Foundation
import AVFoundation

/// Media type for a track (audio or video)
enum MediaType: String, Codable {
    case audio
    case video
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
    
    /// Subsonic song ID for scrobbling (nil for non-Subsonic tracks)
    let subsonicId: String?
    
    /// Subsonic server ID to identify which server the track belongs to
    let subsonicServerId: String?
    
    /// Artwork identifier for casting (Plex thumb path or Subsonic coverArt ID)
    let artworkThumb: String?
    
    /// Media type (audio or video)
    let mediaType: MediaType
    
    /// Genre metadata for Auto EQ
    let genre: String?
    
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
        self.subsonicId = nil     // Local files don't have Subsonic IDs
        self.subsonicServerId = nil
        self.artworkThumb = nil   // Local files use embedded artwork
        
        // Detect media type by checking for video tracks in the asset
        let videoTracks = asset.tracks(withMediaType: .video)
        self.mediaType = videoTracks.isEmpty ? .audio : .video
        self.genre = extractedGenre
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
         subsonicId: String? = nil,
         subsonicServerId: String? = nil,
         artworkThumb: String? = nil,
         mediaType: MediaType = .audio,
         genre: String? = nil) {
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
        self.subsonicId = subsonicId
        self.subsonicServerId = subsonicServerId
        self.artworkThumb = artworkThumb
        self.mediaType = mediaType
        self.genre = genre
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
}

// MARK: - Hashable

extension Track: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
