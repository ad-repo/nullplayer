---
name: radio-streaming
description: Internet radio (Shoutcast/Icecast), metadata fallback, auto-reconnect, ratings/folder organization, and casting. Also covers Library Browser radio mode for Subsonic, Jellyfin, Emby, Plex, and local library (smart playlist generation, history filtering, history pages). Use when working on radio station playback, streaming metadata, auto-reconnect logic, radio organization UI, radio casting, or library-source radio.
---

# Radio in NullPlayer

NullPlayer has two distinct radio systems:

1. **Internet Radio** — Shoutcast/Icecast stream playback (via `RadioManager`)
2. **Library Radio** — Smart playlist generation from Subsonic, Jellyfin, Emby, Plex, and local files, with play-history filtering

---

## 1. Internet Radio

### Architecture

```
Sources/NullPlayer/
├── Radio/
│   ├── RadioManager.swift             # Singleton managing internet radio state
│   ├── RadioStationRatingsStore.swift # SQLite-backed 0-5 ratings (URL-keyed)
│   ├── RadioFolderModels.swift        # Folder descriptor/kind model
│   └── RadioStationFoldersStore.swift # SQLite-backed folders + memberships + play history
├── Resources/Radio/
│   └── default_stations.json          # Bundled default station catalog
├── Data/Models/
│   └── RadioStation.swift             # Station data model
├── Windows/Radio/
│   └── AddRadioStationSheet.swift     # Add/edit station UI
├── Windows/ModernLibraryBrowser/
│   └── ModernLibraryBrowserView.swift # Internet radio folder tree + rating column
└── Windows/PlexBrowser/
    └── PlexBrowserView.swift          # Internet radio folder tree + rating column
```

### RadioManager

Singleton (`RadioManager.shared`) that manages:
- Station list (seeded from bundled JSON, persisted to UserDefaults)
- Current playing station
- Connection state (disconnected/connecting/connected/reconnecting/failed)
- Stream metadata (ICY + SomaFM fallback)
- Internet-radio-only station ratings and folder organization
- Auto-reconnect logic

**Key Properties:**
```swift
var stations: [RadioStation]           // All saved stations
var currentStation: RadioStation?      // Currently playing (nil if not radio)
var currentStreamTitle: String?        // ICY metadata "Artist - Song"
var currentSomaLastPlaying: String?    // SomaFM fallback metadata
var connectionState: ConnectionState   // Current connection state
var isActive: Bool                      // True if radio is playing
var statusText: String?                 // Marquee text (effective stream title)
```

**Notifications:**
- `stationsDidChangeNotification` — Station list modified
- `streamMetadataDidChangeNotification` — effective stream metadata changed (ICY first, Soma fallback second)
- `connectionStateDidChangeNotification` — Connection state changed

### RadioStation Model

```swift
struct RadioStation: Identifiable, Codable {
    let id: UUID
    var name: String
    var url: URL
    var genre: String?
    var iconURL: URL?

    func toTrack() -> Track  // Convert to playable Track
}
```

### Connection States

```swift
enum ConnectionState {
    case disconnected           // Not playing radio
    case connecting             // Initial connection attempt
    case connected              // Successfully streaming
    case reconnecting(attempt)  // Auto-reconnect in progress
    case failed(message)        // Connection failed
}
```

### Audio Engine Integration

RadioManager integrates with AudioEngine through delegate callbacks:

| Callback | Purpose |
|----------|---------|
| `streamDidConnect()` | Called when stream starts playing |
| `streamDidDisconnect(error:)` | Called on stream end/error, triggers reconnect |
| `streamDidReceiveMetadata(_:)` | Receives ICY metadata for display |

**Critical: State Preservation**

When `loadTracks()` is called with radio content:
1. Detect radio content by comparing `track.url` with `currentStation.url`
2. Use `stopLocalOnly()` instead of `stop()` to preserve RadioManager state
3. Calling `stop()` would trigger `RadioManager.stop()`, clearing state

```swift
let isRadioContent: Bool
if RadioManager.shared.isActive {
    isRadioContent = validTracks.first.map { track in
        RadioManager.shared.currentStation?.url == track.url
    } ?? false
}
// Use stopLocalOnly() for radio, stop() for other content
if isRadioContent { stopLocalOnly() } else { stop() }
```

### Playlist URL Resolution

Radio stations often use `.pls`/`.m3u`/`.m3u8` playlist URLs. Always check `CastManager.shared.isCasting` **fresh inside the async callback** — resolution can take up to 10 seconds.

### Auto-Reconnect

1. `streamDidDisconnect(error:)` fires
2. If `manualStopRequested == false` and `autoReconnectEnabled == true`: exponential backoff (2s, 4s, 8s, 16s, 32s), max 5 attempts
3. After max attempts → `.failed`

