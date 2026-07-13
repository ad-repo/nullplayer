# Agent Guide

## Quick Start

```bash
./scripts/bootstrap.sh      # Download frameworks (first time)
./scripts/kill_build_run.sh # Build and run
./scripts/build_dmg.sh      # Build distributable DMG
./scripts/build_mas.sh      # Build signed Mac App Store .pkg (needs MAS_* env vars)
swift test                  # Run unit tests
```

See `docs/development-workflow.md` for build details, log monitoring, and versioning.

## Documentation

Skills contain detailed technical documentation (`skills/` directory):

- **ui-guide**: Coordinate systems, scaling, skin rendering, window docking, Hide Title Bars, UI Size
- **audio-system**: Audio pipelines, EQ, spectrum analysis
- **modern-skin-guide**: Modern skin engine and creation
- **user-guide**: Features, menus, keyboard shortcuts
- **plex-integration**, **jellyfin-integration**, **subsonic-integration**, **emby-integration**: Server integrations
- **sonos-casting**, **chromecast-casting**: Casting protocols and debugging
- **stream-ripper**: Rip a URL to FLAC/MP3/MP4 via yt-dlp — format selection, tagging, cover art, .cue from chapters, activity band
- **youtube-source**: YouTube channel uploads in the Radio tab — browse channels, download audio (FLAC / MP3) ad-free, store in a user folder, and play/cast locally
- **cue-sheets**: .cue playback — direct-play virtual split (one backing file → N gapless playlist rows) + library physical split-on-import (ffmpeg per-track FLACs, off by default)
- **radio-streaming**: Internet radio + library radio support
- **visualizations**: Index/router across all visualization sub-skills (comparison table, when-to-use)
- **main-window-visualization**: Main window's 76×16 vis area — modes, switching, settings
- **spectrum-analyzer-window**: Dedicated 84-bar spectrum window — docking, geometry, analyzer curve, vis_classic waveform demand
- **audio-analysis-window**: Friture-style multi-pane Audio Analysis window — Scope/Levels/Spectrogram panes, stereo PCM path, per-pane consumer gating, AudioAnalysisDSP module
- **peppymeter**: Skinnable analog VU meter window (PeppyMeter port) — meters.txt geometry, CoreGraphics needle/bar compositor, stereo-tap level model, bundled GPL templates
- **flow**: Network throughput meter window — single-height center-stack docking, download/upload view switching, interface selection, classic/modern Flow controllers
- **gpu-vis-modes**: Per-mode shader internals (Fire/JWST/Lightning/Matrix/Snow/EKG) shared by both windows
- **album-art-visualizer**: Library Browser ART-mode Core Image effects
- **projectm-milkdrop**: ProjectM/MilkDrop preset engine + drag-suspend behavior
- **met-museum-visualizer**: Met Museum slideshow engine, API client, image cache
- **metal-gotchas**: Command encoder ordering, render-to-texture y-flip, spectrum coalescing
- **geiss-port**: Geiss Winamp-visualization port — architecture, ABI, configuration levers
- **tripex-port**: Tripex (ben-marsh/tripex) D3D9→OpenGL port — architecture, C ABI, RendererOpenGL, audio ring buffer
- **testing**: UI testing workflows
- **non-retina-fixes**: Display artifact fixes
- **local-library**: SQLite schema, scan pipeline, NAS responsiveness, display-layer query patterns
- **cli**: Headless CLI mode — flags, keyboard controls, source resolution, LibraryFilter/ConnectionState gotchas

## Architecture

```
Sources/NullPlayer/
├── App/              # AppDelegate, WindowManager, menus, MainWindowProviding protocol
├── Audio/            # AudioEngine, StreamingAudioPlayer, EQ
├── Casting/          # Chromecast, Sonos, DLNA casting
├── StreamRipper/     # Rip a URL to FLAC/MP3/MP4 via yt-dlp (tagging, cover art, .cue)
├── Radio/            # Internet radio (stations, metadata fallback, ratings, folders)
├── Skin/             # Classic .wsz skin loading and rendering
├── ModernSkin/       # Modern skin engine (independent of classic system)
├── Windows/          # All window views (MainWindow, ModernMainWindow, ModernSpectrum, ModernPlaylist, ModernEQ, ModernProjectM, ModernLibraryBrowser, PeppyMeter, ModernPeppyMeter, Playlist, EQ, etc.)
├── Plex/             # Plex server integration
├── Subsonic/         # Navidrome/Subsonic server integration
├── Jellyfin/         # Jellyfin media server integration
├── Emby/             # Emby media server integration
├── Visualization/    # ProjectM wrapper, Metal spectrum analyzer, vis_classic bridge/core integration
├── PeppyMeter/       # Analog VU meter engine (meters.txt parser, CoreGraphics compositor, level model)
├── Waveform/         # Shared waveform models, cache service, drawing, and stream accumulation
└── Models/           # Track, Playlist, MediaLibrary
```

