# Phase 3 Tasks: Linux UI

Reference plan: `docs/superpowers/plans/2026-04-12-linux-ui-phase-3.md`

This breakdown covers the full seven-window Linux UI port:
- main player
- playlist
- equalizer
- library browser
- spectrum
- waveform
- projectM

PRs are sequential. The library browser and main window are the first implemented Linux windows because library-driven browsing and the primary playback surface are both needed to exercise playback, queueing, and broader UI flows realistically. The first milestone is still the core three windows, but the order inside that milestone is:
- library browser
- main player
- playlist

## Porting Inventory

### Cross-Cutting UI Platform Work
- Linux desktop app target and toolkit bootstrap.
- App lifecycle, main-thread ownership, and event loop.
- Linux window/controller abstraction to replace direct `NSWindow` assumptions in provider protocols and `WindowManager`.
- Borderless/custom chrome support where needed.
- Multi-window creation, ownership, close/hide/minimize behavior, and focus ordering.
- Window dragging, resize edges, fullscreen support where applicable, and always-on-top handling.
- Center-stack layout rules for `main + EQ + playlist + spectrum + waveform`.
- Side-window layout rules for `library browser + projectM`.
- Window snapping/docking, layout lock, and hide-title-bars behavior.
- Window frame persistence and restore.
- Per-window visibility state and toggle wiring from the main window.
- Context menus, popup menus, file dialogs, save dialogs, URL entry dialogs, and confirmation flows.
- Keyboard shortcut routing across windows.
- Drag-and-drop for file URLs and folders where supported.
- Accessibility labels/roles and focus navigation.
- Linux-safe artwork/image loading and caching path.
- Linux-safe notification delivery and main-thread UI updates.

### 1. Main Player Window Inventory
- Window chrome:
  - close
  - minimize
  - shade
  - draggable borderless frame
  - hide-title-bars compatibility
  - always-on-top/focus styling
- Transport row:
  - previous
  - play
  - pause
  - stop
  - next
  - open/eject
- Playback toggles:
  - shuffle
  - repeat
- Secondary-window toggles:
  - EQ
  - playlist
  - library browser
  - spectrum
  - waveform
  - projectM
- Output menu button (`btn_cast` today, but functionally output devices).
- Appearance/skin button (`btn_sk`) needs an explicit Linux decision:
  - hide for first cut
  - or replace with a Linux appearance menu
- Time display:
  - elapsed/current
  - total duration
  - time display mode compatibility if preserved
  - play/pause/stop status indicator
- Seek bar:
  - click/drag seek
  - video-seek parity decision where video is out of scope
- Volume bar:
  - click/drag volume
- Now-playing display:
  - marquee title text
  - artist/title composition
  - radio metadata updates
  - connection-state updates
  - video-title override handling decision
- Embedded visualization area:
  - mini spectrum/default vis mode
  - visualization mode persistence
  - visibility/context interactions
- Input behaviors:
  - drag-and-drop add/play
  - context menu
  - keyboard shortcuts
- Visibility indicators for secondary windows must stay in sync with actual window state.

### 2. Playlist Window Inventory
- Window chrome:
  - close
  - shade
  - draggable frame
  - dock/undock behavior
  - hide-title-bars compatibility
- Playlist list rendering:
  - current-track highlight
  - selected-row highlight
  - duration display
  - video marker/prefix
  - empty-state message
  - row clipping and current-track marquee
  - optional artwork-backed background treatment
- Selection model:
  - single select
  - cmd-toggle select
  - shift-range select
  - selection anchor behavior
  - auto-scroll to current track
- Playback actions:
  - double-click row to play
  - Enter to play selected
- Scrolling and navigation:
  - wheel scroll
  - Up/Down
  - Page Up/Page Down
  - Home/End
  - Delete
  - Cmd-A
- Bottom-bar buttons:
  - `playlist_btn_add`
  - `playlist_btn_rem`
  - `playlist_btn_sel`
  - `playlist_btn_misc`
  - `playlist_btn_list`
- Add menu:
  - add URL
  - add directory
  - add files
- Remove menu:
  - remove all
  - crop selection
  - remove selected
  - remove dead files
- Selection menu:
  - invert
  - select none
  - select all
- Misc menu:
  - sort by title
  - sort by filename
  - sort by path
  - randomize
  - reverse
  - file info
- List menu:
  - new playlist
  - save playlist
  - load playlist
- Context menu parity for the same actions.
- Drag-and-drop file/folder append behavior.

### 3. Equalizer Window Inventory
- Window chrome:
  - close
  - shade
  - draggable frame
  - dock/undock behavior
  - hide-title-bars compatibility
- EQ power state:
  - ON/OFF toggle
- Auto EQ:
  - AUTO toggle
  - track-change-driven preset application
- Preamp control:
  - integrated slider
  - live updates
  - double-click reset to 0dB
- EQ band controls (21 bands on macOS; 10 bands on Linux GStreamer — driven dynamically by `EQConfiguration.bandCount`):
  - slider hit testing
  - live drag updates
  - double-click band reset
  - manual edit clears active preset highlight
- Preset row:
  - FLAT
  - ROCK
  - POP
  - ELEC
  - HIP
  - JAZZ
  - CLSC
- EQ graph/curve visualization.
- Frequency labels.
- Generic context menu/global menu wiring if preserved.

### 4. Library Browser Window Inventory
- This is the first Linux window to implement.
- The browser is not a secondary surface in practice; it is the main entry point for testing:
  - local-library queries
  - enqueue/play flows
  - ratings and metadata actions
  - remote-provider capability gates
  - queue population for playlist and transport testing
- Window chrome:
  - close
  - shade
  - draggable frame
  - side-window behavior
  - hide-title-bars compatibility
