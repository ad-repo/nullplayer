---
name: subsonic-integration
description: Subsonic/Navidrome API, authentication, music folder selection, streaming, and scrobbling. Use when working on Subsonic/Navidrome integration, library browsing, music folder filtering, or playback reporting.
---

# Subsonic / Navidrome Integration

NullPlayer supports Subsonic-compatible servers (including Navidrome) for music streaming, browsing, and scrobbling.

## Architecture

| File | Purpose |
|------|---------|
| `Subsonic/SubsonicModels.swift` | Domain models (Server, Artist, Album, Song, Playlist, MusicFolder) and API DTOs |
| `Subsonic/SubsonicServerClient.swift` | HTTP client for Subsonic REST API |
| `Subsonic/SubsonicManager.swift` | Singleton managing connections, caching, music folder selection, and track conversion |

## Authentication

Token-based auth is used (Subsonic API 1.13.0+):

```
GET /rest/{endpoint}?u={username}&t={md5(password+salt)}&s={salt}&v=1.16.1&c=NullPlayer&f=json
```

- `t` = MD5 hash of `password + salt`
- `s` = random salt string (16 chars)
- `f=json` added to all API requests (omitted for stream/binary endpoints)

## Music Folders

Navidrome/Subsonic can have multiple music folders (root library directories).

- **Fetch**: `GET /rest/getMusicFolders` — returns all configured music folders
- `SubsonicMusicFolder`: `{ id: String, name: String }`
- `SubsonicManager.musicFolders` — available folders fetched on connect
- `SubsonicManager.currentMusicFolder` — nil means all folders; posts `musicFolderDidChangeNotification` on change
- `selectMusicFolder(_ folder:)` — sets folder, clears cache, triggers preload
- `clearMusicFolderSelection()` — resets to nil (all folders), clears cache, triggers preload
- Persisted via `SubsonicCurrentMusicFolderID` UserDefaults key
- Auto-selection on connect: saved ID → nil (all folders, valid default)
- `musicFolderId` is passed to `getArtists` and `getAlbumList2` when a folder is selected

### Library Browser UI
The "Lib:" zone in the status bar shows the current folder name ("All" when nil). Click to open a folder picker menu.

## API Endpoints

### Library Browsing

- **Artists**: `GET /rest/getArtists?musicFolderId={id}` — indexed A-Z; `musicFolderId` optional
- **Artist detail**: `GET /rest/getArtist?id={artistId}` — returns artist + album list
- **Albums**: `GET /rest/getAlbumList2?type={type}&size={n}&offset={n}&musicFolderId={id}` — `musicFolderId` optional
- **Album detail**: `GET /rest/getAlbum?id={albumId}` — returns album + track list
- **Song**: `GET /rest/getSong?id={songId}`
- **Search**: `GET /rest/search3?query={q}&artistCount={n}&albumCount={n}&songCount={n}`
- **Playlists**: `GET /rest/getPlaylists`
- **Playlist detail**: `GET /rest/getPlaylist?id={playlistId}`
- **Starred**: `GET /rest/getStarred2`

### Album List Types (`getAlbumList2`)

| Type | Description |
|------|-------------|
| `alphabeticalByName` | A-Z by album title |
| `alphabeticalByArtist` | A-Z by artist |
| `newest` | Recently added |
| `frequent` | Most played |
| `recent` | Recently played |
| `starred` | Favorited albums |
| `random` | Random selection |
| `byYear` | By release year |
| `byGenre` | By genre |

### Streaming & Images

- **Stream**: `GET /rest/stream?id={songId}` — omit `f=json`; Navidrome returns binary
- **Cover art**: `GET /rest/getCoverArt?id={coverArtId}&size={px}` — omit `f=json`

### User Actions

- **Star**: `GET /rest/star?id={songId}` / `albumId={id}` / `artistId={id}`
- **Unstar**: `GET /rest/unstar?id={songId}` / `albumId={id}` / `artistId={id}`
- **Rate**: `GET /rest/setRating?id={songId}&rating={1-5}` (0 = remove)
- **Scrobble**: `GET /rest/scrobble?id={songId}&submission=true`

## State Persistence

- Current server ID: `SubsonicCurrentServerID` (UserDefaults)
- Current music folder ID: `SubsonicCurrentMusicFolderID` (UserDefaults) — nil = all folders
- Credentials: macOS login keychain via `KeychainHelper` (key: `subsonic_servers`) — uses permissive `SecAccessCreate` ACL; do NOT add `kSecUseDataProtectionKeychain` (breaks ad-hoc DMG builds with `-34018`)

## Notifications

| Notification | Posted when |
|-------------|-------------|
| `serversDidChangeNotification` | `servers` array changes |
| `connectionStateDidChangeNotification` | Connection state changes |
| `libraryContentDidPreloadNotification` | Background preload completes |
| `musicFolderDidChangeNotification` | `currentMusicFolder` changes |

## Track Identification

Subsonic tracks in the playlist are identified by:
- `track.subsonicId` — the Subsonic song ID
- `track.subsonicServerId` — which server the track belongs to

## Scrobbling

Scrobble threshold: 50% of track duration or 4 minutes, whichever comes first. Reports "now playing" immediately on start via `scrobble(id:submission:false)`.

## Casting (Sonos)

Subsonic streaming URLs contain auth query parameters which Sonos cannot handle. NullPlayer proxies audio through `LocalMediaServer` before casting. Stream URLs also omit `f=json` so Navidrome returns binary audio data.

## Key Gotchas

- **`f=json` on stream endpoints**: Always use `streamAuthParams()` (not `authParams()`) for stream/image URLs — these omit `f=json` which would otherwise cause Navidrome to return JSON instead of binary data
- **`musicFolderId` scoping**: When a music folder is selected, pass its ID to both `getArtists` and `getAlbumList2`. The folder filter is applied server-side; client cache is cleared on folder change to avoid showing stale cross-folder content
- **Folder IDs are integers server-side**: The Subsonic API returns `id` as an integer in `getMusicFolders`. `SubsonicMusicFolder` stores it as `String` (converted from `Int` in the DTO) for consistency with other IDs
