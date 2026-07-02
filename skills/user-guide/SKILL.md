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
| **Equalizer** | Classic 10-band EQ or modern 21-band EQ with presets | EQ button or context menu |
| **Spectrum Analyzer** | Large spectrum visualization | Context menu or Window menu |
| **Audio Analyzer** | Friture-style multi-pane analyzer (Scope, Levels, Spectrogram, Octave, Pitch, Delay) | Context menu or Window menu |
| **Library Browser** | Browse Plex/Jellyfin/Subsonic/Emby and local media | Logo button or context menu |
| **Visualizations** | Visualization engine host for ProjectM, Geiss, Tripex, and Met Museum Art (titled "Visualizations" in menus and window chrome; internally still the ProjectM window) | VZ button, Window menu, or context menu |

In modern UI, **Windows > Play History** opens the **Data** tab inside the Library Browser instead of a separate window. The Data tab is also available in the classic library browser. The Data tab shows:
- **Play Time** summary (day/week/month/year/all-time)
- **Top Artists** (music only)
- **Top Movies** and **Top TV Shows** (separate sections; TV groups by show name)
- **Genre** breakdown (music and video; excludes radio)
- **Sources** breakdown (music and video; excludes radio — a note directs to the Internet Radio section below)
- **Output Devices** breakdown (which speaker/cast device was active; cast sessions record Chromecast/Sonos/DLNA device name)
- **Content Types** donut chart (Music / Movies / TV Shows / Radio / Video)
- **Internet Radio** section — total listen time + Top Stations ranked by play count and listen duration
- **Plays Over Time** time series

All charts are interactive filters — clicking a segment narrows all other charts to that slice. The **Now Playing…** context menu item shows rich track info (album artist, year, track number, genre, play count, rating, file path, etc.) fetched live from the server for Plex/Subsonic/Jellyfin/Emby tracks.

### Top Menu Bar

Global controls are also available from the macOS top menu bar:

- `Windows`
- `UI`
- `Playback`
- `Visuals`
- `Libraries`
- `Output`

`Output > Sonos` supports persistent-open room checkbox selection (same behavior as the context menu Sonos submenu).

`Output > Streaming > Rip URL…` opens the Stream Ripper (paste a URL → FLAC/MP3/MP4); see Output Devices & Casting below.

### Window Docking

Windows automatically snap together when dragged near each other:
- Edge-to-edge snapping
- Screen edge snapping
- Group minimize (attached windows minimize together)
- **Lock Connected Windows / Unlock Connected Windows** toggle (context menu) controls whether connected windows always move as a group
- **Snap to Default** (context menu) resets all windows

**Drag behaviour:**
- **Quick drag** (release mouse within ~400 ms of clicking): the dragged window detaches from its group and moves alone; other connected windows stay put
- **Hold then drag** (hold ≥ 400 ms before moving): all connected windows move together as a group
- **When connected windows are locked**: hold timing is bypassed and drags always move the whole connected group
- Connected peers show a brief highlight overlay at mouseDown to preview which windows will move together

### Compact Mode

**Compact Mode** collapses NullPlayer to a single menu-bar app. Toggle it from the main window's right-click context menu (**Compact Mode**) or the `Windows` top menu — available in **both classic and modern UI**. When enabled:

- The Dock icon is hidden (the app switches to an accessory/menu-bar app) and a **NullPlayer status-bar item** appears in the menu bar. Clicking it reveals the single compact window; its menu also has **Exit Compact Mode**.
- Left-clicking the status-bar item toggles the compact window shown/hidden. Right-clicking opens the Compact Mode menu.
- The compact window opens at the top-right of the screen, aligned directly below the menu bar with no extra gap.
- The sole window is the **Library Browser** with a stripped-down player bar embedded across the top (transport, seek + time, a scrolling title marquee, and volume), built from the active UI's own components (classic skin sprites in classic, modern controls in modern).
- All other windows (Main, EQ, Playlist, Spectrum, etc.) are hidden; their prior visibility is remembered and restored when you exit. **Exceptions:** the video player and debug console windows are allowed in Compact Mode — a playing video stays visible on entry, videos opened while compact (e.g. a downloaded YouTube video) appear normally, and an open debug console remains visible.
- Exiting restores the Dock icon, the macOS menu bar, and the previously open windows.

