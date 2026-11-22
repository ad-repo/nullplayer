# Menu Bar Integration Notes

This document describes how NullPlayer's macOS top menu bar is wired to global player actions.

## Top-Level Menus

`AppDelegate.setupMainMenu()` registers:

- `Windows`
- `UI`
- `Playback`
- `Visuals`
- `Libraries`
- `Output`

The app menu (`About nullPlayer`, `Quit nullPlayer`) remains separate and unchanged.

A standard static **Edit** menu (Undo, Redo, Cut, Copy, Paste, Select All) follows the app menu.
Text fields receive ⌘Z/⇧⌘Z/⌘X/⌘C/⌘V/⌘A only through these items; with no text field focused they
validate as disabled and the keystroke falls through to the window's own `keyDown` (the main
window's bare-letter transport keys are unaffected).

## Builder Ownership Rules

Menu-bar content is built via dedicated `ContextMenuBuilder.buildMenuBar*` methods.

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
