---
name: jellyfin-integration
description: Jellyfin API, authentication flow, rating scale, streaming, scrobbling, and video playback. Use when working on Jellyfin integration, library browsing, playback reporting, or video casting.
---

# Jellyfin Integration

NullPlayer supports Jellyfin media servers for music streaming, video playback (movies and TV shows), browsing, and scrobbling.

## Architecture

| File | Purpose |
|------|---------|
| `Jellyfin/JellyfinModels.swift` | Domain models (Server, Artist, Album, Song, Playlist, Movie, Show, Season, Episode) and API DTOs |
| `Jellyfin/JellyfinServerClient.swift` | HTTP client for Jellyfin REST API (music + video) |
| `Jellyfin/JellyfinManager.swift` | Singleton managing connections, caching, and track conversion (music + video) |
| `Jellyfin/JellyfinPlaybackReporter.swift` | Audio scrobbling and "now playing" reporting |
| `Jellyfin/JellyfinVideoPlaybackReporter.swift` | Video scrobbling with periodic timeline updates |
| `Jellyfin/JellyfinLinkSheet.swift` | Server add/edit/manage UI dialogs |

## Authentication

All requests include header: `Authorization: MediaBrowser Client="NullPlayer", Device="Mac", DeviceId="{uuid}", Version="1.0"`. After auth, also include `X-Emby-Token: {accessToken}`.

- **Auth**: `POST /Users/AuthenticateByName`
  - Body: `{"Username":"x","Pw":"y"}`
  - Returns JSON with `AccessToken` and `User.Id`
  - The access token is stored in keychain

- **Ping**: `GET /System/Ping` (returns 200 if server is reachable)

## Library Browsing

- **All libraries/views**: `GET /Users/{userId}/Views`
  - `fetchMusicLibraries()` returns all views (no `CollectionType` filtering).
  - `fetchVideoLibraries()` uses the same endpoint but filters out non-video library types (`music`, `musicvideos`, `books`, `photos`, `playlists`, `livetv`).
- **Artists**: `GET /Artists/AlbumArtists?parentId={libId}&userId={userId}&Recursive=true&SortBy=SortName`
- **Albums**: `GET /Users/{userId}/Items?parentId={libId}&IncludeItemTypes=MusicAlbum&Recursive=true`
- **Artist albums**: `GET /Users/{userId}/Items?AlbumArtistIds={artistId}&IncludeItemTypes=MusicAlbum`
- **Album tracks**: `GET /Users/{userId}/Items?parentId={albumId}&IncludeItemTypes=Audio`
- **Playlists**: `GET /Users/{userId}/Items?IncludeItemTypes=Playlist&Recursive=true`
- **Search**: `GET /Items?searchTerm={q}&IncludeItemTypes=Audio,MusicAlbum,MusicArtist,Movie,Series,Episode`

## Video Browsing

- **Video libraries**: same `GET /Users/{userId}/Views` endpoint, filtered to exclude non-video `CollectionType` values
- **Movies**: `GET /Users/{userId}/Items?parentId={libId}&IncludeItemTypes=Movie&MediaTypes=Video`
  - `MediaTypes=Video` excludes non-video files
- **Series**: `GET /Users/{userId}/Items?parentId={libId}&IncludeItemTypes=Series`
- **Seasons**: `GET /Shows/{seriesId}/Seasons?userId={userId}`
- **Episodes**: `GET /Shows/{seriesId}/Episodes?userId={userId}&seasonId={seasonId}&MediaTypes=Video`

## Streaming

- **Audio Stream**: `GET /Audio/{itemId}/stream?static=true&api_key={token}`
- **Video Stream**: `GET /Videos/{itemId}/stream?static=true&api_key={token}`
  - Note: Uses `/Videos/` path, not `/Audio/`

## Images

- **Image**: `GET /Items/{itemId}/Images/Primary?maxHeight={size}&maxWidth={size}&tag={imageTag}`
  - `imageTag` is from `ImageTags.Primary` in the item response

## User Actions

