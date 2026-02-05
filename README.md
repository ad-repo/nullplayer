# AdAmp

### A free, open-source recreation inspired by Winamp 2.x for macOS, featuring modern Plex and Sonos integration.

**If you enjoy AdAmp, please ⭐ star ⭐ the project on GitHub!**




https://github.com/user-attachments/assets/1d05032c-d49b-482a-99e9-b3cfa56b2a0b


https://github.com/user-attachments/assets/6c052a05-9d35-4302-ad01-c25b69922ae1



<img width="1455" height="451" alt="Screenshot 2026-01-31 at 10 06 49 PM" src="https://github.com/user-attachments/assets/ff8a5762-b84e-4681-88c1-0283943f2cbf" />
<img width="1481" height="711" alt="Screenshot 2026-01-31 at 10 10 35 PM" src="https://github.com/user-attachments/assets/7758838c-7dc1-477f-b32f-3fd598c9debf" />


## Features

- A Recreation of the classic Winamp 2.x interface with some surprises
- A Brand new library browser window for Plex, Navidrome/Subsonic, and local library files
- Plex Media Server integration with PIN-based authentication
- Plex music and video streaming and playlist support
- ProjectM visualizations with 100 included. Users can download more
- Just like PlexAmp, sonic similarity supportuing radio stations populated by Plex API's  (Library, Genre, Decade, Hits, Deep Cuts)
- Much better Sonos playlist support than the current PlexAmp (Jan 2026)
- Full Winamp 2 skin support (.wsz files)
- Main player, Playlist editor, and 10-band Equalizer windows
- Classic window snapping and docking behavior
- Audio playback: MP3, FLAC, AAC, WAV, AIFF, ALAC, OGG
- Video playback: MKV, MP4, MOV, AVI, WebM, HEVC (KSPlayer/FFmpeg)
- Gapless playback for seamless track transitions
- Sweet Fades (crossfade) with configurable fade duration
- Volume normalization for consistent loudness
- Local media library with metadata parsing
- Local media library backup and restore
- Media Drag and drop support
- Navidrome/Subsonic server integration with scrobbling support
- Album/Cover/Movie art browser with visualizations
- IMDB integration
- Internet radio (Shoutcast/Icecast) with live metadata and auto-reconnect
- AirPlay and Casting to Chromecast, Sonos (multi-room), and DLNA devices
- Cast local files, Navidrome/Subsonic streams, and internet radio to Sonos
- macOS Now Playing integration (Control Center, Touch Bar, AirPods controls)
- [Discord Music Presence](https://github.com/ungive/discord-music-presence) support

## Installation

Download the latest DMG from [Releases](https://github.com/ad-repo/adamp/releases).

Follow [r/AdAmp](https://www.reddit.com/r/AdAmp/) for release notifications. Report bugs on [GitHub Issues](https://github.com/ad-repo/adamp/issues) or the subreddit.


### Fixing "App is damaged" or "macOS cannot verify that this app is free from malware" Error

Since the app is in beta testing and not code-signed (it costs $99 a year to sign the app and I am not sure yet I want to pay that yet) macOS Gatekeeper will block it. To fix this:

**Option 1: Terminal (Recommended)**
```bash
xattr -cr /Applications/AdAmp.app
```

**Option 2: System Settings**
1. Try to open AdAmp (it will be blocked)
2. Go to **System Settings → Privacy & Security**
3. Scroll down and click **Open Anyway** next to the AdAmp message
4. Click **Open** in the confirmation dialog

After either option, AdAmp will open normally.

## Requirements

- macOS 14.0 (Sonoma) or later

## Building from Source

Requires Xcode 15.0+ with Command Line Tools and Swift 5.9+.

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
| [FlyingFox](https://github.com/swhitty/FlyingFox) | Embedded HTTP server for local file casting |
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


<img width="375" height="456" alt="Screenshot 2026-01-31 at 10 02 59 PM" src="https://github.com/user-attachments/assets/67a5d8ed-7c43-4222-ad0e-28c8443207e8" />

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