### Main Window Elements

| Element | Description |
|---------|-------------|
| **Time Display** | Single-click toggles elapsed/remaining; double-click cycles timer number systems in modern UI |
| **Track Marquee** | Scrolling song title/artist, with album art thumbnail when available |
| **Bitrate** | Track bitrate in kbps |
| **Sample Rate** | Audio sample rate in kHz |
| **Stereo Indicator** | Shows mono/stereo status |
| **Cast Indicator** | Shows when casting to external device |
| **Spectrum Analyzer** | Real-time frequency visualization |

### Playback Menu: Timer

`Playback > Timer` unifies main-window timer options:

- `Elapsed` / `Remaining` choose the time basis
- `Number System` is modern-only
- `Default (Decimal)` restores the current default behavior
- Additional modern timer number systems include Arabic-Indic, Extended Arabic-Indic, Devanagari, Bengali, Thai, Fullwidth, Octal, and Hexadecimal

### Sliders

- **Position Bar**: Seek through track
- **Volume Slider**: Adjust playback volume (0-100%)
- **Balance Slider**: Pan audio left/right

### Transport Buttons

Previous, Play, Pause, Stop, Next

### Toggle Buttons

- **Shuffle**: Random playback order
- **Repeat**: Loop playlist
- **EQ**: Show/hide Equalizer
- **PL**: Show/hide Playlist

Modern UI adds: **HT** (Hide Title Bars), **CP** (Compact Mode), **VZ** (Visualizations), **SP** (Spectrum), **WV** (Waveform), **LB** (Library)

## Media Sources

### Plex Integration
- Browse music, movies, and TV shows
- Album artwork and metadata
- Radio features (Track/Artist/Album/Genre/Decade/Rating/Hits/Deep Cuts)
- Automatic scrobbling (90% or end, min 30s)
- Video playback with casting

### Jellyfin Integration
- Browse music and video libraries
- **Library selector** in status bar: click "Lib:" to switch library. Mode-aware — shows music library picker in music tabs (Artists/Albums/Tracks/Plists) and video library picker in Movies/TV tabs. "All" option browses across all libraries.
- Rating scale: 0-100% (0-10 internal)
- Scrobbling (50% or 4 minutes for audio, 90% for video)

### Navidrome/Subsonic
- Browse artists, albums, playlists
- **Music folder selector** in status bar: click "Lib:" to filter by music folder. "All" shows content from all folders.
- Token authentication
- Scrobbling (50% or 4 minutes)
- Casting support via proxy

### Emby Integration
- Browse music and video libraries
- **Library selector** in status bar: click "Lib:" to switch library. "All" browses across all libraries.
- Rating scale: 0-100% (0-10 internal, multiply/divide by 10; 1 star = 20)
- Scrobbling (50% or 4 minutes for audio, 90% for video)
- Casting support via proxy (stream URLs have no file extension)

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
- **Play history tracking** — listen sessions are recorded with pause-aware duration; visible in the Data tab Internet Radio section (total listen time + top stations). Sessions shorter than 1 second are discarded. Long sessions checkpoint every 30 minutes.
- Playback Options now groups all source histories under a single **Radio History** submenu

### Local Files
Drag & drop or use File menu. Supports: MP3, M4A, AAC, WAV, AIFF, FLAC, OGG, ALAC

### .cue Sheets
Open a `.cue` file (File → Open, drag-drop, or double-click), or open an audio file that has a sibling `.cue` next to it, and the single backing file is **virtually split** into its cue tracks — one row per track in the now-playing playlist, with correct titles/durations. Prev/Next move per cue track, seek stays within the current track, and playback crosses track boundaries **gaplessly** (shuffle and repeat-single still advance correctly, but a small gap is expected in those modes). Nothing is written to disk and nothing is added to the library.

