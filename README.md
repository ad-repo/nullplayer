# ClassicAmp

A faithful recreation of the classic Winamp 2.x music player for macOS.

## Features

- **Pixel-perfect UI**: Exact recreation of the classic Winamp interface
- **Full skin support**: Compatible with classic Winamp skins (.wsz files)
- **All classic windows**: Main player, Playlist editor, 10-band Equalizer
- **Window snapping**: Classic Winamp window docking behavior
- **Audio format support**: MP3, FLAC, AAC, WAV, AIFF, ALAC, and more

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
git clone https://github.com/yourusername/ClassicAmp.git
cd ClassicAmp

# Build with Swift Package Manager
swift build

# Or run directly
swift run ClassicAmp
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
| Load file | Cmd+O |

### Loading Skins

1. Download a classic Winamp skin (.wsz file) from [Winamp Skin Museum](https://skins.webamp.org/)
2. In ClassicAmp, go to File → Load Skin...
3. Select the .wsz file

## Architecture

```
ClassicAmp/
├── App/                    # Application lifecycle
├── Audio/                  # AVAudioEngine-based playback
├── Skin/                   # WSZ skin loading and rendering
├── Windows/                # Window controllers and views
│   ├── MainWindow/         # Main player window
│   ├── Playlist/           # Playlist editor
│   └── Equalizer/          # 10-band EQ
├── Data/                   # Models and persistence
└── Utilities/              # BMP parsing, ZIP extraction
```

## Skin Compatibility

ClassicAmp supports classic Winamp 2.x skins (.wsz files). Key supported features:

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

### Phase 2: Skin Engine (In Progress)
- [x] WSZ file extraction
- [x] BMP parsing (8/24/32-bit, RLE)
- [ ] Complete sprite rendering
- [ ] Region-based hit testing

### Phase 3: All Windows
- [ ] Complete main window
- [ ] Playlist editor
- [ ] Equalizer

### Phase 4: Features
- [ ] Media library
- [ ] Shade mode
- [ ] Window docking

### Phase 5: Polish
- [ ] Extended format support (OGG, Opus)
- [ ] Preferences
- [ ] DMG distribution

## License

This project is for personal/educational use. It is not affiliated with Winamp LLC or Radionomy Group.

## Acknowledgments

- [Webamp](https://github.com/captbaritone/webamp) - Excellent reference for skin parsing
- [Winamp Skin Museum](https://skins.webamp.org/) - Skin archive
- Original Winamp by Nullsoft
