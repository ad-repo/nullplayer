# Winamp Skin Format Research

## Known Issues for Future Development

### Position/Seek Slider (FIXED)
The position slider now works correctly:
- **Previous issues**: 
  - After seeking, playback would skip to next track
  - Position would snap back to 0 after seeking
  - Duration was read from cached view property which could be 0
- **Root causes fixed**:
  1. The completion handler from `scheduleFile` fired when `playerNode.stop()` was called during seek
  2. `playerTime(forNodeTime:)` didn't reliably track position after `scheduleSegment`
  3. The view's cached `duration` property wasn't always up-to-date
- **Solution**:
  - Added `playbackGeneration` counter to invalidate stale completion handlers
  - Switched to manual time tracking using `playbackStartDate` + `_currentTime` instead of relying on `playerNode.playerTime()`
  - Now gets duration directly from `audioEngine.duration` instead of cached value
  - Properly manage time tracking state across play/pause/stop/seek operations

---

This document captures research findings about the classic Winamp skin format (.wsz) for implementing AdAmp's skinning system. This is intended to help future development efforts.

## External Resources

### Primary References
- **Webamp Source Code** (JavaScript Winamp clone): https://github.com/captbaritone/webamp
  - Sprite coordinates: `https://raw.githubusercontent.com/captbaritone/webamp/master/packages/webamp/js/skinSprites.ts`
  - This is the authoritative source for exact pixel coordinates of all skin elements
  
- **Winamp Skin Format Documentation**: https://winampskins.neocities.org/
  - Contains guides for each skin component (main, equalizer, playlist, etc.)

### Useful Commands to Fetch Sprite Data
```bash
# Get all EQMAIN sprite coordinates
curl -s "https://raw.githubusercontent.com/captbaritone/webamp/master/packages/webamp/js/skinSprites.ts" | grep -A50 "EQMAIN:"

# Get all CBUTTONS (transport buttons) coordinates  
curl -s "https://raw.githubusercontent.com/captbaritone/webamp/master/packages/webamp/js/skinSprites.ts" | grep -A80 "CBUTTONS:"

# Get PLEDIT (playlist) coordinates
curl -s "https://raw.githubusercontent.com/captbaritone/webamp/master/packages/webamp/js/skinSprites.ts" | grep -A100 "PLEDIT:"
```

---

## Skin File Structure

A `.wsz` file is a ZIP archive containing BMP images:

| File | Purpose |
|------|---------|
| `MAIN.BMP` | Main window background and elements |
| `CBUTTONS.BMP` | Transport control buttons (play, pause, stop, etc.) |
| `TITLEBAR.BMP` | Window title bar sprites |
| `SHUFREP.BMP` | Shuffle, repeat, EQ, playlist toggle buttons |
| `POSBAR.BMP` | Position/seek slider |
| `VOLUME.BMP` | Volume slider |
| `BALANCE.BMP` | Balance slider |
| `MONOSTER.BMP` | Mono/stereo indicator |
| `PLAYPAUS.BMP` | Play/pause status indicator |
| `NUMBERS.BMP` | Time display digits |
| `NUMS_EX.BMP` | Extended number set (if present) |
| `TEXT.BMP` | Marquee/title text font |
| `EQMAIN.BMP` | Equalizer window (275x315 pixels) |
| `EQ_EX.BMP` | Extended EQ graphics (optional) |
| `PLEDIT.BMP` | Playlist editor sprites |
| `PLEDIT.TXT` | Playlist color configuration |

---

## Title Bar Sprite Font (PLEDIT/EQMAIN)

The playlist and equalizer title bars contain a pixel font embedded in the title sprites:
- **PLEDIT.BMP** title sprite includes letters for "WINAMP PLAYLIST"
- **EQMAIN.BMP** title bar includes letters for "EQUALIZER"