Optionally, **Library → Split .cue Albums on Import** (off by default) makes the library scan physically split a backing file into per-track FLACs (via `ffmpeg`) when it finds a `.cue`; the split tracks are added to the library and the original is hidden. With it off, the `.cue` is ignored and the backing file imports as one track. If `ffmpeg` isn't installed, splitting is skipped with a one-time notice and the original imports normally. Takes effect on the next scan. See the **cue-sheets** skill for internals.

### Local Library Browser
Switch the Library Browser source to "Local" to manage a persistent media library.

**+ADD menu** (three options):
- **Add Files...** — file picker filtered to audio formats
- **Add Video Files...** — file picker filtered to video formats (`.mp4`, `.mkv`, `.mov`, etc.); files are classified as movies or TV episodes automatically (SxxExx naming / iTunes metadata)
- **Add Folder...** — folder picker; scans immediately for audio and video files, and saves the folder as a "remembered folder"

**Watch folders (remembered folders):**
- Folders added via "Add Folder..." are persisted in the library database
- They are **not** monitored automatically — there is no filesystem watcher
- Press the **⟳ refresh button** to run an **incremental** re-scan of all remembered folders (new/changed/removed files only)
- Fast ingest behavior: newly discovered files appear quickly with filename/basic info, then metadata (duration/tags/sample rate) fills in asynchronously
- Duplicate detection and per-file signatures prevent unnecessary metadata re-parse for unchanged files
- Progress updates are throttled/coarse during large imports to keep UI responsive

**Tabs:** Artists, Albums, Playlists (`Plists` in the UI), Movies, TV (the TV-shows tab, labeled `Shows` internally), Radio, Search, Data

The **Data tab** is present in both the modern Library Browser and the classic library browser (`PlexBrowserView`). It shows play-history analytics for all sources (see the Data tab description at the top of this section).

### Drag/Drop + Folder Import Behavior (Local/NAS)

Import discovery is now unified across classic + modern entry points (main window, playlist windows, library browsers):

- Directory traversal runs in background (no synchronous recursive UI-thread scans)
- Extension filtering is consistent across add-folder and drag/drop paths
- Supported content checks are shared before accepting a drop
- Works for large local sets and NAS paths (SMB/AFP) with less UI churn during import

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

### Stream Ripper (Output → Streaming → Rip URL…)
- Paste a URL (auto-filled from the clipboard) and pick **FLAC**, **MP3**, or **MP4 video** at a chosen profile: 720p / 2.5 Mbps, 1080p / 4 Mbps (recommended), 1080p / 8 Mbps (high quality), 1440p / 16 Mbps, 4K / 35 Mbps, or Full / 50 Mbps
- Downloads via a system-installed `yt-dlp` (+`ffmpeg`); shows an install hint if missing
- Best-quality source selection; lossless FLAC; video is compatibility-transcoded to H.264/AAC MP4
- Tags output with source metadata; audio embeds cover art. Final files are named `Artist - Title`; video uses a temporary `Artist - Title [source]` file during compatibility transcoding.
- Writes a `.cue` sheet when the source has chapter timestamps
- Progress band at the top of the main window; finish dialog offers **Play Now** / **Reveal in Finder**
- See the **stream-ripper** skill for internals

## Audio Features

### Equalizer
- **Classic UI**: 10-band graphic EQ (-12dB to +12dB per band)
- **Modern UI**: 21-band graphic EQ (-12dB to +12dB per band)
- Preamp control
- Anti-clipping limiter
- **Modern UI**: 7 compact preset toggle buttons in the button row (FLAT, ROCK, POP, ELEC, HIP, JAZZ, CLSC); clicking a preset auto-enables EQ if off; clicking the active preset deactivates it (reverts to flat); dragging any fader clears the active preset
- **Modern UI**: integrated glowing `PRE` control in the graph strip replaces the old preamp slider; drag to adjust preamp, double-click to reset to `0 dB`
- **Modern UI**: double-click a fader to reset that band only to `0 dB`
- **Modern UI**: AUTO button applies genre-based preset for the current track and auto-enables EQ if off
- **Modern UI**: all 21 frequency labels are visible in-window, using compact labels like `1K`, `1.4K`, `2K`, `11.2K`
- **Classic UI**: PRESETS dropdown with all presets including "I'm Old" / "I'm Young"