- Source/server bar:
  - local source
  - Plex source(s)
  - Subsonic source(s)
  - Jellyfin source(s)
  - Emby source(s)
  - radio source
  - library/folder selectors
  - source-specific add/manage/clear menus
  - Plex link sheet entry point
- Browse modes/tabs:
  - Artists
  - Albums
  - Plists
  - Movies
  - Shows
  - Search
  - Radio
  - Data/History
- Tab/function implications:
  - Artists:
    - artist list
    - expand artist to albums/tracks where supported
    - artist play/enqueue/rating actions
  - Albums:
    - album list
    - expand album to tracks where supported
    - album play/enqueue/rating actions
  - Plists:
    - playlist list
    - expand playlist to tracks where supported
    - playlist play/enqueue actions
  - Movies:
    - movie library browsing
    - movie play actions
    - explicit capability gate if Linux video UI is not yet in scope
  - Shows:
    - show -> season -> episode hierarchy
    - episode play actions
    - explicit capability gate if Linux video UI is not yet in scope
  - Search:
    - search results across the active source
    - navigate from search results back into artists/albums where applicable
  - Radio:
    - station/folder hierarchy
    - rating and folder management
    - radio-play generation flows
  - Data/History:
    - play-history presentation
    - mode-specific hosting strategy on Linux
- Search UX:
  - search field state
  - Enter-to-search behavior
  - typeahead behavior
  - empty states
- Main list/tree area:
  - hierarchical expand/collapse
  - row selection
  - double-click actions
  - play/enqueue actions
  - source-specific display items
  - loading states/spinners
- Column system:
  - track columns
  - album columns
  - artist columns
  - radio columns
  - column sorting
  - column resize
  - column visibility config menu
  - horizontal scrolling
  - persisted widths/visibility/sort
- Alphabet jump index.
- Art-only mode:
  - artwork display
  - current-track metadata overlay
  - visualizer overlay button
  - rating button/overlay
  - artwork cycling/interaction
- Ratings:
  - local track rating
  - local album rating
  - local artist rating
  - remote rating adapters where supported
  - radio station ratings
- Metadata editing panels:
  - edit track tags
  - edit album tags
  - edit video tags
  - auto-tag candidate panels/accessories
- Local-library management:
  - add files
  - add video files
  - add watch folder
  - manage watch folders
  - clear local library subsets
- Radio management:
  - add station
  - create folder
  - reset/add default stations
  - folder membership menus
  - smart folder menus
- History/Data mode hosting.
- Context menus for all supported item types.
- Remote source item actions and expansion paths.

### 5. Spectrum Window Inventory
- Window chrome:
  - close
  - shade
  - draggable/resizable frame
  - fullscreen
  - dock/undock behavior
  - hide-title-bars compatibility
- Rendering lifecycle:
  - start on show
  - stop on hide/miniaturize/close
  - resize-aware redraw
- Visualization modes:
  - quality/mode menu
  - double-click mode cycle
  - responsiveness/decay menu
  - normalization menu
- Mode-specific style controls:
  - flame style
  - flame intensity
  - lightning style
  - matrix color
  - matrix intensity
- vis_classic-specific controls:
  - profile list
  - next/previous profile
  - fit to width
  - transparent background
  - import INI
  - export current INI
- Keyboard controls:
  - fullscreen
  - escape to close/exit fullscreen
  - arrow-key mode/profile/style behavior
- Context menu parity for all of the above.

### 6. Waveform Window Inventory
- Window chrome:
  - close
  - draggable/resizable frame
  - dock/undock behavior
  - hide-title-bars compatibility
- Shared waveform rendering:
  - active track updates
  - playback-time updates
  - reload behavior
  - stop loading when hidden
- Interaction model:
  - click/drag seek on waveform
  - cue-point rendering and interaction if enabled
  - tooltip behavior if enabled
- Display options:
  - transparent background mode
  - played/unplayed rendering
  - cue-point colors and overlays
- Shade mode needs an explicit Linux decision because the modern macOS controller currently no-ops `setShadeMode`.

### 7. ProjectM Window Inventory
- Window chrome:
  - close
  - shade
  - draggable/resizable frame
  - fullscreen
  - hide-title-bars compatibility
- Rendering lifecycle:
  - start on show
  - stop on hide/miniaturize/close
  - resize-aware redraw
- Visualization engine handling:
  - projectM availability detection
  - visualization engine selector
  - low-power vs full-quality mode
- Preset navigation:
  - next
  - previous
  - random
  - explicit preset selection
  - set current as default
- Preset organization:
  - ratings
  - favorites
  - favorites menu
  - presets menu
  - preset lock state
- Auto cycling:
  - manual only
  - auto-cycle
  - auto-random
  - interval selection
- Input tuning:
  - audio sensitivity
  - beat sensitivity
- Keyboard controls:
  - fullscreen
  - next/previous/random preset
  - cycle mode
  - performance mode
  - rating shortcuts
- Context menu parity for all of the above.
- Linux dependency gate for `libprojectM`/rendering backend must be explicit.

## PR Breakdown

## Package.swift Changes (prerequisite, lands before or with PR 1)

### Status (2026-04-13)
- [x] Added `NullPlayerLinuxUI` executable product/target in `Package.swift`.
- [x] Added `CGTK4` system library target scaffold in `Sources/CGTK4/`.
- [x] Moved `MediaLibraryStore` + dependent browser/library types into `NullPlayerCore`.
  - Core-side implementations now exist in `NullPlayerCore`; legacy macOS-side copies remain temporarily until full call-site migration.

### New target: `NullPlayerLinuxUI`
- Type: executable
- Sources: `Sources/NullPlayerLinuxUI/`
- Dependencies: `NullPlayerPlayback`, `NullPlayerCore`, `CGTK4` (system library)
- Platform: no explicit platform restriction; Linux-only in practice via conditional compilation and build configuration
- Must not depend on `NullPlayer` (macOS-only target) or any AppKit-importing module