- **Favorite**: `POST /Users/{userId}/FavoriteItems/{itemId}` (add), `DELETE` (remove)
- **Rate**: `POST /Users/{userId}/Items/{itemId}/Rating?likes=true`
- **Scrobble**: `POST /Users/{userId}/PlayedItems/{itemId}`

## Playback Reporting

- **Start**: `POST /Sessions/Playing`
  - Body: `{"ItemId":"{id}","CanSeek":true,"PlayMethod":"DirectStream"}`

- **Progress**: `POST /Sessions/Playing/Progress`
  - Body: `{"ItemId":"{id}","PositionTicks":{ticks},"IsPaused":false}`

- **Stopped**: `POST /Sessions/Playing/Stopped`
  - Body: `{"ItemId":"{id}","PositionTicks":{ticks}}`

## Rating Scale

Jellyfin `UserData.Rating` is 0-100%. The app uses 0-10 internal scale.

Mapping:
- `jellyfin_rating = internal_rating * 10`
- `internal_rating = jellyfin_rating / 10`
- Each star = 20%

## Ticks

Jellyfin uses ticks for duration/position: 1 tick = 10,000 nanoseconds = 0.00001 seconds.

Convert: `ticks = seconds * 10_000_000`

## Track Identification

Jellyfin tracks in the playlist are identified by:
- `track.jellyfinId` — the Jellyfin item UUID
- `track.jellyfinServerId` — which Jellyfin server the track belongs to

## Scrobbling

`JellyfinPlaybackReporter` follows the same rules as `SubsonicPlaybackReporter`:
- Reports "now playing" immediately on track start (via `POST /Sessions/Playing`)
- Reports progress periodically (via `POST /Sessions/Playing/Progress`)
- Scrobbles after 50% of track or 4 minutes, whichever comes first
- Reports stopped on track end/stop (via `POST /Sessions/Playing/Stopped`)

## Video Playback Reporter

`JellyfinVideoPlaybackReporter` mirrors `PlexVideoPlaybackReporter` with Jellyfin API:
- Video scrobble threshold: 90% (vs 50% for audio)
- Minimum play time: 60s before scrobbling
- Periodic timeline updates every 10s via `POST /Sessions/Playing/Progress` with `PositionTicks`
- Tracks pause/resume state with `IsPaused` flag
- Uses ticks (1 tick = 100ns, `seconds × 10_000_000`) for Jellyfin API

## Library Selection

Jellyfin can have multiple libraries of any type. `JellyfinManager` maintains separate current selections for music and video content.

### Music Library Selection
- `musicLibraries: [JellyfinMusicLibrary]` — all server views (unfiltered)
- `currentMusicLibrary: JellyfinMusicLibrary?` — nil means "all libraries"
- `selectMusicLibrary(_ library:)` — set specific library, clears cache, triggers preload
- `clearMusicLibrarySelection()` — resets to nil (all libraries), clears cache, triggers preload
- Posts `musicLibraryDidChangeNotification` from `currentMusicLibrary` `didSet`
- Persisted via `JellyfinCurrentMusicLibraryID` UserDefaults key
- Auto-selection on connect: saved ID → auto-select if only one library → nil (all)

### Video Library Selection
- `videoLibraries: [JellyfinMusicLibrary]` — all server views (unfiltered)
- `currentMovieLibrary: JellyfinMusicLibrary?` — nil means "all libraries"
- `currentShowLibrary: JellyfinMusicLibrary?` — nil means "all libraries"
- `selectMovieLibrary(_ library: JellyfinMusicLibrary?)` — accepts nil to clear
- `selectShowLibrary(_ library: JellyfinMusicLibrary?)` — accepts nil to clear
- Posts `videoLibraryDidChangeNotification` from both `didSet` observers
- Persisted via `JellyfinCurrentMovieLibraryID` / `JellyfinCurrentShowLibraryID`
- Auto-selection on connect: saved ID → hint by `collectionType` ("movies"/"tvshows") → single library fallback