### Playback Options
- **Gapless Playback**: Seamless track transitions (local files)
- **Sweet Fades**: Crossfade between tracks (1-10s duration)
- **Volume Normalization**: Consistent loudness (-14dB target)
- **Reference Tuning**: Pitch-shift playback to a different reference frequency. Presets for Off, 432 Hz, 440 Hz, and a Custom… dialog (source/target Hz, ±2400 cents). Applies to local files and HTTP streams; unavailable while casting because remote renderers have no local audio graph to insert the pitch shifter into. Persists across launches; the CLI also accepts `--tuning`, `--tuning-source`, and `--tuning-offset-cents` as session-only overrides.
- **Playback Speed**: Tempo-preserving speed control from `0.25×` to `4.0×`, with presets plus Custom…. Applies to local files and HTTP streams; unavailable while casting. Persists across launches.
- **Balance**: Stereo pan submenu (slider plus Left / Center / Right presets), backed by `engine.balance` and mirrored by the classic Balance Slider sprite. Gives the modern UI and menu-only/Compact workflows access to balance without a face slider. Persists across launches.
- **Remember State on Quit**: `AppStateManager.restorePlaylistState` restores playlist contents and ordering; it intentionally does not restore the selected track, seek position, or playing state

### Sleep Timer
Accessible via **Playback > Sleep Timer** (or the right-click context menu).

**Modes**
| Mode | Behaviour |
|------|-----------|
| **Timed** | Pause/stop after 5, 10, 15, 30, 45, 60, or 90 minutes, or 2, 5, 8, or 12 hours. A 10-second linear volume fade-out fires before the action. |
| **End of Current Track** | Pause/stop when the currently playing track ends naturally. Does **not** fire on manual skip or previous. Works correctly with Sweet Fades crossfade. |
| **End of Queue** | Pause/stop when the last track in the playlist finishes. |

**Behaviour notes**
- The submenu shows a live countdown (`Sleep Timer: 1:23`) while a timed timer is running.
- Selecting the currently active preset again cancels it (toggle behaviour).
- A **Cancel Sleep Timer** item appears at the top of the submenu while any timer is active.
- If the volume is adjusted manually during a timed fade-out, the fade aborts and the volume is left at the new level.
- If a timed timer is cancelled mid-fade, volume is restored to the level it was at when the timer started.
- State is session-local — not persisted across launches.

### Spectrum Modes
- **Accurate**: True signal levels (40dB range)
- **Adaptive**: Global adaptive normalization
- **Dynamic**: Per-region normalization (bass/mid/treble)

## Visualizations

### Audio Analyzer Window
A multi-pane real-time analyzer (Friture-style), available in both classic and modern UI. Right-click the window to pick a pane:
- **Scope** — oscilloscope waveform of the live signal.
- **Levels** — per-channel Peak and RMS meters (green/yellow/red) in dBFS.
- **Spectrogram** — scrolling waterfall of the spectrum over time.
- **Octave** — 1/3-octave bar spectrum (20 Hz–20 kHz) with peak-hold markers.
- **Pitch** — detected note, frequency, and how sharp/flat it is (best for vocals/single notes; unreliable on deep bass).
- **Delay** — stereo left/right timing offset in ms and samples (resolves up to ±~5.8 ms).

Only the visible pane runs, so the window is light on CPU and idles when closed.

### Main Window GPU Modes
Off, Spectrum, vis_classic, Fire, Enhanced, Ultra, JWST, Lightning, Matrix, Snow, EKG. Double-click cycles visual modes; choose Off from Visuals > Spectrum Analyzer > Main Window > Mode.

### Album Art Visualizer
30 effects transforming album artwork based on audio

### ProjectM/MilkDrop
100+ bundled presets, OpenGL rendering, fullscreen support

### Geiss
Port of Ryan Geiss's classic Winamp visualization. ProjectM-peer engine — selected from the same right-click **Visualization Engine** submenu. Right-click for runtime controls: effect navigation, Geiss Sensitivity, Gamma, Beat Detection, Sync Color to Sound, Slide Shift, Mode Lock, Palette Lock, Auto-Switch interval, visMode (Wave/Spectrum), and Randomize Palette. All settings persist across launches.

