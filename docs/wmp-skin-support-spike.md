# Spike: Windows Media Player (`.wmz`) skin support

**Status:** research spike, no code written. **Date:** 2026-08-30.
**Sample analysed:** `9SeriesDefault.wmz` — Microsoft's "9 Series Default" (theme id `Corona`), 2004.
**External reference:** <https://sites.google.com/view/wmpgoodies/guides/making-a-skin-for-wmp>

## 1. Verdict

Supporting WMP skins as a **fourth skin mode** is feasible, and the container and asset work is
*easier* than `.wal` was — a `.wmz` is a plain ZIP of BMPs and one XML file, with no NSIS
installer, no LZMA, and no MAKI bytecode to reverse-engineer.

The cost is not in the container. It is in three mechanisms the codebase has no precedent for,
one of which dominates the estimate: **`.wms` layout attributes are JScript expressions**, so a
correct implementation needs a real JavaScript host, not a parser. macOS ships JavaScriptCore in
the SDK, so this is a design problem rather than a dependency problem — but it is the schedule risk.

Rough shape: a usable static-render mode is small; a *faithful* mode is a new engine on the order
of 8–12k LOC. See §6.

## 2. What a `.wmz` actually is

`9SeriesDefault.wmz` is a plain ZIP with 119 entries:

| Kind | Count | Notes |
|---|---|---|
| `.wms` skin definition | 1 | `Corona.wms`, 73 KB |
| `.js` script files | 3 | `Corona.js`, `metadata.js`, `corona_tiny.js` |
| `.bmp` assets | 115 | all 24-bit Windows 3.x, no alpha channel |

Reproduce with `unzip -l 9SeriesDefault.wmz`.

**Assets.** Every image is a 24-bit uncompressed Windows BMP:

```
$ file player_top_left.bmp
player_top_left.bmp: PC bitmap, Windows 3.x format, 299 x 33 x 24, ... bits offset 54
```

There is no alpha. Transparency is **color-keyed** at draw time via a per-element
`transparencyColor="#FF00FF"` attribute (40 occurrences in this skin). ImageIO/`NSImage` decodes
Windows BMP natively, so decoding is free; the color-key masking is ours to implement. The
wmpgoodies guide notes skins may also ship GIF/JPG, and PNG on WMP 12 only.

**The skin definition.** `Corona.wms` is **UTF-16LE XML**, 1074 lines. It must be transcoded
before parsing (`iconv -f UTF-16LE -t UTF-8`); a UTF-8-assuming parser sees interleaved NULs.
Structure is `<THEME>` → two `<VIEW>` elements:

- `vPlayer` — the full 859×468 resizable player.
- `viewTiny` — a separate compact view, i.e. **a skin ships multiple top-level views** and
  switches between them (`theme.currentViewID`).

**Element catalog** (counts from this skin):

```
SUBVIEW 33   TEXT 15   BUTTON 14   SLIDER 10   BUTTONELEMENT 10   BUTTONGROUP 6
VOLUMESLIDER 2   SEEKSLIDER 2   BALANCESLIDER 1
PLAYELEMENT/PAUSEBUTTON/STOPELEMENT/PREVELEMENT/NEXTELEMENT/REWBUTTON/REWELEMENT/
  FFWDBUTTON/FFWDELEMENT/RETURNBUTTON/SHUFFLEBUTTON
PLAYLIST 1   DROPDOWNPLAYLIST 1   VIDEO 1   WMPVIDEO 1   WMPEFFECTS 1
EQUALIZERSETTINGS 1   POPUP 1   PLAYER 2   NETWORK 2
```

About 30 tag types — a **fixed, closed widget catalog**. This is a meaningful contrast with
Wasabi, where `<groupdef>`/XUI lets a skin define its own component types. A closed catalog is
easier to implement completely and easier to declare "done".

**Layout** is absolute `left`/`top`/`width`/`height` plus `horizontalAlignment` /
`verticalAlignment` (`stretch`, `left`, `right`, `top`) for resize behaviour, and `zIndex`.

## 3. The three mechanisms with no precedent in this codebase

### 3.1 Mapping-image hit testing

A `BUTTONGROUP` carries one sprite sheet per visual state plus a **`mappingImage`**. Each child
element claims its clickable region by naming a color in that map:

```xml
<BUTTONGROUP id="bgTransports" left="8" top="20" width="136" height="30"
    mappingImage="transports_map.bmp"
    image="transports.bmp" hoverImage="transports_hover.bmp"
    downImage="transports_down.bmp" disabledImage="transports_disabled.bmp">

    <PLAYELEMENT id="play" mappingColor="#FF0000" tabStop="wmpenabled:player.controls.play"/>
    <NEXTELEMENT mappingColor="#FA6A6A"/>
    <STOPELEMENT mappingColor="#00FF00"/>
    <PREVELEMENT mappingColor="#FFFF00"/>
    <BUTTONELEMENT id="bMute" mappingColor="#79C666"
        onClick="jscript:player.settings.mute=down;"
        down="wmpprop:player.settings.mute" sticky="true"/>
</BUTTONGROUP>
```

Hit testing is a **per-pixel color lookup** in the map bitmap, not a rectangle test — buttons may
be any shape. Four mapping images in this skin.

**What we would build:** decode each mapping BMP once into a flat `[UInt32]` buffer, build a
`color → element` dictionary at load, and answer hover/press by sampling one pixel. Cheap, and it
also gives per-element bounding boxes for free (needed for targeted repaint). Nothing in
`Skin/`, `ModernSkin/`, or `WinampModern/` does this today — all three hit-test rectangles.

### 3.2 JScript expressions inside layout attributes

85 occurrences. Geometry is not data, it is code:

```xml
<SUBVIEW id="svMain" left="250" top="0"
    width="JScript:view.width-svStub.width-svMain.left;"
    height="289" zIndex="10"
    verticalAlignment="stretch" horizontalAlignment="stretch">
```

```xml
<REWBUTTON id="rew" ...
    onclick="JScript:down==false?player.controls.play():player.controls.fastReverse();"/>
```

Expressions read peer elements by `id` (`svStub.width`, `svTopMiddle.left+svTopMiddle.width`) and
the host (`view.width`). They must be **re-evaluated on every resize**, in dependency order.

**What we would build:** a JavaScriptCore `JSContext` per view, with every element exposed as a
named object whose geometry properties are live. Cycle and depth limits are ours to add. This is
the single largest piece of work and the reason a "just parse the XML" approach cannot produce a
correct skin — the `Corona` layout literally does not resolve without an evaluator.

### 3.3 `wmpprop:` / `wmpenabled:` data binding

44 occurrences. One-way binds from the player object model, or from a peer widget, into an
attribute:

```
down="wmpprop:player.settings.mute"          value="wmpprop:eq.gainLevel3"
enabled="wmpprop:vis.visible"                visible="wmpenabled:player.controls.pause"
left="wmpprop:bgTransports.left"             value="wmpprop:player.controls.currentPositionString"
```

**What we would build:** a small observable-property registry that re-pushes bound attributes when
the underlying value changes. `wmpenabled:` is the "is this command currently available" variant.
This is straightforward once the object model from §3.2 exists — it shares the same name resolver.

### 3.4 Scripts

```xml
scriptFile="Corona.js;metadata.js;res://wmploc.dll/RT_TEXT/#132"
```

219 + 775 + 202 lines of UTF-16LE JScript. `metadata.js` is overwhelmingly a display-name lookup
table and is largely inert. Note the `res://wmploc.dll/...` entry — a Windows DLL string resource,
unresolvable on macOS; it must degrade to a diagnostic warning, not a load failure.

The object-model surface the skin actually touches is small and enumerable — roughly 40 members:

```
player.{controls, settings, currentMedia, currentPlaylist, openState, playState,
        network, status, URL, launchURL, dvd}
eq.{presetCount, presetTitle, gainLevel1..10}
vis.{visible, next}
theme.{loadPreference, savePreference, loadString, currentViewID, openDialog}
view.{width, height, minWidth, minHeight, timerInterval, minimize, close}
ipl.*  ddpl.*  popupPreset.appendItem  metadata.*
```

Events: `onLoad`, `onClose`, `onTimer` (with `timerInterval`), `openstatechange`,
`playstatechange`, `status_onchange`, `modechange`, `buffering/reception _onchange`, `onClick`,
`onchange`.

Most of this maps directly onto existing NullPlayer facilities (`AudioEngine`, the EQ, the
playlist, the visualisation router). `theme.loadPreference`/`savePreference` map onto
`UserDefaults` namespaced per skin.

## 4. Which base to build on

Evaluated against six criteria. **JSC** = JavaScriptCore.