### New target: `CGTK4` (system library)
Modeled on the existing `CGStreamer` pattern (`Sources/CGStreamer/module.modulemap`):
```
// Sources/CGTK4/module.modulemap
module CGTK4 [system] {
    header "gtk4_link.h"
    link "gtk-4"
    link "gdk-4"
    link "graphene-1.0"
    link "glib-2.0"
    link "gobject-2.0"
    link "gio-2.0"
    export *
}
```
The `gtk4_link.h` header includes `<gtk/gtk.h>` and any additional GDK/GLib headers needed for direct C interop. The `CGTK4` target goes in `Sources/CGTK4/` alongside `CGStreamer`. This is only needed if the spike (PR 1) chooses the direct C interop path; a SwiftPM package dependency like `swift-gtk4` would replace this target.

### Dependency note: SQLite.swift
`MediaLibraryStore` depends on `SQLite.swift` (via `import SQLite`). When `MediaLibraryStore` moves to `NullPlayerCore`, `SQLite.swift` must become a dependency of `NullPlayerCore` in `Package.swift` instead of (or in addition to) `NullPlayer`.

### Required `NullPlayerCore` moves (prerequisite for `NullPlayerLinuxUI`)
The following are currently in `NullPlayer` (macOS-only target) and must move to `NullPlayerCore` before `NullPlayerLinuxUI` can use them:
- `MediaLibraryStore` — local library queries and mutations
- `LocalFileDiscovery` — audio/video file discovery and drop handling. **Transitive dependency**: calls `AudioFileValidator.supportedExtensions` and `AudioFileValidator.supportedVideoExtensions` (defined in `Sources/NullPlayer/Audio/AudioFileValidator.swift`); `AudioFileValidator` must also move to `NullPlayerCore`.
- `AudioFileValidator` — extension-set definitions for supported audio/video file types (enum in `Sources/NullPlayer/Audio/AudioFileValidator.swift`); required by `LocalFileDiscovery`
- `ModernBrowserSource` — enum with cases `.local`, `.plex(serverId:)`, `.subsonic(serverId:)`, `.jellyfin(serverId:)`, `.emby(serverId:)`, `.radio`
- `ModernBrowseMode` — enum with raw values `.artists = 0`, `.albums = 1`, `.plists = 3`, `.movies = 4`, `.shows = 5`, `.search = 6`, `.radio = 7`, `.history = 8`
- `ModernBrowserSortOption` — defined in `Sources/NullPlayer/Windows/ModernLibraryBrowser/ModernLibraryBrowserView.swift` (same file as `ModernBrowserSource`/`ModernBrowseMode`). Cases: `.nameAsc`, `.nameDesc`, `.dateAddedDesc`, `.dateAddedAsc`, `.yearDesc`, `.yearAsc`. Used as a parameter by `MediaLibraryStore` query methods (`artistNames`, `albumSummaries`, `artistLetterOffsets`, `albumLetterOffsets`). Its `save()`/`load()` methods use `UserDefaults`, which will need a cross-platform persistence adapter on Linux.

### Supporting types in `Sources/NullPlayer/Data/Models/MediaLibrary.swift`
The following types are defined in `MediaLibrary.swift` (macOS-only) and are used by `MediaLibraryStore` return values. They must either move to `NullPlayerCore` alongside `MediaLibraryStore` or be re-exported:
- `AlbumSummary` (line ~283) — returned by `albumSummaries()`, `albumsForArtist()`, `albumsForArtistsBatch()`
- `LocalVideo` (line ~292) — local movie file representation
- `LocalEpisode` (line ~332) — local TV episode representation
- `FileScanSignature` (line ~432) — file-change detection for library scanning

Note: `LibraryTrack`, `Album`, `Artist`, `LibrarySortOption`, `LibraryFilter`, and `LibraryError` are already in `Sources/NullPlayerCore/Models/MediaLibraryTypes.swift` and do not need to move.

Moving these may require auditing `NullPlayer` import sites to ensure no AppKit or macOS-only references are dragged into `NullPlayerCore` in the process.

## PR 1: Linux UI Stack Spike And Desktop App Stub
**Goal**: Make the toolkit decision on a real app shape, not a toy demo.

### Tasks
- [x] Add the `NullPlayerLinuxUI` executable target to `Package.swift` beside `NullPlayer` and `NullPlayerCLI`, with dependencies on `NullPlayerPlayback` and `NullPlayerCore` (see Package.swift Changes section above).
  - The system library wrapper pattern already exists in `CGStreamer` (`Sources/CGStreamer/`); use the same pattern to add a `CGTK4` system library target if raw C interop is chosen (see Package.swift Changes section for the modulemap template).
- [x] The spike executable's `Sources/NullPlayerLinuxUI/main.swift` follows the CLI entry point pattern from `Sources/NullPlayerCLI/main.swift`:
  - `#if os(Linux)` guard at top level
  - `import NullPlayerCore`, `import NullPlayerPlayback`, `import CGTK4` (or the chosen binding)
  - GTK initialization (`gtk_init()`) and main loop (`gtk_main()` or `g_application_run()`)
  - Signal handler installation for clean shutdown (see `installSignalHandlers` in `NullPlayerCLI/main.swift`)
  - The `#else` branch prints a "Linux-only" message, matching the CLI pattern
- [x] Build a minimal Linux app bootstrap that can create:
  - one main player window
  - a second top-level window
  - a list/tree view representative of playlist/library work
- [x] Evaluate GTK4 Swift binding options; candidates to assess in the spike:
  - **`swift-gtk4`**: raw Swift bindings over the GTK4 C API
  - **`Adwaita`**: higher-level GTK4 Swift library built on `gtk4-swift`, provides widget abstractions
  - **Custom C interop** (`CGStreamer` pattern): add a GTK4 system library target; no external SwiftPM dependency required
  - Evaluation result (2026-04-13): choose Custom C interop (`CGTK4`) for direct control and zero additional package dependency in the initial spike.
