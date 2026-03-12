# NullPlayer

## A throwback open-source music player for macOS, supporting Plex, Sonos, Navidrome, Jellyfin, Emby and Chromecast integration, local media, internet radio and more.

## This is a 100% clean room hobby project is not affiliated with Winamp, Nullsoft, Sonos, Plex, Radionomy Group or anyone else.

## **If you enjoy NullPlayer, please ⭐ star ⭐ the project on GitHub!**

![MixCollage_player](https://github.com/user-attachments/assets/5d29303e-2910-4f1d-b5ac-b65b7f17a34f)
![MixCollage-12-Mar-2026-03-38-PM-191](https://github.com/user-attachments/assets/b26003a8-bb5d-45ca-9504-2a3e13079fe9)

## Features

- Library browser window for Plex, Jellyfin, Emby, Navidrome/Subsonic, and local library files
- Plex Media Server integration with PIN-based authentication
- Jellyfin media server integration with music and video streaming, scrobbling, and library browsing
- Emby media server integration with music and video streaming, scrobbling, and library browsing
- Inteligent radio mix generation for all sources
- Navidrome/Subsonic server integration with scrobbling support
- Local media library with metadata parsing, editing, library management
- ProjectM visualizations with 100 included. Users can download more
- Sonic similarity radio stations populated by Plex API's  (Library, Genre, Decade, Hits, Deep Cuts)
- Plex radio track history with configurable exclusion rules. Stop the same songs from being added to your Plex radio stations
- Sonos content filtering for unsupported lossless formats. Keeps the music playing by not sending unsupported encodings to Sonos.
- Much better Sonos playlist support than the current PlexAmp (Jan 2026)
- Classic V1 UI has full support for classic Winamp skin skins (.wsz files)
- Modern V2 UI skin system, many v2 skins included. Open format, users can easily make new v2 skins via json
- Original Spenctrum analysis visualization system
- Album art visualization system with user selected effects
- Main player, Playlist editor, and 10-band Equalizer windows
- Classic window snapping and docking behavior
- Audio playback: MP3, FLAC, AAC, WAV, AIFF, ALAC, OGG
- Video playback: MKV, MP4, MOV, AVI, WebM, HEVC (KSPlayer/FFmpeg)
- Gapless playback for seamless track transitions
- Sweet Fades (crossfade) with configurable fade duration
- Media Drag and drop support
- Album/Cover/Movie art browser with visualizations
- Internet radio (Shoutcast/Icecast) with live metadata and auto-reconnect
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

**Skin installation**: Place skin folders or `.nps` bundles in `~/Library/Application Support/NullPlayer/ModernSkins/`, then right-click the player and select your skin from **Modern UI > Select Skin**.

## License

This project is open source and uses the following licensed components:

- **KSPlayer** (GPL-3.0) - Video playback with FFmpeg backend
- **libprojectM** (LGPL-2.1) - ProjectM visualizations



