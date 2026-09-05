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
| BB14 | Animated layout/tab transitions beyond existing object tweens | 0 known dependent skins; existing tween calls are not evidence for this missing surface ([M4]) | L | Measured |
| B18 | Classic minimize-mask parity | — · engine integration, outside the corpus | S | Measured |

### Live-reported draw defects

| Id | Item | Reach | Effort | Tier |
|---|---|---:|:---:|---|
| B123 | **`System.getMousePos*` answers in the window's canvas space where Winamp answers in screen space.** Found while closing B101 (2026-09-04): cPro2's `layout.m` opens its Aero-snap preview when `System.getMousePosX() < 1`, meaning *the cursor is at the left edge of the screen*; ours reads window-relative, so it is true whenever the pointer is anywhere left of the player and the preview opened on an ordinary launch. The suppression that closed B101 hides the symptom on the only skin that has shown it; the reading is still wrong for anything else that asks. **Not a free change**: `WinampModernMainView.currentMousePositionInSkinPixels` is window-space deliberately, and `reference/scripting.md` records three corpus skins (Lobe, Rika, mmd3) whose knobs and dials were fixed by making it so — a screen-space reading wants each of those re-measured live before it lands | 1 skin measured; every skin whose script reads the cursor | M | Live-reported |
| B117 | **WMP11-BlueVU's spectrum jumped and its marquee is low-fps — two separate defects.** (b) the streaming analyzer was starved of buffers: **fixed and live-confirmed 2026-09-04**. (a) the window repaints at ~7 fps: **open**, cause found by B118 (the per-frame layer warp), fix tracked as **B119**. See [detail](#b117) | 2 skins measured; (b) reached every streaming consumer | — | Measured |
| B119 | **WMP11-BlueVU spends ~75% of the main thread where a normal skin spends ~50%**, because it warps two layers on every frame. **(1) the CPU mesh resample is fixed** (2026-09-04, 24.1% -> ~11%). **(2) Core Graphics painting the warped result is open**, ~26% against a control's ~5%. Three candidate causes are now dead by measurement; what is left is drawing less, not drawing cleverer. See [detail](#b119). Shared path (Defix warps too), so a fix wants a corpus sweep | 2 skins measured; every skin with an animating `<layer>` FX mesh | M | Live-reported |
| B111 | **An unchanged `setActivated` dispatched `onToggle`, and it silenced the player on Itemskin.** Reported 2026-09-04 as *"in the itemskin skin the audio does not work — this is the only skin with that symptom"*. `scripts/playerVolumeExtra.maki` answers `onVolumeChanged` by deactivating the mute and ATT buttons, which are already off; each button's `onToggle` **false** branch is `setVolume(savedVolume)`, an uninitialised `0`, and `setVolume` re-raises `onVolumeChanged`. So the host volume went to zero at load, no drag could lift it, and the zero was persisted into the next launch. Wasabi notifies only on an actual change; ours notified unconditionally. **Fixed 2026-09-04** — `setActivated` sends `onToggle`/`onActivate` only when the activation moves (`setActivatedNoCallback` stays the silent write for one that did). **Awaiting the reporter's live confirmation** | 1 of 70 skins binds `onToggle` to the volume; the dispatch rule is engine-wide | S | Live-reported |
| B110 | **A skin's window frame can be a *second window*, and `newDynamicContainer` only ever answers with the one instance.** Ebonite's standard frame opens `newDynamicContainer("sc.alphaframe")` in `wasabi/standardframe/standardframe.m` and keeps it on top of the client with `frame_layout.resize(comp_layout.getLeft(), comp_layout.getTop(), comp_layout.getWidth(), comp_layout.getHeight())` — the visible border (10 left / 17 right / 30 top / 30 bottom, plus RGB-tinted variants) is drawn by that overlay, not by the client window. So the client group is deliberately short: `w="-17" relatw="1" h="-20" relath="1"`, 233x230 of a 250x250 window. We create that window from load and never show it, and we answer `newDynamicContainer` with the already-instantiated container whoever asks, so the margin stays empty — reported 2026-09-03 as "there is no right hand pad". **Implemented 2026-09-03, awaiting the reporter's live confirmation** | 5 skins measured ([M31]); 8 archives build a live copy after the fix | L | Live-reported |
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
- <a id="m31"></a>**M31:** over the **70-skin corpus** (66 net of byte-identical re-adds), `strings` every `.maki` for `newDynamicContainer` and pair the hits with the `dynamic="1"` containers the tree declares. **Re-measured 2026-09-03 while closing B110, correcting the first pass:** **16 skins call it**, not 12, and **5 use it for the per-window frame-overlay idiom**, not 4 — Ebonite_2_1 (`sc.alphaframe`), MoonLight, Itemskin, **K-jr** and **Pure Inspired** (`cont.clear.pl` / `.ml` / `.dl` / `.vd`, one per hosted window kind; K-jr's and Pure Inspired's `standardframe*.maki` are byte-identical to MoonLight's, `cmp` exit 0). All five descend from the same leech-derived `standardframe`, and MoonLight and Itemskin also appear in B78's alpha sweep with the same short client group and 1x1-texture border strips. **4-drelictionreleasepic is not one of them** — the first pass listed it in error: its `scripts/standardframe.m` contains no `newDynamicContainer` at all and does `content = newGroup(groupid); content.init(frameGroup)`, so its frame draws **inline in the same window**; its only `newDynamicContainer` is in `scripts/notifier.maki`. The other callers want instancing for their own windows rather than for chrome: Big Bento (`searchresults`, `Hsearchresults`, `browserpro`), jvc.tape, multipass, the two Love is War Miku variants, hatsune_miku_5, winampmodern566, Defix Hi-END 200, impulse_by_a_t_o_m_i_c and 4-dreliction's notifier. **After B110 landed, 8 archives actually build a live copy** in the render sweep — Ebonite (4), cPro2 Dark Aluminum (2, `searchresults`), Defix Hi-END 200 (2, `browserpro`), the four Big Bento Modern variants and WMP11-BlueVU (1 each) — the rest keep aliasing the declared container because only one program per id ever asks.
- <a id="m32"></a>**M32:** `for d in "$corpus"/*/; do n=$(grep -rlio 'desktopalpha="0"' "$d" | wc -l); [ "$n" != 0 ] && echo "$n ${d}"; done` over the extracted 69-directory corpus. Measured 2026-09-04: **26 skins** declare it in at least one file — WMP11-BlueVU (7), impulse_by_a_t_o_m_i_c (6), Nullsoft.Winamp.2000.SP4.Lite and Itemskin (5), Pure Inspired x2, multipass, MoonLight, K-jr x2, Anaheim_Player_01 (4 each), Ujola Cat and Shield_Amp (2), then 13 with one apiece. **This counts declarations, not dependence** — most of these layouts paint their own chrome edge to edge and did not change when B114 landed. The narrowing is now done: with B114 landed the corpus render sweep (2026-09-04) moves **2 of 590 images** — WMP11-BlueVU's display area and a 7-pixel anti-aliasing fringe on EPS High-End's left speaker. An earlier, wrong version of that fix moved 34, which is what a *fill* rather than a region costs. See [`docs/winamp-modern/backlog-archive.md`](docs/winamp-modern/backlog-archive.md) -> B114.
- <a id="m33"></a>**M33:** parse every `<groupdef>` in the corpus for its `id`, its `inherit_group` and its direct children's `id`s, then report the groupdefs whose own child ids intersect their base's. Measured 2026-09-04 (~40 lines of Python: `os.walk` the skin, regex `<groupdef\b(.*?)>(.*?)</groupdef>` with `re.S`, pull `id`/`inherit_group` from the head and every child's `id` from the body, then intersect each derived group's child ids with its base's): **42 of 69 skins use `inherit_group` at all**, and **3 redeclare a same-`id` child** — Sony_Walkman (6: `component.bottom.left/middle/right`, `region.bottom.left/right`, `wasabi.frame.layout`), canum_winamp (1: `wasabi.frame.layout`), WMP11-BlueVU (1: `wasabi.frame.layout`). All 8 are in `wasabi.standardframe.*` groups, which is why the symptom is always a doubled window frame. **Lower bound:** the probe resolves one level of inheritance only (the base must itself be a declared groupdef), so a chain longer than two is not counted.
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

### B111

- [ ] **B111. An unchanged `setActivated` dispatched `onToggle`.** Reported 2026-09-04: *"in the
      itemskin skin the audio does not work"*, and only that skin. Root-caused the same day from
      `WINAMP_MODERN_CALL_TRACE=1` in the running app.

      **What the skin does.** `scripts/playerVolumeExtra.maki`, on the main and mini layouts:

      ```c
      onVolumeChanged(v) { if (!muted) { att.setActivated(0); mute.setActivated(0); } muted = 0; }
      mute.onToggle(on)  { if (on) { savedVolume = getVolume(); setVolume(0); }
                           else      setVolume(savedVolume); }
      ```

      Both buttons are already off, so in Winamp those two writes do nothing. `volume.mute` is
      declared `<Togglebutton id="volume.mute" />` — no image, no action, no coordinates, a 0×0
      object a user cannot click — so nothing else in the skin ever reaches that handler.

      **What we did.** `WinampModernScriptRuntimeObject.swift`'s `setactivated` case wrote the state
      and then dispatched `ontoggle` + `onactivate` unconditionally. Every volume change therefore ran
      both `onToggle`s' false branch, `setVolume(savedVolume)` with `savedVolume` still `0`; `setVolume`
      re-raised `onVolumeChanged` (bounded by the re-entrancy guard, but the write had landed). Trace
      from the app, on a fresh launch:

      ```
      AppStateManager: Restoring settings state - volume: 0.00
      CALL-TRACE setxmlparam(ghost,0) on Togglebutton#volume.att
      CALL-TRACE setvolume(0)             <- nobody asked
      CALL-TRACE setactivated(0) on Togglebutton#volume.att
      CALL-TRACE setvolume(0)
      ```

      **The fix.** `setActivated` compares the wanted activation against the object's own `activated`
      and notifies only when it moves. `toggleActivation` (a real click) always changes state and is
      unaffected; `setActivatedNoCallback` keeps its job, the silent write for a state that *did*
      move. Documented in `compatibility/maki-surface.md` → *A write that changes nothing is not an
      event*, with the reporting lesson in `skins/itemskin.md`.

      **Verification (2026-09-04).** `swift test --filter WinampModern`: 1290 pass, 12 skipped, 0
      failures — including the two tests that pin `setActivated`'s notification, both of which drive a
      real state change. Debug build relaunched on Itemskin: the `setvolume(0)` cascade is gone
      (`grep -c setvolume` on the call trace: **0**, against 4 before).

      **Remaining live check.** The reporter's persisted volume is still `0.00` — residue saved by the
      bug, which does not clear itself. Raise the volume once, confirm it holds through a drag and
      survives a relaunch, and confirm playback is audible. See the checklist entry in
      `manual-qa-checklist.md`.

### B117

- [x] **B117(b). Streaming starved the `.wal` analyzer, and the spectrum slammed to the floor several
      times a second.** Reported 2026-09-04 as WMP11-BlueVU's spectrum being choppy. **Fixed and
      live-confirmed 2026-09-04** (*"it looks much better now"*).

      `StreamingAudioPlayer.processAudioBuffer` delivered PCM through `DispatchQueue.main.async`, so
      the 2048-point FFT ran on **main** — and the coalescing flag was cleared only *inside* the
      dispatched block, so while main was stalled every buffer was **discarded rather than queued**.
      Past the 150 ms silence timeout the tap answers all-zero bands, hence full-scale-to-floor
      several times a second. `AudioEngine` posts straight from its tap with no coalescer, which is
      the whole of the local-vs-stream asymmetry the reporter saw. Fixed by posting from the audio
      thread and deleting the coalescer; both consumers already expect that thread.

      | | before | after |
      |---|---|---|
      | arrival gap | median 318 ms, p90 1045, max 5981 | median **106 ms** |
      | `WM-VIS-GAP silence` | 480 | **0** |
      | draws reading zero | 481/621 (58%) | **9/900 (1.0%)**, matching local's 2.3% |

      **Dead ends — do not re-try.** The `frameCount >= 2048` short-buffer theory (every streaming
      arrival logged `frames=2048`), and the `offset = max(0, available - fftSize)` staleness lead in
      [`rendering/vis.md`](skills/winamp-modern-skin-guide/reference/rendering/vis.md), which is a
      latency defect and not this one.

      **Left behind for whoever touches it next.** `processAudioBuffer` writes the shared
      `fullStereoPcmLeft/Right` before copying out and the coalescer used to mask that seam; the
      strict 106 ms spacing says the calls are sequential, so this is a note, not a defect. And the
      delivery thread of `.audioStereoPCMFullDataUpdated` is undocumented where it is declared while
      `StreamingAudioPlayer` hops to main in **six** places — `pendingSpectrumUpdate` and
      `pendingPcmUpdate` feed the Classic spectrum and PeppyMeter through the identical block and
      have not been measured. Same seam as `780541ea`, `3b9721af`, `bc4253eb`.

- [ ] **B117(a). The window repaints at ~7 fps, and the marquee with it.** Measured, not disputed:
      the frame interval clusters at 120–145 ms against an expected 33 ms, and `WM-VIS-STALL` is
      median 131 / p90 300 after B117(b). cPro-Bento on the same build is median 60 / p90 68, so it
      is skin-specific. The marquee shares the repaint, which is why the symptom is not audio-shaped.

      **The cause is found and the fix is B119** — the per-frame layer warp in
      `WasabiLayerFXMesh.resample` and the paint that follows it. This item closes when B119 does;
      it holds no separate work.

      **Dead ends — do not re-file.** Scene-memo thrash from the twelve
      `animatedlayer#beatleft/beatright` that write `frame` ~100x/s: `frame` is already scene-neutral
      (`WasabiObjectGraph.isSceneNeutral`), and partitioning all 169 `MUTATION_TRACE` windows gives
      **148 of 150 `writers=12` windows at `resolves=0`**. That claim came from pairing a `writes=`
      line with a `resolves:` line out of a **different** window — the trace prints them separately,
      so read whole windows rather than grepping the two apart. `RESIZE_TRACE` is clean, so it is not
      B52's resize storm either.

### B119

- [ ] **B119. WMP11-BlueVU's per-frame warp costs three quarters of the main thread.** The skin
      warps two layers — 300x300 and 180x180 — on every frame. Half the cost was ours and is fixed;
      half is Core Graphics painting the result and is open.

      **The numbers** (release build, local file playing, hands off, 10 s `sample` each,
      cPro-Bento as the control on the same build minutes apart):

      | | WMP11 before | WMP11 after (1) | control |
      |---|---|---|---|
      | main-thread **busy** | 77.9% | 68.6% | ~49% |
      | `resample` (our CPU warp) | 24.1% | **10.6%** | 0.0% |
      | `CGDisplayListDrawInContextDelegate` (the paint) | 21.3% | **23.0%** | ~5% |

      **(1) The CPU mesh resample — FIXED 2026-09-04.** It interpolated the mesh in `Double` per
      destination pixel; it now does one lerp per row and blends four channels as one `SIMD4` in
      fixed point. 2.05 -> 0.73 ms/frame at 264x264. The doc comment on `resample` is the canonical
      account. Differs from the old form by at most 1 on 4% of channels, which is what the corpus
      sweep sees.

      **(2) Core Graphics painting the warped image — OPEN.** `draw(_:)` records a **display list**,
      and the image is marked into the backing store later, under
      `CA::Transaction::commit -> CGDisplayListDrawInContextDelegate -> ripc_DrawImage -> ripl_Mark`.
      The warp mints a new `CGImage` every frame, so nothing about it can be cached between frames.

      **Ruled out — do not re-try these.**

      - ~~An f16 backing store (EDR / deep colour).~~ `WINAMP_MODERN_DRAW_FORMAT=1` reports
        `layerFormat=RGBA8`, `layerEDR=false`, `edrMax=1.0`. The `RGBAf16_*` frames are Core
        Graphics' resampler, not the destination.
      - ~~The raster being the wrong size or format.~~ Tried 2026-09-04 and **measured worse**:
        emitting the warp at device resolution in the destination's colour space moved the paint
        **not at all** (23.0% -> 26.4%) and added ~5 points to `drawWarped`. Reverted. An isolated
        benchmark said this should have been a 9x win (2.07 ms -> 0.215 ms per draw), and it was not,
        which means a bitmap context in the screen's colour space is **not** a model of what the
        replay composites into. Do not trust that benchmark shape again.
      - ~~Unrelated compositing sharing the replay.~~ The control warps nothing and paints at ~5%;
        WMP11 warps and paints at ~26%, same build, minutes apart. The cost tracks the warped layer.
      - ~~Widening `warpedImageCache`.~~ It is keyed on the mesh on purpose. A 24% cost means the
        layer moves a vertex nearly every frame, so every miss is genuine. `warpSourceCache` already
        caches the source mesh-independently; neither is the lever.

      **What is left.** The paint is expensive because of how many pixels are painted, how often —
      not because of their shape. So: **repaint the FX layers fewer times a second** (check the
      animation clock's rate against the rate the meter actually moves — `WINAMP_MODERN_RENDER_FX_SPIN`
      measures the skin's own cadence), or **paint less of them** (check whether the warp extent is
      larger than what is visible; both costs scale with `w x h`). Neither has been tried.

      **Constraints.** `drawWarped` is shared — Defix's reels and needles take the identical path —
      so a fix wants a corpus render sweep and `RENDER_TIME`/`RENDER_FX` on Defix as a second
      control. Classic and Original behavior must not move.

      **How to confirm.** Release build, WMP11-BlueVU against cPro-Bento, local file playing, hands
      off, 10 s `sample` each. Parse per
      [`harness.md`](skills/winamp-modern-skin-guide/reference/harness.md) — cut the thread block at
      the next `Thread_<id>:`, sum leaves for busy/idle, take the **outermost** occurrence for a
      subtree. Success is WMP11's busy fraction converging on the control's ~50%, and it closes
      **B117(a)** with it. The table above is the baseline of record; the raw `sample` files were
      session scratch and are not preserved.


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

      **What we did.** `System.newDynamicContainer(id)` answered with the **already-instantiated**
      container of that id, so all five of Ebonite's frame programs drove one container. The window
      itself **was** created — `setupAuxiliaryContainers` builds one per declared non-main container —
      and simply never shown: `CGWindowListCopyWindowInfo` showing nothing is what an ordered-out
      window looks like, not a missing one. (The first draft of this entry said we materialize no
      window for it; that was wrong.) The margin was simply empty — which is also what exposed the
      zero-area browser surface closed alongside B78.

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

      **Reach: 5 skins ([M31])**, all from the same leech-derived standardframe — Ebonite,
      MoonLight, Itemskin, K-jr and Pure Inspired. Itemskin's frames were already noticed from the
      other side and closed as B69 ("its frames are a *second* container per window"), which is this
      same idiom seen through the hosted-surface probe. **4-drelictionreleasepic is not one of them**
      — it draws its frame inline in the same window; see the corrected [M31].

      **Before starting:** write the plan to `~/.claude/plans/` and have it reviewed. Window geometry
      has no useful armchair form (B56), so the loop is the `testing` skill's measure-it-live one,
      with `WINAMP_MODERN_PLACE_TRACE=1`.

      **Plan:** `~/.claude/plans/write-the-plan-do-tender-island.md` (revised 2026-09-03 after a
      fact-check; it corrects the reach and the "we materialize no window" claim above). Gated —
      step 1 is a candidate whole fix and scopes the rest.

      - [x] 1. `isDynamic()` on a container, then **measure on Ebonite**. **Measured 2026-09-03:**
            `isDynamic` alone was not enough — the next statement is `system.onScriptLoaded()`, a
            script calling its **own** startup body, which had no dispatchable arity, so the handler
            still died one statement before `frame_layout.show()`. With both landed the frame window
            **is on screen and drawn**: border, "Playlist Editor" title, close button and both
            resizer grips (`WinampModernContainer_sc.alphaframe`, exactly over the client's rect).
            It also settles the decision point: Ebonite runs **five** standardframe programs against
            the one aliased container, so the playlist, library and frame windows all end up at one
            rect (320x250 @ 822,561). Instancing is required.
      - [x] 2. Real instancing for `newDynamicContainer` — **per calling program**. The first program
            to ask keeps the declared container (so every single-holder caller is unchanged); a second
            program asking for the same id gets a live copy built from the container's own XML, with a
            distinct id (`sc.alphaframe#2`) and its opening layout realized. The same program asking
            twice gets the copy it already holds, so Ebonite's close-on-hide/rebuild-on-show cycle
            leaks nothing. Cap 12 per id
      - [x] 3. Window identity: **not** the planned re-key of `auxiliaryContainers` to `WasabiObjectID`.
            A copy is given a distinct container *id* instead, so all 17 `first(where: { $0.containerID
            == id })` sites keep working unchanged and accessibility ids are unique — the plan's stated
            reasons for the re-key, at a fraction of the risk it flagged ("where a silent misroute
            would hide"). Copies carry `nullplayer_dynamic_instance=<declared id>`, the sibling of
            `nullplayer_synthesized`
      - [x] 4. A window per copy: the recipe is factored out of `setupAuxiliaryContainers` into
            `makeAuxiliaryContainer`, and the hook that calls it is wired in `wireContainerCallbacks`,
            **before** `scripts.start()` — Ebonite asks for all five copies from `onScriptLoaded`, and
            wired with the surface coordinator (after `start()`) every copy came up windowless. Copies
            are excluded from `arrangeWindows()`, `place()`, `snapTargetWindows()`, the window menu and
            visibility persistence
      - [x] 5. Client -> frame sync via B69's `borrowedWindowOrigin` — worked as the plan predicted.
            Measured: dragging the frame's title bar moved both windows to (875,688) together
      - [x] 6. `onUserResize` (arity 4), fired from `windowDidResize` only while `inLiveResize`, and the
            ±1 clamp — handled with a **one-pixel tolerance** in `borrowedWindowOrigin`, the offset
            carried through to the desktop origin so the jiggle still happens. Measured: growing by the
            grip took both windows to 385x377; shrinking past the clamp took both to 258x258 **in
            place**, with no jump to the screen corner
      - [x] 7. Z-order: clicking the client buried its own frame (title strip went black, border
            survived only where the client's group does not reach). The pairing is the skin's, so it is
            learned from the `frame.resize(client.getLeft(), …)` idiom itself (`windowsGluedOver`) and
            `windowDidBecomeKey` re-raises the follower one runloop turn later — inside the
            notification the raise is undone by the rest of that pass. Alpha and `isActive` needed
            nothing: both already resolve per window id
      - [x] 8. Click-through measured, not assumed: a click in the frame's transparent middle reached
            the library client and switched it to Albums
      - [x] 9. Correct the B110/M31 backlog facts (reach 5 of 70, not 4 of 61; 4-drelictionreleasepic
            draws its frame inline; K-jr and Pure Inspired are in the cohort; 16 skins call
            `newDynamicContainer`; the frame window is created and never shown)

      **Verification (2026-09-03).** `swift test` 1743 pass + 12 new B110 tests. Corpus render sweep
      over 70 archives against a worktree baseline: every invariant change is an additive `#N` copy
      line, 588 of 590 images identical; `Ebonite_2_1/sc.alphaframe-scdef.png` changed size 640x400 ->
      250x250 (the declared container is now the *playlist's* frame rather than whichever program wrote
      last, which is the fix), and `Anexa/main-shade.png` differs **against a second capture of the same
      build**, the run-to-run flake `reference/harness.md` already records. The four already-working
      pair skins — MoonLight, Itemskin, K-jr, Pure Inspired — build no copies and their dumps are
      unchanged. Ten open/close cycles of the playlist leave the window count where it started.

      **Two defects the reporter's own session found that none of the above caught (2026-09-03), both
      fixed:**

      - **The playlist frame did not appear at all** ("all others do"). The first program to ask is
        answered with the *declared* container, so Ebonite's playlist frame is the one frame that is
        not a copy — and the load-time visibility hook was keyed on "is a copy". Its client is restored
        visible at launch and its `frame_layout.show()` runs inside `scripts.start()`, so that one show
        was dropped. The test is now **"has a script claimed this container through
        `newDynamicContainer`"**, asked of the runtime. It must *not* be the `dynamic="1"` attribute:
        a corpus scan found several skins declaring their real `Pledit`, `MLibrary` and `AVS` windows
        that way, and excluding those from tiling, snapping and the window menu would lose windows
        people open.
      - **The client was drawn over its own frame** ("1/2 of the window is one style and the other
        half is another"), and this took **two** passes. First: re-raising the frame on
        `windowDidBecomeKey` alone is not enough, because at launch the frame is shown *before* the
        client — `restackGluedWindows()` now runs on every window open, on every key change and once
        after launch settles. That still looked identical, and `WINAMP_MODERN_GLUE_TRACE=1` (added for
        it, documented in `reference/harness.md`) named the real cause in one run: a standard frame
        writes the origin **both** ways — `syncFrame()` puts the frame on the client and `syncContent()`
        puts the client back on the frame — so `borrowedWindowOrigin` recorded the pair in *both*
        directions and the restack loop fought itself, whichever direction it handled last winning. The
        record is now written in one direction only: the follower must be a container a script claimed
        through `newDynamicContainer`, the leader must not be.

      **Three further defects from the reporter's live session (2026-09-03), all fixed and confirmed
      by them:**

      - **The top and left borders read flat black** where the right and bottom read as glossy
        chrome. Not a window problem: the client window was painting under those two borders because
        B78 (`d14504f1`) had made Ebonite's four `sysregion="-2"` frame strips paint as artwork
        instead of cutting the region. That commit's own message says why — *"the client area drawn
        over it overhung a frame that was not there"* — and *"this does not give Ebonite its right and
        bottom pads; that margin is reserved for an overlay window the skin opens itself, filed as
        B110"*. B110 built that window, so the premise is gone and the commit is reverted: read as
        silhouettes those strips cut the client to exactly the frame's opening (top 30, left 10, right
        17, bottom 30 — that frame's inner rect to the pixel).
      - **An opaque bar across the frame's titlebar and under its status row**, each stopping short of
        the right edge. The group's `sysregion="1"` backdrop layer was restoring region its own
        siblings had just cut. **A group's own cut-out is not undone from inside it** — the
        cross-group restore S7Reflex needs is untouched. Written up in
        `reference/rendering/hit-testing.md`; the corpus sweep moves one other image, Shield_Amp's
        notifier by 125 px, in the same direction.
      - **The frame came away from NullPlayer's own windows** (Flow, Cava, PeppyMeter) when dragged by
        the frame — dragging the contents always worked. Two causes, both in the hosted-window path
        and written up in `reference/components.md`: the materializer is its own window delegate and
        never announced a move to the skin's script (nor did the reveal, where the placement actually
        happens, off screen); and `moveContainerWindow` could not resolve a hosted window at all, so
        `syncContent()` — the write that pulls the client along — landed nowhere.

      **Verification of those three (2026-09-03):** `swift test` full suite green, with two new
      `WinampModernHostedWindowTests` and a new `WinampModernPhase88Tests` case for the sibling rule
      (its S7Reflex fixture corrected to nest the cut in a group, which is that skin's actual shape).
      Corpus sweep over 69 skins: 582 of 590 images identical — Ebonite's five framed windows plus its
      frame, the known `Anexa/main-shade` flake, and Shield_Amp's 125 px corner. Live: frame dragged,
      client followed to (895,682); window opened, closed, reopened and dragged, frame glued each
      time.

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
