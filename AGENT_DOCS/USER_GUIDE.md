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
2. On first launch (or after an update), the classic Winamp intro sound plays
3. Right-click anywhere on the player to access the context menu
4. **Drag & drop** audio files onto the player, or use **Play > File...** / **Play > Folder...** to add music
5. Or connect your **Plex** account to browse your media library

**Note**: The intro sound only plays on new installs or after updating to a new version. Regular launches skip the intro for a faster startup experience.

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

### Drag & Drop

Drop audio files or folders onto the main player window to add them to the playlist:
- Files are **appended** to the existing playlist (not replaced)
- Folders are scanned recursively for audio files
- Playback starts from the **first dropped file**
- Supported formats: MP3, M4A, AAC, WAV, AIFF, FLAC, OGG, ALAC

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
- **Marquee scrolling** - Long track titles on the currently playing track automatically scroll horizontally

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
- **AUTO** - Automatic genre-based EQ (see Auto EQ below)
- **PRESETS** - Load pre-configured EQ settings
- **Preamp Slider** - Global gain adjustment (-12dB to +12dB)
- **Band Sliders** - Per-frequency adjustment (-12dB to +12dB)

### Auto EQ

When **AUTO** is enabled, the equalizer automatically applies genre-appropriate presets when tracks change:

| Genre Category | Matched Genres |
|----------------|----------------|
| **Rock** | rock, metal, punk, grunge, alternative, hard rock, indie rock |
| **Pop** | pop, dance-pop, synth-pop, k-pop, indie pop |
| **Electronic** | electronic, techno, house, trance, edm, dubstep, ambient |
| **Hip-Hop** | hip-hop, rap, r&b, rnb, soul, funk, trap |
| **Jazz** | jazz, swing, bebop, fusion, smooth jazz, blues |
| **Classical** | classical, orchestra, symphony, opera, baroque, chamber |

**Behavior:**
- When enabled, AUTO immediately applies a preset if the current track has a matching genre
- If the EQ is off when AUTO is enabled, it turns on automatically
- If no genre match is found, the current EQ settings remain unchanged
- Manual EQ adjustments are overridden when the track changes (while AUTO is on)
- AUTO state persists across app restarts

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

- **Selection Artwork**: Artwork updates as you browse and select items (albums, tracks, movies, shows, etc.)
- **Playback Artwork**: When a track plays, artwork from the playing item takes priority
- **Movie Posters**: Movies and TV episodes show poster art from Plex, with TMDb (The Movie Database) as a fallback
- **Music Artwork**: Album art loads from Plex/Subsonic servers, embedded metadata, or iTunes Search API

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

AdAmp supports video playback for Plex movies and TV shows with full audio/subtitle track selection.

### Playing Video

- Browse movies/TV shows in the Library Browser
- Double-click or select **Play** to open the video player
- Video playback automatically pauses any audio playback

### Controls

Hover over the video to reveal controls:
- **Stop** button - Stop playback and close the player (also stops cast on TV if casting)
- **Skip backward** (10 seconds)
- **Play/Pause** button
- **Skip forward** (10 seconds)
- **Seek slider** - Drag to jump to any position
- **Cast** button (TV icon) - Cast to Chromecast or DLNA TV
- **Track Settings** button (speech bubble icon) - Open audio/subtitle selection panel
- **Fullscreen** toggle

Controls auto-hide after 3 seconds during playback.

### Click Overlay

**Single-click** anywhere on the video to show a center overlay with:
- **Large play/pause button** - Toggle playback
- **Close button** (X) in top-right corner - Stop and close the player (also stops cast on TV if casting)

The overlay auto-hides after 2 seconds.

**Double-click** anywhere on the video to toggle play/pause immediately.

### Audio & Subtitle Track Selection

The video player supports multiple audio and subtitle tracks:

**Track Selection Panel:**
- Click the **Track Settings** button (speech bubble icon) in the control bar
- Or press **Cmd+S** to open the Netflix-style selection panel
- Panel slides in from the right edge

