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
- `dist/AdAmp.app` - The application bundle
- `dist/AdAmp-X.Y.dmg` - The distributable DMG with Applications symlink

The script:
1. Builds a release binary (`swift build -c release`)
2. Creates proper app bundle structure with Info.plist
3. Copies VLCKit.framework and libprojectM-4.dylib
4. Fixes rpaths for framework loading
5. Creates DMG with drag-to-Applications install

## Versioning

**Single source of truth:** `Sources/AdAmp/Resources/Info.plist`

To release a new version:
1. Edit `Info.plist`:
   - `CFBundleShortVersionString` - Marketing version (e.g., `1.0`, `1.1`, `2.0`)
   - `CFBundleVersion` - Build number (e.g., `1`, `2`, `3`)
2. Run `./scripts/build_dmg.sh`

The build script reads version from Info.plist automatically. The DMG is named `AdAmp-{version}.dmg`.

**Version in code:** Use `BundleHelper.appVersion`, `BundleHelper.buildNumber`, or `BundleHelper.fullVersion` to access version info in Swift.

## Build Script and Log Monitoring

### Running the App

The `kill_build_run.sh` script:
1. Kills any running AdAmp instances (`pkill -9 -x AdAmp`)
2. Builds with `swift build`
3. Launches the app in background (`.build/debug/AdAmp &`)

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

2. **Find the terminal with AdAmp output** - look for the one that ran kill_build_run.sh

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
pgrep -l AdAmp  # Shows PID if running
```

## Documentation

| Doc | Purpose |
|-----|---------|
| [AGENT_DOCS/USER_GUIDE.md](AGENT_DOCS/USER_GUIDE.md) | Features, menus, keyboard shortcuts |
| [AGENT_DOCS/UI_GUIDE.md](AGENT_DOCS/UI_GUIDE.md) | Coordinate systems, scaling, skin sprites |
| [AGENT_DOCS/AUDIO_SYSTEM.md](AGENT_DOCS/AUDIO_SYSTEM.md) | Audio engine, EQ, spectrum, Plex/Subsonic streaming |
| [AGENT_DOCS/RADIO.md](AGENT_DOCS/RADIO.md) | Internet radio, auto-reconnect, ICY metadata, casting |
| [AGENT_DOCS/VISUALIZATIONS.md](AGENT_DOCS/VISUALIZATIONS.md) | Album art and ProjectM visualizers |
| [AGENT_DOCS/TESTING.md](AGENT_DOCS/TESTING.md) | UI testing mode, accessibility identifiers |
| [AGENT_DOCS/SONOS.md](AGENT_DOCS/SONOS.md) | Sonos discovery, multi-room casting, custom checkbox UI |
| [AGENT_DOCS/CHROMECAST.md](AGENT_DOCS/CHROMECAST.md) | Google Cast protocol, debugging, test scripts |
| [AGENT_DOCS/NON_RETINA_DISPLAY_FIXES.md](AGENT_DOCS/NON_RETINA_DISPLAY_FIXES.md) | Non-Retina display artifacts, blue line fixes, tile seam fixes |

## Architecture

```
Sources/AdAmp/
├── App/              # AppDelegate, WindowManager, menus
├── Audio/            # AudioEngine, StreamingAudioPlayer, EQ
├── Casting/          # Chromecast, Sonos, DLNA casting
├── Radio/            # Internet radio (Shoutcast/Icecast) support
├── Skin/             # Winamp skin loading and rendering
├── Windows/          # All window views (MainWindow, Playlist, EQ, etc.)
├── Plex/             # Plex server integration
├── Subsonic/         # Navidrome/Subsonic server integration
├── Visualization/    # ProjectM wrapper, Metal spectrum analyzer
└── Models/           # Track, Playlist, MediaLibrary
```

## Key Source Files

| Area | Files |
|------|-------|
| Skin | `Skin/SkinElements.swift`, `Skin/SkinRenderer.swift`, `Skin/SkinLoader.swift` |
| Audio | `Audio/AudioEngine.swift`, `Audio/StreamingAudioPlayer.swift` |
| Windows | `Windows/MainWindow/`, `Windows/Playlist/`, `Windows/Equalizer/` |
| Visualization | `Windows/Milkdrop/`, `Windows/Spectrum/`, `Visualization/SpectrumAnalyzerView.swift`, `Visualization/ProjectMWrapper.swift` |
| Plex | `Plex/PlexManager.swift`, `Plex/PlexServerClient.swift` |
| Subsonic | `Subsonic/SubsonicManager.swift`, `Subsonic/SubsonicServerClient.swift`, `Subsonic/SubsonicModels.swift` |
| Radio | `Radio/RadioManager.swift`, `Data/Models/RadioStation.swift`, `Windows/Radio/AddRadioStationSheet.swift` |
| Casting | `Casting/CastManager.swift`, `Casting/CastProtocol.swift`, `Casting/ChromecastManager.swift`, `Casting/UPnPManager.swift`, `Casting/LocalMediaServer.swift` |
| App | `App/WindowManager.swift`, `App/ContextMenuBuilder.swift` |

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

### Modifying skin rendering
1. Check sprite coordinates in `SkinElements.swift`
2. Rendering logic in `SkinRenderer.swift`
3. Test with multiple skins (they vary in implementation)

## Before Making UI Changes

1. Read [AGENT_DOCS/UI_GUIDE.md](AGENT_DOCS/UI_GUIDE.md)
2. Check `SkinElements.swift` for sprite coordinates
3. Follow existing patterns in `MainWindowView` or `EQView`
4. Test at different window sizes (scaling bugs)
5. Test with multiple skins

## Gotchas

- **Skin coordinates**: Winamp skins use top-left origin, macOS uses bottom-left
- **Streaming audio**: Uses `AudioStreaming` library, different from local `AVAudioEngine`
- **Window docking**: Complex snapping logic in `WindowManager` - test edge cases
  - Multi-monitor: Screen edge snapping is skipped if it would cause docked windows to end up on different screens
  - `Snap to Default` centers main window on its current screen (not always the primary display)
- **Sonos menu**: Uses custom `SonosRoomCheckboxView` to keep menu open during multi-select
- **Sonos room IDs**: `sonosRooms` returns room UDNs, `sonosDevices` only has group coordinators - match carefully
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

## Testing

```bash
swift test  # Unit tests (models, parsers, utilities)
```

Manual QA for UI/playback changes:
- Local file playback
- Plex streaming
- Subsonic/Navidrome streaming
- Internet radio (playback, auto-reconnect, ICY metadata display)
- Multiple skins
- Window snapping/docking
- Visualizations
- Sonos casting (multi-room selection, join/leave while casting)
- Radio casting to Sonos (verify stream plays, time resets to 0:00)
- Video casting (Plex movies/episodes to Chromecast/DLNA TVs)

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

