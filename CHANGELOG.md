# Changelog

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
