import AppKit
import AVFoundation

// MARK: - Menu Actions

/// Singleton to handle menu actions — extracted from ContextMenuBuilder
/// to keep each file focused on a single responsibility.
class MenuActions: NSObject {
    static let shared = MenuActions()

    private override init() {
        super.init()
    }

    // MARK: - Window Toggles

    @objc func toggleMainWindow() {
        WindowManager.shared.toggleMainWindow()
    }

    @objc func toggleEQ() {
        WindowManager.shared.toggleEqualizer()
    }
    
    @objc func togglePlaylist() {
        WindowManager.shared.togglePlaylist()
    }
    
    @objc func toggleMediaLibrary() {
        WindowManager.shared.toggleMediaLibrary()
    }
    
    @objc func togglePlexBrowser() {
        WindowManager.shared.togglePlexBrowser()
    }
    
    @objc func toggleProjectM() {
        WindowManager.shared.toggleProjectM()
    }
    
    @objc func toggleSpectrum() {
        WindowManager.shared.toggleSpectrum()
    }

    @objc func toggleWaveform() {
        WindowManager.shared.toggleWaveform()
    }
    
    @objc func toggleDebugConsole() {
        WindowManager.shared.toggleDebugWindow()
    }

    @objc func toggleLibraryHistory() {
        guard WindowManager.shared.isModernUIEnabled else { return }
        WindowManager.shared.toggleLibraryHistory()
    }

    @objc func rerenderCurrentWaveform() {
        WindowManager.shared.reloadWaveform(force: true)
    }

    @objc func clearCurrentWaveformCache() {
        WindowManager.shared.clearCurrentWaveformCache()
    }

    @objc func toggleWaveformCuePoints() {
        WindowManager.shared.toggleWaveformCuePoints()
    }

    @objc func toggleWaveformTransparentBackground() {
        WindowManager.shared.toggleWaveformTransparentBackground()
    }

    @objc func toggleWaveformTooltip() {
        WindowManager.shared.toggleWaveformTooltip()
    }
    
    // MARK: - About Playing
    
    @objc func showAboutPlaying() {
        let wm = WindowManager.shared
        
        // Check for video first (takes priority if both audio and video are active)
        // Path 1: Video player window is active (local playback or cast from player)
        if let videoController = wm.currentVideoPlayerController,
           wm.isVideoActivePlayback {
            showVideoInfo(videoController)
            return
        }
        
        // Path 2: Video casting from menu (no video player window)
        if CastManager.shared.isVideoCasting {
            showVideoCastInfo()
            return
        }
        
        // Check for audio track
        if let track = wm.audioEngine.currentTrack {
            showAudioTrackInfo(track)
            return
        }
        
        // Nothing playing (shouldn't happen - menu item should be disabled)
        let alert = NSAlert()
        alert.messageText = "Nothing Playing"
        alert.informativeText = "No track or video is currently playing."
        alert.runModal()
    }
    
    /// Show info for video casting initiated from context menu (no video player window)
    private func showVideoCastInfo() {
        let castManager = CastManager.shared
        let alert = NSAlert()
        
        let title = castManager.videoCastTitle ?? "Video"
        alert.messageText = title
        
        var info = [String]()
        
        // Duration
        let duration = castManager.videoCastDuration
        if duration > 0 {
            let hours = Int(duration) / 3600
            let minutes = (Int(duration) % 3600) / 60
            let seconds = Int(duration) % 60
            if hours > 0 {
                info.append("Duration: \(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds))")
            } else {
                info.append("Duration: \(minutes):\(String(format: "%02d", seconds))")
            }
        }
        
        // Cast device
        if let session = castManager.activeSession {
            info.append("")
            info.append("Casting to: \(session.device.name)")
            info.append("Device Type: \(session.device.type.displayName)")
        }
        
        // Playback state
        info.append("")
        info.append("Status: \(castManager.isVideoCastPlaying ? "Playing" : "Paused")")
        
        alert.informativeText = info.joined(separator: "\n")
        alert.runModal()
    }
    
    private func showVideoInfo(_ controller: VideoPlayerWindowController) {
        let alert = NSAlert()
        
        if let movie = controller.plexMovie {
            // Plex Movie
            alert.messageText = movie.title
            var info = [String]()
            
            if let year = movie.year { info.append("Year: \(year)") }
            if let studio = movie.studio { info.append("Studio: \(studio)") }
            info.append("Duration: \(movie.formattedDuration)")
            info.append("")
            
            // Video/Audio format from media
            if let media = movie.primaryMedia {
                if let resolution = media.videoResolution {
                    var videoInfo = "Resolution: \(resolution)"
                    if let width = media.width, let height = media.height {
                        videoInfo = "Resolution: \(width)x\(height)"
                    }
                    info.append(videoInfo)
                }
                if let videoCodec = media.videoCodec {
                    info.append("Video Codec: \(videoCodec.uppercased())")
                }
                if let audioCodec = media.audioCodec {
                    var audioInfo = "Audio: \(audioCodec.uppercased())"
                    if let channels = media.audioChannels {
                        audioInfo += " (\(formatChannels(channels)))"
                    }
                    info.append(audioInfo)
                }
                if let bitrate = media.bitrate {
                    info.append("Bitrate: \(bitrate) kbps")
                }
            }
            info.append("")
            
            if let contentRating = movie.contentRating {
                info.append("Content Rating: \(contentRating)")
            }
            if let imdbId = movie.imdbId {
                info.append("IMDB: \(imdbId)")
            }
            if let tmdbId = movie.tmdbId {
                info.append("TMDB: \(tmdbId)")
            }
            info.append("")
            
            if let serverName = PlexManager.shared.currentServer?.name {
                info.append("Source: Plex (\(serverName))")
            } else {
                info.append("Source: Plex")
            }
            
            if let summary = movie.summary, !summary.isEmpty {
                info.append("")
                info.append("Summary: \(summary.prefix(200))\(summary.count > 200 ? "..." : "")")
            }
            
            alert.informativeText = info.joined(separator: "\n")
            
        } else if let episode = controller.plexEpisode {
            // Plex Episode
            let showTitle = episode.grandparentTitle ?? "Unknown Show"
            alert.messageText = "\(showTitle) - \(episode.episodeIdentifier)"
            
            var info = [String]()
            info.append("Episode: \(episode.title)")
            if let seasonTitle = episode.parentTitle {
                info.append("Season: \(seasonTitle)")
            }
            info.append("Duration: \(episode.formattedDuration)")
            info.append("")
            
            // Video/Audio format from media
            if let media = episode.media.first {
                if let resolution = media.videoResolution {
                    var videoInfo = "Resolution: \(resolution)"
                    if let width = media.width, let height = media.height {
                        videoInfo = "Resolution: \(width)x\(height)"
                    }
                    info.append(videoInfo)
                }
                if let videoCodec = media.videoCodec {
                    info.append("Video Codec: \(videoCodec.uppercased())")
                }
                if let audioCodec = media.audioCodec {
                    var audioInfo = "Audio: \(audioCodec.uppercased())"
                    if let channels = media.audioChannels {
                        audioInfo += " (\(formatChannels(channels)))"
                    }
                    info.append(audioInfo)
                }
                if let bitrate = media.bitrate {
                    info.append("Bitrate: \(bitrate) kbps")
                }
            }
            info.append("")
            
            if let imdbId = episode.imdbId {
                info.append("IMDB: \(imdbId)")
            }
            info.append("")
            
            if let serverName = PlexManager.shared.currentServer?.name {
                info.append("Source: Plex (\(serverName))")
            } else {
                info.append("Source: Plex")
            }
            
            if let summary = episode.summary, !summary.isEmpty {
                info.append("")
                info.append("Summary: \(summary.prefix(200))\(summary.count > 200 ? "..." : "")")
            }
            
            alert.informativeText = info.joined(separator: "\n")
            
        } else if let url = controller.localVideoURL {
            // Local video file
            alert.messageText = controller.currentTitle ?? url.lastPathComponent
            var info = [String]()
            info.append("Path: \(url.path)")
            info.append("")
            info.append("Source: Local File")
            alert.informativeText = info.joined(separator: "\n")
            
        } else {
            // Unknown video
            alert.messageText = controller.currentTitle ?? "Video"
            alert.informativeText = "Source: Unknown"
        }
        
        alert.runModal()
    }
    
    private func showAudioTrackInfo(_ track: Track) {
        // Check if this is a Plex track - fetch full metadata async
        if let ratingKey = track.plexRatingKey {
            Task {
                await showPlexTrackInfo(track, ratingKey: ratingKey)
            }
            return
        }
        
        // Check if this is a Subsonic track
        if let subsonicId = track.subsonicId {
            Task { await showSubsonicTrackInfo(track, subsonicId: subsonicId) }
            return
        }
        
        // Check if this is a Jellyfin track
        if let jellyfinId = track.jellyfinId {
            Task { await showJellyfinTrackInfo(track, jellyfinId: jellyfinId) }
            return
        }

        // Check if this is an Emby track
        if let embyId = track.embyId {
            Task { await showEmbyTrackInfo(track, embyId: embyId) }
            return
        }

        // Local file
        Task { await showLocalTrackInfo(track) }
    }
    
