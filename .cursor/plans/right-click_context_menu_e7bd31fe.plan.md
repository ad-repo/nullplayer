---
name: Right-Click Context Menu
overview: Implement a Winamp-style right-click context menu on all windows with Play, Window toggles, Skins, Options, Playback controls, and Exit functionality.
todos:
  - id: preferences
    content: Add timeDisplayMode and isDoubleSize preferences to WindowManager
    status: pending
  - id: audio-methods
    content: Add seekBy(seconds:) and skipTracks(count:) to AudioEngine
    status: pending
  - id: skin-discovery
    content: Add skin directory scanning and discovery to WindowManager
    status: pending
  - id: context-menu-builder
    content: Create shared ContextMenuBuilder with menu validation/state
    status: pending
    dependencies:
      - preferences
      - audio-methods
      - skin-discovery
  - id: context-menu-views
    content: Add context menu via menu(for:) or menu assignment for all views
    status: pending
    dependencies:
      - context-menu-builder
  - id: time-display
    content: Update time display rendering to support elapsed/remaining modes
    status: pending
    dependencies:
      - preferences
  - id: double-size
    content: Implement double size scaling toggle
    status: pending
    dependencies:
      - preferences
  - id: docs
    content: Update docs for new context menu, time mode, double size
    status: pending
---

# Right-Click Context Menu Implementation

## Overview

Add a comprehensive right-click context menu to **all windows** (Main, Equalizer, Playlist) that matches the classic Winamp interface shown in the user's screenshots.

## Menu Structure (From Screenshots)

```
Play → File...
─────────────────────────
✓ Main Window
✓ Equalizer  
✓ Playlist Editor
  Milkdrop (disabled - not implemented)
─────────────────────────
Skins → Load Skin...
        <Base Skin>
        ─────────────
        [Internet Archive]
        [The Hustler]
        [Classic Mario]
        ... (dynamically loaded from ~/Library/Application Support/AdAmp/Skins/)
─────────────────────────
Options → Skins → (same submenu as above)
          ─────────────
          ✓ Time elapsed
            Time remaining
          ─────────────
            Double Size
          ─────────────
            Repeat
            Shuffle
─────────────────────────
Playback → Previous
           Play
           Pause
           Stop
           Next
           ─────────────
           Back 5 seconds
           Fwd 5 seconds
           ─────────────
           10 tracks back
           10 tracks fwd
─────────────────────────
Exit
```

---

## Implementation Details

### 1. Files to Modify

| File | Changes |

|------|---------|

| [`WindowManager.swift`](Sources/AdAmp/App/WindowManager.swift) | Add preferences, skin discovery, double-size logic |

| [`AudioEngine.swift`](Sources/AdAmp/Audio/AudioEngine.swift) | Add `seekBy(seconds:)` and `skipTracks(count:)` |

| **NEW** [`ContextMenuBuilder.swift`](Sources/AdAmp/App/ContextMenuBuilder.swift) | Shared context menu builder |

| [`MainWindowView.swift`](Sources/AdAmp/Windows/MainWindow/MainWindowView.swift) | Add `rightMouseDown`, time display mode |

| [`EQView.swift`](Sources/AdAmp/Windows/Equalizer/EQView.swift) | Add `rightMouseDown` |

| [`PlaylistView.swift`](Sources/AdAmp/Windows/Playlist/PlaylistView.swift) | Add `rightMouseDown` |

| [`SkinRenderer.swift`](Sources/AdAmp/Skin/SkinRenderer.swift) | Update `drawTimeDisplay` for negative time |

---

### 2. User Preferences (WindowManager)

Add to `WindowManager`:

```swift
// MARK: - User Preferences

enum TimeDisplayMode: String {
    case elapsed
    case remaining
}

/// Time display mode (elapsed vs remaining)
var timeDisplayMode: TimeDisplayMode = .elapsed {
    didSet {
        UserDefaults.standard.set(timeDisplayMode.rawValue, forKey: "timeDisplayMode")
        NotificationCenter.default.post(name: .timeDisplayModeDidChange, object: nil)
    }
}

/// Double size mode (2x scaling)
var isDoubleSize: Bool = false {
    didSet {
        UserDefaults.standard.set(isDoubleSize, forKey: "isDoubleSize")
        applyDoubleSize()
    }
}

/// Register defaults + load preferences on init
private func registerPreferenceDefaults() {
    UserDefaults.standard.register(defaults: [
        "timeDisplayMode": TimeDisplayMode.elapsed.rawValue,
        "isDoubleSize": false
    ])
}

/// Load preferences on init
private func loadPreferences() {
    if let mode = UserDefaults.standard.string(forKey: "timeDisplayMode"),
       let displayMode = TimeDisplayMode(rawValue: mode) {
        timeDisplayMode = displayMode
    }
    isDoubleSize = UserDefaults.standard.bool(forKey: "isDoubleSize")
}
```

