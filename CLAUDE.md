# Agent Guide

## Quick Start

```bash
./scripts/bootstrap.sh      # Download frameworks (first time)
./scripts/kill_build_run.sh # Build and run
./scripts/build_dmg.sh      # Build distributable DMG
```

## Distribution

The `build_dmg.sh` script creates a distributable DMG:

```bash
./scripts/build_dmg.sh           # Full release build + DMG
./scripts/build_dmg.sh --skip-build  # Use existing release build
```

Output:
- `dist/NullPlayer.app` - The application bundle
- `dist/NullPlayer-X.Y.dmg` - The distributable DMG with Applications symlink

The script:
1. Builds a release binary (`swift build -c release`)
2. Creates proper app bundle structure with Info.plist
3. Copies VLCKit.framework and libprojectM-4.dylib
4. Fixes rpaths for framework loading
5. Creates DMG with drag-to-Applications install

## Versioning

**Single source of truth:** `Sources/NullPlayer/Resources/Info.plist`

To release a new version:
1. Edit `Info.plist`:
   - `CFBundleShortVersionString` - Marketing version (e.g., `1.0`, `1.1`, `2.0`)
   - `CFBundleVersion` - Build number (e.g., `1`, `2`, `3`)
2. Run `./scripts/build_dmg.sh`

The build script reads version from Info.plist automatically. The DMG is named `NullPlayer-{version}.dmg`.

**Version in code:** Use `BundleHelper.appVersion`, `BundleHelper.buildNumber`, or `BundleHelper.fullVersion` to access version info in Swift.

## Build Script and Log Monitoring

### Running the App

The `kill_build_run.sh` script:
1. Kills any running NullPlayer instances (`pkill -9 -x NullPlayer`)
2. Builds in release mode (`swift build -c release`)
3. Launches the app in background (`.build/arm64-apple-macosx/release/NullPlayer &`)

**Note**: Release mode ensures you're testing the same binary configuration as the DMG distribution, catching optimization-related issues early.

**Important**: The script exits immediately after launching the app. The app continues running independently.

### Monitoring Logs

When running the build script via the Shell tool with `is_background: true`, logs are captured to a terminal file in:
```text
/Users/ad/.cursor/projects/Users-ad-Projects-adamp/terminals/<shell_id>.txt
```

**To find and monitor the correct terminal:**

1. **List terminals folder** to see recent files:
   ```bash
   ls -lt /Users/ad/.cursor/projects/Users-ad-Projects-adamp/terminals/*.txt | head -5
   ```

2. **Find the terminal with NullPlayer output** - look for the one that ran kill_build_run.sh

3. **Monitor logs continuously**:
   ```bash
   tail -f /Users/ad/.cursor/projects/Users-ad-Projects-adamp/terminals/<id>.txt
   ```

4. **Search for specific activity**:
   ```bash
   cat /Users/ad/.cursor/projects/Users-ad-Projects-adamp/terminals/<id>.txt | grep -i "cast\|error\|fail"
   ```

**Note**: The terminal file will show `exit_code: 0` after the build script completes, but new logs from the running app continue to be appended below that marker.

### Checking if App is Running

```bash
pgrep -l NullPlayer  # Shows PID if running
```

## Documentation

Skills contain detailed technical documentation. Key skills include:

- **ui-guide**: Coordinate systems, scaling, skin rendering
- **audio-system**: Audio pipelines, EQ, spectrum analysis
- **modern-skin-guide**: Modern skin engine and creation
- **user-guide**: Features, menus, keyboard shortcuts
- **plex-integration**, **jellyfin-integration**, **subsonic-integration**, **emby-integration**: Server integrations (Plex, Jellyfin, Navidrome/Subsonic, Emby)
- **sonos-casting**, **chromecast-casting**: Casting protocols
- **radio-streaming**: Internet radio support
- **visualizations**: Album art and ProjectM
- **testing**: UI testing workflows
- **non-retina-fixes**: Display artifact fixes

All skills are in the `skills/` directory.

## Architecture

