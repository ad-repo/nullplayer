---
name: cli
description: Headless CLI mode for NullPlayer. Use when working on CLI features, arguments, playback control, query commands, source resolution, or terminal display. Covers architecture, all flags, keyboard controls, and source APIs.
---

# NullPlayer CLI Mode

NullPlayer supports a `--cli` flag that launches a headless mode for browsing, searching, and playing music from all configured sources via the terminal. The process stays alive during playback with interactive keyboard controls. Query commands (`--list-*`, `--search`) print results and exit immediately.

## Launching

```bash
NullPlayer --cli [OPTIONS]
```

`--cli` and `--ui-testing` are mutually exclusive. In CLI mode the app runs with `.accessory` activation policy — no Dock icon, no menu bar.

---

## Architecture

### New Files (`Sources/NullPlayer/CLI/`)

| File | Purpose |
|------|---------|
| `CLIMode.swift` | `NSApplicationDelegate` for CLI mode; `CLIOptions` struct with arg parsing; signal handling |
| `CLIPlayer.swift` | Headless playback controller; owns `AudioEngine`; implements `AudioEngineDelegate` |
| `CLIKeyboard.swift` | Raw terminal input via `tcsetattr`; ANSI escape sequence handling on background queue |
| `CLIDisplay.swift` | Terminal output: progress bar, status lines, ASCII art, `--json` formatting |
| `CLIArtwork.swift` | Artwork loading from local/Plex/Subsonic/Jellyfin/Emby; ASCII art rendering |
| `CLISourceResolver.swift` | Resolves all flags to `[Track]` or `.radioStation`; `CLISourceError` enum |
| `CLIQueryHandler.swift` | Handles `--list-*` and `--search` queries; prints results then calls `exit()` |

### Modified Files

| File | Change |
|------|--------|
| `App/main.swift` | Branch on `--cli` flag; `--cli`+`--ui-testing` mutual exclusion |
| `Audio/AudioEngine.swift` | `static var isHeadless = false`; guards on all 10 `WindowManager.shared` video references |
| `Radio/RadioManager.swift` | `static weak var cliAudioEngine`; `resolvedAudioEngine`; `currentMetadataTitle`; 4 `play(station:)` replacements |
| `Casting/CastManager.swift` | `static weak var cliAudioEngine`; `resolvedAudioEngine`; replacements in `castCurrentTrack`, `castNewTrack`, `pauseLocalPlayback`, Chromecast status handler |
| `Subsonic/SubsonicManager.swift` | Added `fetchPlaylistSongs(id:)` |
| `Jellyfin/JellyfinManager.swift` | Added `fetchPlaylistSongs(id:)` |
| `Emby/EmbyManager.swift` | Added `fetchPlaylistSongs(id:)` |

---

## Arguments

### Boolean Flags

| Flag | Description |
|------|-------------|
| `--cli` | Enable headless CLI mode |
| `--json` | JSON output for all queries/status |
| `--help` | Show help text and exit 0 |
| `--version` | Show version string and exit 0 |
| `--shuffle` | Enable shuffle mode |
| `--repeat-all` | Repeat entire playlist (CLIPlayer-managed; restarts on `.stopped`) |
| `--repeat-one` | Repeat current track (`AudioEngine.repeatEnabled = true`) |
| `--no-art` | Disable ASCII album art (art is shown by default; 256-color half-block) |

`--repeat-all` and `--repeat-one` are mutually exclusive; validated at startup.

### Query Commands (print and exit)

| Flag | Source required? |
|------|-----------------|
| `--list-sources` | No |
| `--list-libraries` | Yes (plex, subsonic, jellyfin, emby) |
| `--list-artists` | Yes |
| `--list-albums` | Yes (optional `--artist` filter) |
| `--list-tracks` | Yes (optional `--artist`/`--album` filter) |
| `--list-genres` | No (local library only) |
| `--list-playlists` | Yes |
| `--list-stations` | No (optional `--folder` filter) |
| `--list-devices` | No (5s discovery wait) |
| `--list-outputs` | No |
| `--list-eq` | No |

`--search` without playback flags (`--artist`, `--album`, `--playlist`, `--radio`, `--station`) is also a query command.

### String/Int Parameters

