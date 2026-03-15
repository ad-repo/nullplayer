---
name: emby-integration
description: Emby API, authentication flow, rating scale, streaming, scrobbling, and video playback. Use when working on Emby integration, library browsing, playback reporting, or video casting.
---

# Emby Integration

NullPlayer supports Emby media servers for music streaming, video playback (movies and TV shows), browsing, and scrobbling.

## Architecture

| File | Purpose |
|------|---------|
| `Emby/EmbyModels.swift` | Domain models (Server, Artist, Album, Song, Playlist, Movie, Show, Season, Episode) and API DTOs |
| `Emby/EmbyServerClient.swift` | HTTP client for Emby REST API (music + video) |
| `Emby/EmbyManager.swift` | Singleton managing connections, caching, and track conversion (music + video) |
| `Emby/EmbyPlaybackReporter.swift` | Audio scrobbling and "now playing" reporting |
| `Emby/EmbyVideoPlaybackReporter.swift` | Video scrobbling with periodic timeline updates |
| `Emby/EmbyLinkSheet.swift` | Server add/edit/manage UI dialogs |

## Authentication

Emby uses a different `Authorization` header format than Jellyfin.

**Before auth** (POST /Users/AuthenticateByName):
```
Authorization: Emby Client="NullPlayer", Device="Mac", DeviceId="{uuid}", Version="1.0"
```

**After auth** (all subsequent requests):
```
Authorization: Emby UserId="{userId}", Client="NullPlayer", Device="Mac", DeviceId="{uuid}", Version="1.0", Token="{accessToken}"
X-Emby-Token: {accessToken}
```

The key differences from Jellyfin:
- Prefix is `Emby` (Jellyfin uses `MediaBrowser`)
- `UserId` is included in the Authorization header after login
- `Token` is appended to the Authorization header after login

- **Auth**: `POST /Users/AuthenticateByName`
  - Body: `{"Username":"x","Pw":"y"}`
  - Returns JSON with `AccessToken` and `User.Id`
  - Access token stored in keychain

- **Ping**: `GET /System/Ping` (returns 200 if server is reachable)

## Library Browsing

- **All libraries/views**: `GET /Users/{userId}/Views`
  - `fetchMusicLibraries()` returns all views (unfiltered).
  - `fetchVideoLibraries()` uses the same endpoint but filters out non-video library types (`music`, `musicvideos`, `books`, `photos`, `playlists`, `livetv`).
- **Artists**: `GET /Artists/AlbumArtists?parentId={libId}&userId={userId}&Recursive=true&SortBy=SortName`
- **Albums**: `GET /Users/{userId}/Items?parentId={libId}&IncludeItemTypes=MusicAlbum&Recursive=true`
- **Artist albums**: `GET /Users/{userId}/Items?AlbumArtistIds={artistId}&IncludeItemTypes=MusicAlbum`
- **Album tracks**: `GET /Users/{userId}/Items?parentId={albumId}&IncludeItemTypes=Audio`
- **Playlists**: `GET /Users/{userId}/Items?IncludeItemTypes=Playlist&Recursive=true`
- **Search**: `GET /Items?searchTerm={q}&IncludeItemTypes=Audio,MusicAlbum,MusicArtist,Movie,Series,Episode`

## Video Browsing

- **Movies**: `GET /Users/{userId}/Items?parentId={libId}&IncludeItemTypes=Movie&MediaTypes=Video`
- **Series**: `GET /Users/{userId}/Items?parentId={libId}&IncludeItemTypes=Series`
- **Seasons**: `GET /Shows/{seriesId}/Seasons?userId={userId}`
- **Episodes**: `GET /Shows/{seriesId}/Episodes?userId={userId}&seasonId={seasonId}&MediaTypes=Video`

## Streaming

- **Audio Stream**: `GET /Audio/{itemId}/stream?static=true&api_key={token}`
- **Video Stream**: `GET /Videos/{itemId}/stream?static=true&api_key={token}`

## Images

- **Image**: `GET /Items/{itemId}/Images/Primary?maxHeight={size}&maxWidth={size}&tag={imageTag}`
  - `imageTag` is from `ImageTags.Primary` in the item response

## User Actions

- **Favorite**: `POST /Users/{userId}/FavoriteItems/{itemId}` (add), `DELETE` (remove)
- **Rate**: `POST /Users/{userId}/Items/{itemId}/Rating?likes=true`
- **Scrobble**: `POST /Users/{userId}/PlayedItems/{itemId}`

## Playback Reporting

Same Sessions endpoints as Jellyfin:

- **Start**: `POST /Sessions/Playing`
  - Body: `{"ItemId":"{id}","CanSeek":true,"PlayMethod":"DirectStream"}`

- **Progress**: `POST /Sessions/Playing/Progress`
  - Body: `{"ItemId":"{id}","PositionTicks":{ticks},"IsPaused":false}`

- **Stopped**: `POST /Sessions/Playing/Stopped`
  - Body: `{"ItemId":"{id}","PositionTicks":{ticks}}`

## Rating Scale

Emby `UserData.Rating` is 0-100%. The app uses 0-10 internal scale.

Mapping:
- `emby_rating = internal_rating * 10`
- `internal_rating = emby_rating / 10`
- Each star = 20%

## Ticks

Emby uses ticks for duration/position: 1 tick = 10,000 nanoseconds = 0.00001 seconds.

Convert: `ticks = seconds * 10_000_000`

## Track Identification

Emby tracks in the playlist are identified by:
- `track.embyId` — the Emby item UUID
- `track.embyServerId` — which Emby server the track belongs to

