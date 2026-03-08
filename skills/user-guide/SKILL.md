---
name: user-guide
description: User-facing features, menus, keyboard shortcuts, and functionality overview. Use when documenting features, understanding user workflows, or explaining capabilities to users.
---

# NullPlayer User Guide

A faithful recreation of Winamp 2.x for macOS with Plex/Jellyfin/Subsonic integration, ProjectM visualizations, and casting support.

## System Requirements

- **macOS 14.0 (Sonoma)** or later
- Internet connection (for streaming and skin downloads)

## Core Features

### Windows

| Window | Description | Toggle |
|--------|-------------|--------|
| **Main Window** | Primary player with transport controls | Always visible |
| **Playlist Editor** | Track list and playlist management | PL button or context menu |
| **Equalizer** | 10-band graphic EQ with presets | EQ button or context menu |
| **Spectrum Analyzer** | Large spectrum visualization | Context menu or Window menu |
| **Library Browser** | Browse Plex/Jellyfin/Subsonic and local media | Logo button or context menu |
| **ProjectM** | Real-time audio visualizations | Menu button or context menu |

### Window Docking

Windows automatically snap together when dragged near each other:
- Edge-to-edge snapping
- Screen edge snapping
- Group movement (docked windows move together)
- Group minimize (attached windows minimize together)
- **Snap to Default** (context menu) resets all windows

### Main Window Elements

| Element | Description |
|---------|-------------|
| **Time Display** | Elapsed/remaining time (click to toggle) |
| **Track Marquee** | Scrolling song title/artist |
| **Bitrate** | Track bitrate in kbps |
| **Sample Rate** | Audio sample rate in kHz |
| **Stereo Indicator** | Shows mono/stereo status |
| **Cast Indicator** | Shows when casting to external device |
| **Spectrum Analyzer** | Real-time frequency visualization |

### Sliders

- **Position Bar**: Seek through track
- **Volume Slider**: Adjust playback volume (0-100%)
- **Balance Slider**: Pan audio left/right

### Transport Buttons

Previous, Play, Pause, Stop, Next, Eject (open file dialog)

### Toggle Buttons

- **Shuffle**: Random playback order
- **Repeat**: Loop playlist
- **EQ**: Show/hide Equalizer
- **PL**: Show/hide Playlist

Modern UI adds: **2X** (Double Size), **HT** (Hide Title Bars), **CA** (Cast), **pM** (ProjectM), **SP** (Spectrum), **LB** (Library)

## Media Sources

### Plex Integration
- Browse music, movies, and TV shows
- Album artwork and metadata
- Radio features (Track/Artist/Album/Genre/Decade/Rating/Hits/Deep Cuts)
- Automatic scrobbling (90% or end, min 30s)
- Video playback with casting

### Jellyfin Integration
- Browse music and video libraries
- **Library selector** in status bar: click "Lib:" to switch library. Mode-aware — shows music library picker in music tabs (Artists/Albums/Tracks/Plists) and video library picker in Movies/Shows tabs. "All" option browses across all libraries.
- Rating scale: 0-100% (0-10 internal)
- Scrobbling (50% or 4 minutes for audio, 90% for video)

### Navidrome/Subsonic
- Browse artists, albums, playlists
- **Music folder selector** in status bar: click "Lib:" to filter by music folder. "All" shows content from all folders.
- Token authentication
- Scrobbling (50% or 4 minutes)
- Casting support via proxy

### Internet Radio
- Shoutcast/Icecast streaming
- Live song metadata (ICY + SomaFM fallback when ICY is missing)
- Auto-reconnect on disconnect
- Large bundled global station catalog (including full SomaFM channel set)
- Curated regional additions (African, Caribbean, South American, European, Indian, Thai) plus expanded jazz streams
- Station management (add/edit/delete/import)
- Internet-radio-only folder organization (smart folders + custom folders)
- 5-star station ratings (persisted per station URL)
- Casting to Sonos
- Playback Options now groups all source histories under a single **Radio History** submenu

### Local Files
Drag & drop or use File menu. Supports: MP3, M4A, AAC, WAV, AIFF, FLAC, OGG, ALAC

### Local Library Browser
Switch the Library Browser source to "Local" to manage a persistent media library.

**+ADD menu** (three options):
- **Add Files...** — file picker filtered to audio formats
- **Add Video Files...** — file picker filtered to video formats (`.mp4`, `.mkv`, `.mov`, etc.); files are classified as movies or TV episodes automatically (SxxExx naming / iTunes metadata)
- **Add Folder...** — folder picker; scans immediately for audio and video files, and saves the folder as a "remembered folder"

**Watch folders (remembered folders):**
- Folders added via "Add Folder..." are persisted in the library database
- They are **not** monitored automatically — there is no filesystem watcher
- Press the **⟳ refresh button** to re-scan all remembered folders and pick up newly added files
- Duplicate detection prevents re-adding files already in the library

**Tabs:** Artists, Albums, Tracks, Playlists, Movies, Shows

## Output Devices & Casting

### Sonos
- Multi-room casting
- Group management while casting
- Local file streaming via embedded server
- Network stream proxying for Subsonic/Jellyfin

### Chromecast
- Audio and video casting
- Position synchronization
- Buffering state handling

### DLNA
- UPnP device discovery
- Video casting to TVs

### AirPlay
- Native macOS AirPlay support
- Auto-detected output devices

## Audio Features