Manual stop (user pressing Stop, loading non-radio content, switching stations) sets `manualStopRequested = true` and does **not** trigger reconnect.

### Stream Metadata (ICY + Soma Fallback)

Primary path:
`StreamingAudioPlayer` → `AudioEngine` → `RadioManager.currentStreamTitle` → `streamMetadataDidChangeNotification`.

Fallback path:
When ICY metadata is missing for SomaFM streams, `RadioManager` polls `https://somafm.com/channels.json` and maps channel `lastPlaying` into `currentSomaLastPlaying`.

Published value is `effectiveStreamTitle`:
1. `currentStreamTitle` (ICY)
2. `currentSomaLastPlaying` (Soma fallback)

UI should consume only `streamMetadataDidChangeNotification` and not assume ICY is always present.

### Casting Radio to Sonos

- Sonos receives the stream URL directly (no proxy)
- Time resets to 0:00 (live stream)
- For MP3 streams use `x-rincon-mp3radio://` URI scheme (Sonos internal buffering)

### Station Persistence

Internet radio persistence is split by concern:

- **Bundled default catalog**: `Sources/NullPlayer/Resources/Radio/default_stations.json` (full curated default station list shipped with the app)
- **Saved station list**: JSON in UserDefaults key `"RadioStations"` (user runtime list; initialized from bundled defaults on first launch or reset)
- **Ratings**: SQLite `~/Library/Application Support/NullPlayer/radio_station_ratings.db`, table `radio_station_ratings` (`station_url` PK, `rating` 0...5, `updated_at`)
- **Folders/memberships/play history**: SQLite `~/Library/Application Support/NullPlayer/radio_station_folders.db`
  - `radio_folders`
  - `radio_station_folder_memberships` (folder ↔ station URL)
  - `radio_station_play_history` (used for "Recently Played" smart folder)

Ratings/folders are URL-keyed. If a station URL is edited, `RadioManager.updateStation` migrates rating and folder references to the new URL. Removing a station purges rating + folder membership + play history rows for that URL.

### Internet Radio Organization (Folders + Ratings)

Internet Radio now uses folder-tree organization in both `ModernLibraryBrowserView` and `PlexBrowserView`.

Smart folders:
- All Stations
- Favorites (rating >= 4)
- Top Rated
- Unrated
- Recently Played
- By Genre (group + dynamic children)
- By Region (group + dynamic children)

Manual folders:
- User-created folders under "My Folders"
- Station membership is managed from station context menu (`Folders` submenu)

Key behavior:
- Rating is 0...5 stars (0 = unrated); clicking the same star again clears rating.
- Rating column is shown for **Internet Radio station rows only**.
- Genre column is centered for all radio sources.
- Internet Radio context menu includes folder actions (create, rename, delete, set active, add/remove station membership).

---

## 2. Library Radio

Library Radio generates smart playlists from server/local sources with play-history deduplication.

### Architecture

```
Sources/NullPlayer/
├── Subsonic/
│   ├── SubsonicManager.swift        # createXxxRadio functions
│   └── SubsonicRadioHistory.swift   # SQLite play history
├── Jellyfin/
│   ├── JellyfinManager.swift        # createXxxRadio functions
│   └── JellyfinRadioHistory.swift   # SQLite play history
├── Emby/
│   ├── EmbyManager.swift            # createXxxRadio functions
│   └── EmbyRadioHistory.swift       # SQLite play history
├── Data/Models/
│   ├── MediaLibrary.swift           # createLocalXxxRadio functions
│   └── LocalRadioHistory.swift      # SQLite play history for local files
├── Windows/ModernLibraryBrowser/
│   └── ModernLibraryBrowserView.swift  # Radio tab UI + RadioType enums
└── Windows/PlexBrowser/
    └── PlexBrowserView.swift           # Classic/Plex browser radio tab UI + RadioType enums
```

### Radio Types (per source)

**Subsonic** (`SubsonicRadioType`):
| Case | Function | Description |
|------|----------|-------------|
| `.libraryRadio` | `createLibraryRadio()` | Random songs from whole library |
| `.librarySimilar` | `createLibraryRadioSimilar()` | Subsonic `getSimilarSongs2` from current track |
| `.starredRadio` | `createRatingRadio()` | Starred songs, shuffled |
| `.starredSimilar` | `createRatingRadioSimilar()` | Similar songs seeded from starred |
| `.genreRadio(g)` | `createGenreRadio(genre:)` | Songs in genre |
| `.genreSimilar(g)` | `createGenreRadioSimilar(genre:)` | Similar to a random track in genre |
| `.decadeRadio(s,e,name)` | `createDecadeRadio(start:end:)` | Songs from year range |
| `.decadeSimilar(s,e,name)` | `createDecadeRadioSimilar(start:end:)` | Similar to a random decade track |

