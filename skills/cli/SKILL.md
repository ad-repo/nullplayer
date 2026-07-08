---
name: cli
description: Headless CLI mode for NullPlayer. Use when working on CLI features, arguments, playback control, query commands, source resolution, or terminal display. Covers architecture, all flags, keyboard controls, and source APIs.
---

# NullPlayer CLI Mode

NullPlayer supports a `--cli` flag that launches a headless mode for browsing, searching, playing, and routing media from all configured sources via the terminal. Treat this as a first-class command surface, not a debug-only mode. The process stays alive during playback with interactive keyboard controls. Query commands (`--list-*`, `--search`) print results and exit immediately.

## Positioning

The right mental model is:

- `nullplayer` is a scriptable media control command
- it connects multiple media sources to multiple playback targets
- it works well inside shell scripts, launchers, shortcuts, and automation pipelines

Be explicit about both sides of the pipeline:

- Sources in: local library, Plex, Subsonic/Navidrome, Jellyfin, Emby, internet radio
- Targets out: local audio outputs, Sonos, Chromecast, UPnP/DLNA

Do not describe it as a daemon, background control server, or remote-control protocol unless that is separately implemented. It is a command you invoke to query, resolve, start playback, and optionally cast.

## Launching

```bash
nullplayer --cli [OPTIONS]
```

`--cli` and `--ui-testing` are mutually exclusive. In CLI mode the app runs with `.accessory` activation policy — no Dock icon, no menu bar.

If the launcher is not installed, the underlying executable is still:

```bash
NullPlayer.app/Contents/MacOS/NullPlayer --cli [OPTIONS]
```

## Automation Use Cases

This CLI is strong when you need one command to:

- query available sources, libraries, outputs, and cast devices
- resolve media from different backends with one consistent UX
- start playback on the Mac itself or send it to a network playback target
- emit machine-friendly query output via `--json`

Typical examples:

```bash
# Query sources and devices for downstream scripting
nullplayer --cli --list-sources --json
nullplayer --cli --list-devices --json
nullplayer --cli --list-outputs --json

# Start playback from different backends with one command shape
nullplayer --cli --source local --artist "Aphex Twin"
nullplayer --cli --source plex --playlist "Dinner"
nullplayer --cli --source jellyfin --album "Moon Safari"

# Use NullPlayer as a media-routing command
nullplayer --cli --source radio --station "KEXP" --cast "Living Room" --cast-type sonos
nullplayer --cli --source local --album "Kid A" --cast "Office TV" --cast-type dlna
nullplayer --cli --source subsonic --artist "Massive Attack" --cast "Kitchen Speaker" --cast-type chromecast
```

When documenting or selling the feature, good phrasing is:

- "scriptable media control command"
- "headless playback and casting command"
- "automation-friendly CLI for multi-source media routing"

Avoid vague phrasing like "CLI browser" when the real value is orchestration across sources and outputs.

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
| `--cast-type <type>` | string | `sonos`, `chromecast`, `dlna` (UPnP/DLNA target filter) |
| `--sonos-rooms <rooms>` | string | Comma-separated Sonos room names for multi-room |
| `--eq <preset>` | string | EQ preset name (case-insensitive; from `EQPreset.allPresets`) |
| `--output <device>` | string | Audio output device name (case-insensitive) |
| `--tuning <off\|Hz>` | string | Reference Tuning: `off`, or target reference frequency in Hz (e.g. `432`). Enables pitch shift for local output only (local files and HTTP streams) — not casting. Session-only override. |
| `--tuning-source <Hz>` | string | Source reference frequency in Hz (default `440`). Used with `--tuning <Hz>`. |
| `--tuning-offset-cents <n>` | float | Direct cents offset (±2400). Wins over `--tuning`/`--tuning-source`. Session-only. |

## Multi-Source / Multi-Output Framing

When explaining this subsystem, always make the two-sided model clear:

1. Source selection
2. Playback routing

Source selection is handled by `--source`, library filters, search filters, playlists, radio modes, and station selection.

Playback routing is handled by:

- default local playback if no routing flag is supplied
- `--output <device>` for local audio device selection
- `--cast <device>` with optional `--cast-type` for network playback targets
- `--sonos-rooms <rooms>` when targeting grouped Sonos playback

That is why "media control command" is more accurate than "terminal player". The command is not limited to local playback; it also chooses where playback goes.

## Query vs Control Behavior

There are two main command shapes:

- Query commands: print results and exit
- Playback commands: resolve media, start playback, then remain attached for interactive control

This distinction matters for automation guidance:

- Use query commands plus `--json` when NullPlayer is feeding another step in the pipeline
- Use playback commands when NullPlayer is the execution step that actually starts playback or casting

Good examples:

```bash
# Query step
nullplayer --cli --list-playlists --source plex --json

# Execution step
nullplayer --cli --source plex --playlist "Focus" --cast "Bedroom" --cast-type sonos
```

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

### Implicit music-library selection (Plex, Jellyfin, Emby)

The CLI is audio-only, but Plex, Jellyfin, and Emby all expose non-music sections and carry over the GUI's last-selected library, which may be one of them (a Plex Movies/TV section, or a Jellyfin/Emby `Playlists`/`Video`/`Movies`/`TV shows` view). A music query against a non-music library returns `[]`, surfacing as "artist not found" / "0 artist(s)".

`CLISourceResolver.ensureMusicLibrarySelected(source:)` runs before music-only operations (`--list-artists/albums/tracks`, and artist/album/search playback — **not** playlists, which are server-level, and **not** Subsonic, see below):

- If the current library is already a music library, it is kept.
- If there is exactly one music library, it is auto-selected (and persists, since selection is written to UserDefaults).
- If there are several and the current one isn't music, it throws a clear "specify one with `--library <name>`" error listing the available music libraries.

How "is this a music library?" is decided per source:

- **Plex:** `PlexLibrary.isMusicLibrary` (from `availableLibraries`).
- **Jellyfin / Emby:** `collectionType == "music"`. **Gotcha:** `JellyfinManager.musicLibraries` / `EmbyManager.musicLibraries` are misnamed — `fetchMusicLibraries()` maps **every** view (`/Users/{id}/Views`) with no filtering, so those arrays include `Playlists`/`Video`/`Movies`/`TV shows`. Always filter by `collectionType` before treating an entry as music. `connectInBackground` only auto-selects a music library when there is exactly one view or a saved ID, so with multiple views the restored `currentMusicLibrary` is often a non-music view.

This pairs with the connectivity fix: `checkConnectivity` now `await`s the background connect/refresh task for **all** server sources (`serverRefreshTask` for Plex, `serverConnectTask` for Subsonic/Jellyfin/Emby) so `serverClient`/`currentLibrary` are populated before any query. `listSources()` awaits the same tasks so configured servers report **Connected** instead of racing to "Not configured".

**Subsonic/Navidrome is exempt** (`ensureMusicLibrarySelected` no-ops for it): it is a music-only server with no music/video split. `fetchArtists()` passes `musicFolderId: currentMusicFolder?.id`, and `nil` (the default, "all folders") returns every artist — there is no non-music library to land on.

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

## Testing

### Test Files

| File | Target | Tests | Covers |
|------|--------|-------|--------|
| `Tests/NullPlayerAppTests/CLIOptionsTests.swift` | `NullPlayerAppTests` | 12 unit | `CLIOptions.parse`, `isQueryMode`, `isSearchQuery` |

Run them:
```bash
swift test --filter CLIOptionsTests
```

`swift test` needs the projectM dylibs on the runner's rpath — if it fails to launch,
symlink them first (see the `swift-test-dylib-rpath` note):
```bash
for d in Frameworks/libprojectM-4*.dylib; do ln -sf "$PWD/$d" ".build/debug/$(basename "$d")"; done
```

### What is and isn't covered

`CLIOptionsTests` uses `@testable import NullPlayer` and calls `CLIOptions.parse([String])`
directly (index 0 is the executable path, skipped by the parser). It covers the pure,
deterministic surface: default values, every boolean/`--list-*` flag, `--cli` being a
no-op, all string/int/double value flags, and the query-vs-playback classification
(`isQueryMode`, and `isSearchQuery` flipping to playback when `--search` is combined with
`--artist`/`--album`/`--playlist`/`--radio`/`--station`). The original Plex bug command
shape (`--source plex --list-albums --artist …`) is pinned as a regression guard.

**Not unit-tested (needs live servers or a spawned binary — do via manual QA):**

- `CLISourceResolver` source resolution and `ensureMusicLibrarySelected` — depend on
  `PlexManager`/`Subsonic`/`Jellyfin`/`Emby` singletons connected to real servers. Verify
  by hand against a configured server (e.g. `--source jellyfin --list-artists` returns rows,
  not `0 artist(s)`).
- `CLIDisplay` table/JSON formatting and `CLIQueryHandler` output — no tests yet.

### Testability limitations (known quality gaps)

- **`CLIOptions.parse` calls `exit(1)` on invalid input** (bad `--decade`/`--volume`/
  `--tuning-offset-cents`, unknown flags, or a flag missing its value). That terminates the
  process, so error paths can't be unit-tested without spawning a subprocess. Parsing and
  validation should be separated (return an error instead of exiting) before those cases can
  be covered in-process — keep test inputs valid until then.
- A string flag whose value begins with `--` is treated as "missing value" (the parser
  guards `!args[i+1].hasPrefix("--")`), so values like `--search "--foo"` are rejected.

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