- [x] Test critical toolkit capabilities early:
  - multiple windows
  - menus/context menus
  - keyboard shortcuts
  - drag-and-drop
  - file dialogs
  - scrolling list performance
  - main-thread/async update model
  - Status from spike implementation (2026-04-13):
    - multiple windows: implemented
    - menus/context menus: implemented via GTK popover context menus in main/playlist
    - keyboard shortcuts: implemented for core main-window actions
    - drag-and-drop: implemented for main load + playlist append
    - file dialogs: seam wired (`LinuxMenuDialogService`); native dialog backend remains to be filled
    - scrolling list performance: implemented with GTK `ScrolledWindow` + `ListBox`
    - main-thread/async updates: implemented via `AudioEngineDelegate` -> window controller updates
- [x] Record one explicit go/no-go decision.
  - Decision (2026-04-13): **GO** with `CGTK4` custom C interop for the initial Linux UI spike.
- [x] If direct bindings fail the spike, pivot immediately to a higher-level GTK-backed abstraction.
  - Not triggered: direct `CGTK4` path is currently viable; fallback remains documented.

### Verify
- [x] Linux app target builds and launches a visible window.
  - Build is passing; Linux runtime launch path is implemented in `main.swift` + `LinuxAppLifecycle` and opens real GTK windows.
- [x] The decision on toolkit direction is explicit in docs.

## PR 2: Cross-Platform Window And Presentation Seams
**Goal**: Stop treating AppKit window/controller types as the shared UI contract.

### Tasks
- [x] Introduce Linux-safe window/provider abstractions for all seven windows.
  - The seven existing provider protocols to adapt: `MainWindowProviding`, `PlaylistWindowProviding`, `LibraryBrowserWindowProviding`, `EQWindowProviding`, `SpectrumWindowProviding`, `WaveformWindowProviding`, `ProjectMWindowProviding`.
  - All seven are currently defined in `Sources/NullPlayer/App/` (macOS-only) and each has a `window: NSWindow` property. The abstraction work must replace or conditionally compile out that `NSWindow` reference before Linux controllers can conform.
  - Concrete protocol methods each Linux controller must implement (beyond `window`):
    - **MainWindowProviding**: `showWindow(_:)`, `updateTrackInfo(_: Track?)`, `updateVideoTrackInfo(title: String)`, `clearVideoTrackInfo()`, `updateTime(current: TimeInterval, duration: TimeInterval)`, `updatePlaybackState()`, `updateSpectrum(_: [Float])`, `toggleShadeMode()`, `skinDidChange()`, `windowVisibilityDidChange()`, `setNeedsDisplay()` + properties `isShadeMode: Bool`, `isWindowVisible: Bool`
    - **PlaylistWindowProviding**: `showWindow(_:)`, `skinDidChange()`, `reloadPlaylist()`, `setShadeMode(_: Bool)` + properties `isShadeMode: Bool`
    - **LibraryBrowserWindowProviding**: `showWindow(_:)`, `skinDidChange()`, `setShadeMode(_: Bool)`, `reloadData()`, `showLinkSheet()` + properties `isShadeMode: Bool`, `browseModeRawValue: Int`
    - **EQWindowProviding**: `showWindow(_:)`, `skinDidChange()`, `setShadeMode(_: Bool)` + properties `isShadeMode: Bool`
    - **SpectrumWindowProviding**: `showWindow(_:)`, `skinDidChange()`, `stopRenderingForHide()`, `setShadeMode(_: Bool)` + properties `isShadeMode: Bool`
    - **WaveformWindowProviding**: `showWindow(_:)`, `skinDidChange()`, `setShadeMode(_: Bool)`, `updateTrack(_: Track?)`, `updateTime(current: TimeInterval, duration: TimeInterval)`, `reloadWaveform(force: Bool)`, `stopLoadingForHide()` + properties `isShadeMode: Bool`
    - **ProjectMWindowProviding**: `showWindow(_:)`, `skinDidChange()`, `stopRenderingForHide()`, `setShadeMode(_: Bool)`, `toggleFullscreen()`, `nextPreset(hardCut: Bool)`, `previousPreset(hardCut: Bool)`, `selectPreset(at: Int, hardCut: Bool)`, `randomPreset(hardCut: Bool)`, `reloadPresets()` + properties `isShadeMode: Bool`, `isFullscreen: Bool`, `isPresetLocked: Bool`, `isProjectMAvailable: Bool`, `currentPresetName: String`, `currentPresetIndex: Int`, `presetCount: Int`, `presetsInfo: (bundledCount: Int, customCount: Int, customPath: String?)`
  - **Note**: `skinDidChange()` can be a no-op in all Linux controllers initially — there is no classic/modern skin system on Linux. The method must exist for protocol conformance but the body can be empty.
  - **Note**: `AppState` is already in `Sources/NullPlayerCore/Models/AppState.swift` and is cross-platform. Linux controllers can use it directly for state persistence without moving anything.
- [x] Split AppKit-specific responsibilities out of provider protocols and `WindowManager` assumptions.
  - Linux now uses `LinuxWindowProviding` protocols + `LinuxWindowCoordinator` without `NSWindow` or AppKit imports.
- [x] Create Linux-facing window controllers conforming to the extracted protocols (all in `Sources/NullPlayerLinuxUI/Windows/`):
  - `LinuxMainWindowController: MainWindowProviding`
  - `LinuxPlaylistWindowController: PlaylistWindowProviding`
  - `LinuxLibraryBrowserWindowController: LibraryBrowserWindowProviding`
  - `LinuxEQWindowController: EQWindowProviding`
  - `LinuxSpectrumWindowController: SpectrumWindowProviding`
  - `LinuxWaveformWindowController: WaveformWindowProviding`
  - `LinuxProjectMWindowController: ProjectMWindowProviding`