## Key Source Files

| Area | Files |
|------|-------|
| Skin (Classic) | `Skin/SkinElements.swift`, `Skin/SkinRenderer.swift`, `Skin/SkinLoader.swift` |
| Skin (Modern) | `ModernSkin/ModernSkinEngine.swift`, `ModernSkin/ModernSkinConfig.swift`, `ModernSkin/ModernSkinRenderer.swift`, `ModernSkin/ModernSkinLoader.swift`, `ModernSkin/ModernSkinElements.swift` |
| Audio | `Audio/AudioEngine.swift`, `Audio/StreamingAudioPlayer.swift` |
| Windows | `Windows/MainWindow/`, `Windows/ModernMainWindow/`, `Windows/ModernSpectrum/`, `Windows/ModernPlaylist/`, `Windows/ModernWaveform/`, `Windows/ModernEQ/`, `Windows/ModernProjectM/`, `Windows/ModernLibraryBrowser/` |
| Visualization | `Visualization/SpectrumAnalyzerView.swift`, `Visualization/VisClassicBridge.swift`, `Visualization/ProjectMWrapper.swift`, `Visualization/*.metal`, `Sources/CVisClassicCore/` |
| PeppyMeter | `PeppyMeter/PeppyMeterConfig.swift`, `PeppyMeter/PeppyMeterRenderer.swift`, `PeppyMeter/PeppyMeterLibrary.swift`, `PeppyMeter/PeppyMeterPresenter.swift`, `Windows/PeppyMeter/`, `Windows/ModernPeppyMeter/` |
| Flow | `Utilities/NetworkThroughputMonitor.swift`, `Windows/NetworkMonitor/`, `Windows/ModernNetworkMonitor/` |
| Waveform | `Waveform/WaveformCacheService.swift`, `Waveform/BaseWaveformView.swift` |
| App | `App/WindowManager.swift`, `App/AppStateManager.swift`, `App/ContextMenuBuilder.swift` |
| Local Library | `Data/Models/MediaLibrary.swift`, `Utilities/LocalFileDiscovery.swift` |

## Common Tasks

### Adding a menu item
- Context menus: `ContextMenuBuilder.swift`
- Main menu bar: `AppDelegate.swift`

### Adding a new window
1. Create folder in `Windows/`
2. Add WindowController + View
3. Register in `WindowManager.swift`
4. Add a provider protocol in `App/` if it has shared classic/modern behavior

### Modifying skin rendering (classic)
1. Check sprite coordinates in `SkinElements.swift`
2. Rendering logic in `SkinRenderer.swift`
3. Test with multiple skins — they vary in implementation

### Modifying modern skin rendering
1. Element definitions: `ModernSkinElements.swift`; rendering: `ModernSkinRenderer.swift`
2. See modern-skin-guide skill for full docs

## Before Making UI Changes

1. Read ui-guide skill
2. Check `SkinElements.swift` for sprite coordinates
3. Test at different window sizes (scaling bugs) and multiple skins

## Testing

```bash
swift test  # Unit tests (models, parsers, utilities)
```

Manual QA for UI/playback changes: local file playback, Plex/Subsonic/Jellyfin/Emby streaming, internet radio, multiple skins, window snapping/docking, visualizations, Sonos casting (multi-room), video casting (Chromecast/DLNA).

## Gotchas

- **Modern skin system is completely independent**: Files in `ModernSkin/`, `Windows/ModernMainWindow/`, `Windows/ModernSpectrum/`, `Windows/ModernPlaylist/`, `Windows/ModernEQ/`, `Windows/ModernProjectM/`, `Windows/ModernLibraryBrowser/`, and `Windows/ModernPeppyMeter/` must NEVER import or reference anything from `Skin/` or `Windows/MainWindow/`. Coupling points: `AppDelegate` (mode selection), `WindowManager` (via provider protocols), and shared infrastructure (`AudioEngine`, `Track`, `PlaybackState`).

