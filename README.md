# AdAmp

A faithful recreation of the classic Winamp 2.x music player for macOS.

## Features

- **Pixel-perfect UI**: Exact recreation of the classic Winamp interface
- **Full skin support**: Compatible with classic Winamp skins (.wsz files)
- **All classic windows**: Main player, Playlist editor, 10-band Equalizer
- **Window snapping**: Classic Winamp window docking behavior
- **Audio format support**: MP3, FLAC, AAC, WAV, AIFF, ALAC, and more
- **Video format support**: MKV, MP4, MOV, AVI, WebM, HEVC via FFmpeg (KSPlayer)
- **Media library**: Organize and browse your music collection
- **Plex integration**: Stream music and video from your Plex Media Server
- **Casting support**: Cast to Chromecast, Sonos, and DLNA TVs
- **Spectrum analyzer**: Real-time audio visualization

## Screenshots

(Coming soon)

## Requirements

- macOS 12.0 (Monterey) or later
- Apple Silicon or Intel Mac

## Building

### Prerequisites

- Xcode 14.0 or later
- Swift 5.9 or later

### Build Steps

```bash
# Clone the repository
git clone https://github.com/yourusername/AdAmp.git
cd AdAmp

# Build with Swift Package Manager
swift build

# Or run directly
swift run AdAmp
```

### Xcode

You can also open the project in Xcode:

```bash
open Package.swift
```

## Usage

### Basic Controls

| Action | Keyboard Shortcut |
|--------|-------------------|
| Play | X |
| Pause | C |
| Stop | V |
| Previous | Z |
| Next | B |
| Seek backward | ← |
| Seek forward | → |
| Volume up | ↑ |
| Volume down | ↓ |
| Toggle Equalizer | Alt+E |
| Toggle Playlist | Alt+P |
| Toggle Media Library | Cmd+L |
| Toggle Plex Browser | Cmd+P |
| Load file | Cmd+O |

### Media Library Controls

| Action | Keyboard Shortcut |
|--------|-------------------|
| Delete selected from library | Delete |
| Play selected | Enter |
| Navigate | ↑ / ↓ |
| Multi-select | Cmd+Click or Shift+Click |

Right-click in the Media Library for additional options:
- **Play** / **Add to Playlist** - Play or queue selected items
- **Show in Finder** - Reveal the file in Finder
- **Remove from Library** - Remove from library (keeps files on disk)
- **Delete File from Disk** - Permanently delete files (with Trash option)

### Right-Click Context Menu

Right-click on any window (Main, Equalizer, or Playlist) to access the context menu:

- **Play** - Open files or folders
- **Window toggles** - Show/hide Main Window, Equalizer, Playlist Editor
- **Skins** - Load skins from file or from `~/Library/Application Support/AdAmp/Skins/`
- **Options**:
  - Time elapsed/remaining toggle
  - Double Size (2x scaling)
  - Repeat/Shuffle toggles
- **Plex** - Link/unlink Plex account, show Plex Browser
- **Playback** - Transport controls, seek ±5 seconds, skip ±10 tracks
- **Exit** - Quit application

### Loading Skins

