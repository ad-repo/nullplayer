# NullPlayer

## A throwback open-source music player for macOS written in Swift, with a first-class headless CLI for automation, multi-source playback, and casting across Sonos, Chromecast, UPnP/DLNA, local media servers, and internet radio.

## This is a 100% clean room hobby project is not affiliated with Winamp, Nullsoft, Sonos, Plex, Radionomy Group or anyone else.

## **If you enjoy NullPlayer, please ⭐ star ⭐ the project on GitHub!**

![MixCollage_player](https://github.com/user-attachments/assets/5d29303e-2910-4f1d-b5ac-b65b7f17a34f)
![MixCollage-12-Mar-2026-03-38-PM-191](https://github.com/user-attachments/assets/b26003a8-bb5d-45ca-9504-2a3e13079fe9)
<img width="733" height="184" alt="Screenshot 2026-04-05 at 8 52 33 PM" src="https://github.com/user-attachments/assets/3f602a8d-b9bb-43d1-af75-89e4fcb06d08" />
<img width="1389" height="660" alt="Screenshot 2026-04-05 at 8 54 54 PM" src="https://github.com/user-attachments/assets/4f2dc824-e90e-4f28-b151-02dc05727cdf" />
<img width="1383" height="632" alt="Screenshot 2026-04-05 at 8 56 50 PM" src="https://github.com/user-attachments/assets/18ccac12-28b2-4a8c-9cea-b742d325c610" />
<img width="1266" height="559" alt="Screenshot 2026-04-05 at 9 14 34 PM" src="https://github.com/user-attachments/assets/92104d80-c6d2-43f3-bad0-cf626c009919" />
<img width="1646" height="844" alt="Screenshot 2026-04-05 at 9 21 27 PM" src="https://github.com/user-attachments/assets/8d08d61c-66fb-4ec3-8197-cd2df614444b" />


## Features

- First-class headless CLI for terminal workflows and automation pipelines
- Scriptable media control across multiple sources and playback targets
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
- Modern mode with 21-band EQ implementation, Classic mode with standard 10-band EQ
- Classic window snapping and docking behavior
- Audio playback: MP3, FLAC, AAC, WAV, AIFF, ALAC, OGG
- Video playback: MKV, MP4, MOV, AVI, WebM, HEVC (KSPlayer/FFmpeg)
- Gapless playback for seamless track transitions
- Sweet Fades (crossfade) with configurable fade duration
- Sleep Timer — timed (5 min – 12 hr with volume fade-out), end of current track, or end of queue
- Media Drag and drop support
- Album/Cover/Movie art browser with visualizations
- Internet radio (Shoutcast/Icecast) with live metadata and auto-reconnect
- AirPlay and Casting to Chromecast, Sonos (multi-room), and DLNA devices
- Cast local files, Jellyfin/Emby/Navidrome/Subsonic streams, and internet radio to Sonos
- macOS Now Playing integration (Control Center, Touch Bar, AirPods controls)
- [Discord Music Presence](https://github.com/ungive/discord-music-presence) support
- Headless CLI mode for querying libraries, starting playback, and routing to local outputs or cast devices (no GUI, no Dock icon)

## Installation

Download the latest DMG from [Releases](https://github.com/ad-repo/nullplayer/releases).

Follow [r/NullPlayer](https://www.reddit.com/r/NullPlayer/) for release notifications. Report bugs on [GitHub Issues](https://github.com/ad-repo/nullplayer/issues) or the subreddit.

### Optional command-line launcher

If you want to use NullPlayer as a scriptable command in terminal workflows or automation pipelines without digging into `NullPlayer.app/Contents/MacOS`, the DMG includes:

- `nullplayer` — launcher wrapper
- `Install NullPlayer CLI.command` — one-click installer for `/usr/local/bin/nullplayer`

Install flow:

```bash
open "/Volumes/NullPlayer/Install NullPlayer CLI.command"
nullplayer --cli --help
```

The launcher looks for:

- `/Applications/NullPlayer.app`
- `~/Applications/NullPlayer.app`


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

Library data is stored as a SQLite database at `~/Library/Application Support/NullPlayer/library.db`.

**Backup & Restore API** (`MediaLibrary.swift`):

| Function | Description |
|----------|-------------|
| `backupLibrary(customName:)` | Creates timestamped `.db` backup, returns URL |
| `restoreLibrary(from:)` | Restores from backup (auto-backs up current first) |
| `listBackups()` | Returns backup URLs sorted newest first |
| `deleteBackup(at:)` | Deletes a backup file |

Backups are stored in `~/Library/Application Support/NullPlayer/Backups/`.

## CLI Mode

NullPlayer includes a first-class headless CLI mode for browsing, querying, playing, and routing media entirely from the terminal. It is designed to work as a scriptable command in automation pipelines: resolve media from multiple sources, pick a local output or cast target, then hand off playback without opening the GUI.

This is not just a hidden debug flag. `nullplayer` is a supported command surface for:

- querying and searching local, Plex, Subsonic/Navidrome, Jellyfin, Emby, and radio sources
- starting playback from those sources with a stable command-line interface
- routing playback to local outputs or casting to Sonos, Chromecast, and UPnP/DLNA devices
- emitting machine-friendly query output with `--json`

```bash
nullplayer --cli [OPTIONS]
```

### Multi-source media control

`nullplayer` can act as a scriptable media control command for automation pipelines, connecting multiple media sources to multiple playback targets.

Supported media sources include:

- local library
- Plex
- Subsonic / Navidrome
- Jellyfin
- Emby
- internet radio

Supported playback targets include:

- local audio output devices
- Sonos
- Chromecast
- UPnP / DLNA

Typical automation shape:

```bash
nullplayer --cli --source plex --playlist "Morning Rotation" --cast "Living Room" --cast-type sonos
nullplayer --cli --source local --artist "Boards of Canada" --output "MacBook Pro Speakers"
nullplayer --cli --station "KEXP" --source radio --cast "Kitchen Speaker" --cast-type chromecast
```

### Query commands (print results and exit)

```bash
nullplayer --cli --list-sources                          # show configured sources
nullplayer --cli --list-artists --source plex            # list artists
nullplayer --cli --list-albums  --source local           # list albums
nullplayer --cli --list-tracks  --source subsonic        # list tracks
nullplayer --cli --list-genres  --source local           # list genres
nullplayer --cli --list-playlists --source jellyfin      # list playlists
nullplayer --cli --list-stations                         # list internet radio stations
nullplayer --cli --list-eq                               # list EQ presets
nullplayer --cli --list-outputs                          # list audio output devices
nullplayer --cli --list-devices                          # list cast devices
nullplayer --cli --search "radiohead" --source local     # search library
nullplayer --cli --list-artists --source plex --json     # JSON output
```

### Playback

```bash
nullplayer --cli --source local --artist "Pink Floyd"
nullplayer --cli --source plex --album "OK Computer" --shuffle
nullplayer --cli --source local --genre "Jazz" --repeat-all
nullplayer --cli --station "KEXP" --source radio
nullplayer --cli --source local --radio artist --artist "Björk"
nullplayer --cli --source local --volume 80 --eq "Rock"
nullplayer --cli --source jellyfin --playlist "Late Night" --cast "Bedroom" --cast-type sonos
nullplayer --cli --source local --album "Selected Ambient Works 85-92" --cast "Office TV" --cast-type dlna
```

### Volume control

Set the initial playback volume at launch:

```bash
nullplayer --cli --source local --artist "Björk" --volume 80
nullplayer --cli --source plex --playlist "Focus" --cast "Living Room" --cast-type sonos --volume 35
```

During playback:

- `↑` increases volume by 5%
- `↓` decreases volume by 5%
- `m` toggles mute

When casting is active, the same CLI volume control path is used for the cast target as well.

### Keyboard controls (during playback)

| Key | Action |
|-----|--------|
| `Space` | Pause/Resume |
| `q` | Quit |
| `>` / `<` | Next / Previous track |
| `→` / `←` | Seek forward / backward 10s |
| `↑` / `↓` | Volume up / down |
| `s` | Toggle shuffle |
| `r` | Cycle repeat (off → all → one) |
| `m` | Toggle mute |
| `i` | Show track info |

See `nullplayer --cli --help` for the full flag reference. If you have not installed the launcher yet, the underlying app binary is still available at `NullPlayer.app/Contents/MacOS/NullPlayer`.

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