**Jellyfin** (`JellyfinRadioType`):
| Case | Function |
|------|----------|
| `.libraryRadio` | `createLibraryRadio()` — random songs |
| `.libraryInstantMix` | `createLibraryRadioInstantMix()` — InstantMix seeded from current track |
| `.genreRadio(g)` | `createGenreRadio(genre:)` |
| `.genreInstantMix(g)` | `createGenreRadioInstantMix(genre:)` |
| `.decadeRadio(s,e,name)` | `createDecadeRadio(start:end:)` |
| `.decadeInstantMix(s,e,name)` | `createDecadeRadioInstantMix(start:end:)` |
| `.favoritesRadio` | `createFavoritesRadio()` — favorite songs |
| `.favoritesInstantMix` | `createFavoritesRadioInstantMix()` |

**Emby** (`EmbyRadioType`) — same structure as Jellyfin (Library, Genre, Decade, Favorites each with plain + InstantMix variant).

**Local** (`LocalRadioType`):
| Case | Function |
|------|----------|
| `.libraryRadio` | `createLocalLibraryRadio()` |
| `.genreRadio(g)` | `createLocalGenreRadio(genre:)` |
| `.decadeRadio(s,e,name)` | `createLocalDecadeRadio(start:end:)` |

`MediaLibrary` also has `createLocalArtistRadio(artist:limit:)` for artist-seeded radio (prefers `albumArtist` over `artist`).

### RadioConfig

`RadioConfig` (file: `ModernLibraryBrowserView.swift`) provides shared constants:

```swift
struct RadioConfig {
    static let defaultLimit = 100          // Tracks per radio session
    static let decades: [DecadeRange]      // Pre-defined decade ranges (1960s–2020s)
    static let ratingStations: [...]       // Plex rating-based presets
}
```

### Playback Options Menu

Playback options now expose a dedicated `Radio` submenu.

Items under `Playback Options -> Radio`:

- `Max Tracks Per Artist`
- `Playlist Length`
- `History`

`Playlist Length` is backed by `RadioPlaybackOptions.playlistLength` and supports:

- `100`
- `250`
- `500`
- `1000`
- `10000`

`Max Tracks Per Artist` and radio history controls were moved under this submenu from the top level playback options menu.

### Playlist Generation Pipeline

Each `createXxxRadio` function follows this pattern:

```
1. Fetch candidate tracks from server
2. filterOutHistoryTracks(_:)  — remove recently played
3. filterForArtistVariety(_:limit:maxPerArtist:)  — cap per-artist slots
4. Return up to `limit` tracks
```

Candidate fetch sizing:

- Standard behavior: over-fetch by `3x` for headroom before artist dedupe
- If `Max Tracks Per Artist` is `Unlimited` (`0`), use the requested playlist length directly and do not over-fetch

**Instant Mix / Similar** functions additionally:
1. Try to reuse the currently playing track as seed (if it belongs to the active server)
2. Fall back to fetching a random seed from the server
3. Call server's InstantMix/getSimilarSongs2 API with the seed

### Play History System

Each source has its own SQLite database in `~/Library/Application Support/NullPlayer/`:

| Source | Database | Class |
|--------|----------|-------|
| Subsonic | `subsonic_radio_history.db` | `SubsonicRadioHistory` |
| Jellyfin | `jellyfin_radio_history.db` | `JellyfinRadioHistory` |
| Emby | `emby_radio_history.db` | `EmbyRadioHistory` |
| Local | `local_radio_history.db` | `LocalRadioHistory` |

**Schema (Subsonic/Jellyfin/Emby):** `id`, `track_id`, `title`, `artist`, `album`, `server_id`, `played_at` (epoch Double), `normalized_key`

**Schema (Local):** `id`, `track_url`, `title`, `artist`, `album`, `played_at`, `normalized_key`

**Key methods:**
```swift
func recordTrackPlayed(_ track: Track)           // Insert/replace on track finish
func filterOutHistoryTracks(_ tracks: [Track]) -> [Track]  // Remove recently played
func fetchHistory() -> [XxxRadioHistoryEntry]    // For history page
func clearHistory()                              // Wipe database
var isEnabled: Bool                              // retentionInterval != .off
var historyPageURL: URL?                         // http://127.0.0.1:{httpPort}/xxx-radio-history
```

**Retention intervals:** Off / 2 Weeks / 1 Month (default) / 3 Months / 6 Months. Stored in UserDefaults (e.g. `"subsonicRadioHistoryInterval"`).

**Dedup logic:** Tracks are excluded if their `track_id` OR `normalized_key` (`"artist|title"`, lowercased) appears in history within the retention window **for the active server** (`server_id == currentServer.id`).

**Thread safety:** `recordTrackPlayed` is always called via `Task.detached(priority: .utility)` in `AudioEngine` (4 call sites: cast completion, local completion, crossfade, streaming crossfade) to keep SQLite I/O off the audio callback thread.

