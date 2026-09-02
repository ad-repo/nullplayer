# Winamp 5.x Modern Skins (`.wal`) — ranked open backlog

This is the only live backlog for the Winamp Modern subsystem. A skin is a test case, not a
milestone: take measured capability work from the top down. Closed entries move to
[`docs/winamp-modern/backlog-archive.md`](docs/winamp-modern/backlog-archive.md) in the same change
that closes them.

## Ranking

Measured items are ordered by reach, with effort as an advisory tiebreaker. Reach is corpus demand,
not severity. Live-reported draw defects are kept in their own tier because a screenshot or runtime
observation is not comparable to a static declaration count.

Effort bands: **S** = one attribute/method/local draw fix; **M** = behavior spanning multiple files
without a seam change; **L** = a host seam, protocol change, or new fixture harness.

### Measured capability gaps

| Id | Item | Reach | Effort | Tier |
|---|---|---:|:---:|---|
| B99 | **`enumObject` / `getNumObjects` are unimplemented, and ClassicPro's InfoViewer walks its object list with them.** Dispatch is fail-closed, so each call abandons the whole handler, not just the loop. Measured on cPro2 Dark Aluminum 2026-09-01: `enumObject` ×12 and `getNumObjects` ×2, all from `xui/CentroSUI/_v2/InfoViewer/InfoViewer.xml`, and the demand **rose** from ×2 once `System.onShowLayout` started running the paths that reach it. `enumItem` (×1, `xml/widgets-manager-cpro2.xml`) is the same family | 1 skin measured; the `_v2` SUI is shared by any future engine-`two` skin | M | Measured |
| B100 | **`onLeaveArea` is unimplemented.** `xui/CentroSUI/_v2/CentroSUI.xml` binds it (×1). The paired `onEnterArea` decides what a hover reveals, so the leave half is what puts it away again — expect something in the SUI to stay lit after the pointer goes | 1 skin measured (cPro2) | S | Measured |
| B101 | **Aero-snap and the engine-two drop shadow are inert, by decision rather than by omission.** `snapAdjust` is accepted and returns `.null`; `main.aerosnap` renders as a 2-node stub. `load-two_alpha.xml` declares a `main.shadow` container (830×630) that nothing instantiates. Both are Windows shell behaviours with macOS counterparts already provided by the window server, so this is filed to record the decision, not to schedule work. Close it as *won't do* unless a skin turns out to draw something into either | every engine-`two` skin | L | Measured |
| BB14 | Animated layout/tab transitions beyond existing object tweens | 0 known dependent skins; existing tween calls are not evidence for this missing surface ([M4]) | L | Measured |
| B18 | Classic minimize-mask parity | — · engine integration, outside the corpus | S | Measured |

### Live-reported draw defects

