# Connected Window Drag Rules Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the distance-based undock mechanism with a time-based hold model — short hold (<400ms) detaches a window from its group, long hold (≥400ms) moves all connected windows together — and add visual highlight on connected peers during the hold phase.

**Architecture:** `WindowManager` gains a `DragMode` state machine evaluated at the first `windowWillMove` call. A `connectedWindowHighlightDidChange` notification is posted at drag start and cleared when mode is determined or drag ends. All 10 dockable window views subscribe to the notification and draw a semi-transparent overlay when highlighted.

**Tech Stack:** Swift, AppKit, NotificationCenter, `CACurrentMediaTime` (CoreVideo timing)

**Spec:** `docs/superpowers/specs/2026-03-15-connected-window-drag-rules-design.md`

---

## Chunk 1: WindowManager State Machine

### Task 1: Add DragMode enum, new state, notification name; remove undockThreshold

**Files:**
- Modify: `Sources/NullPlayer/App/WindowManager.swift`

No test yet — this task is additive scaffolding only. The testable logic is extracted in Task 2.

- [ ] **Step 1: Add notification name**

In `WindowManager.swift` at the top-level `extension Notification.Name` block (around line 5), add:

```swift
static let connectedWindowHighlightDidChange = Notification.Name("connectedWindowHighlightDidChange")
```

- [ ] **Step 2: Add DragMode enum**

After the `TimeDisplayMode` enum (early in the file, before the `WindowManager` class), add:

```swift
/// Determines how a window drag affects its connected group.
enum DragMode {
    case pending   // mouseDown received, drag not yet started
    case separate  // drag started before holdThreshold — window moves alone
    case group     // holdThreshold elapsed before drag — connected windows move together
}
```

- [ ] **Step 3: Replace undockThreshold with hold state**

In `WindowManager.swift` around line 314, replace:
```swift
/// Undock threshold - how far you need to drag a window to break it free from the group
private let undockThreshold: CGFloat = 10
```
with:
```swift
/// Hold threshold - how long (seconds) before a drag moves the connected group
let holdThreshold: TimeInterval = 0.4

/// Time when current drag's mouseDown was received
private var holdStartTime: CFTimeInterval?

/// Current drag mode, determined on first windowWillMove call
private var dragMode: DragMode = .pending

/// Whether a connectedWindowHighlightDidChange notification was posted for this drag
private var highlightWasPosted = false
```

All new properties are `private`. Tests only use the `static func determineDragMode(holdStart:currentTime:threshold:)` which takes threshold as a parameter — no instance property access needed.

- [ ] **Step 4: Build to confirm no errors**

```bash
cd /Users/ad/Projects/nullplayer && swift build 2>&1 | head -40
```
Expected: build succeeds (undockThreshold reference in windowWillMove will cause an error — that's expected; it's replaced in Task 3).

> **Timing design note:** Mode is intentionally evaluated at the first `mouseDragged` event (first `windowWillMove` call), not via a timer. The time elapsed between `mouseDown` and first mouse movement IS the hold duration. If the user presses down and immediately moves → short hold → separate. If the user holds 500ms before moving → long hold → group. This is correct per spec. Brief highlight flash on short-hold drags is acknowledged acceptable.

- [ ] **Step 5: Commit**

```bash
git add Sources/NullPlayer/App/WindowManager.swift
git commit -m "feat: add DragMode enum and hold state to WindowManager"
```

---

### Task 2: Extract determineDragMode() static function (TDD)

**Files:**
- Modify: `Sources/NullPlayer/App/WindowManager.swift`
- Create: `Tests/NullPlayerTests/WindowManagerDragModeTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/NullPlayerTests/WindowManagerDragModeTests.swift`:

```swift
import XCTest
@testable import NullPlayer

final class WindowManagerDragModeTests: XCTestCase {

    func testShortHoldReturnsSeparate() {
        // Elapsed 0.1s < 0.4s threshold → separate
        let mode = WindowManager.determineDragMode(
            holdStart: 1000.0,
            currentTime: 1000.1,
            threshold: 0.4
        )
        XCTAssertEqual(mode, .separate)
    }

    func testLongHoldReturnsGroup() {
        // Elapsed 0.5s >= 0.4s threshold → group
        let mode = WindowManager.determineDragMode(
            holdStart: 1000.0,
            currentTime: 1000.5,
            threshold: 0.4
        )
        XCTAssertEqual(mode, .group)
    }

    func testExactThresholdReturnsGroup() {
        // Elapsed == threshold → group
        let mode = WindowManager.determineDragMode(
            holdStart: 1000.0,
            currentTime: 1000.4,
            threshold: 0.4
        )
        XCTAssertEqual(mode, .group)
    }

    func testNilHoldStartReturnsGroup() {
        // nil holdStart (mid-flight detection fallback) → group
        let mode = WindowManager.determineDragMode(
            holdStart: nil,
            currentTime: 1000.0,
            threshold: 0.4
        )
        XCTAssertEqual(mode, .group)
    }

    func testZeroElapsedReturnsSeparate() {
        // Elapsed 0s → separate
        let mode = WindowManager.determineDragMode(
            holdStart: 1000.0,
            currentTime: 1000.0,
            threshold: 0.4
        )
        XCTAssertEqual(mode, .separate)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /Users/ad/Projects/nullplayer && swift test --filter WindowManagerDragModeTests 2>&1 | tail -20
```
Expected: compile error — `determineDragMode` does not exist yet.

- [ ] **Step 3: Add the static function to WindowManager**

In `WindowManager.swift`, inside the `// MARK: - Window Snapping & Docking` section (around line 2312), add before `windowWillStartDragging`:

```swift
/// Pure timing function: determines drag mode from hold duration.
/// - Parameters:
///   - holdStart: The CACurrentMediaTime() value captured at mouseDown, or nil if unavailable.
///   - currentTime: The current CACurrentMediaTime() value.
///   - threshold: The hold duration threshold in seconds.
/// - Returns: `.separate` if elapsed time is below threshold; `.group` otherwise.
static func determineDragMode(
    holdStart: CFTimeInterval?,
    currentTime: CFTimeInterval,
    threshold: TimeInterval
) -> DragMode {
    guard let start = holdStart else { return .group }
    return (currentTime - start) < threshold ? .separate : .group
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd /Users/ad/Projects/nullplayer && swift test --filter WindowManagerDragModeTests 2>&1 | tail -20
```
Expected: all 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/NullPlayer/App/WindowManager.swift Tests/NullPlayerTests/WindowManagerDragModeTests.swift
git commit -m "feat: add determineDragMode() static function with unit tests"
```

---

### Task 3: Update windowWillStartDragging, windowWillMove, windowDidFinishDragging

**Files:**
- Modify: `Sources/NullPlayer/App/WindowManager.swift`

- [ ] **Step 1: Add postConnectedWindowHighlight helper**

In `WindowManager.swift`, add this private helper near `postLayoutChangeNotification` (around line 2769):

```swift
/// Post a connectedWindowHighlightDidChange notification.
/// - Parameter windows: The windows to highlight. Pass an empty set to clear all highlights.
private func postConnectedWindowHighlight(_ windows: Set<NSWindow>) {
    NotificationCenter.default.post(
        name: .connectedWindowHighlightDidChange,
        object: nil,
        userInfo: ["highlightedWindows": windows]
    )
}
```

- [ ] **Step 2: Update windowWillStartDragging**

Replace the entire body of `windowWillStartDragging(_:fromTitleBar:)` (lines 2319–2342) with:

```swift
func windowWillStartDragging(_ window: NSWindow, fromTitleBar: Bool = false) {
    draggingWindow = window
    dragStartOrigin = window.frame.origin
    isTitleBarDrag = fromTitleBar
    holdStartTime = CACurrentMediaTime()
    dragMode = .pending

    // Find all windows that are docked to this window
    dockedWindowsToMove = findDockedWindows(to: window)

    // Store relative offsets from dragging window's origin (prevents drift during fast movement)
    dockedWindowOffsets.removeAll()
    dockedWindowOriginalOrigins.removeAll()
    let dragOrigin = window.frame.origin
    for dockedWindow in dockedWindowsToMove {
        let offset = NSPoint(
            x: dockedWindow.frame.origin.x - dragOrigin.x,
            y: dockedWindow.frame.origin.y - dragOrigin.y
        )
        dockedWindowOffsets[ObjectIdentifier(dockedWindow)] = offset
        dockedWindowOriginalOrigins[ObjectIdentifier(dockedWindow)] = dockedWindow.frame.origin
    }

    // Highlight connected peers so user can see which windows would move together
    if !dockedWindowsToMove.isEmpty {
        postConnectedWindowHighlight(Set(dockedWindowsToMove))
        highlightWasPosted = true
    }
}
```

- [ ] **Step 3: Patch the mid-flight fallback in windowWillMove**

In `windowWillMove`, around line 2385, there is a fallback that calls `windowWillStartDragging` when a different window triggers `windowWillMove` mid-flight:

```swift
// EXISTING — find this:
if draggingWindow !== window {
    windowWillStartDragging(window)
}
```

This would reset `holdStartTime` to "now", making `elapsed ≈ 0` and incorrectly triggering `.separate` mode. Fix by immediately setting `dragMode = .group` after this fallback call:

```swift
// REPLACE WITH:
if draggingWindow !== window {
    windowWillStartDragging(window)
    dragMode = .group  // mid-flight detection: hold measurement unavailable, default to group
}
```

- [ ] **Step 4: Replace the undock block in windowWillMove**

In `windowWillMove`, find and replace the undock block (lines 2389–2408):

```swift
// OLD — remove this entire block:
let isMainWindow = window === mainWindowController?.window
if !isMainWindow && isTitleBarDrag && !dockedWindowsToMove.isEmpty {
    let dragDistance = hypot(newOrigin.x - dragStartOrigin.x, newOrigin.y - dragStartOrigin.y)
    if dragDistance > undockThreshold {
        isMovingDockedWindows = true
        for dockedWindow in dockedWindowsToMove {
            if let origin = dockedWindowOriginalOrigins[ObjectIdentifier(dockedWindow)] {
                dockedWindow.setFrameOrigin(origin)
            }
        }
        isMovingDockedWindows = false
        dockedWindowsToMove.removeAll()
        dockedWindowOffsets.removeAll()
        dockedWindowOriginalOrigins.removeAll()
    }
}
```

Replace with:

```swift
// NEW — determine mode on first drag movement
if dragMode == .pending {
    let mode = WindowManager.determineDragMode(
        holdStart: holdStartTime,
        currentTime: CACurrentMediaTime(),
        threshold: holdThreshold
    )
    dragMode = mode
    if mode == .separate {
        // Restore peers to their pre-drag positions before breaking the dock
        isMovingDockedWindows = true
        for dockedWindow in dockedWindowsToMove {
            if let origin = dockedWindowOriginalOrigins[ObjectIdentifier(dockedWindow)] {
                dockedWindow.setFrameOrigin(origin)
            }
        }
        isMovingDockedWindows = false
        dockedWindowsToMove.removeAll()
        dockedWindowOffsets.removeAll()
        dockedWindowOriginalOrigins.removeAll()
        if highlightWasPosted {
            postConnectedWindowHighlight([])
            highlightWasPosted = false
        }
    }
}
```

- [ ] **Step 4: Update windowDidFinishDragging**

Replace the body of `windowDidFinishDragging(_:)` (lines 2347–2353) with:

```swift
func windowDidFinishDragging(_ window: NSWindow) {
    draggingWindow = nil
    dockedWindowsToMove.removeAll()
    dockedWindowOffsets.removeAll()
    dockedWindowOriginalOrigins.removeAll()
    holdStartTime = nil
    dragMode = .pending
    if highlightWasPosted {
        postConnectedWindowHighlight([])
        highlightWasPosted = false
    }
    _ = tightenClassicCenterStackIfNeeded()
    postLayoutChangeNotification()
    updateDockedChildWindows()
}
```

- [ ] **Step 5: Build to confirm no errors**

```bash
cd /Users/ad/Projects/nullplayer && swift build 2>&1 | head -40
```
Expected: clean build (no undockThreshold references remain).

- [ ] **Step 6: Run all tests**

```bash
cd /Users/ad/Projects/nullplayer && swift test 2>&1 | tail -20
```
Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/NullPlayer/App/WindowManager.swift
git commit -m "feat: replace distance-based undock with hold-duration drag mode"
```