**Panel Features:**
- **Audio Section** - Lists all available audio tracks with language and codec info
- **Subtitles Section** - Lists all subtitle tracks with an "Off" option
- **Subtitle Settings** - Adjust subtitle delay (-5s to +5s)
- Checkmark indicates currently selected track
- Click outside the panel to dismiss

**Quick Access:**
- **S key** - Cycle through subtitle tracks (including Off)
- **A key** - Cycle through audio tracks
- **Right-click > Audio** - Submenu for quick audio track selection
- **Right-click > Subtitles** - Submenu for quick subtitle selection

### External Subtitles (Plex)

When playing Plex content, external subtitle files stored on the server are also available in the track selection panel. These are marked as "External" and support formats like SRT, ASS, and VTT.

### Keyboard Controls

| Key | Action |
|-----|--------|
| **Space** | Toggle play/pause |
| **F** | Toggle fullscreen |
| **Escape** | Exit fullscreen, close panel, or close player |
| **←** | Skip back 10 seconds |
| **→** | Skip forward 10 seconds |
| **S** | Cycle through subtitle tracks |
| **A** | Cycle through audio tracks |
| **Cmd+S** | Open track selection panel |

### Known Issues

**Cursor appearance on window edges**: The cursor may display resize icons (horizontal resize or X) when moving from window edges into the video content area. This is a limitation of using the KSPlayer video library with borderless resizable windows on macOS. The video player is fully functional - this is only a cosmetic cursor issue.

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

### Plex Radio

Generate dynamic playlists from the radio icon in the library browser toolbar. Each station type has two variants:
- **Standard**: Random tracks matching the criteria
- **Sonic**: Tracks sonically similar to the current/seed track

| Radio Station | Description |
|---------------|-------------|
| **Library Radio** | Random tracks from your entire library |
| **Only the Hits** | Popular tracks (1M+ Last.fm scrobbles) |
| **Deep Cuts** | Lesser-known tracks (under 1k scrobbles) |
| **Genre Stations** | Tracks from specific genres (dynamically loaded from your library) |
| **Decade Stations** | Tracks from specific decades (1920s-2020s) |

**Context Menu Radio** (right-click items):

| Radio Type | How to Access | Description |
|------------|---------------|-------------|
| **Track Radio** | Right-click track > "Start Track Radio" | Plays sonically similar tracks |
| **Album Radio** | Right-click album > "Start Album Radio" | Plays tracks from sonically similar albums |
| **Artist Radio** | Right-click artist > "Start Artist Radio" | Plays tracks from sonically similar artists |

**Radio Features**:
- Artist variety: Max 2 tracks per artist (1 for Sonic), spread apart to avoid back-to-back
- Genres fetched dynamically from your Plex library
- Sonic stations use currently playing track as seed, or random if nothing playing

**Requirements**: Plex Pass with sonic analysis enabled on the server for Sonic variants.

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

### Sonos Casting

**Output Devices > Sonos** provides multi-room casting to Sonos speakers.

#### Sonos Menu Structure

```
Sonos                          ▸
├── ☐ Dining Room                 (checkbox)
├── ☐ Living Room                 (checkbox)  
├── ☐ Kitchen                     (checkbox)
├── ─────────────────
├── 🟢 Start Casting              (or 🔴 Stop Casting)
└── Refresh
```

#### How to Cast to Sonos

1. **Load music** - Play or load a track (Plex, Subsonic, or local files)
2. **Open Sonos menu** - Right-click → Output Devices → Sonos
3. **Select rooms** - Check one or more room checkboxes (menu stays open!)
4. **Start casting** - Click **🟢 Start Casting**

#### Multi-Room Selection

The room checkboxes use a special view that **keeps the menu open** when clicked. This lets you:
- Check multiple rooms without reopening the menu
- Configure all your targets before starting
- Click "Start Casting" when ready

#### Checkbox Meanings

| When... | Checked (☑) | Unchecked (☐) |
|---------|-------------|---------------|
| NOT casting | Room selected for casting | Room not selected |
| Casting | Room receiving audio | Room not receiving audio |

