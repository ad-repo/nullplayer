# Connected Window Drag Rules — Design Spec

**Date:** 2026-03-15
**Branch:** window-rules-experimental
**Status:** Approved

---

## Summary

Replace the current distance-based undock mechanism with a time-based hold model. How long the user holds before dragging determines whether the window moves alone (short hold) or moves with its connected group (long hold). All dockable windows are treated identically — including the main window.

---

## Drag Architecture Note

All dockable windows set `isMovableByWindowBackground = false`, disabling macOS system-level window dragging. Each window view handles drag events manually via `mouseDown` / `mouseDragged` / `mouseUp` overrides that call directly into `WindowManager`. This means `windowWillStartDragging` is called synchronously from within the view's `mouseDown` — it is not a system drag callback. `holdStartTime` is therefore effectively captured at mouseDown time, making sub-second timing reliable.

---

## Behavior Rules

| Interaction | Result |
|---|---|
| Short hold + drag (< 400ms) | Dragged window detaches from group; moves alone |
| Long hold + drag (≥ 400ms) | All connected windows move together as a group |
| No connected windows | Window always moves alone regardless of hold duration |

**Main window:** Treated the same as all other windows. A short-hold drag on the main window detaches it from its group; a long-hold drag moves the group. This is a deliberate behavior change from the current system (which always moved the main window with its group).

**Body-area drags:** The `fromTitleBar` parameter is preserved in `windowWillStartDragging` for reference but is no longer used to gate undock logic. Both title-bar and body-area drags use the same hold-timing model.

**Peer connectivity after detach:** When a window detaches via short hold, former peers remain connected to each other. No explicit graph update is needed — connectivity is position-derived (BFS adjacency check) and peers have not moved during the hold period (no `windowWillMove` calls have occurred). BFS on peers after detach correctly returns the unchanged peer group.

The 400ms threshold aligns with typical macOS long-press conventions and feels responsive without triggering on accidental short clicks.

---

## Hold State Machine

### New state in `WindowManager`

```swift
private var holdStartTime: CFTimeInterval?
private let holdThreshold: TimeInterval = 0.4  // 400ms
private var dragMode: DragMode = .pending
private var highlightWasPosted: Bool = false

private enum DragMode {
    case pending   // mouseDown received, drag not yet started
    case separate  // drag started before threshold — window moves alone
    case group     // threshold elapsed before drag — connected windows move together
}
```

### Event flow

1. **`windowWillStartDragging(_:fromTitleBar:)`** — called from view's `mouseDown`
   - Sets `holdStartTime = CACurrentMediaTime()`, `dragMode = .pending`
   - Finds connected windows via existing BFS (`findDockedWindows`)
   - If connected peers exist: posts `connectedWindowHighlightDidChange` with peer set; sets `highlightWasPosted = true`
   - Stores `dockedWindowOriginalOrigins` for peers (same as today — needed for restore on `.separate`)

2. **First call to `windowWillMove(_:to:)`** where `dragMode == .pending`:
   - Calculates `elapsed = CACurrentMediaTime() - (holdStartTime ?? 0)`
   - `elapsed < holdThreshold` → `.separate`:
     - Sets `dragMode = .separate`
     - Restores all peers to `dockedWindowOriginalOrigins` (same restore logic as existing undock path)
     - Clears `dockedWindowsToMove`, `dockedWindowOffsets`, `dockedWindowOriginalOrigins`
     - If `highlightWasPosted`: posts empty `connectedWindowHighlightDidChange`; sets `highlightWasPosted = false`
   - `elapsed >= holdThreshold` → `.group`:
     - Sets `dragMode = .group`
     - Proceeds with existing group-move logic unchanged
   - Subsequent calls: skip determination (mode already set)
   - **Fallback — `holdStartTime == nil`** (drag detected without a prior `mouseDown` call, e.g. via the existing `draggingWindow !== window` re-entry path in `windowWillMove`): set `dragMode = .group` and proceed with group-move logic. This preserves existing behavior for the edge case where dragging is detected mid-flight.

3. **`windowDidFinishDragging(_:)`**
   - Clears `holdStartTime = nil`, resets `dragMode = .pending`
   - If `highlightWasPosted`: posts empty `connectedWindowHighlightDidChange`; sets `highlightWasPosted = false`
   - Existing cleanup (snapping, child window updates, tighten stack, etc.) unchanged

4. **Window closed mid-drag**: `WindowManager` observes `NSWindow.willCloseNotification` centrally. If the closing window is `draggingWindow`, calls `windowDidFinishDragging` to clean up hold state. No changes to individual window controllers.