---

### Task 4: Add NSWindow.willCloseNotification observer for mid-drag cleanup

**Files:**
- Modify: `Sources/NullPlayer/App/WindowManager.swift`

- [ ] **Step 1: Register observer in init()**

In `private init()` (line 360), add after `loadDefaultSkin()`:

```swift
// Clean up drag state if a window closes mid-drag
NotificationCenter.default.addObserver(
    self,
    selector: #selector(handleWindowWillClose(_:)),
    name: NSWindow.willCloseNotification,
    object: nil
)
```

- [ ] **Step 2: Add the handler**

Add this method to `WindowManager` in the `// MARK: - Window Snapping & Docking` section:

```swift
@objc private func handleWindowWillClose(_ notification: Notification) {
    guard let closingWindow = notification.object as? NSWindow,
          closingWindow === draggingWindow else { return }
    windowDidFinishDragging(closingWindow)
}
```

- [ ] **Step 3: Build and run tests**

```bash
cd /Users/ad/Projects/nullplayer && swift build 2>&1 | head -20 && swift test 2>&1 | tail -10
```
Expected: clean build, all tests pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/NullPlayer/App/WindowManager.swift
git commit -m "feat: clean up hold state when dragged window closes mid-drag"
```

---

## Chunk 2: View Highlight Rendering

All views follow the same pattern:
1. Add `private var isHighlighted = false`
2. Add `addObserver` for `.connectedWindowHighlightDidChange` in the existing setup method
3. Add `@objc private func connectedWindowHighlightDidChange(_ notification: Notification)` handler
4. Add the overlay at the end of `draw(_:)`, before the closing brace

The handler is identical for every view:

```swift
@objc private func connectedWindowHighlightDidChange(_ notification: Notification) {
    let highlighted = notification.userInfo?["highlightedWindows"] as? Set<NSWindow> ?? []
    let newValue = highlighted.contains { $0 === window }
    if isHighlighted != newValue {
        isHighlighted = newValue
        needsDisplay = true
    }
}
```

The overlay is identical for every view — add at the very end of `draw(_:)` before the closing `}`:

```swift
if isHighlighted {
    NSColor.white.withAlphaComponent(0.15).setFill()
    bounds.fill()
}
```

### Task 5: Add highlight rendering to classic views

**Files:**
- Modify: `Sources/NullPlayer/Windows/MainWindow/MainWindowView.swift`
- Modify: `Sources/NullPlayer/Windows/Playlist/PlaylistView.swift`
- Modify: `Sources/NullPlayer/Windows/Equalizer/EQView.swift`
- Modify: `Sources/NullPlayer/Windows/Waveform/WaveformView.swift`
- Modify: `Sources/NullPlayer/Windows/Spectrum/SpectrumView.swift`

#### MainWindowView

- [ ] **Step 1: Add isHighlighted property and observer**

In `MainWindowView.swift`, add the property near the other `private var` flags (around line 1312 near `isDraggingWindow`):

```swift
private var isHighlighted = false
```

In `setupView()` (around line 241, after the last `addObserver` call before the closing `}`), add:

```swift
// Observe connected-window highlight changes during drag
NotificationCenter.default.addObserver(self, selector: #selector(connectedWindowHighlightDidChange(_:)),
                                       name: .connectedWindowHighlightDidChange, object: nil)
