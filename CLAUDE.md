# Agent Guide

## Quick Start

```bash
./scripts/bootstrap.sh      # Download frameworks (first time)
./scripts/kill_build_run.sh # Build and run
./scripts/build_dmg.sh      # Build distributable DMG
swift test                  # Run unit tests
```

See `docs/development-workflow.md` for build details, log monitoring, and versioning.

## Skills

Technical documentation lives in `skills/`. Read the owning skill before changing a subsystem.

- `ui-guide`: UI geometry/rendering; `audio-system`: playback/EQ; `app-state`: restoration and persistence; `user-guide`: features and menus
- `original-skin-guide`: Original skins; `winamp-modern-skin-guide`: `.wal` support, a slim router over `reference/`; `wal-skin-report`: `/wal-skin-report <skin.wal>`
- `plex-integration`, `jellyfin-integration`, `subsonic-integration`, `emby-integration`: media servers
- `sonos-casting`, `chromecast-casting`: casting protocols and debugging
- `stream-ripper`: URL ripping; `youtube-source`: YouTube audio; `cue-sheets`: cue playback/splitting; `radio-streaming`: radio
- `visualizations`: visualizer router; `main-window-visualization`: inline vis; `spectrum-analyzer-window`: analyzer; `audio-analysis-window`: analysis panes
- `peppymeter`: analog VU; `cava`: bar spectrum; `flow`: network meter; `gpu-vis-modes`: shaders; `album-art-visualizer`: ART effects
- `projectm-milkdrop`: MilkDrop; `met-museum-visualizer`: slideshow; `metal-gotchas`: Metal rules
- `geiss-port`, `tripex-port`, `vis-classic-guide`: visualization ports and compatibility
- `testing`: UI test workflows; `non-retina-fixes`: 1x display fixes; `local-library`: SQLite and scanning; `cli`: headless mode

## Architecture

```text
Sources/NullPlayer/
├── App/, Windows/                         App lifecycle and UI
├── Audio/, Casting/                       Playback, EQ, and casting
├── StreamRipper/, Radio/                  Downloading and radio
├── Skin/, ModernSkin/, WinampModern/       Skin engines
├── Plex/, Subsonic/, Jellyfin/, Emby/      Server integrations
└── Visualization/, Cava/, PeppyMeter/, Waveform/, Models/  Visuals and models
```

## Key Source Files

- App: `App/WindowManager.swift`, `App/AppStateManager.swift`, `App/ContextMenuBuilder.swift`
- Classic skin: `Skin/SkinElements.swift`, `Skin/SkinRenderer.swift`, `Skin/SkinLoader.swift`
- Audio: `Audio/AudioEngine.swift`, `Audio/StreamingAudioPlayer.swift`
- Windows: `Windows/MainWindow/`, `Windows/ModernMainWindow/`, and sibling feature-window roots
- Models/local library: `Models/Track.swift`, `Models/Playlist.swift`, `Data/Models/MediaLibrary.swift`, `Utilities/LocalFileDiscovery.swift`

## Common Tasks

- Add context-menu items in `App/ContextMenuBuilder.swift`; add main-menu items in `App/AppDelegate.swift`.
- To add a window: create its `Windows/` folder, add its controller and view, register it in `WindowManager.swift`, and add an `App/` provider protocol when classic and modern implementations share behavior.
- For a NullPlayer-owned window that should inherit `.wal` chrome, use the hosted-window registry path; see `winamp-modern-skin-guide/reference/components.md`.

## Before Making UI Changes

1. Read `ui-guide`.
2. Check `Skin/SkinElements.swift` for classic sprite coordinates.
3. Test multiple UI sizes and skins.

## Testing

Run `swift test`. For UI or playback work, manually exercise local and server playback, radio, multiple skins, docking, visualizations, casting, and relevant window sizes.

## Rules

- No Spotify, Apple Music, or Amazon Music integrations; they are explicitly not accepted.
- `ModernSkin/` and `Windows/Modern*/` must never import from `Skin/` or `Windows/MainWindow/`; see `original-skin-guide`.
- Winamp Modern (`.wal`) work must never change Classic or Original behavior. This binds shared
  code too — a change in `App/` that both modes run is gated on the mode, not justified by
  reasoning that it "should be a no-op"; see `winamp-modern-skin-guide`.
- Skin sprites use a top-left origin; macOS uses bottom-left. See `ui-guide`.
- Slicing `Data` preserves original indices; always use `data.startIndex`.
- Read the owning skill before changing a subsystem. Put new subsystem details in that skill, never here.