### Spectrum Analyzer Window
55 bars, 9 quality modes (Winamp/vis_classic/Enhanced/Ultra/Fire/JWST/Lightning/Matrix/Snow)

## Skins

### Loading Skins
- **Skins > Load Skin...** to open `.wsz` file
- Place in `~/Library/Application Support/NullPlayer/Skins/` for auto-discovery
- Bundled skins: Silver (default), Classic, Dark, Light

### Modern UI Mode
- **Skins > Modern/Classic > Switch to…** to change UI mode
- Switches **live, with no restart** — only the mode-dependent window layer is rebuilt; audio, casting, the video player, and playlist/seek/play state continue uninterrupted. Picking a specific modern or classic skin while in the other mode also switches live.
- Modern skins use `skin.json` format
- Portable modern skin bundles use `.nsz` (ZIP) and can be imported via **Skins > Modern > Load Skin...**
- Bundled modern skins: NeonWave (default), Skulls

### Large UI Mode
- **Modern UI**: toggle via context menu → **Large UI**
- **Classic UI**: toggle via **2X button** or context menu → **Large UI**
- Scales all windows by 1.5x
- Persists across restarts
- **Modern UI**: toggles live instantly
- **Classic UI**: requires a restart (dialog appears before any UI change)

### Hide Title Bars (Modern UI)
- Toggle via context menu or HT button on the main window
- **HT Off (default)**: EQ/Playlist/Spectrum hide titlebars when docked — this is always active, even with HT off
- **HT On**: All 6 windows (main, EQ, playlist, spectrum, ProjectM, library browser) hide titlebars; the main window keeps the same outer size while its internal layout expands to fill the reclaimed space
- Preserves the border line (titlebar area collapses to border width, not 0)

## Keyboard Shortcuts

### Playback
- **Space**: Play/Pause
- **V**: Stop
- **B**: Next track
- **Z**: Previous track
- **←/→**: Seek backward/forward 5s
- **↑/↓**: Volume up/down

### vis_classic Profiles
- **Main window**: **, / .** previous/next profile
- **Spectrum window**: **[ / ]** previous/next profile (left/right also cycle profiles in vis_classic mode)
- **Transparent Background**: right-click in vis_classic mode and toggle per window (main and spectrum persist separately)

### Geiss
- **→ / ←**: Next / Previous effect
- **R**: Random effect
- **F**: Toggle fullscreen
- **Escape**: Exit fullscreen
- All other levers (sensitivity, gamma, locks, auto-switch, palette randomize, etc.) are right-click context-menu only — see the Visualizations section above.

### Tripex
- **→ / ←**: Next / Previous effect
- **R**: Random effect
- **F**: Toggle fullscreen
- **Escape**: Exit fullscreen
- Hold, auto-cycle, auto-random, intensity, audio info, help overlay, and effect selection are right-click context-menu only.

### Met Museum Art
- **→ / ← / R**: Advance to another artwork
- **F**: Toggle fullscreen
- **Escape**: Exit fullscreen
- Department, slideshow interval, transition, aspect ratio, audio-modulated effects, beat-triggered changes, attribution, and cache clearing are right-click context-menu only.

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
- **Right-click column headers**: Configure visible columns. Artists shows Artist, Album, and Track sections; Albums shows Album and Track sections. Checkbox clicks keep the menu open; each section has its own reset.
- **Right Arrow**: Expand item (artists, albums, playlists, shows, seasons); if already expanded, move to first child
- **Left Arrow**: Collapse expanded item; if not expanded, jump to parent item
- **Tab / Shift+Tab**: Cycle forward/backward through tabs (Artists → Albums → Playlists (Plists in the UI) → Movies → TV → Radio → Search → Data)
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
- **Shift+Click** for multi-select in playlist/browser
- **Cmd+J** to jump to currently playing track
- Windows **dock automatically** when dragged near each other
- **Large UI** (1.5x) is available in both modern and classic UI; classic requires restart
