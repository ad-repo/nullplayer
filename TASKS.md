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
| B45 | Container declared without a reachable renderable layout | 1 skin / 1 container ([M17]) | M | Measured |
| BB13 | `setClipboardText()` | 1 skin / 1 MAKI program symbol; the program contains three calls ([M18]) | S | Measured |
| BB14 | Animated layout/tab transitions beyond existing object tweens | 0 known dependent skins; existing tween calls are not evidence for this missing surface ([M4]) | L | Measured |
| B18 | Classic minimize-mask parity | — · engine integration, outside the corpus | S | Measured |

### Live-reported draw defects

| Id | Item | Reach | Effort | Tier |
|---|---|---:|:---:|---|
| BB28 | Stretched visualization overlaps file info after restart | — · seen on Windows 10 edition Light (2026-08-25) | M | Live-reported |
| BB26 | File-info rating row draws dots rather than stars | — · seen on base and Light variants (2026-08-25) | S | Live-reported |
| B58 | In-skin visualization surface swallows single clicks | — · every skin with a `<vis>` the host fills | S | Live-reported |
| B60 | Hosted library and video surfaces have no body drag | — · every skin with a usable standard frame | M | Live-reported |
| B59 | Skins whose own player leaves almost no drag handle | 2 skins measured under 50% ([M19]) | M | Live-reported |
| B65 | A division by zero abandons the whole handler | 1 skin / 2 sites measured (Shield_Amp); corpus reach unmeasured | S | Live-reported |
| B71 | A layout script loads before the frame beside it has a client area | — · seen on Defix's detached visualizer (2026-08-29); corpus reach unmeasured | L | Live-reported |
| BB34 | An embedded visualization pane's engine never starts | — · seen on Big Bento Modern's Multi Content View mini pane (2026-08-29) | M | Live-reported |
| B74 | T800's five memory slots share one storage key | 1 skin / 5 buttons collapsing to 1 slot ([M22]) | L | Live-reported |
| B75 | A skin that includes the same script twice runs every handler twice | 1 skin measured (T800); corpus reach unmeasured | M | Live-reported |

### Awaiting manual QA

| Id | Item | Remaining check |
|---|---|---|
| B41 | `getMonitorWidth` / `getMonitorHeight` | Move Big Bento Modern between displays and verify its side-playlist sizing follows the display containing the player |
| B66 | The Wasabi standard form widgets | The **drawing** half is verified in the render sweep across the corpus. Radios and check boxes are **done** — a click on either was found dead in the app 2026-08-29 (B14's QA, on Shield_Amp and Styx: an unbound box drew from its `cfgattrib` provider's "no" instead of its own `activated`) and both are now confirmed live, including set exclusivity. What is left is the **drop-down's persistence**: on Styx's Config open the `Position` drop-down, pick an entry, then reopen the window and confirm the pick survived — which is the skin's own `onTextChanged` persisting it |

## Reproducible reach commands

All commands use the 36 directories extracted with `7zz` from
`~/Library/Application Support/NullPlayer/WinampModernSkins/` (excluding
`ClassicProEngine`). Set `corpus=/path/to/the/extracted/root`.

**A command lives here only while the item that cites it is open.** Closing an item moves its
command into that item's archive entry, in the same change — otherwise the entry is left behind
citing nothing, which is how five of these went stale before being pruned 2026-08-30 (M3, M7, M8,
M20, M21 — now recorded under BB10, B41, BB5, B66 and B67 respectively). Every `[M##]` below must
resolve to a live citation above.

