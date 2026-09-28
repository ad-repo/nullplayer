# Winamp 5.x Modern Skins (`.wal`) — ranked open backlog

This is the only live backlog for the Winamp Modern subsystem. A skin is a test case, not a
milestone: take measured capability work from the top down. Closed entries move to
[`docs/winamp-modern/backlog-archive.md`](docs/winamp-modern/backlog-archive.md) in the same change
that closes them. A row that is stale, a question rather than work, or self-described as not worth
doing moves to [`LOW_QUALITY_TASKS.md`](LOW_QUALITY_TASKS.md). This file holds tasks; how the engine
works belongs in `skills/winamp-modern-skin-guide/`.

## Ranking

Measured items are ordered by reach, with effort as an advisory tiebreaker. Reach is corpus demand,
not severity. Live-reported draw defects are kept in their own tier because a screenshot or runtime
observation is not comparable to a static declaration count.

Effort bands: **S** = one attribute/method/local draw fix; **M** = behavior spanning multiple files
without a seam change; **L** = a host seam, protocol change, or new fixture harness.

### Measured capability gaps

| Id | Item | Reach | Effort | Tier |
|---|---|---:|:---:|---|
| B99 | **`enumObject` / `getNumObjects` are unimplemented.** ClassicPro's InfoViewer (`xui/CentroSUI/_v2/InfoViewer/InfoViewer.xml`) walks its object list with them, and dispatch fails closed, so each call abandons the whole handler. Measured on cPro2 Dark Aluminum 2026-09-01: `enumObject` x12, `getNumObjects` x2 | 1 skin measured; the `_v2` SUI is shared by any engine-`two` skin | M | Measured |
| B18 | **Classic minimize-all ignores the window's mask.** `miniaturizeAllManagedWindows` (`App/WindowManager.swift:8653`) calls `miniaturize(nil)` on windows whose style mask lacks `.miniaturizable` — the bug modern's minimize had. Classic parity item, outside the `.wal` subsystem | — · engine integration, outside the corpus | S | Measured |

### Live-reported draw defects