| Criterion | Original (`nullPlayerModern`) | Winamp Modern (Wasabi) |
|---|---|---|
| Arbitrary nested XML tree ingestion | ✗ none — config is `skin.json` | ✓ `WalXML.swift` + `WasabiObjectGraph.swift` |
| Bounded/validated archive reader | ✗ plain directory loading | ✓ `WalArchive.swift`, ZIP with limits |
| Image sprite compositing + state sets | partial (per-element PNGs) | ✓ full, with resource cache |
| Per-pixel hit testing | ✗ | ✗ (rect-based) — new for both |
| Scripting host | ✗ | ✓ *shape* only — MAKI VM, not reusable for JScript |
| Window/controller hosting shell | ✓ clean `Windows/Modern*` + provider protocols | ✓ but heavier, multi-container |
| Risk of disturbing an existing mode | low | **high** — guide forbids behaviour changes |

**Original as the base.** The `ModernSkin` *engine* (`Sources/NullPlayer/ModernSkin/`, ~5,771 LOC)
is a **fixed element catalog driven by `skin.json` + a palette + optional PNGs**, with
programmatic fallback drawing for anything without an image. A `.wms` is an arbitrary nested
widget tree with skin-authored geometry expressions and skin-authored hit regions. Translating
`.wms` into `skin.json` would mean discarding the tree, the expressions, and the mapping images —
i.e. discarding the skin. **The engine layer is the wrong base.**

Its *window and controller layer* is a different story: `Windows/Modern*`, the provider protocols,
and the `WindowManager` registration conventions are a clean, well-understood hosting shell with
no `.wal` entanglement. **That part is a good base.**

**Winamp Modern as the base.** `WinampModern/` (~23,650 LOC) is the structural near-twin: archive
→ VFS → XML → object graph → Core Graphics scene render with hit testing and a script runtime, all
reporting through typed `WalFailure`/`WalDiagnostic` values rather than traps. But it is the
codebase's most complex subsystem, and `skills/winamp-modern-skin-guide` forbids changes that
alter Winamp Modern behaviour. Reuse must therefore be by **extraction**, never by widening the
Wasabi path in place. Concretely, the two schemas share a philosophy but almost no tag or
attribute — grafting WMP nodes onto `WasabiObjectGraph` would put `.wal` at risk for no
structural gain.

### Recommendation: hybrid

Build a **new, independent `Sources/NullPlayer/WMPSkin/` engine**, and:

- **Reuse from Winamp Modern, as leaf utilities or as patterns:**
  - `WalArchive.swift` — reusable close to verbatim. `.wmz` is plain ZIP, so unlike `.wal` there
    is no NSIS/LZMA path at all; only the entry-name/extension policy differs.
  - The bounded-limits model (`WalArchiveLimits` and friends) and the typed
    `WalFailure`/`WalDiagnostic` reporting style.
  - The rendering shape proven at `Windows/WinampModern/WinampModernMainView.swift:701` —
    `NSView.draw(_:)` over a `CGContext` with a scene cache and targeted repaint. No Metal.
  - The ingestor protocol in `WinampModern/WinampModernSkinImporter.swift:83-103`; a
    `WmzContainerIngestor` slots in beside `WalContainerIngestor` with no change to the existing
    ingestion path.
  - The host-bridge shape of `WinampModernHost.swift` for the `AudioEngine` boundary.
- **Reuse from Original:** the window/controller/provider conventions as the hosting shell.
- **Do not:** express `.wms` through `skin.json`, and do not add WMP nodes to `WasabiObjectGraph`.

## 5. Sketch of the work

Each phase is independently demonstrable.

- **P0 — ingest.** ZIP via `WalArchive`, UTF-16LE transcode, XML → typed node tree. Deliverable: a
  text dump of the tree for any `.wmz`.
- **P1 — static render.** BMP decode, color-key transparency, `SUBVIEW` nesting,
  alignment/`stretch` layout, `zIndex` ordering. Constant-folded geometry only — expressions
  treated as zero. Deliverable: `vPlayer` rendered recognisably.
- **P2 — input.** Rect and mapping-image hit testing, hover/down/disabled state sets, transports
  wired to `AudioEngine`. Deliverable: a clickable, playing skin.
- **P3 — scripting.** JSC host: `JScript:` attribute expressions with resize re-evaluation,
  `wmpprop:`/`wmpenabled:` binding, `scriptFile` loading, the ~40-member object model, the event
  set. Deliverable: correct layout at every window size, and `Corona.js` running.
- **P4 — mode plumbing.** `PlayerUIMode.wmp` and a fourth `PlayerUIControllerFamily` in
  `App/PlayerUIMode.swift` (the enum is at line 20, the family at line 14; `usesModernControllers`,
  `usesModernEQLayout`, and `modernSkinFamily` each need a fourth answer); the controller factory
  switch at `App/WindowManager.swift:856` and `reloadUI(to:)`; the Skins submenu in
  `App/ContextMenuBuilder.swift`; `WmzContainerIngestor`; a `WMPSkins/` support directory.
