# AdAmp

A faithful recreation of the classic Winamp 2.x music player for macOS.

## Features

- **Pixel-perfect UI**: Exact recreation of the classic Winamp interface
- **Full skin support**: Compatible with classic Winamp skins (.wsz files)
- **All classic windows**: Main player, Playlist editor, 10-band Equalizer
- **Window snapping**: Classic Winamp window docking behavior
- **Audio format support**: MP3, FLAC, AAC, WAV, AIFF, ALAC, and more
- **Media library**: Organize and browse your music collection
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
| Load file | Cmd+O |

### Loading Skins

1. Download a classic Winamp skin (.wsz file) from [Winamp Skin Museum](https://skins.webamp.org/)
2. In AdAmp, go to File → Load Skin...
3. Select the .wsz file

## Architecture

```
AdAmp/
├── App/                    # Application lifecycle
├── Audio/                  # AVAudioEngine-based playback + spectrum analysis
├── Skin/                   # WSZ skin loading and rendering
├── Windows/                # Window controllers and views
│   ├── MainWindow/         # Main player window
│   ├── Playlist/           # Playlist editor
│   ├── Equalizer/          # 10-band EQ
│   └── MediaLibrary/       # Media library browser
├── Data/                   # Models and persistence
│   └── Models/             # Track, Playlist, MediaLibrary, EQPreset
├── Utilities/              # BMP parsing, ZIP extraction
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

### Phase 5: Polish (In Progress)
- [ ] Extended format support (OGG, Opus)
- [ ] Preferences
- [ ] DMG distribution

### Future: Expanded Test Coverage
- [ ] BMP Parser tests with real 8/24/32-bit BMPs and RLE compression
- [ ] SkinLoader tests with actual .wsz files
- [ ] Sprite coordinate verification tests
- [ ] M3U/PLS import round-trip tests
- [ ] Region hit testing tests
- [ ] Window snapping logic tests

## License

This project is for personal/educational use. It is not affiliated with Winamp LLC or Radionomy Group.

## Acknowledgments

- [Webamp](https://github.com/captbaritone/webamp) - Excellent reference for skin parsing
- [Winamp Skin Museum](https://skins.webamp.org/) - Skin archive
- Original Winamp by Nullsoft