```
Sources/NullPlayer/
├── App/              # AppDelegate, WindowManager, menus, MainWindowProviding protocol
├── Audio/            # AudioEngine, StreamingAudioPlayer, EQ
├── Casting/          # Chromecast, Sonos, DLNA casting
├── Radio/            # Internet radio (Shoutcast/Icecast) support
├── Skin/             # Classic .wsz skin loading and rendering
├── ModernSkin/       # Modern skin engine (independent of classic system)
├── Windows/          # All window views (MainWindow, ModernMainWindow, ModernSpectrum, ModernPlaylist, ModernEQ, ModernProjectM, ModernLibraryBrowser, Playlist, EQ, etc.)
├── Plex/             # Plex server integration
├── Subsonic/         # Navidrome/Subsonic server integration
├── Jellyfin/         # Jellyfin media server integration
├── Emby/             # Emby media server integration
├── Visualization/    # ProjectM wrapper, Metal spectrum analyzer + flame mode
└── Models/           # Track, Playlist, MediaLibrary
```

## Key Source Files

| Area | Files |
|------|-------|
| Skin (Classic) | `Skin/SkinElements.swift`, `Skin/SkinRenderer.swift`, `Skin/SkinLoader.swift` |
| Skin (Modern) | `ModernSkin/ModernSkinEngine.swift`, `ModernSkin/ModernSkinConfig.swift`, `ModernSkin/ModernSkinRenderer.swift`, `ModernSkin/ModernSkinLoader.swift`, `ModernSkin/ModernSkinElements.swift` |
| Audio | `Audio/AudioEngine.swift`, `Audio/StreamingAudioPlayer.swift`, `Audio/BPMDetector.swift` |
| Windows | `Windows/MainWindow/`, `Windows/ModernMainWindow/`, `Windows/ModernSpectrum/`, `Windows/ModernPlaylist/`, `Windows/ModernEQ/`, `Windows/ModernProjectM/`, `Windows/ModernLibraryBrowser/`, `Windows/Playlist/`, `Windows/Equalizer/` |
| Visualization | `Windows/ProjectM/`, `Windows/Spectrum/`, `Visualization/VisualizationGLView.swift`, `Visualization/SpectrumAnalyzerView.swift`, `Visualization/SpectrumShaders.metal`, `Visualization/FlameShaders.metal`, `Visualization/CosmicShaders.metal`, `Visualization/ElectricityShaders.metal`, `Visualization/MatrixShaders.metal`, `Visualization/ProjectMWrapper.swift` |
| Marquee | `Skin/MarqueeLayer.swift` (classic), `ModernSkin/ModernMarqueeLayer.swift` (modern), `Windows/Playlist/PlaylistView.swift` |
| Plex | `Plex/PlexManager.swift`, `Plex/PlexServerClient.swift` |
| Subsonic | `Subsonic/SubsonicManager.swift`, `Subsonic/SubsonicServerClient.swift`, `Subsonic/SubsonicModels.swift` |
| Jellyfin | `Jellyfin/JellyfinManager.swift`, `Jellyfin/JellyfinServerClient.swift`, `Jellyfin/JellyfinModels.swift`, `Jellyfin/JellyfinPlaybackReporter.swift` |
| Emby | `Emby/EmbyManager.swift`, `Emby/EmbyServerClient.swift`, `Emby/EmbyModels.swift`, `Emby/EmbyPlaybackReporter.swift`, `Emby/EmbyVideoPlaybackReporter.swift` |
| Radio | `Radio/RadioManager.swift`, `Data/Models/RadioStation.swift`, `Windows/Radio/AddRadioStationSheet.swift` |
| Casting | `Casting/CastManager.swift`, `Casting/CastProtocol.swift`, `Casting/ChromecastManager.swift`, `Casting/UPnPManager.swift`, `Casting/LocalMediaServer.swift`, `Casting/CastDevice.swift` |
| App | `App/WindowManager.swift`, `App/AppStateManager.swift`, `App/ContextMenuBuilder.swift`, `App/MainWindowProviding.swift`, `App/SpectrumWindowProviding.swift`, `App/PlaylistWindowProviding.swift`, `App/EQWindowProviding.swift`, `App/ProjectMWindowProviding.swift`, `App/LibraryBrowserWindowProviding.swift` |

## Common Tasks

### Adding a menu item
1. Edit `ContextMenuBuilder.swift` for context menus
2. Or `AppDelegate.swift` for main menu bar items

### Adding a keyboard shortcut
1. Find the relevant view's `keyDown(with:)` method
2. Follow existing pattern for key handling