- **UI mode switching is live (no restart)**: `modernUIEnabled` UserDefaults preference selects which `MainWindowProviding` implementation `WindowManager` creates. `setClassicMode()`/`setModernMode()` call `WindowManager.reloadUI(toModernUI:)`, which tears down only the mode-dependent window layer (`teardownModeDependentWindows()`), flips the flag, prepares the target-mode runtime (`prepareUIRuntime`), reprograms the shared EQ nodes, rebuilds the menu, and recreates the windows. `AudioEngine` is owned by `WindowManager` (not a window), so playback/casting/playlist/seek survive untouched and audio state is deliberately not snapshotted. The mode-independent `VideoPlayerWindowController` is preserved across the switch. Skin-driven mode switches (`selectClassicSkin`/`selectModernSkin`/`loadDefaultClassicSkin`) are also live: they load the target skin into `currentSkin` (classic) or set `modernSkinName` (modern), then call `reloadUI`. Classic UI Size changes are also live now — `setUIScaleLevel(_:)` updates `uiScaleLevel` and `applyDoubleSize(previousScale:)` resizes in place (ending with a forced `forceRedrawTree` repaint so layer-backed classic views don't leave a stale "ghost"). `reloadUI` collapses `uiScaleLevel` to 1x before a mode switch and re-applies the captured level after, so nothing in the UI requires a relaunch.

- **Mode-specific features must be guarded at all layers**: When a feature only applies to one UI mode, enforce it in three places: (1) menu/UI check (`if wm.isModernUIEnabled`), (2) property getter returns safe default in wrong mode, (3) action function has `guard isModernUIEnabled else { return }`.

- **Remember State On Quit**: `AppStateManager` saves/restores session state (v2) for window visibility/layout, audio/EQ state, and playlist contents. It intentionally does not save or restore the selected/current track, seek position, or playing state, so launch starts paused with no track loaded solely because state was restored. Two-phase restoration: settings first (`restoreSettingsState`), then playlist (`restorePlaylistState`). Streaming tracks are loaded as placeholder `Track` objects then replaced asynchronously via `engine.replaceTrack(at:with:)`. When adding new state: durable preferences stay in `UserDefaults`; quit-session state goes in the `AppState` struct with `decodeIfPresent` defaults. Do not move every `UserDefaults` key into AppState. If a durable preference can trap users in a hard-to-recover state, expose a reset path instead. `Reset Saved State...` clears only the saved AppState blob; visualization preference resets are centralized in `VisualizationPreferences`.

- **Library browser expand tasks must use `Task.detached`**: In both `ModernLibraryBrowserView` and classic `PlexBrowserView`, expand tasks for Jellyfin, Emby, and Subsonic must use `Task.detached { @MainActor ... }` instead of `Task { @MainActor ... }`. Regular `Task {}` can inherit cancellation state from the main actor context.

- **vis_classic state is window-scoped**: Main window and spectrum window keep independent profile, fit, and transparent-background settings. Use `VisClassicBridge.PreferenceScope` and scoped keys (e.g. `visClassicLastProfileName.mainWindow`). Do not use shared keys.

- **Modern skin visualization defaults are first-use defaults on launch**: `ModernSkinEngine.configureSkinDependencies(preservePersistedProfiles: true)` must not overwrite existing visualization `UserDefaults` values. Skin config may seed missing mode/style/profile keys on launch, but explicit skin changes and skin reset still apply the selected skin's defaults. Use `ModernSkinEngine.shouldApplyDefault(...)` for any new skin-driven visualization key.

- **Streaming audio**: Uses `AudioStreaming` library, different from local `AVAudioEngine`.

- **Local file completion handler**: Must use `scheduleFile(_:at:completionCallbackType:completionHandler:)` with `.dataPlayedBack` — NOT the deprecated 3-parameter form which fires before audio finishes playing.

- **Swift Data slicing pitfall**: When you slice a `Data`, it maintains original indices. Always use `data.startIndex` explicitly, never `data[0]` or `data[4..<n]` on a slice.

- **Metal command encoders**: Guard the pipeline BEFORE creating an encoder — if pipeline is nil after encoder creation, the command buffer is left in an invalid state. See visualizations skill for details.

- **NSTextField background**: Setting `backgroundColor` has no effect unless `drawsBackground = true` is also set.

- **No Spotify/Apple/Amazon**: These integrations are explicitly not accepted.

- **Skin coordinates**: Skin sprites use top-left origin; macOS uses bottom-left.
