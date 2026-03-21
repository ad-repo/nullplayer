# Changelog

## 0.18.0

### CLI Mode

- **Headless playback** — NullPlayer can now run without a UI via `--cli` flag, enabling scriptable playback from the terminal.
- **Full keyboard control** — play/pause, skip, seek, volume, shuffle, repeat, and quit all work from the terminal in CLI mode.
- **Auto-exit on queue end** — the process exits automatically when the queue finishes playing; guarded by a `hasStartedPlaying` flag to prevent premature exit during async startup.
- **Source resolution** — CLI mode resolves the same library sources (local files, Plex, Subsonic, Jellyfin, Emby) as the UI.

### Window System

- **Window layout lock** — a new lock mode prevents all windows from being moved or resized until unlocked, useful for fixed desktop setups.
- **Large UI improvements** — Large UI is now 1.5× scale with corrected text scaling and waveform scaling.
- **Minimize All Windows** — a "Minimize All Windows" item is now available in the Windows menu.
- **Stretch + session restore for spectrum and playlist** — the spectrum and playlist windows can now be freely resized horizontally, and their last-set size is restored on reopen.
- **Active window stays on top during bring-to-front** — the currently active window is no longer pushed behind peers when bringing a group to the front.
- **Library window group drag** — the library window now correctly activates and participates in connected-window group drags.

### ProjectM

- **Preset star ratings** — ProjectM presets can be rated 1–5 stars directly from the visualization overlay. Ratings persist across sessions.
- **Rating overlay** — a five-star overlay appears on mouse hover in ProjectM; Delete/Backspace clears the rating for the current preset.
- **Persistent default preset** — a preset can be set as the default and will be loaded on every launch.
- **Presets menu renamed** — the ProjectM presets menu is renamed for clarity, and preset list entries now show gold stars for rated presets.

### Visualizations

- **Art mode effect picker** — a grouped effect picker is now available in both the modern and classic art mode context menus, with a "Set as Default" option to persist the preferred effect across sessions.
- **Library and ProjectM window highlights** — the Library Browser and ProjectM windows now show a connected-window highlight when docked, matching the behavior of other windows.
- **Media controls type fix** — `MPNowPlayingInfoPropertyMediaType` is now correctly set to audio, fixing incorrect type metadata in the system media controls overlay.

### Library Browser

- **Rating column** — a rating column with gold stars is now shown in the library track list and in art-only mode, for all connected sources (local, Plex, Subsonic, Jellyfin, Emby). The column appears as the first column in the artist view.
- **Live rating updates** — ratings changed via the context menu now immediately update in the library list without requiring a refresh.
- **Horizontal scroll** — the library browser now supports horizontal scrolling when columns overflow the visible width.

### Local Library

- **Multi-artist support** — artist tags are now parsed into individual artist entries via a new `track_artists` join table (schema v3). Artists joined by `;` or `feat.`/`ft.` are stored as separate rows, enabling accurate per-artist browsing and radio.
- **Artist split fix** — `/` is no longer treated as a multi-artist separator, so artist names like `AC/DC` are no longer incorrectly split.
- **Album grouping** — album queries now group exclusively by `album_artist`, removing a fallback to the `artist` tag that caused incorrect album grouping.
- **Art window rating fix** — rating a track in art mode no longer moves the art window.
- **Occlusion cache on resize** — the window occlusion cache is now cleared on resize, fixing stale border segments after window size changes.

### Bug Fixes

- Fixed waveform squashing on horizontal resize in the classic skin
- Fixed waveform returning to 1× from Large UI
- Fixed waveform frame resetting on show/hide (now only resets on full close/reopen)
- Fixed waveform transparency not restoring after switching between classic and modern UI modes
- Fixed waveform pre-rendering for streaming service tracks
- Fixed classic main-window accepting edge resize gestures while docked
- Fixed window snapping re-entrancy recursion crash
- Fixed drag-mode group highlight activating incorrectly on startup
- Fixed classic ProjectM drag-detach leaving visualization paused
- Fixed intermittent playlist text disappearance in classic and modern views
- Fixed classic playlist titlebar tiling at stretched widths
- Fixed modern HT main-window stretching incorrectly when the display panel expands
- Honored `marqueeSize` from skin definition on skin reload; bumped modern UI marquee size
- Cleared stale cover art when switching to a track with no embedded artwork
- Removed output device selection from main window context menu
- Updated app icon

## 0.17.3

### Window System