### Adding a new window
1. Create folder in `Windows/`
2. Add WindowController + View
3. Register in `WindowManager.swift`

### Modifying skin rendering (classic)
1. Check sprite coordinates in `SkinElements.swift`
2. Rendering logic in `SkinRenderer.swift`
3. NullPlayer-Silver.wsz is the bundled default skin (silver/gray). Generated by `scripts/generate_default_skin.swift` and bundled in `Resources/Skins/`
4. Users load `.wsz` skins via Skins > Load Skin... or place them in `~/Library/Application Support/NullPlayer/Skins/`
5. Official skin packages are in `dist/Skins/` (NullPlayer-Silver.wsz, NullPlayer-Classic.wsz, NullPlayer-Dark.wsz, NullPlayer-Light.wsz)
6. Test with multiple skins (they vary in implementation)

### Modifying modern skin rendering
1. Element definitions in `ModernSkin/ModernSkinElements.swift`
2. Rendering logic in `ModernSkin/ModernSkinRenderer.swift`
3. Skin config schema in `ModernSkin/ModernSkinConfig.swift` (includes `TitleTextConfig` for image-based title text)
4. Title text system: three-tier fallback (full title image → character sprites → system font). Config via `titleText` in skin.json. Character sprites use `title_upper_`/`title_lower_` prefixes to avoid macOS case-insensitive filesystem collisions. Pixel art rendered with nearest-neighbor interpolation.
5. Bundled skins: NeonWave (default, sprite-based title text generated by `scripts/generate_neonwave_title_sprites.swift`), Skulls (image-based reference with pixel art sprites, generated by `scripts/generate_skulls_skin.swift`)
6. See modern-skin-guide skill for full docs

### Adding a modern sub-window
1. Follow the layer-by-layer checklist in modern-skin-guide skill (advanced-features.md → "Adding a Modern Sub-Window")
2. Reference implementation: `Windows/ModernSpectrum/` (simplest sub-window)

## Before Making UI Changes

1. Read ui-guide skill
2. Check `SkinElements.swift` for sprite coordinates
3. Follow existing patterns in `MainWindowView` or `EQView`
4. Test at different window sizes (scaling bugs)
5. Test with multiple skins

## Gotchas

- **Remember State On Quit**: `AppStateManager` saves/restores complete session state (v2). Two-phase restoration: settings first (`restoreSettingsState` — skin, volume, EQ, windows, double size), then playlist (`restorePlaylistState` — tracks with ordering preserved, current track index, seek position). Streaming tracks (Plex/Subsonic/Jellyfin/Emby) are loaded as placeholder `Track` objects with saved metadata, then replaced asynchronously via `engine.replaceTrack(at:with:)`. Radio tracks are saved via `SavedTrack.radioURL`. Many other settings (visualization modes, browser columns, radio stations, hide title bars) persist independently via UserDefaults and are NOT part of `AppState`. When adding new state: if it's a preference that should always persist, use UserDefaults directly; if it's session state that should only persist when "Remember State" is enabled, add it to the `AppState` struct with `decodeIfPresent` defaults
- **Modern main window layout split**: The time panel's visual boundary is hardcoded as a `drawInsetPanel` call in `ModernMainWindowView.swift` `draw()` — it is NOT an element in `ModernSkinElements`. The display panel uses `marqueeBackground` from `ModernSkinElements`. When adjusting time-panel geometry, update **both** the `drawInsetPanel` rect in `ModernMainWindowView.swift` and the dependent element rects (`timeDisplay`, `statusPlay/Pause/Stop`) in `ModernSkinElements.swift`.
- **Modern skin system is completely independent**: Files in `ModernSkin/`, `Windows/ModernMainWindow/`, `Windows/ModernSpectrum/`, `Windows/ModernPlaylist/`, `Windows/ModernEQ/`, `Windows/ModernProjectM/`, and `Windows/ModernLibraryBrowser/` must NEVER import or reference anything from `Skin/` or `Windows/MainWindow/`. The coupling points are only: `AppDelegate` (mode selection), `WindowManager` (via `MainWindowProviding`, `SpectrumWindowProviding`, `PlaylistWindowProviding`, `EQWindowProviding`, `ProjectMWindowProviding`, and `LibraryBrowserWindowProviding` protocols), and shared infrastructure (`AudioEngine`, `Track`, `PlaybackState`)
- **UI mode switching requires restart**: The `modernUIEnabled` UserDefaults preference selects which `MainWindowProviding` implementation `WindowManager` creates. Changing it at runtime shows a "Restart / Cancel" confirmation dialog — choosing Restart relaunches the app automatically, choosing Cancel reverts the preference
- **Mode-specific features must be guarded at all layers**: When a feature only applies to one UI mode (modern or classic), enforce it in three places:
  1. **Menu/UI**: Wrap the menu item or button in an `if wm.isModernUIEnabled` check so it's not shown in the wrong mode
  2. **Property getter or setter**: Make the property return the safe default (e.g. `false`) when the wrong mode is active, OR reset to the safe default in `didSet` — this prevents stale UserDefaults or programmatic access from leaking behavior across modes
  3. **Action/toggle function**: Add a `guard isModernUIEnabled else { return }` at the top of the toggle/apply function
  
  Example (Hide Title Bars — modern only):
  ```swift
  // Property: getter returns false in classic mode
  var hideTitleBars: Bool {
      get { isModernUIEnabled && UserDefaults.standard.bool(forKey: "hideTitleBars") }
      set { UserDefaults.standard.set(newValue, forKey: "hideTitleBars") }
  }
  // Toggle: guard at top
  func toggleHideTitleBars() {
      guard isModernUIEnabled else { return }
      ...
  }
  // Menu: wrapped in if-check
  if wm.isModernUIEnabled {
      let item = NSMenuItem(title: "Hide Title Bars", ...)
      menu.addItem(item)
  }
  ```
