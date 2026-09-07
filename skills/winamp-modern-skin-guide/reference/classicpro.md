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

**The installer can ship one path twice, and NSIS keeps the *last* one.** Audited 2026-09-05 by
extracting `ClassicPro_2.01.exe` with `7z` and diffing it file-by-file against the installed tree:
308 of 309 files are byte-identical, and the one deviation is ours, not the user's.
`xui/PlaylistPro/_v1/PlaylistPro.xml` appears **twice** in the installer — a 312-byte stub dated
2012-01-24 and the full 3711-byte definition dated 2012-10-17 — and it is the only duplicated path in
the engine tree. NSIS replays `ExtractFile` in order, so a real Winamp install ends with the 3711-byte
file; `NSISArchive.extract` does the opposite (`guard result[path] == nil else { continue }`,
first-write-wins) and keeps the stub. The stub is a bare `windowholder` `groupdef`; the full version
is what defines the PlaylistPro search-results list, its edit box, and the search bar — so cPro skins
using the `_v1` PlaylistPro XUI ran against a hollowed-out definition. **Fixed 2026-09-05** in
`5ede97b1`: `extract` is last-wins, and because a duplicate no longer grows `result`, it counts
materialized extractions rather than result entries to bound the work. `declaredTotal` still
accumulates over superseded duplicates — an over-count in the conservative direction, and *not* the
decompression cost, since `LZMA1Decoder.output` is cumulative and re-reading an earlier position is
an array copy, never a second inflate.

`xui-files_one.xml` includes `_v1` and `xui-files_two.xml` includes `_v2`, and only `_v1` was
duplicated — so this cost the **`one` family alone** its playlist search UI, and `two`-family skins
never saw it. Confirmed on screen in cPro-Bento: no search strip before, the edit box and Search
button after. Note `p0` of `EW_EXTRACTFILE` is the overwrite flag and `NSISArchive` does not decode
it, so last-wins is an assumption; it is safe here because the second copy is both later in replay
order and newer, so every overwrite mode keeps it.

**An engine imported before that fix keeps the stub** — the engine lives outside the app bundle and
there is no migration. Re-importing the installer is the only remedy, which is what the untested-build
status line and the load-time warning exist to prompt.

**The engine is pinned by digest, and the tree hash is the authority.**
`ClassicProEngineProvenance.swift` holds the SHA-256 of `ClassicPro_2.01.exe`
(`c118937b…`, 1 370 091 bytes) and of the 309-file tree it extracts to (`265193d8…`, observed after
the last-wins fix; a first-wins reader gives `53a9ff68…`). Re-derive the tree hash by importing and
reading `contentHash` from `.engine-info.json`, never by hand.

A tree hash that is *not* the pinned one is a signal to **investigate, never to update the constant**
— with the installer digest matching, it means our extraction changed, which is why `verdict` reports
`.treeMismatch` there instead of folding the installer digest into an OR. `.unrecognized` is the
ordinary "some other build" case: a blocking Cancel/Import Anyway alert at import, a greyed status
line in the menu, and one warning per engine hash when a skin actually **reads bytes from** the mount
(the engine mounts for every skin, so a probe must not count — `WalVirtualFileSystem` records only in
`data(at:)`). A `nil` installer digest, from a folder or bare-tree import, is not a downgrade: the
tree hash alone can still say `.knownGood`.

The digests only verify against the user's own copy — there is nothing committed to check them
against, and there cannot be.

The audit's other two results are clean and worth not re-deriving: the one file 7z produces that we do
not (`widgets/data/nowplaying/$SMPROGRAMS/…/$(LSTR_114).url`) is a Start Menu shortcut whose path
still holds unresolved NSIS variables — `NSISArchive` skips those deliberately and 7z does not — and
recomputing the store's content hash over the installed tree still reproduces the `contentHash` in
`.engine-info.json`, so nothing has been touched since import.

**The engine ships its MAKI `.m` source next to the bytecode.** Read the script that owns the broken
feature instead of inferring semantics — `getARGBValue`'s BGRA channel order, `getDateYear`'s
years-since-1900 scale, and the `isInvalid` probe idiom were all pinned that way rather than guessed.

**The SUI decides its own panes from the width it is handed, with no state of its own.**
`xui/CentroSUI/_v1/scripts/CentroSUI.m` shows and hides the right-hand playlist pane
(`centro.playlist1`) purely on the `w` of its `onResize` — `if(w<10){ area_right.hide(); } else
{ area_right.show(); }` — and `area_left`/`area_mini` are laid out the same way. So **any** wrong
width we hand this engine is not a mis-paint that the next frame corrects; it is a state change the
skin makes and does not revisit. B138 is that exact failure: one phantom 0-wide resize across a
layout switch hid the playlist pane for the rest of the session. See [scripting.md](scripting.md) →
*A layout switch is not a pane collapse*.


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
