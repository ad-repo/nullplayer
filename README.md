# AdAmp

A faithful recreation of Winamp 2.x for macOS loaded up with Plex, Navidrome/Subsonic, and Sonos support!

## Features

- Somewhat kind of maybe Pixel-perfect recreation of the classic Winamp 2.x interface
- A Brand new library browser window for Plex, Navidrome/Subsonic, and local library files
- ProjectM visualizations with 100 included. Users can download more
- Full Winamp 2 skin support (.wsz files)
- Main player, Playlist editor, and 10-band Equalizer windows
- Classic window snapping and docking behavior
- Audio playback: MP3, FLAC, AAC, WAV, AIFF, ALAC, OGG
- Video playback: MKV, MP4, MOV, AVI, WebM, HEVC (KSPlayer/FFmpeg)
- Gapless playback for seamless track transitions
- Sweet Fades (crossfade) with configurable fade duration
- Volume normalization for consistent loudness
- Local media library with metadata parsing
- Media library backup and restore
- Plex Media Server integration with PIN-based authentication
- Plex music and video streaming
- Plex Radio stations (Library, Genre, Decade, Hits, Deep Cuts) with sonic similarity
- Navidrome/Subsonic server integration with scrobbling support
- Album art visualizations
- Casting to Chromecast, Sonos, and DLNA devices
- Airplay support

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15.0+ with Command Line Tools
- Swift 5.9+

## Building

```bash
# Clone the repository
git clone https://github.com/ad-repo/adamp.git
cd adamp

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
| [libprojectM](https://github.com/projectM-visualizer/projectm) | Milkdrop visualizations |

## Media Library

Library data is stored as JSON at `~/Library/Application Support/AdAmp/library.json`.

**Backup & Restore API** (`MediaLibrary.swift`):

| Function | Description |
|----------|-------------|
| `backupLibrary(customName:)` | Creates timestamped JSON backup, returns URL |
| `restoreLibrary(from:)` | Restores from backup (auto-backs up current first) |
| `listBackups()` | Returns backup URLs sorted newest first |
| `deleteBackup(at:)` | Deletes a backup file |

Backups are stored in `~/Library/Application Support/AdAmp/Backups/`.

## Development

See [AGENTS.md](AGENTS.md) for documentation links and key source files.

**Note:** This project will never support Spotify, Youtube, Apple or Amazon. Please do not submit PRs for this type of integration.

## Skins

AdAmp supports classic Winamp 2.x skins (.wsz files). Download skins from [Winamp Skin Museum](https://skins.webamp.org/).

## License

This project is open source and uses the following licensed components:

- **KSPlayer** (GPL-3.0) - Video playback with FFmpeg backend
- **libprojectM** (LGPL-2.1) - Milkdrop visualizations

This project is not affiliated with Winamp LLC or Radionomy Group.

## Acknowledgments

- [Webamp](https://github.com/captbaritone/webamp) - Reference for skin parsing
- [Winamp Skin Museum](https://skins.webamp.org/) - Skin archive
- [Plex](https://www.plex.tv/) - Media server integration
- Original Winamp by Nullsoft