- **Skin coordinates**: skin skins use top-left origin, macOS uses bottom-left
- **Library browser expand tasks must use `Task.detached`**: In `ModernLibraryBrowserView`, expand tasks (artist → albums, album → songs, etc.) for Jellyfin, Emby, and Subsonic must use `Task.detached { @MainActor ... }` instead of `Task { @MainActor ... }`. Regular `Task { }` can inherit cancellation state from the calling context on the main actor, causing the task to be immediately cancelled. Artist expansion should also prefer filtering cached albums by `artistId` (instant) before falling back to a network request
- **Jellyfin/Emby library selector is browse-mode-aware**: The "Lib:" click zone in the library browser shows a music library picker when in music tabs (Artists/Albums/Tracks/Plists) and a video library picker when in Movies/Shows tabs. Both `JellyfinManager` and `EmbyManager` have separate `currentMusicLibrary`, `currentMovieLibrary`, and `currentShowLibrary` — each posts its own notification (`musicLibraryDidChangeNotification`, `videoLibraryDidChangeNotification`). `fetchMusicLibraries()` and `fetchVideoLibraries()` both return ALL views without `CollectionType` filtering. `selectMovieLibrary(_:)` and `selectShowLibrary(_:)` accept `nil` to show all.
- **Subsonic music folders**: `SubsonicManager` now tracks `musicFolders: [SubsonicMusicFolder]` and `currentMusicFolder: SubsonicMusicFolder?` (nil = all folders). Fetched via `getMusicFolders` on connect. `musicFolderId` is passed to `getArtists` and `getAlbumList2` when a folder is selected. Persisted via `SubsonicCurrentMusicFolderID` UserDefaults key. Posts `musicFolderDidChangeNotification` on change.
- **Streaming audio**: Uses `AudioStreaming` library, different from local `AVAudioEngine`
- **Local file completion handler**: Must use `scheduleFile(_:at:completionCallbackType:completionHandler:)` with `.dataPlayedBack` - NOT the deprecated 3-parameter `scheduleFile(_:at:completionHandler:)` which defaults to `.dataConsumed` and fires before audio finishes playing, causing premature track advancement and UI desync
- **Window docking**: Complex snapping logic in `WindowManager` - test edge cases
  - Multi-monitor: Screen edge snapping is skipped if it would cause docked windows to end up on different screens
  - `Snap to Default` centers main window on its current screen (not always the primary display)
  - Coordinated minimize: uses `addChildWindow`/`removeChildWindow` in `windowWillMiniaturize`/`windowDidDeminiaturize` to temporarily make docked windows children of the main window so they animate into the dock together. Child relationships are removed on restore so windows remain independent for normal docking/dragging
  - **Center stack collapse**: `slideUpWindowsBelow(closingFrame:)` in `WindowManager` slides docked windows up when a stack window is hidden. Called from `toggleEqualizer/Playlist/Spectrum` — capture the frame BEFORE `orderOut`, then call it. Uses BFS over `dockThreshold`-adjacent windows (by vertical gap + horizontal overlap). Must set `isSnappingWindow = true` during moves to prevent the docking feedback loop.