- **P5 — remaining widgets.** `PLAYLIST`/`DROPDOWNPLAYLIST`, `EQUALIZERSETTINGS` (10-band — maps
  onto the existing classic EQ, not the 21-band modern one), `WMPEFFECTS`/`VIDEO`, `POPUP`, and
  the second `viewTiny` view with view switching.

## 6. Effort and risk

Order-of-magnitude, benchmarked against the existing engines (`Skin/` ≈ 6,934 LOC,
`ModernSkin/` ≈ 5,771, `WinampModern/` ≈ 23,649):

| Phase | Rough LOC | Risk |
|---|---|---|
| P0 ingest | 400–700 | low — mostly reuse |
| P1 static render | 1,200–2,000 | low, routine |
| P2 input | 600–1,000 | low |
| P3 scripting | 2,500–4,000 | **high** |
| P4 mode plumbing | 400–800 | medium — touches shared files, must be gated |
| P5 remaining widgets | 1,500–2,500 | medium |
| **Total** | **~7,000–11,000** | |

Well under `.wal` (no bytecode VM, no NSIS, no XUI/groupdef system, closed widget catalog), well
over Classic. **P3 is the schedule risk**; P1 and P2 are routine work with a known shape. P4 is
low-LOC but high-care: it edits files all four modes run through.

## 7. What will not work

- `res://wmploc.dll/RT_TEXT/#132` and any other `res://` string resource — Windows DLL resources.
  Degrade to a warning and fall back to the literal attribute text.
- `player.dvd`, `player.launchURL`, and other Windows-shell-coupled members.
- WMP visualisation plugins and `WMPEFFECTS` presets — `WMPEFFECTS` can host *our* visualiser, but
  cannot run WMP's.
- Any skin whose JScript reaches for the Windows registry, `ActiveXObject`, or the shell.
- Video-heavy skins, to the extent NullPlayer is audio-first — `VIDEO`/`WMPVIDEO` would render as
  an inert or visualiser-filled pane.

Each of these should surface as a named diagnostic in a compatibility report, mirroring
`WinampModernCompatibilityReport.swift`, rather than as a load failure.

## 8. Security

The `.wal` sandbox rules apply verbatim and must not be weakened for `.wmz`: no host filesystem
access outside the skin's own resource provider, every input bounded (entry count, uncompressed
bytes, compression ratio, XML depth, image dimensions, script size), and typed failures rather
than traps.

One rule is **new**: a bare `JSContext` has no execution ceiling. JavaScriptCore needs its own
budget — a wall-clock watchdog via `JSContextGroupSetExecutionTimeLimit`, plus caps on expression
re-evaluation depth and on `onTimer` frequency — before any untrusted skin script is evaluated.

## 9. Recommendation

Proceed, but buy the information cheaply first. **P0 + P1 is the decision point**: roughly a
week's work, no product-code commitment beyond a new directory, and it answers the only question
that actually matters — whether a real Microsoft skin renders recognisably from its own assets
without an expression evaluator. If `vPlayer` comes out looking like WMP 9 with geometry
expressions stubbed to zero, the remaining phases are a known quantity. If it does not, the
`.wms` layout model is more entangled with JScript than this analysis suggests, and the estimate
in §6 should be revisited before committing to P3.

## Appendix: reproducing the analysis

```bash
mkdir wmz && cd wmz
unzip -q ~/Downloads/9SeriesDefault.wmz
unzip -l ~/Downloads/9SeriesDefault.wmz          # 119 entries
ls *.bmp | wc -l                                  # 115
file player_top_left.bmp                          # 24-bit Windows 3.x BMP

iconv -f UTF-16LE -t UTF-8 Corona.wms > corona.xml
wc -l corona.xml                                   # 1074
grep -oE '<[A-Z][A-Z0-9]+' corona.xml | sort | uniq -c | sort -rn   # element inventory
grep -oE '[a-zA-Z]+=' corona.xml | sort | uniq -c | sort -rn        # attribute inventory
grep -c 'JScript:' corona.xml                      # 85
grep -c 'wmpprop:' corona.xml                      # 44
grep -oE 'wmpprop:[^"]*' corona.xml | sort -u      # the bind targets

iconv -f UTF-16LE -t UTF-8 Corona.js | less        # scripts are UTF-16 too
```
