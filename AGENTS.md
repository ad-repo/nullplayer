# Agent Guide

## Quick Start

```bash
./scripts/bootstrap.sh      # Download frameworks (first time)
./scripts/kill_build_run.sh # Build and run
```

## Documentation

| Doc | Purpose |
|-----|---------|
| [docs/USER_GUIDE.md](docs/USER_GUIDE.md) | Features, menus, keyboard shortcuts |
| [docs/UI_GUIDE.md](docs/UI_GUIDE.md) | Coordinate systems, scaling, skin sprites |
| [docs/AUDIO_SYSTEM.md](docs/AUDIO_SYSTEM.md) | Audio engine, EQ, spectrum, Plex streaming |
| [docs/VISUALIZATIONS.md](docs/VISUALIZATIONS.md) | Album art and ProjectM visualizers |

## Architecture

```
Sources/AdAmp/
├── App/              # AppDelegate, WindowManager, menus
├── Audio/            # AudioEngine, StreamingAudioPlayer, EQ
├── Skin/             # Winamp skin loading and rendering
├── Windows/          # All window views (MainWindow, Playlist, EQ, etc.)
├── Plex/             # Plex server integration
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

1. Read [docs/UI_GUIDE.md](docs/UI_GUIDE.md)
2. Check `SkinElements.swift` for sprite coordinates
3. Follow existing patterns in `MainWindowView` or `EQView`
4. Test at different window sizes (scaling bugs)
5. Test with multiple skins

## Gotchas

- **Skin coordinates**: Winamp skins use top-left origin, macOS uses bottom-left
- **Streaming audio**: Uses `AudioStreaming` library, different from local `AVAudioEngine`
- **Window docking**: Complex snapping logic in `WindowManager` - test edge cases
- **No Spotify/Apple/Amazon**: These integrations are explicitly not accepted

## Testing

```bash
swift test  # Unit tests (models, parsers, utilities)
```

Manual QA for UI/playback changes:
- Local file playback
- Plex streaming  
- Multiple skins
- Window snapping/docking
- Visualizations