- [x] Move `ModernBrowserSource`, `ModernBrowseMode`, and `ModernBrowserSortOption` from `NullPlayer` to `NullPlayerCore` as a prerequisite for `LinuxLibraryBrowserWindowController` to use them.
- [x] Extract shared command surfaces for:
  - transport
  - playlist mutations
  - EQ state
  - window visibility toggles
  - output-device selection
- [x] Define Linux-safe menu/dialog service seams.
- [x] Define Linux-safe image/artwork loading seam.
- [x] Define Linux-safe graphics capability seam for spectrum/waveform/projectM decisions.

### Verify
- [x] Shared UI-facing code can compile without AppKit imports.
- [x] macOS build still wires through existing AppKit implementations.

## PR 3: Linux App Shell And Window Coordinator
**Goal**: Stand up the Linux multi-window shell before porting individual windows.

### Tasks
- [x] Implement Linux app lifecycle (`LinuxAppLifecycle` in `Sources/NullPlayerLinuxUI/App/LinuxAppLifecycle.swift` — Linux equivalent of `AppDelegate`) and event loop ownership. Follow the CLI bootstrap pattern from `Sources/NullPlayerCLI/main.swift`: create the `AudioEngineFacade` with `LinuxGStreamerAudioBackend`, install signal handlers, then enter the GTK main loop.
- [x] Implement the Linux window coordinator (`LinuxWindowCoordinator` in `Sources/NullPlayerLinuxUI/App/LinuxWindowCoordinator.swift` — Linux equivalent of `WindowManager`) for top-level window creation, show, hide, and toggle for all seven windows. Must map to the key `WindowManager` methods:
  - `showMainWindow()` / `togglePlaylist()` / `toggleEqualizer()` / `togglePlexBrowser()` / `toggleSpectrum()` / `toggleWaveform()` / `toggleProjectM()`
  - Visibility tracking per window (the macOS `WindowManager` uses `NSWindow.isVisible`)
  - Owns references to all seven Linux window controllers via their provider protocols, just as the macOS `WindowManager` does
- [x] Create Linux equivalents for window creation/show/hide/toggle for all seven windows.
- [x] Implement basic focus ordering and bring-to-front behavior.
- [x] Implement per-window visibility state so the main window can reflect secondary-window visibility.
- [x] Add placeholder Linux windows for all seven product windows so the shape is real early.
- [x] Introduce initial frame persistence hooks.

### Verify
- Linux can open, close, hide, and restore each of the seven windows.
- Visibility state is reflected correctly in the coordinator.

## PR 4: Library Browser Local-Only Core
**Goal**: Land the first useful Linux browser because it is the primary entry path for real playback testing.

### Tasks
- [x] Prerequisite: `MediaLibraryStore` and `LocalFileDiscovery` must be moved to `NullPlayerCore` before this PR can wire up data access (see Package.swift Changes; may land in PR 2 or as its own commit).
- [x] Implement `LinuxLibraryBrowserWindowController: LibraryBrowserWindowProviding` as the Linux controller for this window.
- [x] Extract Linux-safe local-library query/provider surface from current AppKit-heavy browser code, using `MediaLibraryStore` methods (defined in `Sources/NullPlayer/Data/Models/MediaLibraryStore.swift`, will be in `NullPlayerCore` after the prerequisite move):
  - `func artistNames(limit: Int, offset: Int, sort: ModernBrowserSortOption) -> [String]` — artist list
  - `func albumSummaries(limit: Int, offset: Int, sort: ModernBrowserSortOption) -> [AlbumSummary]` — album list (returns `AlbumSummary` with fields: `id: String`, `name: String`, `artist: String?`, `year: Int?`, `trackCount: Int`)
  - `func albumsForArtist(_ artistName: String) -> [AlbumSummary]` — expand artist
  - `func albumsForArtistsBatch(_ names: [String]) -> [String: [AlbumSummary]]` — batch expand for multiple artists
  - `func tracksForAlbum(_ albumId: String) -> [LibraryTrack]` — expand album (returns `LibraryTrack` from `NullPlayerCore/Models/MediaLibraryTypes.swift`)
  - `func searchTracks(query: String, limit: Int, offset: Int) -> [LibraryTrack]` — track search
  - `func artistLetterOffsets(sort: ModernBrowserSortOption) -> [String: Int]` / `func albumLetterOffsets(sort: ModernBrowserSortOption) -> [String: Int]` — alphabet jump index
- [x] Port browser window chrome and side-window behavior.
- [x] Port local-only source bar behavior.
- [x] Port the core browse modes needed for initial Linux usefulness (`ModernBrowseMode` cases):
  - `.artists = 0`
  - `.albums = 1`
  - `.search = 6`
- Add explicit call on whether local Movies/Shows are part of this phase or deferred until Linux video UI exists.
- [x] Port search UX and empty states.
- Port list/tree rendering, selection, expansion, double-click play, and enqueue/play actions.
- Port core column system:
  - default columns
  - sort
  - resize
  - horizontal scroll
  - persisted widths/sort
- Port alphabet jump index if it remains part of the chosen Linux toolkit layout.
- [x] Port local-library management actions:
  - add files
  - add watch folder
  - manage watch folders
  - clear local library subsets
- Port local ratings for tracks/albums/artists if they remain in first-cut scope.
- Port local item context menus.
- [x] Ensure browser actions can drive real playback starts and queue mutations through shared seams.

### Verify
- Linux user can browse the local library, search it, and play/enqueue from it.
- Local watch-folder and library-management flows are wired.

