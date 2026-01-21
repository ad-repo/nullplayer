# Skin Selection UI & Full Skin Compliance

## Overview

Add user-facing skin selection so users can load any Winamp skin (.wsz) from places like the [Winamp Skin Museum](https://skins.webamp.org/). Ensure all windows (including Browser, Media Library, Milkdrop) properly adapt to loaded skins for a cohesive look.

## HARD RULE

**The current look and feel with the default skin (base-2.91.wsz) CANNOT be modified.** All existing rendering must remain exactly as it is. New skin support must be additive only.

## Goals

1. Let users browse and load .wsz skin files
2. Persist selected skin across app launches
3. Support hot-reload (change skins without restart)
4. **All windows look correct with any skin** (not just built-in windows)
5. **Default skin appearance is unchanged** (hard requirement)

## Current State

- SkinLoader already extracts and parses .wsz files
- All windows respond to `notifySkinChanged()`
- Default skin (base-2.91.wsz) is bundled in Resources
- REGION.TXT parsed but not applied (custom window shapes)
- **Problem**: Browser, Media Library, Milkdrop use custom sprites that won't match other skins

## Winamp Window Types & Proper Sprites

| Window Type | Sprite Source | Notes |

|-------------|---------------|-------|

| Main | MAIN.BMP, TITLEBAR.BMP, CBUTTONS.BMP | ✅ Already correct |

| Equalizer | EQMAIN.BMP | ✅ Already correct |

| Playlist | PLEDIT.BMP | ✅ Already correct |

| Media Library | GEN.BMP | ❌ Currently uses PLEDIT.BMP |

| AVS/Milkdrop | GEN.BMP | ❌ Currently uses custom PNG |

| Browser | GEN.BMP or PLEDIT.BMP | ⚠️ Uses PLEDIT.BMP (acceptable) |

## Tasks

### Phase 1: Add GEN.BMP Support for Non-Default Skins (DEFERRED)

**Status: DISABLED** - GEN.BMP rendering was implemented but disabled due to:

1. Incorrect sprite coordinates in SkinElements.swift (font Y positions wrong)
2. Many skins don't include font glyphs in GEN.BMP at all
3. Coordinate system issues causing mirrored/corrupted text

**Current behavior:** All windows use PLEDIT.BMP-style sprites regardless of skin.

This provides consistent appearance but doesn't match each skin's unique GEN.BMP styling.

**Future work needed:**

- Research accurate GEN.BMP coordinates from actual skin files
- Determine which skins include font glyphs vs. not
- Fix coordinate transformations for proper sprite extraction

- [x] 1.1 Add `isDefaultSkin` check to WindowManager/SkinLoader ✅
- [x] 1.2 Add GEN.BMP rendering methods to SkinRenderer ✅ (implemented but disabled)
- [ ] 1.3 Update Milkdrop window: use GEN.BMP (DISABLED - needs coordinate fixes)
- [ ] 1.4 Update Media Library window: use GEN.BMP (DEFERRED)
- [x] 1.5 Keep existing PLEDIT.BMP/custom PNG rendering as fallback ✅
- [x] 1.6 Test: default skin must look exactly the same as before ✅

### Phase 2: Skin Selection UI ✅

- [x] 2.1 Add "Skins" submenu to context menu
- [x] 2.2 Add "Load Skin..." menu item with NSOpenPanel
- [x] 2.3 Copy selected skin to Application Support/AdAmp/Skins/
- [x] 2.4 Load and apply selected skin via SkinLoader
- [x] 2.5 Call WindowManager.notifySkinChanged() to refresh all windows

### Phase 3: Skin Persistence ✅

- [x] 3.1 Store current skin path in UserDefaults
- [x] 3.2 Load saved skin on app launch (fallback to default if missing)
- [x] 3.3 Add "Reset to Default Skin" menu option

### Phase 4: Skin Management UI ✅

- [x] 4.1 List installed skins in Skins submenu
- [x] 4.2 Show checkmark next to currently active skin
- [x] 4.3 Click skin name to switch to it
- [x] 4.4 Add "Open Skins Folder" option

### Phase 5: Window Regions (Custom Shapes) - Optional

- [ ] 5.1 Create NSBezierPath from REGION.TXT point lists
- [ ] 5.2 Apply region as window mask for non-rectangular windows

### Phase 6: Custom Cursors - Optional

- [ ] 6.1 Implement .cur file parser
- [ ] 6.2 Apply custom cursors to UI elements

## File Changes

### Phase 1 Files (Skin Compatibility)

- `Sources/AdAmp/Skin/SkinElements.swift` - Add GEN.BMP sprite definitions
- `Sources/AdAmp/Skin/SkinRenderer.swift` - Add GEN.BMP rendering methods
- `Sources/AdAmp/Windows/Milkdrop/MilkdropView.swift` - Use GEN.BMP sprites
- `Sources/AdAmp/Windows/MediaLibrary/MediaLibraryView.swift` - Use GEN.BMP sprites
- `Sources/AdAmp/Windows/PlexBrowser/PlexBrowserView.swift` - Use skin TEXT.BMP font

### Phase 2-4 Files (UI & Persistence)

- `Sources/AdAmp/App/ContextMenuBuilder.swift` - Add Skins submenu
- `Sources/AdAmp/App/AppDelegate.swift` - Add menu bar items
- `Sources/AdAmp/App/WindowManager.swift` - Add skin management methods
- `Sources/AdAmp/Skin/SkinLoader.swift` - Add persistence, skin listing

### Files to Keep (Default Skin Assets)

- `Sources/AdAmp/Resources/milkdrop_titlebar.png` - KEEP as default/fallback (hard rule)
- All existing custom sprites remain unchanged for default skin

## Implementation Notes

### Skin Storage Location

```
~/Library/Application Support/AdAmp/Skins/
├── base-2.91.wsz (copied from bundle on first run)
├── user-skin-1.wsz
└── user-skin-2.wsz
```

### UserDefaults Keys

- `currentSkinPath` - Path to active skin file (relative to Skins folder)
- `currentSkinName` - Display name for menu

### Menu Structure

```
Right-click → Skins
  ├── Load Skin...
  ├── ─────────────
  ├── ✓ Base 2.91 (default)
  ├── Custom Skin 1
  ├── Custom Skin 2
  ├── ─────────────
  ├── Reset to Default
  └── Open Skins Folder
```

### Hot Reload Flow

1. User selects skin
2. SkinLoader.load(from: url) parses .wsz
3. WindowManager.shared.currentSkin = newSkin
4. WindowManager.shared.notifySkinChanged()
5. Each window controller calls skinDidChange() → redraws

## GEN.BMP Sprite Layout (194x109)

GEN.BMP is the proper source for Media Library and AVS/Milkdrop windows:

```
Y=0-19:   Title bar ACTIVE (left corner 25px, tile 29px, right corner 41px with buttons)
Y=21-40:  Title bar INACTIVE
Y=42-62:  Window borders (left, right, bottom corners and tiles)
Y=72-78:  Alphabet A-Z (5x6 pixels, 1px spacing)
Y=79-85:  Numbers 0-9 and symbols
```

### Already Defined in SkinElements.swift

- `GenWindow.TitleBarActive` - left corner, tile, right corner
- `GenWindow.TitleBarInactive` - same for inactive state
- `GenWindow.Borders` - corner and edge sprites
- `GenFont` - character positions for A-Z, 0-9

### What Needs Implementation

1. `SkinLoader.isDefaultSkin` - property to detect if current skin is the bundled default
2. `SkinRenderer.drawGenWindowTitleBar()` - NEW method for GEN.BMP title bar
3. `SkinRenderer.drawGenWindowBorders()` - NEW method for GEN.BMP borders  
4. `SkinRenderer.drawGenText()` - NEW method for GEN.BMP font
5. Update MilkdropView: add conditional - if non-default skin has GEN.BMP, use it; else keep current rendering
6. Update MediaLibraryView: same conditional approach
7. **All existing rendering code paths remain unchanged** (default skin behavior preserved)

## Testing

### Critical (Hard Rule Verification)

- [ ] **DEFAULT SKIN UNCHANGED**: Verify base-2.91.wsz looks exactly the same as before any changes
- [ ] **Screenshot comparison**: Compare against reference screenshot (provided in plan conversation)

**Reference Screenshot**: `docs/screenshots/default_skin_reference.png`

![Default Skin Reference](../docs/screenshots/default_skin_reference.png)

Windows shown:

- Milkdrop: Dark "MILKDROP" title bar, blue-gray borders, dark content area
- Main: Classic green/black Winamp look, "WINAMP" title
- Playlist: "WINAMP PLAYLIST", green text on dark background
- Equalizer: "WINAMP EQUALIZER", green sliders, dark background  
- Library: "WINAMP LIBRARY", green text, dark background, alphabetical index

### Functional Tests

- [ ] Load skin from Winamp Skin Museum
- [ ] Verify all windows update correctly with new skin
- [ ] Verify skin persists after restart
- [ ] Test switching between multiple skins
- [ ] Test "Reset to Default" functionality
- [ ] Test with skins that have missing GEN.BMP (fallback to current behavior)
- [ ] Test Browser/Library/Milkdrop windows with various skins

## References

- Winamp Skin Museum: https://skins.webamp.org/
- Webamp sprite coordinates: https://github.com/captbaritone/webamp/blob/master/packages/webamp/js/skinSprites.ts
- Existing skin format research: docs/SKIN_FORMAT_RESEARCH.md