### Removed

The existing `undockThreshold` (10px distance check) and its `!isMainWindow && isTitleBarDrag && !dockedWindowsToMove.isEmpty` guard in `windowWillMove` are removed. These guarded undock logic only — not widget protection, which operates at the view layer before any `WindowManager` call. The `isTitleBarDrag` property is preserved for possible future use but is no longer read in the undock path.

---

## Highlight System

Connected peers are highlighted immediately at `mouseDown` to show the user which windows belong to the group.

### Notification

```swift
static let connectedWindowHighlightDidChange = Notification.Name("connectedWindowHighlightDidChange")
// userInfo key: "highlightedWindows" — value: Set<NSWindow>
// Empty set = clear all highlights
```

- Posted at `windowWillStartDragging` with peer set (only if peers exist)
- Posted when `.separate` mode is confirmed (empty set, only if `highlightWasPosted`)
- Posted at `windowDidFinishDragging` (empty set, only if `highlightWasPosted`)
- Never posted for solo-window drags (no peers = no spurious notifications)

**Brief flash on short-hold:** For short-hold drags, the highlight may appear for up to one event loop before the first `mouseDragged` fires and `.separate` clears it. This is imperceptible in practice.

### Rendering

Each dockable window view observes `connectedWindowHighlightDidChange` and checks whether its `window` is in the `highlightedWindows` set.

**Classic views** (`MainWindowView`, `PlaylistView`, `EQView`, `WaveformView`, classic `SpectrumView`):
- Maintain an `isHighlighted: Bool` flag
- On change: call `needsDisplay = true`
- In `draw(_:)`: if `isHighlighted`, fill `bounds` with `NSColor.white.withAlphaComponent(0.15)` **after** the skin render pass (so it overlays the skin)

**Modern views** (`ModernMainWindowView`, `ModernPlaylistView`, `ModernWaveformView`, `ModernEQView`, `ModernSpectrumView`):
- Use a `@State` bool or `@ObservedObject` observable driven by the notification
- Render `Color.white.opacity(0.15)` as a `.overlay` on the root view

The dragging window is **never** highlighted — only its connected peers.

---

## Interaction Protection

No changes to widget protection. Per-view `mouseDown` hit-testing gates `windowWillStartDragging` — it is only called after confirming the click is not on a button, slider, or visualization area.

Widgets using drag motions (seek slider, volume slider, balance slider) short-circuit `mouseDragged` via the `draggingSlider` flag before `windowWillMove` is reached. Removing `isTitleBarDrag` from the undock check does not affect this — slider and button hit-testing is handled entirely within the view's `mouseDown`, independent of `isTitleBarDrag`.

---

## Affected Files

| File | Change |
|---|---|
| `App/WindowManager.swift` | Add `DragMode` enum, `holdStartTime`, `holdThreshold`, `dragMode`, `highlightWasPosted` state; update `windowWillStartDragging`, `windowWillMove`, `windowDidFinishDragging`; add `connectedWindowHighlightDidChange` notification; add `NSWindow.willCloseNotification` observer for mid-drag cleanup; remove `undockThreshold` and undock distance check |
| `Windows/MainWindow/MainWindowView.swift` | Observe highlight notification, draw overlay in `draw(_:)` |
| `Windows/Playlist/PlaylistView.swift` | Observe highlight notification, draw overlay in `draw(_:)` |
| `Windows/Equalizer/EQView.swift` | Observe highlight notification, draw overlay in `draw(_:)` |
| `Windows/Waveform/WaveformView.swift` | Observe highlight notification, draw overlay in `draw(_:)` |
| `Windows/Spectrum/` (classic spectrum view) | Observe highlight notification, draw overlay in `draw(_:)` |
| `Windows/ModernMainWindow/ModernMainWindowView.swift` | Observe highlight notification, render overlay |
| `Windows/ModernPlaylist/ModernPlaylistView.swift` | Observe highlight notification, render overlay |
| `Windows/ModernWaveform/ModernWaveformView.swift` | Observe highlight notification, render overlay |
| `Windows/ModernEQ/ModernEQView.swift` | Observe highlight notification, render overlay |
| `Windows/ModernSpectrum/ModernSpectrumView.swift` | Observe highlight notification, render overlay |

---

## Out of Scope

- Haptic feedback on hold threshold crossing
- Animated highlight transitions
- Configurable hold threshold in preferences
- Any changes to snapping, docking detection, or child window tracking
