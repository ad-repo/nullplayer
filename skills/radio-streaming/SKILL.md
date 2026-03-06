---
name: radio-streaming
description: Internet radio, Shoutcast/Icecast protocols, auto-reconnect, ICY metadata, and casting. Also covers the Library Browser radio mode for Subsonic, Jellyfin, Emby, and local library (smart playlist generation, history filtering, history pages). Use when working on radio station playback, streaming metadata, auto-reconnect logic, radio casting, or library-source radio.
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
│   └── RadioManager.swift        # Singleton managing internet radio state
├── Data/Models/
│   └── RadioStation.swift        # Station data model
└── Windows/Radio/
    └── AddRadioStationSheet.swift # Add/edit station UI
```

### RadioManager

Singleton (`RadioManager.shared`) that manages:
- Station list (persisted to UserDefaults)
- Current playing station
- Connection state (disconnected/connecting/connected/reconnecting/failed)
- ICY stream metadata (current song title)
- Auto-reconnect logic

**Key Properties:**
```swift
var stations: [RadioStation]           // All saved stations
var currentStation: RadioStation?      // Currently playing (nil if not radio)
var currentStreamTitle: String?        // ICY metadata "Artist - Song"
var connectionState: ConnectionState   // Current connection state
var isActive: Bool                      // True if radio is playing
var statusText: String?                 // Display text for marquee
```

**Notifications:**
- `stationsDidChangeNotification` — Station list modified
- `streamMetadataDidChangeNotification` — ICY metadata received
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

### ICY Metadata

`StreamingAudioPlayer` → `AudioEngine` → `RadioManager` → `streamMetadataDidChangeNotification` → marquee.

Keys: `StreamTitle`, `StreamUrl`, `icy-name`, `icy-genre`.

### Casting Radio to Sonos

- Sonos receives the stream URL directly (no proxy)
- Time resets to 0:00 (live stream)
- For MP3 streams use `x-rincon-mp3radio://` URI scheme (Sonos internal buffering)

### Station Persistence

Stored as JSON in UserDefaults key `"RadioStations"`. Default stations: SomaFM Groove Salad, Drone Zone, DEF CON Radio.

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
└── Windows/ModernLibraryBrowser/
    └── ModernLibraryBrowserView.swift  # Radio tab UI + RadioType enums
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

### Playlist Generation Pipeline

Each `createXxxRadio` function follows this pattern:

```
1. Fetch candidate tracks from server (limit * 3 for headroom)
2. filterOutHistoryTracks(_:)  — remove recently played
3. filterForArtistVariety(_:limit:maxPerArtist:)  — cap per-artist slots
4. Return up to `limit` tracks
```

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

Accessed via context menu: right-click → Options → *Source* Radio History → View Radio History...

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

The Library Browser's **Radio** browse mode (`ModernBrowseMode.radio`) shows:

- Each source's available radio stations as a flat list
- Station names + category (Library, Genre, Decade, Favorites, Starred)
- Double-click to play, loading animation while generating

Implemented in `ModernLibraryBrowserView`: `loadXxxRadioStations()` fetches genres → `buildXxxRadioStationItems()` populates `displayItems` → `playXxxRadioStation()` generates + loads the playlist.

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
- [ ] ICY metadata displays in marquee
- [ ] Stop → no auto-reconnect; disconnect network → auto-reconnect attempts
- [ ] Cast to Sonos, time resets to 0:00

**Library radio:**
- [ ] Subsonic/Jellyfin/Emby radio tab loads genres and decade stations
- [ ] Double-click station → playlist fills with correct tracks
- [ ] After playing through tracks, history filters them out on next session
- [ ] Rapid tab switches → no stale results applied
- [ ] Double-click another station quickly → no duplicate playlist clears
- [ ] History menu visible after disconnecting server (not only while connected)
- [ ] History page sorts Played column correctly (newest last when ↑)
- [ ] Starred radio respects current music folder selection