- **Hold-to-group drag** — windows now use a time-based drag model instead of a distance threshold. A quick drag (< 400 ms hold) separates the grabbed window from its group; a longer hold (≥ 400 ms) moves all connected windows together.
- **Drag group preview** — connected peer windows show a subtle highlight overlay at mouseDown so it's clear which windows will move as a group before the drag begins.
- **Group screen-edge clamping** — when dragging a connected group, the entire group is clamped so no window is pushed off-screen at the top of the display.
- **ProjectM suspend during drag** — ProjectM rendering is suspended for the duration of a window drag to prevent WindowServer stalls on Apple Silicon.

## 0.17.2

### Waveform

- **Horizontal stretch** — the waveform window can now be resized horizontally to any width, not just the default fixed size.
- **Size preserved across sessions** — the waveform window no longer resets to its default size when reopened; the last user-set size is restored.

### Visualizations

- **Classic spectrum/waveform transparency** — the transparent-background setting for classic spectrum and waveform visualizations no longer resets to off on every launch.

## 0.17.1

### Local Library

- **Manage Folders window** — the watch-folder list is now a proper resizable window instead of an alert sheet, with full editing support on large network-volume libraries that previously appeared empty.
- **Manage Folders in context menu** — a direct "Manage Folders…" link is now available in the Local Library context menu.
- **Import pipeline optimized** — the scan-to-import handoff is restructured to reduce redundant work on large libraries and NAS volumes; scan signatures are no longer persisted for fast-track entries before enrichment completes.
- **NAS safety: skip cleanup on empty scan** — library cleanup is skipped when a NAS returns 0 files, preventing accidental removal of the entire library when the volume is temporarily unreachable.
- **Scanning animation fixes** — the progress animation no longer stops mid-import or persists after a scan is cancelled.
- **Library toolbar count** — the toolbar now shows the total track count instead of the paginated-page count.
- **Alphabet navigation** — letter-jump navigation now works across all pages in the local library, not just the first.
- **Library browser layering** — the library browser no longer appears behind main center-stack windows when they overlap.
- **Border gap fixed** — the classic library browser no longer shows a gap at the scan-animation border.
- **Context menu track count** — the library context menu now shows the correct track count; orphaned DB tracks that couldn't previously be cleared can now be removed.

### Async Local Track Transitions

- **Beachball-free auto-advance** — opening the next local file is now performed on a background I/O queue (`advanceToLocalTrackAsync`) so the main thread is never blocked during track transitions.
- **Beachball-free Sweet Fades** — crossfade file opens are also moved to the background I/O queue and guarded by a `crossfadeFileLoadToken` to prevent stale loads from arriving late.

### Visualizations

- **vis_classic crash fix** — resolved a data race between the CVDisplayLink callback thread and the main thread accessing the C++ vis_classic core.
- **Spectrum/waveform border fix** — the classic spectrum and waveform visualizations no longer occlude the left and right window borders.
- **Double Size crash fix** — toggling Double Size no longer crashes with a stack overflow; the animated window repositioning triggered infinite recursion in the docked-window movement loop.

## 0.17.0

### Window System

- **Hide Title Bars extended to all windows** — sub-windows (EQ, Playlist, Spectrum) now always hide their titlebars when docked. With Hide Title Bars enabled, all six windows hide titlebars unconditionally. Now defaults to on. The main window shrinks to fill the frame without a gap at the top.
- **Per-corner window sharpness** — corners automatically sharpen when a window is aligned against a screen edge or adjacent docked window, so the UI looks clean against boundaries without hard corners everywhere else.
- **XL mode** — the 2X double-size button is now XL at 1.5× scale, giving a more usable intermediate size. State buttons (shuffle, repeat, etc.) are reordered.
- **Docking fixes** — resolved nine window behavior issues: over-eager snapping, window shift on undock, stack collapse gaps, HT startup sizing, and more.
- **Menu bar parity** — key player actions are now available from the macOS menu bar with dynamically refreshed checkmarks/state (Windows, UI, Playback, Visuals, Libraries, Output).

### Modern Glass Skins

- **Skin-configurable window opacity** — `window.opacity` in skin.json sets background transparency per-window. Sub-windows can inherit or override independently.
- **Per-area opacity controls** — skins can set opacity independently for each region (display panel, playlist area, EQ bands, etc.) without affecting the rest of the window.
- **Text-only opacity** — a separate opacity knob for display text vs background glass, enabling frosted-glass aesthetics where the text reads clearly against a blurred background.
- **Spectrum opacity override** — the spectrum visualization layer has its own opacity control, independent of window opacity, so glass skins can keep the spectrum vivid.
- **Glass seam/darkening stability** — improved seam clearing and glass compositing so docked stacks stay visually consistent during moves and resizes.
- **New bundled skins** — NeonWave (default), SeaGlass, SmoothGlass, BloodGlass, and BananaParty are included.

