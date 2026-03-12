import Foundation

/// Resolves service-backed streaming tracks to fresh stream URLs using persisted IDs.
enum StreamingTrackResolver {

    static func resolve(_ track: Track) async -> Track? {
        if let ratingKey = track.plexRatingKey {
            return await resolvePlexTrack(
                ratingKey: ratingKey,
                serverId: track.plexServerId
            )
        }
        if let songId = track.subsonicId {
            return await resolveSubsonicTrack(
                songId: songId,
                serverId: track.subsonicServerId
            )
        }
        if let songId = track.jellyfinId {
            return await resolveJellyfinTrack(
                songId: songId,
                serverId: track.jellyfinServerId
            )
        }
        if let songId = track.embyId {
            return await resolveEmbyTrack(
                songId: songId,
                serverId: track.embyServerId
            )
        }
        return nil
    }

    private static func resolvePlexTrack(ratingKey: String, serverId: String?) async -> Track? {
        guard let client = await plexClient(for: serverId) else {
            NSLog("StreamingTrackResolver: no Plex client available for track %@", ratingKey)
            return nil
        }

        do {
            guard let plexTrack = try await client.fetchTrackDetails(trackID: ratingKey),
                  let streamURL = client.streamURL(for: plexTrack) else {
                return nil
            }

            let media = plexTrack.media.first
            var artist = plexTrack.grandparentTitle
            let title = plexTrack.title
            if let artistName = artist,
               title.lowercased().hasPrefix(artistName.lowercased() + " - ") {
                artist = nil
            }

            return Track(
                url: streamURL,
                title: title,
                artist: artist,
                album: plexTrack.parentTitle,
                duration: plexTrack.durationInSeconds,
                bitrate: media?.bitrate,
                sampleRate: media?.audioSampleRate,
                channels: media?.audioChannels,
                plexRatingKey: plexTrack.id,
                plexServerId: serverId ?? PlexManager.shared.currentServer?.id,
                artworkThumb: plexTrack.thumb,
                genre: plexTrack.genre
            )
        } catch {
            NSLog("StreamingTrackResolver: failed Plex track refresh %@: %@", ratingKey, error.localizedDescription)
            return nil
        }
    }

    private static func resolveSubsonicTrack(songId: String, serverId: String?) async -> Track? {
        let client: SubsonicServerClient?
        if let serverId, let credentials = KeychainHelper.shared.getSubsonicServer(id: serverId) {
            client = SubsonicServerClient(credentials: credentials)
        } else {
            client = SubsonicManager.shared.serverClient
        }

        guard let client else {
            NSLog("StreamingTrackResolver: no Subsonic client available for song %@", songId)
            return nil
        }

        do {
            guard let song = try await client.fetchSong(id: songId),
                  let streamURL = client.streamURL(for: song) else {
                return nil
            }

            let mimeType = song.contentType ?? song.suffix.map {
                CastManager.detectAudioContentType(forExtension: $0)
            }

            return Track(
                url: streamURL,
                title: song.title,
                artist: song.artist,
                album: song.album,
                duration: song.durationInSeconds,
                bitrate: song.bitRate,
                sampleRate: song.samplingRate,
                channels: nil,
                plexRatingKey: nil,
                subsonicId: song.id,
                subsonicServerId: serverId ?? SubsonicManager.shared.currentServer?.id,
                artworkThumb: song.coverArt,
                genre: song.genre,
                contentType: mimeType
            )
        } catch {
            NSLog("StreamingTrackResolver: failed Subsonic track refresh %@: %@", songId, error.localizedDescription)
            return nil
        }
    }

    private static func resolveJellyfinTrack(songId: String, serverId: String?) async -> Track? {
        let client: JellyfinServerClient?
        if let serverId, let credentials = KeychainHelper.shared.getJellyfinServer(id: serverId) {
            client = JellyfinServerClient(credentials: credentials)
        } else {
            client = JellyfinManager.shared.serverClient
        }

        guard let client else {
            NSLog("StreamingTrackResolver: no Jellyfin client available for song %@", songId)
            return nil
        }

        do {
            guard let song = try await client.fetchSong(id: songId),
                  let streamURL = client.streamURL(for: song) else {
                return nil
            }

            let mimeType = song.contentType.map {
                CastManager.detectAudioContentType(forExtension: $0)
            }

            return Track(
                url: streamURL,
                title: song.title,
                artist: song.artist,
                album: song.album,
                duration: song.durationInSeconds,
                bitrate: song.bitRate,
                sampleRate: song.sampleRate,
                channels: song.channels,
                plexRatingKey: nil,
                subsonicId: nil,
                subsonicServerId: nil,
                jellyfinId: song.id,
                jellyfinServerId: serverId ?? JellyfinManager.shared.currentServer?.id,
                artworkThumb: song.imageTag,
                genre: song.genre,
                contentType: mimeType
            )
        } catch {
            NSLog("StreamingTrackResolver: failed Jellyfin track refresh %@: %@", songId, error.localizedDescription)
            return nil
        }
    }

    private static func resolveEmbyTrack(songId: String, serverId: String?) async -> Track? {
        let client: EmbyServerClient?
        if let serverId, let credentials = KeychainHelper.shared.getEmbyServer(id: serverId) {
            client = EmbyServerClient(credentials: credentials)
        } else {
            client = EmbyManager.shared.serverClient
        }

        guard let client else {
            NSLog("StreamingTrackResolver: no Emby client available for song %@", songId)
            return nil
        }

        do {
            guard let song = try await client.fetchSong(id: songId),
                  let streamURL = client.streamURL(for: song) else {
                return nil
            }

            let mimeType = song.contentType.map {
                CastManager.detectAudioContentType(forExtension: $0)
            }

            return Track(
                url: streamURL,
                title: song.title,
                artist: song.artist,
                album: song.album,
                duration: song.durationInSeconds,
                bitrate: song.bitRate,
                sampleRate: song.sampleRate,
                channels: song.channels,
                plexRatingKey: nil,
                subsonicId: nil,
                subsonicServerId: nil,
                jellyfinId: nil,
                jellyfinServerId: nil,
                embyId: song.id,
                embyServerId: serverId ?? EmbyManager.shared.currentServer?.id,
                artworkThumb: song.imageTag,
                genre: song.genre,
                contentType: mimeType
            )
        } catch {
            NSLog("StreamingTrackResolver: failed Emby track refresh %@: %@", songId, error.localizedDescription)
            return nil
        }
    }

    private static func plexClient(for serverId: String?, timeout: TimeInterval = 15) async -> PlexServerClient? {
        if let serverId,
           let currentServer = PlexManager.shared.currentServer,
           currentServer.id == serverId,
           let currentClient = PlexManager.shared.serverClient {
            return currentClient
        }

        if serverId == nil, let currentClient = PlexManager.shared.serverClient {
            return currentClient
        }

        guard let account = KeychainHelper.shared.getPlexAccount() else {
            return nil
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let serverId,
               let server = PlexManager.shared.servers.first(where: { $0.id == serverId }),
               let client = PlexServerClient(server: server, authToken: account.authToken) {
                return client
            }

            if serverId == nil,
               let server = PlexManager.shared.currentServer,
               let client = PlexServerClient(server: server, authToken: account.authToken) {
                return client
            }

            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        return nil
    }
}