AdAmp combines these letter sprites to build new titles (ex: "PLEX BROWSER") and
falls back to a 5x6 pixel pattern for missing letters. See:
- `SkinElements.TitleBarFont` for character sources and fallback pixels
- `SkinRenderer.drawTitleBarSpriteText()` for rendering logic

## Plex Browser Title Font Asset

For the Plex browser title, AdAmp now uses a dedicated sprite atlas:
- Resource: `Sources/AdAmp/Resources/title_font_plex.png`
- Cell size: 5x6 pixels with 1px spacing
- Characters included: P, L, E, X, B, R, O, W, S

`SkinRenderer.drawTitleBarSpriteText()` pulls glyphs from this atlas to render
“PLEX BROWSER” in the same pixel style as the title sprites.

---

## EQMAIN.BMP Layout (275x315 pixels)

The equalizer sprite sheet contains all EQ window elements:

### Background & Window States
| Element | X | Y | Width | Height | Notes |
|---------|---|---|-------|--------|-------|
| EQ Window Background | 0 | 0 | 275 | 116 | Main EQ window background |
| Title Bar (Active) | 0 | 134 | 275 | 14 | "WINAMP EQUALIZER" active |
| Title Bar (Inactive) | 0 | 149 | 275 | 14 | Title bar when window inactive |

### Slider Knob (from webamp)
| Element | X | Y | Width | Height | Notes |
|---------|---|---|-------|--------|-------|
| EQ_SLIDER_THUMB | 0 | 164 | 11 | 11 | Normal state |
| EQ_SLIDER_THUMB_SELECTED | 0 | 176 | 11 | 11 | Pressed/selected state |
| EQ_SLIDER_BACKGROUND | 13 | 164 | 209 | 129 | Full slider area background |

### ON/AUTO/PRESETS Buttons (from webamp)
| Element | X | Y | Width | Height | Notes |
|---------|---|---|-------|--------|-------|
| EQ_ON_ACTIVE | 0 | 119 | 26 | 12 | ON button - enabled state |
| EQ_ON_ACTIVE_PRESSED | 26 | 119 | 26 | 12 | ON button - enabled+pressed |
| EQ_ON_INACTIVE | 0 | 107 | 26 | 12 | ON button - disabled state |
| EQ_ON_INACTIVE_PRESSED | 26 | 107 | 26 | 12 | ON button - disabled+pressed |
| EQ_AUTO_ACTIVE | 52 | 119 | 32 | 12 | AUTO button - enabled |
| EQ_AUTO_ACTIVE_PRESSED | 84 | 119 | 32 | 12 | AUTO button - enabled+pressed |
| EQ_AUTO_INACTIVE | 52 | 107 | 32 | 12 | AUTO button - disabled |
| EQ_AUTO_INACTIVE_PRESSED | 84 | 107 | 32 | 12 | AUTO button - disabled+pressed |
| EQ_PRESETS_NORMAL | 224 | 164 | 44 | 12 | PRESETS button normal |
| EQ_PRESETS_PRESSED | 224 | 176 | 44 | 12 | PRESETS button pressed |

### EQ Graph
| Element | X | Y | Width | Height | Notes |
|---------|---|---|-------|--------|-------|
| EQ_GRAPH_BACKGROUND | 0 | 294 | 113 | 19 | Graph area background |
| EQ_GRAPH_LINE_COLORS | 115 | 294 | 1 | 19 | Color palette for graph line |

### Colored Slider Bars (Programmatic Implementation)

**Important Discovery:** The EQ slider colored bars are NOT sprite-based with multiple fill states. Instead, they are programmatically drawn with a **single solid color** that represents the current knob position.

**How it works:**
- The entire slider track is filled with ONE color
- The color is determined by WHERE the knob is positioned on the gradient scale
- The knob sits on top of this colored track

**Color Scale (based on knob position):**
| Knob Position | dB Value | Color |
|---------------|----------|-------|
| Top | +12dB (boost) | RED |
| Upper-middle | +6dB | Orange |
| Middle | 0dB | YELLOW |
| Lower-middle | -6dB | Yellow-green |
| Bottom | -12dB (cut) | GREEN |

