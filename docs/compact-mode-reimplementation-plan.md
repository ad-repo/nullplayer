# Compact Mode Reimplementation Plan

## Summary

Compact Mode should be reimplemented as a dedicated menu-bar mini-player surface.

The current implementation is structurally fragile because it repurposes the Library Browser window as the compact window. That couples Compact Mode to normal browser behavior: side docking, browser layout, shade mode, state restoration, resizing, modern/classic browser variants, and AppKit child-window relationships.

The replacement design should introduce a dedicated Compact Mode controller and dedicated compact window. Compact Mode should no longer use `plexBrowserWindowController` or `ModernLibraryBrowserWindowController` as its surface.

## Current problems

Compact Mode currently mutates too many unrelated systems at once:

- application activation policy (`.regular` ↔ `.accessory`)
- status-bar item lifecycle
- main menu lifecycle
- normal window visibility snapshots
- docked child-window relationships
- Library Browser normal/compact rendering
- persistent `compactModeEnabled` restore behavior
- live modern/classic UI switching behavior

This creates ambiguous states:

- Library Browser visible as a normal window vs visible as compact window
- Library Browser hidden because the user closed it vs hidden because Compact Mode owns it
- Library Browser frame as normal restored frame vs compact dropdown frame
- `window.isVisible` says “visible” while the user cannot see the window because activation policy/window ordering changed
- exiting compact restores browser/main/menu state in the wrong order

The missing menu-bar items after exiting Compact Mode are a symptom of the same issue. `.accessory → .regular` is asynchronous, but the current implementation rebuilds menus and restores windows as if the app is immediately regular again.

## High-level direction

1. Revert the incremental Compact Mode patches from the current debugging session.
2. Stop using Library Browser as the Compact Mode surface.
3. Add a dedicated `CompactModeWindowController` and `CompactModeView`.
4. Add a small Compact Mode coordinator/state machine.
5. Make enter/exit transitions explicit and ordered.
6. Keep normal app-window restoration separate from compact-window ownership.

## Files to add

Suggested new files:

- `Sources/NullPlayer/Windows/CompactMode/CompactModeWindowController.swift`
- `Sources/NullPlayer/Windows/CompactMode/CompactModeView.swift`
- optional: `Sources/NullPlayer/App/CompactModeCoordinator.swift`

Alternatively, the coordinator can live in `WindowManager+CompactMode.swift` if the project prefers extensions over another object.

## Files to simplify/remove compact responsibilities from

Remove app-level Compact Mode responsibilities from the Library Browser implementations:

- `Sources/NullPlayer/Windows/PlexBrowser/PlexBrowserWindowController.swift`
- `Sources/NullPlayer/Windows/ModernLibraryBrowser/ModernLibraryBrowserWindowController.swift`
- `Sources/NullPlayer/Windows/ModernLibraryBrowser/ModernLibraryBrowserView.swift`
- `Sources/NullPlayer/App/LibraryBrowserWindowProviding.swift`

Specifically, Compact Mode should no longer call:

- `showPlexBrowser()`
- `plexBrowserWindowController?.setCompactMode(true)`
- `plexBrowserWindowController?.window` as the compact surface

If the embedded Library Browser mini-player is wanted later, treat it as a separate browser feature, not app-level Compact Mode.

## State machine

Compact Mode should not infer state from `window.isVisible`.

Use explicit state:

```swift
enum CompactModeState {
    case regular
    case entering
    case compactHidden
    case compactVisible
    case exiting
}
```

Tracked coordinator state:

```swift
private var compactModeState: CompactModeState = .regular
private var regularWindowSnapshot: CompactWindowSnapshot?
private var compactStatusItem: NSStatusItem?
private var compactWindowController: CompactModeWindowController?
```

## Regular-window snapshot

Use a typed snapshot, not a string dictionary.

Example:

```swift
struct CompactWindowSnapshot {
    var main: WindowSnapshot?
    var equalizer: WindowSnapshot?
    var playlist: WindowSnapshot?
    var spectrum: WindowSnapshot?
    var audioAnalysis: WindowSnapshot?
    var waveform: WindowSnapshot?
    var projectM: WindowSnapshot?
    var library: WindowSnapshot?
    var video: WindowSnapshot?
    var debug: WindowSnapshot?
}

struct WindowSnapshot {
    var wasVisible: Bool
    var frame: NSRect
    var wasShadeMode: Bool
}
```

The compact window must never be included in this snapshot.

## Enter Compact Mode sequence

`enterCompactMode(revealWindow:)` should follow this order:

```swift
guard compactModeState == .regular else { return }

compactModeState = .entering
UserDefaults.standard.set(true, forKey: "compactModeEnabled")

regularWindowSnapshot = captureRegularWindowSnapshot()

detachDockedChildWindows()
orderOutRegularWindows()

NSApp.setActivationPolicy(.accessory)
createCompactStatusItem()
createCompactWindowControllerIfNeeded()

DispatchQueue.main.async {
    if revealWindow {
        showCompactWindow()
        compactModeState = .compactVisible
    } else {
        hideCompactWindow()
        compactModeState = .compactHidden
    }
}
```

Important requirements:

- Do not call `showPlexBrowser()`.
- Do not route through normal side-docked window positioning.
- Do not reuse `plexBrowserWindowController?.window`.
- Detach AppKit child windows before hiding normal windows.
- Compact window ownership belongs only to the Compact Mode controller.

## Exit Compact Mode sequence

`exitCompactMode()` should follow this order:

```swift
guard compactModeState == .compactVisible || compactModeState == .compactHidden else { return }

compactModeState = .exiting
UserDefaults.standard.set(false, forKey: "compactModeEnabled")

hideCompactWindow()
destroyOrRetainCompactWindowController()
removeCompactStatusItem()

NSApp.setActivationPolicy(.regular)
restoreDockIconImage()

DispatchQueue.main.async {
    rebuildMainMenu()
    restoreRegularWindowSnapshot()
    updateDockedChildWindows()
    NSApp.activate(ignoringOtherApps: true)
    compactModeState = .regular
}
```

Main menu restoration must happen after returning to `.regular`. Do not rebuild the menu synchronously immediately after `NSApp.setActivationPolicy(.regular)`.

## Compact window design

Use a dedicated `NSPanel` or borderless `NSWindow`.

Recommended panel setup:

```swift
let panel = NSPanel(
    contentRect: initialFrame,
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: false
)

panel.level = .statusBar
panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
panel.hidesOnDeactivate = false
panel.isReleasedWhenClosed = false
```

Show using:

```swift
panel.orderFrontRegardless()
```

Positioning:

- Prefer anchoring below the status-bar item.
- If the status item window is not available yet, fall back to a visible top-area position on the active/main screen.
- Clamp to the screen’s visible frame.

## Status item behavior

The status item should own only compact visibility and exit commands.

Left click:

```swift
toggleCompactWindowVisibility()
```

Right-click menu:

- Show/Hide Compact Window
- Exit Compact Mode

Do not use `window.isVisible` as source of truth. Use `compactModeState`.

## Playback updates

Current forwarding methods in `WindowManager` can stay, but their target should change.

Instead of forwarding to the Library Browser:

```swift
plexBrowserWindowController?.updateCompactBarTime(...)
plexBrowserWindowController?.updateCompactBarTrack(...)
plexBrowserWindowController?.updateCompactBarPlaybackState()
```

forward to:

```swift
compactModeWindowController?.updateTime(...)
compactModeWindowController?.updateTrack(...)
compactModeWindowController?.updatePlaybackState()
```

The compact controller/view should read from `WindowManager.shared.audioEngine` only for initial seeding. Ongoing updates should come through the existing broadcast/forwarding path.

## Launch restore behavior

Existing launch behavior:

```swift
let shouldRestoreCompactMode = UserDefaults.standard.bool(forKey: "compactModeEnabled")
AppStateManager.shared.restoreSettingsState {
    if shouldRestoreCompactMode {
        enterCompactMode(revealWindow: false)
    }
}
```

This is acceptable only if restoration is safe.

Add defensive behavior:

- If Compact Mode restore cannot create a status item or compact window, clear `compactModeEnabled`.
- Restore regular main window.
- Rebuild main menu.
- Never leave the app in accessory mode without a status item.

## Live UI mode switching

If the user switches modern/classic while Compact Mode is active, prefer a simple policy:

1. Exit Compact Mode.
2. Perform UI mode switch.
3. Do not automatically re-enter Compact Mode unless there is a deliberate product decision to do so.

This is safer because Compact Mode should be mode-independent and should not depend on the mode-dependent window teardown/rebuild path.

## Testing matrix

Manual QA:

- Launch regular → enter Compact Mode → compact window appears.
- Exit Compact Mode → main menu and main window restored.
- Enter Compact Mode again → compact window appears.
- Hide compact window via status item → show via status item.
- Right-click status item → Exit Compact Mode.
- Relaunch while `compactModeEnabled` is persisted → app starts as menu-bar app with status item.
- Relaunch compact → status item click shows compact window.
- Modern UI: main only.
- Modern UI: main + EQ + playlist + spectrum + library.
- Classic UI: main only.
- Classic UI: main + EQ + playlist + spectrum + library.
- Library Browser open before compact → restored correctly on exit.
- Library Browser closed before compact → stays closed on exit.
- Docked windows before compact → docking restored after exit.
- Switch modern/classic after exiting compact.
- Switch modern/classic while compact is active → should exit compact first, then switch.

Automated/pure-logic tests:

- valid state transitions
- invalid transition no-ops
- snapshot capture/restore data shape
- compact show/hide state changes
- persisted `compactModeEnabled` handling
- restore failure clears persisted compact flag

Most AppKit ordering and activation-policy behavior still requires manual QA.

## Non-goals

- Do not make Library Browser the compact surface.
- Do not infer Compact Mode state from normal window visibility.
- Do not synchronously restore menu/windows immediately after activation policy changes.
- Do not include the compact window in regular window state snapshots.
- Do not rely on docked child-window behavior while in Compact Mode.

## Success criteria

Compact Mode is successful when:

- the app can enter and exit Compact Mode repeatedly in both modern and classic UI;
- the compact window always appears when requested;
- the menu bar always returns after exit;
- normal windows restore exactly to their pre-compact visibility and frames;
- Library Browser behavior is unchanged outside Compact Mode;
- launch restore cannot trap the app in an invisible accessory-mode state.