- <a id="m19"></a>**M19:** `WINAMP_MODERN_DRAG_PROBE="$corpus_wal" swift test --filter WinampModernDragProbe` over the 36 installed `.wal` files, where `$corpus_wal` is `~/Library/Application Support/NullPlayer/WinampModernSkins`. Reports each container's draggable share; add `WINAMP_MODERN_DRAG_MAP=1` for the face map. See `skills/winamp-modern-skin-guide/reference/harness.md`.
- <a id="m4"></a>**M4:** source audit recorded in the item; `setTarget*` calls exercise the already implemented object tween machine and must not be counted as demand for animated layout/tab transitions.
- <a id="m22"></a>**M22:** `rg -i -o '<[[:space:]]*Wasabi:Button[^>]*>' "$corpus" --glob '*.xml'`, then keep the matches with neither `action=` nor `text=` — the ones only a script drives.
- <a id="m17"></a>**M17:** `rg -i -o '<container[^>]*id="Pledit"' "$corpus/Shield_Amp/xml/pledit.xml"`, then verify that file contains no `<layout>`.
- <a id="m18"></a>**M18:** `rg -a -i -o 'setClipboardText' "$corpus"`

For grep-derived rows, “skins” is the number of distinct first path components and “uses” is the
number of matched declarations or MAKI program symbols. A compiled MAKI method name is a program
symbol, not necessarily a call-site count; rows say so where that distinction matters.

## Item detail

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
      side-by-side layout, 2026-08-29; the layout itself is correct and confirmed live. Corpus reach
      unmeasured — the seven other skins with a `{0000000A}` holder all keep it in an auxiliary
      window, so this may be specific to a pane embedded in the player.

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

### B45