| Flag | Type | Notes |
|------|------|-------|
| `--source <name>` | string | `local`, `plex`, `subsonic`, `jellyfin`, `emby`, `radio` |
| `--library <name>` | string | Select sub-library/folder within source (plex, subsonic, jellyfin, emby); case-insensitive |
| `--artist <name>` | string | Filter/select by artist (case-insensitive) |
| `--album <name>` | string | Filter/select by album (case-insensitive) |
| `--track <name>` | string | Post-filter by track title (substring) |
| `--genre <name>` | string | Filter by genre |
| `--decade <year>` | int | Decade start year (e.g. 1970); passed as `start:end+9` |
| `--playlist <name>` | string | Select playlist by exact name (case-insensitive) |
| `--search <query>` | string | Search within source |
| `--radio <mode>` | string | See radio modes below |
| `--station <name>` | string | Internet radio station name (`--source radio` required) |
| `--folder <name>` | string | Radio folder (see `RadioFolderKind` mapping) |
| `--channel <name>` | string | Radio channel (with `--folder channel`) |
| `--region <name>` | string | Radio region (with `--folder region`) |
| `--volume <0-100>` | int | Initial volume (divided by 100 for `AudioEngine.volume`) |
| `--cast <device>` | string | Cast to named device (case-insensitive match) |
| `--cast-type <type>` | string | `sonos`, `chromecast`, `dlna` |
| `--sonos-rooms <rooms>` | string | Comma-separated Sonos room names for multi-room |
| `--eq <preset>` | string | EQ preset name (case-insensitive; from `EQPreset.allPresets`) |
| `--output <device>` | string | Audio output device name (case-insensitive) |

---

## `--library` Flag

Selects a source-specific sub-library before any query or playback. All subsequent operations (artists, albums, radio, etc.) are scoped to that library.

| Source | Concept | Manager API |
|--------|---------|-------------|
| `plex` | Plex library section | `selectLibrary(_:)` on `PlexManager`; from `availableLibraries` |
| `subsonic` | Music folder | `selectMusicFolder(_:)` on `SubsonicManager`; from `musicFolders` |
| `jellyfin` | Music library | `selectMusicLibrary(_:)` on `JellyfinManager`; from `musicLibraries` |
| `emby` | Music library | `selectMusicLibrary(_:)` on `EmbyManager`; from `musicLibraries` |

Use `--list-libraries --source <name>` to see available libraries. The current selection (marked `*`) is from the GUI's saved preference.

## Radio Modes (`--radio <mode>`)

| Mode | Required flags | Source availability |
|------|---------------|-------------------|
| `library` | — | Plex, Subsonic, Jellyfin, Emby |
| `genre` | `--genre <name>` | All |
| `decade` | `--decade <year>` | All |
| `hits` | — | Plex only |
| `deep-cuts` | — | Plex only |
| `rating` | — | Plex (`minRating: 4.0`), Subsonic (no params) |
| `favorites` | — | Jellyfin, Emby only |
| `artist` | `--artist <name>` | All |
| `album` | `--artist <name> --album <name>` | All |
| `track` | `--track <name>` or `--search <name>` | All |

**Plex param differences:** `createDecadeRadio(startYear:endYear:)` — not `start:end:`.
**Subsonic/Jellyfin/Emby:** `createDecadeRadio(start:end:)`.
**Subsonic artist/album radio:** takes ID string, not model object.
**Plex artist/album radio:** takes model object (must resolve via `fetchArtists`/`fetchAlbums` first).

---

## RadioFolderKind Mapping

| `--folder` value | Enum case |
|-----------------|-----------|
| `all` | `.allStations` |
| `favorites` | `.favorites` |
| `top-rated` | `.topRated` |
| `unrated` | `.unrated` |
| `recent` | `.recentlyPlayed` |
| `channels` | `.byChannel` |
| `genres` | `.byGenre` |
| `regions` | `.byRegion` |
| `genre` | `.genre(name)` — requires `--genre` |
| `channel` | `.channel(name)` — requires `--channel` |
| `region` | `.region(name)` — requires `--region` |

---

## Keyboard Controls (during playback)

