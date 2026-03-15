# Waveform Window Horizontal Stretch

**Date:** 2026-03-15
**Status:** Approved

## Overview

Allow the waveform window to be stretched horizontally in both Classic and Modern UI modes. The window starts at the skin's default width (matching the main window) but can be freely resized wider or narrower by the user. Width becomes independent of the main window — no coupling in either direction.

The minimum width is the skin's intrinsic minimum (275 × scale factor). Width is never scaled by the Double Size multiplier — only the height is affected by Double Size.

## Changes

### 1. `WindowManager.applyCenterStackSizingConstraints`

In the `.waveform` case, use the skin's intrinsic minimum for `minSize.width` and unlock `maxSize.width`:

```swift
// Before:
window.minSize = NSSize(width: targetSize.width, height: targetHeight)
window.maxSize = NSSize(width: targetSize.width, height: CGFloat.greatestFiniteMagnitude)

// After (waveform only):
let skinMinWidth: CGFloat  // SkinElements.WaveformWindow.minSize.width (Classic)
                           // or ModernSkinElements.waveformMinSize.width (Modern)
                           // both equal 275 * scaleFactor
window.minSize = NSSize(width: skinMinWidth, height: targetHeight)
window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
```

### 2. `WindowManager.normalizedCenterStackRestoredFrame`

For the `.waveform` case only, remove the two lines that clamp the restored frame to the main window:
- `normalized.origin.x = mainWindow.frame.minX`  ← remove for waveform
- `normalized.size.width = mainWindow.frame.width` ← remove for waveform

Height normalization in the same function (the HT-toggle compact/full height correction in the `playlist, waveform` block) is left intact — only the x-origin and width clamps are removed.

First-show (no saved frame) still goes through `applyDefaultCenterStackFrameForCurrentHT`, which defaults to main window width — intentional, unchanged.

### 3. `ModernWaveformWindowController`

**3a. `allowedResizeEdges`:** Change from `[.bottom]` to `[.bottom, .left, .right]`.

**3b. `setupWindow()` maxSize:** `setupWindow()` currently sets `window.maxSize = NSSize(width: window.minSize.width, height: CGFloat.greatestFiniteMagnitude)`. Change `maxSize.width` to `CGFloat.greatestFiniteMagnitude`. (`minSize` is already set to `ModernSkinElements.waveformMinSize` — no change needed there.)

### 4. `WaveformWindowController.setupWindow()` (Classic)

Both branches set `maxSize.width` to a locked value:

- **Main branch** (`if let mainWindow`): Keep frame width at `mainFrame.width` (correct default). Change `minSize.width` to `SkinElements.WaveformWindow.minSize.width` and `maxSize.width` to `CGFloat.greatestFiniteMagnitude`.
- **Else branch**: Change `maxSize.width` from `window.minSize.width` to `CGFloat.greatestFiniteMagnitude`. `minSize` is already `SkinElements.WaveformWindow.minSize` — no change needed.

`ResizableWindow` already handles all 4 resize edges — no edge changes needed for Classic.

### 5. `WindowManager.applyDoubleSize()`

The Double Size block resets waveform width in two branches. Preserve the current width in both; do not apply any scale multiplier to width (width is not a Double-Size-scaled dimension):

- **Visible branch** (`setFrame`): Use `waveformWindow.frame.width` instead of `targetWidth`. Position at `x: mainFrame.minX` (left-aligned to main, consistent with stack behavior).
- **Hidden branch** (`setContentSize`): Change `NSSize(width: targetWidth, height: newHeight)` to `NSSize(width: waveformWindow.frame.width, height: newHeight)`.

In both branches: set `minSize.width` to `skinMinWidth` (intrinsic) and `maxSize.width` to `CGFloat.greatestFiniteMagnitude`.

### 6. `WindowManager` HT-toggle `windowsBelow` loop

The loop sets `winFrame.size.width = frame.width` for every docked-below window. Skip this width assignment for the waveform window with a guard. The `origin.x = frame.minX` line in the same loop is kept for waveform — waveform is always left-aligned with the main window, even when wider.

(The `applyCenterStackSizingConstraints` call earlier in the same loop is correct after change #1.)

### 7. `AppStateManager.repairClassicCenterStackFrames`

`normalizedFlushFrame` always sets `width: adjustedMain.width`, snapping any stretched waveform back to main width on dock repair. Add a `preserveWidth` parameter and pass `true` for the waveform call site:

```swift
func normalizedFlushFrame(for candidate: NSRect, below anchor: NSRect, preserveWidth: Bool = false) -> NSRect {
    NSRect(
        x: adjustedMain.minX,
        y: anchor.minY - candidate.height,
        width: preserveWidth ? candidate.width : adjustedMain.width,
        height: candidate.height
    )
}
```

Waveform is the last candidate in the repair chain — no window currently stacks below it, so a wide `anchorFrame` after waveform repair has no downstream effect.

Note: `repairClassicDockedStackWidthsIfNeeded` (restore-time repair) calls this same function, so this fix covers both the live and restore-time repair paths.

## Non-Changes

- **Views:** `WaveformView` and `ModernWaveformView` use `.width + .height` autoresizing masks and compute `waveformRect` from live bounds. No view changes needed.
- **State persistence:** Window frame (including width) is already saved/restored via `AppState`. No new fields needed.
- **Docking:** Vertical stack docking is unaffected.
- **First-show default width:** `applyDefaultCenterStackFrameForCurrentHT` defaults to main window width. Intentional, not changed.
- **Horizontal alignment:** `positionSubWindow` and HT-toggle loop both left-align to `mainFrame.minX`. A wider waveform extends to the right. No change needed.

## Scope

Seven targeted edits across four files:
- `WindowManager.swift` — changes 1, 2, 5, 6
- `ModernWaveformWindowController.swift` — change 3
- `WaveformWindowController.swift` — change 4
- `AppStateManager.swift` — change 7

No new files, no new state, no view changes.