## PR 5: Main Player Window
**Goal**: Land the primary Linux playback window alongside the browser-driven flows.

### Tasks
- [x] Implement `LinuxMainWindowController: MainWindowProviding` as the Linux controller for the main player window.
  - Required `MainWindowProviding` methods to implement (see full signatures in PR 2 notes above).
  - Playback commands go through `AudioEngineFacade` (`Sources/NullPlayerPlayback/Audio/AudioEngineFacade.swift`). Key methods the main window will call:
    - Transport: `play()`, `pause()`, `stop()`, `next()`, `previous()`
    - Seek: `seek(to: TimeInterval)`, `seekBy(seconds: Double)`
    - Volume/balance: `volume` (get/set `Float`), `balance` (get/set `Float`)
    - Toggles: `shuffleEnabled` (get/set `Bool`), `repeatEnabled` (get/set `Bool`)
    - Open: `loadFiles(_: [URL])`, `loadFolder(_: URL)`, `appendFiles(_: [URL])`
    - State observation: `state` (returns `PlaybackState`), `currentTime` (returns `TimeInterval`), `duration` (returns `TimeInterval`), `currentTrack` (returns `Track?`)
    - Visualization: `addSpectrumConsumer(_:)` / `removeSpectrumConsumer(_:)` for the embedded mini spectrum
    - Output: `outputDevices`, `currentOutputDevice` for the output-device menu
- [x] Port main-window custom chrome behavior needed for Linux:
  - close
  - minimize
  - optional shade
  - drag
  - focus styling
  - Uses GTK server-side chrome for close/minimize/drag/focus; shade remains a lightweight state toggle for now.
- [x] Port transport controls:
  - previous
  - play
  - pause
  - stop
  - next
  - open/eject
- [x] Port playback toggles:
  - shuffle
  - repeat
- [x] Port secondary-window toggle buttons:
  - EQ
  - playlist
  - library browser
  - spectrum
  - waveform
  - projectM
- [x] Port output-device menu button.
- [x] Make an explicit Linux decision for the current skin/appearance button.
  - Linux decision (2026-04-13): defer skin/appearance button and show explicit non-interactive note in the main window.
- [x] Port time display and playback status indicator.
- [x] Port seek and volume sliders.
- [x] Port marquee/now-playing metadata with radio metadata update path.
- [x] Port the embedded mini visualization area or define a Linux-safe placeholder behavior.
- [x] Port keyboard shortcuts and context menu.
  - Keyboard shortcuts are wired (`Space`, arrow seek, `Ctrl+O/P/E/B/S/W/M`); right-click context menu now exposes core transport/open actions.
- [x] Port file/folder drag-and-drop into the main window.
- [x] Ensure the main window reflects playback launched from the library browser immediately and correctly.

### Verify
- [x] End-to-end playback can be started from the library browser and controlled from the Linux main window.
- [x] Secondary-window toggle state updates correctly.

## PR 6: Playlist Window
**Goal**: Land full queue editing on Linux after browser + main window flows are in place.

### Tasks
- [x] Port playlist window chrome and drag behavior.
- [x] Port track list rendering, current-track highlight, selection highlight, duration display, video marker, and empty state.
- [x] Port current-track marquee behavior.
- [x] Port selection model:
  - single
  - cmd-toggle
  - shift-range
  - selection anchor
  - Implemented with GTK multiple-selection list behavior and multi-select aware remove/crop actions.
- [x] Port double-click and Enter-to-play behavior.
- [x] Port wheel scrolling and keyboard navigation.
- [x] Port bottom-bar buttons and menus:
  - add
  - remove
  - selection
  - misc
  - list
  - Implemented as direct bottom action rows for first cut (not grouped submenu buttons yet).
- [x] Port playlist actions:
  - [x] add URL
  - [x] add directory
  - [x] add files
  - [x] remove all
  - [x] crop selection
  - [x] remove selected
  - [x] remove dead files
  - [x] sort by title/artist/album/filename/path
  - [x] reverse
  - [x] randomize
  - [x] file info
  - [x] new/save/load playlist
- [x] Port context menu parity.
- [x] Port drag-and-drop append behavior.
- [x] Decide whether artwork-backed playlist background is included in the first Linux cut or temporarily simplified.
  - Linux decision (2026-04-13): use a simplified non-artwork playlist background in first cut.

### Verify
- [x] Linux playlist window can replace the CLI for queue editing.
- [x] Save/load playlist flow works end-to-end.

## PR 7: Window Layout, Docking, And Global Window Behavior
**Goal**: Reintroduce the multi-window product shape on Linux beyond simple independent windows.

### Tasks
- Port center-stack window relationships for:
  - main
  - EQ
  - playlist
  - spectrum
  - waveform
- Port side-window positioning for:
  - library browser
  - projectM
- Port snap/dock calculations.
- Port layout lock behavior.
- Port hide-title-bars behavior where it materially affects interaction.
- Port always-on-top behavior.
- Port frame restore rules for all seven windows.
- Port visibility-change notifications back to the main window.
- Port bring-all-windows-to-front rules and fullscreen exceptions.

### Verify
- Window layout behavior is coherent on Linux even if not yet pixel-identical to macOS.
- Docked windows move and restore together correctly.

## PR 8: Equalizer Window
**Goal**: Port the EQ window completely.

### Tasks
- Port EQ window chrome and dock behavior.
- Port ON/OFF and AUTO controls.
- Port preamp slider and reset behavior.
- Port EQ sliders and reset behavior.
  - **Band count mismatch**: macOS uses `EQConfiguration.modern21` (21 bands) while the Linux GStreamer backend provides 10-band EQ via `equalizer-nbands` (`supportsEQ: true`, `eqBandCount: 10`). The Linux EQ window must use `eqConfiguration.frequencies.count` (from `EQConfiguration` in `Sources/NullPlayerCore/Audio/EQConfiguration.swift`) dynamically rather than hardcoding 21 sliders. The `EQConfiguration` struct already has `bandCount`, `frequencies`, and `displayLabels` arrays that size correctly for both 10-band and 21-band layouts. Preset gain arrays will be remapped automatically via `EQConfiguration.gainValues(remapping:from:)`.
