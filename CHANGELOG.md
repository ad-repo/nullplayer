# Changelog

## v0.16.2
- **Fix: Plex streaming tracks never load after restart** — `PlexManager.serverClient` was always nil at state-restoration time because Plex connects asynchronously; now polls via `waitForPlexClient()` every 250ms for up to 15s, and shows placeholder metadata immediately while the URL loads
- **Plex Radio History** — records, filters, and displays recently played Plex Radio tracks in a dedicated history panel; accessible from the Plex Radio context menu
- **CPU optimizations** — three targeted improvements: FFT guard (skips spectrum analysis when the visualization window is hidden), occlusion stops (pauses Metal renders when a window is occluded or miniaturized), lazy cast discovery (defers UPnP scanning until first needed)
- **Add Folder picker**: prevent drilling into subdirectories (only top-level folder selection allowed)
- Fix: move `#` alphabet letter below column headers and correct scroll position calculation in library browser

## v0.16.1 — Playlist CPU fix
- Replace 30Hz `displayTimer` with event-driven updates: track changes now go through the existing `handleTrackDidChange` notification instead of polling
- Replace timer-driven marquee scrolling in modern playlist with a `ModernMarqueeLayer` sublayer — text pre-rendered to a `CGImage` once, then scrolled by moving the layer frame (no `draw()` invocations at 30Hz)
- CPU during playback drops from ~15–20% → <5%

## v0.16.0 — Skins, ratings, edit panels
### Modern UI Polish
- Title bar height increased from 14 → 18 base units for better usability
- Rounded corners on undocked modern UI windows
- 4px gap between panels and title bar
- Center stack gap collapses when sub-windows are hidden (EQ, Playlist, Spectrum)
- Explicit text color definitions added to all bundled skin.json files

### Local Library
- **Metadata edit panels** — in-app editing for tracks, albums, and video files
- **Album and artist ratings** (★–★★★★★) stored in MediaLibrary with dedicated star columns in the browser
- Fix: resize hidden sub-windows correctly when toggling double-size mode

### Sonos Casting
- Auto-skip Sonos-incompatible lossless formats during cast playback
- Skip WavPack (`.wv`) files during Sonos casting
- Fix: `castTrackDidFinish` skip loops now use `allowUnknownSampleRate: true` (scan functions run before sample rate is fetched; strict mode was silently skipping all nil-SR FLAC tracks)

### Bundled Skins
- New: **Bubblegum Retro** with pixel-art title character sprites
- New: **Sakura Minimal** with pixel-art title character sprites

### Spectrum Analyzer
- Improved dynamic range and level consistency across sources

## v0.15.0 — Library browser, Emby, new skins
### Emby Integration
- Full Emby media server support: browse artists, albums, tracks, playlists, movies, and TV shows
- Audio streaming with `StreamingAudioPlayer`; playback scrobbling via `EmbyPlaybackReporter`
- Video playback reporting via `EmbyVideoPlaybackReporter` (90% scrobble threshold, periodic timeline updates)
- Video casting to Chromecast and DLNA devices
- Server credentials stored in Keychain

### Library Browser
- Removed Tracks tab from both modern and classic library browsers
- Single-click album rows to expand them inline across all tabs
- Search wired up for Jellyfin, Subsonic, and Emby
- Clicking an artist in search results navigates to the Artists tab
- Library selectors added for Jellyfin and Navidrome/Subsonic — switch music libraries or folders from the browser status bar
- Subsonic music folder selection (`getMusicFolders`); folder ID passed to `getArtists` and `getAlbumList2`; persisted via UserDefaults
- Server and library names scroll when they overflow the status bar
- Title column is now resizable

### Local Video Library
- "Add Video Files..." in local library `+ADD` menu
- Video file types added to library extension support list

### Skins
- New modern skins: **Arctic Minimal**, **Emerald Forge**, **Industrial Signal**
- Redesigned Skulls skin transport buttons with amber CG icons
- Subtle recessed panel depth added to time display and spectrum analyzer
- Uniform 6px left margin alignment in modern UI

### Spectrum Analyzer (Enhanced mode)
- Eliminated black grid artifact, noisy "off" cells, seams, and sub-pixel midline
- Off cells now show dim ambient LED glow instead of black
- Cells fill full viewport width; dense grid with brighter active cells

