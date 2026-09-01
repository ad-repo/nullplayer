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


## Engine "two"

Everything above is the `one` family, which every cPro skin in the corpus used until cPro2 Dark
Aluminum was first measured (2026-09-01). A skin selects the family in **two** places and both must
agree: `ClassicPro.xml`'s `<ClassicPro version="2.01" engine="two">`, and the `<include>` in
`skin.xml` — `load-two.xml`, or `load-two_alpha.xml` for the drop-shadow variant.

The `two` entry point pulls an include graph **disjoint** from `one`. Nothing measured on a
cPro-Bento-family skin transfers automatically:

| | `one` | `two` |
|---|---|---|
| player XML | `one/xml/player*.xml` | `two/xml/player{,-elements,-elements-sui,-shade,-shade-elements}.xml`, `standardframe.xml`, `window-overrides.xml` |
| SUI / playlist | `xui/CentroSUI`, `PlaylistPro` | `xui/CentroSUI/_v2`, `PlaylistPro/_v2` (via `xui/xui-files_two.xml`) |
| widgets | `widgets/Load/*` | `widgets/Load/v2/*`, `xml/widgets-manager-cpro2.xml` |
| shadow | — | `two/xml/player-shadow.xml` (`main.shadow`), only under `load-two_alpha.xml` |
| layout scripts | `one/scripts/player.m`, `shade.m` | `two/scripts/layout.m`, `playback-layout.m`, `shade{,-layout,-resizer}.m`, `info-text.m`, `info-seeker.m`, `presetpos.m`, `read-classicpro.m` |

**The whole player is laid out from `System.onShowLayout`, and only from there.** `layout.m` places
`two.screen` — the entire info + transport band — inside `fullScreen()`, and the only cold-start
caller is `System.onShowLayout`, which the engine comments *"On cold start"*. The one line in
`buildSkin()` that would otherwise set it is **commented out in the engine source**. A host that does
not dispatch that event gets a skin whose bands sit at `y=0`, drawn over the titlebar, with a
titlebar-height dead strip above the SUI — and no diagnostic anywhere, because every element parsed
and every script ran.

Its guard is `if(_layout==normal && !shade.isVisible())`, so a host must also answer `isVisible` on a
**layout** by whether it is its container's *active* one. A container shows exactly one layout at a
time; reporting the window's visibility for every layout it owns makes `normal` and `shade` both true
and the cold start never runs.

`fullScreen(false)` also seeds the window from `getPublicInt("cPro2.x", getCurAppLeft())` and the
three siblings, so all four `getCurApp*` methods must exist **and answer in Winamp's screen space**
(y downward). `presetpos.m`'s F9–F12 slots call the same four in one expression, so a missing
`getCurAppWidth`/`getCurAppHeight` kills `saveFramePos()` on its third call and nothing is ever
stored.

**`<TextSettings>` styles are order-dependent.** `two/scripts/read-classicpro.m` receives each
`<Style>` through `parser_onCallback` as two parallel lists and applies them with
`if (name == "id") busyWith = value; else if (busyWith == …) apply` — so every attribute written
*before* `id` is skipped by construction, and the engine comments that it relies on the id arriving
first. The lists must be in **document** order; see
[scripting.md](scripting.md) → *`parser_onCallback` hands its attributes in document order*.

**`ClassicProEngineStore.validate` still hard-requires the `one` family**
(`ClassicProEngine.swift`, *"does not provide the \"one\" family required by cPro-Bento"*). That was
accurate when written and is now misleading: a `two`-only tree would be rejected even though the
corpus has a skin that needs only `two`. It is not a live problem — the shipped ClassicPro 2.01
installer contains **both** families, so the gate passes and `WINAMP_MODERN_ENGINE` need not be set
at all (the shared store already resolves) — but if a `two`-only tree ever turns up, the gate and its
message are what to change.

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
