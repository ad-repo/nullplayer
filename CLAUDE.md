# Agent Guide

## Quick Start

```bash
./scripts/bootstrap.sh      # Download frameworks (first time)
./scripts/kill_build_run.sh # Build and run
```

## Documentation

| Doc | Purpose |
|-----|---------|
| [AGENT_DOCS/USER_GUIDE.md](AGENT_DOCS/USER_GUIDE.md) | Features, menus, keyboard shortcuts |
| [AGENT_DOCS/UI_GUIDE.md](AGENT_DOCS/UI_GUIDE.md) | Coordinate systems, scaling, skin sprites |
| [AGENT_DOCS/AUDIO_SYSTEM.md](AGENT_DOCS/AUDIO_SYSTEM.md) | Audio engine, EQ, spectrum, Plex/Subsonic streaming |
| [AGENT_DOCS/VISUALIZATIONS.md](AGENT_DOCS/VISUALIZATIONS.md) | Album art and ProjectM visualizers |
| [AGENT_DOCS/TESTING.md](AGENT_DOCS/TESTING.md) | UI testing mode, accessibility identifiers |
| [AGENT_DOCS/SONOS.md](AGENT_DOCS/SONOS.md) | Sonos discovery, multi-room casting, custom checkbox UI |

## Architecture

```
Sources/AdAmp/
├── App/              # AppDelegate, WindowManager, menus
├── Audio/            # AudioEngine, StreamingAudioPlayer, EQ
├── Casting/          # Chromecast, Sonos, DLNA casting
├── Skin/             # Winamp skin loading and rendering
├── Windows/          # All window views (MainWindow, Playlist, EQ, etc.)
├── Plex/             # Plex server integration
├── Subsonic/         # Navidrome/Subsonic server integration
├── Visualization/    # ProjectM wrapper
└── Models/           # Track, Playlist, MediaLibrary
```

## Key Source Files

| Area | Files |
|------|-------|
| Skin | `Skin/SkinElements.swift`, `Skin/SkinRenderer.swift`, `Skin/SkinLoader.swift` |
| Audio | `Audio/AudioEngine.swift`, `Audio/StreamingAudioPlayer.swift` |
| Windows | `Windows/MainWindow/`, `Windows/Playlist/`, `Windows/Equalizer/` |
| Visualization | `Windows/Milkdrop/`, `Windows/PlexBrowser/PlexBrowserView.swift`, `Visualization/ProjectMWrapper.swift` |
| Plex | `Plex/PlexManager.swift`, `Plex/PlexServerClient.swift` |
| Subsonic | `Subsonic/SubsonicManager.swift`, `Subsonic/SubsonicServerClient.swift`, `Subsonic/SubsonicModels.swift` |
| Casting | `Casting/CastManager.swift`, `Casting/UPnPManager.swift`, `Casting/ChromecastManager.swift`, `Casting/LocalMediaServer.swift` |
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
- **Sonos menu**: Uses custom `SonosRoomCheckboxView` to keep menu open during multi-select
- **Sonos room IDs**: `sonosRooms` returns room UDNs, `sonosDevices` only has group coordinators - match carefully
- **No Spotify/Apple/Amazon**: These integrations are explicitly not accepted

## Testing

```bash
swift test  # Unit tests (models, parsers, utilities)
```

Manual QA for UI/playback changes:
- Local file playback
- Plex streaming
- Subsonic/Navidrome streaming
- Multiple skins
- Window snapping/docking
- Visualizations
- Sonos casting (multi-room selection, join/leave while casting)