    @MainActor
    private func showPlexTrackInfo(_ track: Track, ratingKey: String) async {
        let alert = NSAlert()
        alert.messageText = track.displayTitle
        
        var info = [String]()
        
        // Try to fetch full Plex metadata
        var plexTrack: PlexTrack?
        if let client = PlexManager.shared.serverClient {
            plexTrack = try? await client.fetchTrackDetails(trackID: ratingKey)
        }
        
        // Basic info (always available from Track)
        info.append("Title: \(track.title)")
        if let albumArtist = plexTrack?.grandparentTitle {
            info.append("Album Artist: \(albumArtist)")
        } else if let artist = track.artist {
            info.append("Artist: \(artist)")
        }
        if let album = plexTrack?.parentTitle ?? track.album { info.append("Album: \(album)") }
        info.append("")

        // Duration
        info.append("Duration: \(track.formattedDuration)")

        // Extended info from Plex API
        if let pt = plexTrack {
            if let genre = pt.genre { info.append("Genre: \(genre)") }
            if let year = pt.parentYear { info.append("Year: \(year)") }
            if let index = pt.index {
                var trackInfo = "Track: \(index)"
                if let disc = pt.parentIndex { trackInfo += " (Disc \(disc))" }
                info.append(trackInfo)
            }
            info.append("")
            
            // Audio format from media
            if let media = pt.media.first {
                if let codec = media.audioCodec {
                    var formatInfo = "Format: \(codec.uppercased())"
                    if let channels = media.audioChannels {
                        formatInfo += " (\(formatChannels(channels)))"
                    }
                    info.append(formatInfo)
                }
                if let sr = media.audioSampleRate { info.append("Sample Rate: \(sr) Hz") }
                if let bitrate = media.bitrate {
                    info.append("Bitrate: \(bitrate) kbps")
                }
                // File path from part
                if let part = media.parts.first, let file = part.file {
                    info.append("File: \(file)")
                }
            }
            if let summary = pt.summary, !summary.isEmpty {
                info.append("")
                info.append("Summary: \(summary)")
            }
            info.append("")
            
            // Plex-specific metadata
            if let ratingCount = pt.ratingCount, ratingCount > 0 {
                info.append("Last.fm Scrobbles: \(formatNumber(ratingCount))")
            }
            if let userRating = pt.userRating, userRating > 0 {
                info.append("Your Rating: \(formatStarRating(userRating))")
            }
        } else {
            // Fallback to Track model data
            info.append("")
            if let bitrate = track.bitrate { info.append("Bitrate: \(bitrate) kbps") }
            if let sampleRate = track.sampleRate { info.append("Sample Rate: \(sampleRate) Hz") }
            if let channels = track.channels { info.append("Channels: \(formatChannels(channels))") }
        }
        info.append("")
        
        // Source
        if let serverName = PlexManager.shared.currentServer?.name {
            info.append("Source: Plex (\(serverName))")
        } else {
            info.append("Source: Plex")
        }
        
        alert.informativeText = info.joined(separator: "\n")
        alert.runModal()
    }
    
    @MainActor
    private func showSubsonicTrackInfo(_ track: Track, subsonicId: String) async {
        let alert = NSAlert()
        alert.messageText = track.displayTitle

        var info = [String]()

        var song: SubsonicSong?
        if let client = SubsonicManager.shared.serverClient {
            song = try? await client.fetchSong(id: subsonicId)
        }

        // Identity
        info.append("Title: \(song?.title ?? track.title)")
        if let artist = song?.artist ?? track.artist { info.append("Artist: \(artist)") }
        if let albumArtist = song?.albumArtist { info.append("Album Artist: \(albumArtist)") }
        if let album = song?.album ?? track.album { info.append("Album: \(album)") }
        if let year = song?.year { info.append("Year: \(year)") }
        if let trackNum = song?.track {
            var s = "Track: \(trackNum)"
            if let disc = song?.discNumber { s += " (Disc \(disc))" }
            info.append(s)
        }
        if let genre = song?.genre { info.append("Genre: \(genre)") }
        info.append("")

        // Audio
        let durationSecs = song.map { $0.duration } ?? Int(track.duration ?? 0)
        info.append("Duration: \(durationSecs / 60):\(String(format: "%02d", durationSecs % 60))")
        if let sr = song?.samplingRate ?? track.sampleRate { info.append("Sample Rate: \(sr) Hz") }
        if let br = song?.bitRate ?? track.bitrate { info.append("Bitrate: \(br) kbps") }
        if let ct = song?.contentType { info.append("Format: \(ct)") }
        if let size = song?.size, size > 0 { info.append("File Size: \(formatFileSize(size))") }
        info.append("")

        // Stats
        if let pc = song?.playCount { info.append("Play Count: \(pc)") }
        if let ur = song?.userRating, ur > 0 { info.append("Rating: \(formatStarRating(Double(ur) * 2))") }
        if let starred = song?.starred { info.append("Starred: \(formatDate(starred))") }
        if let created = song?.created { info.append("Date Added: \(formatDate(created))") }
        if song?.playCount != nil || song?.userRating != nil || song?.starred != nil { info.append("") }

        // Source
        if let serverName = SubsonicManager.shared.currentServer?.name {
            info.append("Source: Subsonic (\(serverName))")
        } else {
            info.append("Source: Subsonic")
        }
        if let path = song?.path { info.append("File: \(path)") }
        info.append("Track ID: \(subsonicId)")

        alert.informativeText = info.joined(separator: "\n")
        alert.runModal()
    }
    
    @MainActor
    private func showJellyfinTrackInfo(_ track: Track, jellyfinId: String) async {
        let alert = NSAlert()
        alert.messageText = track.displayTitle

        var info = [String]()

        var song: JellyfinSong?
        if let client = JellyfinManager.shared.serverClient {
            song = try? await client.fetchSong(id: jellyfinId)
        }

        // Identity
        info.append("Title: \(song?.title ?? track.title)")
        if let artist = song?.artist ?? track.artist { info.append("Artist: \(artist)") }
        if let albumArtist = song?.albumArtist { info.append("Album Artist: \(albumArtist)") }
        if let album = song?.album ?? track.album { info.append("Album: \(album)") }
        if let year = song?.year { info.append("Year: \(year)") }
        if let trackNum = song?.track {
            var s = "Track: \(trackNum)"
            if let disc = song?.discNumber { s += " (Disc \(disc))" }
            info.append(s)
        }
        if let genre = song?.genre { info.append("Genre: \(genre)") }
        info.append("")

        // Audio
        let durationSecs = song.map { $0.duration } ?? Int(track.duration ?? 0)
        info.append("Duration: \(durationSecs / 60):\(String(format: "%02d", durationSecs % 60))")
        if let sr = song?.sampleRate ?? track.sampleRate { info.append("Sample Rate: \(sr) Hz") }
        if let ch = song?.channels ?? track.channels { info.append("Channels: \(formatChannels(ch))") }
        if let br = song?.bitRate ?? track.bitrate { info.append("Bitrate: \(br) kbps") }
        if let ct = song?.contentType { info.append("Format: \(ct.uppercased())") }
        if let size = song?.size, size > 0 { info.append("File Size: \(formatFileSize(size))") }
        info.append("")

        // Stats
        if let pc = song?.playCount { info.append("Play Count: \(pc)") }
        if let ur = song?.userRating, ur > 0 { info.append("Rating: \(formatStarRating(Double(ur) / 10))") }
        if let fav = song?.isFavorite, fav { info.append("Favorite: Yes") }
        if let created = song?.created { info.append("Date Added: \(formatDate(created))") }
        if song?.playCount != nil || song?.userRating != nil { info.append("") }

        // Source
        if let serverName = JellyfinManager.shared.currentServer?.name {
            info.append("Source: Jellyfin (\(serverName))")
        } else {
            info.append("Source: Jellyfin")
        }
        if let path = song?.path { info.append("File: \(path)") }
        info.append("Track ID: \(jellyfinId)")

        alert.informativeText = info.joined(separator: "\n")
        alert.runModal()
    }
    
    @MainActor
    private func showEmbyTrackInfo(_ track: Track, embyId: String) async {
        let alert = NSAlert()
        alert.messageText = track.displayTitle

        var info = [String]()

        var song: EmbySong?
        if let client = EmbyManager.shared.serverClient {
            song = try? await client.fetchSong(id: embyId)
        }

        // Identity
        info.append("Title: \(song?.title ?? track.title)")
        if let artist = song?.artist ?? track.artist { info.append("Artist: \(artist)") }
        if let albumArtist = song?.albumArtist { info.append("Album Artist: \(albumArtist)") }
        if let album = song?.album ?? track.album { info.append("Album: \(album)") }
        if let year = song?.year { info.append("Year: \(year)") }
        if let trackNum = song?.track {
            var s = "Track: \(trackNum)"
            if let disc = song?.discNumber { s += " (Disc \(disc))" }
            info.append(s)
        }
        if let genre = song?.genre { info.append("Genre: \(genre)") }
        info.append("")

        // Audio
        let durationSecs = song.map { $0.duration } ?? Int(track.duration ?? 0)
        info.append("Duration: \(durationSecs / 60):\(String(format: "%02d", durationSecs % 60))")
        if let sr = song?.sampleRate ?? track.sampleRate { info.append("Sample Rate: \(sr) Hz") }
        if let ch = song?.channels ?? track.channels { info.append("Channels: \(formatChannels(ch))") }
        if let br = song?.bitRate ?? track.bitrate { info.append("Bitrate: \(br) kbps") }
        if let ct = song?.contentType { info.append("Format: \(ct.uppercased())") }
        if let size = song?.size, size > 0 { info.append("File Size: \(formatFileSize(size))") }
        info.append("")

        // Stats
        if let pc = song?.playCount { info.append("Play Count: \(pc)") }
        if let ur = song?.userRating, ur > 0 { info.append("Rating: \(formatStarRating(Double(ur) / 10))") }
        if let fav = song?.isFavorite, fav { info.append("Favorite: Yes") }
        if let created = song?.created { info.append("Date Added: \(formatDate(created))") }
        if song?.playCount != nil || song?.userRating != nil { info.append("") }

        // Source
        if let serverName = EmbyManager.shared.currentServer?.name {
            info.append("Source: Emby (\(serverName))")
        } else {
            info.append("Source: Emby")
        }
        if let path = song?.path { info.append("File: \(path)") }
        info.append("Track ID: \(embyId)")

        alert.informativeText = info.joined(separator: "\n")
        alert.runModal()
    }