- **Hide Title Bars mode** (modern UI only): `hideTitleBars` UserDefaults preference hides skinned title bars on all windows. Only available in modern UI mode — the getter returns `false` when classic mode is active, and the menu item is hidden. Key implementation details:
  - Each view's `titleBarHeight` computed property returns `borderWidth` (not 0) when hidden, preserving the top border line
  - `toggleHideTitleBars()` must adjust `minSize`/`maxSize` constraints BEFORE resizing (EQ has `maxSize = minSize`)
  - Stack windows (main, EQ, playlist, spectrum) resize independently; side windows (ProjectM, Library Browser) match the stack height
- **Double Size mode** (both modern and classic UI): Toggle via 2X button on main window or context menu.
  - **Modern UI**: live toggle — `ModernSkinElements.scaleFactor` is a computed property (`baseScaleFactor * sizeMultiplier`). `baseScaleFactor` is set by skin.json `window.scale`; `sizeMultiplier` is set to 2.0 by double size mode. Do NOT cache `scaleFactor` in a `let` property -- use a computed `var` or reference it inline. Views must observe `.doubleSizeDidChange` and recreate their renderer. Side windows (Library Browser, ProjectM) scale width by `sizeMultiplier` and match stack height; their layout constants and hardcoded pixel padding must also multiply by `sizeMultiplier`
  - **Classic UI**: requires restart (same pattern as classic/modern mode switching). `MenuActions.toggleDoubleSize()` shows a "Restart Required" dialog before touching the UI, then toggles `isDoubleSize` and calls `relaunchApp()` if confirmed. The toggle happens before relaunch so `applicationWillTerminate` → `saveState()` captures the new value. `applyDoubleSize()` is not guarded by `isModernUIEnabled` — it runs for both modes.
  - **Startup restoration**: `isDoubleSize` is restored in `AppStateManager.restoreSettingsState()` BEFORE sub-windows are shown (at the top of the `+0.1s` dispatch block). This ensures `applyDoubleSize` runs while sub-windows are not yet visible, so it only updates the main window's `minSize`/frame — it does NOT re-scale sub-window frames that are already at their saved 2x sizes. If the flag is restored after sub-windows appear, the playlist height (which is relative to current frame) gets doubled again (4x) instead of staying at 2x.
  - When title bars are hidden, all window drags pass `fromTitleBar: true` to allow undocking (no visual title bar to grab)
  - Classic windows use drawing transform offset (`translateBy`) to shift the skin image up; modern windows use conditional `titleBarHeight`
- **Sonos menu**: Uses custom `SonosRoomCheckboxView` to keep menu open during multi-select
- **Sonos room IDs**: `sonosRooms` returns room UDNs, `sonosDevices` only has group coordinators - match carefully. Use `UPnPManager.sonosCastDevice(forZoneUDN:)` to create a `CastDevice` from zone info when the target room isn't a group coordinator
- **Sonos coordinator transfer**: When unchecking the coordinator while other rooms remain grouped, `CastManager.transferSonosCast()` saves session state, stops the old coordinator, casts to the new coordinator, and re-joins other rooms. Uses `UPnPManager.disconnectSession()` to clear the session without sending Stop (old coordinator already standalone). `stopCasting()` ungroups all member rooms before stopping to prevent stale group topology
- **Subsonic→Sonos casting**: Uses LocalMediaServer proxy because Sonos can't handle URLs with query params (auth tokens). The proxy also handles localhost-bound Navidrome servers. Stream URLs omit `f=json` (only for API responses, not binary streams)
- **Internet radio state management**: `loadTracks()` must use `stopLocalOnly()` instead of `stop()` when loading radio content - calling `stop()` triggers `RadioManager.stop()` which clears state and breaks auto-reconnect/metadata. The `isRadioContent` check detects radio by matching track URL with `currentStation.url`
- **Radio playlist URL resolution**: When resolving `.pls`/`.m3u` URLs, check `CastManager.shared.isCasting` fresh inside the async callback, not captured before the network request (up to 10s timeout). User may start casting during resolution
- **Video casting has TWO paths** - handle both in control logic:
  - **Player path**: Cast button in video player → `VideoPlayerWindowController.isCastingVideo`
  - **Menu path**: Right-click → Cast to... → `CastManager.shared.isVideoCasting` (no video player window!)
  - Controls must check both: `WindowManager.toggleVideoCastPlayPause()` handles routing