### History Web Pages

`LocalMediaServer` (port: `LocalMediaServer.httpPort` = 8765) serves per-source history pages:

| URL | Source |
|-----|--------|
| `/subsonic-radio-history` | Subsonic |
| `/jellyfin-radio-history` | Jellyfin |
| `/emby-radio-history` | Emby |
| `/local-radio-history` | Local files |

Pages are generated as self-contained HTML with a sortable table. The Played column uses `data-sort="{epoch}"` for correct numeric sort (not locale string sort).

Accessed via context menu: right-click → Options → `Radio History` → source-specific entry.

The context menu entry is shown whenever a server has **ever been configured** (not only while actively connected).

If `LocalMediaServer.start()` fails, an `NSAlert` is shown describing the error (not silently swallowed).

### Artist Variety Filtering

After history filtering, `filterForArtistVariety` caps tracks per artist:

```swift
func filterForArtistVariety(_ tracks: [Track], limit: Int, maxPerArtist: Int = 2) -> [Track]
```

Standard radio: `maxPerArtist = 2`. Instant Mix / Similar: `maxPerArtist = 1` (more variety).

### Race Condition Guards (ModernLibraryBrowserView)

- **radioLoadTask**: cancelled when source/mode changes before a new genre fetch begins. Result is discarded if source or browseMode changed while awaiting.
- **radioPlayTask**: cancelled if user double-clicks another station before the previous radio generation completes.

---

## UI Integration

### Library Browser Radio Tab

The browser Radio tab has two behaviors:

- **Internet Radio source (`currentSource == .radio`)**:
  - Folder tree + active-folder station list
  - Columns: `Title | Genre | Rating` for station rows
  - Genre centered; rating centered
  - Folder context actions + station folder-membership submenu
- **Library radio sources (Plex/Subsonic/Jellyfin/Emby/Local)**:
  - Source-specific generated radio stations (Library/Genre/Decade/etc.)
  - Genre/category column centered in radio lists
  - Double-click to generate and play queue

Implemented in both browser views:
- `Windows/ModernLibraryBrowser/ModernLibraryBrowserView.swift`
- `Windows/PlexBrowser/PlexBrowserView.swift`

### Main Window Marquee

Priority order:
1. Error message
2. Video title (video playing)
3. Radio status/stream title (internet radio active)
4. Track title

---

## Testing Checklist

**Internet radio:**
- [ ] Add station with direct stream URL and with .pls/.m3u URL
- [ ] Metadata displays in marquee (ICY when present, Soma fallback when ICY absent)
- [ ] Stop → no auto-reconnect; disconnect network → auto-reconnect attempts
- [ ] Cast to Sonos, time resets to 0:00
- [ ] Folder tree renders in both Modern and Plex browsers
- [ ] Create/rename/delete manual folder; station membership toggles correctly
- [ ] Rating stars persist across relaunch; clicking selected star clears rating
- [ ] Editing station URL migrates rating/folder membership

**Library radio:**
- [ ] Subsonic/Jellyfin/Emby radio tab loads genres and decade stations
- [ ] Double-click station → playlist fills with correct tracks
- [ ] After playing through tracks, history filters them out on next session
- [ ] Rapid tab switches → no stale results applied
- [ ] Double-click another station quickly → no duplicate playlist clears
- [ ] Playback Options has a single `Radio History` submenu with source-specific entries
- [ ] History menu visible after disconnecting server (not only while connected)
- [ ] History page sorts Played column correctly (newest last when ↑)
- [ ] Starred radio respects current music folder selection

## Implementation Gotchas

### State Management — Use `stopLocalOnly()` not `stop()`

`loadTracks()` must use `stopLocalOnly()` instead of `stop()` when loading radio content. Calling `stop()` triggers `RadioManager.stop()` which clears state and breaks auto-reconnect/metadata. The `isRadioContent` check detects radio by matching track URL with `currentStation.url`.

### Metadata Fallback — `effectiveStreamTitle`

`RadioManager` publishes `effectiveStreamTitle` (ICY `currentStreamTitle` first, SomaFM `currentSomaLastPlaying` fallback). UI should listen to `streamMetadataDidChangeNotification`, not raw ICY-only fields.

### Ratings and Folders Are URL-Keyed

Ratings and folder membership are keyed by station URL (not station UUID). `RadioManager.updateStation` must migrate URL references via `moveRating(fromURL:toURL:)` and `foldersStore.moveStationURLReferences(from:to:)`; `removeStation` must purge both stores.

### Playlist URL Resolution — Check `isCasting` Inside Async Callback

When resolving `.pls`/`.m3u` URLs, check `CastManager.shared.isCasting` fresh inside the async callback, not captured before the network request (up to 10s timeout). User may start casting during resolution.