### Window & UI Fixes
- Double Size mode available in Classic UI (requires restart, consistent with modern/classic switch)
- Auto-hide title bars when docked in modern UI
- Fix drag-to-undock for playlist and spectrum in hidden titlebar mode
- Volume/seek slider thumb constrained within track bounds
- Fix shade mode text inconsistency for ProjectM and Spectrum windows
- Classic skin title bars preserve TITLEBAR.BMP / PLEDIT.BMP sprites without text overlays
- Eliminated noisy healthcheck log spam from LocalMediaServer

## v0.14.0 — Jellyfin, modern skin title text, Sonos resilience
### Jellyfin Integration
- Full music library: browse artists, albums, tracks, genres; search across songs, albums, artists
- Audio streaming via `StreamingAudioPlayer`; scrobbling via `JellyfinPlaybackReporter`
- Auto EQ genre fetch — when a track lacks embedded genre metadata, fetches from Jellyfin API to apply the correct Auto EQ preset
- Artwork loading from Jellyfin image API (fixed: `imageTag` is optional, not required)
- Video content: browse and play movies and TV shows (season/episode hierarchy)
- Video playback reporting via `JellyfinVideoPlaybackReporter`
- Video casting to Chromecast and DLNA
- Video library selector: context menu picks which Jellyfin video library to browse; auto-detects movies vs. TV shows via `collectionType`
- Non-video file filtering: `MediaTypes=Video` server-side filter plus client-side extension check

### Modern Skin Title Text Engine
- Three-tier rendering: pre-rendered full title image → character sprites → system font fallback
- Character sprites use `title_upper_` / `title_lower_` prefixes (avoids macOS case-insensitive filesystem collisions)
- Pixel-art nearest-neighbor interpolation for sharp sprite scaling
- Runtime color tinting and decoration sprites
- New: **Skulls** bundled skin (lo-fi stereo receiver aesthetic) with image-based title reference
- Updated NeonWave skin with sprite-based title text

### Seamless Docked Window Borders
- Border blend configurable per skin via `skin.json` (0.0–1.0 value)

### Sonos Resilience
- 5-second playback polling via `GetTransportInfo` + `GetPositionInfo` to detect external pause/stop and sync position
- Auto content-type detection (`CastManager.detectAudioContentType`) — never hardcodes `audio/mpeg`
- HEAD request handling in LocalMediaServer (Sonos sends HEAD before GET)
- UPnP Error 701 ("Transition Not Available") retry: poll transport state until ready before retrying
- Sleep/wake recovery
- Multi-room coordinator transfer: when unchecking the current coordinator, `transferSonosCast()` migrates the session and re-joins remaining rooms
- Connection Security detection: shows specific error on 401/403 (Sonos firmware 85.0+ setting)
- `x-rincon-mp3radio://` URI scheme for MP3 internet radio streams (uses Sonos internal radio buffering)
- Content-Length buffering for MP3/OGG streams (chunked encoding only works for WAV/FLAC)

### Remember State v2
- Track seek position restored on restart
- Playlist ordering preserved across restarts (not just track list)
- Radio tracks saved via `SavedTrack.radioURL`
- New state fields: double size, skin selection, output device, browse mode
- Streaming tracks (Plex/Subsonic/Jellyfin/Emby) restored as placeholder `Track` objects, then replaced asynchronously via `engine.replaceTrack(at:with:)`

### Other Changes
- UI mode switch (Modern ↔ Classic) now shows Restart / Cancel dialog; Cancel reverts the preference
- EQ: double-click any band to reset all bands to flat
- Crossfade: stray completion handler suppression; proper `.dataPlayedBack` callback prevents premature track advance
- Library browser: leading articles ("The", "A", "An") ignored in sort order and alphabet navigation
- Fix: `EastSonosCompatibleTrack` scan functions use `allowUnknownSampleRate: true`

## v0.13.1
- Classic skins: use original `TITLEBAR.BMP` for main window; remove NullPlayer logo overlay
- Classic playlist: system font fallback for non-Latin characters (CJK, Arabic, etc.)
- Fix: star rating position in classic art mode (was overlapping VIS/ART/F5 buttons)
- Fix: `playNow()` and `insertTracksAfterCurrent()` correctly route to the active cast device when casting
- "Play and Replace Queue" context menu option in library browsers
- `dataColor` palette key for yellow glow on data fields in classic art mode

## v0.13.0 — Modern Skin Engine
### Modern Skin Engine
- New `ModernSkin/` system completely independent of classic `.wsz` skin loading
- Skin configuration via `skin.json`: colors, fonts, glow effects, layout options, scale factor
- 9 configurable font size keys for fine-grained typography control
- EQ colors, marquee behavior, glow intensity, and scale factor all configurable per skin
- Bundled skin: **NeonWave** (neon glow aesthetic)