#### While Casting

- **Check a room** → Room joins the cast and starts playing
- **Uncheck a room** → Room leaves the cast and stops playing
- **🔴 Stop Casting** → Stops all rooms, clears selection

#### Errors

| Error | Solution |
|-------|----------|
| "No Music" | Load a track before casting |
| "No Room Selected" | Check at least one room |
| "No Device Found" | Click Refresh, wait 10 seconds |

#### Requirements

- **UPnP must be enabled** in the Sonos app (Account → Privacy & Security → Connection Security)
- Sonos speakers must be on the same network as your Mac
- Works with Plex/Subsonic streaming and local files
- Local file casting requires firewall to allow port 8765

### Chromecast & DLNA

**Output Devices** also discovers:
- **Chromecast** - Google Cast speakers and displays
- **TVs (DLNA)** - DLNA-compatible televisions

To cast audio:
1. Start playing audio in AdAmp
2. Select a device from the menu
3. **Stop Casting** to return to local playback

**Refresh Devices** rescans your network for all cast targets.

### Video Casting

AdAmp supports casting Plex movies and TV episodes to video-capable devices (Chromecast and DLNA TVs). Sonos is audio-only.

There are **two casting paths** with different control behaviors:

#### Path 1: Casting from Video Player

1. Open a movie or episode in the video player
2. Click the **Cast** button (TV icon) in the control bar
3. Select a device from the menu:
   - **Chromecast** devices listed first
   - **TVs** (DLNA) listed separately
4. Video pauses locally and casts to the selected device
5. Playback resumes from current position on the TV

**Controls**: Use the video player window controls or main window transport buttons.

#### Path 2: Casting from Plex Browser (Menu)

Right-click a movie or episode in the Library Browser:
1. Select **Cast to...** from the context menu
2. Choose a target device
3. Video plays directly on the TV (no local video player window)

**Controls**: Use the **main window transport buttons** (Play, Pause, Stop) to control playback. The main window time display and position slider also work for seeking.

#### Video Casting Requirements

- Device must support video (Sonos excluded automatically)
- Plex content: Uses direct stream URL with authentication token
- Local video files: Served via embedded HTTP server (port 8765)
- Resume position: Casting remembers where you were in the video

#### Stopping Video Cast

- **From video player**: Click the Cast button or close the player
- **From menu cast**: Use Stop button on main window, or right-click → Output Devices → select the active device

#### Known Limitations

**Chromecast**: Fully supported for both audio and video casting using the Google Cast Protocol v2. Supports playback controls (play, pause, seek, volume) from AdAmp.

**Samsung TVs**: Samsung TVs have limited DLNA control support. While video casting works for playback, remote control features (seek, volume, pause) may not be available. This is a Samsung firmware limitation - use the TV's remote to control playback. (Tested on Samsung QN90BA 75")

**Other DLNA TVs**: Most DLNA-compatible TVs (LG, Sony, etc.) should work for video casting. Remote control support varies by manufacturer.

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
| **↑** | Move selection up |
| **↓** | Move selection down |
| **Shift+↑** | Extend selection up |
| **Shift+↓** | Extend selection down |
| **Home** | Jump to first track |
| **End** | Jump to last track |
| **Page Up** | Move selection up by a page |
| **Page Down** | Move selection down by a page |
| **Shift+Home/End/PgUp/PgDn** | Extend selection to target |
| **Delete** | Remove selected tracks |
| **Enter** | Play selected track |
| **Cmd+A** | Select all |

### Video Player

| Key | Action |
|-----|--------|
| **Space** | Play/Pause |
| **F** | Toggle fullscreen |
| **Escape** | Exit fullscreen / Close panel / Close |
| **←** | Skip back 10 seconds |
| **→** | Skip forward 10 seconds |
| **S** | Cycle subtitle tracks |
| **A** | Cycle audio tracks |
| **Cmd+S** | Open track selection panel |

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

### About Playing

Shows detailed metadata for the currently playing track or video. This option is disabled (grayed out) when nothing is playing.