**Visual Style:**
- Bar width: 4 pixels (slim, centered in track)
- Corner radius: 2 pixels (slightly rounded top and bottom)
- Drawn behind the slider thumb

**Implementation (SkinRenderer.swift):**
```swift
// Normalize knob position to 0-1 range
let normalized = (value + 12) / 24  // 0 = -12dB, 1 = +12dB

// Interpolate color from gradient stops
// Green (0.0) → Yellow (0.5) → Red (1.0)
let trackColor = interpolateColor(at: normalized, stops: colorStops)

// Draw rounded rect for the track
let path = NSBezierPath(roundedRect: barRect, xRadius: 2, yRadius: 2)
trackColor.setFill()
path.fill()
```

**Note:** The EQ_SLIDER_BACKGROUND sprite at (13, 164) in EQMAIN.BMP may contain pre-rendered states, but the programmatic approach provides more flexibility and matches the classic Winamp appearance better.

---

## EQ Window Layout (In-Window Coordinates)

The EQ window is 275x116 pixels (standard size):

### Element Positions (Winamp Y-axis: 0=top, increases downward)
```
Slider Positions:
- Preamp X: 21
- First Band X: 78  
- Band Spacing: 18 pixels between each band
- Slider Y: 38 (top of slider track)
- Slider Height: 63 pixels (travel distance)
- Slider Width: 11 pixels (knob width)

Button Positions:
- ON button: (14, 18) - 26x12
- AUTO button: (40, 18) - 32x12  
- PRESETS button: (217, 18) - 44x12
- Close button: (264, 3) - 9x9

Graph Position:
- Graph rect: (86, 17, 113, 19)

Title Bar:
- Height: 14 pixels
```

### Band Frequencies (left to right)
60Hz, 170Hz, 310Hz, 600Hz, 1kHz, 3kHz, 6kHz, 12kHz, 14kHz, 16kHz

---

## Coordinate System Notes

### Winamp vs macOS Coordinates
- **Winamp**: Y=0 at top, Y increases downward
- **macOS**: Y=0 at bottom, Y increases upward

### Transform Applied in Drawing
```swift
// Flip to Winamp coordinates
context.translateBy(x: 0, y: bounds.height)
context.scaleBy(x: 1, y: -1)
```

After this transform, drawing at Y=0 appears at the TOP of the view.

### Slider Value Mapping
```swift
// EQ band values: -12dB to +12dB
// Normalized: 0.0 to 1.0
let normalizedValue = (value + 12) / 24

// Thumb Y position (in Winamp coords)
// At +12dB (normalizedValue=1): thumb at TOP
// At -12dB (normalizedValue=0): thumb at BOTTOM  
let thumbY = sliderY + (sliderHeight - thumbSize) * (1 - normalizedValue)
```

---

## Known Issues & Future Work

### EQ Window
1. **Colored slider bars** - ✅ IMPLEMENTED. Programmatically drawn (not sprite-based). The bars:
   - Fill the entire track with a single solid color based on knob position
   - Color scale: RED (+12dB boost) → YELLOW (0dB) → GREEN (-12dB cut)
   - Slim design (4px wide) with rounded corners (2px radius)
   - Drawn behind the slider thumb

2. **Graph curve** - ✅ IMPLEMENTED. Uses the same color scale as slider bars:
   - Each line segment colored based on the band values it connects
   - RED for boosted frequencies, YELLOW for neutral, GREEN for cut

3. **Shade mode** - EQ shade mode (compact view) needs implementation

### Main Window
- Main window appears to render correctly with current skin

### Cast Indicator (Replaces Mono)
- The traditional "mono" indicator has been repurposed to show "CAST" status
- Uses the skin's text font (TEXT.BMP) instead of the monoster.bmp mono sprite
- Position: Same as mono indicator (212, 41), centered in the 27x12 area
- When casting is active: Text is fully lit (normal alpha)
- When casting is inactive: Text is dimmed (30% alpha, matching mono off state)
- Stereo indicator remains unchanged and shows audio channel info