```

- [ ] **Step 2: Add handler**

Add the handler method anywhere among the other `@objc` notification handlers in the file:

```swift
@objc private func connectedWindowHighlightDidChange(_ notification: Notification) {
    let highlighted = notification.userInfo?["highlightedWindows"] as? Set<NSWindow> ?? []
    let newValue = highlighted.contains { $0 === window }
    if isHighlighted != newValue {
        isHighlighted = newValue
        needsDisplay = true
    }
}
```

- [ ] **Step 3: Add overlay to draw()**

At the very end of `override func draw(_ dirtyRect: NSRect)`, before the closing `}`, add:

```swift
if isHighlighted {
    NSColor.white.withAlphaComponent(0.15).setFill()
    bounds.fill()
}
```

#### PlaylistView

- [ ] **Step 4: Apply same pattern to PlaylistView**

- Add `private var isHighlighted = false` near other state flags
- In `setupView()` (around line 120, after the last existing `addObserver` call), add:
  ```swift
  NotificationCenter.default.addObserver(self, selector: #selector(connectedWindowHighlightDidChange(_:)),
                                         name: .connectedWindowHighlightDidChange, object: nil)
  ```
- Add the handler (identical to above)
- Add overlay at end of `draw(_:)` (after `context.restoreGState()` at line 388, before closing `}`)

#### EQView

- [ ] **Step 5: Apply same pattern to EQView**

- Add `private var isHighlighted = false` near state flags
- In `setupView()` (around line 104, after existing observer registration), add:
  ```swift
  NotificationCenter.default.addObserver(self, selector: #selector(connectedWindowHighlightDidChange(_:)),
                                         name: .connectedWindowHighlightDidChange, object: nil)
  ```
- Add the handler
- Add overlay at end of `draw(_:)`

#### WaveformView

- [ ] **Step 6: Apply same pattern to WaveformView**

- Add `private var isHighlighted = false` near the other `private var` flags (around line 5)
- In `override init(frame frameRect: NSRect)` (line 45), after `setAccessibilityLabel(...)`, add:
  ```swift
  NotificationCenter.default.addObserver(self, selector: #selector(connectedWindowHighlightDidChange(_:)),
                                         name: .connectedWindowHighlightDidChange, object: nil)
  ```
  Add the same to `required init?(coder:)` (line 54) after its `setAccessibilityLabel`.
- In `deinit` (line 63), add `NotificationCenter.default.removeObserver(self)` (WaveformView has no removeObserver currently)
- Add the handler
- Add overlay at end of `draw(_:)` (after `drawWaveform(in: context)` at line 104, before closing `}`)

#### SpectrumView

- [ ] **Step 7: Apply same pattern to SpectrumView**

- Add `private var isHighlighted = false`
- In `setupView()` (around line 72, after existing `addObserver` calls), add:
  ```swift
  NotificationCenter.default.addObserver(self, selector: #selector(connectedWindowHighlightDidChange(_:)),
                                         name: .connectedWindowHighlightDidChange, object: nil)
  ```
- Add the handler
- Add overlay at end of `draw(_:)`

- [ ] **Step 8: Build**

```bash
cd /Users/ad/Projects/nullplayer && swift build 2>&1 | head -40
```
Expected: clean build.

- [ ] **Step 9: Manual test — classic skin**

Launch the app in classic skin mode. Dock 2–3 windows together (drag until they snap). Then:
- Tap and immediately drag one window → it detaches, no highlight visible (too brief)
- Hold ~0.5s then drag → peers highlight white, group moves together

- [ ] **Step 10: Commit**

```bash
git add Sources/NullPlayer/Windows/MainWindow/MainWindowView.swift \
        Sources/NullPlayer/Windows/Playlist/PlaylistView.swift \
        Sources/NullPlayer/Windows/Equalizer/EQView.swift \
        Sources/NullPlayer/Windows/Waveform/WaveformView.swift \
        Sources/NullPlayer/Windows/Spectrum/SpectrumView.swift