## Scrobbling

`EmbyPlaybackReporter` follows the same rules as `JellyfinPlaybackReporter`:
- Reports "now playing" immediately on track start (via `POST /Sessions/Playing`)
- Reports progress periodically (via `POST /Sessions/Playing/Progress`)
- Scrobbles after 50% of track or 4 minutes, whichever comes first
- Reports stopped on track end/stop (via `POST /Sessions/Playing/Stopped`)

## Video Playback Reporter

`EmbyVideoPlaybackReporter` mirrors `JellyfinVideoPlaybackReporter`:
- Video scrobble threshold: 90% (vs 50% for audio)
- Minimum play time: 60s before scrobbling
- Periodic timeline updates every 10s via `POST /Sessions/Playing/Progress` with `PositionTicks`
- Tracks pause/resume state with `IsPaused` flag
- Uses ticks (`seconds × 10_000_000`) for Emby API

## Library Selection

`EmbyManager` maintains separate current selections for music and video content.

### Music Library Selection
- `musicLibraries: [EmbyMusicLibrary]` — all server views
- `currentMusicLibrary: EmbyMusicLibrary?` — nil means "all libraries"
- `selectMusicLibrary(_ library:)` — set specific library, clears cache, triggers preload
- `clearMusicLibrarySelection()` — resets to nil (all libraries)
- Posts `musicLibraryDidChangeNotification` on change
- Persisted via `EmbyCurrentMusicLibraryID` UserDefaults key

### Video Library Selection
- `currentMovieLibrary: EmbyMusicLibrary?` — nil means "all libraries"
- `currentShowLibrary: EmbyMusicLibrary?` — nil means "all libraries"
- `selectMovieLibrary(_ library: EmbyMusicLibrary?)` — accepts nil to clear
- `selectShowLibrary(_ library: EmbyMusicLibrary?)` — accepts nil to clear
- Posts `videoLibraryDidChangeNotification` on change
- Persisted via `EmbyCurrentMovieLibraryID` / `EmbyCurrentShowLibraryID`

### Library Browser UI
The status bar "Lib:" zone is browse-mode-aware:
- Music tabs (Artists/Albums/Tracks/Plists) → shows `currentMusicLibrary`, opens music picker
- Movies tab → shows `currentMovieLibrary`, opens video picker
- Shows tab → shows `currentShowLibrary`, opens video picker
- "All" shown and selectable when no specific library is chosen

## Artist Expansion Performance

When expanding an Emby artist in the library browser, albums are resolved from the preloaded cache (`cachedEmbyAlbums`) by filtering on `artistId`, making expansion instant. Network fallback only occurs if the cache has no matching albums.

**Important**: Expand tasks must use `Task.detached` (not `Task { }`) to avoid inheriting cancellation state from the calling context.

## Casting

Emby tracks support casting to Sonos, Chromecast, and DLNA devices:
- Sonos requires proxy — `needsEmbyProxy` flag in `CastManager`
- Artwork is loaded via `EmbyManager.shared.imageURL()`
- Stream URLs use `api_key` auth parameter

### Video Casting
- `CastManager.castEmbyMovie(_:to:startPosition:)` — cast a movie
- `CastManager.castEmbyEpisode(_:to:startPosition:)` — cast an episode
- Stream URL uses `/Videos/{id}/stream?static=true&api_key={token}`
- `VideoPlayerWindowController.play(embyMovie:)` / `play(embyEpisode:)` for local playback

## Credential Storage

Emby credentials are stored using `KeychainHelper`:
- Key: `emby_servers`
- Stores: `[EmbyServerCredentials]` (includes access token and userId)
- Uses the macOS login keychain with a permissive `SecAccessCreate` ACL. Do NOT add `kSecUseDataProtectionKeychain` or `kSecAttrAccessible` — they require entitlements that ad-hoc signed DMG builds don't have and cause `-34018 errSecMissingEntitlement`.

## State Persistence

- Current server ID: `EmbyCurrentServerID` (UserDefaults)
- Current music library ID: `EmbyCurrentMusicLibraryID` (UserDefaults) — nil = all libraries
- Current movie library ID: `EmbyCurrentMovieLibraryID` (UserDefaults) — nil = all libraries
- Current show library ID: `EmbyCurrentShowLibraryID` (UserDefaults) — nil = all libraries
- Playlist tracks with `embyId`/`embyServerId` are saved/restored by `AppStateManager`

## Relationship to Jellyfin

Emby and Jellyfin share the same MediaBrowser API ancestry. The REST endpoints are nearly identical. Key differences:
- **Auth header prefix**: Emby uses `Emby`, Jellyfin uses `MediaBrowser`
- **UserId in header**: Emby includes `UserId=` in Authorization after login; Jellyfin does not
- Emby and Jellyfin can coexist — all integration code is in separate `Emby/` files

## Implementation Gotchas

- **Library selector is browse-mode-aware**: The "Lib:" click zone shows a music library picker in music tabs (Artists/Albums/Tracks/Plists) and a video library picker in Movies/Shows tabs. `EmbyManager` has separate `currentMusicLibrary`, `currentMovieLibrary`, and `currentShowLibrary` — each posts its own notification. `selectMovieLibrary(_:)` and `selectShowLibrary(_:)` accept `nil` to show all.
- **Streaming URL content type (Sonos)**: Emby stream URLs (`/Audio/{id}/stream`) have no file extension, so `detectAudioContentType(for:)` defaults to `audio/mpeg`. This breaks Sonos casting for non-MP3 formats. Prefer `Track.contentType` set by the server client from API metadata.
