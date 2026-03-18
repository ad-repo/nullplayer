# Art Mode Visualization Settings Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a grouped visualization effect picker and a persistent startup-default setting to Art Mode's context menus.

**Architecture:** All changes are in `ModernLibraryBrowserView.swift`. A static `groups` property on `VisEffect` defines the 5 categories. A new `buildVisEffectGroupSubmenus(into:)` helper populates both context menus from that definition. A new `browserVisDefaultEffect` UserDefaults key stores the startup-default effect, checked before `browserVisEffect` on init.

**Tech Stack:** Swift, AppKit (`NSMenu`, `NSMenuItem`), `UserDefaults`

---

## Chunk 1: VisEffect groups + selection handler + default persistence

### Task 1: Add `groups` static property to `VisEffect`

**Files:**
- Modify: `Sources/NullPlayer/Windows/ModernLibraryBrowser/ModernLibraryBrowserView.swift:418-427`

The `VisEffect` enum is a nested type inside `ModernLibraryBrowserView`. Add a `static var groups` property as the last member inside the enum body (before its closing `}`).

- [ ] **Step 1: Add the `groups` property inside `VisEffect`**

Replace:
```swift
        case datamosh = "Datamosh", blocky = "Blocky"
    }
```

With:
```swift
        case datamosh = "Datamosh", blocky = "Blocky"
        static var groups: [(title: String, effects: [VisEffect])] {[
            ("Rotation & Scaling", [.psychedelic, .kaleidoscope, .vortex, .spin, .fractal, .tunnel]),
            ("Distortion",         [.melt, .wave, .glitch, .rgbSplit, .twist, .fisheye, .shatter, .stretch]),
            ("Motion",             [.zoom, .shake, .bounce, .feedback, .strobe, .jitter]),
            ("Copies & Mirrors",   [.mirror, .tile, .prism, .doubleVision, .flipbook, .mosaic]),
            ("Pixel Effects",      [.pixelate, .scanlines, .datamosh, .blocky]),
        ]}
    }
```

- [ ] **Step 2: Build and verify no compile errors**

```bash
cd /Users/ad/Projects/nullplayer && swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!`

---

### Task 2: Add `menuSelectEffect(_:)` and `menuSetDefaultEffect()` handlers

**Files:**
- Modify: `Sources/NullPlayer/Windows/ModernLibraryBrowser/ModernLibraryBrowserView.swift` — near line 4607 (existing `@objc` vis handlers)

Add the two new handlers immediately after `@objc private func menuNextEffect() { nextVisEffect() }` (line 4607).

- [ ] **Step 1: Add the handlers**

Replace:
```swift
    @objc private func menuNextEffect() { nextVisEffect() }
```

With:
```swift
    @objc private func menuNextEffect() { nextVisEffect() }

    @objc private func menuSelectEffect(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let effect = VisEffect(rawValue: raw) else { return }
        currentVisEffect = effect
        UserDefaults.standard.set(effect.rawValue, forKey: "browserVisEffect")
    }

    @objc private func menuSetDefaultEffect() {
        UserDefaults.standard.set(currentVisEffect.rawValue, forKey: "browserVisDefaultEffect")
    }
```

- [ ] **Step 2: Build**

```bash
cd /Users/ad/Projects/nullplayer && swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!`

---

### Task 3: Update init restoration to respect `browserVisDefaultEffect`

**Files:**
- Modify: `Sources/NullPlayer/Windows/ModernLibraryBrowser/ModernLibraryBrowserView.swift:593-600`

The existing restoration block (lines 593–600) loads `browserVisEffect`. Replace it so that `browserVisDefaultEffect` takes priority when set.

- [ ] **Step 1: Replace the restoration block**

Replace:
```swift
        // Load saved visualizer preferences
        if let savedEffect = UserDefaults.standard.string(forKey: "browserVisEffect"),
           let effect = VisEffect(rawValue: savedEffect) {
            currentVisEffect = effect
        }
```

With:
```swift
        // Load saved visualizer preferences — default effect takes priority over last-used
        let defaultEffectKey = UserDefaults.standard.string(forKey: "browserVisDefaultEffect")
        let lastUsedKey = UserDefaults.standard.string(forKey: "browserVisEffect")
        if let raw = defaultEffectKey ?? lastUsedKey, let effect = VisEffect(rawValue: raw) {
            currentVisEffect = effect
        }
```

- [ ] **Step 2: Build**

```bash
cd /Users/ad/Projects/nullplayer && swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/NullPlayer/Windows/ModernLibraryBrowser/ModernLibraryBrowserView.swift
git commit -m "feat: add VisEffect groups, effect selection handler, and default persistence"
```

