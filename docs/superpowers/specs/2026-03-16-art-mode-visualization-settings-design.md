# Art Mode: Visualization Settings — Design Spec

**Date:** 2026-03-16
**Status:** Approved

## Overview

Add a grouped visualization effect picker and a persistent startup-default setting to Art Mode's context menus. All changes are confined to `ModernLibraryBrowserView.swift`.

## Features

### 1. Grouped Effect List in Context Menu

The 30 `VisEffect` cases are organized into 5 named groups, each exposed as a submenu in both context menus:

| Group | Effects |
|---|---|
| Rotation & Scaling | Psychedelic, Kaleidoscope, Vortex, Endless Spin, Fractal Zoom, Time Tunnel |
| Distortion | Acid Melt, Ocean Wave, Glitch, RGB Split, Twist, Fisheye, Shatter, Rubber Band |
| Motion | Zoom Pulse, Earthquake, Bounce, Feedback Loop, Strobe, Jitter |
| Copies & Mirrors | Infinite Mirror, Tile Grid, Prism Split, Double Vision, Flipbook, Mosaic |
| Pixel Effects | Pixelate, Scanlines, Datamosh, Blocky |

Each effect item shows a checkmark (`.on`) when it is the current effect, and a bullet (`.mixed`) when it is the saved default but not currently active.

### 2. Default/Favorite Visualization

A new UserDefaults key `browserVisDefaultEffect` stores the user's chosen startup effect. On init, this key takes priority over `browserVisEffect` (last-used). The "Set Current as Default" menu item writes the current effect to this key.

**Init restoration priority:**
1. `browserVisDefaultEffect` (startup default, if set)
2. `browserVisEffect` (last-used fallback)
3. `.psychedelic` (hardcoded fallback)

## Menu Structure

### `showVisualizerMenu` (vis is active)

```
▶ <Current Effect Name>          ← disabled label
──────────────────
Rotation & Scaling  ▶
Distortion          ▶
Motion              ▶
Copies & Mirrors    ▶
Pixel Effects       ▶
──────────────────
Set Current as Default
──────────────────
Turn Off
```

### `showArtContextMenu` (vis is off)

```
Enable Visualization
Visualization       ▶
  ├── Rotation & Scaling  ▶
  ├── Distortion          ▶
  ├── Motion              ▶
  ├── Copies & Mirrors    ▶
  ├── Pixel Effects       ▶
  ├── ──────────────────
  └── Set Current as Default
──────────────────
Rate                ▶            (when track is rateable)
──────────────────
Exit Art View
```

## Implementation

All changes in `Sources/NullPlayer/Windows/ModernLibraryBrowser/ModernLibraryBrowserView.swift`.

### New UserDefaults Key
- `browserVisDefaultEffect` — raw string value of a `VisEffect` case

### New Members on `VisEffect`

```swift
static var groups: [(title: String, effects: [VisEffect])] { ... }
```

Returns the 5 group definitions in order.

### New Private Methods

| Method | Purpose |
|---|---|
| `buildVisEffectGroupSubmenus(into:)` | Appends grouped submenus to an `NSMenu`; shared by both menu builders |
| `menuSelectEffect(_:)` | `@objc` — reads `representedObject` as `String`, sets `currentVisEffect`, saves `browserVisEffect` |
| `menuSetDefaultEffect()` | `@objc` — saves `currentVisEffect.rawValue` to `browserVisDefaultEffect` |

### Modified Methods

| Method | Change |
|---|---|
| `init` / `viewDidLoad` restoration block | Check `browserVisDefaultEffect` before `browserVisEffect` |
| `showVisualizerMenu` | Replace "Next Effect →" with group submenus + "Set Current as Default" |
| `showArtContextMenu` | Add "Visualization ▶" item with nested group submenus + "Set Current as Default" |

## Out of Scope

- `visMode` (random/cycle) persistence — not part of this spec
- PlexBrowserView (classic UI) — not part of this spec
- Any other visualization system (main window, spectrum window)
