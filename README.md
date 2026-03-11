# NullPlayer

### A free, open-source music player for macOS, featuring modern Plex, Jellyfin, Emby, and Sonos integration.

###  This is a clean room project is not affiliated with classic skin, classic skin LLC, Radionomy Group or anyone else.

**If you enjoy NullPlayer, please ⭐ star ⭐ the project on GitHub!**


## Features

- Library browser window for Plex, Jellyfin, Emby, Navidrome/Subsonic, and local library files
- Plex Media Server integration with PIN-based authentication
- Plex music and video streaming and playlist support
- Jellyfin media server integration with music and video streaming, scrobbling, and library browsing
- Emby media server integration with music and video streaming, scrobbling, and library browsing
- Navidrome/Subsonic server integration with scrobbling support
- Local media library with metadata parsing, editing, library management
- ProjectM visualizations with 100 included. Users can download more
- Sonic similarity radio stations populated by Plex APIs (Library, Genre, Decade, Hits, Deep Cuts, and rating-based presets)
- Unified `Radio History` submenu with per-source repeat filtering controls (Plex, Subsonic/Navidrome, Jellyfin, Emby, Local)
- Sonos content filtering for unsupported lossless formats. Keeps the music playing by not sending unsupported encodings to Sonos.
- Much better Sonos playlist support than the current PlexAmp (Jan 2026)
- Classic V1 UI has full support for classic Winamp skin skins (.wsz files)
- Modern V2 UI skin system, many v2 skins included. Open format, users can easily make new v2 skins via json
- Original spectrum analysis visualization system with `vis_classic` exact mode (profile-compatible) in both main and spectrum windows
- Dockable waveform window in both classic and modern UI modes with current-track rendering, click-to-seek for timed tracks, optional `.cue` markers, and live streaming waveform support
- Album art visualization system with user selected effects
- Main player, Playlist editor, Waveform window, and 10-band Equalizer windows
- Classic window snapping and docking behavior
- Audio playback: MP3, FLAC, AAC, WAV, AIFF, ALAC, OGG
- Video playback: MKV, MP4, MOV, AVI, WebM, HEVC (KSPlayer/FFmpeg)
- Gapless playback for seamless track transitions
- Sweet Fades (crossfade) with configurable fade duration
- Volume normalization for consistent loudness
- Media Drag and drop support
- Album/Cover/Movie art browser with visualizations
- IMDB integration
- Internet radio (Shoutcast/Icecast) with a large bundled global station catalog, live metadata (ICY + SomaFM fallback), and auto-reconnect
- Internet radio smart/manual folders with persistent 5-star station ratings
- AirPlay and Casting to Chromecast, Sonos (multi-room), and DLNA devices
- Cast local files, Jellyfin/Emby/Navidrome/Subsonic streams, and internet radio to Sonos
- macOS Now Playing integration (Control Center, Touch Bar, AirPods controls)
- [Discord Music Presence](https://github.com/ungive/discord-music-presence) support

## Installation

Download the latest DMG from [Releases](https://github.com/ad-repo/nullplayer/releases).

Follow [r/NullPlayer](https://www.reddit.com/r/NullPlayer/) for release notifications. Report bugs on [GitHub Issues](https://github.com/ad-repo/nullplayer/issues) or the subreddit.


### Fixing "App is damaged" or "macOS cannot verify that this app is free from malware" Error

Since the app is in beta testing and not code-signed (it costs $99 a year to sign the app and I am not sure yet I want to pay that yet) macOS Gatekeeper will block it. To fix this:

**Option 1: Terminal (Recommended)**
```bash
xattr -cr /Applications/NullPlayer.app
```

**Option 2: System Settings**
1. Try to open NullPlayer (it will be blocked)
2. Go to **System Settings → Privacy & Security**
3. Scroll down and click **Open Anyway** next to the NullPlayer message
4. Click **Open** in the confirmation dialog

After either option, NullPlayer will open normally.

## Requirements

- macOS 14.0 (Sonoma) or later

## Building from Source

Requires Xcode 15.0+ with Command Line Tools and Swift 5.9+.

```bash
# Clone the repository
git clone https://github.com/ad-repo/nullplayer.git
cd nullplayer

# Download required frameworks
./scripts/bootstrap.sh

# Build and run
./scripts/kill_build_run.sh
```

The bootstrap script downloads VLCKit and libprojectM from GitHub Releases with checksum verification.

To open in Xcode:

```bash
open Package.swift
```

## Dependencies

| Library | Purpose |
|---------|---------|
| [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) | .wsz skin file extraction |
| [SQLite.swift](https://github.com/stephencelis/SQLite.swift) | Media library storage |
| [KSPlayer](https://github.com/kingslay/KSPlayer) | Video playback with FFmpeg backend |
| [AudioStreaming](https://github.com/dimitris-c/AudioStreaming) | HTTP audio streaming for Plex |
| [FlyingFox](https://github.com/swhitty/FlyingFox) | Embedded HTTP server for local file casting |
| [libprojectM](https://github.com/projectM-visualizer/projectm) | ProjectM visualizations |

## Media Library

Library data is stored as JSON at `~/Library/Application Support/NullPlayer/library.json`.

**Backup & Restore API** (`MediaLibrary.swift`):

| Function | Description |
|----------|-------------|
| `backupLibrary(customName:)` | Creates timestamped JSON backup, returns URL |
| `restoreLibrary(from:)` | Restores from backup (auto-backs up current first) |
| `listBackups()` | Returns backup URLs sorted newest first |
| `deleteBackup(at:)` | Deletes a backup file |

Backups are stored in `~/Library/Application Support/NullPlayer/Backups/`.

## Development

See [AGENTS.md](AGENTS.md) for documentation links and key source files.

**Note:** This project will never support Spotify, Youtube, Apple or Amazon. Please do not submit PRs for this type of integration.

## Skins

NullPlayer has two UI modes, selectable from the right-click context menu under **Skins**. Switching between modes triggers an automatic restart prompt:

### Classic Mode

Classic `.wsz` skin support. No skins are bundled -- the app starts with a native macOS appearance. To apply a skin, use **Skins > Load Skin...** to open a `.wsz` file, or place skin files in `~/Library/Application Support/NullPlayer/Skins/` and select them from the Skins menu. Official NullPlayer skin packages are available in the `dist/Skins/` directory or from [Releases](https://github.com/ad-repo/nullplayer/releases). Thousands of community-created skins can be downloaded from the **Skins > Get More Skins...** menu link.

### Modern Mode

A custom skin engine built from scratch with a neon cyberpunk aesthetic. Modern skins are JSON-configured and support:

- **Color palette theming** -- define 12 named colors and the entire UI adapts
- **Custom PNG image assets** -- optionally replace any UI element with your own artwork
- **Procedural grid backgrounds** -- configurable Tron-style perspective grids
- **Bloom/glow post-processing** -- Metal-based glow effects on bright UI elements
- **Custom fonts** -- bundle TTF/OTF fonts or use any system font
- **Animations** -- sprite frame cycling and parametric effects (pulse, glow, rotate, color cycle)

The bundled default skin ("NeonWave") is fully programmatic -- zero image assets, pure palette-driven rendering.

**Creating a skin is as simple as writing a single JSON file.** See [SKINNING.md](SKINNING.md) for the complete guide.

**Skin installation**: Use **UI > Modern > Load Skin...** to import a `.nsz` bundle, or place skin folders/`.nsz` files in `~/Library/Application Support/NullPlayer/ModernSkins/`, then select the skin from **UI > Modern**.

## Waveform Window

NullPlayer includes a standalone dockable waveform window in both UI modes.

- Local audio files generate and cache a 4096-bucket waveform in `~/Library/Application Support/NullPlayer/WaveformCache/`
- Timed streams build a progressive live waveform and remain seekable
- Live radio-style streams render a rolling live waveform and are shown as non-seekable
- Optional adjacent `.cue` files provide cue markers and tooltip labels
- The window is available from the Window/context menus and docks into the same center stack as EQ, Playlist, and Spectrum

## License

NullPlayer is licensed under **GPL-3.0-only**. It also distributes third-party components with their own notices and terms:

- **KSPlayer** (GPL-3.0) - Video playback with FFmpeg backend
- **libprojectM** (LGPL-2.1) - ProjectM visualizations
- **vis_classic** resources/core attribution (MIT) - notice included at `Sources/NullPlayer/Resources/vis_classic/LICENSE.txt`
- **Nullsoft FFT code** used by `CVisClassicCore` upstream files (`fft.h` / `fft.cpp`) - BSD-style 3-clause terms; notice included at `Sources/CVisClassicCore/upstream/FFTNullsoft_LICENSE.txt` and bundled copy at `Sources/NullPlayer/Resources/ThirdPartyLicenses/FFTNullsoft_LICENSE.txt`