### Modern Windows
- Modern Main Window with volume slider, mini spectrum analyzer, and toggle button row
- Modern Spectrum Analyzer window with skin-aware styling
- Modern Playlist window with album art background
- Modern EQ window with glowing neon sliders and presets
- Modern ProjectM visualization window
- Modern Library Browser with resizable/configurable columns

### Display Modes
- **Double Size (2x)** mode — toggle via 2X button or context menu; live resize in modern mode
- **Hide Title Bars** — toggle via HT button or context menu; top border line preserved; windows remain draggable
- Both modes restricted to modern UI; classic mode unaffected

### BPM Detection
- Real-time BPM detection using libaubio
- BPM display in main window with double-click multiplier cycling (1x → 2x → 0.5x)
- Default multiplier set to 0.5x for smoother visualizations
- Disabled in classic mode to reduce CPU usage

### Ratings
- Star ratings for Navidrome/Subsonic tracks (synced to server)
- Star ratings for local files (stored in MediaLibrary database)

### Queue Management
- "Play Now" preserves current playlist instead of replacing it
- Playlist-specific context menus with distinct queue operations

### Library Browser Improvements
- Resizable columns with drag handles; configurable column visibility
- Click behavior matches playlist; scroll direction matches system natural scrolling
- Sonic analysis radio stations visible in browser

### Window Management
- Coordinated minimize: docked windows minimize together into a single Dock icon
- Fix: playlist crash during window resize animations (monitor disconnect + double-size)

### Performance
- CPU reduced from ~50% → ~7% idle with modern skin + spectrum open

### Build
- DMG bundles all transitive Homebrew dylib dependencies (libsndfile, libFLAC, etc.)
- Bundled `NullPlayer-Silver.wsz` as default classic skin; other official skins in `dist/Skins/`

## v0.12.0 — Spectrum modes, NullPlayer branding
### Spectrum Analyzer Modes
- **Fire mode**: GPU flame simulation with audio-reactive tongues; 4 color styles (Inferno, Aurora, Electric, Ocean); 2 intensity presets (Mellow/Intense)
- **JWST mode**: deep space flythrough with 3D perspective star field; JWST diffraction flares as frequency indicators; rare giant flare events on bass peaks
- **Matrix mode**: falling digital rain visualization
- **Lightning mode**: GPU procedural storm visualization
- **Ultra mode**: smoothed seamless gradient with perceptual gamma, warm color trails, physics-based bouncing peaks, reflection effect
- **Winamp mode** improvements: floating peak indicators, discrete color bands with 3D shading, segmented LED gaps
- **Enhanced mode** improvements: warm amber fade trails, gravity-bouncing peaks, anti-aliased rounded corners
- Double-click the spectrum window to cycle through all modes
- Fire mode also available in the main window visualization area (double-click to cycle)
- Spectrum and flame visualizations pause and stop with playback state

### MilkDrop / ProjectM
- User-controllable **Audio Sensitivity** (PCM gain: Low 0.5x to Max 3.0x) via context menu
- User-controllable **Beat Sensitivity** (Low 0.5–2.0) via context menu

### App
- Renamed from AdAmp to **NullPlayer** (IP compliance); all internal references updated
- New app icon and main window logo
- Removed playlist bottom control bar; replaced with thin border
- Fix: window stack spawn fills existing gaps instead of always appending to bottom
- Fix: snap-to-default consolidates all visible windows without gaps
- Removed scrollbar widgets from playlist and library browser
- Unified title bar graphics and font sizes across all windows
- Enlarged window close button hit areas for easier clicking

### Bug Fixes
- Fix: local file track advancement using `.dataPlayedBack` callback (prevents premature track advance and UI desync)
- Fix: library browser and MilkDrop opening on the wrong side near screen edges

## v0.11.0 — Plex artist expand reliability
- Robust `parentKey` extraction handling multiple Plex server URL formats (`/library/metadata/ID`, `/library/metadata/ID/children`, bare IDs)
- Remove artist/album from expanded set on fetch failure so users can retry by clicking again
- Don't cache empty album results when `albumCount > 0` (allows retry on transient failures or compilation albums)
- NSLog diagnostics for all expand operations