- Port preset buttons and active-preset highlighting.
- Port EQ curve rendering and frequency labels.
- Port auto-EQ behavior on track changes.
- Port generic context-menu/global-menu integration if retained.

### Verify
- Linux EQ window drives the shared playback EQ state correctly.
- Preset application and manual slider adjustment behave correctly.

## PR 9: Spectrum Window
**Goal**: Port the analyzer window and its Linux rendering/config surface.

### Tasks
- Port spectrum window chrome, resize behavior, shade mode, and fullscreen.
- Wire Linux rendering lifecycle start/stop hooks.
- Port mode/quality selection.
- Port responsiveness/decay and normalization controls.
- Port flame, lightning, and matrix style/intensity controls.
- Decide Linux support level for `vis_classic` mode:
  - full support
  - capability-gated support
  - temporary omission with explicit UI fallback
  - **Note**: `vis_classic` depends on `CVisClassicCore`, a C++ library at `Sources/CVisClassicCore/` (contains `VisClassicCore.cpp` plus upstream C headers). This library currently compiles only on macOS. Porting it to Linux requires: (1) verifying the C++ source has no macOS-specific dependencies (CoreFoundation, Accelerate, etc.), (2) adding Linux compilation support in `Package.swift`, and (3) ensuring the Metal rendering path in `VisClassicBridge` has a non-Metal alternative (OpenGL or Cairo) for Linux.
- If supported, port vis_classic profile management and fit/transparent-background toggles.
- Port keyboard shortcuts and context menu parity.

### Verify
- Linux spectrum window renders correctly, resizes correctly, and stops rendering when hidden.

## PR 10: Waveform Window
**Goal**: Port the waveform window and its interaction model.

### Tasks
- Port waveform window chrome and resize behavior.
- Port waveform rendering using shared waveform services.
  - **GStreamer capability gap**: The Linux GStreamer backend currently reports `supportsWaveformFrames: false`. The waveform window depends on PCM frame data delivered via `addWaveformConsumer(_:)` / `removeWaveformConsumer(_:)` on `AudioEngineFacade`. This PR must either: (1) extend the GStreamer backend to extract PCM frames (e.g., via a `level` or `appsink` element tapped into the pipeline), or (2) capability-gate the waveform window so it shows a "Waveform not available" state when the backend does not support it. Option 2 is safer for initial delivery; the backend extension can follow.
- Port track/time update wiring.
- Port click/drag seek behavior over the waveform.
- Port cue-point rendering and interaction if enabled for Linux.
- Port transparent-background mode.
- Port tooltip behavior if retained.
- Make an explicit Linux decision on shade mode because the current modern controller effectively disables it.
- Port stop-loading-on-hide behavior.

### Verify
- Linux waveform window can render a track waveform and seek accurately.
- Hidden/closed waveform windows do not leak background work.

## PR 11: ProjectM Enablement And Window Port
**Goal**: Port the visualization window behind an explicit Linux dependency gate.

### Tasks
- Decide and document Linux `libprojectM` support path.
  - **Current state**: `CProjectM` is defined in `Package.swift` at `Frameworks/libprojectm-4/` with `condition: .when(platforms: [.macOS])` — it is macOS-only. On macOS it wraps a pre-built `libprojectM-4.dylib`.
  - **Linux approach**: Create a system library target `CProjectMLinux` (or conditionally compile `CProjectM`) following the `CGStreamer` pattern:
    ```
    // Sources/CProjectMLinux/module.modulemap
    module CProjectMLinux [system] {
        header "projectm_link.h"
        link "projectM-4"
        export *
    }
    ```
    This assumes `libprojectm-4` is installed via the system package manager (`apt install libprojectm-dev` or equivalent). The `projectm_link.h` header includes `<projectM-4/projectM.h>`.
  - The existing `ProjectMWrapper` (`Sources/NullPlayer/Visualization/ProjectMWrapper.swift`) uses the C API via `CProjectM` — the Linux wrapper would use the same C API surface through `CProjectMLinux`.
- Add Linux build/dependency wiring for projectM if viable.
- Port projectM window chrome, resize behavior, shade mode, and fullscreen.
- Port rendering lifecycle start/stop hooks.
- Port preset navigation:
  - next
  - previous
  - random
  - select preset
  - set current default
- Port preset ratings and favorites.
- Port cycle mode and interval selection.
- Port visualization engine selection.
- Port audio sensitivity, beat sensitivity, and performance mode.
- Port keyboard shortcuts and context menu parity.
- If projectM is not viable yet on Linux, ship a capability-gated disabled window state rather than silently dropping the product surface.

### Verify
- On supported Linux setups, projectM runs end-to-end.
- On unsupported setups, the UI degrades predictably and explicitly.

## PR 12: Library Browser Advanced Features And Remaining Browser Parity
**Goal**: Bring the browser beyond local-core usefulness.

### Tasks
- All `ModernBrowserSource` cases must be handled (moved to `NullPlayerCore` by PR 2):
  - `.local`
  - `.plex(serverId: String)`
  - `.subsonic(serverId: String)`
  - `.jellyfin(serverId: String)`
  - `.emby(serverId: String)`
  - `.radio`
- All `ModernBrowseMode` cases with raw values (moved to `NullPlayerCore` by PR 2):
  - `.artists = 0`, `.albums = 1`, `.plists = 3`, `.movies = 4`, `.shows = 5`, `.search = 6`, `.radio = 7`, `.history = 8`