1. Download a classic Winamp skin (.wsz file) from [Winamp Skin Museum](https://skins.webamp.org/)
2. Right-click on any window → Skins → Load Skin...
3. Select the .wsz file

Or place skins in `~/Library/Application Support/AdAmp/Skins/` and they will appear in the Skins menu.

### Time Display Modes

The time display can show either:
- **Time elapsed** - Shows current playback position (default)
- **Time remaining** - Shows time left with minus sign

Toggle via right-click → Options → Time elapsed/remaining

### Double Size Mode

Enable 2x scaling via right-click → Options → Double Size. All windows will scale to double their normal size while maintaining pixel-perfect rendering.

### Plex Integration

AdAmp can stream music and video directly from your Plex Media Server:

1. **Link your account**: Right-click → Plex → Link Plex Account... (or Plex menu → Link Plex Account...)
2. **Enter the PIN**: A 4-character code will be displayed
3. **Authorize**: Go to [plex.tv/link](https://plex.tv/link) and enter the code
4. **Browse**: Open the Plex Browser (Cmd+P or View → Plex Browser)
5. **Play**: Click any track, movie, or episode to start playback

**Music Features:**
- Browse by Artists, Albums, or Tracks
- Hierarchical navigation (Artist → Albums → Tracks)
- Add to playlist or play immediately

**Video Features:**
- Browse Movies and TV Shows
- Hierarchical navigation (Show → Seasons → Episodes)
- Dedicated video player window with skinned Winamp-style title bar
- KSPlayer with FFmpeg backend for MKV, WebM, HEVC, and extended codec support
- Fullscreen support, keyboard controls (Space for play/pause, arrow keys to seek)

**General Features:**
- PIN-based authentication (no password entry required)
- Search across all your Plex libraries
- Prefers local server connections for best performance
- Secure token storage in macOS Keychain
- **Play statistics tracking** - Play counts and last played dates sync to Plex

**Requirements:**
- A Plex Media Server with music and/or video libraries
- Network access to your Plex server (local or remote)

### Casting Support

AdAmp can cast Plex content to network devices:

**Supported Devices:**
- **Chromecast** - Google Cast devices (Audio, Video, Ultra)
- **Sonos** - Sonos speakers and soundbars
- **DLNA TVs** - Samsung, LG, Sony, and other DLNA-compatible TVs

**How to Cast:**
1. Start playing a track from Plex
2. Right-click → Casting → Select your device
3. Playback will transfer to the cast device
4. Use Stop Casting to return to local playback

**Features:**
- Automatic device discovery (mDNS for Chromecast, SSDP for UPnP/DLNA)
- Seamless handoff between local and cast playback
- Transport controls (play/pause/stop/seek) forwarded to cast device
- Refresh Devices option to rediscover after network changes

**Limitations:**
- Casting only works with Plex content (HTTP/HTTPS streaming URLs)
- Local files cannot be cast (no built-in HTTP server)
- Some older DLNA TVs may not support all audio formats
- Chromecast requires the device to be on the same local network

**Troubleshooting:**
- If devices don't appear, try Refresh Devices from the Casting menu
- Ensure your Mac and cast devices are on the same network subnet
- Check that local network access is allowed in System Settings → Privacy
- For Chromecast, ensure the device is set up and online
- For Sonos, ensure the speaker is not in a group (standalone mode works best)

## Architecture

```
AdAmp/
├── App/                    # Application lifecycle
├── Audio/                  # AVAudioEngine-based playback + spectrum analysis
├── Casting/                # Cast device discovery and playback
│   ├── CastDevice          # Device models and enums
│   ├── CastManager         # Unified casting interface
│   ├── ChromecastManager   # Chromecast discovery (mDNS) and protocol
│   └── UPnPManager         # Sonos/DLNA discovery (SSDP) and SOAP control
├── Plex/                   # Plex Media Server integration
│   ├── PlexAuthClient      # PIN-based authentication
│   ├── PlexServerClient    # Server API communication
│   ├── PlexManager         # Account & state management
│   └── PlexPlaybackReporter # Play statistics & scrobbling
├── Skin/                   # WSZ skin loading and rendering
├── Windows/                # Window controllers and views
│   ├── MainWindow/         # Main player window
│   ├── Playlist/           # Playlist editor
│   ├── Equalizer/          # 10-band EQ
│   ├── MediaLibrary/       # Local media library browser
│   ├── PlexBrowser/        # Plex content browser (music + video)
│   └── VideoPlayer/        # Video player window (KSPlayer/FFmpeg-based)
├── Data/                   # Models and persistence
│   └── Models/             # Track, Playlist, MediaLibrary, EQPreset, PlexModels
├── Utilities/              # BMP parsing, ZIP extraction, Keychain
└── docs/                   # Development documentation
```

## Development Documentation

**⚠️ IMPORTANT FOR DEVELOPERS/AI AGENTS:**

Before working on skin rendering or UI issues, read:

- **[docs/SKIN_FORMAT_RESEARCH.md](docs/SKIN_FORMAT_RESEARCH.md)** - Comprehensive research on Winamp skin format including:
  - All sprite coordinates from webamp source code
  - EQMAIN.BMP layout and element positions
  - Coordinate system differences (Winamp vs macOS)
  - Known issues and pending work
  - External resource URLs for reference
  - Debugging tips and commands

## Skin Compatibility

AdAmp supports classic Winamp 2.x skins (.wsz files). Key supported features:

- main.bmp - Main window graphics
- cbuttons.bmp - Transport button sprites
- numbers.bmp - LED time display digits
- text.bmp - Scrolling marquee font
- pledit.bmp - Playlist background
- eqmain.bmp - Equalizer background
- pledit.txt - Playlist color configuration
- viscolor.txt - Visualization colors
- region.txt - Non-rectangular window shapes

## Development Status

### Phase 1: Foundation ✅
- [x] Project setup
- [x] Audio engine with AVAudioEngine
- [x] Basic main window
- [x] Basic unit tests for models

### Phase 2: Skin Engine ✅
- [x] WSZ file extraction
- [x] BMP parsing (8/24/32-bit, RLE)
- [x] Complete sprite rendering (SkinRenderer)
- [x] Sprite coordinate definitions (SkinElements)
- [x] Region-based hit testing (SkinRegion)
- [x] Skin-aware main window view
- [x] Skin-aware EQ and Playlist views
- [x] Fallback rendering for missing skin assets

### Phase 3: All Windows ✅
- [x] Complete main window with skin support
- [x] Playlist editor with skin support
- [x] Equalizer with skin support
- [x] Shade mode for all windows (main, EQ, playlist)
- [x] Complete all button interactions

### Phase 4: Features ✅
- [x] Media library with metadata parsing
- [x] Media library window (browse by tracks/artists/albums/genres)
- [x] Window docking improvements (grouped movement)
- [x] Spectrum analyzer visualization
- [x] Plex Media Server integration
  - [x] PIN-based account linking
  - [x] Server discovery and selection
  - [x] Music library browsing (Artists/Albums/Tracks)
  - [x] Video library browsing (Movies/TV Shows/Episodes)
  - [x] Search functionality
  - [x] Streaming audio playback
  - [x] Video player with KSPlayer (MKV/extended codecs) and skinned UI
  - [x] Secure credential storage (Keychain)
- [x] Casting support
  - [x] Chromecast discovery and playback (mDNS)
  - [x] Sonos speaker support (UPnP/SSDP)
  - [x] DLNA TV support (Samsung, LG, Sony, etc.)
  - [x] Unified casting menu
  - [x] Plex URL tokenization for cast devices

### Phase 5: Polish (In Progress)
- [x] Right-click context menu (all windows)
- [x] Time display mode (elapsed/remaining)
- [x] Double size scaling
- [x] Skin directory discovery
- [ ] Extended format support (OGG, Opus)
- [ ] Preferences window
- [ ] DMG distribution

### Future: Expanded Test Coverage
- [ ] BMP Parser tests with real 8/24/32-bit BMPs and RLE compression
- [ ] SkinLoader tests with actual .wsz files
- [ ] Sprite coordinate verification tests
- [ ] M3U/PLS import round-trip tests
- [ ] Region hit testing tests
- [ ] Window snapping logic tests

## License

This project is open source and uses the following licensed components:

- **KSPlayer** (GPL-3.0) - Video playback with FFmpeg backend for extended codec support

This project is not affiliated with Winamp LLC or Radionomy Group.

## Acknowledgments

- [Webamp](https://github.com/captbaritone/webamp) - Excellent reference for skin parsing
- [Winamp Skin Museum](https://skins.webamp.org/) - Skin archive
- Original Winamp by Nullsoft