    @MainActor
    private func showLocalTrackInfo(_ track: Track) async {
        let alert = NSAlert()
        alert.messageText = track.displayTitle

        var info = [String]()
        let lt = MediaLibrary.shared.findTrack(byURL: track.url)

        // For non-library files, read extra tags directly from the file
        let fileAlbumArtist: String?
        if lt == nil, track.url.isFileURL {
            fileAlbumArtist = await loadLocalAlbumArtist(from: track.url)
        } else {
            fileAlbumArtist = nil
        }

        // Identity
        info.append("Title: \(track.title)")
        if let artist = lt?.artist ?? track.artist { info.append("Artist: \(artist)") }
        if let albumArtist = lt?.albumArtist ?? fileAlbumArtist { info.append("Album Artist: \(albumArtist)") }
        if let album = lt?.album ?? track.album { info.append("Album: \(album)") }
        if let year = lt?.year { info.append("Year: \(year)") }
        if let trackNum = lt?.trackNumber {
            var s = "Track: \(trackNum)"
            if let disc = lt?.discNumber { s += " (Disc \(disc))" }
            info.append(s)
        }
        if let genre = lt?.genre ?? track.genre { info.append("Genre: \(genre)") }
        if let composer = lt?.composer { info.append("Composer: \(composer)") }
        if let bpm = lt?.bpm { info.append("BPM: \(bpm)") }
        if let key = lt?.musicalKey { info.append("Key: \(key)") }
        info.append("")

        // Playback stats
        let duration = lt.map { $0.duration } ?? track.duration
        if let d = duration {
            let secs = Int(d)
            info.append("Duration: \(secs / 60):\(String(format: "%02d", secs % 60))")
        } else {
            info.append("Duration: \(track.formattedDuration)")
        }
        if let sampleRate = lt?.sampleRate ?? track.sampleRate { info.append("Sample Rate: \(sampleRate) Hz") }
        if let channels = lt?.channels ?? track.channels { info.append("Channels: \(formatChannels(channels))") }
        if let bitrate = lt?.bitrate ?? track.bitrate { info.append("Bitrate: \(bitrate) kbps") }
        if let fileSize = lt?.fileSize, fileSize > 0 { info.append("File Size: \(formatFileSize(fileSize))") }
        info.append("")

        // Library stats
        if let lt {
            info.append("Play Count: \(lt.playCount)")
            if let rating = lt.rating, rating > 0 { info.append("Rating: \(formatStarRating(Double(rating)))") }
            if let lastPlayed = lt.lastPlayed { info.append("Last Played: \(formatDate(lastPlayed))") }
            info.append("Date Added: \(formatDate(lt.dateAdded))")
            info.append("")
        }

        // Extra tags
        var hasExtra = false
        if let comment = lt?.comment { info.append("Comment: \(comment)"); hasExtra = true }
        if let grouping = lt?.grouping { info.append("Grouping: \(grouping)"); hasExtra = true }
        if let isrc = lt?.isrc { info.append("ISRC: \(isrc)"); hasExtra = true }
        if let copyright = lt?.copyright { info.append("Copyright: \(copyright)"); hasExtra = true }
        if let mbRec = lt?.musicBrainzRecordingID { info.append("MusicBrainz Recording: \(mbRec)"); hasExtra = true }
        if let mbRel = lt?.musicBrainzReleaseID { info.append("MusicBrainz Release: \(mbRel)"); hasExtra = true }
        if let dcRel = lt?.discogsReleaseID { info.append("Discogs Release: \(dcRel)"); hasExtra = true }
        if let dcMas = lt?.discogsMasterID { info.append("Discogs Master: \(dcMas)"); hasExtra = true }
        if let dcLab = lt?.discogsLabel { info.append("Discogs Label: \(dcLab)"); hasExtra = true }
        if let dcCat = lt?.discogsCatalogNumber { info.append("Discogs Catalog: \(dcCat)"); hasExtra = true }
        if hasExtra { info.append("") }

        info.append("Path: \(track.url.path)")
        info.append("")
        info.append("Source: Local File")

        alert.informativeText = info.joined(separator: "\n")
        alert.runModal()
    }

