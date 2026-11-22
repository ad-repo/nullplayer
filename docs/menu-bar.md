# Menu Bar Integration Notes

This document describes how NullPlayer's macOS top menu bar is wired to global player actions.

## Top-Level Menus

`AppDelegate.setupMainMenu()` registers, in order:

- the app menu (`About nullPlayer`, `Check for Updates…`, `Quit nullPlayer`)
- `Edit`
- `Windows`
- `Skins`
- `Playback`
- `Visuals`
- `Libraries`
- `Output`

**Edit** is the standard static AppKit menu (Undo, Redo, Cut, Copy, Paste, Select All). Text
fields receive ⌘Z/⇧⌘Z/⌘X/⌘C/⌘V/⌘A only through these items. A focused playlist (Classic, Original,
and the `.wmz` list widget) answers Select All, so ⌘A reaches its `selectAll(_:)` through the menu,
not its `keyDown`. With nothing focused that answers an item, the item validates as disabled and
the keystroke falls through to the window's own `keyDown` (the main window's bare-letter transport
keys are unaffected).

## Builder Ownership Rules

The dynamic menus (`Windows` onward) are built via dedicated `ContextMenuBuilder.buildMenuBar*`
methods. The app menu and Edit are static AppKit menus built inline in `setupMainMenu()`.

Important constraints:

- Do not share `NSMenuItem` instances between context menus and menu-bar menus.
- Do not use `copy()` on action-bearing `NSMenuItem` instances for menu-bar action dispatch.
- Build menu-bar-safe trees directly or move items from a temporary menu.

## Dynamic Refresh

Top-level menu freshness is handled by `NSMenuDelegate.menuNeedsUpdate` in `AppDelegate`:

- Menus are rebuilt when opened so checkmarks and availability are current.
- This is required for startup restore cases (window visibility and playback state).

## Output/Sonos Specific Rules

The `Output` menu is rebuilt on open and reads current discovery state.

Key behavior:

- Discovery is started from app lifecycle (`applicationDidFinishLaunching`), not during menu construction.
- Sonos in toolbar `Output` uses the same `SonosRoomCheckboxView` interaction model as the context menu.
- Sonos room checkbox clicks keep the submenu open for multi-select pairing before start/stop cast.