**For Audio Tracks:**
- Title, Artist, Album
- Duration, Bitrate, Sample Rate, Channels
- File path (local) or server path (Plex)
- Genre, Year, Track Number (Plex only)
- Last.fm scrobble count and your rating (Plex only)

**For Videos:**
- Title, Year, Studio (movies)
- Show name, Season, Episode (TV)
- Resolution, Video/Audio codecs
- Content rating, IMDB/TMDB IDs
- Summary (truncated)

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
- Sweet Fades (Crossfade)
- Fade Duration (when Sweet Fades enabled)
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

### Plex Context Menu (Right-click in Library Browser)

| Item Type | Menu Options |
|-----------|--------------|
| **Track** | Play, Add to Playlist, Start Track Radio |
| **Album** | Play Album, Add Album to Playlist, Start Album Radio |
| **Artist** | Play All by Artist, Expand/Collapse, Start Artist Radio |
| **Movie** | Play Movie, Add to Playlist, Cast to..., View Online |
| **Episode** | Play Episode, Add to Playlist, Cast to..., View Online |

### Video Player Context Menu (Right-click on video)

| Menu Item | Description |
|-----------|-------------|
| **Play/Pause** | Toggle playback |
| **Skip Backward 10s** | Rewind 10 seconds |
| **Skip Forward 10s** | Fast forward 10 seconds |
| **Audio** | Submenu listing available audio tracks |
| **Subtitles** | Submenu listing subtitle tracks (includes "Off") |
| **Track Settings...** | Opens the track selection panel |
| **Always on Top** | Keep video window above other windows |
| **Toggle Fullscreen** | Enter/exit fullscreen mode |
| **Close** | Stop playback and close the video player |

**Note**: To cast video, use the Cast button (TV icon) in the control bar.

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
- Works with both local files and streaming (Plex/Subsonic)
- Not compatible with Repeat Single mode
- Disabled when Sweet Fades (crossfade) is enabled

### Sweet Fades (Crossfade)

**Playback Options > Sweet Fades (Crossfade)** enables smooth blending between tracks:
- Tracks overlap and crossfade at the end of each song
- Uses equal-power fade curve for perceptually smooth transitions
- Works with both local files and streaming (Plex/Subsonic)

**Fade Duration** options (when Sweet Fades is enabled):
- 1s, 2s, 3s, **5s (default)**, 7s, 10s

**Constraints:**
- Disabled when casting (playback is remote)
- Skipped for mixed source transitions (local→streaming)
- Skipped if next track is shorter than 2× fade duration
- Skipped in Repeat Single mode
- Cancelled if you seek, skip, or select a different track

**Note:** Sweet Fades takes precedence over Gapless Playback. When enabled, gapless pre-scheduling is disabled.

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
- **Milkdrop fullscreen state** (restores to fullscreen if it was fullscreen)
- **Audio settings** (volume, balance, shuffle, repeat, gapless, normalization, Sweet Fades)
- **Equalizer settings** (enabled state, preamp, all band values)
- **Playlist** (local files AND streaming tracks from Plex/Subsonic)
- **Milkdrop preset** (restores the last-used visualization preset)
- **Library Browser source** (remembers which library was selected)
- **Custom skin** (if a non-default skin was loaded)
- **UI preferences** (time display mode, always on top)

**Note**: Streaming tracks require their respective servers (Plex/Navidrome) to be available on launch. Tracks from unavailable servers will be skipped. The playlist is restored but no track is automatically loaded or played - you choose when to start playback.

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

### Sonos Issues

- **No Sonos devices appear**: Ensure UPnP is enabled in Sonos app settings
- **"No Music" error**: Load a track before casting
- **"No Room Selected" error**: Check at least one room checkbox
- **Room won't join cast**: Click Refresh, ensure UPnP is enabled
- **Checkbox changes don't work**: Wait for discovery to complete (10+ seconds after refresh)
- **Menu disappears during refresh**: Close and reopen context menu - data is preserved
- **Local files won't cast**: Ensure firewall allows port 8765 and Mac has a local network IP

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