- [ ] **B45. Shield_Amp's playlist container has no layout.** `RENDER-DUMP dropped container: Pledit
      (no layout)` — the skin declares `Pledit` (and the catalog routes `playlist=declared:Pledit` to
      it), but nothing renderable is inside, so its `PL` button most likely opens nothing. Surfaced by
      B33's sweep, which is the first time this skin has ever loaded far enough to be measured.
      Unclear yet whether this is the skin shipping an empty container, an `<include>` we skip, or a
      layout named something other than `normal` — LOBE's B26 was the last of those and the container
      was being dropped silently, so check that first. Nothing else about this skin has been measured
      beyond the render sweep and one live launch

---

### BB13

- [ ] **BB13. `setClipboardText()`** — absent, so copy-title and copy-path from the skin's own menus
      are inert. Three call sites.

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

### B59

- [ ] **B59. Skins whose own player leaves almost no drag handle.** Measured 2026-08-28 with
      `WINAMP_MODERN_DRAG_PROBE` ([M19]): **Defix 33%** draggable and **corneramp_redux 49%**,
      against a corpus median of ~84% (Big Bento 90%, Lobe 97%, Core-X5 99%). On Defix the handle is
      a ~15px picture frame around the edge plus two thin strips. **This is not a hit-test bug** —
      every top blocker is the skin's own declaration: a `move="0"` layer covering 17% of the face,
      a script-bound `CASBODY` layer 13%, `Slider#seeker.ghost` 6%, the transport buttons. Honouring
      those is B38.1's policy working correctly, so no policy change can reach it.
      Two candidates, neither started. **A host escape hatch** — ⌘-drag moves the window from
      anywhere regardless of what the object claims; a handful of lines in
      `WinampModernMainView.mouseDown`, ⌘ is otherwise unused in that view's mouse path, and no skin
      sees the event. It is the only one that actually fixes Defix. **A deferred drag** on
      script-bound layers — the exclusion comment at `WinampModernMainView.swift:1683` already names
      Winamp's press-and-hold distinction and admits the hit test does not model it; a travel
      threshold would recover `CASBODY` (13%) and corneramp's `main1` (28%) without eating their
      clicks, and B57's `WinampModernHostedWindowDrag` is the shape to copy. It is the riskier of
      the two (it changes when every skin's `onleftbuttondown` fires) and it only takes Defix to
      ~46%, so it is not what makes that skin usable.
      Also measured, unexplained: a press where `renderer.object(at:)` finds **nothing** returns at
      `WinampModernMainView.swift:1141` before the drag branch, so it does not drag either. Large
      `none=` shares — Ujola Cat 64%, multipass 62%, Love is War Miku 55%, S7Reflex 53%,
      winampmodern566 41% — are presumably outside the shaped region, but that has not been checked
      against the region mask, and if any of it is inside the window it is dead area for one line's
      reason.

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

<details>
<summary>B52's task list, kept for the measurements it records</summary>

---

### BB28

- [ ] **BB28. The stretched visualization draws with the file info on top of it.** Reported live
      2026-08-25 on *Windows 10 edition Light*, with a screenshot: the analyzer spans the Multi
      Content View while the bitrate line, title, artist, album and the cover all show through it.
      **Reproduces only after a restart, and only once playback starts** (a 7.3:1 letterbox takes the
      renderer's analyzer, which is blank without audio — see `WinampModernVisualizationHolder`, BB9).

      **The sequence, measured in the running app** (`WINAMP_MODERN_DEBUG_HOLDERS=1` +
      `WINAMP_MODERN_TRACE_MAKI=1`, which is what made this legible at all):

      ```
      t=0     mcvcore @909 (onscriptloaded): page = Visualization ({6A619628};Visualization = 1)
              → hides infodisplay/songinfodisplay/cover/coverflow, shows info.component.vis.full  ✅
              → arms a 50 ms transition lock (v170; the page routines guard on its isRunning())
      t=0     a second player-normal-mcv script @3160 (onscriptloaded), gated only by a
              getRuntimeVersion() range check (2…65535 — we answer 5, so it passes):
              → arms a 700 ms one-shot (v171)
      t=700   @3237 (ontimer v171) → call 2416 → v171.stop()
              routine 2416 = "activate File Info": writes Component3="File Info", then **only calls
              show()**. It contains no hide at all, so it cannot displace the visualization page.
      ```

      **No engine defect was found behind it.** Each of these was proposed and then killed by
      measurement, and they are listed so nobody re-runs them: `openHolders` forcing (it never runs
      for `visualization`); the private `Visualizer Mode`; a stale `Component3` (setting it to
      `"Visualization"` changes nothing); `getGuiX` (`vis.prv -> 51`, correct and parent-relative);
      handler shadowing (zero shadowed bindings); config-attribute **dispatch order** (sorting by
      creation order changes nothing); missing visualization-surface detection (that log line is about
      a dedicated vis *window*, which Bento does not declare); target-animation completion
      (`onTargetReached` on `info.component.cover` fires *after* the page is already back); the
      `Cycle File Info` setting (the page returns with it off — an earlier "confirmed" reading here
      was a grep taken before the 5 s mark and is wrong); and the `v2` disable flag (set only on the
      version check's failure branch, which a supported runtime never takes).

      **Two fixes were written for it and reverted**, both unproven: cancelling a hidden object's
      target animation, and ordering the `ondatachanged` dispatch. Neither changed the outcome.

      **What is left is a policy question, not a defect.** These four MCV pages are *not* the
      `visible`-tagged sibling tabs `closeDisplacedPages` knows how to arbitrate: only
      `info.component.vis.full` declares `visible="0"`, while `cover`, `infodisplay` and
      `songinfodisplay` declare none and are meant to be on screen *together* — they are the File
      Info page. So sibling-exclusivity is the wrong rule here and must not be reached for.
      The open question is whether the `{6A619628}` page radio should be honoured at launch at all,
      given the skin's own startup activates File Info unconditionally 700 ms later. Winamp evidently
      never collides, which suggests it does not restore the visualization *into the panel* at start.
      Deciding that changes launch behaviour for all four variants and wants its own live QA.

      **Workaround today:** set the panel's page to anything but Visualization; the overlap needs that
      page stored to happen. Turning on *Open in Multi Content View (stretched)* does **not** set the
      page — verified — so the two settings are independent and the page is the one that matters.

---

### BB26

- [ ] **BB26. The file-info rating row draws as five dots, not stars.** Found live 2026-08-25 while
      closing BB4, on the base variant and on Light. `infodisplay.line.rating.stars`
      (`xml/player-normal-mcv.xml:256`) sits under the genre line and paints five small faint dots
      where the skin means star glyphs. Cause unmeasured — do not guess one; note only that its parent
      `infodisplay.line.rating` is declared `visible="0"` at `:396`, so "should this row be on screen
      at all" is part of the question, not settled before it.

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
