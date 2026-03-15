# Connected Window Drag Rules — Design Spec

**Date:** 2026-03-15
**Branch:** window-rules-experimental
**Status:** Approved

---

## Summary

Replace the current distance-based undock mechanism with a time-based hold model. How long the user holds before dragging determines whether the window moves alone (short hold) or moves with its connected group (long hold). All dockable windows are treated identically — no special cases for the main window.

---

## Behavior Rules

| Interaction | Result |
|---|---|
| Short hold + drag (< 400ms) | Dragged window detaches from group; moves alone |
| Long hold + drag (≥ 400ms) | All connected windows move together as a group |
| No connected windows | Window always moves alone regardless of hold duration |

When a window detaches via short hold, its former connected peers remain connected to each other — only the dragged window separates.

---

## Hold State Machine

### New state in `WindowManager`

```swift
private var holdStartTime: CFTimeInterval?
private let holdThreshold: TimeInterval = 0.4  // 400ms
private var dragMode: DragMode = .pending

private enum DragMode {
    case pending   // mouseDown received, drag not yet started
    case separate  // drag started before threshold — window moves alone
    case group     // threshold elapsed before drag — connected windows move together
}
```

### Event flow

1. **`windowWillStartDragging(_:fromTitleBar:)`**
   - Sets `holdStartTime = CACurrentMediaTime()`
   - Sets `dragMode = .pending`
   - Finds connected windows via existing BFS (`findDockedWindows`)
   - Posts `connectedWindowHighlightDidChange` with connected peers (if any)

2. **First call to `windowWillMove(_:to:)`**
   - If `dragMode == .pending`: determine mode based on elapsed time
     - `elapsed < holdThreshold` → `.separate`: clear `dockedWindowsToMove`; the window drags alone and detaches
     - `elapsed >= holdThreshold` → `.group`: proceed with existing group-move logic unchanged
   - Subsequent calls skip mode determination (mode is already set)

3. **`windowDidFinishDragging(_:)`**
   - Clears `holdStartTime`
   - Resets `dragMode = .pending`
   - Posts `connectedWindowHighlightDidChange` with empty set (clears highlight)
   - Existing cleanup (snapping, child window updates, etc.) unchanged

### Removed

The existing `undockThreshold` (10px distance check) and its associated `isTitleBarDrag` / `isMainWindow` guard are removed. The timing model fully replaces them.

---

## Highlight System

Connected peers are highlighted immediately at `mouseDown` to show the user which windows belong to the group.

### Notification

```swift
static let connectedWindowHighlightDidChange = Notification.Name("connectedWindowHighlightDidChange")
// userInfo key: "highlightedWindows" — value: Set<NSWindow>
// Empty set = clear all highlights
```

- Posted at `windowWillStartDragging` with the set of connected peers (not the dragging window itself)
- Posted at `windowDidFinishDragging` and when `.separate` mode is confirmed, with an empty set

### Rendering

Each dockable window view (classic and modern) observes the notification:

- Maintains a local `isHighlighted: Bool` flag
- Sets `needsDisplay = true` on change
- In `draw(_:)`: when `isHighlighted`, draws a semi-transparent overlay (e.g. `NSColor.white.withAlphaComponent(0.15)`) over the window content

The dragging window itself is **never** highlighted — only its connected peers are shown, so the user can clearly see what's attached to what they're grabbing.

**No connected windows:** If the dragged window has no connected peers, no notification is posted and no highlight appears.

---

## Interaction Protection

No changes to widget protection. The existing per-view `mouseDown` hit-testing already gates `windowWillStartDragging` — it is only called after confirming the click is not on a button, slider, or visualization area. The hold timer therefore cannot activate through widget interactions.

Widgets that use drag motions (seek slider, volume slider, balance slider) already short-circuit `mouseDragged` via the `draggingSlider` flag before `windowWillMove` is reached. This is unchanged.

---

## Affected Files

| File | Change |
|---|---|
| `App/WindowManager.swift` | Add `DragMode` enum, `holdStartTime`, `holdThreshold`, `dragMode` state; update `windowWillStartDragging`, `windowWillMove`, `windowDidFinishDragging`; add `connectedWindowHighlightDidChange` notification; remove `undockThreshold` distance check |
| `Windows/MainWindow/MainWindowView.swift` | Observe highlight notification, draw overlay |
| `Windows/Playlist/PlaylistView.swift` | Observe highlight notification, draw overlay |
| `Windows/Equalizer/EQView.swift` | Observe highlight notification, draw overlay |
| `Windows/ModernMainWindow/ModernMainWindowView.swift` | Observe highlight notification, draw overlay |
| `Windows/ModernPlaylist/ModernPlaylistView.swift` | Observe highlight notification, draw overlay |
| `Windows/ModernWaveform/ModernWaveformView.swift` | Observe highlight notification, draw overlay |
| `Windows/ModernEQ/ModernEQView.swift` | Observe highlight notification, draw overlay |
| `Windows/Spectrum/SpectrumWindowController.swift` (or view) | Observe highlight notification, draw overlay |
| `Windows/ModernSpectrum/ModernSpectrumView.swift` | Observe highlight notification, draw overlay |

---

## Out of Scope

- Haptic feedback on hold threshold crossing
- Animated highlight transitions
- Configurable hold threshold in preferences
- Any changes to snapping, docking detection, or child window tracking
