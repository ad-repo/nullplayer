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
| B110 | **A skin's window frame can be a *second window*, and `newDynamicContainer` only ever answers with the one instance.** Ebonite's standard frame opens `newDynamicContainer("sc.alphaframe")` in `wasabi/standardframe/standardframe.m` and keeps it on top of the client with `frame_layout.resize(comp_layout.getLeft(), comp_layout.getTop(), comp_layout.getWidth(), comp_layout.getHeight())` — the visible border (10 left / 17 right / 30 top / 30 bottom, plus RGB-tinted variants) is drawn by that overlay, not by the client window. So the client group is deliberately short: `w="-17" relatw="1" h="-20" relath="1"`, 233x230 of a 250x250 window. We answer `newDynamicContainer` with the already-instantiated container and materialize no window for it, so the margin stays empty — reported 2026-09-03 as "there is no right hand pad" | 4 skins measured ([M31]); Big Bento wants instancing for a different purpose | L | Live-reported |
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
- <a id="m31"></a>**M31:** over the 61-skin corpus, `strings` every `.maki` for `newDynamicContainer` and pair the hits with the `dynamic="1"` containers the tree declares. Measured 2026-09-03: **12 skins call it**, and **4 use it for the per-window frame-overlay idiom** — Ebonite_2_1 (`sc.alphaframe`), MoonLight and Itemskin (`cont.clear.pl` / `.ml` / `.dl` / `.vd`, one per hosted window kind), 4-drelictionreleasepic (`resizable_status` / `resizable_nostatus`). All four descend from the same leech-derived `standardframe`, and MoonLight and Itemskin also appear in B78's alpha sweep with the same short client group and 1x1-texture border strips. The other callers want instancing for their own windows rather than for chrome: Big Bento (`searchresults`, `Hsearchresults`, `browserpro`), jvc.tape, multipass, the two Love is War Miku variants, hatsune_miku_5 and winampmodern566.
- <a id="m22"></a>**M22:** `rg -i -o '<[[:space:]]*Wasabi:Button[^>]*>' "$corpus" --glob '*.xml'`, then keep the matches with neither `action=` nor `text=` — the ones only a script drives.

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

### B110

- [ ] **B110. A skin's window frame can be a second window, and `newDynamicContainer` only ever
      answers with the one instance.** Reported 2026-09-03 on Ebonite_2_1 while closing B78: *"there
      is no right hand pad"*. Root-caused the same day from the skin's own MAKI **source**, which it
      ships beside the compiled form.

      **What the skin does.** `wasabi/standardframe/standardframe.m`:

      ```c
      frame_cont   = newDynamicContainer("sc.alphaframe");
      frame_layout = frame_cont.getLayout("scdef");
      ...
      frame_layout.resize(comp_layout.getLeft(), comp_layout.getTop(),
                          comp_layout.getWidth(), comp_layout.getHeight());
      ```

      One overlay window per framed window, parked on the client's exact rect, carrying the border
      art — `window.topleft` / `top` / `topright` / `left` / `right` / `bottomleft` / `bottom` /
      `bottomright` at 10 left, 17 right, 30 top, 30 bottom, each with `.red` / `.green` / `.blue`
      variants the RGB config fades between, plus the resizer grips and the window title. The client
      window's own group is short by exactly that margin (`w="-17" relatw="1" h="-20" relath="1"` —
      233x230 inside a 250x250 window), because the overlay is what fills it.

      **What we do.** `System.newDynamicContainer(id)` answers with the **already-instantiated**
      container of that id (`compatibility/maki-surface.md`), and nothing materializes it as a
      window that tracks another window. `CGWindowListCopyWindowInfo` on the running app shows no
      such window, and the margin is simply empty — which is also what exposed the zero-area browser
      surface closed alongside B78.

      **Two halves, and the second is the harder one.**
      1. **Instancing.** A fresh instance per call, addressed by the object the script holds rather
         than by id. A skin that opens one overlay per window needs three or four live at once, and
         the current single instance would have them fighting over one container.
      2. **A window that tracks another window.** `syncFrame()` / `syncContent()` copy geometry both
         ways — the frame follows the client, and dragging the frame moves the client — plus
         `LAYOUT_PROPS` (alpha, linkwidth/linkheight, minimum/maximum, taskbar) copied across, and
         the skin's own resize handling. This is window management, so it is squarely under the
         Classic-safety rule: gate on `uiMode.controllerFamily == .winampModern` and change no shared
         placement path without saying so.

      **Reach: 4 skins ([M31])**, all from the same leech-derived standardframe — Ebonite,
      MoonLight, Itemskin, 4-drelictionreleasepic. Itemskin's frames were already noticed from the
      other side and closed as B69 ("its frames are a *second* container per window"), which is this
      same idiom seen through the hosted-surface probe.

      **Before starting:** write the plan to `~/.claude/plans/` and have it reviewed. Window geometry
      has no useful armchair form (B56), so the loop is the `testing` skill's measure-it-live one,
      with `WINAMP_MODERN_PLACE_TRACE=1`.

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

Run this before committing backlog changes:

```bash
scripts/validate_winamp_modern_backlog.sh TASKS.md
```

It checks two things: no closed (`- [x]`) item is still here rather than archived, and every open
item in a **ranking** table carries a Reach. The Reach check is scoped to the five-column ranking
tables — the three-column *Awaiting manual QA* table has no Reach column and is not asked for one —
and it tests that the cell is non-blank rather than that it looks numeric, since "every `.wal` skin"
is a true and common answer. The script had both faults until 2026-09-02 and, because `set -e` stops
at the closed-item check, the Reach half had never actually run.
