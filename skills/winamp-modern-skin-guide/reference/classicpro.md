# ClassicPro engine import

Reference for the `winamp-modern-skin-guide` skill.

## ClassicPro engine

cPro-Bento does not contain its own engine — it depends on the **ClassicPro** plugin, which ships in a
separate Windows installer. NullPlayer bundles nothing and asks for no permission; the user supplies
the installer and it is extracted **internally**, with no external tools, temp files, or code
execution:

- `LZMA1Decoder` — from-scratch incremental raw LZMA1 range decoder
- `NSISArchive` — NSIS-2 solid-LZMA reader; replays only `SetOutPath`/`ExtractFile` to reconstruct the
  file tree. Other layouts (non-solid, zlib/bzip2, NSIS-3, non-NSIS) get an actionable diagnostic.
- `ClassicProEngineImporter` accepts `.exe`, `.zip` (including a nested installer), or an extracted
  folder; validates structure (requires the `one` family) and SHA-256 hashes the content
- `ClassicProEngineStore` keeps one private copy and exposes a read-only mounted provider

The engine's entire native (`ClassicPro.w5s`) surface is three filesystem-shell methods, none on the
render path. They are adapted under a strict policy: `exploreFile` reveals an existing file in Finder,
`openFile` opens an existing file with the default app (no URLs, no `~`, no executables), and
`findFiles` is a bounded no-op returning −1 so callers early-return.

`WinampVersionCheck` is satisfied by reporting a build number past the `2405` gate, so `load.xml`
*branches* through its "please update Winamp" path rather than being hard-blocked. The skin's own
`warning.maki` runs a **second, independent** check — a `Map` load of the engine's 1×1
`image/installed.png` — and `switchSkin`es away if it fails; that is why `loadMap` must accept a path.
`switchSkin` itself is accepted and inert: choosing a skin is the host's decision, not a script's.

**The engine ships its MAKI `.m` source next to the bytecode.** Read the script that owns the broken
feature instead of inferring semantics — `getARGBValue`'s BGRA channel order, `getDateYear`'s
years-since-1900 scale, and the `isInvalid` probe idiom were all pinned that way rather than guessed.


## The widget census: `ColorMgr.onLoaded` → `cProLoaded()`

The engine's widgets — the Widgets Manager's list, and the SUI tabs a user widget adds — all hang off
one event that is easy to miss:

```maki
Global ColorMgr StartupCallback;
System.onScriptLoaded() { StartupCallback = new ColorMgr; … }
StartupCallback.onLoaded() { cProLoaded(); }
```

`cProLoaded()` is the **only** caller of `widget_manager_register` / `_check` / `_done`, the three
actions that fill `widgetsManager.maki`'s list, and three separate scripts declare one:
`CproTabs` registers "Main Area", `one/scripts/drawer.m` "Drawer Area", `CentroSUI` "Side Area" —
which is the 3 its `NUM_WIDGET_PLACES` counts, so all three must be dispatched, not just the one
whose window is open.

Two things had to be true before any of it ran:

- **`new ColorMgr` is the singleton.** Winamp's colour manager is one object; a script saying `new`
  is asking for *the* one. Answering with a generic dynamic shell made `onLoaded` unreachable —
  dispatch matches on the value the variable holds — and sent `getColor`/`getGammaSet` to an object
  that has neither.
- **`onLoaded` is dispatched after every `onScriptLoaded` in the skin**, because the three
  `cProLoaded()` bodies call actions on `widgetsManager.maki`, which is a *skin-level* script.
  Dispatched earlier it reaches a manager whose own `onScriptLoaded` has not yet found its list.

The drawer's own bucket is `wndtype="centro.widgets.drawer"` and the engine ships no widget declaring
that `windowtype`, so **zero user widgets in the drawer is correct** and *"No widgets found for this
view!"* is the right menu item. The widgets live in `centro.widgets.main`, whose bucket is in
`xui/CentroSUI/_v{1,2}/CproTabs/CproTabs.xml`.

## The `(255,0,128)` menu-bar filler is the engine's own decision

Four of the installed cPro skins ship uncut template filler where the titlebar menu artwork should be
cut, and `mainmenu.maki` detects exactly that and **hides its own menu bar**, showing `cpro.bg.title`
instead where the skin declares one. So a magenta menu bar is never Winamp's behaviour and never the
skin author's intent — it is a failed self-check. See
[scripting.md](scripting.md) → *`Map.loadMap(id)` covers the bitmap's sub-rect*, which is what broke
it.

`(255,0,128)` is the ClassicPro **template's** "uncut area" marker, not a per-skin choice:
cPro-Bento's own `buttons.png` carries 14,958 such pixels across the sheet, and its menu row is the
part its author deliberately erased to transparent. Measured 2026-08-31.