**Note**: `WindowManager` already uses `UserDefaults` for window positions (lines 328-366). Keep keys as constants to avoid drift.

---

### 3. Audio Engine Methods

Add to `AudioEngine`:

```swift
/// Seek relative to current position
func seekBy(seconds: TimeInterval) {
    let newTime = max(0, min(duration, currentTime + seconds))
    seek(to: newTime)
}

/// Skip multiple tracks forward or backward
func skipTracks(count: Int) {
    guard !playlist.isEmpty else { return }
    
    if shuffleEnabled {
        // In shuffle mode, skip one at a time
        for _ in 0..<abs(count) {
            if count > 0 { next() } else { previous() }
        }
        return
    }
    
    // Calculate new index with wraparound
    var newIndex = currentIndex + count
    while newIndex < 0 { newIndex += playlist.count }
    newIndex = newIndex % playlist.count
    
    currentIndex = newIndex
    loadTrack(at: currentIndex)
    if state == .playing { play() }
}
```

---

### 4. Skin Discovery (WindowManager)

```swift
// MARK: - Skin Discovery

/// Application Support directory for AdAmp
var applicationSupportURL: URL {
    let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
    return paths[0].appendingPathComponent("AdAmp")
}

/// Skins directory
var skinsDirectoryURL: URL {
    applicationSupportURL.appendingPathComponent("Skins")
}

/// Get list of available skins (name, URL)
func availableSkins() -> [(name: String, url: URL)] {
    // Ensure directory exists
    try? FileManager.default.createDirectory(at: skinsDirectoryURL, withIntermediateDirectories: true)
    
    guard let contents = try? FileManager.default.contentsOfDirectory(at: skinsDirectoryURL, includingPropertiesForKeys: nil) else {
        return []
    }
    
    return contents
        .filter { $0.pathExtension.lowercased() == "wsz" }
        .map { (name: $0.deletingPathExtension().lastPathComponent, url: $0) }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
}

/// Load the base/default skin
func loadBaseSkin() {
    currentSkin = SkinLoader.shared.loadDefault()
    notifySkinChanged()
}
```

---

### 5. Double Size Implementation

Leverage existing `scaleFactor` infrastructure in views. When toggled:

- Resize main window to 550x232 (2x of 275x116)
- Resize EQ window to 550x232
- Playlist maintains aspect but scales
```swift
private func applyDoubleSize() {
    let scale: CGFloat = isDoubleSize ? 2.0 : 1.0
    
    // Main window
    if let window = mainWindowController?.window {
        let targetSize = NSSize(width: Skin.mainWindowSize.width * scale,
                                 height: Skin.mainWindowSize.height * scale)
        var frame = window.frame
        let heightDiff = targetSize.height - frame.height
        frame.origin.y -= heightDiff  // Anchor top-left
        frame.size = targetSize
        window.setFrame(frame, display: true, animate: true)
    }
    
    // EQ window
    if let window = equalizerWindowController?.window {
        let targetSize = NSSize(width: Skin.eqWindowSize.width * scale,
                                 height: Skin.eqWindowSize.height * scale)
        var frame = window.frame
        let heightDiff = targetSize.height - frame.height
        frame.origin.y -= heightDiff
        frame.size = targetSize
        window.setFrame(frame, display: true, animate: true)
    }
    
    // Playlist - scale minimum size and max constraints to avoid jitter
    // Update minSize/maxSize on playlist window and any autosave frame logic
}
```


---

### 6. Context Menu Builder (New File)

Create `Sources/AdAmp/App/ContextMenuBuilder.swift`:

```swift
import AppKit

/// Builds the shared right-click context menu for all Winamp windows
class ContextMenuBuilder {
    
    static func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let wm = WindowManager.shared
        
        // Play submenu
        menu.addItem(buildPlayMenuItem())
        menu.addItem(NSMenuItem.separator())
        
        // Window toggles
        menu.addItem(buildWindowItem("Main Window", visible: wm.mainWindowController?.window?.isVisible ?? false, action: #selector(Actions.toggleMainWindow)))
        menu.addItem(buildWindowItem("Equalizer", visible: wm.isEqualizerVisible, action: #selector(Actions.toggleEQ)))
        menu.addItem(buildWindowItem("Playlist Editor", visible: wm.isPlaylistVisible, action: #selector(Actions.togglePlaylist)))
        
        let milkdrop = NSMenuItem(title: "Milkdrop", action: nil, keyEquivalent: "")
        milkdrop.isEnabled = false
        menu.addItem(milkdrop)
        
        menu.addItem(NSMenuItem.separator())
        
        // Skins submenu
        menu.addItem(buildSkinsMenuItem())
        
        // Options submenu  
        menu.addItem(buildOptionsMenuItem())
        
        // Playback submenu
        menu.addItem(buildPlaybackMenuItem())
        
        menu.addItem(NSMenuItem.separator())
        
        // Exit
        let exit = NSMenuItem(title: "Exit", action: #selector(Actions.exit), keyEquivalent: "")
        exit.target = Actions.shared
        menu.addItem(exit)
        
        menu.autoenablesItems = false
        return menu
    }
    
    // ... helper methods for each submenu
}

// Singleton to handle menu actions + validation
class Actions: NSObject, NSMenuItemValidation {
    static let shared = Actions()

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        // Use menuItem.action to set state and enabled/disabled per current app state
        // Example: menuItem.state = WindowManager.shared.isPlaylistVisible ? .on : .off
        return true
    }

    @objc func toggleMainWindow() { WindowManager.shared.toggleMainWindow() }
    @objc func toggleEQ() { WindowManager.shared.toggleEqualizer() }
    @objc func togglePlaylist() { WindowManager.shared.togglePlaylist() }
    @objc func exit() { NSApp.terminate(nil) }
    // ... etc
}
```

---

### 7. Add rightMouseDown to All Views

Prefer menu delegation so subviews still show the menu (playlist rows, buttons, etc.).

```swift
override func menu(for event: NSEvent) -> NSMenu? {
    ContextMenuBuilder.buildMenu()
}
```

---

### 8. Time Display Mode

Modify `MainWindowView.drawNormalModeScaled()`:

```swift
// Calculate display time
let displayTime: TimeInterval
if WindowManager.shared.timeDisplayMode == .remaining && duration > 0 {
    displayTime = currentTime - duration  // Negative value
} else {
    displayTime = currentTime
}

let isNegative = displayTime < 0
let absTime = abs(displayTime)
let minutes = Int(absTime) / 60
let seconds = Int(absTime) % 60

renderer.drawTimeDisplay(minutes: minutes, seconds: seconds, isNegative: isNegative, in: context)
```

Update `SkinRenderer.drawTimeDisplay()` to accept `isNegative` parameter and draw minus sign from `SkinElements.Numbers.minus`.

Also subscribe to `timeDisplayModeDidChange` and trigger a redraw of the main view (not a window visibility change).

---

## Testing Checklist

- [ ] Right-click opens menu on Main window
- [ ] Right-click opens menu on EQ window
- [ ] Right-click opens menu on Playlist window
- [ ] Play > File... opens file picker
- [ ] Window toggles show correct checkmarks
- [ ] Skins > Load Skin... opens file picker for .wsz
- [ ] Skins > Base Skin resets to default
- [ ] Skins submenu shows files from ~/Library/Application Support/AdAmp/Skins/
- [ ] Options > Time elapsed/remaining toggles and persists
- [ ] Options > Double Size scales all windows
- [ ] Options > Repeat/Shuffle match button states
- [ ] Playback controls work correctly
- [ ] Back/Fwd 5 seconds seeks correctly
- [ ] 10 tracks back/fwd skips correctly
- [ ] Exit quits application
 - [ ] Menu state updates reflect current repeat/shuffle/window visibility
 - [ ] Right-click works over controls and playlist rows
 - [ ] Double size preserves min/max window constraints
 - [ ] Docs updated for context menu and preferences