### Playlist Window  
- Playlist sprites are in PLEDIT.BMP
- Colors defined in PLEDIT.TXT
- Needs full implementation review

### Window Docking/Snapping
- Basic snapping implemented in WindowManager
- Windows snap to each other within 10px threshold
- Docked windows move together as a group
- May need refinement for edge cases

---

## Implementation Files

### Key Source Files
- `Sources/AdAmp/Skin/SkinElements.swift` - All sprite coordinates and layout constants
- `Sources/AdAmp/Skin/SkinRenderer.swift` - Drawing code for all skin elements
- `Sources/AdAmp/Skin/SkinLoader.swift` - WSZ file loading and BMP parsing
- `Sources/AdAmp/Skin/Skin.swift` - Skin data model
- `Sources/AdAmp/Windows/Equalizer/EQView.swift` - EQ window view
- `Sources/AdAmp/Windows/Equalizer/EQWindowController.swift` - EQ window controller
- `Sources/AdAmp/App/WindowManager.swift` - Window management, snapping, docking

### Test Skin Location
- Default skin: `Sources/AdAmp/Resources/base-2.91.wsz`
- Extracted for testing: `/tmp/skin_extract/`

---

## Debugging Tips

### Extract and View Skin Files
```bash
# Extract skin to temp directory
unzip -o Sources/AdAmp/Resources/base-2.91.wsz -d /tmp/skin_extract

# Convert BMP to PNG for viewing
sips -s format png /tmp/skin_extract/EQMAIN.BMP --out /tmp/skin_extract/eqmain.png

# Check image dimensions
sips -g pixelHeight -g pixelWidth /tmp/skin_extract/EQMAIN.BMP
```

### Fetching Latest Webamp Coordinates
```bash
# Full sprite definitions
curl -s "https://raw.githubusercontent.com/captbaritone/webamp/master/packages/webamp/js/skinSprites.ts" > /tmp/skinSprites.ts
```

---

## Version History

- **2026-01-18**: Plex Browser tab selection styling
  - Removed blue background fill from selected tabs
  - Selected tab now indicated by white text only (cleaner look)

- **2026-01-17**: EQ colored slider bars and graph curve
  - Implemented colored slider track backgrounds (programmatic, not sprite-based)
  - Key insight: bars use a SINGLE solid color based on knob position, not gradient fill
  - Color scale: RED (+12dB) → YELLOW (0dB) → GREEN (-12dB)
  - Slim bar design (4px) with rounded corners (2px radius)
  - EQ graph curve now uses same color scale for line segments
  - Removed sprite-based approach in favor of programmatic drawing for flexibility

- **2026-01-17**: Playlist window skin implementation completed
  - Fully skinned playlist window using PLEDIT.BMP sprites
  - Implemented proper scaling architecture matching Main/EQ windows
  - Added comprehensive implementation notes: `docs/PLAYLIST_IMPLEMENTATION_NOTES.md`
  - Key learnings documented: coordinate systems, scaling, hit testing patterns

- **2026-01-16**: Initial research document created
  - Documented EQMAIN.BMP sprite coordinates from webamp
  - Fixed EQ slider knob (was 14x63, corrected to 11x11 at y=164)
  - Fixed ON/AUTO button coordinates
  - Implemented window dragging fix for EQ (sliders vs window drag)
  - Implemented basic window snapping/docking
  - Disabled colored bars pending proper sprite-based implementation

---

## Related Documentation

- **[PLAYLIST_IMPLEMENTATION_NOTES.md](./PLAYLIST_IMPLEMENTATION_NOTES.md)** - Detailed implementation guide covering coordinate systems, scaling architecture, hit testing patterns, and common pitfalls for the playlist window (applicable to all skinned windows)