git commit -m "feat: add drag highlight overlay to classic window views"
```

---

### Task 6: Add highlight rendering to modern views

**Files:**
- Modify: `Sources/NullPlayer/Windows/ModernMainWindow/ModernMainWindowView.swift`
- Modify: `Sources/NullPlayer/Windows/ModernPlaylist/ModernPlaylistView.swift`
- Modify: `Sources/NullPlayer/Windows/ModernWaveform/ModernWaveformView.swift`
- Modify: `Sources/NullPlayer/Windows/ModernEQ/ModernEQView.swift`
- Modify: `Sources/NullPlayer/Windows/ModernSpectrum/ModernSpectrumView.swift`

All five follow the same pattern as Task 5. The setup method names differ:

| View | Setup method | addObserver location |
|---|---|---|
| `ModernMainWindowView` | `setupView()` | After last `addObserver` (~line 145) |
| `ModernPlaylistView` | `commonInit()` or `setupView()` | After last `addObserver` (~line 142) |
| `ModernWaveformView` | `commonInit()` | After last `addObserver` (~line 103) |
| `ModernEQView` | `setupView()` or `commonInit()` | After last `addObserver` (~line 174) |
| `ModernSpectrumView` | `setupView()` | After last `addObserver` (~line 106) |

All have `deinit` with `NotificationCenter.default.removeObserver(self)` — no changes needed there.

- [ ] **Step 1: Apply pattern to ModernMainWindowView**

- Add `private var isHighlighted = false` near other state properties
- In `setupView()`, after the last `addObserver` call (around line 145), add:
  ```swift
  NotificationCenter.default.addObserver(self, selector: #selector(connectedWindowHighlightDidChange(_:)),
                                         name: .connectedWindowHighlightDidChange, object: nil)
  ```
- Add the handler
- Add overlay at end of `draw(_:)`, before closing `}`

- [ ] **Step 2: Apply pattern to ModernPlaylistView**

Same as above, using `commonInit()` or `setupView()`.

- [ ] **Step 3: Apply pattern to ModernWaveformView**

Same, using `commonInit()`.

- [ ] **Step 4: Apply pattern to ModernEQView**

Same, using appropriate setup method.

- [ ] **Step 5: Apply pattern to ModernSpectrumView**

Same, using `setupView()`.

- [ ] **Step 6: Build**

```bash
cd /Users/ad/Projects/nullplayer && swift build 2>&1 | head -40
```
Expected: clean build.

- [ ] **Step 7: Manual test — modern skin**

Launch in modern skin mode. Dock 2–3 windows. Then:
- Tap and immediately drag → detaches, no highlight
- Hold ~0.5s then drag → peers highlight white, group moves together
- Verify widgets (sliders, buttons) are unaffected — clicking them does not trigger highlight

- [ ] **Step 8: Run all tests**

```bash
cd /Users/ad/Projects/nullplayer && swift test 2>&1 | tail -20
```
Expected: all tests pass.

- [ ] **Step 9: Commit**

```bash
git add Sources/NullPlayer/Windows/ModernMainWindow/ModernMainWindowView.swift \
        Sources/NullPlayer/Windows/ModernPlaylist/ModernPlaylistView.swift \
        Sources/NullPlayer/Windows/ModernWaveform/ModernWaveformView.swift \
        Sources/NullPlayer/Windows/ModernEQ/ModernEQView.swift \
        Sources/NullPlayer/Windows/ModernSpectrum/ModernSpectrumView.swift
git commit -m "feat: add drag highlight overlay to modern window views"
```