### Equalizer
- 10-band graphic EQ (-12dB to +12dB per band)
- Preamp control
- Anti-clipping limiter
- **Modern UI**: 7 compact preset toggle buttons in the button row (FLAT, ROCK, POP, ELEC, HIP, JAZZ, CLSC); clicking a preset auto-enables EQ if off; clicking the active preset deactivates it (reverts to flat); dragging any fader clears the active preset
- **Modern UI**: double-click a fader to reset that band only to 0 dB; double-click preamp to reset preamp only
- **Modern UI**: AUTO button applies genre-based preset for the current track and auto-enables EQ if off
- **Classic UI**: PRESETS dropdown with all presets including "I'm Old" / "I'm Young"

### Playback Options
- **Gapless Playback**: Seamless track transitions (local files)
- **Sweet Fades**: Crossfade between tracks (1-10s duration)
- **Volume Normalization**: Consistent loudness (-14dB target)
- **Remember State on Quit**: Restore session on launch

### Spectrum Modes
- **Accurate**: True signal levels (40dB range)
- **Adaptive**: Global adaptive normalization
- **Dynamic**: Per-region normalization (bass/mid/treble)

## Visualizations

### Main Window GPU Modes
Spectrum, Fire, Enhanced, Ultra, JWST, Lightning, Matrix, Snow (double-click to cycle)

### Album Art Visualizer
30 effects transforming album artwork based on audio

### ProjectM/MilkDrop
100+ bundled presets, OpenGL rendering, fullscreen support

### Spectrum Analyzer Window
55 bars, 8 quality modes (Winamp/Enhanced/Ultra/Fire/JWST/Lightning/Matrix/Snow)

## Skins

### Loading Skins
- **Skins > Load Skin...** to open `.wsz` file
- Place in `~/Library/Application Support/NullPlayer/Skins/` for auto-discovery
- Bundled skins: Silver (default), Classic, Dark, Light

### Modern UI Mode
- **Options > Use Modern UI** to enable modern skin engine
- Requires restart to switch modes
- Modern skins use `skin.json` format
- Bundled modern skins: NeonWave (default), Skulls

### Double Size Mode
- Toggle via **2X button** or context menu → **Double Size**
- Scales all windows by 2x
- Persists across restarts
- **Modern UI**: toggles live instantly
- **Classic UI**: requires a restart (dialog appears before any UI change)

### Hide Title Bars (Modern UI)
- Toggle via context menu or HT button on the main window
- **HT Off (default)**: EQ/Playlist/Spectrum hide titlebars when docked — this is always active, even with HT off
- **HT On**: All 6 windows (main, EQ, playlist, spectrum, ProjectM, library browser) hide titlebars; content expands to fill the reclaimed space
- Preserves the border line (titlebar area collapses to border width, not 0)

## Keyboard Shortcuts

### Playback
- **Space**: Play/Pause
- **V**: Stop
- **B**: Next track
- **Z**: Previous track
- **←/→**: Seek backward/forward 5s
- **↑/↓**: Volume up/down

### Windows
- **Cmd+L**: Show/hide Playlist
- **Cmd+G**: Show/hide Equalizer
- **Cmd+S**: Show/hide Spectrum Analyzer (modern UI) or Library Browser (classic UI)
- **Cmd+K**: Show/hide ProjectM
- **Cmd+J**: Jump to current track in playlist

### Playlist
- **Enter**: Play selected track
- **Delete**: Remove selected tracks
- **Cmd+A**: Select all

### Library Browser
- **Enter**: Play Now (insert and play)
- **Shift+Enter**: Play Next (insert after current, no auto-play if empty)
- **Option+Enter**: Add to Queue (append, no auto-play if empty)
- **Right Arrow**: Expand item (artists, albums, playlists, shows, seasons); if already expanded, move to first child
- **Left Arrow**: Collapse expanded item; if not expanded, jump to parent item
- **Tab / Shift+Tab**: Cycle forward/backward through tabs (Artists → Albums → Plists → Movies → Shows → Search → Radio)
- **Space**: Play/Pause
- **Type letters**: Jump to first matching item by name (type-ahead, clears after ~1s); Backspace removes last character, Escape clears immediately
- **Cmd+F**: Focus search field
- **Escape**: Clear search (in search tab) or clear type-ahead buffer

## Data Storage

| Data | Location |
|------|----------|
| Playlists | `~/Library/Application Support/NullPlayer/Playlists/` |
| Skins | `~/Library/Application Support/NullPlayer/Skins/` |
| ProjectM Presets | `~/Library/Application Support/NullPlayer/Presets/` |
| Settings | `~/Library/Preferences/com.nullplayer.NullPlayer.plist` |
| Credentials | macOS Keychain |
| Local Library DB | `~/Library/Application Support/NullPlayer/library.db` |

## Additional Documentation

For comprehensive documentation, see:
- [features-reference.md](features-reference.md) - Detailed window/feature documentation
- [keyboard-shortcuts.md](keyboard-shortcuts.md) - Complete keyboard shortcut reference

## Quick Tips

- **Drag & drop** files/folders onto the player to add them
- **Right-click** anywhere for the context menu
- **Double-click** title bars for shade mode
- **Shift+Click** for multi-select in playlist/browser
- **Cmd+J** to jump to currently playing track
- Windows **dock automatically** when dragged near each other
- **Double Size** (2X) is available in both modern and classic UI; classic requires restart