---

## Chunk 2: Shared submenu builder + updated context menus

### Task 4: Add `buildVisEffectGroupSubmenus(into:)` helper

**Files:**
- Modify: `Sources/NullPlayer/Windows/ModernLibraryBrowser/ModernLibraryBrowserView.swift` — add near `showVisualizerMenu` (around line 3911)

Add this private helper immediately before `showVisualizerMenu`. Use the function signature as the anchor for the Edit tool.

- [ ] **Step 1: Add the helper**

Replace:
```swift
    private func showVisualizerMenu(at event: NSEvent) {
```

With:
```swift
    /// Appends grouped effect submenus to `menu`. Each item is checked when it
    /// matches `currentVisEffect`; bullet-marked when it matches the saved default.
    private func buildVisEffectGroupSubmenus(into menu: NSMenu) {
        let savedDefault = UserDefaults.standard.string(forKey: "browserVisDefaultEffect")
        for group in VisEffect.groups {
            let groupItem = NSMenuItem(title: group.title, action: nil, keyEquivalent: "")
            let sub = NSMenu(title: group.title)
            for effect in group.effects {
                let item = NSMenuItem(title: effect.rawValue,
                                      action: #selector(menuSelectEffect(_:)),
                                      keyEquivalent: "")
                item.target = self
                item.representedObject = effect.rawValue
                if effect == currentVisEffect {
                    item.state = .on
                } else if effect.rawValue == savedDefault {
                    item.state = .mixed
                }
                sub.addItem(item)
            }
            groupItem.submenu = sub
            menu.addItem(groupItem)
        }
    }

    private func showVisualizerMenu(at event: NSEvent) {
```

- [ ] **Step 2: Build**

```bash
cd /Users/ad/Projects/nullplayer && swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!`

---

### Task 5: Update `showVisualizerMenu`

**Files:**
- Modify: `Sources/NullPlayer/Windows/ModernLibraryBrowser/ModernLibraryBrowserView.swift:3911-3921`

Replace the existing `showVisualizerMenu` body:

- [ ] **Step 1: Replace the method**

Replace:
```swift
    private func showVisualizerMenu(at event: NSEvent) {
        let menu = NSMenu(title: "Visualizer")
        let currentItem = NSMenuItem(title: "▶ \(currentVisEffect.rawValue)", action: nil, keyEquivalent: "")
        currentItem.isEnabled = false; menu.addItem(currentItem)
        let nextItem = NSMenuItem(title: "Next Effect →", action: #selector(menuNextEffect), keyEquivalent: "")
        nextItem.target = self; menu.addItem(nextItem)
        menu.addItem(NSMenuItem.separator())
        let offItem = NSMenuItem(title: "Turn Off", action: #selector(turnOffVisualization), keyEquivalent: "")
        offItem.target = self; menu.addItem(offItem)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
```

With:
```swift
    private func showVisualizerMenu(at event: NSEvent) {
        let menu = NSMenu(title: "Visualizer")
        let currentItem = NSMenuItem(title: "▶ \(currentVisEffect.rawValue)", action: nil, keyEquivalent: "")
        currentItem.isEnabled = false; menu.addItem(currentItem)
        menu.addItem(NSMenuItem.separator())
        buildVisEffectGroupSubmenus(into: menu)
        menu.addItem(NSMenuItem.separator())
        let defaultItem = NSMenuItem(title: "Set Current as Default",
                                     action: #selector(menuSetDefaultEffect),
                                     keyEquivalent: "")
        defaultItem.target = self; menu.addItem(defaultItem)
        menu.addItem(NSMenuItem.separator())
        let offItem = NSMenuItem(title: "Turn Off", action: #selector(turnOffVisualization), keyEquivalent: "")
        offItem.target = self; menu.addItem(offItem)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
```

- [ ] **Step 2: Build**

```bash
cd /Users/ad/Projects/nullplayer && swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!`

---

### Task 6: Update `showArtContextMenu`

**Files:**
- Modify: `Sources/NullPlayer/Windows/ModernLibraryBrowser/ModernLibraryBrowserView.swift:3923-3942`

Replace the existing `showArtContextMenu` body:

- [ ] **Step 1: Replace the method**