| Key | Action |
|-----|--------|
| `Space` | Pause/Resume |
| `q` / `Q` | Quit (restores terminal) |
| `>` | Next track |
| `<` | Previous track |
| `→` (right arrow) | Seek forward 10s |
| `←` (left arrow) | Seek backward 10s |
| `↑` (up arrow) | Volume up 5% |
| `↓` (down arrow) | Volume down 5% |
| `s` / `S` | Toggle shuffle |
| `r` / `R` | Cycle repeat (off → all → one → off) |
| `m` / `M` | Toggle mute |
| `i` / `I` | Show current track info |

`CLIKeyboard` reads stdin on a background `DispatchQueue` and dispatches all player calls to `DispatchQueue.main.async`.

---

## Thread Safety

- `CLIKeyboard` reads stdin on background queue — all `AudioEngine` calls dispatched to `DispatchQueue.main.async`
- `AudioEngineDelegate` callbacks arrive on main thread — safe to update `CLIDisplay`
- Signal handlers use `DispatchSourceSignal` on `.main` — safe for terminal restore
- `CLIMode.applicationDidFinishLaunching` spawns `Task { @MainActor in ... }` for all async resolution

---

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success / clean quit |
| 1 | Error (auth failure, no matches, invalid args) |
| 130 | Interrupted (SIGINT / Ctrl+C) |

---

## `AudioEngine.isHeadless` Pattern

Set to `true` by `CLIMode.applicationDidFinishLaunching` before anything else runs. Guards all video-related `WindowManager.shared` accesses inside `AudioEngine`:

```swift
// Property guards
if !AudioEngine.isHeadless { WindowManager.shared.setVideoVolume(volume) }

// Method guards
guard !AudioEngine.isHeadless else { return }
WindowManager.shared.toggleVideoCastPlayPause()
```

## `resolvedAudioEngine` Pattern

Both `RadioManager` and `CastManager` have:

```swift
static weak var cliAudioEngine: AudioEngine?

private var resolvedAudioEngine: AudioEngine {
    if AudioEngine.isHeadless, let cliEngine = Self.cliAudioEngine {
        return cliEngine
    }
    return WindowManager.shared.audioEngine
}
```

`CLIPlayer.init` wires this:
```swift
RadioManager.cliAudioEngine = audioEngine
CastManager.cliAudioEngine = audioEngine
```

All `WindowManager.shared.audioEngine` references in the cast/radio path use `resolvedAudioEngine` instead.

## `currentMetadataTitle`

`RadioManager.currentMetadataTitle` is a computed property:
```swift
var currentMetadataTitle: String? { currentStreamTitle ?? currentSomaLastPlaying }
```

`CLIPlayer` polls this every 5s via a `Timer` to display stream metadata updates.

---

## Connection State Checks

`SubsonicManager`, `JellyfinManager`, and `EmbyManager` have nested `ConnectionState` enums without `Equatable` conformance. Use pattern matching:

```swift
// Correct
if case .connected = SubsonicManager.shared.connectionState { ... }

// Wrong (compile error — ConnectionState not Equatable)
SubsonicManager.shared.connectionState == .connected
```

## LibraryFilter Usage

`LibraryFilter` has `var` properties (`Set<String>`), not a custom initializer. Use property assignment:

```swift
// Correct
var filter = LibraryFilter()
filter.artists = ["Pink Floyd"]
filter.albums = ["The Wall"]

// Wrong (compile error — no memberwise init with array literals)
LibraryFilter(artists: ["Pink Floyd"])
```

Available `LibrarySortOption` cases: `.title`, `.artist`, `.album`, `.dateAdded`, `.duration`, `.playCount`. There is no `.trackNumber` or `.genre`.

---

## `fetchPlaylistSongs` on Subsonic/Jellyfin/Emby

Added to each manager to avoid exposing `serverClient` to CLI code:

```swift
func fetchPlaylistSongs(id: String) async throws -> [SubsonicSong] {
    guard let client = serverClient else { throw SubsonicClientError.unauthorized }
    let result = try await client.fetchPlaylist(id: id)
    return result.songs
}
```

Error type is `SubsonicClientError.unauthorized` / `JellyfinClientError.unauthorized` / `EmbyClientError.unauthorized` (no `.notConnected` case exists in these clients).