- **Swift Data slicing pitfall**: When you slice a `Data`, it maintains original indices! Use `data.startIndex` explicitly:
  ```swift
  // WRONG - may read wrong bytes if data is a slice:
  let byte = data[0]
  let slice = data[4..<total]
  
  // CORRECT - always works:
  let byte = data[data.startIndex]
  let slice = data[(data.startIndex + 4)..<(data.startIndex + total)]
  ```
- **Metal command encoders**: Never use `if let enc = cb.makeRenderCommandEncoder(...), let pl = pipeline { ... }` — if `pipeline` is nil, the encoder is created but never ended, leaving the command buffer in an invalid state and causing a Metal API violation crash on `commit()`. Always guard the pipeline BEFORE creating the encoder:
  ```swift
  // WRONG - encoder created but never ended if pipeline is nil:
  if let enc = cb.makeRenderCommandEncoder(descriptor: rpd), let pl = pipeline {
      enc.setRenderPipelineState(pl)
      enc.endEncoding()
  }
  cb.commit()  // Crashes!
  
  // CORRECT - guard pipeline first, then create encoder:
  guard let pl = pipeline else { inFlightSemaphore.signal(); return }
  if let enc = cb.makeRenderCommandEncoder(descriptor: rpd) {
      enc.setRenderPipelineState(pl)
      enc.endEncoding()
  }
  cb.commit()
  ```
- **Spectrum shader availability**: Use `SpectrumAnalyzerView.isShaderAvailable(for:)` to check if a mode's shader file exists before switching to it. This static method works without a view instance and should be used when restoring modes from UserDefaults and when building menus. The instance method `isPipelineAvailable(for:)` checks the actual compiled pipeline and is used after `setupMetal()`
- **NSTextField background**: Setting `backgroundColor` on an `NSTextField` has no visible effect unless `drawsBackground = true` is also set. Always pair them — missing this causes the custom color to be silently ignored (e.g. light text invisible on white in light mode)
- **Edit panel input fields**: Editable `NSTextField` inputs use black text on white background — not the window's dark theme colors. Read-only labels and window chrome may follow the dark theme
- **No Spotify/Apple/Amazon**: These integrations are explicitly not accepted
- **Plex API filter operators**: `URLQueryItem` will URL-encode operators like `>=`, `<=` which breaks Plex filtering. Build URLs manually for filter params. Note: Plex only supports `>=`, `<=`, `=`, `!=` operators - **NOT `<` or `>`** (use `<=` with value-1 instead):
  ```swift
  // WRONG - URLQueryItem encodes >= as %3E%3D, Plex ignores the filter:
  URLQueryItem(name: "userRating>=", value: "8")
  
  // WRONG - Plex doesn't support < operator (returns 400 Bad Request):
  let url = "...&ratingCount<1000&..."
  
  // CORRECT - manual URL with literal operators:
  let url = "\(baseURL)/library/sections/\(id)/all?type=10&userRating>=8&..."
  
  // CORRECT - use <= with threshold-1 instead of <:
  let url = "...&ratingCount<=999&..."  // equivalent to <1000
  ```