| Id | Item | Reach | Effort | Tier |
|---|---|---:|:---:|---|
| B123 | **`System.getMousePos*` answers in window space; Winamp answers in screen space.** cPro2's `layout.m` opens its Aero-snap preview on `getMousePosX() < 1`; the B101 suppression hides that one symptom. **Constraint:** `WinampModernMainView.currentMousePositionInSkinPixels` is window-space on purpose — Lobe, Rika and mmd3's knobs were fixed by it (`reference/scripting.md`) — so re-measure each of those live before a screen-space reading lands | 1 skin measured; every skin whose script reads the cursor | M | Live-reported |
| B119 | **WMP11-BlueVU spends ~75% of the main thread where a normal skin spends ~50%**, painting two warped FX layers every frame. The CPU resample half is fixed; the Core Graphics paint (~26% against a control's ~5%) is open. Closing this also closes B117(a), the skin's ~7 fps marquee. See [detail](#b119) | 2 skins measured; every skin with an animating `<layer>` FX mesh | M | Live-reported |
| B147 | **The library window follows the main window's height in a `.wal` session.** `toggleHideTitleBars` (`App/WindowManager.swift:511`) resizes the side-docked library and projectM windows by the main window's height delta — Original centre-stack behaviour. Its guard `isRunningModernUI` (`:390`) does not name `WinampModernMainWindowController`, so `.wal` falls through to the stale `isModernUIEnabled` preference. **Gate the resize itself on the mode; do not add the controller to the predicate**, whose other callers would all inherit the answer. Classic and Original byte-identical. The `.wmz` half is W237 in [`WMP_TASKS.md`](WMP_TASKS.md) | every `.wal` session with the library open | S | Live-reported |
| B60 | **The hosted library and video surfaces have no body drag.** `WinampModernLibrarySurfaceView`'s blank area below the last row could be a handle and is not; `WinampModernVideoSurfaceView` overrides no `mouseDown` and its picture is a child window, so whether a press reaches anything is unverified — measure it in the app. `WinampModernBrowserSurfaceView` is out of scope (the page owns the mouse) | — · every skin with a usable standard frame | M | Live-reported |
| B65 | **A division by zero abandons the whole handler, where Winamp carries on.** `MakiBytecode.swift` opcode 67 throws `invalidScript`; MAKI's `/` is a float divide, so Winamp yields infinity and runs on. See [detail](#b65) | 1 skin / 2 sites measured (Shield_Amp); corpus reach unmeasured | S | Live-reported |
| B71 | **A layout script loads before the standard frame beside it has a client area**, so every name it resolves is null. Measured on Defix's detached visualizer. See [detail](#b71) | — · seen on Defix's detached visualizer; corpus reach unmeasured | L | Live-reported |
| BB34 | **An embedded visualization pane's engine never starts.** Big Bento Modern's Multi Content View mini pane draws black; the last line is `WINAMP-MODERN-VIS: resume … visible=0 … rendering=0`. **Re-measure first** — BB35's fix gives a detached surface a route back and may have cured it. 6 corpus skins embed a holder in the player (B23a), not 1 | — · seen on Big Bento Modern's mini pane | M | Live-reported |
| B74 | **T800's five memory slots share one storage key.** See [detail](#b74) | 1 skin / 5 buttons collapsing to 1 slot ([M22]) | L | Live-reported |
| B82 | **A runtime-instantiated subtree is never told the current playback state.** A widget brought up mid-session gets `onScriptLoaded` and a seeding `onResize`, but no `onTitleChange` / `onPlay` / `onAlbumArtLoaded`, so it stays blank until the next track change. Measured on ClassicPro's Now Playing widget: its three `SC:FadeText` lines stay empty. The seeding pass runs once in `WinampModernMainView.scriptsDidStart()` | 5 cPro skins ship widgets; any skin using `<CustomObject>` or `GroupList.instantiate` | M | Live-reported |
| B80 | **Horizontal seams at fractional UI Sizes.** Hairlines along band boundaries on cPro at 105%. Affects exactly the sizes fractional at 2x backing (90/105/110/115/125/135/175). See [detail](#b80) | 7 of 13 UI Sizes; every skin ([M25]) | M | Live-reported |
| B79 | **`autowidthsource` naming a bitmap label sizes its group to nothing.** `autoWidth` answers only for `<text>`, `<songticker>` and check boxes, so winampmodern566's `<groupdef id="menugroup.file" autowidthsource="File.txt">` resolves 0 wide and its titlebar menus have no hit target. Fix: give an object with resolved artwork its bitmap's width. Moves group sizing engine-wide, so it wants a corpus sweep | 2 skins / 24 declarations ([M24]) | S | Live-reported |

### Awaiting manual QA

| Id | Item | Remaining check |
|---|---|---|
| B41 | `getMonitorWidth` / `getMonitorHeight` | Needs a second display. Load Big Bento Modern, move the player to it, open the right-side playlist and toggle **Enlarge Playlist**; the column must size against the player's display, with no 2x oversizing on Retina. Repeat back on the primary display |
| B85 | The Widgets Manager's three place buttons | On a cPro skin: drawer menu -> *Widgets Manager*, then **show in main / drawer / side** on a row. Uninstall and support are expected to stay inert |
| B66 | The Wasabi drop-down's persistence | On Styx's Config, pick a `Position` drop-down entry, reopen the window, confirm the pick survived |
| B110 | Ebonite's frame overlay windows ([record](docs/winamp-modern/backlog-archive.md#b110--a-skins-window-frame-can-be-a-second-window--implementation-record)) | Reporter's confirmation that Ebonite's frames draw, stay glued and stack correctly |
| B111 | Itemskin's silenced audio ([record](docs/winamp-modern/backlog-archive.md#b111--an-unchanged-setactivated-dispatched-ontoggle--implementation-record)) | The persisted volume is `0.00` residue: raise it once, confirm it holds through a drag and a relaunch, and that playback is audible |
| B56a | Window tiling follow-ups | A skin whose playlist is a classic fallback; a Classic/Original regression pass; the arrangement after a live UI-Size change (expect `arrangeWindows()` to need re-running) |

## Agent-verifiable without user input

Triaged 2026-09-27 against the `app-control` tools: `launch.sh`, `winhelper`
(`click`/`dblclick`/`drag`/`move`/`scroll`/`clickdiff`/`capture`/`screens`), `menu.applescript`,
the window census and the render-dump harness. The ranking above still sets the order.

| Id | What the agent can do alone | How it is verified |
|---|---|---|
| B99 | Implement `enumObject` / `getNumObjects` | `RENDER_SCRIPTS` failure count on cPro2 Dark Aluminum goes to 0; open InfoViewer live and `capture` it |
| B65 | Measure reach with a `RENDER_SCRIPTS=1` corpus sweep, then make the float divide follow IEEE | Sweep count of `division by zero`; Shield_Amp songticker scrolls in two `capture`s taken apart |
| B79 | Size an `autowidthsource` bitmap label from its artwork | Corpus render sweep; on winampmodern566, `clickdiff` on a titlebar menu entry shows a new layer≠0 row (a menu opened) |
| B60 | Add a body drag on the library blank area and the video surface | `drag` + `windows` origin delta; the video is opened with `dblclick` on a browser row |
| BB34 | Re-measure first | Big Bento Modern, tick the mini pane with `click`, then take two `capture`s and check they are not black and not identical |
| B82 | Seed a runtime-instantiated subtree with the current track | cPro Now Playing widget opened with `click` mid-track; `capture` shows the title, artist and album lines |
| B123 | Re-measure Lobe and mmd3 knobs under a screen-space cursor reading (Rika is not installed) | `drag` each knob or dial and `capture` before and after, on both builds, via an A/B env switch |
| B74 | Confirm the `<Wasabi:Button>` object model, then key each slot separately | T800: hold `drag` for ≥2.5 s on each slot, then check the `defaults` keys and the recall `playTrack` log lines |
| B18 | Fix the classic minimize mask | Classic skin, minimize-all from the menu bar; the `windows` rows disappear and come back on restore |
| B71 | Reorder script startup, then handle visrb2's auto-hide | Corpus render sweep; Defix detached vis: `click` Reattach, and `clickdiff` shows the window change |
| B80 | Add a partial-repaint mode to the harness, then fix the seam | Count partial-alpha rows at a fractional scale; live: set UI Size from the menu, `move` over controls, `capture` |
| B119 | Try a lower FX repaint rate, or clip the warp extent | Hands-off release `sample` of WMP11-BlueVU against cPro-Bento, per `harness.md` |
| B111 | Drag the volume up, relaunch | Persisted volume ≠ 0 after relaunch, and the log shows no `setvolume(0)` cascade (audibility is not checked) |
| B56a | The three tiling checks | `windows` geometry before and after a UI-Size change from the menu bar; Classic/Original census rows unchanged |

**Partly verifiable.** B147: the fix is autonomous, but *Hide Title Bars* is only in the context
menu, so the live toggle is Route D. B66 and B85: the drop-down and the drawer menu may be
contextual menus; if a synthetic press does not open them, they are Route D.

**Needs the user.** B41 needs a second display (`winhelper screens` shows one). B110 waits on the
reporter's confirmation.

## Reproducible reach commands

All commands use the directories extracted with `7zz` from
`~/Library/Application Support/NullPlayer/WinampModernSkins/` (excluding `ClassicProEngine`). Set
`corpus=/path/to/the/extracted/root`.

**The corpus is 80 `.wal` archives as of 2026-09-27**, so an `[M##]` measured against an earlier
count is not comparable to a new one. **Four are byte-identical re-adds** of installed skins —
`pure_inspired_for_winamp_by_marisa85_d35ix2r` = `Pure Inspired`,
`k_jr_winamp_skin_by_marisa85_d329ymw` = `K-jr`, and the two `dewytears_v2_5_by_dewytear_d2yn025_*`
= `DewyTears_{Pink,Black}GlassV2.5` — so exclude them from any per-skin count.

A command lives here only while an open item cites it; closing the item moves the command into its
archive entry.

- <a id="m25"></a>**M25:** device scale is UI Size x the display's backing factor, so on a 2x panel the fractional stops are 90, 105, 110, 115, 125, 135 and 175 % — 7 of the 13 `UIScaleLevel` cases. To check a *full* draw, `WINAMP_MODERN_RENDER_SCALE=<factor> WINAMP_MODERN_RENDER_DUMP=/tmp/s WINAMP_MODERN_WAL=<skin> swift test --filter WinampModernRenderDumpTests`, then count rows whose alpha is strictly between transparent and opaque.
- <a id="m24"></a>**M24:** for each `.wal` (and the ClassicPro engine tree), collect `id=` from every `<layer>` and every `<text>`, then keep the `autowidthsource="…"` values that name a layer and not a text. Measured 2026-08-31: The_Nokia_5220_XpressMusic 12 of 12 and winampmodern566 12 of 18.
- <a id="m22"></a>**M22:** `rg -i -o '<[[:space:]]*Wasabi:Button[^>]*>' "$corpus" --glob '*.xml'`, then keep the matches with neither `action=` nor `text=` — the ones only a script drives.

## Item detail

### B119

- [ ] **B119. WMP11-BlueVU's per-frame warp costs three quarters of the main thread.** The skin
      warps two layers — 300x300 and 180x180 — on every frame.

      **Baseline** (release build, local file playing, hands off, 10 s `sample` each, cPro-Bento as
      the control on the same build minutes apart):

      | | WMP11 before | WMP11 after (1) | control |
      |---|---|---|---|
      | main-thread **busy** | 77.9% | 68.6% | ~49% |
      | `resample` (our CPU warp) | 24.1% | **10.6%** | 0.0% |
      | `CGDisplayListDrawInContextDelegate` (the paint) | 21.3% | **23.0%** | ~5% |

      **(1) The CPU mesh resample is fixed** (2026-09-04); the doc comment on `resample` is the
      account. **(2) Core Graphics painting the warped image is open.** The warp mints a new
      `CGImage` every frame, marked into the backing store under `CA::Transaction::commit ->
      CGDisplayListDrawInContextDelegate`.

      **Ruled out — do not re-try:** an f16 backing store (`WINAMP_MODERN_DRAW_FORMAT=1` reports
      `RGBA8`); emitting the warp at device resolution in the destination's colour space (measured
      worse, 23.0% -> 26.4%, reverted); unrelated compositing (the control paints ~5%); widening
      `warpedImageCache` (every miss is genuine).

      **To try:** repaint the FX layers fewer times a second (compare the animation clock with the
      skin's own cadence, `WINAMP_MODERN_RENDER_FX_SPIN`), or paint less of them (is the warp extent
      larger than what is visible?).

      **Constraints.** `drawWarped` is shared with Defix's reels and needles, so a fix wants a corpus
      render sweep and `RENDER_TIME`/`RENDER_FX` on Defix as a second control. Classic and Original
      must not move. **Done when** WMP11's busy fraction converges on the control's ~50%, measured as
      above and parsed per [`harness.md`](skills/winamp-modern-skin-guide/reference/harness.md).

### B65

- [ ] **B65. A division by zero abandons the whole handler.** Shield_Amp's songticker never
      initialises: its `OneDirectionText` widget reads `{9149C445-…};Text Ticker Speed`, which no
      script in that archive registers, so `getData()` answers `""` and `20/stringToFloat("")`
      divides by zero. Fail-closed is right for a missing method; it is wrong for arithmetic, where
      the IEEE answer exists.
      **Before changing it:** confirm what Winamp produces for the integer case as well as the float
      one (opcode 67 sees both), and measure reach with a `RENDER_SCRIPTS=1` corpus sweep counting
      `division by zero`. Keep the warning.

### B71

- [ ] **B71. A layout's own script loads before the standard frame beside it has a client area.**
      `WinampModernScriptRuntime.start()` dispatches `onScriptLoaded` to every program and only then
      delivers XUI params, and a `<Wasabi:StandardFrame:*>` has no client area until its `content`
      param arrives. On Defix's detached visualizer, `visrb2.maki` binds eleven names
      (`vis.DTB`, `vis.random`, `VIS_Menu`, …) and `RENDER_SCRIPTS=bindings` prints `-> null` for each.
      **Tried and reverted once (2026-08-29):** delivering each owner's params right after its own
      `onScriptLoaded` makes the bindings live, and then `visrb2`'s auto-hide (hide the control bar at
      load, re-show from a 300 ms timer gated on `layout.isActive()`, relayout on `onResize`) left
      Reattach dead and the Options button gone. So: (1) the ordering change, behind the corpus render
      sweep; (2) the auto-hide/relayout behaviour, which has no measurement yet.

### B74

- [ ] **B74. T800's five memory slots all write one storage key.** `quicksongpick.maki` keys each
      slot on `getParent().getID()`, and all five buttons sit directly in `groupdef player.main.cms`,
      so every slot reads and writes `winampModern.config.T800.T800.player_main_cms`; the skin prints
      `Song recorded: player.main.cms` where it should print `Mem3`.
      **Likely cause, unconfirmed:** `wasabi.button` is an identifier-only shell
      (`WasabiSkinInitializer.swift`), so `<Wasabi:Button id="Mem3">` is one flat object. In Wasabi
      the tag is a standard-library group, and if the script's receiver is a control inside it,
      `getParent()` is `Mem3`. Making it a real group touches all 32 `<Wasabi:Button>` declarations
      and the B14/B66 form widgets, so confirm the object model first.
      Recording needs a hold of ~2.5 s, and the confirmation is written inside the jaw — neither is a
      defect.

### B80

- [ ] **B80. Horizontal seams at fractional UI Sizes.** A *full* draw is clean at 2.0 and 2.1 device
      scale (zero partially-transparent rows), so the defect is the **targeted-repaint** path:
      `draw(_:)` clears `dirtyRect` and redraws clipped to it, and a partly-cleared boundary row keeps
      a hairline until a full repaint. Backing-aligning the invalidation rect in `setNeedsDisplay(_:)`
      was tried and did not cure it. Suspect the hosted surfaces, which are real `NSView` subviews
      with their own invalidation. The cPro2 "clicking recolours a region" report was a different
      defect (closed); do not re-chase the region-scale probe. The harness has no partial-repaint
      mode, which is most of this task ([M25]).

## Backlog hygiene check

Run before committing backlog changes:

```bash
scripts/validate_winamp_modern_backlog.sh WINAMP5_TASKS.md
```