    private func loadLocalAlbumArtist(from fileURL: URL) async -> String? {
        await Task.detached(priority: .userInitiated) {
            let asset = AVAsset(url: fileURL)
            guard let metadata = try? await asset.load(.metadata) else { return nil }

            let identifiers: [AVMetadataIdentifier] = [
                .id3MetadataBand,
                .iTunesMetadataAlbumArtist,
            ]

            for identifier in identifiers {
                let items = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: identifier)
                for item in items {
                    if let albumArtist = try? await item.load(.stringValue),
                       !albumArtist.isEmpty {
                        return albumArtist
                    }
                }
            }

            return nil
        }.value
    }
    
    // MARK: - Formatting Helpers for About Playing
    
    private func formatChannels(_ channels: Int) -> String {
        switch channels {
        case 1: return "Mono"
        case 2: return "Stereo"
        case 6: return "5.1"
        case 8: return "7.1"
        default: return "\(channels) channels"
        }
    }
    
    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
    
    private func formatStarRating(_ rating: Double) -> String {
        // Expects a 0-10 scale (10 = 5 stars)
        let stars = max(0, min(5, Int(round(rating / 2))))
        return String(repeating: "★", count: stars) + String(repeating: "☆", count: 5 - stars)
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_048_576
        if mb >= 1000 {
            return String(format: "%.2f GB", mb / 1024)
        }
        return String(format: "%.1f MB", mb)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    // MARK: - File Operations
    
    @objc func openFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio, .mp3, .wav, .aiff]
        
        if panel.runModal() == .OK {
            WindowManager.shared.audioEngine.loadFiles(panel.urls)
        }
    }
    
    @objc func openFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        
        if panel.runModal() == .OK, let url = panel.url {
            WindowManager.shared.audioEngine.loadFolder(url)
        }
    }
    
    // MARK: - Skin Operations
    
    @objc func loadDefaultClassicSkin() {
        let wm = WindowManager.shared
        let previousSkinPath = UserDefaults.standard.string(forKey: "lastClassicSkinPath")
        // Clear the last used skin so the bundled default loads
        UserDefaults.standard.removeObject(forKey: "lastClassicSkinPath")
        
        if wm.isRunningModernUI {
            // Switch to classic mode with default skin on next launch
            if !showRestartAlert(beforeRelaunch: {
                wm.isModernUIEnabled = false
            }) {
                if let previousSkinPath = previousSkinPath {
                    UserDefaults.standard.set(previousSkinPath, forKey: "lastClassicSkinPath")
                } else {
                    UserDefaults.standard.removeObject(forKey: "lastClassicSkinPath")
                }
            }
        } else {
            // Already in classic mode - load bundled default skin now
            wm.loadBundledDefaultSkin()
        }
    }
    
    @objc func loadSkinFromFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.init(filenameExtension: "wsz")!]
        
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let wm = WindowManager.shared
        do {
            let importedURL = try wm.importClassicSkin(from: url)
            if !wm.loadSkin(from: importedURL) {
                let alert = NSAlert()
                alert.messageText = "Failed to Load Classic Skin"
                alert.informativeText = "The skin was imported but could not be loaded."
                alert.alertStyle = .warning
                alert.runModal()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Failed to Import Classic Skin"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    @objc func loadModernSkinFromFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.init(filenameExtension: ModernSkinLoader.bundleExtension)!]
        panel.message = "Select a .\(ModernSkinLoader.bundleExtension) modern skin bundle"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let previousSkinName = UserDefaults.standard.string(forKey: "modernSkinName")
        do {
            let importedSkinName = try ModernSkinEngine.shared.importSkinBundle(from: url)
            if WindowManager.shared.isRunningModernUI {
                if !ModernSkinEngine.shared.loadSkin(named: importedSkinName) {
                    if let previousSkinName = previousSkinName {
                        UserDefaults.standard.set(previousSkinName, forKey: "modernSkinName")
                    } else {
                        UserDefaults.standard.removeObject(forKey: "modernSkinName")
                    }
                    let alert = NSAlert()
                    alert.messageText = "Failed to Load Modern Skin"
                    alert.informativeText = "The skin was imported but could not be loaded."
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Failed to Import Modern Skin"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
    
    @objc func getMoreClassicSkins() {
        guard let url = URL(string: "https://skins.webamp.org") else { return }
        NSWorkspace.shared.open(url)
    }
    
    @objc func loadSkin(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        WindowManager.shared.loadSkin(from: url)
        UserDefaults.standard.set(url.path, forKey: "lastClassicSkinPath")
    }
    
    /// Select a classic skin and switch to classic mode if needed
    @objc func selectClassicSkin(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        let wm = WindowManager.shared
        
        // Persist the last used classic skin path
        let previousSkinPath = UserDefaults.standard.string(forKey: "lastClassicSkinPath")
        UserDefaults.standard.set(url.path, forKey: "lastClassicSkinPath")
        
        if wm.isRunningModernUI {
            // Switch to classic mode and load this skin on next launch
            if !showRestartAlert(beforeRelaunch: {
                wm.isModernUIEnabled = false
            }) {
                // User cancelled — revert
                if let previousSkinPath = previousSkinPath {
                    UserDefaults.standard.set(previousSkinPath, forKey: "lastClassicSkinPath")
                } else {
                    UserDefaults.standard.removeObject(forKey: "lastClassicSkinPath")
                }
            }
        } else {
            // Already in classic mode — load the skin immediately
            wm.loadSkin(from: url)
        }
    }
    
    /// Select a modern skin and switch to modern mode if needed
    @objc func selectModernSkin(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        let wm = WindowManager.shared
        
        // Persist the selected modern skin name (ModernSkinEngine does this too, but
        // we need it set before restart when switching from classic mode)
        let previousSkinName = UserDefaults.standard.string(forKey: "modernSkinName")
        UserDefaults.standard.set(name, forKey: "modernSkinName")
        
        if !wm.isRunningModernUI {
            // Switch to modern mode — skin will load on next launch
            if !showRestartAlert(beforeRelaunch: {
                wm.isModernUIEnabled = true
            }) {
                // User cancelled — revert
                if let previousSkinName = previousSkinName {
                    UserDefaults.standard.set(previousSkinName, forKey: "modernSkinName")
                } else {
                    UserDefaults.standard.removeObject(forKey: "modernSkinName")
                }
            }
        } else {
            // Already in modern mode — load the skin immediately
            ModernSkinEngine.shared.loadSkin(named: name)
        }
    }
    
    @objc func openModernSkinsFolder() {
        ModernSkinEngine.shared.openSkinsFolder()
    }
    
    // MARK: - UI Mode Switching
    
    @objc func setClassicMode() {
        let wm = WindowManager.shared
        guard wm.isRunningModernUI else { return }
        _ = showRestartAlert(beforeRelaunch: {
            wm.isModernUIEnabled = false
        })
    }
    
    @objc func setModernMode() {
        let wm = WindowManager.shared
        guard !wm.isRunningModernUI else { return }
        _ = showRestartAlert(beforeRelaunch: {
            wm.isModernUIEnabled = true
        })
    }
    
    /// Shows a restart confirmation alert. Returns `true` if the user confirmed and the app is restarting.
    @discardableResult
    private func showRestartAlert(
        informativeText: String = "NullPlayer needs to restart to apply the UI mode change. Restart now?",
        beforeRelaunch: (() -> Void)? = nil
    ) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Restart Required"
        alert.informativeText = informativeText
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Restart")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // User confirmed — relaunch the app
            beforeRelaunch?()
            relaunchApp()
            return true
        }
        return false
    }
    
    /// Relaunch the application by opening a new instance and terminating the current one.
    private func relaunchApp() {
        guard let bundleURL = Bundle.main.bundleURL as URL? else { return }
        
        // Spawn a detached shell that sleeps 0.5s then opens the bundle.
        // Must be launched BEFORE NSApp.terminate so it survives the parent's exit
        // (macOS reparents orphaned children to launchd). Pass the path as $1
        // (positional arg) to avoid any shell-injection risk.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5 && /usr/bin/open \"$1\"", "--", bundleURL.path]
        try? task.run()

        NSApp.terminate(nil)
    }
    
    // MARK: - Options
    
    @objc func setTimeElapsed() {
        WindowManager.shared.timeDisplayMode = .elapsed
    }
    
    @objc func setTimeRemaining() {
        WindowManager.shared.timeDisplayMode = .remaining
    }
    
    @objc func toggleRepeat() {
        WindowManager.shared.audioEngine.repeatEnabled.toggle()
    }
    
    @objc func toggleShuffle() {
        WindowManager.shared.audioEngine.shuffleEnabled.toggle()
    }
    
    @objc func toggleGaplessPlayback() {
        WindowManager.shared.audioEngine.gaplessPlaybackEnabled.toggle()
    }
    
    @objc func toggleVolumeNormalization() {
        WindowManager.shared.audioEngine.volumeNormalizationEnabled.toggle()
    }
    
    @objc func toggleSweetFade() {
        WindowManager.shared.audioEngine.sweetFadeEnabled.toggle()
    }
    
    @objc func setSweetFadeDuration(_ sender: NSMenuItem) {
        guard let duration = sender.representedObject as? Double else { return }
        WindowManager.shared.audioEngine.sweetFadeDuration = duration
    }

    @objc func setRadioMaxTracksPerArtist(_ sender: NSMenuItem) {
        guard let maxTracks = sender.representedObject as? Int else { return }
        RadioPlaybackOptions.maxTracksPerArtist = maxTracks
    }

    @objc func setRadioPlaylistLength(_ sender: NSMenuItem) {
        guard let playlistLength = sender.representedObject as? Int else { return }
        RadioPlaybackOptions.playlistLength = playlistLength
    }
    
    @objc func toggleBrowserArtworkBackground() {
        WindowManager.shared.showBrowserArtworkBackground.toggle()
    }

    // MARK: - Plex Radio History

    @objc func setPlexRadioHistoryInterval(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let interval = PlexRadioHistoryInterval(rawValue: rawValue) else { return }
        PlexRadioHistory.shared.retentionInterval = interval
    }

    @objc func viewPlexRadioHistory() {
        Task {
            if !LocalMediaServer.shared.isRunning {
                try? await LocalMediaServer.shared.start()
            }
            if let url = PlexRadioHistory.shared.historyPageURL {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @objc func clearPlexRadioHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear Radio History?"
        alert.informativeText = "This will remove all Plex Radio track history. This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            PlexRadioHistory.shared.clearHistory()
        }
    }

    // MARK: - Subsonic Radio History

    @objc func setSubsonicRadioHistoryInterval(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let interval = SubsonicRadioHistoryInterval(rawValue: rawValue) else { return }
        SubsonicRadioHistory.shared.retentionInterval = interval
    }

    @objc func viewSubsonicRadioHistory() {
        Task {
            if !LocalMediaServer.shared.isRunning {
                do { try await LocalMediaServer.shared.start() } catch {
                    await MainActor.run {
                        let alert = NSAlert(); alert.messageText = "Could Not Open History"
                        alert.informativeText = "The local history server failed to start: \(error.localizedDescription)"
                        alert.alertStyle = .warning; alert.runModal()
                    }
                    return
                }
            }
            if let url = SubsonicRadioHistory.shared.historyPageURL { NSWorkspace.shared.open(url) }
        }
    }

    @objc func clearSubsonicRadioHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear Radio History?"
        alert.informativeText = "This will remove all Subsonic Radio track history. This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { SubsonicRadioHistory.shared.clearHistory() }
    }

    // MARK: - Jellyfin Radio History

    @objc func setJellyfinRadioHistoryInterval(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let interval = JellyfinRadioHistoryInterval(rawValue: rawValue) else { return }
        JellyfinRadioHistory.shared.retentionInterval = interval
    }

    @objc func viewJellyfinRadioHistory() {
        Task {
            if !LocalMediaServer.shared.isRunning {
                do { try await LocalMediaServer.shared.start() } catch {
                    await MainActor.run {
                        let alert = NSAlert(); alert.messageText = "Could Not Open History"
                        alert.informativeText = "The local history server failed to start: \(error.localizedDescription)"
                        alert.alertStyle = .warning; alert.runModal()
                    }
                    return
                }
            }
            if let url = JellyfinRadioHistory.shared.historyPageURL { NSWorkspace.shared.open(url) }
        }
    }

    @objc func clearJellyfinRadioHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear Radio History?"
        alert.informativeText = "This will remove all Jellyfin Radio track history. This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { JellyfinRadioHistory.shared.clearHistory() }
    }

    // MARK: - Emby Radio History

    @objc func setEmbyRadioHistoryInterval(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let interval = EmbyRadioHistoryInterval(rawValue: rawValue) else { return }
        EmbyRadioHistory.shared.retentionInterval = interval
    }

    @objc func viewEmbyRadioHistory() {
        Task {
            if !LocalMediaServer.shared.isRunning {
                do { try await LocalMediaServer.shared.start() } catch {
                    await MainActor.run {
                        let alert = NSAlert(); alert.messageText = "Could Not Open History"
                        alert.informativeText = "The local history server failed to start: \(error.localizedDescription)"
                        alert.alertStyle = .warning; alert.runModal()
                    }
                    return
                }
            }
            if let url = EmbyRadioHistory.shared.historyPageURL { NSWorkspace.shared.open(url) }
        }
    }

    @objc func clearEmbyRadioHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear Radio History?"
        alert.informativeText = "This will remove all Emby Radio track history. This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { EmbyRadioHistory.shared.clearHistory() }
    }

    // MARK: - Local Radio History

    @objc func setLocalRadioHistoryInterval(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let interval = LocalRadioHistoryInterval(rawValue: rawValue) else { return }
        LocalRadioHistory.shared.retentionInterval = interval
    }

    @objc func viewLocalRadioHistory() {
        Task {
            if !LocalMediaServer.shared.isRunning {
                do { try await LocalMediaServer.shared.start() } catch {
                    await MainActor.run {
                        let alert = NSAlert(); alert.messageText = "Could Not Open History"
                        alert.informativeText = "The local history server failed to start: \(error.localizedDescription)"
                        alert.alertStyle = .warning; alert.runModal()
                    }
                    return
                }
            }
            if let url = LocalRadioHistory.shared.historyPageURL { NSWorkspace.shared.open(url) }
        }
    }

    @objc func clearLocalRadioHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear Radio History?"
        alert.informativeText = "This will remove all Local Radio track history. This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { LocalRadioHistory.shared.clearHistory() }
    }

    // MARK: - Main Window Visualization Options

    @objc func setMainVisMode(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? MainWindowVisMode else { return }
        UserDefaults.standard.set(mode.rawValue, forKey: "mainWindowVisMode")
        // Notify main window to update visualization mode
        NotificationCenter.default.post(name: NSNotification.Name("MainWindowVisChanged"), object: nil)
    }
    
    @objc func setMainVisFlameStyle(_ sender: NSMenuItem) {
        guard let style = sender.representedObject as? FlameStyle else { return }
        UserDefaults.standard.set(style.rawValue, forKey: "mainWindowFlameStyle")
        // Notify main window only (independent from spectrum window flame style)
        NotificationCenter.default.post(name: NSNotification.Name("MainWindowVisChanged"), object: nil)
    }
    
    @objc func setSpectrumFlameStyle(_ sender: NSMenuItem) {
        guard let style = sender.representedObject as? FlameStyle else { return }
        UserDefaults.standard.set(style.rawValue, forKey: "flameStyle")
        NotificationCenter.default.post(name: NSNotification.Name("SpectrumSettingsChanged"), object: nil)
    }
    
    @objc func setSpectrumLightningStyle(_ sender: NSMenuItem) {
        guard let style = sender.representedObject as? LightningStyle else { return }
        UserDefaults.standard.set(style.rawValue, forKey: "lightningStyle")
        NotificationCenter.default.post(name: NSNotification.Name("SpectrumSettingsChanged"), object: nil)
    }
    
    @objc func setSpectrumFlameIntensity(_ sender: NSMenuItem) {
        guard let intensity = sender.representedObject as? FlameIntensity else { return }
        UserDefaults.standard.set(intensity.rawValue, forKey: "flameIntensity")
        NotificationCenter.default.post(name: NSNotification.Name("SpectrumSettingsChanged"), object: nil)
    }
    
    @objc func setSpectrumMatrixColor(_ sender: NSMenuItem) {
        guard let scheme = sender.representedObject as? MatrixColorScheme else { return }
        UserDefaults.standard.set(scheme.rawValue, forKey: "matrixColorScheme")
        NotificationCenter.default.post(name: NSNotification.Name("SpectrumSettingsChanged"), object: nil)
    }
    
    @objc func setSpectrumMatrixIntensity(_ sender: NSMenuItem) {
        guard let intensity = sender.representedObject as? MatrixIntensity else { return }
        UserDefaults.standard.set(intensity.rawValue, forKey: "matrixIntensity")
        NotificationCenter.default.post(name: NSNotification.Name("SpectrumSettingsChanged"), object: nil)
    }
    
    @objc func setMainVisFlameIntensity(_ sender: NSMenuItem) {
        guard let intensity = sender.representedObject as? FlameIntensity else { return }
        UserDefaults.standard.set(intensity.rawValue, forKey: "mainWindowFlameIntensity")
        NotificationCenter.default.post(name: NSNotification.Name("MainWindowVisChanged"), object: nil)
    }
    
    @objc func setMainVisLightningStyle(_ sender: NSMenuItem) {
        guard let style = sender.representedObject as? LightningStyle else { return }
        UserDefaults.standard.set(style.rawValue, forKey: "mainWindowLightningStyle")
        NotificationCenter.default.post(name: NSNotification.Name("MainWindowVisChanged"), object: nil)
    }
    
    @objc func setMainVisMatrixColor(_ sender: NSMenuItem) {
        guard let scheme = sender.representedObject as? MatrixColorScheme else { return }
        UserDefaults.standard.set(scheme.rawValue, forKey: "mainWindowMatrixColorScheme")
        NotificationCenter.default.post(name: NSNotification.Name("MainWindowVisChanged"), object: nil)
    }
    
    @objc func setMainVisMatrixIntensity(_ sender: NSMenuItem) {
        guard let intensity = sender.representedObject as? MatrixIntensity else { return }
        UserDefaults.standard.set(intensity.rawValue, forKey: "mainWindowMatrixIntensity")
        NotificationCenter.default.post(name: NSNotification.Name("MainWindowVisChanged"), object: nil)
    }
    
    @objc func setMainVisResponsiveness(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? SpectrumDecayMode else { return }
        UserDefaults.standard.set(mode.rawValue, forKey: "mainWindowDecayMode")
        NotificationCenter.default.post(name: NSNotification.Name("MainWindowVisChanged"), object: nil)
    }
    
    @objc func setMainVisNormalization(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? SpectrumNormalizationMode else { return }
        UserDefaults.standard.set(mode.rawValue, forKey: "mainWindowNormalizationMode")
        NotificationCenter.default.post(name: NSNotification.Name("MainWindowVisChanged"), object: nil)
    }
    
    // MARK: - Spectrum Analyzer Options
    
    @objc func setSpectrumQuality(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? SpectrumQualityMode else { return }
        UserDefaults.standard.set(mode.rawValue, forKey: "spectrumQualityMode")
        // Notify spectrum analyzer views to update
        NotificationCenter.default.post(name: NSNotification.Name("SpectrumSettingsChanged"), object: nil)
    }
    
    @objc func setSpectrumResponsiveness(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? SpectrumDecayMode else { return }
        UserDefaults.standard.set(mode.rawValue, forKey: "spectrumDecayMode")
        // Notify spectrum analyzer views to update
        NotificationCenter.default.post(name: NSNotification.Name("SpectrumSettingsChanged"), object: nil)
    }
    
    @objc func setSpectrumNormalization(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? SpectrumNormalizationMode else { return }
        UserDefaults.standard.set(mode.rawValue, forKey: "spectrumNormalizationMode")
        // Normalization mode is read each frame, no notification needed
    }

    @objc func loadVisClassicProfile(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        NotificationCenter.default.post(
            name: .visClassicProfileCommand,
            object: nil,
            userInfo: ["command": "load", "profileName": name, "target": "spectrumWindow"]
        )
    }

    @objc func nextVisClassicProfile() {
        NotificationCenter.default.post(
            name: .visClassicProfileCommand,
            object: nil,
            userInfo: ["command": "next", "target": "spectrumWindow"]
        )
    }

    @objc func previousVisClassicProfile() {
        NotificationCenter.default.post(
            name: .visClassicProfileCommand,
            object: nil,
            userInfo: ["command": "previous", "target": "spectrumWindow"]
        )
    }

    @objc func importVisClassicProfile() {
        NotificationCenter.default.post(
            name: .visClassicProfileCommand,
            object: nil,
            userInfo: ["command": "import", "target": "spectrumWindow"]
        )
    }

    @objc func exportVisClassicProfile() {
        NotificationCenter.default.post(
            name: .visClassicProfileCommand,
            object: nil,
            userInfo: ["command": "export", "target": "spectrumWindow"]
        )
    }

    @objc func toggleVisClassicFitToWidth() {
        NotificationCenter.default.post(
            name: .visClassicProfileCommand,
            object: nil,
            userInfo: ["command": "fitToWidth", "target": "spectrumWindow"]
        )
    }

    @objc func toggleVisClassicTransparentBg() {
        let enabled = !VisClassicBridge.transparentBgDefault(for: .spectrumWindow)
        UserDefaults.standard.set(enabled, forKey: VisClassicBridge.PreferenceScope.spectrumWindow.transparentBgKey)
        NotificationCenter.default.post(
            name: .visClassicProfileCommand,
            object: nil,
            userInfo: ["command": "transparentBg", "target": "spectrumWindow", "enabled": enabled]
        )
    }

    @objc func loadMainVisClassicProfile(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        NotificationCenter.default.post(
            name: .visClassicProfileCommand,
            object: nil,
            userInfo: ["command": "load", "profileName": name, "target": "mainWindow"]
        )
    }

    @objc func nextMainVisClassicProfile() {
        NotificationCenter.default.post(
            name: .visClassicProfileCommand,
            object: nil,
            userInfo: ["command": "next", "target": "mainWindow"]
        )
    }

    @objc func previousMainVisClassicProfile() {
        NotificationCenter.default.post(
            name: .visClassicProfileCommand,
            object: nil,
            userInfo: ["command": "previous", "target": "mainWindow"]
        )
    }

    @objc func importMainVisClassicProfile() {
        NotificationCenter.default.post(
            name: .visClassicProfileCommand,
            object: nil,
            userInfo: ["command": "import", "target": "mainWindow"]
        )
    }

    @objc func exportMainVisClassicProfile() {
        NotificationCenter.default.post(
            name: .visClassicProfileCommand,
            object: nil,
            userInfo: ["command": "export", "target": "mainWindow"]
        )
    }

    @objc func toggleMainVisClassicFitToWidth() {
        NotificationCenter.default.post(
            name: .visClassicProfileCommand,
            object: nil,
            userInfo: ["command": "fitToWidth", "target": "mainWindow"]
        )
    }

    @objc func toggleMainVisClassicTransparentBg() {
        let enabled = !VisClassicBridge.transparentBgDefault(for: .mainWindow)
        UserDefaults.standard.set(enabled, forKey: VisClassicBridge.PreferenceScope.mainWindow.transparentBgKey)
        NotificationCenter.default.post(
            name: .visClassicProfileCommand,
            object: nil,
            userInfo: ["command": "transparentBg", "target": "mainWindow", "enabled": enabled]
        )
    }
    
    @objc func toggleRememberState() {
        AppStateManager.shared.isEnabled.toggle()
        
        // When enabling, immediately save current state to avoid
        // restoring stale state from previous session
        if AppStateManager.shared.isEnabled {
            AppStateManager.shared.saveState()
        }
    }
    
    @objc func toggleAlwaysOnTop() {
        WindowManager.shared.isAlwaysOnTop.toggle()
    }
    
    @objc func toggleHideTitleBars() {
        WindowManager.shared.toggleHideTitleBars()
    }
    
    @objc func toggleDoubleSize() {
        let wm = WindowManager.shared
        if wm.isModernUIEnabled {
            // Modern mode: live toggle works correctly
            wm.isDoubleSize.toggle()
        } else {
            // Classic mode: show the dialog BEFORE touching the UI so it never distorts.
            // Inline the alert so we can toggle the flag and call relaunchApp() ourselves —
            // the standard showRestartAlert() helper calls relaunchApp() internally and never
            // returns, which would leave the flag at the old value when saveState() fires.
            let alert = NSAlert()
            alert.messageText = "Restart Required"
            alert.informativeText = "NullPlayer needs to restart to apply the size change. Restart now?"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Restart")
            alert.addButton(withTitle: "Cancel")
            
            if alert.runModal() == .alertFirstButtonReturn {
                // Toggle first so applicationWillTerminate → saveState() captures the new value.
                // applyDoubleSize() starts an async animation that never renders — app terminates first.
                wm.isDoubleSize.toggle()
                relaunchApp()
            }
        }
    }

    @objc func toggleWindowLayoutLock() {
        WindowManager.shared.toggleWindowLayoutLock()
    }
    
    @objc func snapToDefault() {
        WindowManager.shared.snapToDefaultPositions()
    }

    @objc func minimizeAllWindows() {
        WindowManager.shared.miniaturizeAllManagedWindows()
    }
    
    // MARK: - Playback Controls
    
    @objc func previous() {
        WindowManager.shared.audioEngine.previous()
    }
    
    @objc func play() {
        WindowManager.shared.audioEngine.play()
    }
    
    @objc func pause() {
        WindowManager.shared.audioEngine.pause()
    }
    
    @objc func stop() {
        WindowManager.shared.audioEngine.stop()
    }
    
    @objc func next() {
        WindowManager.shared.audioEngine.next()
    }
    
    @objc func back5Seconds() {
        WindowManager.shared.audioEngine.seekBy(seconds: -5)
    }
    
    @objc func fwd5Seconds() {
        WindowManager.shared.audioEngine.seekBy(seconds: 5)
    }
    
    @objc func back10Tracks() {
        WindowManager.shared.audioEngine.skipTracks(count: -10)
    }
    
    @objc func fwd10Tracks() {
        WindowManager.shared.audioEngine.skipTracks(count: 10)
    }
    
    // MARK: - Plex
    
    @objc func linkPlexAccount() {
        WindowManager.shared.showPlexLinkSheet()
    }
    
    @objc func unlinkPlexAccount() {
        let alert = NSAlert()
        alert.messageText = "Unlink Plex Account?"
        alert.informativeText = "This will remove your Plex account from NullPlayer. You can link it again later."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Unlink")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            WindowManager.shared.unlinkPlexAccount()
        }
    }
    
    @objc func selectPlexServer(_ sender: NSMenuItem) {
        guard let serverID = sender.representedObject as? String,
              let server = PlexManager.shared.servers.first(where: { $0.id == serverID }) else {
            return
        }
        
        Task {
            do {
                NSLog("MenuActions: Attempting to connect to server '%@'", server.name)
                try await PlexManager.shared.connect(to: server)
                NSLog("MenuActions: Successfully connected to server '%@'", server.name)
                
                // Notify the Plex browser to reload
                await MainActor.run {
                    NotificationCenter.default.post(name: PlexManager.serversDidChangeNotification, object: nil)
                }
            } catch {
                NSLog("MenuActions: Failed to connect to server '%@': %@", server.name, error.localizedDescription)
                
                // Show error to user
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Failed to Connect"
                    alert.informativeText = "Could not connect to \(server.name): \(error.localizedDescription)"
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }
    
    @objc func selectPlexLibrary(_ sender: NSMenuItem) {
        guard let libraryID = sender.representedObject as? String,
              let library = PlexManager.shared.availableLibraries.first(where: { $0.id == libraryID }) else {
            return
        }
        
        PlexManager.shared.selectLibrary(library)
    }
    
    @objc func refreshPlexServers() {
        Task {
            do {
                try await PlexManager.shared.refreshServers()
                print("Plex servers refreshed: \(PlexManager.shared.servers.map { $0.name })")
            } catch {
                print("Failed to refresh Plex servers: \(error)")
                
                // Show error to user
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Failed to Refresh Servers"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }
    
    // MARK: - Subsonic
    
    @objc func addSubsonicServer() {
        WindowManager.shared.showSubsonicLinkSheet()
    }
    
    @objc func manageSubsonicServers() {
        WindowManager.shared.showSubsonicServerList()
    }
    
    @objc func selectSubsonicServer(_ sender: NSMenuItem) {
        guard let serverID = sender.representedObject as? String,
              let server = SubsonicManager.shared.servers.first(where: { $0.id == serverID }) else {
            return
        }
        
        Task {
            do {
                NSLog("MenuActions: Attempting to connect to Subsonic server '%@'", server.name)
                try await SubsonicManager.shared.connect(to: server)
                NSLog("MenuActions: Successfully connected to Subsonic server '%@'", server.name)
                
                await MainActor.run {
                    NotificationCenter.default.post(name: SubsonicManager.serversDidChangeNotification, object: nil)
                }
            } catch {
                NSLog("MenuActions: Failed to connect to Subsonic server '%@': %@", server.name, error.localizedDescription)
                
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Failed to Connect"
                    alert.informativeText = "Could not connect to \(server.name): \(error.localizedDescription)"
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }
    
    @objc func disconnectSubsonic() {
        SubsonicManager.shared.disconnect()
        NotificationCenter.default.post(name: SubsonicManager.connectionStateDidChangeNotification, object: nil)
    }
    
    @objc func refreshSubsonicLibrary() {
        Task {
            await SubsonicManager.shared.preloadLibraryContent()
            NSLog("MenuActions: Subsonic library refreshed")
        }
    }
    
    @objc func showSubsonicInBrowser() {
        // Show the library browser with Subsonic source selected
        guard let serverId = SubsonicManager.shared.currentServer?.id else { return }
        
        WindowManager.shared.showPlexBrowser()
        
        // Set the browser source to Subsonic
        NotificationCenter.default.post(
            name: NSNotification.Name("SetBrowserSource"),
            object: BrowserSource.subsonic(serverId: serverId)
        )
    }
    
    // MARK: - Jellyfin
    
    @objc func addJellyfinServer() {
        WindowManager.shared.showJellyfinLinkSheet()
    }
    
    @objc func manageJellyfinServers() {
        WindowManager.shared.showJellyfinServerList()
    }
    
    @objc func selectJellyfinServer(_ sender: NSMenuItem) {
        guard let serverID = sender.representedObject as? String,
              let server = JellyfinManager.shared.servers.first(where: { $0.id == serverID }) else { return }
        Task {
            do {
                try await JellyfinManager.shared.connect(to: server)
                await MainActor.run { NotificationCenter.default.post(name: JellyfinManager.serversDidChangeNotification, object: nil) }
            } catch {
                await MainActor.run { let a = NSAlert(); a.messageText = "Failed to Connect"; a.informativeText = error.localizedDescription; a.runModal() }
            }
        }
    }
    
    @objc func disconnectJellyfin() {
        JellyfinManager.shared.disconnect()
        NotificationCenter.default.post(name: JellyfinManager.connectionStateDidChangeNotification, object: nil)
    }
    
    @objc func refreshJellyfinLibrary() {
        Task { await JellyfinManager.shared.preloadLibraryContent() }
    }
    
    @objc func showJellyfinInBrowser() {
        // Show the library browser with Jellyfin source selected
        guard let serverId = JellyfinManager.shared.currentServer?.id else { return }
        
        WindowManager.shared.showPlexBrowser()
        
        // Set the browser source to Jellyfin
        NotificationCenter.default.post(
            name: NSNotification.Name("SetBrowserSource"),
            object: BrowserSource.jellyfin(serverId: serverId)
        )
    }
    
    @objc func selectJellyfinVideoLibrary(_ sender: NSMenuItem) {
        guard let libId = sender.representedObject as? String,
              let lib = JellyfinManager.shared.videoLibraries.first(where: { $0.id == libId }) else { return }
        // Select for both movie and show (Jellyfin video libs can contain both)
        JellyfinManager.shared.selectMovieLibrary(lib)
        JellyfinManager.shared.selectShowLibrary(lib)
    }
    
    @objc func selectJellyfinMusicLibrary(_ sender: NSMenuItem) {
        if let libId = sender.representedObject as? String,
           let lib = JellyfinManager.shared.musicLibraries.first(where: { $0.id == libId }) {
            JellyfinManager.shared.selectMusicLibrary(lib)
        } else {
            JellyfinManager.shared.clearMusicLibrarySelection()
        }
    }

    // MARK: - Emby Actions

    @objc func addEmbyServer() {
        WindowManager.shared.showEmbyLinkSheet()
    }

    @objc func manageEmbyServers() {
        WindowManager.shared.showEmbyServerList()
    }

    @objc func selectEmbyServer(_ sender: NSMenuItem) {
        guard let serverID = sender.representedObject as? String,
              let server = EmbyManager.shared.servers.first(where: { $0.id == serverID }) else { return }
        Task {
            do {
                try await EmbyManager.shared.connect(to: server)
                await MainActor.run { NotificationCenter.default.post(name: EmbyManager.serversDidChangeNotification, object: nil) }
            } catch {
                await MainActor.run { let a = NSAlert(); a.messageText = "Failed to Connect"; a.informativeText = error.localizedDescription; a.runModal() }
            }
        }
    }

    @objc func disconnectEmby() {
        EmbyManager.shared.disconnect()
        NotificationCenter.default.post(name: EmbyManager.connectionStateDidChangeNotification, object: nil)
    }

    @objc func refreshEmbyLibrary() {
        Task { await EmbyManager.shared.preloadLibraryContent() }
    }

    @objc func showEmbyInBrowser() {
        guard let serverId = EmbyManager.shared.currentServer?.id else { return }

        WindowManager.shared.showPlexBrowser()

        NotificationCenter.default.post(
            name: NSNotification.Name("SetBrowserSource"),
            object: BrowserSource.emby(serverId: serverId)
        )
    }

    @objc func selectEmbyVideoLibrary(_ sender: NSMenuItem) {
        guard let libId = sender.representedObject as? String,
              let lib = EmbyManager.shared.videoLibraries.first(where: { $0.id == libId }) else { return }
        // Select for both movie and show (Emby video libs can contain both)
        EmbyManager.shared.selectMovieLibrary(lib)
        EmbyManager.shared.selectShowLibrary(lib)
    }

    @objc func selectEmbyMusicLibrary(_ sender: NSMenuItem) {
        if let libId = sender.representedObject as? String,
           let lib = EmbyManager.shared.musicLibraries.first(where: { $0.id == libId }) {
            EmbyManager.shared.selectMusicLibrary(lib)
        } else {
            EmbyManager.shared.clearMusicLibrarySelection()
        }
    }

    @objc func selectSubsonicMusicFolder(_ sender: NSMenuItem) {
        if let folderId = sender.representedObject as? String,
           let folder = SubsonicManager.shared.musicFolders.first(where: { $0.id == folderId }) {
            SubsonicManager.shared.selectMusicFolder(folder)
        } else {
            SubsonicManager.shared.clearMusicFolderSelection()
        }
    }
    
    // MARK: - Output Device
    
    @objc func selectOutputDevice(_ sender: NSMenuItem) {
        let deviceID = sender.representedObject as? AudioDeviceID
        WindowManager.shared.audioEngine.setOutputDevice(deviceID)
    }
    
    @objc func openSoundSettings() {
        // Open System Settings > Sound
        if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc func selectAirPlayDevice(_ sender: NSMenuItem) {
        // AirPlay devices need to be selected in Sound Settings first
        // Show an alert explaining this
        guard let deviceName = sender.representedObject as? String else { return }
        
        let alert = NSAlert()
        alert.messageText = "Select \(deviceName)"
        alert.informativeText = "To use this AirPlay device, select it in Sound Settings, then choose 'System Default' in NullPlayer.\n\nOpening Sound Settings..."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Sound Settings")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            openSoundSettings()
        }
    }
    
    // MARK: - Casting
    
    @objc func castToDevice(_ sender: NSMenuItem) {
        guard let device = sender.representedObject as? CastDevice else { return }
        
        Task {
            do {
                try await CastManager.shared.castCurrentTrack(to: device)
                NSLog("MenuActions: Started casting to %@", device.name)
            } catch {
                NSLog("MenuActions: Failed to cast: %@", error.localizedDescription)
                
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Casting Failed"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }
    
    @objc func stopCasting() {
        Task {
            await CastManager.shared.stopCasting()
            NSLog("MenuActions: Stopped casting")
        }
    }
    
    @objc func refreshCastDevices() {
        CastManager.shared.refreshDevices()
        NSLog("MenuActions: Refreshing cast devices")
    }
    
    @objc func refreshSonosRooms() {
        Task {
            await CastManager.shared.refreshSonosGroups()
            NSLog("MenuActions: Refreshed Sonos rooms")
        }
    }
    
    @objc func castToSonosRoom(_ sender: NSMenuItem) {
        let castManager = CastManager.shared
        
        // Check if music is loaded
        guard WindowManager.shared.audioEngine.currentTrack != nil else {
            NSLog("MenuActions: Cannot cast - no music loaded")
            Task { @MainActor in
                let alert = NSAlert()
                alert.messageText = "No Music"
                alert.informativeText = "Load a track before casting."
                alert.alertStyle = .warning
                alert.runModal()
            }
            return
        }
        
        // Get selected rooms
        let selectedUDNs = castManager.selectedSonosRooms
        
        // If no rooms selected, show error
        if selectedUDNs.isEmpty {
            NSLog("MenuActions: Cannot cast - no rooms selected")
            Task { @MainActor in
                let alert = NSAlert()
                alert.messageText = "No Room Selected"
                alert.informativeText = "Select a room first by checking it in the Sonos menu."
                alert.alertStyle = .warning
                alert.runModal()
            }
            return
        }
        
        // Find a device to cast to
        // sonosRooms has room UDNs, but sonosDevices only has group coordinator devices
        // We need to find a device that matches one of our selected rooms
        let rooms = castManager.sonosRooms
        let devices = castManager.sonosDevices
        
        NSLog("MenuActions: Selected UDNs: %@", selectedUDNs.joined(separator: ", "))
        NSLog("MenuActions: Available devices: %@", devices.map { "\($0.name):\($0.id)" }.joined(separator: ", "))
        NSLog("MenuActions: Available rooms: %@", rooms.map { "\($0.name):\($0.id)" }.joined(separator: ", "))
        
        // Find the first device that matches a selected room
        var targetDevice: CastDevice?
        var targetRoomUDN: String?
        
        for udn in selectedUDNs {
            // First try direct match (room is a coordinator)
            if let device = devices.first(where: { $0.id == udn }) {
                targetDevice = device
                targetRoomUDN = udn
                break
            }
            
            // If no direct match, find by room name
            if let room = rooms.first(where: { $0.id == udn }) {
                if let device = devices.first(where: { $0.name.hasPrefix(room.name) }) {
                    targetDevice = device
                    targetRoomUDN = udn
                    break
                }
            }
        }
        
        // If still no match, just use the first available Sonos device
        // IMPORTANT: Set targetRoomUDN to the device we're actually casting to, not a selected room.
        // This ensures all selected rooms get joined to the group in the loop below.
        // (Previously this was set to selectedUDNs.first, which caused that room to be
        // incorrectly filtered out of the join loop even though it wasn't receiving audio.)
        if targetDevice == nil, let firstDevice = devices.first {
            NSLog("MenuActions: No exact match, using first available device: %@", firstDevice.name)
            targetDevice = firstDevice
            targetRoomUDN = firstDevice.id
        }
        
        guard let device = targetDevice, let firstUDN = targetRoomUDN else {
            NSLog("MenuActions: Could not find any Sonos device to cast to")
            Task { @MainActor in
                let alert = NSAlert()
                alert.messageText = "No Device Found"
                alert.informativeText = "Could not find a Sonos device to cast to. Try refreshing."
                alert.alertStyle = .warning
                alert.runModal()
            }
            return
        }
        
        Task {
            do {
                // Start casting to first room
                NSLog("MenuActions: Starting cast to '%@' (id: %@)", device.name, device.id)
                try await castManager.castCurrentTrack(to: device)
                
                // Join additional selected rooms to the group
                let otherUDNs = selectedUDNs.filter { $0 != firstUDN }
                if !otherUDNs.isEmpty {
                    // Wait a moment for cast to establish
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    
                    for udn in otherUDNs {
                        NSLog("MenuActions: Joining room %@ to cast group (coordinator: %@)", udn, device.id)
                        try await castManager.joinSonosToGroup(zoneUDN: udn, coordinatorUDN: device.id)
                        try? await Task.sleep(nanoseconds: 200_000_000)
                    }
                }
                
                // Refresh topology
                await castManager.refreshSonosGroups()
                
            } catch {
                NSLog("MenuActions: Cast to Sonos failed: %@", error.localizedDescription)
                // Clean up any partial session state to prevent local+cast conflict
                await castManager.stopCasting()
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Cast Failed"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }
    
    // MARK: - Sonos Grouping
    
    @objc func sonosRoomJoinGroup(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? SonosRoomAction,
              case .join(let coordinatorUDN, let coordinatorName) = action.action else { return }
        
        Task {
            do {
                NSLog("MenuActions: Joining room '%@' to '%@'", action.roomName, coordinatorName)
                try await CastManager.shared.joinSonosToGroup(
                    zoneUDN: action.roomUDN,
                    coordinatorUDN: coordinatorUDN
                )
                NSLog("MenuActions: '%@' joined '%@'", action.roomName, coordinatorName)
            } catch {
                NSLog("MenuActions: Sonos grouping failed: %@", error.localizedDescription)
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Sonos Grouping Failed"
                    alert.informativeText = "Could not join \(action.roomName) to \(coordinatorName): \(error.localizedDescription)"
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }
    
    @objc func sonosRoomLeaveGroup(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? SonosRoomAction,
              case .leave = action.action else { return }
        
        Task {
            do {
                NSLog("MenuActions: Making room '%@' standalone", action.roomName)
                try await CastManager.shared.unjoinSonos(zoneUDN: action.roomUDN)
                NSLog("MenuActions: '%@' is now standalone", action.roomName)
            } catch {
                NSLog("MenuActions: Sonos ungrouping failed: %@", error.localizedDescription)
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Sonos Ungrouping Failed"
                    alert.informativeText = "Could not make \(action.roomName) standalone: \(error.localizedDescription)"
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }
    
    /// Toggle a Sonos room in/out of cast group
    @objc func toggleSonosRoom(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? SonosRoomToggle else {
            NSLog("MenuActions: toggleSonosRoom - no info found")
            return
        }
        
        let castManager = CastManager.shared
        let isCastingToSonos = castManager.activeSession?.device.type == .sonos
        
        NSLog("MenuActions: toggleSonosRoom '%@' isChecked=%d isCasting=%d", 
              info.roomName, info.isCurrentlyInGroup ? 1 : 0, isCastingToSonos ? 1 : 0)
        
        if isCastingToSonos {
            // WHILE CASTING: toggle actually joins/unjoins the Sonos group
            Task {
                do {
                    if info.isCurrentlyInGroup {
                        // Currently receiving audio - remove from group
                        NSLog("MenuActions: Removing '%@' from cast group", info.roomName)
                        try await castManager.unjoinSonos(zoneUDN: info.roomUDN)
                    } else {
                        // Not receiving audio - join to active cast
                        if let coordinatorUDN = castManager.activeSession?.device.id {
                            NSLog("MenuActions: Adding '%@' to cast group", info.roomName)
                            try await castManager.joinSonosToGroup(
                                zoneUDN: info.roomUDN,
                                coordinatorUDN: coordinatorUDN
                            )
                        }
                    }
                    
                    // Refresh topology to update UI
                    await castManager.refreshSonosGroups()
                    NSLog("MenuActions: Toggle complete for '%@'", info.roomName)
                    
                } catch {
                    NSLog("MenuActions: Toggle failed for '%@': %@", info.roomName, error.localizedDescription)
                }
            }
        } else {
            // NOT CASTING: just toggle selection state (stored locally)
            if info.isCurrentlyInGroup {
                castManager.selectedSonosRooms.remove(info.roomUDN)
                NSLog("MenuActions: Deselected '%@' for casting", info.roomName)
            } else {
                castManager.selectedSonosRooms.insert(info.roomUDN)
                NSLog("MenuActions: Selected '%@' for casting", info.roomName)
            }
        }
    }
    
    /// Legacy toggle handler
    @objc func toggleSonosZoneInGroup(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? SonosGroupingInfo else { return }
        
        Task {
            do {
                if info.isCurrentlyInGroup {
                    NSLog("MenuActions: Removing '%@' from group '%@'", info.zoneName, info.coordinatorName)
                    try await CastManager.shared.unjoinSonos(zoneUDN: info.zoneUDN)
                } else {
                    NSLog("MenuActions: Adding '%@' to group '%@'", info.zoneName, info.coordinatorName)
                    try await CastManager.shared.joinSonosToGroup(
                        zoneUDN: info.zoneUDN,
                        coordinatorUDN: info.coordinatorUDN
                    )
                }
            } catch {
                NSLog("MenuActions: Sonos grouping failed: %@", error.localizedDescription)
            }
        }
    }
    
    @objc func ungroupAllSonos() {
        let rooms = CastManager.shared.sonosRooms
        
        // Find rooms that are in groups
        let roomsToUnjoin = rooms.filter { $0.isInGroup }
        
        if roomsToUnjoin.isEmpty {
            NSLog("MenuActions: No rooms to ungroup")
            return
        }
        
        NSLog("MenuActions: Ungrouping %d rooms", roomsToUnjoin.count)
        
        Task {
            // Use actor-isolated storage for thread safety
            actor FailedRoomsCollector {
                var failed: [String] = []
                func add(_ name: String) { failed.append(name) }
                func getAll() -> [String] { failed }
            }
            let collector = FailedRoomsCollector()
            
            for room in roomsToUnjoin {
                do {
                    try await CastManager.shared.unjoinSonos(zoneUDN: room.id)
                    NSLog("MenuActions: Ungrouped '%@'", room.name)
                } catch {
                    NSLog("MenuActions: Failed to ungroup '%@': %@", room.name, error.localizedDescription)
                    await collector.add(room.name)
                }
                
                // Small delay between commands to avoid overwhelming Sonos
                try? await Task.sleep(nanoseconds: 300_000_000)  // 0.3 seconds
            }
            
            let failedRooms = await collector.getAll()
            if !failedRooms.isEmpty {
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Some Rooms Failed to Ungroup"
                    alert.informativeText = "Failed to ungroup: \(failedRooms.joined(separator: ", "))"
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            } else {
                NSLog("MenuActions: All rooms ungrouped successfully")
            }
        }
    }
    
    // MARK: - Local Library
    
    @objc func backupLibrary() {
        do {
            let backupURL = try MediaLibrary.shared.backupLibrary()
            
            let alert = NSAlert()
            alert.messageText = "Library Backed Up"
            alert.informativeText = "Your library has been backed up to:\n\(backupURL.lastPathComponent)"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Show in Finder")
            
            if alert.runModal() == .alertSecondButtonReturn {
                NSWorkspace.shared.selectFile(backupURL.path, inFileViewerRootedAtPath: backupURL.deletingLastPathComponent().path)
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Backup Failed"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
    
    @objc func restoreLibraryFromFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.init(filenameExtension: "db")!, .json]
        panel.title = "Select Library Backup"
        panel.message = "Choose a library backup file to restore"
        
        // Start in backups directory if it exists
        let backupsDir = MediaLibrary.shared.backupsDirectory
        if FileManager.default.fileExists(atPath: backupsDir.path) {
            panel.directoryURL = backupsDir
        }
        
        if panel.runModal() == .OK, let url = panel.url {
            confirmAndRestoreLibrary(from: url)
        }
    }
    
    @objc func restoreLibraryFromBackup(_ sender: NSMenuItem) {
        guard let backupURL = sender.representedObject as? URL else { return }
        confirmAndRestoreLibrary(from: backupURL)
    }
    
    private func confirmAndRestoreLibrary(from url: URL) {
        let currentTrackCount = MediaLibrary.shared.tracksSnapshot.count
        
        let alert = NSAlert()
        alert.messageText = "Restore Library?"
        alert.informativeText = "This will replace your current library (\(currentTrackCount) tracks) with the backup.\n\nA backup of your current library will be created automatically before restoring."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            do {
                try MediaLibrary.shared.restoreLibrary(from: url)
                
                let newTrackCount = MediaLibrary.shared.tracksSnapshot.count
                
                let successAlert = NSAlert()
                successAlert.messageText = "Library Restored"
                successAlert.informativeText = "Your library has been restored with \(newTrackCount) tracks."
                successAlert.alertStyle = .informational
                successAlert.runModal()
            } catch {
                let errorAlert = NSAlert()
                errorAlert.messageText = "Restore Failed"
                errorAlert.informativeText = error.localizedDescription
                errorAlert.alertStyle = .critical
                errorAlert.runModal()
            }
        }
    }
    
    @objc func manageFolders() {
        WatchFolderManagerDialog.present {}
    }

    @objc func showLibraryInFinder() {
        MediaLibrary.shared.showLibraryInFinder()
    }

    @objc func showBackupsInFinder() {
        MediaLibrary.shared.showBackupsInFinder()
    }
    
    @objc func clearLocalMusic() {
        performLocalLibraryClear(.music)
    }

    @objc func clearLocalMovies() {
        performLocalLibraryClear(.movies)
    }

    @objc func clearLocalTV() {
        performLocalLibraryClear(.tv)
    }

    @objc func clearLibrary() {
        performLocalLibraryClear(.all)
    }

    private enum LocalLibraryClearScope {
        case music
        case movies
        case tv
        case all

        var dialogTitle: String {
            switch self {
            case .music: return "Clear Music?"
            case .movies: return "Clear Movies?"
            case .tv: return "Clear TV?"
            case .all: return "Clear Library?"
            }
        }

        var backupName: String {
            switch self {
            case .music: return "pre_clear_music_auto_backup"
            case .movies: return "pre_clear_movies_auto_backup"
            case .tv: return "pre_clear_tv_auto_backup"
            case .all: return "pre_clear_auto_backup"
            }
        }
    }

    private func performLocalLibraryClear(_ scope: LocalLibraryClearScope) {
        let store = MediaLibraryStore.shared
        let trackCount = store.trackCount()
        let movieCount = store.movieCount()
        let episodeCount = store.episodeCount()
        let totalCount = trackCount + movieCount + episodeCount

        let targetCount: Int
        let targetLabel: String
        let informativeText: String
        let confirmTitle: String

        switch scope {
        case .music:
            targetCount = trackCount
            targetLabel = "music track\(targetCount == 1 ? "" : "s")"
            informativeText = "This will remove \(targetCount) \(targetLabel) from your library. Files on disk will NOT be deleted.\n\nA backup will be created automatically before clearing."
            confirmTitle = "Clear Music"
        case .movies:
            targetCount = movieCount
            targetLabel = "movie\(targetCount == 1 ? "" : "s")"
            informativeText = "This will remove \(targetCount) \(targetLabel) from your library. Files on disk will NOT be deleted.\n\nA backup will be created automatically before clearing."
            confirmTitle = "Clear Movies"
        case .tv:
            targetCount = episodeCount
            targetLabel = "TV episode\(targetCount == 1 ? "" : "s")"
            informativeText = "This will remove \(targetCount) \(targetLabel) from your library. Files on disk will NOT be deleted.\n\nA backup will be created automatically before clearing."
            confirmTitle = "Clear TV"
        case .all:
            targetCount = totalCount
            targetLabel = "local item\(targetCount == 1 ? "" : "s")"
            informativeText = "This will remove \(targetCount) \(targetLabel) from your library (\(trackCount) tracks, \(movieCount) movies, \(episodeCount) episodes). Files on disk will NOT be deleted.\n\nA backup will be created automatically before clearing."
            confirmTitle = "Clear Library"
        }

        guard targetCount > 0 else {
            let alert = NSAlert()
            alert.messageText = "Nothing to Clear"
            switch scope {
            case .music:
                alert.informativeText = "No local music tracks are currently in the library."
            case .movies:
                alert.informativeText = "No local movies are currently in the library."
            case .tv:
                alert.informativeText = "No local TV episodes are currently in the library."
            case .all:
                alert.informativeText = "No local tracks, movies, or episodes are currently in the library."
            }
            alert.alertStyle = .informational
            alert.runModal()
            return
        }
        
        let alert = NSAlert()
        alert.messageText = scope.dialogTitle
        alert.informativeText = informativeText
        alert.alertStyle = .critical
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            do {
                try MediaLibrary.shared.backupLibrary(customName: scope.backupName)
            } catch {
                NSLog("Failed to create pre-clear backup: %@", error.localizedDescription)
            }

            switch scope {
            case .music:
                MediaLibrary.shared.clearMusicLibrary()
            case .movies:
                MediaLibrary.shared.clearMovieLibrary()
            case .tv:
                MediaLibrary.shared.clearTVLibrary()
            case .all:
                MediaLibrary.shared.clearLibrary()
            }
            
            let successAlert = NSAlert()
            successAlert.messageText = "Library Updated"
            successAlert.informativeText = "Removed \(targetCount) \(targetLabel). A backup was saved automatically."
            successAlert.alertStyle = .informational
            successAlert.runModal()
        }
    }
    
    // MARK: - Visualizations
    
    @objc func addVisualizationsFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.title = "Select Visualizations Folder"
        panel.message = "Choose a folder containing .milk preset files"
        panel.prompt = "Add Folder"
        
        if panel.runModal() == .OK, let url = panel.url {
            // Count .milk files in the selected folder
            let fileManager = FileManager.default
            var milkCount = 0
            if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: nil) {
                while let fileURL = enumerator.nextObject() as? URL {
                    if fileURL.pathExtension.lowercased() == "milk" {
                        milkCount += 1
                    }
                }
            }
            
            if milkCount == 0 {
                let alert = NSAlert()
                alert.messageText = "No Presets Found"
                alert.informativeText = "The selected folder doesn't contain any .milk preset files. Please choose a folder with projectM presets."
                alert.alertStyle = .warning
                alert.runModal()
                return
            }
            
            // Save the custom folder path
            ProjectMWrapper.customPresetsFolder = url.path
            
            // Reload presets
            WindowManager.shared.reloadVisualizationPresets()
            
            let alert = NSAlert()
            alert.messageText = "Presets Added"
            alert.informativeText = "Found \(milkCount) preset files in the selected folder. Presets have been reloaded."
            alert.alertStyle = .informational
            alert.runModal()
            
            NSLog("MenuActions: Added custom visualizations folder: %@", url.path)
        }
    }
    
    @objc func showVisualizationsFolder() {
        guard let customPath = ProjectMWrapper.customPresetsFolder else { return }
        
        let url = URL(fileURLWithPath: customPath)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
    }
    
    @objc func removeVisualizationsFolder() {
        guard ProjectMWrapper.customPresetsFolder != nil else { return }
        
        let alert = NSAlert()
        alert.messageText = "Remove Custom Presets Folder?"
        alert.informativeText = "This will remove the custom presets folder from NullPlayer. The folder and its files will not be deleted from disk.\n\nOnly bundled presets will be available after this."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            ProjectMWrapper.customPresetsFolder = nil
            WindowManager.shared.reloadVisualizationPresets()
            
            NSLog("MenuActions: Removed custom visualizations folder")
        }
    }
    
    @objc func rescanVisualizations() {
        WindowManager.shared.reloadVisualizationPresets()
        
        let info = WindowManager.shared.visualizationPresetsInfo
        let total = WindowManager.shared.visualizationPresetCount
        
        let alert = NSAlert()
        alert.messageText = "Presets Rescanned"
        if info.customPath != nil {
            alert.informativeText = "Found \(total) presets (\(info.bundledCount) bundled, \(info.customCount) custom)"
        } else {
            alert.informativeText = "Found \(total) bundled presets"
        }
        alert.alertStyle = .informational
        alert.runModal()
        
        NSLog("MenuActions: Rescanned visualizations - %d total presets", total)
    }
    
    @objc func showBundledPresets() {
        guard let bundledPath = ProjectMWrapper.bundledPresetsPath else {
            let alert = NSAlert()
            alert.messageText = "Bundled Presets Not Found"
            alert.informativeText = "The bundled presets directory could not be located."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }
        
        let url = URL(fileURLWithPath: bundledPath)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
    }
    
    // MARK: - Exit
    
    @objc func exit() {
        NSApp.terminate(nil)
    }
}