Replace (note: blank lines contain 8 spaces):
```
    private func showArtContextMenu(at event: NSEvent) {
        let menu = NSMenu(title: "Art")
        let visItem = NSMenuItem(title: "Enable Visualization", action: #selector(enableArtVisualization), keyEquivalent: "")
        visItem.target = self; menu.addItem(visItem)
        
        // Rate submenu (when a rateable track is playing)
        if let currentTrack = WindowManager.shared.audioEngine.currentTrack,
           currentTrack.plexRatingKey != nil || currentTrack.subsonicId != nil || currentTrack.jellyfinId != nil || currentTrack.embyId != nil || currentTrack.url.isFileURL {
            menu.addItem(NSMenuItem.separator())
            let rateMenu = buildRateSubmenu()
            let rateItem = NSMenuItem(title: "Rate", action: nil, keyEquivalent: "")
            rateItem.submenu = rateMenu
            menu.addItem(rateItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        let exitItem = NSMenuItem(title: "Exit Art View", action: #selector(exitArtView), keyEquivalent: "")
        exitItem.target = self; menu.addItem(exitItem)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
```

With:
```swift
    private func showArtContextMenu(at event: NSEvent) {
        let menu = NSMenu(title: "Art")
        let visItem = NSMenuItem(title: "Enable Visualization", action: #selector(enableArtVisualization), keyEquivalent: "")
        visItem.target = self; menu.addItem(visItem)

        // Visualization submenu — effect picker + set default
        let visMenuContainer = NSMenuItem(title: "Visualization", action: nil, keyEquivalent: "")
        let visSub = NSMenu(title: "Visualization")
        buildVisEffectGroupSubmenus(into: visSub)
        visSub.addItem(NSMenuItem.separator())
        let defaultItem = NSMenuItem(title: "Set Current as Default",
                                     action: #selector(menuSetDefaultEffect),
                                     keyEquivalent: "")
        defaultItem.target = self; visSub.addItem(defaultItem)
        visMenuContainer.submenu = visSub
        menu.addItem(visMenuContainer)

        // Rate submenu (when a rateable track is playing)
        if let currentTrack = WindowManager.shared.audioEngine.currentTrack,
           currentTrack.plexRatingKey != nil || currentTrack.subsonicId != nil || currentTrack.jellyfinId != nil || currentTrack.embyId != nil || currentTrack.url.isFileURL {
            menu.addItem(NSMenuItem.separator())
            let rateMenu = buildRateSubmenu()
            let rateItem = NSMenuItem(title: "Rate", action: nil, keyEquivalent: "")
            rateItem.submenu = rateMenu
            menu.addItem(rateItem)
        }

        menu.addItem(NSMenuItem.separator())
        let exitItem = NSMenuItem(title: "Exit Art View", action: #selector(exitArtView), keyEquivalent: "")
        exitItem.target = self; menu.addItem(exitItem)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
```

- [ ] **Step 2: Build**

```bash
cd /Users/ad/Projects/nullplayer && swift build 2>&1 | grep -E "error:|Build complete"
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/NullPlayer/Windows/ModernLibraryBrowser/ModernLibraryBrowserView.swift
git commit -m "feat: add grouped effect picker and default setting to art mode context menus"
```

---

## Manual QA Checklist

After both commits, run the app (`./scripts/kill_build_run.sh`) and verify:

**Vis-active menu (right-click while visualization is running):**
- [ ] "▶ Current Effect" label shows the correct effect name (disabled)
- [ ] 5 group submenus appear (Rotation & Scaling, Distortion, Motion, Copies & Mirrors, Pixel Effects)
- [ ] Each group's submenu lists the correct effects with a checkmark on the active one
- [ ] Selecting a different effect immediately switches the visualization
- [ ] "Set Current as Default" saves the effect — quit and relaunch confirms it starts on that effect
- [ ] If default ≠ current, the default shows a bullet (`.mixed`) state in the list
- [ ] "Turn Off" still works
- [ ] "Next Effect →" no longer appears in the menu

**Art context menu (right-click while vis is off):**
- [ ] "Enable Visualization" still appears and works
- [ ] "Visualization ▶" submenu appears with all 5 groups
- [ ] Selecting an effect in the submenu sets it as the current effect (visible when vis is then enabled)
- [ ] "Set Current as Default" works from this menu too
- [ ] Rate submenu still appears for rateable tracks
- [ ] "Exit Art View" still works

**Persistence:**
- [ ] Quit and relaunch — visualization starts on the default effect, not necessarily the last-used
- [ ] Clear `browserVisDefaultEffect` from UserDefaults (via Defaults Editor or Terminal) — confirms fallback to `browserVisEffect` (last-used)
- [ ] Set `browserVisDefaultEffect` to a stale/invalid value (e.g. `"BadEffect"`) — confirms fallback to last-used, then `.psychedelic` hardcoded default