### Library Browser UI
The status bar "Lib:" zone is **browse-mode-aware**:
- Music tabs (Artists/Albums/Tracks/Plists) → shows `currentMusicLibrary`, click opens music library menu
- Movies tab → shows `currentMovieLibrary`, click opens video library menu
- Shows tab → shows `currentShowLibrary`, click opens video library menu
- "All" is shown and selectable when no specific library is chosen
- Notifications: browser observes `musicLibraryDidChangeNotification` and `videoLibraryDidChangeNotification` and reloads relevant cached content

## Artist Expansion Performance

When expanding a Jellyfin artist in the library browser (both modern `ModernLibraryBrowserView` and classic `PlexBrowserView`), albums are resolved from the preloaded cache (`cachedJellyfinAlbums`) by filtering on `artistId`, making expansion instant. Network fallback only occurs if the cache has no matching albums.

**Important**: Expand tasks must use `Task.detached` (not `Task { }`) to avoid inheriting cancellation state from the calling context. Inherited cancellation can surface as Jellyfin request failures like `NSURLErrorDomain Code=-999 "cancelled"` during artist expansion.

## Large Library Performance Notes

Jellyfin can load noticeably slower than Emby/Plex/Subsonic on very large libraries due to server-side cost of deep recursive item queries (`Recursive=true`) over large datasets.

Current app-side mitigations:
- `JellyfinServerClient` uses smaller pagination (`1000`) for artists/albums/movies/shows and guards against repeated pages to avoid long/hanging scans.
- `JellyfinManager.preloadLibraryContent()` is music-focused (artists/albums/playlists) so initial browse readiness is not blocked by movie/show scans.
- Artist views in both modern/classic render artists first, then warm `cachedJellyfinAlbums` asynchronously in background.
- `performRequest` emits slow-request logs for endpoint-level diagnostics on real servers.

## Casting

Jellyfin tracks support casting to Sonos, Chromecast, and DLNA devices:
- Sonos requires proxy (like Subsonic) — `needsJellyfinProxy` flag
- Artwork is loaded via `JellyfinManager.shared.imageURL()`
- Stream URLs use `api_key` auth parameter, not header auth

### Content Type Detection for Sonos Casting

Jellyfin (and Subsonic) streaming URLs use paths like `/Audio/{id}/stream` with no file extension. This means `CastManager.detectAudioContentType(for:)` defaults to `audio/mpeg`, which is wrong for FLAC/WAV/etc.

**Fix**: `CastManager.prepareProxyURL(for:device:)` handles this with a multi-layer strategy:
1. Use `track.contentType` if available (set by `JellyfinManager.convertToTrack()` from the `Container` field)
2. If nil, send a HEAD request to the upstream URL and read the `Content-Type` response header
3. Pass the detected content type to both the proxy registration and the DIDL-Lite metadata
4. Fall back to `detectAudioContentType(for:)` only as a last resort

**State restoration**: `SavedTrack.contentType` persists the MIME type across app restarts.

### Video Casting

Jellyfin movies and episodes can be cast to video-capable devices (Chromecast, DLNA TVs):
- `CastManager.castJellyfinMovie(_:to:startPosition:)` — cast a movie
- `CastManager.castJellyfinEpisode(_:to:startPosition:)` — cast an episode
- Stream URL uses `/Videos/{id}/stream?static=true&api_key={token}`

## Credential Storage

Jellyfin credentials are stored using `KeychainHelper`:
- Key: `jellyfin_servers`
- Stores: `[JellyfinServerCredentials]` (includes access token and userId)
- Uses the macOS login keychain with a permissive `SecAccessCreate` ACL. Do NOT add `kSecUseDataProtectionKeychain` or `kSecAttrAccessible` — they require entitlements that ad-hoc signed DMG builds don't have and cause `-34018 errSecMissingEntitlement`.

## State Persistence

- Current server ID: `JellyfinCurrentServerID` (UserDefaults)
- Current music library ID: `JellyfinCurrentMusicLibraryID` (UserDefaults) — nil = all libraries
- Current movie library ID: `JellyfinCurrentMovieLibraryID` (UserDefaults) — nil = all libraries
- Current show library ID: `JellyfinCurrentShowLibraryID` (UserDefaults) — nil = all libraries
- Playlist tracks with `jellyfinId`/`jellyfinServerId` are saved/restored by `AppStateManager`