- Port remaining browse modes and tabs explicitly:
  - Plists
  - Radio
  - Data/History
  - Movies, if Linux video browsing is in scope
  - Shows, if Linux video browsing is in scope
  - remote-source variants of Artists/Albums/Plists/Search
- Port mode-specific functions for each remaining tab:
  - Plists:
    - provider playlist listing
    - expand to tracks
    - play/enqueue actions
  - Radio:
    - station list
    - folder tree
    - add/edit/manage actions
    - radio-generation actions
    - ratings
  - Data/History:
    - play-history listing
    - mode-specific hosting/presentation
  - Movies:
    - movie listing
    - artwork/metadata columns or art-only behavior
    - play actions or explicit capability gate
  - Shows:
    - show/season/episode hierarchy
    - episode actions
    - artwork/metadata presentation
- Port advanced column configuration menu and persisted visible-column sets.
- Port art-only mode, visualizer overlay, and rating overlay.
- Port metadata editing panels:
  - track
  - album
  - video
  - auto-tag flows
- Port radio management UI:
  - add station
  - folders
  - defaults reset/add-missing
  - smart folder actions
- Port source-specific menus:
  - Plex libraries
  - Subsonic folders
  - Jellyfin libraries
  - Emby libraries
  - source selection
- Port remote context menus and play/enqueue flows.
- Port history/data hosting strategy without relying on AppKit-only hosting assumptions.
- Make an explicit call on Linux support for movie/show browsing if Linux video UI is still outside this phase.

### Verify
- Browser functionality matches the chosen Phase 3 scope explicitly rather than implicitly.
- Unsupported browser/provider features fail closed and visibly.

## PR 13: State Persistence, Menus, And App-Level Integration
**Goal**: Make the Linux UI feel like one product rather than seven disconnected windows.

### Tasks
- [x] **`AppState` is already cross-platform**: The `AppState` struct is defined in `Sources/NullPlayerCore/Models/AppState.swift` and is already part of `NullPlayerCore`. The Linux port reuses this struct directly.
  - **Gap: missing spectrum/waveform window fields.** `AppState` currently only tracks visibility and frames for 5 windows: main, playlist, equalizer, plexBrowser, projectM. It does NOT have `isSpectrumVisible`, `isWaveformVisible`, `spectrumWindowFrame`, or `waveformWindowFrame`. These must be added to `AppState` (with `decodeIfPresent` defaults for backward compatibility) before or alongside this PR.
  - **Capability-gated settings**: `AppState` stores `gaplessPlaybackEnabled` and `sweetFadeEnabled`, but the Linux GStreamer backend declares `supportsGaplessPlayback: false` and `supportsSweetFade: false`. The Linux state restore must either hide these settings in the UI or silently ignore them.
- [x] Create a `LinuxAppStateManager` (in `Sources/NullPlayerLinuxUI/App/LinuxAppStateManager.swift`) as the Linux equivalent of the macOS `AppStateManager`. It should:
  - Use the same `AppState` struct for serialization
  - Persist to `~/.config/nullplayer/appstate.json` following XDG Base Directory conventions (`$XDG_CONFIG_HOME/nullplayer/` if set, else `~/.config/nullplayer/`)
  - Implement the same two-phase restoration pattern as macOS: settings first (`restoreSettingsState`), then playlist (`restorePlaylistState`)
  - macOS uses `UserDefaults` + `NSCoding`; Linux should use `JSONEncoder`/`JSONDecoder` with the `AppState` struct (which is `Codable`)
  - Simple per-key preferences (like `ModernBrowserSortOption.save()`/`.load()`) that use `UserDefaults` on macOS will need a Linux-safe wrapper — either Foundation's `UserDefaults` on Linux (available but behavior may differ) or a simple JSON-backed key-value store at the same XDG path
- Persist and restore frames/visibility/shade/fullscreen state where supported.
- Persist browser state:
  - source
  - mode/tab
  - sort
  - columns
  - art-only state if retained
- Persist visualization state:
  - spectrum mode/style options
  - projectM defaults/cycle options
- Persist waveform display options.
- Persist EQ auto/preset-related UI state if appropriate.
- Add Linux app menus/global commands as needed for parity with window-local actions.
- Audit every menu/dialog flow for Linux-safe implementation.
- Ensure main-window visibility indicators stay correct through app restart and state restore.

### Verify
- Linux app relaunches into a coherent prior UI state.
- Menu and dialog flows work consistently across windows.

## PR 14: Testing, Packaging, And Final QA
**Goal**: Make the Linux UI port maintainable.

### Tasks
- Add build coverage for the Linux UI target in CI.
- Add presenter/view-model tests for cross-platform UI state.
- Add focused integration tests for:
  - transport state reflected in main window
  - playlist mutations reflected in playlist window
  - library actions enqueue/play correctly
  - EQ state wiring
  - window visibility and persistence
- Add smoke coverage for multi-window creation/show/hide/restore.
- Document Linux runtime dependencies for the chosen toolkit and any graphics/visualization stacks.
- Document contributor setup and known capability gates.
- Run manual QA across all seven windows.

### Verify
- Linux UI build is repeatable.
- The seven-window product shape is documented, testable, and maintainable.

## Explicit Decisions Still Needed
- Toolkit decision: raw GTK 4 bindings vs higher-level GTK-backed layer.
- Whether `btn_sk` becomes a Linux appearance menu, is hidden, or is deferred entirely.
- Whether local Movies/Shows are Phase 3 scope when Linux video playback UI is outside the seven-window set.
- Whether waveform shade mode is a real Linux requirement or remains unsupported.
- Whether `vis_classic` is supported in the Linux spectrum window or capability-gated.
- Whether projectM is fully enabled on Linux in this phase or shipped behind a capability gate first.
- How much remote-source browser parity belongs in Phase 3 versus a later phase.
