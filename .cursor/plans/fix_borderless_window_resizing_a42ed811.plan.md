---
name: Fix Borderless Window Resizing
overview: Keep the custom skinned appearance while enabling native macOS resize behavior by using a titled window with transparent/hidden title bar and fullSizeContentView. Also fix app not coming to foreground on launch.
todos:
  - id: fix-foreground
    content: Fix app not coming to foreground on launch in AppDelegate
    status: completed
  - id: update-main-window
    content: Update MainWindowController with titled+transparent titlebar pattern
    status: completed
  - id: update-playlist-window
    content: Update PlaylistWindowController with same pattern
    status: completed
    dependencies:
      - update-main-window
  - id: update-eq-window
    content: Update EQWindowController with same pattern
    status: completed
    dependencies:
      - update-main-window
  - id: update-medialibrary-window
    content: Update MediaLibraryWindowController with same pattern
    status: completed
    dependencies:
      - update-main-window
  - id: test-resizing
    content: Test all windows resize properly while maintaining skinned look
    status: pending
  - id: verify-size-constraints
    content: Verify/set per-window min/max sizes to protect skin layout
    status: completed
  - id: verify-activation-reopen
    content: Verify Dock reopen brings main window forward as expected
    status: pending
  - id: verify-titlebar-controls
    content: Confirm custom window controls cover close/minimize/zoom
    status: pending
---

# Fix Window Resizing and Foreground Activation

## Problems

1. **Resizing**: Windows use `.borderless` style mask which removes native resize handles
2. **Foreground**: App doesn't come to foreground on launch because `activate()` is called before windows exist

## Solution

Use the standard macOS pattern for custom-chrome windows:

1. **Include `.titled` and `.resizable` in the style mask** - This gives you native resize behavior at edges/corners
2. **Use `.fullSizeContentView`** - Content extends behind the title bar area
3. **Make title bar invisible** - `titlebarAppearsTransparent = true` and `titleVisibility = .hidden`
4. **Hide traffic light buttons** - Manually hide close/minimize/zoom buttons
5. **Keep `isMovableByWindowBackground = true`** - Allows dragging from anywhere
6. **Preserve skin constraints** - Ensure min/max sizes keep the layout valid
7. **Confirm activation paths** - Foreground on launch and Dock reopen should behave

This is how apps like iTerm, Pixelmator, and other custom-chrome Mac apps work.

## Files to Modify

### 0. [AppDelegate.swift](Sources/AdAmp/App/AppDelegate.swift) - Fix Foreground Activation

The issue: `main.swift` calls `app.activate(ignoringOtherApps: true)` **before** `applicationDidFinishLaunching` runs, so no windows exist yet.

Add at the end of `applicationDidFinishLaunching`, after `showMainWindow()`:

```swift
// Bring app to foreground after windows are created
NSApp.activate(ignoringOtherApps: true)
windowManager.mainWindowController?.window?.makeKeyAndOrderFront(nil)
```

Also verify (or add if missing) that Dock reopen focuses the main window:

```swift
func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    windowManager.mainWindowController?.window?.makeKeyAndOrderFront(nil)
    return true
}
```

### 1. [MainWindowController.swift](Sources/AdAmp/Windows/MainWindow/MainWindowController.swift)

Change window creation (line 20-25):

```swift
let window = ResizableWindow(
    contentRect: NSRect(origin: .zero, size: Skin.mainWindowSize),
    styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
    backing: .buffered,
    defer: false
)
```

Add to `setupWindow()`:

```swift
window.titlebarAppearsTransparent = true
window.titleVisibility = .hidden
window.standardWindowButton(.closeButton)?.isHidden = true
window.standardWindowButton(.miniaturizeButton)?.isHidden = true
window.standardWindowButton(.zoomButton)?.isHidden = true
```

If the app supports fullscreen or style changes, re-hide the buttons in any window state change callbacks (AppKit can re-show them). Add to the NSWindowDelegate extension:

```swift
whefunc windowDidExitFullScreen(_ notification: Notification) {
    guard let window = window else { return }
    window.standardWindowButton(.closeButton)?.isHidden = true
    window.standardWindowButton(.miniaturizeButton)?.isHidden = true
    window.standardWindowButton(.zoomButton)?.isHidden = true
}
```

**Size constraints**: The main window and EQ window have fixed skin sizes. Two options:

- **Option A**: Set `maxSize = minSize` to prevent resizing (keeps pixel-perfect skin)
- **Option B**: If the skin renderer supports scaling, allow resize but maintain aspect ratio

For now, recommend **Option A** for main/EQ windows since Winamp skins are typically pixel-art and don't scale well. Playlist and media library are resizable by design.

### 2. [PlaylistWindowController.swift](Sources/AdAmp/Windows/Playlist/PlaylistWindowController.swift)

Same pattern - change style mask and add title bar hiding in `setupWindow()`.

### 3. [EQWindowController.swift](Sources/AdAmp/Windows/Equalizer/EQWindowController.swift)

Same pattern.

### 4. [MediaLibraryWindowController.swift](Sources/AdAmp/Windows/MediaLibrary/MediaLibraryWindowController.swift)

Already has `.resizable`, just needs `.titled`, `.fullSizeContentView`, and title bar hiding.

### 5. [ResizableWindow.swift](Sources/AdAmp/Windows/ResizableWindow.swift)

Keep as-is - the `canBecomeKey` and `canBecomeMain` overrides are still useful.

### 6. Verify Custom Window Controls in Views

The Winamp skin likely has its own close/minimize buttons drawn in `MainWindowView`, `PlaylistView`, and `EQView`. After hiding the system traffic lights:

- Verify the skin's custom close button calls `window?.close()` or `NSApp.terminate(nil)`
- Verify the skin's custom minimize button calls `window?.miniaturize(nil)`
- Verify the skin's custom shade/windowshade toggle still works
- The hidden system buttons should not interfere since they're just hidden, not removed

## Result

- Visual appearance stays identical (custom skin)
- Native macOS resize handles at all edges and corners
- Standard window behavior (minimize, zoom, full screen support)
- App comes to foreground on launch
- Dock reopen focuses the main window reliably
- Works like any other Mac app