## v0.10.0 — Spectrum overhaul + stability
### Spectrum Analyzer
- Local playback FFT upgraded 512 → 2048 points (matches streaming path)
- **Volume-independent display**: spectrum bars and MilkDrop show consistent levels regardless of volume setting
- Pink noise fix: proper bandwidth scaling (√) for flat display
- Smoothed reference levels prevent pulsing artifacts in adaptive normalization mode
- Accurate mode now uses full display height for better dynamic range
- Spectrum Analyzer submenu in context menu (quality, responsiveness, normalization modes)

### Stability
- Memory leak fix: Metal drawable pool limited to 3 (prevents unbounded growth)
- CVDisplayLink use-after-free crash fix (weak reference wrapper)
- Audio engine race conditions fixed: duplicate timers, concurrent `loadTrack`, skip guards
- Choppy animation fix: disabled display sync to allow frame dropping

### Playlist & UI
- Auto-highlight and auto-scroll to currently playing track in playlist
- Multi-disc album sorting: disc number first, then track number
- Video player: draggable resize from all edges and corners

## v0.9.19 — CPU optimizations + Ultra spectrum
- Spectrum display link auto-pauses after 1s of silence; resumes automatically when audio data arrives
- Marquee timer: 15Hz → 8Hz; auto-stops when nothing needs scrolling, restarts on track/metadata changes
- Visualization windows stop their display links on `orderOut()` (not just on close)
- **Ultra quality spectrum mode**: 84 bars, rainbow frequency-based colors, 3D cylinder lighting, specular highlights; 84 bars (up from 42)
- Spectrum fullscreen support (press F or use context menu; Escape to exit)
- Supports up to 120Hz on ProMotion displays
- GPU-accelerated **marquee via CALayer + CABasicAnimation** — text pre-rendered to bitmap; no more `draw()` calls for scrolling
- Playlist uses **bitmap font** from skin's `TEXT.BMP`; selected track text renders white
- Playlist: auto-selects currently playing track on open
- CPU reduced from ~40% → ~3–5% when casting with no visualization windows open

## v0.9.17
- Fix spectrum analyzer "pumping" — slow down adaptive normalization blend factors for stable levels

## v0.9.16
- Smoother spectrum bar decay (factor 0.55 → 0.90)

## v0.9.15
- Fix Metal shader not loading in app bundle after DMG install

## v0.9.13 — Metal Spectrum Analyzer window
- New standalone **Metal GPU-accelerated Spectrum Analyzer** window (42 bars, 60Hz via CVDisplayLink)
- Two quality modes: Winamp (skin palette colors) and Enhanced (LED matrix with peaks and fade trails)
- Docks with Main/EQ/Playlist stack; supports shade mode; state persists across restarts
- Fix: stable adaptive normalization (no more pumping)
- Fix: smoother bar decay

## v0.9.12
- **CPU optimization**: idle usage ~50% → ~10%
- MilkDrop 30fps/60fps quality toggle in context menu

## v0.9.11
- Fix artwork crash in library browser during rapid track changes

## v0.9.10
- Fix Navidrome server dialog not appearing
- Fix radio auto-reconnect on background thread disconnects
- Plex Radio: artwork display and "View Art" context menu item

## v0.9.9 — Internet Radio
- **Internet radio (Shoutcast/Icecast)**: auto-reconnect with exponential backoff; ICY metadata displayed in marquee
- Import stations from `.pls` / `.m3u` / `.m3u8` URLs or local files
- Cast radio streams to Sonos (`x-rincon-mp3radio://` for MP3)
- Fix: Subsonic/Navidrome Sonos casting via LocalMediaServer proxy (handles URLs with auth query params and localhost-bound servers)

## v0.9.8
- Fix ProjectM OpenGL context race condition crash on window resize
- Fix shuffle casting: continue to next random track instead of stopping after current
- Fix version display in About screen during debug builds

## v0.9.3–v0.9.4 — ProjectM stability
- Fix ProjectM SIGSEGV crash (NULL texture accessed on CVDisplayLink thread)
- Non-blocking lock in `renderFrame()`; 3-frame delay after preset load to let GPU state settle
- Disable soft cuts and auto preset-switching by default

## v0.9.0 — M4A error handling
- Detect M4A streaming failures (moov atom at end of file; common with Plex transcoding)
- Display error in marquee; auto-advance to next track

## v1.0 — Initial stable release
- **File associations**: double-clicking audio files in Finder opens the app
- **State restoration**: Plex/Subsonic streaming tracks, MilkDrop preset selection and fullscreen state
- Track load failure: error shown in marquee; playback stops cleanly
- Always on Top: dialog windows appear above the main window
- Input validation: unsupported file extensions rejected immediately with clear feedback