### Waveform

- **Dockable waveform window** — a new Waveform window can be shown/hidden like other sub-windows and docks into the main stack.
- **Skin-configurable appearance** — waveform supports transparent background styles in modern skins and integrates with modern UI controls.

### Internet Radio

- **Folder organization** — stations can be organized into an expandable folder tree, visible in both the modern and classic library browsers. Folders persist across sessions. Smart reassignment moves a station's history and ratings when it changes folders.
- **Station ratings** — rate any internet radio station 1–10 directly in the library. Ratings are stored in a local SQLite database keyed by station URL and survive station edits.
- **Station artwork** — album art now loads for internet radio stations in both the modern and classic library browsers.
- **Station search** — search internet radio by metadata (name/genre/region/URL) with click-to-play results.
- **Expanded built-in catalog** — full SomaFM channel list added as defaults and auto-merged for existing users. Regional stations, jazz stations, verified Boston and scanner feeds included.
- **Grouped radio history** — playback histories from all sources (Plex, Subsonic, Jellyfin, Emby, local) are now consolidated under a single Radio History menu instead of scattered per-source.

### vis_classic

- **Exact mode** — vis_classic now runs as a faithful Winamp-replica visualizer with full FFT, bar, and color fidelity matching the original Nullsoft implementation.
- **Scoped profiles** — the main window and spectrum window each maintain their own independent vis_classic profile and fit-to-width setting. Changing one doesn't affect the other.
- **Skin visualization defaults** — skins can declare a default visualization mode and vis_classic profile in skin.json. The bundled classic skin defaults to the Purple Neon profile.
- **Bundled profile pack** — a full set of classic vis_classic profiles are included by default for quick switching.
- **Transparent background controls** — skins can default vis_classic transparency per-window and control its opacity independently for main vs spectrum windows.

### New Visualizations

- **Snow mode** — a new Metal spectrum shader that renders the frequency spectrum as falling snow particles.

### Classic Library UI

- **Local album and artist ratings** — albums and artists in your local library can now be rated directly in the classic browser. Ratings appear in both list view and art view.
- **Art mode interactions** — single-click an item in art view to rate it; double-click to cycle through its available artwork.
- **Date sorting parity** — the classic library browser now sorts by date and year using the same logic as the modern UI, consistently across all connected sources.
- **Replace Queue in library menus** — the "Replace Queue" action was missing from classic library context menus; it is now present alongside Play and Add to Queue.
- **Source radio parity** — source radio tabs in the classic browser now match the modern UI's behavior including F5 refresh support.
- **Watch folder manager** — manage watched local-library folders (rescan, reveal in Finder, remove with counts) from a dedicated dialog.

### Modern EQ

- **Preset buttons rework** — the preset button row now stretches to fill the available width, buttons are always enabled regardless of whether the EQ is active, and double-clicking a band's label resets that band to 0 dB.

### Other

- **Natural numeric sorting** — library tracks, albums, and artists sort in natural order (Track 2 before Track 10) consistently across all sources.
- **Modern skin bundles** — portable modern skins can be imported as `.nsz` (ZIP) bundles via UI → Modern → Load Skin....
- **Skin import persistence** — imported skins persist and remain selectable in future sessions.
- **Get More Skins** — a link to the skins directory is now in the Classic UI skin menu.
- **Credential storage hardened** — server credentials are stored in the data-protection keychain with a reduced attack surface. Dev builds use UserDefaults to avoid repeated Keychain authorization prompts during development.
- **Licensing/provenance** — added third-party license notices and waveform provenance documentation for distribution.

### Bug Fixes

- Fixed a streaming crossfade deadlock between the crossfade timer and `AVAudioEngine.stop()`
- Fixed streaming playlist restore by refreshing service-backed track URLs when needed (Plex/Subsonic/Jellyfin/Emby)
- Fixed audio engine state desync when handing off from cast back to local playback
- Fixed radio-to-local playback handoff leaving the engine in a stopped state
- Fixed library multi-remove hanging on large selections; added scoped local library clear actions
- Fixed classic library browser rendering artifacts (server bar transparency and incorrect text colors)
- Fixed volume slider not responding to arrow keys in the modern UI
- Fixed waveform window click-through during async waveform loading
- Reduced idle CPU and GPU usage across all spectrum visualization modes and during window dragging
- Improved Jellyfin loading resilience for large libraries (smaller page sizes, duplicate-page guards, background album warming)
