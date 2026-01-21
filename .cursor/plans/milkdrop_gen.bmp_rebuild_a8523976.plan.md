---
name: Milkdrop Gen.bmp Rebuild
overview: Rebuild the Milkdrop visualization window chrome using proper GEN.BMP sprites from the Gen.gif reference image, replacing the custom milkdrop_titlebar.png with authentic Winamp-style title bar, borders, and alphabet font.
todos:
  - id: add-gen-asset
    content: Download Gen.gif, convert to PNG, and add to Resources folder
    status: completed
  - id: fix-sprite-coords
    content: Verify and fix SkinElements.GenWindow and GenFont sprite coordinates against actual Gen.gif
    status: completed
  - id: update-skin-loader
    content: Add genWindowImage property to Skin.swift for fallback loading from bundle
    status: completed
  - id: rebuild-renderer
    content: Replace SkinRenderer.drawMilkdropWindow methods to use GEN.BMP sprites (title bar, borders, alphabet)
    status: completed
  - id: update-layout
    content: Update MilkdropView and SkinElements.Milkdrop.Layout for 20px title bar and 11px borders
    status: completed
---

# Milkdrop Window Rebuild with GEN.BMP Sprites

## Problem

The current Milkdrop window uses a custom `milkdrop_titlebar.png` (1518x48) that doesn't match the classic Winamp style. The title bar and borders look "off" compared to authentic Winamp skins.

## Solution

Rebuild the Milkdrop window using GEN.BMP sprites from the reference Gen.gif at https://winampskins.neocities.org/images/Gen.gif. This provides:

- Proper title bar with left corner, tileable middle, and right corner with close button
- Left/right side borders that tile vertically
- Bottom bar with corners and tileable middle section
- Pixel alphabet (A-Z, 0-9) for drawing "MILKDROP" title text

## GEN.BMP Sprite Layout (194x109 pixels)

Based on the [Winamp skin tutorial](https://winampskins.neocities.org/twonine.html):

```
Y=0-19:    Title bar ACTIVE
        - Left corner (25px wide)
        - Tileable middle (29px, starts at x=26)
        - Right corner with close button (41px, starts at x=153)

Y=21-40:   Title bar INACTIVE (same structure)

Y=42-70:   Side borders
        - Left border tile (11px wide, at x=0)
        - Right border tile (11px wide, at x=12)

Y=72-85:   Bottom bar
        - Bottom-left corner (11px, at x=0)
        - Bottom tile (29px, at x=12)
        - Bottom-right corner (11px, at x=42)

Y=88-93:   Alphabet A-Z (5x6 px each, 1px spacing)
Y=96-101:  Numbers 0-9 and symbols (5x6 px each)
```

## Key Files

- [SkinElements.swift](Sources/AdAmp/Skin/SkinElements.swift) - Update GenWindow sprite coordinates (fix font Y positions)
- [SkinRenderer.swift](Sources/AdAmp/Skin/SkinRenderer.swift) - Replace drawMilkdropWindow methods to use GEN.BMP sprites
- [MilkdropView.swift](Sources/AdAmp/Windows/Milkdrop/MilkdropView.swift) - Update layout constants for 20px title bar
- [Skin.swift](Sources/AdAmp/Skin/Skin.swift) - Ensure gen image is loaded from skin or bundle
- `Sources/AdAmp/Resources/gen.png` - Add converted Gen.gif as fallback asset

## Implementation

### 1. Add Gen.gif Asset as PNG

Download Gen.gif from the tutorial site and convert to PNG:

- Save as `Sources/AdAmp/Resources/gen.png` 
- Add to Package.swift resources

### 2. Fix SkinElements.GenWindow Coordinates

Current font positions may be wrong. Verify against actual Gen.gif:

```swift
struct GenFont {
    static let alphabetY: CGFloat = 88   // Row containing A-Z
    static let numbersY: CGFloat = 96    // Row containing 0-9
}
```

### 3. Update SkinRenderer.drawMilkdropWindow

Replace the current implementation to:

1. Draw title bar: left corner + tiled middle + right corner
2. Draw side borders: tile left/right borders vertically
3. Draw bottom bar: left corner + tiled middle + right corner  
4. Draw "MILKDROP" text using GenFont alphabet sprites

### 4. Update MilkdropView Layout

Change from 14px title bar to 20px:

```swift
struct Layout {
    static let titleBarHeight: CGFloat = 20  // Was 14
    static let leftBorder: CGFloat = 11      // Was 3
    static let rightBorder: CGFloat = 11     // Was 3
    static let bottomBorder: CGFloat = 14    // Was 3
}
```

### 5. Add Fallback Image Loading

Update `Skin.swift` to load gen.png from bundle when skin doesn't include GEN.BMP:

```swift
static var genWindowImage: NSImage? {
    guard let url = Bundle.module.url(forResource: "gen", withExtension: "png") else { return nil }
    return NSImage(contentsOf: url)
}
```

## Visual Reference

The Gen.gif shows the complete sprite sheet:

- Two rows of title bar (active top, inactive below)
- Decorative grip marks on left corner
- Close button in right corner
- Dark blue/purple color scheme with gold/tan highlights
- Pixel alphabet for window titles