- **Sonos playback polling**: CastManager polls Sonos every 5s via `GetTransportInfo` + `GetPositionInfo` to detect external pause/stop and sync position. This is different from Chromecast which uses its own 1s status polling. The polling timer starts in `startSonosPolling()` and stops in `stopSonosPolling()` / `stopCasting()`.
- **Sonos Content-Type matching**: The content type in `CastMetadata` (used in DIDL-Lite `protocolInfo`) MUST match the actual file format. Use `CastManager.detectAudioContentType(for:)` to derive from URL extension. Never hardcode `"audio/mpeg"` or `"audio/flac"` -- Sonos may reject mismatched content.
- **Subsonic/Jellyfin/Emby streaming URL content type**: Streaming URLs from Subsonic (`/rest/stream?id=...`), Jellyfin (`/Audio/{id}/stream`), and Emby (`/Audio/{id}/stream`) have no file extension, so `detectAudioContentType(for:)` defaults to `audio/mpeg`. This breaks Sonos casting for non-MP3 formats. Always prefer `Track.contentType` (set by the server client from API metadata) or upstream HEAD detection via `prepareProxyURL()`. The `SavedTrack.contentType` field preserves this across app restarts.
- **Sonos HEAD requests**: LocalMediaServer must handle HEAD requests (not just GET). Sonos sends HEAD before GET to check Content-Length. Missing HEAD handler causes 404 which can prevent playback.
- **Sonos Content-Length for MP3/OGG**: Sonos closes the connection if `Content-Length` header is missing for MP3 and OGG. Chunked transfer encoding only works for WAV/FLAC. The stream proxy must buffer the full response for MP3/OGG to provide Content-Length.
- **Sonos radio URI scheme**: For MP3 internet radio streams cast to Sonos, use `x-rincon-mp3radio://` instead of `http://`. This uses Sonos's internal radio buffering which is more resilient. Only applies to MP3 radio, not AAC/OGG.
- **Sonos UPnP Error 701**: "Transition Not Available" - the most common Sonos SOAP error. Returned as HTTP 500 with `<errorCode>701</errorCode>` in body. Don't blindly retry -- poll `getTransportState()` until transport is ready (STOPPED/PLAYING/PAUSED_PLAYBACK), then retry.
- **Sonos Connection Security (firmware 85.0+)**: Users can disable UPnP or enable Authentication in Sonos app settings. Both break SOAP control. On 401/403, show a specific error message about Connection Security settings.
- **Sonos format compatibility — two-tier check**: `CastManager.isSonosCompatible` has strict (default) and permissive (`allowUnknownSampleRate: true`) modes. _Scan/positioning_ functions (`advanceToFirstSonosCompatibleTrack`, all skip loops in `castTrackDidFinish`) MUST use `allowUnknownSampleRate: true` — they run before the sample rate is fetched. _Cast_ functions (`castCurrentTrack`, `castNewTrack`) fetch the SR first, then call strict mode as the final verdict. Using strict mode in a scan loop silently skips all nil-SR FLAC tracks (e.g. Plex) without ever attempting a fetch.

## Testing

```bash
swift test  # Unit tests (models, parsers, utilities)
```

Manual QA for UI/playback changes:
- Local file playback
- Plex streaming
- Subsonic/Navidrome streaming
- Jellyfin streaming
- Emby streaming
- Internet radio (playback, auto-reconnect, ICY metadata display)
- Multiple skins
- Window snapping/docking
- Visualizations
- Sonos casting (multi-room selection, join/leave while casting)
- Radio casting to Sonos (verify stream plays, time resets to 0:00)
- Video casting (Plex/Jellyfin/Emby movies/episodes to Chromecast/DLNA TVs)

## Troubleshooting Integrations

### Standalone Test Programs

When debugging complex protocol integrations (Chromecast, UPnP, etc.), create standalone Swift test scripts to isolate the problem from the full app:

```bash
# Run a standalone test script
swift scripts/test_chromecast.swift
```

**Benefits:**
- Faster iteration (no full app rebuild)
- Isolated environment (no interference from other systems)
- Easier to add debug output
- Can test specific protocol steps in sequence

**Example test script structure** (see `scripts/test_chromecast.swift`):
1. Minimal protocol implementation (encode/decode)
2. Direct network connection
3. Step-by-step message exchange with logging
4. Clear success/failure output

**When to use:**
- Silent crashes with no stack trace
- Protocol timeouts where you can't tell what's failing
- Complex async flows that are hard to debug in the full app
- Third-party device communication issues

### Chromecast Debugging

The Chromecast implementation uses Google Cast Protocol v2:
- TLS connection to port 8009
- Protobuf-framed messages (4-byte big-endian length prefix)
- Key namespaces: `connection`, `heartbeat`, `receiver`, `media`

Test with: `swift scripts/test_chromecast.swift`

Common issues:
- **Silent crash on receive**: Check Data slice indexing (use `startIndex`)
- **Timeout waiting for transportId**: Check receive loop is processing buffer
- **TLS errors**: Chromecast uses self-signed certs, must accept in verify block

