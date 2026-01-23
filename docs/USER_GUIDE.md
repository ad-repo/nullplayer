# AdAmp User Guide

A faithful recreation of Winamp 2.x for macOS with Plex Media Server integration, Milkdrop visualizations, and casting support.

## Table of Contents

- [System Requirements](#system-requirements)
- [Getting Started](#getting-started)
- [Main Player Window](#main-player-window)
- [Playlist Editor](#playlist-editor)
- [Equalizer](#equalizer)
- [Library Browser](#library-browser)
- [Milkdrop Visualizations](#milkdrop-visualizations)
- [Art Visualizer](#art-visualizer)
- [Video Player](#video-player)
- [Plex Integration](#plex-integration)
- [Navidrome/Subsonic Integration](#navidromesubsonic-integration)
- [Output Devices & Casting](#output-devices--casting)
- [Skins](#skins)
- [Keyboard Shortcuts](#keyboard-shortcuts)
- [Context Menu Reference](#context-menu-reference)
- [Local Library Management](#local-library-management)
- [Audio Features](#audio-features)
- [File Format Support](#file-format-support)
- [Data Storage](#data-storage)

---

## System Requirements

- **macOS 13.0 (Ventura)** or later
- Internet connection (for Plex streaming and skin downloads)

---

## Getting Started

### First Launch

1. Launch AdAmp to see the classic Winamp 2.x main player window
2. Right-click anywhere on the player to access the context menu
3. Use **Play > File...** or **Play > Folder...** to add music
4. Or connect your **Plex** account to browse your media library

### Window Layout

AdAmp consists of several windows that can be shown/hidden:

| Window | Description | Toggle |
|--------|-------------|--------|
| **Main Window** | Primary player with transport controls | Always visible |
| **Playlist Editor** | Track list and playlist management | PL button or context menu |
| **Equalizer** | 10-band graphic EQ with presets | EQ button or context menu |
| **Library Browser** | Browse Plex and local media | Logo button or context menu |
| **Milkdrop** | Real-time audio visualizations | Menu button or context menu |

### Window Snapping & Docking

Windows automatically snap together when dragged near each other:
- **Edge-to-edge snapping**: Windows dock when edges touch
- **Screen edge snapping**: Windows snap to screen borders
- **Group movement**: Docked windows (Main, Playlist, EQ) move together when dragged

**Snap to Default** (context menu) resets all windows to their default positions.

---

## Main Player Window

The main window provides core playback controls and track information.

### Display Elements

| Element | Description |
|---------|-------------|
| **Time Display** | Shows elapsed or remaining time (click to toggle) |
| **Track Info Marquee** | Scrolling song title/artist |
| **Bitrate Display** | Track bitrate in kbps |
| **Sample Rate** | Audio sample rate in kHz |
| **Stereo Indicator** | Shows mono/stereo status |
| **Cast Indicator** | Shows when casting to external device |
| **Spectrum Analyzer** | Real-time frequency visualization |
| **Playback Status** | Play/Pause/Stop indicator |

### Sliders

| Slider | Function |
|--------|----------|
| **Position Bar** | Seek through the track |
| **Volume Slider** | Adjust playback volume (0-100%) |
| **Balance Slider** | Pan audio left/right |

### Transport Buttons

| Button | Function |
|--------|----------|
| **Previous** | Go to previous track (or rewind in video) |
| **Play** | Start playback |
| **Pause** | Pause playback |
| **Stop** | Stop playback and reset position |
| **Next** | Go to next track (or skip forward in video) |
| **Eject** | Open file dialog to add files |

### Toggle Buttons

| Button | Function |
|--------|----------|
| **Shuffle** | Enable random playback order |
| **Repeat** | Loop playlist continuously |
| **EQ** | Show/hide Equalizer window |
| **PL** | Show/hide Playlist Editor |

### Title Bar Buttons

| Button | Function |
|--------|----------|
| **Logo (top-left)** | Open Library Browser |
| **Menu** | Open Milkdrop visualizations |
| **Minimize** | Minimize to dock |
| **Shade** | Toggle compact "shade" mode |
| **Close** | Quit AdAmp |

### Shade Mode

Double-click the title bar (or click the shade button) to enter **Shade Mode** - a compact horizontal view showing:
- Track title with scrolling marquee
- Current time display
- Basic window controls

Double-click again to return to normal mode.

---

## Playlist Editor

The Playlist Editor manages your playback queue.

### Track List

- **Click** a track to select it
- **Double-click** to play immediately
- **Shift+Click** to extend selection
- **Cmd+Click** to toggle individual selection
- **Scroll wheel** to navigate long lists
- **Drag & drop** files to add them

### Bottom Bar Information

The bottom bar displays:
- **Remaining tracks** and **countdown time** (updates during playback)
- **Current playback position** (minutes:seconds)

### Mini Transport Controls

Small transport buttons in the bottom bar:
- Previous, Play, Pause, Stop, Next, Open

### Button Menus

**ADD Button:**
- Add URL... - Stream from a URL
- Add Directory... - Add all audio from a folder
- Add Files... - Select individual files

**REM Button:**
- Remove All - Clear entire playlist
- Crop Selection - Keep only selected tracks
- Remove Selected - Delete selected tracks
- Remove Dead Files - Remove missing files

**SEL Button:**
- Invert Selection
- Select None
- Select All (Cmd+A)

**MISC Button:**
- Sort submenu (by Title, Filename, Path)
- Randomize - Shuffle playlist order
- Reverse - Reverse playlist order
- File Info... - Show track metadata
- Playlist Options...

**LIST Button:**
- New Playlist - Clear and start fresh
- Save Playlist... - Export as .m3u file
- Load Playlist... - Import .m3u/.m3u8 file

### Shade Mode

Double-click the title bar for a compact horizontal playlist view.

---

## Equalizer

The 10-band graphic equalizer lets you shape your sound.

### Frequency Bands

| Band | Frequency |
|------|-----------|
| 1 | 60 Hz (Low Shelf) |
| 2 | 170 Hz |
| 3 | 310 Hz |
| 4 | 600 Hz |
| 5 | 1 kHz |
| 6 | 3 kHz |
| 7 | 6 kHz |
| 8 | 12 kHz |
| 9 | 14 kHz |
| 10 | 16 kHz (High Shelf) |

### Controls

- **ON/OFF** - Enable/disable EQ processing
- **AUTO** - Automatic EQ adjustment (reserved)
- **PRESETS** - Load pre-configured EQ settings
- **Preamp Slider** - Global gain adjustment (-12dB to +12dB)
- **Band Sliders** - Per-frequency adjustment (-12dB to +12dB)

### EQ Graph

The graph displays your current EQ curve with color coding:
- **Red** (top) - Boost (+12dB)
- **Yellow** (middle) - Flat (0dB)
- **Green** (bottom) - Cut (-12dB)

### Presets

Built-in presets include:
- **Flat** - All bands at 0dB
- **i'm old** - High frequency boost (+6dB at 16kHz)
- **i'm young** - Bass boost (+6dB at 60Hz)

### Anti-Clipping

A transparent limiter prevents distortion when applying boosts:
- Threshold: -1dB
- Fast attack (1ms), natural release (50ms)

### Shade Mode

Double-click the title bar for a compact view.

---

## Library Browser

The unified Library Browser provides access to both **Plex media** and **local files**.

### Navigation

- **Artists** - Browse by artist
- **Albums** - Browse by album with artwork
- **Playlists** - Plex playlists and smart mixes
- **Local Library** - Your imported local files

### Plex Features

When connected to Plex:
- Browse music, movies, and TV shows
- View album artwork
- Play tracks directly or add to playlist
- Full video playback support
- Automatic play statistics (scrobbling)

### Album Art Background

Enable **Browser Album Art Background** in Playback Options to show a blurred artwork background while browsing.

### Art Visualizer

When viewing album art, click the **VIS** button to open the Art Visualizer with audio-reactive effects.

---

## Milkdrop Visualizations

AdAmp includes projectM-powered Milkdrop visualizations with 100+ bundled presets.

### Opening Milkdrop

- Click the **Menu button** (hamburger icon) on the main window
- Or use the context menu: **Milkdrop**
- Or keyboard: **F** to toggle fullscreen when focused

### Keyboard Controls

| Key | Action |
|-----|--------|
| **F** | Toggle fullscreen mode |
| **Escape** | Exit fullscreen |
| **→** (Right) | Next preset (smooth transition) |
| **←** (Left) | Previous preset (smooth transition) |
| **Shift+→** | Next preset (hard cut) |
| **Shift+←** | Previous preset (hard cut) |
| **R** | Random preset (smooth) |
| **Shift+R** | Random preset (hard cut) |
| **L** | Toggle preset lock (stay on current) |

### Custom Presets

Add your own MilkDrop/projectM presets (.milk files):

1. **Visualizations > Add Presets Folder...**
2. Select a folder containing .milk files
3. **Rescan Presets** to reload

Manage custom folders:
- **Show Custom Presets Folder** - Open in Finder
- **Remove Custom Folder** - Stop using custom presets
- **Show Bundled Presets** - View included presets

### Idle Mode

When audio is not playing, the visualization automatically enters a calmer "idle mode" with reduced beat sensitivity.

---

## Art Visualizer

The Art Visualizer transforms album artwork with audio-reactive shader effects.

### Opening

1. Navigate to an album in the Library Browser
2. Switch to album art view
3. Click the **VIS** button

### Effect Presets

| Effect | Description |
|--------|-------------|
| **Clean** | Original artwork, no effects |
| **Subtle Pulse** | Gentle brightness/scale pulse on beats |
| **Liquid Dreams** | Flowing displacement with color shifts |
| **Glitch City** | Heavy RGB split and block glitches |
| **Cosmic Mirror** | Kaleidoscope with chromatic aberration |
| **Deep Bass** | Intense displacement on low frequencies |

### Keyboard Controls

| Key | Action |
|-----|--------|
| **Escape** | Close window (or exit fullscreen) |
| **Enter** | Toggle fullscreen |
| **←/→** | Cycle through effects |
| **↑/↓** | Adjust effect intensity |

---

## Video Player

AdAmp supports video playback for Plex movies and TV shows.

### Playing Video

- Browse movies/TV shows in the Library Browser
- Double-click or select **Play** to open the video player
- Video playback automatically pauses any audio playback

### Controls

Hover over the video to reveal controls:
- **Play/Pause** button
- **Skip backward** (10 seconds)
- **Skip forward** (10 seconds)
- **Seek slider** - Drag to jump to any position
- **Fullscreen** toggle

Controls auto-hide after 3 seconds during playback.

### Keyboard Controls

| Key | Action |
|-----|--------|
| **Space** | Toggle play/pause |
| **F** | Toggle fullscreen |
| **Escape** | Exit fullscreen or close |
| **←** | Skip back 10 seconds |
| **→** | Skip forward 10 seconds |

### Main Window Integration

While video plays:
- Main window shows video title and time
- Transport buttons control video playback
- Position slider seeks within video

---

## Plex Integration

Connect AdAmp to your Plex Media Server for streaming access.

### Linking Your Account

1. Open context menu > **Plex > Link Plex Account...**
2. Enter the PIN code shown at **plex.tv/link**
3. Wait for authentication to complete

### Managing Servers

Once linked:
- **Plex > Servers** - Switch between multiple servers
- **Plex > Libraries** - Select music/video libraries
- **Plex > Refresh Servers** - Update server list

### Unlinking

**Plex > Unlink Account** removes your Plex credentials from AdAmp.

### Play Statistics

AdAmp reports playback to Plex:
- **Now Playing** - Appears in other Plex clients
- **Play count** - Increments when track finishes
- **Last played date** - Updated on completion

A track is "scrobbled" when:
- At least 30 seconds have played, AND
- 90% completion OR track finishes naturally

---

## Navidrome/Subsonic Integration

AdAmp supports Navidrome, Subsonic, and other Subsonic-compatible music servers.

### Adding a Server

1. Open context menu > **Navidrome/Subsonic > Add Server...**
2. Enter server details:
   - **Name**: Display name for the server
   - **URL**: Server address (e.g., `http://localhost:4533` or `https://music.example.com`)
   - **Username**: Your server username
   - **Password**: Your server password
3. Click **Test Connection** to verify (optional)
4. Click **Save** to add and connect

### Managing Servers

- **Navidrome/Subsonic > Servers** - Switch between multiple servers
- **Navidrome/Subsonic > Manage Servers...** - Add, edit, or remove servers
- **Navidrome/Subsonic > Disconnect** - Disconnect from current server
- **Navidrome/Subsonic > Refresh Library** - Re-fetch artists and albums

### Browsing Content

Once connected, use the Library Browser to browse:
- Artists and their albums
- Albums (sorted alphabetically, by year, etc.)
- Search across your library
- Playlists from your server

Select **Subsonic: [Server Name]** from the source dropdown in the Library Browser.

### Play Statistics

AdAmp reports playback to Subsonic servers:
- **Now Playing** - Shows what's currently playing on the server
- **Play count** - Increments when track is scrobbled

A track is "scrobbled" when:
- **50% of the track has played**, OR
- **4 minutes have played** (whichever comes first)

This follows standard scrobbling rules used by Last.fm and other services.

### Favorites

Right-click tracks, albums, or artists to add them to your favorites (starred items) on the server.

---

## Output Devices & Casting

### Local Audio

**Output Devices > Local Audio** lists:
- **System Default** - Follow macOS sound settings
- Connected audio devices (speakers, headphones, USB DACs)

### AirPlay

**Output Devices > AirPlay** shows:
- **Connected** devices (select directly)
- **Available** devices (connect via Sound Settings first)

Click **Sound Settings...** to manage AirPlay connections.

### Cast Devices

**Output Devices > Cast Devices** discovers:
- **Chromecast** - Google Cast speakers and displays
- **Sonos** - Sonos speakers on your network
- **TVs (DLNA)** - DLNA-compatible televisions

To cast:
1. Start playing audio in AdAmp
2. Select a cast device from the menu
3. **Stop Casting** to return to local playback

**Refresh Devices** rescans your network.

---

## Skins

AdAmp supports classic Winamp 2.x skins (.wsz files).

### Loading Skins

- **Skins > Load Skin...** - Select a .wsz file
- **Skins > Get More Skins...** - Opens [Winamp Skin Museum](https://skins.webamp.org/)
- **&lt;Base Skin 1/2/3&gt;** - Built-in default skins

### Managing Skins

Downloaded skins appear in the Skins menu if placed in:
```
~/Library/Application Support/AdAmp/Skins/
```

### Lock Browser/Milkdrop to Default

Enable this option to keep the Library Browser and Milkdrop windows using the default skin regardless of main player skin.

---

## Keyboard Shortcuts

### Main Window

| Key | Action |
|-----|--------|
| **Space** | Play/Pause |
| **X** | Play |
| **C** | Pause |
| **V** | Stop |
| **Z** | Previous track |
| **B** | Next track |
| **←** | Seek back 5 seconds |
| **→** | Seek forward 5 seconds |
| **↑** | Volume up |
| **↓** | Volume down |

### Playlist Editor

| Key | Action |
|-----|--------|
| **Delete** | Remove selected tracks |
| **Enter** | Play selected track |
| **Cmd+A** | Select all |

### Video Player

| Key | Action |
|-----|--------|
| **Space** | Play/Pause |
| **F** | Toggle fullscreen |
| **Escape** | Exit fullscreen / Close |
| **←** | Skip back 10 seconds |
| **→** | Skip forward 10 seconds |

### Milkdrop

| Key | Action |
|-----|--------|
| **F** | Toggle fullscreen |
| **Escape** | Exit fullscreen |
| **→** | Next preset |
| **←** | Previous preset |
| **Shift+→** | Next preset (hard cut) |
| **Shift+←** | Previous preset (hard cut) |
| **R** | Random preset |
| **Shift+R** | Random preset (hard cut) |
| **L** | Toggle preset lock |

### Art Visualizer

| Key | Action |
|-----|--------|
| **Escape** | Close / Exit fullscreen |
| **Enter** | Toggle fullscreen |
| **←/→** | Cycle effects |
| **↑/↓** | Adjust intensity |

---

## Context Menu Reference

Right-click anywhere on AdAmp windows to access:

### Play
- **File...** - Open file dialog
- **Folder...** - Open folder dialog

### Window Toggles
- Main Window
- Equalizer
- Playlist Editor
- Library Browser
- Milkdrop

### Skins
- Load Skin...
- Get More Skins...
- Base skins (1, 2, 3)
- Lock Browser/Milkdrop to Default
- Available skins list

### Visualizations
- Preset count info
- Add Presets Folder...
- Show Custom Presets Folder
- Remove Custom Folder
- Rescan Presets
- Show Bundled Presets

### Playback Options
- Time elapsed / Time remaining
- Repeat
- Shuffle
- Gapless Playback
- Volume Normalization
- Browser Album Art Background
- Remember State on Quit

### Local Library
- Track count
- Backup Library...
- Restore Library (submenu)
- Show Library in Finder
- Show Backups Folder
- Clear Library...

### Plex
- Account status
- Link/Unlink Account
- Servers (submenu)
- Libraries (submenu)
- Refresh Servers
- Show Plex Browser

### Output Devices
- Local Audio devices
- AirPlay devices
- Cast Devices (Chromecast, Sonos, DLNA)

### Window Controls
- Always on Top
- Snap to Default

### Exit
- Quit AdAmp

---

## Local Library Management

### Library Storage

Library data is stored at:
```
~/Library/Application Support/AdAmp/library.json
```

### Backup & Restore

**Local Library > Backup Library...** creates a timestamped backup.

**Local Library > Restore Library** offers:
- **From File...** - Select any backup file
- **Recent Backups** - Quick access to last 10 backups

Backups are stored in:
```
~/Library/Application Support/AdAmp/Backups/
```

A backup is automatically created before:
- Restoring a backup
- Clearing the library

### Clear Library

**Local Library > Clear Library...** removes all tracks from the library.
- Creates automatic backup first
- Does NOT delete files from disk

---

## Audio Features

### Gapless Playback

**Playback Options > Gapless Playback** enables seamless transitions:
- Next track is pre-scheduled during playback
- Works with local files only (not streaming)
- Not compatible with Repeat Single mode

### Volume Normalization

**Playback Options > Volume Normalization** adjusts loudness:
- Target: -14dB (Spotify standard)
- Analyzes up to 30 seconds per track
- Gain clamped to ±12dB
- Headroom protection prevents clipping
- Local files only

### Spectrum Analyzer

The main window displays real-time frequency analysis:
- 75 frequency bands (20Hz - 20kHz, logarithmic)
- 512-point FFT (~11.6ms latency at 44.1kHz)
- Fast attack, slow decay smoothing

### Remember State on Quit

**Playback Options > Remember State on Quit** saves and restores the complete app state:

When enabled, the following is saved on quit and restored on launch:
- **Window positions and visibility** (Main, EQ, Playlist, Browser, Milkdrop)
- **Audio settings** (volume, balance, shuffle, repeat, gapless, normalization)
- **Equalizer settings** (enabled state, preamp, all band values)
- **Playlist** (local files only, not streaming tracks)
- **Playback position** (resumes from where you left off)
- **Custom skin** (if a non-default skin was loaded)
- **UI preferences** (time display mode, always on top, double size)

**Note**: Only local file playlists are saved. Streaming tracks (Plex, Subsonic) are not persisted as they require authentication on each launch.

---

## File Format Support

### Audio (Local Playback)

| Format | Extensions |
|--------|------------|
| MP3 | .mp3 |
| AAC/M4A | .m4a, .aac |
| WAV | .wav |
| AIFF | .aiff, .aif |
| FLAC | .flac |
| Apple Lossless | .alac |
| Ogg Vorbis | .ogg |

### Audio (Plex)

- Everything Plex supports

### Video

| Format | Extensions |
|--------|------------|
| MKV | .mkv |
| MP4 | .mp4 |
| MOV | .mov |
| AVI | .avi |
| WebM | .webm |
| HEVC | .hevc |

### Playlists

- M3U (.m3u)
- M3U8 (.m3u8)

### Skins

- Winamp 2.x skins (.wsz) - ZIP archives

### Visualizations

- MilkDrop presets (.milk)

---

## Data Storage

| Data | Location |
|------|----------|
| Library database | `~/Library/Application Support/AdAmp/library.json` |
| Library backups | `~/Library/Application Support/AdAmp/Backups/` |
| Downloaded skins | `~/Library/Application Support/AdAmp/Skins/` |
| Plex credentials | macOS Keychain |
| Window positions | UserDefaults |
| EQ settings | UserDefaults |
| Saved app state | UserDefaults (when "Remember State" enabled) |
| Preferences | UserDefaults |

---

## Troubleshooting

### Audio Issues

- **No sound**: Check Output Devices, ensure correct device selected
- **EQ not working**: Verify EQ is enabled (ON button lit)
- **Plex streaming issues**: Refresh servers, check network connection

### Video Issues

- **Video won't play**: Ensure KSPlayer framework is installed
- **Buffering**: Check network connection to Plex server

### Visualization Issues

- **Black screen**: Verify OpenGL support, try different presets
- **Missing presets**: Use Rescan Presets in Visualizations menu

### Casting Issues

- **Devices not found**: Use Refresh Devices, check network
- **Casting fails**: Ensure device is on same network as AdAmp

---

## Credits

- [Webamp](https://github.com/captbaritone/webamp) - Skin parsing reference
- [Winamp Skin Museum](https://skins.webamp.org/) - Skin archive
- [projectM](https://github.com/projectM-visualizer/projectm) - Milkdrop visualizations
- [KSPlayer](https://github.com/kingslay/KSPlayer) - Video playback
- [AudioStreaming](https://github.com/dimitris-c/AudioStreaming) - HTTP audio streaming
- Original Winamp by Nullsoft

---

*AdAmp is not affiliated with Winamp LLC or Radionomy Group.*