| Id | Item | Reach | Effort | Tier |
|---|---|---:|:---:|---|
| B106 | **String width is measured with a full CoreText typesetting pass on the layout path.** `autoWidth(of:)` is reached from `append`, so every `<text>` sized from its own content ran `NSString.size(withAttributes:)` on **every scene rebuild** - `__NSStringDrawingEngine` -> `TTypesetterAttrString` - to answer a question whose answer never changes. Measured 2026-09-01 on cPro Bento (drawer visualization up, playing): the walk from `append` alone was 4.7%, and `__NSStringDrawingEngine` totalled **13.6%** across three call sites (`append`/`autoWidth`, `drawPlaylistComponent`/`drawSurfaceText`, and `drawText`'s own measure). Fixed for the two sites that measure with exactly `[.font:]`, which makes the memo key provably complete: `WasabiTextMetrics.measuredWidth(of:font:)`. `width(of:text:)` 5.1% -> 0.3%, `autoWidth` 5.5% -> 0.8%, `sizeWithAttributes` 7.8% -> 2.4% | every `.wal` skin with `autowidth` text; worst where the graph is largest | S | Live-reported |
| B105 | **`WinampModernConfiguration.safeComponent` rebuilds `CharacterSet.alphanumerics.union(_:)` on every call.** That union is not a cheap constant - it materializes Unicode bitmap planes (`CFUniCharGetBitmapForPlane`). It runs **twice per `storageKey`**, and a `storageKey` per config read, which puts it on the frame path for every `cfgattrib` in the scene. Measured **2.5%** of the main thread on cPro Bento, 2026-09-01. Fixed: the set is a `static let`, and an already-safe name is returned as-is instead of being rebuilt one `Character` at a time | every `.wal` skin with `cfgattrib` bindings | S | Live-reported |
| B104 | **A `CharacterSet` is rebuilt once per character, on a scan over every object in the graph, twice a frame.** `WinampModernComponents.swift:112` builds `CharacterSet(charactersIn:)` **inside** a `filter` closure, so CoreFoundation runs `CFCharacterSetCreateWithCharactersInString` -> `qsort` (and the matching dealloc) once per scalar to answer "is this character hex". It is reached from `refreshWaveformDemand`, which walks `allObjectsUnordered` **twice** calling `componentKind(of:)` on every object. Measured 2026-09-01 on cPro Bento with the drawer visualization up and audio playing (7991 main-thread samples): `normalize` **14.6%** of the main thread (~13.7% of it building and freeing `CharacterSet`s), `refreshWaveformDemand` **32.8%**, `surfaceID(of:)` **32.0%**. Nothing in the line is cPro-specific - the **reach** is: the cost is per object, and cPro's graph (ClassicPro engine + CentroSUI + tabs + widgets + drawer) is the corpus's largest, which is also why adding the drawer made it worse | every `.wal` skin; scales with object count, so worst by far on cPro | S | Live-reported |
| B103 | **The script-dispatch and per-frame resolution paths rebuild their lookup tables on every call.** Measured 2026-09-01 on `2222-cPro__Bento`, debug build, **idle with nothing playing**: the process sits at **58-65% CPU** and `sample` puts ~64% of it on the main thread - 32.1% in `animationTick` -> `refreshLayerFXMeshes` -> `evaluateLayerFXMesh`, 30.8% in the `draw` that tick asks for. The mesh is not the cost: `WINAMP_MODERN_FX_TRACE=1` shows **one** realtime layer, `layer#animationscreen`, at `fx_setgridsize(10,1)` - an 11x2 vertex mesh, 44 MAKI calls per tick, 1320/sec. That works out to **~240 us per script dispatch**, and the four causes are all rebuilt-per-call tables; see the detail section | every `.wal` skin (items 1, 2, 4 are shared script/resource code); worst on cPro, which runs a 30 Hz realtime FX layer | M | Live-reported |
| B58 | In-skin visualization surface swallows single clicks | — · every skin with a `<vis>` the host fills | S | Live-reported |
| B60 | Hosted library and video surfaces have no body drag | — · every skin with a usable standard frame | M | Live-reported |
| B65 | A division by zero abandons the whole handler | 1 skin / 2 sites measured (Shield_Amp); corpus reach unmeasured | S | Live-reported |
| B71 | A layout script loads before the frame beside it has a client area | — · seen on Defix's detached visualizer (2026-08-29); corpus reach unmeasured | L | Live-reported |
| BB34 | An embedded visualization pane's engine never starts | — · seen on Big Bento Modern's Multi Content View mini pane (2026-08-29) | M | Live-reported |
| B74 | T800's five memory slots share one storage key | 1 skin / 5 buttons collapsing to 1 slot ([M22]) | L | Live-reported |
| B75 | A skin that includes the same script twice runs every handler twice | 1 skin measured (T800); corpus reach unmeasured | M | Live-reported |
| B82 | **A runtime-instantiated subtree is never told the current playback state.** A widget the user brings up mid-session gets `onScriptLoaded` and a seeding `onResize`, but no `onTitleChange` / `onPlay` / `onAlbumArtLoaded` for the track already playing, so anything it draws from those handlers stays blank until the *next* track change. Measured on ClassicPro's Now Playing widget (2026-08-31): the cover and jewel case draw, and its three `SC:FadeText` lines — title, artist, album, all filled from `System.onTitleChange` — stay empty. The whole-scene seeding pass runs once in `WinampModernMainView.scriptsDidStart()`, long before a widget instantiated by a tab click exists | 5 cPro skins ship widgets; any skin using `<CustomObject>` or `GroupList.instantiate` | M | Live-reported |
| B84 | **`WA5:Options` maps to the Skins/UI menu, which is thin.** B77 routed a skin's own menu bar to NullPlayer's menus; `WA5:File`/`Play`/`Windows`/`Help` have clear counterparts, but Winamp's Options menu (preferences, time display, skins, always-on-top) has none. It currently opens `buildMenuBarUIMenu()` — 4 items, mostly skin families. The fatter candidate is `buildMenu()`, the player's own context menu, which duplicates the Exit already on `WA5:File`. A decision, not a defect: pick a mapping or build an Options menu for it | 6 skins declare a `<Menu>` bar | S | Live-reported |
| B80 | Horizontal seams at fractional UI Sizes. Reported 2026-08-31 on cPro at **105%**, as hairlines along the boundaries between the drawer, seek and transport bands. **Measured facts:** a *full* draw is clean at both 2.0 and 2.1 device scale — zero partially-transparent rows in either, tested on the alpha channel, so this is not inherent to fractional scaling. It is the **targeted-repaint** path: `draw(_:)` clears `dirtyRect` and redraws the scene clipped to it, and a boundary row that is only partly cleared and partly repainted keeps a hairline until something forces a full repaint (which is why changing UI Size makes them vanish). Backing-aligning the invalidation rect outward in `setNeedsDisplay(_:)` was tried and **did not cure it** — necessary but not sufficient; the remaining unaligned step is unidentified. **Still open after the cPro2 pass (2026-09-01):** the *"clicking recolours a region"* report on cPro2 looked like a bigger instance of this and was not — it was a declared-empty group falling back to its parent's clip, fixed in the renderer, and it never went through the dirty-rect path. So B80 has one fewer candidate explanation and no new evidence; do not re-chase the region-scale probe. Suspect the hosted surfaces, which are real `NSView` subviews with their own invalidation. Affected sizes are exactly those fractional at 2x backing — 90/105/110/115/125/135/175 — and 50/100/150/200/250/300 are clean, confirmed by the reporter | 7 of 13 UI Sizes; every skin ([M25]) | M | Live-reported |
| B79 | `autowidthsource` naming a **bitmap** label sizes its group to nothing. `autoWidth` answers only for `<text>`, `<songticker>` and check boxes; every other type returns `nil`, so a group pointed at a `<layer image="…">` collapses to 0 wide and takes its children with it. Reported on winampmodern566 (2026-08-31): its titlebar menu entries do not open, because `<groupdef id="menugroup.file" autowidthsource="File.txt">` resolves to `(1, 18, **0**, 16)` while the label layer beside it is 31 wide, so `<Menu w="0" relatw="1">` inherits a zero box and there is nothing to click. **Not a regression** — those entries had no hit target before `<Menu>` existed either; B77 exposed the gap rather than causing it. cPro is unaffected because its `autowidthsource` names a `<text>`. Fix is to give an object with resolved artwork its bitmap's width, but it moves group sizing engine-wide and wants its own corpus sweep | 2 skins / 24 declarations ([M24]) | S | Live-reported |
| B78 | **A negative `sysregion` suppresses real frame artwork, so the content overhangs the frame.** Reported on Ebonite_2_1 (2026-08-31) as "the window contents are bigger than the frame"; reproduced and root-caused 2026-08-31. `WasabiRenderer.isRegionOnly` drops any layer whose `sysregion` is negative, which deletes the four border layers of Ebonite's standard frame and leaves only its `inner` layer — 19px narrower than the client area drawn over it. The rule is right for the silhouette masks it was written for (Ujola Cat) and wrong for real artwork | 308 layers / **37 of 53 skins** currently suppressed ([M26]) | M | Live-reported |

### Awaiting manual QA

| Id | Item | Remaining check |
|---|---|---|
| B41 | `getMonitorWidth` / `getMonitorHeight` | Move Big Bento Modern between displays and verify its side-playlist sizing follows the display containing the player |
| B85 | The Widgets Manager's three place buttons | On a cPro skin open the drawer menu -> *Widgets Manager*, then click **show in main / drawer / side** on a row. Each sends `show_widget` through `widgetsManager.maki` to CproTabs / CentroSUI / the drawer, and all three legs should now work given B77's `wndtype` buckets and `<CustomObject>`; none has been exercised. **Uninstall and support are expected to stay inert** — `ClassicProFile.openFile` refuses executables and `System.navigateUrl` is out of scope by sandbox policy, so a dead button there is correct, not a finding |
| B66 | The Wasabi standard form widgets | The **drawing** half is verified in the render sweep across the corpus. Radios and check boxes are **done** — a click on either was found dead in the app 2026-08-29 (B14's QA, on Shield_Amp and Styx: an unbound box drew from its `cfgattrib` provider's "no" instead of its own `activated`) and both are now confirmed live, including set exclusivity. What is left is the **drop-down's persistence**: on Styx's Config open the `Position` drop-down, pick an entry, then reopen the window and confirm the pick survived — which is the skin's own `onTextChanged` persisting it |

## Reproducible reach commands

All commands use the directories extracted with `7zz` from
`~/Library/Application Support/NullPlayer/WinampModernSkins/` (excluding
`ClassicProEngine`). Set `corpus=/path/to/the/extracted/root`.

**The corpus is 70 archives as of 2026-08-31**, up from the 36 and then 53 earlier rows were measured
against — so an older `[M##]` denominator is not comparable to a newer one, and rows say which they
used. **Four of the 70 are byte-identical re-adds** of skins already installed, under their
DeviantArt filenames — `pure_inspired_for_winamp_by_marisa85_d35ix2r` = `Pure Inspired`,
`k_jr_winamp_skin_by_marisa85_d329ymw` = `K-jr`, and the two `dewytears_v2_5_by_dewytear_d2yn025_*`
= `DewyTears_{Pink,Black}GlassV2.5` (SHA-256 verified). They should be deleted; until they are,
**exclude them from any per-skin count** or one skin is reported twice.

**A command lives here only while the item that cites it is open.** Closing an item moves its
command into that item's archive entry, in the same change — otherwise the entry is left behind
citing nothing, which is how five of these went stale before being pruned 2026-08-30 (M3, M7, M8,
M20, M21 — now recorded under BB10, B41, BB5, B66 and B67 respectively). Every `[M##]` below must
resolve to a live citation above.

- <a id="m4"></a>**M4:** source audit recorded in the item; `setTarget*` calls exercise the already implemented object tween machine and must not be counted as demand for animated layout/tab transitions.
- <a id="m25"></a>**M25:** device scale is UI Size x the display's backing factor, so on a 2x panel the fractional stops are 90, 105, 110, 115, 125, 135 and 175 % — 7 of the 13 `UIScaleLevel` cases — and 50, 100, 150, 200, 250, 300 are integral. To check a *full* draw at either, `WINAMP_MODERN_RENDER_SCALE=<factor> WINAMP_MODERN_RENDER_DUMP=/tmp/s WINAMP_MODERN_WAL=<skin> swift test --filter WinampModernRenderDumpTests` renders the scene the way the view does; count rows whose alpha is strictly between transparent and opaque to find partial-coverage seams objectively rather than by eye. The harness has no partial-repaint mode, which is why it cannot reproduce the live defect — adding one is most of this task.
- <a id="m24"></a>**M24:** for each `.wal` (and the ClassicPro engine tree), collect `id=` from every `<layer>` and every `<text>`, then keep the `autowidthsource="…"` values that name a layer and not a text. Measured 2026-08-31: **The_Nokia_5220_XpressMusic 12 of 12** and **winampmodern566 12 of 18**; no other skin in the 53 points one at a bitmap. Both are Menu-bar skins, which is why the symptom shows up there first.
- <a id="m26"></a>**M26:** over the 53 extracted skin trees, count `<layer>` / `<animatedlayer>` declarations whose `sysregion` parses as a negative integer — these are exactly the ones `WasabiRenderer.isRegionOnly` refuses to paint. Measured 2026-08-31: **308 layers across 37 of the 53 skins**, led by winampmodern566 (26), Styx (23), Nullsoft.Winamp.2000.SP4.Lite (20), S7Reflex (18), Anaheim_Player_01 (16) and Ebonite_2_1 (16). The recurring four-layer `top`/`left`/`right`/`bottom` shape — the standard frame's own border — accounts for most of the ~25 skins that declare exactly 4. To see what a suppressed layer would have painted, read its `image=` bitmap's alpha profile: Ebonite's `gfx/standardframe/window/background.png` is 10x10 solid black at a uniform **alpha 179** (a fill), while Ujola Cat's `window-regions.png` is a magenta-and-white mask. That difference is the candidate discriminator and is not yet a rule.

  M23, the playlist-holder size sweep this row used to cite, is **deleted rather than archived**: it measured the wrong thing. Its finding is kept here because it is still true and still not the bug — the holder Ebonite allots is 227x172, the smallest in the corpus is micro at 140x69, and 27 of the 44 skins that expose one are under 260x180. See B78 for why holder size is innocent.
- <a id="m22"></a>**M22:** `rg -i -o '<[[:space:]]*Wasabi:Button[^>]*>' "$corpus" --glob '*.xml'`, then keep the matches with neither `action=` nor `text=` — the ones only a script drives.
- <a id="m30"></a>**M30:** per skin tree, case-fold the `id=` of every `<container>` and keep the duplicates. Measured 2026-08-31: **Ebonite_2_1** (`sc.alphaframe`) and **WMP11-BlueVU** (`meter`). That grep finds only the literal-duplicate half; the **double-include** half does not show up in it and must be found from the render dump, where one declaration prints twice in `RENDER-DUMP containers` — **jvc.tape.v0.5**, whose `xml/pledit.xml` is included from both `skin.xml:17` and `xml/amp.xml:9`. Three skins between the two shapes. **Corrected 2026-09-01 while closing B96:** the live reach is **2**. Ebonite's second `sc.alphaframe` is in `wasabi/standardframe/Copy of standardframe.xml`, an authoring leftover no `<include>` names, so it never reaches the graph — a reminder that this grep reads the *tree*, not the include closure.

For grep-derived rows, “skins” is the number of distinct first path components and “uses” is the
number of matched declarations or MAKI program symbols. A compiled MAKI method name is a program
symbol, not necessarily a call-site count; rows say so where that distinction matters.

## Item detail

The batch measurement of the **12 skins added 2026-08-30 and 2026-08-31** — profiled 2026-08-31 with
`WinampModernRenderDumpTests` under `RENDER_BITMAPS` + `RENDER_SCRIPTS=bindings`, every layout PNG
read — is now fully closed out. Grades from that batch: `cpro2_dark_aluminum` and `canum` did not
load (**F**, fixed 2026-09-01 by B93 and B92; `cpro2_dark_aluminum` has since been measured and
driven end to end — it is the corpus's only ClassicPro engine-`two` skin and needed five further
fixes, see [skins/cpro2-dark-aluminum.md](skills/winamp-modern-skin-guide/skins/cpro2-dark-aluminum.md)),
`Winamp 3.0 Default` loaded blank (**F**, fixed
2026-09-01 — it was a standard frame whose content group never entered the graph), `Darjah 1` **D**,
`cpro_interface` / `nullsoft_media_player_10` / `jvc.tape` **C**, and `WMP11-BlueVU` / `MMD3-4-5` /
`EPS_High-End` / `TRON Legacy` / `Firefox` **B**. **No live pass was run** on that batch, so none of
it has been driven under the mouse, and the harness's absence of a component host means an empty
*pane* is not evidence — only an empty *window* is.

---

### BB14

- [ ] **BB14. Animated layout and tab transitions, and easing beyond linear.** Our layout and tab
      switches are instant visibility swaps. Sprite `<AnimatedLayer>`, the
      `setTarget*`/`setTargetSpeed`/`gotoTarget`/`cancelTarget`/`onTargetReached` tween machine and
      timers are all implemented and are what Bento's own animations are built from, so **nothing in
      this family depends on this**. Filed so the absence is recorded rather than rediscovered.

---

### BB34

- [ ] **BB34. An embedded `{0000000A}` visualization pane's engine never starts.** With Big Bento
      Modern's Multi Content View mini pane ticked, the pane is laid out correctly and draws
      **black**: `WINAMP-MODERN-VIS: resume … visible=0 … rendering=0` is the last line, and nothing
      asks the surface again. That is the shape of *The engine will not start in a window nobody has
      shown yet* ([reference/components/visualization.md](skills/winamp-modern-skin-guide/reference/components/visualization.md)),
      which `resumeRendering()` was added to fix — but for a holder in the **main** window, where
      `WinampModernMainView.setSceneVisible(true)` was supposed to cover it. Found while landing BB9's
      side-by-side layout, 2026-08-29; the layout itself is correct and confirmed live.
      **Re-measure before doing any work on it (2026-08-30).** Two things the entry predates: BB35 was
      a second, independent way this same pane went black — an election flip leaving its surface
      detached and stopped — and its fix gives a detached surface a route back, so BB34's symptom may
      already be gone. And the reach note here is wrong: B23a measured **6** corpus skins embedding a
      holder in the player, not one, so "specific to a pane embedded in the player" is not the narrow
      case it reads as.

---

### B41

The implementation and its automated coverage shipped; that record is in
[the archive](docs/winamp-modern/backlog-archive.md). Only the manual check below keeps B41 open.

- [ ] **B41 manual QA.** When a second display is available, load Big Bento Modern, move the player
      to that display, open the right-side playlist with its bottom-right up-arrow, and toggle
      **Enlarge Playlist**. Confirm the side column opens and sizes against the display containing
      the player rather than the primary display. Repeat after moving the player back to the primary
      display. If either display is Retina, confirm there is no 2× oversizing. Archive B41 only after
      this check is accepted.

---

**Not open, and not a defect:**

- The Windows 10 edition's zero-byte `window/no_alb_art_shade.png` is the skin's own bug. It degrades
  to a warning and that one placeholder draws nothing, which is the correct outcome.
- The wide-window pane split (B38.5). `from="left"` anchors the divider to the left edge and the right
  pane absorbs the extra width — see B38 below.

---

### B71

- [ ] **B71. A layout's own script loads before the standard frame beside it has a client area, so
      every name it resolves is null.** `WinampModernScriptRuntime.start()` dispatches `onScriptLoaded`
      to **every** object-owned program, and only then delivers XUI params. A
      `<Wasabi:StandardFrame:*>` has no client area until its `content` param arrives — that is what
      `onSetXuiParam` builds — so a `<script>` declared *after* the frame in the same layout runs
      against an empty frame, and every `findObject` in its `onScriptLoaded` answers null.
      **Measured on Defix's detached visualizer (VISCON), 2026-08-29**, the window B16 made visible.
      `visrb2.maki` resolves eleven names — `vis.DTB` (Reattach), `vis.random`, `VIS_Menu`, `VIS_Cfg`,
      `VISCON.component.control`, `VISCON.component.vis`, … — and `RENDER_SCRIPTS=bindings` prints
      `bind onleftbuttonup v50 -> null` for each. The trace order is
      `WASABI_STANDARDFRAME@398` (the frame's `onScriptLoaded`) → `SUI.xml@270` (visrb2's) →
      `WASABI_STANDARDFRAME@989` (`onSetXuiParam`, which instantiates the content) → the content's own
      scripts. Only the last group finds anything, which is why `syncbutton.maki` — declared *inside*
      the instantiated group — binds correctly while the layout's script does not.
      **The fix is a reordering of script startup for every skin, and it was tried and reverted once**
      (2026-08-29): delivering each owner's params immediately after that owner's own `onScriptLoaded`,
      in document order, does make the bindings live — and then `visrb2`'s own logic starts running,
      which hides the control bar at load and re-shows it from a 300 ms timer gated on
      `layout.isActive()`, plus an `onResize` that re-lays-out the bar. The observed result in the app
      was Reattach still dead **and** the Options button gone. So this is two pieces of work: the
      ordering change (which needs the 36-skin render sweep behind it, not a live poke at one window),
      then the auto-hide/relayout behaviour, which has no measurement yet.
      **Do not treat "Reattach does nothing" as the whole item** — the *other* buttons on that bar were
      dead for an unrelated reason (B70, closed), and fixing that one made three of them work without moving
      this at all.

---

### B18

- [ ] **B18. The classic UI's minimize mask.** `miniaturizeAllManagedWindows` calls `miniaturize(nil)`
      on windows whose masks lack `.miniaturizable`, which is the bug modern's minimize had. Parity
      item, outside the `.wal` subsystem

---

-
---

### B106

- [x] Memoize the string measurement in `WasabiTextMetrics.measuredWidth(of:font:)`, keyed on
      `(text, fontName, pointSize)` and shared by `width(of:text:)` and `surfaceTextWidth`.

**Deliberately not done: the drawing half.** `drawText` is ~200 lines in which nearly every branch
documents a specific skin defect it exists to fix (B87's clip rule, the `offsetx` sliver, cPro2's
4px tuck, the clock cells). Converting it to cached CoreText lines is the real remaining win and is
exactly the change that quietly breaks one of those cases - it wants the corpus render sweep as a
safety net first. `drawText`'s own `measured` call is also left alone: it passes the full attribute
dictionary (font + colour + paragraph), so routing it through a font-only cache is only safe if
paragraph style cannot affect a single-line width, which is believed but not established.

**The result that matters more than the table, measured 2026-09-01.** Main-thread *busy* fraction
across the three runs on identical state:

| | busy |
|---|---:|
| before B104 | 95.3% |
| after B104 | 93.8% |
| after B105 + B106 | 91.1% |

**The main thread is still saturated.** Per-frame work fell a long way - the named functions dropped
by 5-20x - but the animation and visualization clocks simply take the freed capacity and run more
frames, so the busy fraction barely moves. Chasing individual leaf costs has reached diminishing
returns: what is left is dominated by `draw` (41.4%, mostly text drawing and image compositing),
`refreshLayerFXMeshes`, and the scene walk.

**Item 4 is done (2026-09-01).** `frame` joined `alpha` in `isSceneNeutral`. It is evidenced rather
than predicted:
`append` (13.4%) + `sceneNodes` (12.4%) are rebuilding a scene that mostly did not change, because
`sceneGeneration` still moves every frame from cPro's `beatvis` `<animatedlayer>`s writing `frame`.
Verified when B103 was investigated: `append` never reads `frame`, and the sprite is picked at draw
time by `animatedFrameImage` -> `WasabiAnimation.state` on the live object, downstream of the scene
cache - so exempting it cannot freeze the animation. Measured effect in the debug build: `append`
13.4% -> 3.0%, `layoutNodes` 8.6% -> 2.1%, `layout()` 10.5% -> 3.8%.

**It did not improve the frame rate, and the reason matters more than the change.** With the
exemption in, the debug build's visualization clock still stalled at the same cadence: 8.6 -> 8.1
late ticks/s, median gap 47ms -> 49ms against a 33ms target. The freed capacity was absorbed rather
than turned into frames.

## The debug build was the constraint (2026-09-01)

Main-thread **busy** fraction, cPro Bento with the drawer visualization up and audio playing:

| build | busy | idle |
|---|---:|---:|
| debug, before B103 | 98.6% | 1.4% |
| debug, after B103-B106 | 94.4% | 5.6% |
| debug, + `frame` exempt | 96.2% | 3.8% |
| **release, all of it** | **60.7%** | **39.3%** |

**Profile the build the user runs before optimizing past the algorithmic fixes.** Everything after
B106 - the 46ms frames, the 21.7 fps, "still saturated after freeing 23%" - was a debug-build
artifact. B103-B106 were worth doing at any optimization level because they are *algorithmic* (a
311-entry dictionary rebuilt per call, a `CharacterSet` per character, a CoreText pass to re-answer
a constant); ordinary code executed often is the category where debug-vs-release decides whether
there is a problem at all.

**`WINAMP_MODERN_VIS_STALL` is `#if DEBUG`.** It cannot fire in a release build, so a release run
reports zero stalls whether or not any occurred. Read a silent instrument as "not running" until
proven otherwise. The cross-build metric that does work is the busy fraction from `sample`: count
leaf frames sitting in `mach_msg2_trap` / `semaphore_wait` / `__psynch_cvwait` as idle.

**No pre-fix release baseline was captured**, so how much of that 39% headroom these changes bought
is unmeasured. The release figure above is *with* every fix including the `frame` exemption.

---

### B105

- [x] Hoist the `CharacterSet` to a `static let`; return an already-safe component unchanged.
      Measured at **2.5%** before the fix; not yet re-measured after.

**Remaining, measured but not fixed** (cPro Bento, drawer visualization up, playing, after B103-B105):

| candidate | share | note |
|---|---:|---|
| ~~`drawText`~~ | ~~8.8%~~ | **Done 2026-09-02.** Text draws from cached CoreText lines (`WasabiTextMetrics.line(for:font:)`), and four tables that were rebuilt per string per frame are memos. Headless, `WINAMP_MODERN_RENDER_TIME` ×2 scale: cPro Bento `main/normal` **5.51 -> 5.06-5.11 ms/frame (-8%)**, its `notifier` -41%, `widgets.manager` -14%; Big Bento Modern `main/normal` 30.47 -> 30.2 (-0.7%, at the edge of noise - that layout is not spending its 30 ms on text). Corpus sweep over all 69 archives: invariants identical, 585/590 PNGs byte-identical and the other 5 antialiasing at <=5/255. See `reference/performance.md` -> *The drawing half of `drawText`* |
| float16 image compositing | ~7% | `ripc_DrawImage` -> `RGBAf16_image` -> `RGBAf16_sample_RGBAf_inner` plus `vCGCompositePixelShape_ARGB16F_vec`: every blit runs through the **16-bit float** pipeline. Nothing in the app sets `contentsFormat`, `colorSpace` or a depth limit, so this is the system default on a wide-gamut display. Skin art is 8-bit PNG, so `RGBA8Uint` would be lossless *for the artwork* - but the renderer also synthesizes gradients (`$gradient`), which could band. **A visual decision, not a free win**: measure and look at it before adopting |
| `refreshLayerFXMeshes` | 20.0% | The MAKI interpreter evaluating cPro's warp mesh per tick. Genuine work; bounded by B103's dispatch fixes. Would need a cheaper interpreter or a coarser mesh, both of which change behaviour |

---

### B104

- [x] **1. `normalize` builds a `CharacterSet` per character.** `WinampModernComponents.swift:112`.
      Hoist the hex test out of the closure — better, drop `CharacterSet` and test the UTF-8 byte
      directly, which is what "is this an ASCII hex digit" actually is. Measured at **14.6%** of the main thread, ~13.7% of it building and freeing `CharacterSet`s.
- [x] **2. `surfaceID(of:)` is recomputed per object, per scan.** Nothing memoizes it, so every walk
      re-derives the same answer for every object. Cache it on the object, dropped by `setAttribute`
      for the keys it reads.
- [x] **3. `refreshWaveformDemand` walks `allObjectsUnordered` twice.** `WasabiRenderer.swift:3559`
      and `:3577` each want one boolean. One pass answers both.
- [ ] **4. Re-measure, then decide about `isSceneNeutral`.** The memo on `sceneGeneration`
      (`WasabiRenderer.swift:3545`) misses every frame because cPro's `beatvis` `<animatedlayer>`s
      write `frame` on every tick (B103's mutation trace). With 1-3 done the miss may stop mattering.
      **Do not add `frame` to the exemption set on a prediction** — measure first.

**Order matters here.** 1 and 3 are exact and carry no invalidation risk; 2 introduces a cache and
should be judged on measurement after 1 and 3, not before.

**Result, measured 2026-09-01** — three samples on identical state (cPro Bento, drawer visualization
up, audio playing), true inclusive share of the main thread:

| symbol | before | after 1+3 | after 1+2+3 |
|---|---:|---:|---:|
| `refreshWaveformDemand` | 32.8% | 18.5% | **1.7%** |
| `surfaceID(of:)` | 32.0% | 17.8% | **0.7%** |
| `componentKind(of:)` | 31.9% | 17.7% | **0.7%** |
| `normalize` | 14.6% | 2.6% | **0.0%** |
| `WinampModernMainView.draw` | 55.1% | 46.1% | **36.2%** |

Item 2 earned its place: 1+3 alone left `componentKind` at 17.7%.

**Measurement pitfall this exposed — `append` is recursive.** Aggregating a `sample` tree by summing
every frame that carries a symbol counts a recursive function once per level, so `append` read as
**73%** of the main thread when its true inclusive share is **12.2%**, and `normalize` read as 28.3%
against a true 14.6%. Inclusive share has to count only the **outermost** occurrence of a symbol on
each stack. Two figures were reported from the inflated form before this was caught. Anything derived
from a `sample` tree by substring matching is suspect for the same reason: `refreshWaveformDemand`
also appears as `closure #4 in …` and `partial apply for closure #4 in …` on the same stack.

--

### B103

Four rebuilt-per-call tables on the main thread. Ranked by measured share; each is independent, so
they land one at a time.

- [x] **1. `signature(for:classGUID:)` builds a 311-entry dictionary literal per call.**
      `WinampModernScriptRuntime.swift:2283` declares `let signatures: [String: MakiMethodSignature] = [...]`
      as a **local**, so every method invocation the interpreter makes allocates and hashes 311
      entries. Above it, `classGUID.map(Self.canonicalGUID)` is evaluated up to **five separate
      times** in the same call. Hoist the table to a `static let` and compute the canonical GUID
      once into a local. Measured at **10.4%** of the main thread.
- [x] **2. `MakiClassGUID.canonical` is O(n^2) with ~20 allocations, called 5x per dispatch.**
      `MakiBytecode.swift:58` walks a 32-character string with `String.index(_:offsetBy:)` in a
      `stride`, building 16 substrings, reversing them in groups of four and joining. Rewrite over
      `utf8` bytes and memoize on the raw string. Measured at **10.4%** (`canonical` +
      `canonicalGUID`); item 1 removes four of the five calls, this removes the cost of the fifth.
      **Done without the memo:** one `Array(raw)` plus one `String` makes the function O(n) with two
      allocations instead of O(n²) with ~20, and a cache keyed on the raw string would spend a
      32-character hash to save what is now a 32-character loop. Result is character-identical.
- [x] **3. The resolved `NSFont` is not cached; only the raw `CGFont` is.**
      `WasabiTextMetrics.font(identifier:size:traits:)` (`WasabiTextMetrics.swift:33`) caches
      `CGFont` by path, so `CTFontCreateWithGraphicsFont`, `applying(traits:)` (an
      `NSFontManager.convert` round trip) and the whole `installedFont` branch - `NSFontManager`
      `font(withFamily:)` -> `CTFontDescriptorCreateMatchingFontDescriptorsWithOptions` - run **per
      string, per frame**. Add a cache keyed on `(identifier, size, traits)`, which is what the
      signature already offers, and clear it beside `fonts` in `teardown`. Measured at **2.6%** on
      cPro Bento and **5.7%** on `cPro_T2T-by-MAC`, whose text is heavier.
- [x] **4. `WalResourceRegistry.resolved(identifier:in:)` folds with ICU per lookup.**
      `WasabiSkinInitializer.swift:125` calls `Self.fold` - `String.folding(options:locale:)`, a full
      Unicode normalization - on every id, and allocates a fresh `Set<String>` for the alias
      cycle guard, per resource id, per frame. Memoize the fold. Measured at **3.4%**.

**Constraints.** Items 1, 2 and 4 are shared `.wal` code and item 3 is `WinampModern/` only, so
Classic and Original are untouched by construction - no mode gate is needed because no shared *app*
code is involved. None of the four changes what is drawn, so the render sweep must come back
byte-identical.

**Corrected figures (2026-09-01).** The per-symbol drops first reported for these four were derived
by substring-matching the `sample` tree, which counts a symbol once per frame that carries it and so
double-counts closures and recursion (see B104's measurement-pitfall note). True inclusive share,
outermost occurrence only — and note the two runs are **not** the same app state (idle vs. playing),
so read each row as an order-of-magnitude drop, not a controlled A/B:

| symbol | before (idle) | after (playing) |
|---|---:|---:|
| `signature(for:classGUID:)` | 10.4% | 0.4% |
| `MakiClassGUID.canonical` | 5.1% | 0.3% |
| `WasabiTextMetrics.font` | 2.6% | 1.2% |
| `WalResourceRegistry.resolved` | 3.4% | 0.6% |

**Caveat on the numbers.** All of the above was measured on a **debug** build, so the absolute
percentages are inflated. The two largest are algorithmic rather than optimizer-sensitive, so the
shape holds in release, but the win should be re-measured with `sample` on a release build before
the figures are written into `reference/performance.md`.

**Not measured yet:** the profile above is **idle**. Playing adds B51's vis clock on top of it.


### B58

- [ ] **B58. `WinampModernVisualizationSurfaceView` swallows single clicks.** Found while fixing B57
      (2026-08-28). Its `mouseDown` handles `clickCount >= 2` and nothing else, so a single press on
      the visualization inside the skin's *own* player window does nothing — including not dragging
      the window. Same defect class as B57, different mechanism: this surface has no
      `hostedContext`, so the drag would have to route through the parent `WinampModernMainView`'s
      skin hit test, and what `shouldDragWindow` answers for the holder underneath it is the open
      question. Do not copy `WinampModernHostedWindowDrag` in without checking that.

---

### B65

- [ ] **B65. A division by zero abandons the whole handler, where Winamp carries on.** Found
      2026-08-28 while measuring Shield_Amp for B64. Its songticker never initialises: the
      third-party `OneDirectionText` widget reads an attribute (`{9149C445-…};Text Ticker Speed`)
      that **no script in that archive registers** — the widget expects a different host skin to
      create it — so `getData()` answers `""`, which is `!= "0"`, the guard passes, and
      `Delay = 20/stringToFloat("")` divides by zero. `MakiBytecode.swift` opcode 67 raises a typed
      `invalidScript` there, which abandons the enclosing `onScriptLoaded`.
      **Winamp does not**: MAKI's `/` is a float divide, so it yields infinity and the handler runs
      on. Fail-closed is right for a *missing* method (we cannot unwind the stack without an arity);
      it is wrong for arithmetic, where the IEEE answer exists and the skin's own later guards may
      well cope with it. Same failure class as Phase 33's — one fault takes a whole startup handler
      and every feature behind it reads as missing.
      **Before changing it:** confirm what Winamp actually produces for the integer case as well as
      the float one (opcode 67 sees both), and measure the corpus — a `RENDER_SCRIPTS=1` sweep
      counting `failed=…division by zero` is the reach number this row is missing. Do not relax the
      *diagnostic*; a warning should still be recorded, per the "degrade gracefully with a warning"
      rule in the skill.

### B60

- [ ] **B60. The hosted library and video surfaces still have no body drag.** Left out of B57
      deliberately (2026-08-28). `WinampModernLibrarySurfaceView` is a table in a scroll view — rows
      and scrollers legitimately claim their presses, but the blank area below the last row could be
      a handle and currently is not. `WinampModernVideoSurfaceView` overrides no `mouseDown` at all
      and the picture is a child window parked on the holder box, so whether a press there reaches
      anything is unverified — measure it in the running app rather than reasoning it out.
      `WinampModernBrowserSurfaceView` is out of scope: it is a WKWebView and the page owns the
      mouse.
      (The Itemskin observation that used to sit here — a standard frame with `surfaces=0` for every
      hosted id — was a different defect and is closed as B69: its frames are a *second* container per
      window, so the hosted probe was looking at the content half of a pair.)

### B78

- [ ] **B78. A negative `sysregion` suppresses real frame artwork, so the window's content overhangs
      the frame.** Reported on Ebonite_2_1 (2026-08-31) as "the window contents are bigger than the
      frame". **Reproduced live and root-caused the same day** — the two causes the entry originally
      proposed are both wrong and are recorded below so they are not re-derived.

      **What is on screen.** Ebonite's Playlist window, moved clear of every other window and
      measured per row against the renderer's own 250x250 output:

      ```
      y=  0..16   fully transparent
      y= 17..29   opaque x = 11..213     <- 203 wide
      y= 30..219  opaque x = 10..232     <- 223 wide
      y=220..226  opaque x = 11..213     <- 203 wide
      y=227..249  fully transparent
      ```

      The content is 223px wide and overhangs the only frame artwork that draws by **19px to the
      right and 9px below**. There is no border at all: the outer 10px left, 17px right, 17px top and
      23px bottom of the window are fully transparent.

      **The cause.** Ebonite's `wasabi.frame.dummy` groupdef
      (`wasabi/standardframe/standardframe.xml:134`) draws its frame as five layers — `top`, `left`,
      `right`, `bottom` over `wasabi.frame.dummybg` with `sysregion="-2"`, and `inner` over
      `wasabi.frame.inner` with `sysregion="1"`. `WasabiRenderer.isRegionOnly` (`:2398`) answers true
      for any negative `sysregion` and such a layer is never painted, so the four border layers are
      dropped and only `inner` survives — `x=11 y=17 w=203 h=210`, which is the measured opaque box
      exactly. The frame's script then instantiates the content group at `(10, 30, 223, 190)` on top
      of it, and that is the overhang.

      **The suppressed bitmap is not a mask.** `gfx/standardframe/window/background.png` is 10x10
      solid black at a uniform **alpha 179** — a translucent border fill. The rule exists for a real
      defect (Ujola Cat's `window-regions.png` silhouettes painting magenta and white slabs over the
      title strips) but keys on the sign alone, which is too coarse.

      **Two corrections to how this was filed.** The `.playlist` holder has **no NSView surface**:
      `layoutHostedSubviews` (`WinampModernMainView.swift:1058`) positions only `.library`,
      `.visualization`, `.video`, `.hostWindow` and browser surfaces, and the embedded playlist is
      drawn by `WasabiRenderer.drawPlaylistComponent` (`:4744`), which clips to the holder before
      drawing a row — so the `surface.view.frame` sentence described a path this surface never takes.
      And the row metrics are innocent: `auto` resolves to **100%** here (`text=11.0px row=12.0px`,
      14 rows in 172px), because `WinampModernTextScale.autoDivisor` is 48 and anything under a 528px
      window sits on the 11px floor. Holder size is not the reach number; [M26] is.

      **Also ruled out, do not re-try.** Container-level `default_w`/`default_h`/`minimum_w`/
      `minimum_h` are read nowhere — `WinampModernContainerTopology.analyze` takes sizes only from the
      layout (`:86-94`) while reading the container's `default_x`/`default_y` (`:244`) — and 37 such
      declarations across 20 skins are ignored. **Honouring them would be a regression.** Ebonite
      disproves them itself: its `<container id="equalizer" default_w="346" default_h="192">` sits
      over a layout locked at `w/h/minimum/maximum = 147x106`, and its `<container id="main"
      minimum_h="300" maximum_h="300">` over layouts 40 to 297 tall. The numbers are cargo-culted from
      Winamp Modern and Winamp evidently ignores them too.

      **Before changing the rule:** it is shared, and 37 of 53 skins have layers behind it ([M26]), so
      this wants the corpus render sweep behind it rather than a live poke at one window. Ujola Cat is
      the named regression case — a fix that repaints its five masks puts magenta and white slabs back
      over its title strips. The candidate discriminator is the bitmap's alpha profile (uniform
      translucent fill vs. colour-keyed mask); it is a candidate, not yet a rule.

---

<details>
<summary>B52's task list, kept for the measurements it records</summary>

---

### B74

- [ ] **B74. T800's five memory slots all write one storage key.** Fixed and verified 2026-08-29:
      the slots were unreachable (a script-bound `<Wasabi:Button>` was not interactive) and
      `System.playFile` was unimplemented; both are closed and the record/recall cycle works. What
      remains is that **Mem1…Mem5 are one slot**. `quicksongpick.maki` keys each slot on
      `getParent().getID()`, and all five buttons are declared directly in `groupdef
      player.main.cms`, so every one of them reads and writes
      `winampModern.config.T800.T800.player_main_cms` — recording on Mem2 overwrites Mem1. The
      skin's own confirmation proves the intent: it prints **`Song recorded: player.main.cms`**
      where it should print `Song recorded: Mem3`.

      **Likely cause, unconfirmed.** `wasabi.button` is registered as an identifier-only shell
      (`WasabiSkinInitializer.swift`), so `<Wasabi:Button id="Mem3">` is one flat object whose
      parent is the enclosing groupdef. In Wasabi the tag is a standard-library **group**, and if
      the script's receiver is a control *inside* it then `getParent()` is `Mem3` and the key is
      per-slot. Making the tag a real group is the fix that follows from that reading, but it
      touches all 32 `<Wasabi:Button>` declarations in the corpus and the B14/B66 form widgets that
      are verified against the flat shape — so confirm the object model before changing it.

      Two usability notes that are **not** defects and were mistaken for one during QA: recording
      needs a hold of **~2 s** (measured: 300/900/1500 ms record nothing, 2500 ms records), and the
      "Song recorded" confirmation is written to `text#songticker.text`, which lives **inside the
      jaw** — with the mouth shut a successful record looks like nothing happened.

---

### B75

- [ ] **B75. A skin that includes the same script twice runs every handler twice.** T800 declares
      `<script file="scripts/quicksongpick.maki"/>` in **both** `skin.xml:27` and
      `xml/player-normal.xml:302`. Two programs are parsed, both bind the same five buttons, and
      every press runs both — so one click on a memory slot calls `System.playFile` twice and
      enqueues the track twice (live: `playTrack: index 16` immediately followed by `index 17`).
      Both bodies are byte-identical (`body=88323` in `RENDER_SCRIPTS=bindings`).

      The dispatcher already drops a handler whose **body is a byte-for-byte repeat** of an earlier
      one, but only *within one program*; two programs from the same source are a different case.
      Winamp probably doubles this too, so this may be the skin's own bug rather than ours — decide
      that before adding a cross-program rule. Note the counter-example already recorded in
      `MakiProgram`: Big Bento's `mcvcore` declares `System.onScriptLoaded` twice with **different**
      bodies on purpose, and a rule that keeps only one broke it.

---

## Pending live verification

These are verification state, not implementation priorities.

| Id | Verification | Reach | Effort | Tier |
|---|---|---:|:---:|---|
| B56a | Window tiling: classic-fallback playlist, Classic regression pass, live UI-Size change | — · verification only | S | Verification |
| B24 | cPro-Bento library/playlist remount cycle | — · verification only | S | Verification |
| B26 | Lobe and Ebonite container behavior | — · verification only | S | Verification |
| B28 | Component frame sizing on Lobe and cPro-Bento | — · verification only | S | Verification |
| B30 | Lobe/Styx/mmd3 control geometry | — · verification only | S | Verification |
| B31 | Lobe playlist content | — · verification only | S | Verification |

### Verification detail

- [ ] **B56a.** B56 shipped and is verified on Defix and Anaheim. Three checks remain: a skin whose
      playlist is a **classic fallback** rather than skin-owned; a **Classic/Original regression pass**
      (the tiling is an early return gated on `uiMode.controllerFamily == .winampModern`, so this
      should be a formality — confirm it is); and the arrangement after a **live UI-Size change**,
      which resizes every window and is the one input the sweep does not re-run for. Expect that last
      one to need `arrangeWindows()` called again, the same way launch does.

- [ ] **B24 verify:** Live on cPro-Bento: Media Library → Playlist → Media Library → Playlist, and
      the Video tab
- [ ] **B26 verify on Lobe:** the `CT` button opens the window, the picker lists 43, Switch applies one
- Already verified: **B26 on BLAKK, 2026-08-25.** It opens on its first declared layout (`boombox`,
      436×160 — it has no `normal`), and the full cycle works from its own Switch Player Mode button:
      boombox 436×160 → `stick` 650×30 → `remote` 160×280 → boombox, each matching its declared size
      and rendering completely (the remote shows art, 965 KBPS/44 KHZ, time, spectrum, transport).
      The button is script-bound through `configure.maki`'s `bboxswitch.onLeftClick`, not an
      `action="SWITCH"`, so this also exercises `switchToLayout` from a MAKI handler.
- [ ] **B26 verify on Ebonite_2_1 — half done, 2026-08-25.** It **opens**: 197×297, its first
      declared layout `full` (it has no `normal` either). Its five other layouts
      (`compact`/`stick`/`mini`/`minivert`/`narrow`) were **not** exercised. They hang off
      `<SC:WindowModeButton>` at `full` (188,24,9,5) with `lclick="switchto:compact"` and a
      right-click menu of all five (`xml/player-full.xml:7`), each layout's own button chaining to
      the next. Note this skin's own colour defect is fixed but separate (see the Ebonite note in
      `skills/winamp-modern-skin-guide/skins.md`).
- [ ] **B28 verify:** Live on Lobe **and** on a tall skin (cPro-Bento), for the visualization and
      library windows, at 1× and 2×. Note Lobe cannot exercise the library half — its catalog reads
      `library=synthesized:nullplayer.library`, so the surface coordinator opens the skin's own
      synthesized window and never reaches `rightDockedSideFrame`. That half needs a skin whose
      catalog reads `library=classic(...)`
- [ ] **B30 verify on LOBE:** drag the dial and the volume strip
- [ ] **B30 verify on Styx** (volume) and **mmd3** (knobs unchanged — its group is at the origin)
- [ ] **B31 verify on Lobe:** the Pledit window shows playlist content

## Backlog hygiene check

Run this in CI or before committing backlog changes:

```bash
if grep -n '^- \[x\]' TASKS.md; then
  echo "closed item still in TASKS.md — archive it"
  exit 1
fi
if grep -n '^| B' TASKS.md | grep -vE '\|[^|]*([0-9]+[^|]*skins?|[0-9]+ variants|—)[^|]*\|'; then
  echo "open item missing Reach"
  exit 1
fi
```
