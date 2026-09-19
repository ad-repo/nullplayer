# Windows Media Player (`.wmz`) backlog archive

Closed entries moved out of [`WMP_TASKS.md`](../../WMP_TASKS.md) so the live backlog stays a list of
work that is still open. Every row below is preserved **verbatim**, including the evidence it was
closed on — a closed item is only worth keeping because of what it recorded about the corpus, and a
summarised one is worth nothing.

The live, reach-ranked backlog is [`WMP_TASKS.md`](../../WMP_TASKS.md); the `.wal` counterpart to
this file is [`docs/winamp-modern/backlog-archive.md`](../winamp-modern/backlog-archive.md). A
`.wmz` entry goes here, a `.wal` entry goes there.

## W176 — a skin opened on the nag panel it declares ahead of its player, 2026-09-19

**Closed 2026-09-19, accepted by the reporter.** The row as it stood:

| ID | Item | Reach | Notes |
|---|---|---|---|
| W176 | `WALL-E` presents its `upgradeView` nag panel as the player, and its real `mainView` opens beside it | **1 archive confirmed live, 2026-09-15**; the wider class is the 3 archives already named for declaring `upgradeView` ahead of their real view (`xsn_sports`, `Halo 2`, `T3-Skynet_Media_Player`) | Found while verifying W175, not from a report, and **not caused by it** — the dispatcher posts no `openView` at load at all, so the successor list is empty under the old `last` rule and under the new ranking alike and the walk falls through to document order either way. (Reasoned from the commands, not measured against a baseline build; a worktree at the parent commit would settle it.) `WALL-E`'s dispatcher is the corpus's only one that opens its player from its *timer* rather than its `onLoad`: `checkRemoteViewStatus()` calls `theme.openView('mainView')` on the first tick where `delayPop` is true, so at the moment the candidate walk runs the dispatcher has posted **no** view to go to and the walk falls through to document order — which reaches `upgradeView`, the "your Windows Media Player is too old" panel WMP never shows. Measured: `defaults delete NullPlayer wmpSkinViewID`, launch `-uiMode wmp`, and the window list is player 382x298 + `mainView` 392x298, with `wmpSkinViewID` persisting as `upgradeView`. The donor ranking in `SKILL.md` § *Every NullPlayer window in WMP mode* already refuses `upgradeView` when borrowing a **frame**; the candidate walk does not, and that is the smallest form of this fix. The second half is harder and should be decided first: **a player that arrives one tick late has no way to claim the app's window**, because the first view with a canvas binds it (W96). |

**The row's reach was one archive short and the corpus scan is the reason to keep this entry.**
Re-derived 2026-09-19 by splitting every `.wms` on `<VIEW` with `WMPTextDecoder`'s encoding rules,
over the 185 installed archives: **5 declare a notice view, not 4** — `Dreamcatcher` is the one the
row missed — and **every one of them declares it ahead of the view it means by the player**, which
is what makes a document-order fallback land on the nag panel rather than merely risk it:

| Archive | Notice view | Position | What follows it |
|---|---|---|---|
| `Dreamcatcher` | `versionView` | 1 of 8 | `upgradeView`, `mainView`, … |
| `xsn_sports` | `versionView` | 1 of 8 | `upgradeView`, `mainView`, … |
| `T3-Skynet_Media_Player` | `versionView` | 1 of 9 | `upgradeView`, `mainView`, … |
| `Halo 2` | `upgradeView` | 2 of 10 | `controlView`, `mainView`, … |
| `WALL-E` | `upgradeView` | 3 of 4 | `mainView` |

The fix is `WMPMainWindowController.startupCandidates`, which is the walk's seed list lifted out of
`reloadSelectedSkin` so the ranking is testable without a window: a notice view is refused as a
**seed** — from document order, where it now sorts last rather than being dropped, and from the
user's persisted `wmpSkinViewID`, because landing on one is how it came to be persisted and
honouring it there makes the defect survive its own fix. It stays reachable as a **successor**,
which is the only way the corpus opens one on purpose: `WALL-E`'s `preview.js` branches on
`parseInt(player.versionInfo)` and redirects to `upgradeView` for a player of version 7–10. We
answer `12.0.0.0`, so that branch is not taken and the panel is now unreachable in the corpus.

**The second half of the row needed no decision.** It asked how "a player that arrives one tick late
claims the app's window", since the first view with a canvas binds it (W96). With `mainView` ranked
ahead of the notice it takes the window at load, and the dispatcher's later
`theme.openView('mainView')` lands on a view that is already open, where `show` is a raise. Nothing
has to be taken away from anything.

**Verified live, one launch per skin from a deleted `wmpSkinViewID`:** `WALL-E` one window 392x298
(was player 382x298 + `mainView` 392x298, key persisting as `upgradeView`), `Dreamcatcher` 475x485,
`T3-Skynet_Media_Player` 317x330, `xsn_sports` 409x277 and `Halo 2` 327x294 — the last two plus the
panels their own `onLoadSkin` opens — and all five persisting `mainView`. `corona` is the control at
`vPlayer`, unchanged.

**One live report came in against this change and was measured rather than fixed: it was not a
defect.** `WALL-E`'s `mainView` orders its three system buttons **Windows-style** — minimize, full
mode, close, left to right at `305,4` / `333,4` / `361,4` — where macOS puts close leftmost, so
reading them left to right as close/minimize/maximize gives "the X to close maps to minimize and the
minimize maps to library toggle". `WMP_RENDER_CLICK` at each centre hits the button under it
(`btnMin`, `btnFull` → `command=toggleLibrary`, `btnClose`); the bitmaps are a dash on the left and
a red X on the right, as authored; and driven live the X leaves 0 windows with the process alive
while the dash leaves `AXMinimized=true` with 1. See `SKILL.md` § *Which control a click reaches*.

## W99 — a view resolved against a size nothing is drawn at, 2026-09-19

**Closed 2026-09-19, accepted by the reporter.** The row as it stood:

| ID | Item | Reach | Notes |
|---|---|---|---|
| W99 | A drawer's own toggle button drifts out from under the pointer once the view's timer runs | `xsn_sports` confirmed both live and headlessly; **every skin with a timer and a moved drawer is a candidate — count it** | Reported live 2026-09-09 as "it opens and closes right away, it is resistant to opening", and **reproduced against a baseline worktree at the parent commit, where it behaves identically** — so it is not W55, which only made it visible by correctly hiding a shut drawer's contents. `vidDrawerButton` in `xsn_sports/videoView` is drawn at `61,291` on the first frame and at `61,271` after `WMP_RENDER_SETTLE=2` runs the view's own 500 ms timer; a click at the first position returns `CLICK … MISS`, and a click at the settled one hits and opens the drawer to `4 widgets[slider×4]`. So the drawer works and the *target moves*. Twenty pixels, on a rebuild driven by a timer that only calls `htcpVid()` — which alpha-blends artwork and moves nothing — so find what re-resolves that subtree's geometry between ticks before assuming the handler did it. The old scripted-`view.height` theory is closed by W113; reproduce with `WMP_SKIN=…/xsn_sports.wmz WMP_RENDER_SETTLE=2 WMP_RENDER_PROBE=videoView`. |

**The row's own reproduction numbers were stale and the button never moved.** `vidDrawerButton` is
at `180,291` in every capture at every settle value. What moves is everything anchored to the view's
*bottom* — eight frame pieces, both drawer covers, `vidOutline`'s height and `vidResize` — 20 px
between frame 0 and the first timer tick. Looking for what re-resolved the drawer's subtree was
looking for the wrong node; the `EXPR` line had been printing the answer for the whole of Phase 5:

```
EXPR videoView/vid3_1.top: view.height-221 -> 195  live=175
```

Two evaluators, one expression, and the live one wins. **`->` is the initial resolver against the
canvas and `live=` is the script runtime's; a disagreement between them is this defect and there is
no other reading of it.** Corpus-wide, over the 4,679 expressions that depend only on
`view.width`/`view.height`, **809 disagreed**.

**It is two mechanisms sharing one symptom, and fixing either alone makes the other worse.**

1. **The expression pass runs before the handlers**, by design — a pane positioned off another must
   see the frame that pane lands at, not its markup — but the view's own size is the one input a
   handler can change out from under a pass that has already read it. `xsn_sports` authors
   `<view id="videoView" height="396">` and its `onLoad` → `checkVideoPlayerState()` writes
   `view.height = 416` whenever the player has nothing to stop, so the scene is built at 416 while
   `top="jscript:view.height-221"` still answers 175.
2. **The builder can refuse the assignment, and only the builder knew.**
   `canvas = resizeLimits.clamp(…)`, so a view declaring `minHeight` has a floor its own script
   cannot write through: `ALXMorph` is `<view id="videoView" height="357" minHeight="357">` and
   `onLoadVid()` assigns 316. The canvas stays 357 and the script goes on answering 316.

Fixing (1) alone and re-resolving against the *raw* assignment is not a smaller version of the fix,
it is the defect with more reach — measured over 20 archives it walked
`Back to the Future Trilogy/videoView` out to `x=-94` and `Plus! Professional/videoView` to `y=-8`.
**A collateral diff is counter-evidence; that sweep is what caught it before it shipped.**

**The fix.** `WMPScriptContext.perform` clamps the view element's own width/height to its
`minWidth`/`minHeight`/`maxWidth`/`maxHeight` at the end of the transaction — read the way
`WMPSceneBuilder.viewLimit` reads them, a script write first and then the markup literal, because
`WMPScriptViewPlan` seeds every authored attribute — writes it back, and re-resolves the geometry
expressions when it differs from the size the transaction opened at. `WMPScriptRuntime` reports that
clamped size as `viewSize` instead of the raw assignment, so the window, the next transaction and
the expressions all carry one number. A handler's own geometry write still wins twice over: the
runtime applies the transaction's mutations to the overrides *after* the expression values, and the
addresses it wrote are retired from the model commit.

**Reach, and why `xsn_sports` was the worst case to look at.** A view with an `onTimer` corrects
itself on the next tick, which is why the row read as a drifting button rather than as a broken
window. **217 corpus views across ~90 archives author this shape** — an `onLoad` that resizes its
own view over `jscript:view.width`/`view.height` geometry — and **146 of them have no timer at all
and never correct.** Reproduce the count by decoding each `.wms` as `reference/harness.md` requires
and matching `<view … onLoad=…>` against a `jscript:view.(width|height)` in its own body.

| corpus sweep, 179 archives / 630 views | base | fix |
|---|---|---|
| `view.width`/`view.height` expressions | 4,679 | 4,679 |
| …resolving against a size nothing is drawn at | **809** | **0** |
| nodes moved | — | 601, across 59 views in 39 skins |
| canvases changed | — | 0 |
| nodes gained or lost | — | 0 |
| negative origins | 19 | 19 |

**What it looks like.** `AlienMorph/visView` drew with its entire right-hand column missing — no
right rail, no close control, white gaps down the right edge — because every piece of it is
`left="jscript:view.width-175"`. It now draws a complete symmetric window. **That is W68's
"the Alienware family draws a shell", and this row is part of the answer to it**: `ALXMorph`,
`AlienMorph`, `AlienwareTeleport`, `Alienware Invader` and `Alienware_Darkstar_WMP11` all declare
`minWidth`/`minHeight` on views their own `onLoad` assigns through.

**One collateral diff that is recorded rather than explained.** Three `visView`s (`Dreamcatcher`,
`Harry_Potter_and_the_Chamber_of_Secrets`, `Xbox`) go from 2 widgets to 1. The lost one is
`<TEXT id="visEffectsText" value="wmpprop:visEffects.currentEffectTitle">`, which authors no size and
in the baseline hosted a `0x10` rect at `y=247` in a 245-tall view, printing `visible=none`. It drew
nothing before and draws nothing now, and commands and hit counts are identical in all three. The
same three views' `visEffects` goes from `353x240` clipped down to `291x218` to a clean `259x193` —
the visualizer sized for the window instead of for the size the script asked for, which is the same
shape as W235.

## W235 — a visualizer sized off a sibling's extent, 2026-09-19

**Closed 2026-09-19, accepted by the reporter.** Fixed by commit `c78f32f7` ("Follow the window
stretch with the visualizer inside it"), which was taken against `Compact` and closed this row as
collateral — the row was still open because nobody re-measured `NVIDIA` after it. The row as it
stood:

| ID | Item | Reach | Notes |
|---|---|---|---|
| W235 | **A visualizer sized off a sibling's extent keeps its authored size while that sibling stretches** | **1 archive confirmed live 2026-09-18 (`NVIDIA`), inside a shape 76 archives author — 149 `<EFFECTS>` extents read off a sibling with no arithmetic, 72 of them in an archive declaring a resizable view.** How many of the 72 actually mis-size is **unmeasured**, so this row is placed provisionally: `Compact` authors the same shape (`myeffect` off `svScreen`) and resolves correctly, so the population is the candidate set, not the defect count. Reproduce the count with the decoded scan in `skills/wmp-skin-guide/reference/harness.md` — a `.wms` is UTF-16 and `grep` goes silent on it | Reported 2026-09-18 as *"when you stretch nvidia the built in viz does not expand"*, with a capture: the green lightning sits at its authored ~390x175 in the top-left of a panel that has grown to fill the window. **`visFrame` is fine and is the black panel you can see behind it** — `<subview id="visFrame" width="jscript:view.width-90" height="jscript:view.height-214" horizontalAlignment="stretch" verticalAlignment="stretch">` grows exactly as authored. What does not is the child that reads it: `<effects id="visEffects" width="jscript:visFrame.width" height="jscript:visFrame.height" windowed="false" horizontalAlignment="stretch" verticalAlignment="stretch">`, which resolves to the extent `visFrame` had at the view's authored 285x301 rather than re-reading the grown parent. **It is not W227, and it is not the `Compact` spill fix that came out of W227**, and that was measured rather than argued: the same two-axis stretch (285x301 -> 487x502) was driven twice on one debug build, once with that fix's `WMPSceneBuilder` hunk in and once with that single file reverted, and the visualizer is at the identical size and position in both captures. Neither change moves it. It is also a different mechanism from that fix — there a *script-assigned* absolute was having the window's growth added to it a second time; here nothing is script-assigned at all. The question this row opens is evaluation order: the parent's stretch is applied when the parent is laid out, and a sibling read that resolves against the authored graph rather than against `geometries` cannot see it. **Nothing headless can see this one.** `visEffects` is gated behind `mainModeVis.visible`, so `WMP_RENDER_PROBE` reports `mainView` with no effects widget at any size — `WMP_RENDER_SIZE=900x900` on `NVIDIA` prints four widgets and none of them is it. It needs the live app with a track playing, per `live-ui-testing`. The other three `mainView` widgets do grow correctly at 900x900 (`metadata` 99 -> 714 wide), so the view's own stretch is working and this is the binding alone. |

**The row's "nothing headless can see this one" was wrong, and that is the reusable part.**
`visEffects` is gated behind `mainModeVis.visible`, which is `false` at load — but `visModeToggle()`
hangs off the main-mode button group's second mapping element, so one `WMP_RENDER_CLICK` reaches the
state and `CLICK … changed=[…]` prints the geometry of every node the toggle resolved. A gated
widget is not out of reach; it is one click behind a flag that was never tried. The measurement,
with `WMP_RENDER_SIZE` supplying the stretch (the button group is right-aligned, so the click moves
with it):

```sh
WMP_SKIN=…/NVIDIA.wmz WMP_RENDER_HOST=playing WMP_RENDER_SIZE=285x301 \
  WMP_RENDER_CLICK='mainView@193,95' swift test --filter WMPRenderDumpTests/testSweepsSkinOrCorpus
WMP_SKIN=…/NVIDIA.wmz WMP_RENDER_HOST=playing WMP_RENDER_SIZE=700x700 \
  WMP_RENDER_CLICK='mainView@608,95' swift test --filter WMPRenderDumpTests/testSweepsSkinOrCorpus
```

| canvas | `visFrame` | `visEffects` |
|---|---|---|
| 285x301 (authored) | 195x87 | 195x87 |
| 700x700 | 610x486 | 610x486 |

`610x486` is `700-90` by `700-214`, which is what `visFrame` authors, and the child reads it exactly
at both sizes. The mechanism that closed it is `c78f32f7`'s second half: `ownAuthoredSize` was taking
the runtime's own geometry override — this canvas's answer echoed back — as the alignment baseline,
so every child's stretch delta was zero. It now takes an override only when `scriptAssignedGeometry`
says a handler wrote it, and an authored `jscript:` binding falls through to the markup baseline it
should always have had.

**The live half was not re-driven by the closing session and did not need to be.** A synthetic
`winhelper drag` cannot drive this skin's grip: `mainResize`'s handler is `onMouseDown` →
`view.size('bottomright')`, the call arrives back asynchronously, and `discardStaleResize`'s
`pressedMouseButtons` gate correctly refuses an arm whose button is already up — so every posted
drag either moved the window or reached nothing, with `WMP_RESIZE_TRACE=1` silent throughout. That
is the tool's limit, not a defect, and it is why the reporter's own drag is what closed this.

**`W235` is stamped on unrelated code, and it is not this row.** `WMPMainView.swift` (the
stale-resize arm and the margin rule) and `WMPMainWindowController.swift` cite `W235` for the AppKit
edge-wedge work in commit `f5552068` — a third duplicate-ID collision after W196/W217 and W171/W218.
Those comments mean that defect, never this one.

## W195 — the `res://wmploc.dll` string ids, 2026-09-19

**Closed 2026-09-19** by commit `ac4af32c`, accepted live by the reporter. The row as it stood:

| ID | Item | Reach | Notes |
|---|---|---|---|
| W195 | 44 of the 50 `res://wmploc.dll` string ids draw as empty | **133 uses of 50 ids across 6 archives**, of which `WMPResourceStrings` names 9 (decoded scan, 2026-09-16) | The remainder are mostly *format* strings a skin builds a sentence from — `transport.js`'s buffering tooltip (`#2099`), its status strings (`#2077`, `#2078`, `#2063`) and the DVD chapter format (`#2086`) — plus the reception-quality tooltips (`#2079`-`#2081`, `#2092`). They are blank rather than wrong, which is where `theme.loadString` has always been. **Add a row to the table only when something in the corpus states the text** (a tooltip on the same control, a markup default the script replaces); the alternative is inventing Microsoft's wording, which was explicitly declined when this was opened. |

**The constraint was loosened when it was taken, and that is what made it closable.** The row had
stood on *"add a row only when something in the corpus states the text"*, which the opening session
read as requiring a literal restatement elsewhere. The reporter widened it — *"if you can figure out
the tooltip name with a high confidence from the element that is ok too"* — which turns a control's
own `onClick` and property bindings into evidence. Nothing else about the row changed.

**The census had been counting half the corpus.** Decoding all 185 archives and normalising to UTF-8
first is load-bearing: `netgen.wms`, `corona.wms`, `Corona.js`, `metadata.js` and `corona_tiny.js`
are UTF-16LE, and a byte-oriented `grep` walks straight past them. With that done the count
reproduces the row's own figure exactly — **133 literal uses of 50 ids across 6 archives**, plus 3
built at runtime from a computed id:

```sh
# from a directory of unzipped archives, UTF-16 files iconv'd to UTF-8
grep -rioa 'RT_STRING/#[0-9]*' . | sed 's|^\./||'
```

| archive | uses |
|---|---|
| `Revert (1)` | 47 |
| `Revert` | 41 |
| `Compact` | 22 |
| `corona` | 12 |
| `9SeriesDefault` | 12 |
| `circle` | 2 |

**The table went 9 ids to 34, and every row is earned one of two ways.** Either the corpus states
the wording — `#1811`'s own element carries `accName="Minimize"` in plain text beside the resource
URL, and five archives author `upToolTip="Close"` on the button `#1812` sits on — or the element's
binding leaves one reading: `#1809` is a `<slider>` with `min="0"`,
`max="wmpprop:player.currentmedia.duration"` and `value="wmpprop:player.controls.currentposition"`;
`#1845` is `min="-100" max="100"` bound to `player.settings.balance` with its own printed `<TEXT>`
label; `#2063` is the only argument `OnDisconnectTransport()` ever hands `ShowStatus()`. Authored
wording is copied **verbatim**, capitalisation included, which is why `3906`/`3907` read "Turn
Equalizer On"/"Turn Equalizer Off" while `1814`-`1817` are lowercase.

**Measure coverage by attribute, not by use.** The scene builder reads `toolTip`/`upToolTip`/
`downToolTip` and `value`, and the object model answers `theme.loadString`; it reads neither
`accName` nor `accKeyboardShortcut` nor `fontFace` nor `scrollingDirection` nor
`<theme author= copyright=>`. Of the 133 uses, **90 sit in an attribute that reaches the screen, and
those go 13 resolved to 58**:

| archive | before | after |
|---|---|---|
| `Revert (1)` | 2/47 | 33/47 |
| `Revert` | 2/41 | 27/41 |
| `Compact` | 11/21 | 13/21 |
| `9SeriesDefault` | 0/11 | 2/11 |
| `corona` | 0/11 | 2/11 |
| `circle` | 0/2 | 2/2 |

Five rows in the table (`2109`, `2130`, `3904`, `3905`, `3908`) and the two theme-metadata ids
(`1998`/`1999`) are **correct and invisible** — they appear only in attributes nothing reads. They
were kept, and marked as such in `WMPResourceStrings`, because the evidence for them is the same
evidence as for the rows beside them; they are not counted as coverage.

**Sixteen ids stay blank on purpose, and the reasons are three different reasons.** Format strings
fed to the skin's own `sprintf` (`#2099` buffering, `#2086` DVD chapter, `#2066` bitrate,
`#2077`/`#2078` DRM signature), where a wrong guess yields a wrong *sentence* rather than a wrong
word; wording with no anchor (`#2079`-`#2081`, `#2092`, picked off `nReceptionQuality` thresholds
that say what is *measured* and never what is printed; `#1273`/`#2150`; `#2097`, the second HDCD
mode beside `#2098`); and ids that are not labels at all, which is now **W236**.

**Four archives never decoded** — `bruteforce`, `Need_for_Speed_Underground`,
`QuantumRedshiftWMPSkin` (CAB) and `SplinterCellWMPSkin` (a zip `unzip` rejects). Raw `strings` finds
no `RT_STRING` in any of them, which is not conclusive under compression, so the 133 is a floor.

## W226 — a hidden element still has a place

**Closed 2026-09-18.** Accepted live on `Compact` by the reporter, the second half of the W225
session's report: *"when you stretch the window the visualization does not follow the stretch"*.

**The widget was never at fault, and the row said to measure that before ranking it.** A hosted
surface is an AppKit view laid into the scene's frame, so the question is whether the *scene* frame
grew. `WMP_RENDER_PROBE=all` with `WMP_RENDER_HOST=playing` — the vis pane is `visible="false"`
until playback starts, so a stopped host hosts no `myeffect` at all — at `422x378` and at
`700x600`:

| | own size | 700x600, before | 700x600, after |
|---|---|---|---|
| `WIDGET … effects id=myeffect` | `280x215` | `558x215` | `558x437` |
| `svVisual`, the pane it lives in | `320x240` | `598x`**`240`** | `598x462` |
| `svEffectsControls`, the viz strip | `top=220` | `top=`**`220`** | `top=442` |

The surface sat exactly on its scene frame in every run. The width followed the drag and the height
did not, which makes it two scene-side defects in `WMPSceneBuilder`, one behind the other.

**1. A geometry binding reads where the target *is*, and a hidden target was nowhere.** `Compact`
sizes its pane with `<subview id="svVisual" height="wmpprop:video1.height">`, and `video1` is
`visible="false"` for the whole of audio playback — `ShowVisualizations(true)` hides the video and
shows the effects. The walk returns on an invisible node before recording a geometry, so
`laidOutGeometry` had nothing to answer from and the read fell through to the static resolver, which
reads the markup: **240**, the height the window was *born* at. WMP lays hidden elements out and
answers the read from its live object model. A hidden node is now measured — geometry only: no
paint, no hit target, no widget, no children, and no entry in the resolved or unresolved tallies —
and **only when some other node in the view binds a `left`/`top`/`width`/`height` off it**
(`geometryBindingTargets`). Every other hidden node in the corpus leaves the walk exactly where it
did before.

**2. The alignment baseline was reading the resize back as if it were authored.**
`ownAuthoredSize` is what every child's alignment delta is measured from, and W225 put the geometry
overrides into it deliberately: a container a *handler* sized is a baseline, because the handler
stated that size on purpose. But `WMPScriptRuntime` writes an override for two different things —
a script assignment, and its own re-evaluation of an authored expression or binding — and the second
is only this canvas's answer echoed back. With `svVisual` reading 462 on both sides of the
subtraction the delta was zero, so the strip under the visualizer stayed at its authored `top` while
the pane around it grew. `authoredDimension` now takes an override only when
`overrides.scriptAssignedGeometry` says a handler wrote it, and re-reads the markup otherwise.
`jscript:` attributes are untouched: the static resolver evaluates them at the current canvas, which
is the same number `parseDimension` already had.

**Blast radius, measured.** Full 179-archive render sweep against a baseline worktree at
`3daa3cb7`: **706 RENDER-DUMP invariant lines identical, 0 differing**; **553 PNGs identical, 0
lost, 0 new, 1 differing**. The one is `Scooby-Doo_2/infoView`, and it is **not this change** — two
runs of the *same* build disagree about it, because the skin picks its character at random. That
archive is the corpus's one nondeterministic render and a sweep diff naming it alone is noise; see
`skills/wmp-skin-guide/reference/harness.md`. `swift test`: 2402 passed, 18 skipped, 0 failures.

**Still open from the same report:** W227, the window-edge band, which runs no skin resize bracket
at all.

---

## W232-W233 — the Disney report, 2026-09-18

**Two defects, one skin, and neither is what the ranking said was wrong with it.**
`Disney_Mix_Central/mainView` was the last unexplained row in `starved.tsv` — W68's own text named
it as where that row now starts, with *"draws its banner and five widgets and answers no click
anywhere"*. The `0 hits` is a **frame-0 phantom**, the third of its kind after `Batman Begins` and
`Alienware Invader`: `mainBack` is authored `visible="false"` and everything else hangs off
`wmpprop:mainBack.visible`, and `onViewTimer` runs a 31-frame intro (3 s delay, then 50 ms a frame)
before revealing the player. At `WMP_RENDER_SETTLE=6` the view goes `7 nodes / 0 commands / 0 hits`
→ `39 / 24 / 14`, and `WMP_RENDER_CLICK` dispatches play, prev, next, the time readout and
`toggleLibrary` correctly. **Settle a `0 hits` row before opening its markup, exactly as with a
`0 commands` one.**

The "five widgets" half was real, and the live report that followed was a second defect entirely.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W232 | A `<TEXT>` that states a string and no geometry was drawn at its parent's origin | **246 nodes across 42 of 185 archives** (decoded markup scan; `<text>` with a literal `value` and no `left`/`top`/`width`/`height` and no alignment). The 35 aligned readouts and the bound-value residue are outside it | **Closed 2026-09-18.** The Skins Factory house style declares **two** string subviews per view, and `isStringTableText` closed only the first: `locSub`'s tooltip constants have no `value` to measure, so they never resolved and never drew. The second holds the strings its script substitutes into WMP's own rip-CD readouts and those carry a literal `value` — `intrinsicTextSize` measured the glyphs, the node resolved at its parent's origin and all five sentences drew **stacked on one another at `0,0` over the artwork**. WMP draws none of them, for the reason the unsized `<PLAYLIST>` established the day before: a node stating no `width`/`height` and carrying no image is 0x0 in WMP's own arithmetic. `WMPSceneBuilder.isStringConstantText`. **Three guards, each a corpus population rather than a hypothetical**: the scene overrides are asked alongside the markup, because `Cablemusic`'s 34 station rows are `<TEXT id="pr0" value="">` with no geometry either and are placed entirely by `InitPrograms()` — a markup-only rule deletes both its drawers; an authored alignment is geometry, which keeps `Constantine`'s and `NVIDIA`'s `<text id="visEffectName" horizontalAlignment="center" value="test"/>` and the 35 skins that author one; and a `wmpprop:`/`jscript:` `value` is not a stated string, which is what leaves the 61-node bound-`<TEXT>` residue reported. **Census pair over 184 archives, `49f64442` → this change: 20 of 553 PNGs move, and 19 of them change nothing below `y=13`** — the top-left band a parent-origin string lands in, `x[0,247] y[1,13]` at the widest. The 20th is `Scooby-Doo_2/infoView`, which picks its character at random and differs between two runs of the same binary. **`hits==0` (84 views / 51 skins) and `commands==0` (79 / 49) are unchanged**, so no view stopped drawing or stopped answering a click. |
| W233 | Reopening the player after a skin closed it revealed a dead window | **24 corpus archives** author the windowless `controlView` dispatcher and the close button is in every one of them (W89's own count); the dead window is reachable by any other close of the player | **Closed 2026-09-18, live-only — no headless probe can see it, because the sweep has no window.** Reported on `Disney_Mix_Central` as *"when you go to the playlist you get trapped … if you close the playlist you do not return to the main window … when you bring the playlist back into focus the playlist is frozen"*. The X on the playlist's title bar is not a playlist control: it writes `theme.savePreference('exitView','true')`, the windowless dispatcher reads it back 100 ms later and posts `view.close()`, and W89 runs a dispatcher's commands against the player — so it closes the **player window**, which is what WMP's own close does. Measured: zero NullPlayer windows afterwards and the process still alive. The defect is the way back. The controller owns **one** `playerWindow` for its life; `closeViewWindow` tears the presentation down and orders that window out, but the `NSWindow` survives as the controller's `window`, so `WindowManager.showMainWindow` → `showWindow(_:)` ordered the corpse back in — the last picture the skin drew, no scene, no hit map, no timer, and `WMP_WIDGET_TRACE` recording **zero presents** after the restore. `showWindow(_:)` now rebuilds the session when the window it is about to reveal has no presentation behind it. **`reloadSelectedSkin` rather than a re-present**: the close discarded the script view, and the reload runs the skin's own `onLoad`, which is what clears the latched preference — `onLoadMain` writes `exitView` back to `false`, and without that the dispatcher's next tick closes the window the restore just rebuilt. A `playerWindowIsACorpse` flag gates it, because a launch is also a window with no presentation and rebuilding there cancels the session load already running; verified as exactly one `src=initial` present per launch. Same class as `pharaoh`'s recorded *"you can get trapped in the mini windows with no way back to the main window"*. Verified live end to end: playlist → X (window gone) → Windows > Main Window → the window returns presenting and the playlist toggle works again. |

**What W232 does to the ranking, and it moves the wrong way on purpose — the same shape as W75.**
`starved.tsv` is `unresolved / declared`, and five of `Disney_Mix_Central/mainView`'s ten declared
nodes were those string constants. With them gone the numerator is unchanged at 3 and the
denominator is 5, so the row goes **0.300 → 0.600 and to the top of the file** for a view that got
strictly better. Corpus starved views go 2 → 3 for that reason and no other. **The three it still
counts are the string subviews' own parents** — `locSub`, the anonymous one and a `<controls>` —
which is W231's question, not this one: a container whose every child is a string constant is a
string table too, and nothing has opened that yet.

**The process lesson, and it is W68's own rule turned on the row that states it.** W68 says a high
ratio ranks a view as *worth dumping* and only the PNG says whether anything is missing. Disney was
the last row nobody had dumped, and when it was dumped the ranked defect (`0 hits`) was an intro
running correctly while an unranked one — five sentences of Microsoft boilerplate painted across the
corner of the player — was in the same picture the whole time. **Read the PNG before believing the
column.**

## W207 — how a hosted window and a borrowed border share the space, 2026-09-16

**The open half of the donor class, closed the same week it opened.** Reported as
*"the interior is too small because the exterior border is very wide"*, and settled by the reporter
directly: *"the interior window … should be its full borderless size. then the border is added after
that and the final size is simply the full interior + border. whatever the border is. different
skins will have different width borders. this is ok."*

| ID | Item | Reach | Notes |
|---|---|---|---|
| W207 | A hosted window's *interior* shrank by whatever the borrowed frame's borders took, rather than the window growing around it | **Every window NullPlayer draws itself, under every skin that lends a frame** — 88 rings plus 32 panels of 185 archives. The borders differ by an order of magnitude across the corpus: `anemone`'s drawer is 173x145 of frame, `Halo 2`'s ring is 22/34/47/21 | **Closed 2026-09-16.** The window is **grown**: `HostedWindowBorderLayout` remembers each hosted window's interior in borderless points and sets the frame to `interior + border`, anchored top-left, `minSize` with it. One central rule, driven off `NSWindow.didResizeNotification`, `didBecomeKey` and `windowLayoutDidChange`, so a hosted window added later joins by appearing in `WindowManager.hostedBorderWindows` alone. The border comes from `WMPHostedFrameProvider.donorInsets`, which resolves a donor's four borders **without reference to any window** — the piece that was missing, because a 600x150 analyser can never render a frame carrying 173x145 of border and so could never learn its insets from one. Below that size the donor is answered nil and the window keeps palette chrome until the growth lands; nothing is drawn at a scale its author did not choose. Verified in the running app under `anemone` (all five windows 321x145 → 470x257, hole exactly the interior), `Halo 2` (interiors unchanged across the switch), `Ice`, and `corona`, which lends nothing and gives every window its own chrome and original size back |

**Three answers preceded it and each was reported wrong**, recorded so none is retried: composing at
the borders' own size left a **five-point hole** with the drawer squashed around it; refusing a
window that could not carry the borders took the border off everything but PeppyMeter; and a uniform
scale-to-fit sized so the hole keeps a third of each axis is the thin border the report was about.

**Two more were tried during this work and are wrong for reasons worth keeping.** Growing each window
to the donor's *declared floor* so a ring lands at 1:1 — `Ice` declares `min=585x308`, so every
hosted window was forced to 585x308 at once; that is the ring path's own recorded rejection
(*forcing every hosted window up to the donor's minimum moves windows the user placed*) confirmed by
test. And measuring the growth against the donor's **raw** margins instead of through
`reclaimingSideRacks` — `Ice`'s `plView` states a 157pt right rack, and growing by it put 157pt of
decorative artwork on every window's right edge with nothing in it.

**Three defects inside the rule itself, none visible in a screenshot or a `HOSTED-FRAME` line**, all
found with `WMP_BORDER_TRACE` and all worth knowing before touching this again:

1. `apply()` ran once, when the skin landed, and every window opened afterwards missed it — the trace
   was simply empty. Opening a window now posts a layout change and makes it key; both are watched.
2. Reading a window's interior back as `frame − donorBorder` made every window a **fixed point of its
   own rule**: Cava opens 321x145, `anemone` lends 173x145, so the interior came back `148x0`, the
   target came back 321x145 — the size it already was — and nothing ever grew. The interior is read
   against the border the window is **wearing** (`hostedSurfaceFrameArtwork(for:)?.metrics ?? fallback`),
   which is the same question the view's own `draw` asks.
3. The docking pass settles a window a point off our own `setFrame`, in a `didResize` outside the
   applying flag — read as the user's, it re-derived the interior and the analyser came back
   `387x219` where its siblings came back `321x145`. Targets are rounded, a 1pt landing is accepted,
   and a resize matching the last applied size is not the user's. A persisted interior is written
   only when measured against a border we are certain of, or it outlives the session and comes back
   next launch as the size the user gets.

## W208 — the Ice report, 2026-09-16

**Reported as two defects in one screenshot — *"this is the built in ice eq and playlist. both are
broken"*, then, on the playlist, *"the playlist somehow doubling the right side border is a very
weird way"*.** That second remark is what found the cause: the right border was not *missing*, it was
being drawn **twice**. Both closed the same day, and both turned out to be the same rule applied in
two more places — **artwork draws at its own size; the box the skin declares around it is a box, not
a scale.** The engine already stated that for a `<BUTTON>`'s `image`; it did not hold for a
`CUSTOMSLIDER`'s filmstrip cell or for a `backgroundImage` off its stretch axes.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W208a | A `CUSTOMSLIDER`'s selected filmstrip cell was drawn **stretched to the node's declared box**, and `borderSize` exists precisely to make that box bigger than the art | **17 of 318 `customSlider` paints, across 4 of the 75 skins that author one** — `Ice` 10, `Stars and Stripes` 5, `Nautical` 1, `Halloween` 1. The other 301 already had cell and frame the same size and are untouched by construction (`min(frame, cell)` is identity there) | **Closed 2026-09-16.** `Ice` authors ten equaliser bands as `width="20" height="140" borderSize="20"` over a 5x65 `positionImage`, so every cell was blown up 4x across and 2x down — which drew the band grid a second time below the frosted panel and over the window's own bottom frame, and is what the screenshot showed. The fix is the rule already written beside it in `WMPSceneBuilder` for the no-strip case — own size, anchored top-left, capped by the frame — extended to the strip cell, which is artwork too. Reproduce the population with the `crop=` vs `frame=` comparison on `WMP_RENDER_PROBE=all` over the corpus. All four skins render better: `Stars and Stripes`'s volume bar is a crisp row of blue segments instead of a 13px smear, `Nautical`'s volume track is an undistorted curve. Confirmed in the running app on `Ice`'s own equaliser |
| W208b | A `backgroundImage` was stretched onto an axis the skin never asked it to stretch on, so a frame whose pieces are anchored at different offsets came apart into **two ragged right edges** | **93 of 2,959 non-tiled background paints whose bitmap could be read, across 29 of 185 archives** — `Ice` 17, `STALKER` 13, `Halloween` 11, `AlienMorph` 10, then a tail of 3s and 2s. Of 554 corpus view renders, **35 changed** | **Closed 2026-09-16.** `backgroundImage` fills its frame because a `stretch`-aligned subview grows with a resizable window and its tile covers the delta — still true, which is why both `stretch` axes and `backgroundTiled` stay exempt. What is left is a box the skin made larger than the art on purpose. `Ice`'s playlist is the case: its four right-hand pieces are anchored at four different offsets (`view.width-163/-154/-165/-150`) and declared four boxes wider than their bitmaps, so stretched they ended at **487, 468, 468 and 483** and the border split into two edges with the corner blob overhanging the tile; drawn at their own widths **all four end at 468**, the single edge the skin drew. The rule's first shape was `min(box, art)` and it still squashed the other half of the population — `Vid-topleft.bmp` is 43x61 in a 62x52 box, so `min` drew it 43x52 and the corner's curve stopped meeting the left tile, a step that reads as a detached side panel (*"left window side panel is wrong"*). It is the art's **own** size now: **70 of 2,961 paints across 13 skins** are on the larger-than-its-box side, they overflow into the clip they already inherit, and re-rendering the corpus moved only 14 views — `Halloween`, `STALKER` and `AlienMorph` carry 57 of those 70 paints and none of their renders changed at all. Every one of the 35 changed views was rendered and compared against its baseline: `AlienMorph`'s videoView loses a stray black slab hanging under its bottom bar, `TDK`'s playlist module is visually identical, `Ice`'s playlist closes into one clean border with the resize grip in its corner. Confirmed in the running app |
| W208c | A ring piece is chosen by **alignment alone**, so a skin's own edge-anchored *button* competes for a corner slot and wins it whenever the author declared it first | Ring roles are filled from eight alignment pairs across every corpus skin that lends one — **88 of 185 archives**. The fix costs none of them: all 88 `HOSTED-FRAME` lines are byte-identical either side of it | **Closed 2026-09-16.** `Ice` writes `<subview id="Plshuffle" horizontalAlignment="left" verticalAlignment="Bottom" backgroundimage="Pl-shuffle.bmp">` — 26x24, wrapping a `<Repeatbutton>` — six nodes before `Vid-bottomleft.bmp`, and first-declaration-wins handed it the bottom-left corner. Every NullPlayer window wearing that ring got the skin's shuffle glyph hanging outside the frame's own curve, which is both wrong to look at and a lie about what the glyph does. A candidate carrying **transport** is now refused, which is the ring's half of the rule the panel path already applies (`carriesTransport`, `Erektorset`). **Refusing anything *clickable* was tried first and is the wrong rule**: it cost 7 of the 88 rings, because a window's own resize grip and close box are plain `<button>`s wrapped in edge-anchored subviews and they are frame furniture — `Ice`'s own bottom-right corner art *is* its resize grip. The `HOSTED-FRAME` line cannot see this defect (it reports the ring's count and the client hole, not which bitmap filled a slot); `WMP_HOSTED_FRAME_DUMP` is what shows it |

**What this did not close, measured so it is not re-derived as a defect.** `Ice`'s `plView` still
presents a **585x308** window around **468x304** of art, because its canvas is `clamp(width=383)`
against `minWidth="585"`. That is not this skin's bug and not a sizing bug: over the corpus,
**200 of 554 view renders leave more than 30pt of empty canvas on the right or bottom** — `Israeli`
538, `Plus! Hard Boiled` 366, `Ocean` 387 — so a view declared larger than its art is the corpus
norm, and a rule that shrank a window to what it paints would move a third of it. Two readings were
ruled out on the way and neither is worth retrying: building at the authored width instead of the
clamped one (the shortfall is linear with slope 1, so **no** canvas size closes it), and sizing the
window to its painted extent (the 200 above).

**The instrument that found it.** The alpha bounding box of a view dump —
`WMP_SKIN=…/Ice.wmz WMP_RENDER_DUMP=<dir> swift test --filter WMPRenderDumpTests/testSweepsSkinOrCorpus`,
then compare `getbbox()` with the image size. `plView` came back 487x304 of 585x308 before, 468x304
after. Nothing in `HOSTED-FRAME` or a screenshot separates "the border is missing" from "the border
is drawn twice, 19pt apart"; the per-piece `frame=` on `WMP_RENDER_PROBE=all`, read against the
bitmaps' own widths, is what did.

## W205-W206 — the anemone report, 2026-09-16

**Reported as two defects — *"anemone skin has a problem with the visualization outside the skin and
the playlist/eq buttons do not work"*.** Both closed the same day; `anemone` has a dossier
(`skills/wmp-skin-guide/reference/skins/anemone.md`).

| ID | Item | Reach | Notes |
|---|---|---|---|
| W205 | A windowless `<EFFECTS>` confined by a **sibling backdrop** was confined by nothing, so the visualizer drew outside the skin | **1 of 185 archives** — `anemone`. The population of a childless keyed container beside an `<EFFECTS>` is 4 archives (`anemone`, `Mandalay`, `Vario`, `Military`) and only `anemone`'s backdrop is two-toned; corpus-wide, 4 of the 2,531 widgets the sweep places carry a `mask=` and the other 3 are the pre-existing `Plus!` ones | **Closed 2026-09-16.** `anemone`'s `<EFFECTS>` is a child of the `<VIEW>`, which has `backgroundColor="none"` and no artwork, so neither the container rule (W147) nor `groundShape` (W174/W198) had anything to read — and its own player art **cannot** be read as a shape: `background.bmp` keys the lens hole and the matte outside the anemone in the same `#00FF00` (19,433 px of hole exactly coincident with the lens, 30,943 of matte), which is the W174 hazard verbatim. What states the shape is the sibling immediately behind the surface — `<subview id="blback" zIndex="-1" backgroundImage="blback.bmp" transparencyColor="#00FF00">`, 239x187 in **exactly two colours**: 19,433 px of black lens and 25,260 of key. `WMPSceneBuilder` now takes the **nearest sibling drawn behind** an `<EFFECTS>` as its region mask when that sibling is a shape mask rather than a picture, and `Mandalay` holds both halves of that rule down: its `<effects zIndex="-2">` has `displayback` (5,691 colours, a picture) directly behind it at the same rect and two-toned `black1.bmp` five layers further back at `zIndex="-7"`, so taking any two-toned sibling would clip its visualizer to a 135x204 strip while taking the nearest finds the picture, which `isShapeMask` rejects. `WIDGET myview/5 effects id=visEffects frame=39,37 240x190 … mask=blback.bmp@39,38 239x187 keys=#00FF00` |
| W206 | A `sticky="true"` button's latch was the artwork's state and never the script's, so the corpus's drawer idiom could not open a drawer | **`anemone`'s two drawers are the reported case**; the idiom is `plb.down`/`acb.down` read inside the handler the same click raises | **Closed 2026-09-16.** WMP flips a sticky button's `down` on release **before** it raises the `onClick`, and `anemone` reads it straight back: `onclick="setVisibility('openPlaylist')"` over `if(plb.down == true){…open…}else{…close…}`. The latch lived only in `WMPInteractionState`, so `plb.down` answered its authored value on every press, the handler took its `else` branch every time, and neither drawer could be opened while both buttons drew themselves down. `WMPScriptRuntime.setWidgetDown` commits the pointer's latch into the live element **and** as an override, in the same task and ahead of the handlers (`WMPMainWindowController.stickyLatch`); the override is mirrored back onto the artwork after the transaction, so a handler that clears the latch by name — `setVisibility('closePlaylist')`, raised by the × *inside* the tray — un-lights the player's own button instead of leaving it lit over a closed drawer and inverted for the next press. `WMP_RENDER_CLICK` drives both halves: `plb.down=true playlisttray.visible=true viewSize=635x268`, then `after: 2 widgets[effects×1 playlist×1]`. The probe's own `drive()` keeps the same latch, because without it a headless click reproduced the defect rather than the behaviour |

## W199-W200 — the pharaoh report, 2026-09-16

**Reported as three defects — *"pharoh skin has 3 issues first is w199 the second is you can get
trapped in the mini winodws with no way back to the main window. also no visulixation displays"* —
and it is two.** The first and third are one rule: a container's `backgroundColor` fill was painted
as a bare rectangle under its own colour-keyed artwork, so it filled in both of the holes that
artwork cuts, and the two mean opposite things — the `clippingColor` matte is *outside the window*
and the `transparencyColor` hole is *where the visualizer shows through*. The second is a different
rule with the same shape as W175: `theme.openView` opens a window beside the opener and leaves the
opener alone, and a view with no canvas had its window-scoped commands run against the opener
instead. `pharaoh` has a dossier at `skills/wmp-skin-guide/reference/skins/pharaoh.md`.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W199 | A container's own `backgroundColor` fill is not clipped by its own key colours, so a skin's window is a rectangle where it should be a silhouette **and its visualizer is buried** | **10 nodes in 9 archives** — a container declaring a `backgroundColor` other than `none`, at least one key, and a background image: `Asimov_Radio`, `Nautical`, `anime`, `aoe`, `bluegrid`, `cerulean`, `claw`, `gadget`, `pharaoh` (twice). Measured 2026-09-16 over the 185 installed archives with a `WMPTextDecoder`-shaped decode (158 UTF-16, 146 cp1252, 89 UTF-8, 9 UTF-8-BOM). **Five of them hang an `<EFFECTS zIndex="-1">` under the keyed hole** — `aoe`, `bluegrid`, `claw`, `gadget`, `pharaoh` — each rect within 2 px of the hole's own bounds, and every one of the five rendered a fully opaque rectangle with no visualizer in it | **Closed 2026-09-16.** **A container's fill and its background image are one layer, and the container's keys apply to the composite** — which is what `backgroundColor="none"` already got by having no fill at all. `WMPSceneBuilder.backgroundFillMask` emits the fill inside a `WMPSceneClipMask` of the node's own artwork keyed by `clippingColor` **∪** `transparencyColor`, and `pharaoh` states the control inside its own archive: `vRos` is the same markup with `backgroundColor="none"` and it clipped correctly throughout (1,462 transparent px, exactly `rosetta.bmp`'s `#FF0000` count). `sSphinx` is the same markup with `backgroundColor="black"` and rendered **0 transparent px of 99,600** — `sphinx.bmp` carries 53,252 px of `#FF0000` and every one came back black. **Both keys, unlike `groundShape`, and the difference is the point**: that one answers *where the window is* and must never read a hole as a matte (`Plus! BubbleSkin`, W174); this one answers *where the composite is opaque*, and there a hole is as transparent as the matte around it. That second half is the whole of the "no visualization" report — `pharaoh`'s surface was hosted and running the entire time (`VisualizationGLView: Setting up ProjectM with viewport 174x148`, which is its 87x74 rect at 2x) under 1,608 px of black fill in exactly the `#FF00FF` apex. Verified live with a track playing: **1,595 of those 1,608 pixels change between two captures 0.7 s apart and 0 of the 87 artwork pixels do.** **The guards are `clipMask`'s and they keep their counter-evidence**: untiled and authored at the node's own size, so `Gorillaz`'s 50x28 `#33CC66` swatch is still a ground rather than a shape (143,248 px, the corpus's only total loss). `isShapeMask` is deliberately *not* required, for `groundShape`'s reason — this artwork is a picture with keys cut out of it, which is exactly the population that guard excludes — so `YIL!OMA2K` is untouched: it declares no `backgroundColor` beside its `clippingColor` and is not in the population at all. **`cerulean` was a named exemption and is now one of ten**: `isCeruleanFace`, a one-skin predicate matching `cerulean.wms` + `face.bmp` + `#9AACDB`, whose comment asserted the same pattern was *"intentional in skins such as Claw, Gadget, and Pharaoh"*. It is not, and the general rule subsumes it — cerulean's PNG is byte-identical across the change while its command count goes 12 → 13, which is the one invariant line the sweep moves. **Corpus sweep, 184 archives / 553 images: 5 images changed and each diff is exactly its skin's matte count** — `pharaoh` 53,251 (of 53,252 `#FF0000`, the odd pixel overdrawn by artwork), `gadget` 27,318, `claw` 22,217, `bluegrid` 19,200, `aoe` 8,318. The sixth, `Scooby-Doo_2/infoView`, is the sweep's documented nondeterministic image and is in the counter-evidence table for that. `WMPContainerFillClipTests` pins the rule and both guards. |
| W200 | A windowless view opened by `theme.openView` ran its window-scoped commands against **the opener**, so a ghost redirect replaced the player and a ghost close closed it | **2 of 185 archives** author an `openView` target with no canvas — `pharaoh`'s `vGhost` and `vGhostAutoDetect` (`width="0" height="0"`) and `cyberchannel`'s `playView` (no size, no background image). Scan of every `openView`/`openViewRelative` target resolved against its own `<VIEW>` declaration, same decode as W199 | **Opened and closed 2026-09-16.** `theme.openView` opens a window beside the opener and leaves the opener alone (W90); `theme.currentViewID` replaces the calling window's view. A view with no canvas has no window, and `loadView`'s windowless branch ran *every* command it posted against `existing ?? opener ?? player` — correct for the host-level ones and wrong for the three that are about a window. `pharaoh` states both failures: its transport's *Audio controls/Playlist/Video* button calls `theme.openView('vGhostAutoDetect')`, whose `onLoad` writes `theme.currentViewID='vRos'`, and the redirect landed on the player — **the 400x249 sphinx became the 197x194 rosetta panel**, whose own `CloseRos()` then called `vRos.close()` on the app's only window. Driven live before the fix, two clicks left the process running with **zero windows**. And it survived a relaunch, which is why the reporter could not get out: `OnLoad()` opens `vGhost` on every launch and its `onLoad` reads a preference the skin itself saves — `if(theme.loadPreference('paneOpen')=='true')theme.currentViewID='vRos';else view.close();` — so with `paneOpen` false the player was closed before it was ever seen, and with it true the player became the panel. Both branches, every launch. `WMPMainWindowController.redirectedToOwnWindow` rewrites `setCurrentView` to `openView` and drops a valueless `closeView`/`minimizeWindow`, and it applies **only when `existing == nil`** — a view that becomes windowless in its own `onLoad` (`Halo 2`'s `previewView`) is reached by a switch, has a window, and is unchanged. `theme.closeView('name')` is untouched: naming a target is not the same as meaning your own, and 84 archives call the named form. Verified live: the transport button now opens `vRos` as a second 197x194 window beside the 400x249 player, and its × closes only itself. `WMPWindowlessSuccessorTests` holds all three halves. |

## W198 — the Cerulean visualizer report, 2026-09-16

**Reported as *"the visualization is sticking out of the right side of the face by a few pixels … I
have seen similar on other skins"*, and the reporter was right about the second half.** One rule was
missing, not one skin: a hosted `<EFFECTS>` surface was confined by the container's *shape*
(`WMPWidgetRegionMask`) or by the artwork drawn *over* it (`WMPWidget.commandSplitIndex`), and by
nothing at all to the window's own silhouette.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W198 | A hosted `<EFFECTS>` surface was not confined by the window's own shape, so a rect that overhangs the silhouette painted outside the skin | **6 of the 96 `<EFFECTS>` the corpus sweep places across 84 archives** overhang their container's `clippingColor` region — `raveworld` 4,939 px, `Plus! Professional` 3,550 (faded shut, so not hosted), `pharaoh` 1,524, `digitaldj` 113, `Headspace` 106, `cerulean` 104 (`WMP_RENDER_PROBE=all` over the 185 installed archives, `offshape=`) | **Closed 2026-09-16.** Cerulean confines its visualizer by **paint**: `face.bmp` is drawn over the surface through `commandSplitIndex` and the eye is a `#FF00FF` hole in it. But paint can only occlude where the window exists, and `face.bmp`'s last three columns inside the `<EFFECTS>` rect are `#FF0000` — its `clippingColor`, pixels the skin cut out of its own silhouette. Nothing is painted there, so nothing hid the surface. Measured live before the change: **104 opaque pixels at x 218-220, y 204-253** of the 237x412 window, every one a pixel `face.bmp` marks clipped; after, **0**, with the lens intact at 4,264/4,264. **The shape was already computed and already used for one thing.** `WMPSceneBuilder.groundShape` — `clippingColor` only, never `transparencyColor`, for the reason W174 states — is what `WMPEffectsGround` is painted through, so the black ground under the visualizer was clipped to the window and the visualizer drawn on top of it was not. It now rides on the widget as `WMPWidget.clippingShape` and `WMPEffectsSurfaceView` clips to it **and** to `regionMask`, intersected: a skin can state either, both or neither. `Plus! Professional` states both with the same file and the same key, so it is unchanged. **Counter-evidence, and it is `pharaoh`.** Of the six, five cut only pixels the rendered scene leaves fully transparent (cerulean 104/104, digitaldj 113/113, Headspace 102/106, raveworld 4,827/4,939) — proof the surface was leaking outside the window. `pharaoh` cuts 1,524 px the scene paints **opaque**, because `<subview id="sSphinx" backgroundImage="sphinx.bmp" backgroundColor="black" clippingColor="#FF0000">` fills its whole frame black and that fill is not clipped to its own shape. Its `<effects>` sits in a `#FF00FF` pyramid apex surrounded by `#FF0000` sky, so the visualizer is now correctly confined to the pyramid and the sky it used to cover is left showing the unclipped black. **That black is a separate, still-open defect** — a container's `backgroundColor` fill should be clipped by its `clippingColor` region, which would give pharaoh a pyramid-shaped window instead of a rectangle — and it is deliberately not fixed here: widening a fill clip corpus-wide is the change `Gorillaz` and `YIL!OMA2K` hold down. **`offshape=` is the field that ranks this class and it is new** (`WIDGET` line, `reference/harness.md`): the leak is *inside* the widget's own rect, so `WMP_RENDER_APPKIT`'s `outside=` reads a clean 0 on every one of the six. |

## W196-W197 — the NVIDIA playlist report, 2026-09-16

**One report — *"the playlist library is opening very small size now and possibly distorting the
aspect ratio"* — and it was two unrelated defects, neither of which any headless probe could see.**
`WMP_RENDER_CLICK` answered `viewSize=700x480` on the playlist toggle throughout: the engine
computed the right size and the *window* never wore it. Both were found by driving the debug build
with `CGEvent` and reading the window list either side of the click, which is the same loop W186/W187
needed and for the same reason — a sweep has no window.

The reporter's screenshot was the whole diagnosis once it was measured: 582x614 pixels on a retina
display is a 291x307-point window, and the layout inside it was the 730x574 one scaled unevenly onto
it. A picture that does not match its frame is AppKit stretching, not a layout fault, and that split
the report in two before any code was read.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W196 | A view's resize limits were read from the markup only, so a mode that raises its own floor never raised it | **3 of 185 archives** write a view limit from script — `Compact`, `Disney_Mix_Central`, `NVIDIA` — and **all three author every name they write** (decoded `.wms`+`.js` scan, 2026-09-16); the nine-skin Skins Factory playlist family is the reach on screen | **Closed 2026-09-16.** `minWidth`/`minHeight`/`maxWidth`/`maxHeight` are a resize *contract* and not a layout, and a multi-mode skin moves them as it switches: `NVIDIA`'s `setModesMinWidth('playlist')` raises the floor 285x301 → 700x480 before `autoSizeView` grows the window to it, and puts it back for audio mode. `WMPSceneBuilder` read `literal(view, …)`, so the floor stayed at the audio mode's for the whole session and the playlist could be dragged to a quarter of the size its own layout needs — `plListBoxSub`, `plExtraInfo`, `plNameText` and three more resolve to negative dimensions there, which is the pile-up in the screenshot. They arrive in `overrides.properties` and not `overrides.geometry`, because the runtime routes only `left`/`top`/`width`/`height` to geometry and a limit is not a frame. **`WMPObjectModel.writeElement` had a second half of the same hole**: a write to one of the four committed as a mutation only where the markup happened to author the same attribute, so the rule was about the markup rather than about the property. The corpus number above is what says closing it moves nothing today. |
| W197 | The window resize a script asked for was lost with the task that carried it | engine-wide; certain rather than unlucky on any skin with a short view timer — **442 `timerInterval`/`onTimer` uses across 91 archives** | **Closed 2026-09-16, live-only.** W190 moved `setWindowSize` to after the render so the frame and the picture change together, and that opened a window between the two points where the assignment lives only on `presentation.scriptViewSize`: recorded before the build, applied after it. A transaction cancelled in between loses the frame and keeps the size. `NVIDIA` holds `timerInterval="100"` and its playlist switch takes ~45 ms to build and render, so the tick that lands inside is a certainty — traced as `enter assigned=730x574` → `CANCELLED` → every later transaction rebuilding a 730x574 picture and presenting it into the 285x301 window. The test is now the canvas against the **window**, not the assignment against nil, so any later transaction recovers the frame; the rebuild-skipping guard also requires the window to match the presented canvas, or a quiet tick would leave it stranded. **Do not narrow this back to `assignedWindowSize != nil`** — that is the version that shipped, and the race is the defect. |

**What was ruled out, and it cost the most time here**: the white Media Library panel in the same
screenshot, reported alongside. It is **the skin's own artwork** — the middle band of
`pl_left_tile.png`, 185x11, tiled down the left column — and not a control this engine draws.
Suppressing the `<LISTBOX>` background fill in the scene and having the empty control paint nothing
were both built and both backed out: neither moved a pixel, because the box is white in the bitmap.
It is white on screen because it is **empty**, which is W66 and still open.

**The process lesson**: W197 reproduced only as a race, and the instrument that showed it was four
`NSLog` lines around the transaction — enter, early-return, cancelled, applied — read against the
window list. A cancelled task returns silently, so every probe either side of it reported a healthy
engine, and the first two attempts at the fix were reasoning about which size to pass rather than
about which of them had ever run.

## W184-W192 — the Compact drawer report, 2026-09-16

**One report — *"drawer controls don't work in compact wmp skin"* — and it was nine unrelated engine
defects.** `Compact.wmz`'s two drawers are its playlist (right) and its settings pane (bottom); every
one of the faults below sat behind the one before it, so each was only visible once its predecessor
was fixed. **Three of them no headless probe could see**, and the reason is worth keeping: a render
dump rebuilds the scene straight from the script's overrides, so the canvas grows there whether or
not the *window* ever moves. W186 in particular rendered perfectly in every capture while doing
nothing whatsoever on screen. The instrument that found each one is named in its row.

The reporter drove the app throughout and the session's shape is the lesson: eight of the nine were
found by a `WMP_RENDER_CLICK` on a decoded coordinate or by driving the debug build with `CGEvent`
and reading the window list, never by a sweep.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W184 | WMP's `event` object is undefined, so a handler that reads it dies on its first line | **84 of 185 archives** name `event.*` (decoded script scan, 2026-09-16); `screenWidth`/`screenHeight` is 6 archives and only `Compact` depends on it — the five Plus! uses sit behind a short-circuiting `player.dvd.isAvailable("dvd") &&` | **Closed 2026-09-16.** `TogglePlaylist`/`ToggleSettings` open `view.maxWidth = event.screenWidth` *before* they grow the view, so `ReferenceError: Can't find variable: event` took the growth and the slide with it and the click read as inert. `WMPObjectModel.readEvent` answers `screenWidth`/`screenHeight` from the window's own display (a fixed 1920x1080 headlessly, so a corpus sweep reads the same on every machine) and `shiftKey`/`ctrlKey`/`altKey` from the dispatching event. **`keyCode` and the pointer coordinates stay unrecognised on purpose** — 433 uses across 79 archives, and this engine dispatches no `onKeyDown`, so answering `0` would tell every one of those handlers a key it never saw was pressed. Found with `WMP_RENDER_CLICK` + `WMP_CALL_TRACE`. |
| W185 | A script-assigned alignment is anchored at the markup instead of at the assignment | **1 of 185 archives** assigns an alignment from script (20 writes, `Compact`; decoded scan of `.wms`+`.js`, 2026-09-16) | **Closed 2026-09-16.** WMP re-measures an element's margins the moment its `horizontalAlignment` is written — which is the whole point of the `SetAlignment(false)` → grow → `SetAlignment(true)` dance in both drawer handlers. Measured from the authored size instead, `playerView` (`stretch`) took the full 179 px the drawer had just added and covered it: *"the drawers do not slide out, they change the size/shape of the player"*. `WMPSceneOverrides.scriptAssignedAlignment` records the canvas each write happened at — and the canvas **moves within the transaction**, so the write after `view.width += rightMove` anchors at the new size. |
| W186 | A one-axis resize was not a resize, so the window never moved | `Compact` (both drawers); the rule is engine-wide | **Closed 2026-09-16, and no headless probe could see it.** `assignedViewSize` demanded an override for *both* `width` and `height`; the playlist drawer writes only width and the settings drawer only height, so it returned nil and the app never resized the window. Every capture showed the drawer open because the builder takes the canvas from the overrides regardless. The axis the script did not touch is now the window's current one. Found by driving the debug build and reading `CGWindowListCopyWindowInfo` before and after the click. |
| W187 | A script transaction rebuilt at the last scene's canvas, not the window's | engine-wide | **Closed 2026-09-16, live-only.** Stretch the window and shrink it back and a transaction still in flight across the resize — or the view's own 4 s timer afterwards — re-presented the pre-resize canvas *and* stored it as `activeScene`, so every later transaction read the stale size back and the window never recovered: `Compact` drawn 750 wide inside a 601 window with its body over the drawer. The rebuild takes the window's current content size, with the script's own assignment winning only when that transaction made one. |
| W188 | The cumulative overrides re-asserted a stale axis and undid the user's stretch | `Compact`; engine-wide rule | **Closed 2026-09-16.** `overrides.geometry` is cumulative — the playlist drawer's 601 stays there for the session — so W186's fallback pulled it back whenever a *later* handler touched only the height. Reported as *"the right side drawer keeps stretching the window and releasing the stretch"*. The size now comes from **this transaction's own mutations**, with the window's current size for the other axis. |
| W189 | `res://wmploc.dll/RT_STRING/#<id>` was drawn as text | **133 uses of 50 distinct ids across 6 archives** (decoded script scan, 2026-09-16) | **Closed 2026-09-16.** `Compact` labels its settings tab and both on/off switches with strings from Windows' own resource library; the URL itself was drawn — 200 px of it in a box authored 110 wide for the word *On*, running out under the SRS logo. Reported as *"the srs text is misaligned"*, and **the misalignment was the string, not the layout**. `WMPResourceStrings` resolves the ids the corpus itself names (the play/pause tooltip and accName either side of `transport.js`'s image swap, the three settings tab titles, the On/Off pair) and answers the empty string for everything else, which is what `theme.loadString` had always answered. Wired into all three routes a skin reaches them by: a readout's `value`, a tooltip, and `theme.loadString`. **Add a row only when something in the corpus states the text** — the alternative to blank is invention. |
| W190 | The window was resized ahead of the picture that fits it | engine-wide | **Closed 2026-09-16, live-only.** `setWindowSize` ran right after the transaction, so AppKit stretched the old image into the new frame until the render landed: the player ballooned and snapped back every time a drawer opened or closed. Reported as *"a big UI flash when the drawer opens"*. The frame is now set in the same main-actor turn as `present`. Verified with staggered `screencapture`s at 60 ms across the transition — the first frame at the new width is already the correct layout. |
| W191 | `<RETURNBUTTON>` does nothing, so the library is unreachable from the skin | **19 uses across 15 of 182 archives** (`wmp_markup_census.sh`, 2026-09-16); **15 of the 19 author no `onClick` at all** | **Closed 2026-09-16.** The element *is* the command — WMP's route back to the media centre — and treating it as an ordinary button left it a hit target that did nothing. Reported as *"the library button does not call the library"*. It now posts the `toggleLibrary` the script route already had, **only when the markup authored nothing**: `anemone` and `modernblue` spell `onClick="view.returnToMediaCenter();"` on theirs and posting it here too would open the library and shut it again on one click. |
| W192 | A piece pinned to an edge does not ride it through a resize in the same handler | **1 of 185 archives** (the same `Compact` scan as W185) | **Closed 2026-09-16.** The corpus idiom is three statements — pin the piece, change the view's size, pin it back — and it is how `SnapToVideoSize` keeps a drawer glued to the edge while the window changes size around it. This engine lays a view out **once per transaction**, so the middle state never existed: the drawer stayed at the coordinate it had while the window grew past it, putting its tab (authored 184 px inside it) outside the window where nothing could ever click it again. Reported as *"the drawers disappear … stuck in a bad state that you cannot escape"*; **not reproduced from the reporter's own steps** — both buttons they suspected are inert for the drawers — so this closes the mechanism that provably strands one, not necessarily the path they took. Measured: a right-aligned drawer at x=120 stays at 120 when the handler takes the view 200→300, and rides to 220 after. |

**The process lesson, and it is the same one W175 left**: a defect that lives in the *window* rather
than in the scene is invisible to every flag in `harness.md`, because the sweep never has a window.
W186, W187 and W190 are each that, and each took one launch of the debug build plus a window list
read before and after a `CGEvent` click. Reach for that loop the moment a report says a control
"does nothing" and a capture says it works.

## Closure notes moved out of the live backlog, 2026-09-15

These are the closure narratives that had accumulated at the top of [`WMP_TASKS.md`](../../WMP_TASKS.md) —
W128, W129, W144, W102, the magenta class, W161-W162, W163-W166, W167-W169, W170, W171-W173, W174 and
W175, each with the report that opened it, the sweep that closed it and the process lesson it left. They
are preserved verbatim; the live backlog is a list of open work and a closed row reads as open work there.
The durable process rules from these also live in `skills/wmp-skin-guide/reference/harness.md`.

**W175 closed 2026-09-15, from one report — *"xbox music player skin is not showing the main window.
it opens to the playlist and there is no route to get to the main window"*.** A view with no window
can honour `theme.currentViewID` and `theme.openView` only as "which view next", and the initial-load
walk read both off one `hostCommands.last`. **They are not the same request.** A redirect replaces the
view and the last write wins; `openView` opens a *window per call* and leaves the caller alone, so
`XBOX Music Mixer`'s `controlView`, whose `onLoadSkin()` ends
`theme.openView('mainView'); theme.openView('eqView');`, was read as "go to `eqView`" — and `mainView`
is the only one of its seven views whose buttons reach the others. `windowlessSuccessors` now ranks
the opened views by the skin's **own declaration order**, makes the earliest the player, keeps the
rest in the candidate list, and replays them against the player through `applyHostCommands` once it
is on screen. Closure notes in [the archive](docs/wmp-skin/wmp-backlog-archive.md).

**W175 is the row to read for a defect a sweep is structurally blind to, and for a fix that hides
behind a persisted preference.** No flag in `harness.md` performs the candidate walk — it renders
each view independently — so every probe said this skin was healthy, and it was: the engine simply
presented the wrong one of its healthy views. **The old rule was right by luck wherever a skin opened
its player last**, which is why `Halo 2` never showed it while sharing the architecture exactly. The
measurement is a window list per launch, and it is one `osascript` line:

```bash
defaults write NullPlayer wmpSkinName -string "XBOX Music Mixer"
defaults delete NullPlayer wmpSkinViewID   # written on every present — a wrong player is sticky
nohup ./.build/arm64-apple-macosx/debug/NullPlayer -uiMode wmp > /tmp/app.log 2>&1 &
osascript -e 'tell application "System Events" to get {name, size} of every window \
  of (first process whose name is "NullPlayer")'
```

**Delete `wmpSkinViewID` before believing any launch here.** It is written on every present, so the
engine's own wrong answer outranks the fix on the next launch (W153), and the same walk then stops at
the player and never reaches the dispatcher at all.

**W174 closed 2026-09-15, from one report — *"ovoid skin is missing its backing in the center, it
click through to the desktop"*.** A `<VIEW>` that declares both `clippingColor` and
`transparencyColor` has said two different things, and only the first is *the window is not here*.
Both were keyed out of the artwork alike, so `Ovoid`'s screen — 11,400 magenta pixels inside a
153x200 oval whose 6,468 red ones are its corners — was a hole through a borderless
`isOpaque = false` window, with nothing to see and nothing to click. Behind it is an `<EFFECTS>`,
and **a rect that authors no backdrop of its own still has one, and in WMP it is black**. The ground
is laid under everything in the below layer and clipped to the shape the nearest container states
with its `clippingColor` — never `transparencyColor`, which is the hole it exists to fill. Sweep:
**5 of 184 images move, every changed pixel a former hole becoming opaque black.** Closure notes in
[the archive](docs/wmp-skin/wmp-backlog-archive.md).

**W174 is the row to read for a class the sweep *can* rank, and for how to ask it.** The reach is
not in the markup — it is 17 partly transparent rects of 95, found by dumping the corpus and
counting fully transparent pixels inside each `WIDGET … effects` frame, and narrowed to 5 by the
clipping-colour gate. The gate is the whole design: `circle` and `Plus! BubbleSkin` are in the 17
and must stay untouched, and both are in
`skills/wmp-skin-guide/reference/skins/README.md`'s counter-evidence table for it. **The same
sentence has now been reported twice about two different mechanisms** — W166 was
*"the window has no backing when a track plays and it clicks through to the background"* on
`Colorchooser`, and that was a script-assigned `zIndex` reaching `windowedEffectsRects`. A hole in a
`.wmz` window is a symptom, not a defect; find which layer left it.

**W171–W173 closed 2026-09-15, from one report — *"Plus! HueShifter has a green section"*, then
*"is it supposed to be green or not because it still is"*.** Three independent defects behind one
screenshot, and the reported colour was not one of them: the green is the skin's own artwork, which
its shipped `hueshifter_final.jpg` settles.

- **W171 — a `clippingImage` with no `clippingColor` clipped nothing.** 169 of the corpus's 172
  declarations write one; the three that do not name a **fully opaque** mask, so the source-alpha
  test kept every pixel. HueShifter drew `body_lower.jpg` — a 213x66 lavender plate — as a
  hard-edged box across the bottom of the player. The key is now the mask's own corner, which is
  the `auto` derivation (W167) and white in all three files.
- **W172 — `transparencyColor` states a container's shape, and a container's shape is a region.**
  `clipMask` read only `clippingColor`, so HueShifter's five mask-backed subviews were plain
  rectangles; **127 nodes across 17 archives** qualify under the existing three guards. Fixing it
  broke `Ice`, whose `Clip.png` marks its keep region with **alpha-zero** pixels — so
  `WMPSceneClipMask` now renders through `regionMask` rather than `clippingMask`. **The test that
  said `transparencyColor` never shapes cited `cerulean` and was wrong on its own evidence**: that
  skin writes `clippingColor` beside it and its `face.bmp` is 18,601 colours, which `isShapeMask`
  rejects twice over.
- **W173 — `hueShift` was unimplemented, and it is the property the skin is named after.** Ten
  writes, one archive, all from script. Implemented as a luma-preserving rotation folded into the
  decode and keyed on the angle. **The NTSC YIQ matrix is the trap**: it rotates the opposite way
  and clips saturated pixels out of gamut; use the standard `hue-rotate` matrix.

Corpus sweep across all three: **4 of 180 archives moved** — `Plus! HueShifter`, `Secura`,
`portals`, `elvis` — every one toward the skin's own artwork, plus `Scooby-Doo_2`'s
nondeterministic `randomPic()`. Closure notes in
[the archive](docs/wmp-skin/wmp-backlog-archive.md); the family's side is
`skills/wmp-skin-guide/reference/skins/plus-family.md`.

**W171–W173 are the row to read for what a render sweep cannot rank.** W172 looked like a clean
win at 5 archives until `Ice` was opened and read: the frost overlay it erased was **invisible in
the diff count** and only a before/after pair, looked at, showed it. And W173 is invisible to a
sweep outright — the property defaults to 0, so 179 archives are byte-identical and the one that
moves does so only after a handler runs.

**W170 closed 2026-09-14, from a live report — *"in hue pressing pause does not pause the stream and
play is not responsive at all"*, then *"stop does not stop"*.** `openstatechange` was raised off the
**play** state, so every pause told the skin a media had just opened. **109 of the 180 archives
author `OpenState_onchange`** and three answer it by playing — `Plus! HueShifter`,
`Plus! Plasma Ball` and `Plus! SlimLine` share a handler whose `osMediaOpen` arm ends in
`player.controls.play()` — so playback restarted 16 ms after every pause, and after a stop the
re-play reloaded the track from 0:00. Each event now rides its own quantity
(`WMPMainWindowController.stateEdgeEvents`). Closure notes in
[the archive](docs/wmp-skin/wmp-backlog-archive.md); the family's side is
`skills/wmp-skin-guide/reference/skins/plus-family.md`.

**W170 is the row to read for what a corpus sweep cannot do.** The same session drove a full
transport audit — 284 decoded play/pause points across 149 skins, both host states — and reported
the transport healthy, correctly: the defect is in the event raised 16 ms *after* the click, and the
harness seeds one host snapshot and never transitions. The first live pass then cleared the skin
too, because it used a local file: only the streaming path turns the spurious re-play into a real
restart. The numbers and the two point-decode traps that produce a convincing false "dead control"
are in `skills/wmp-skin-guide/reference/harness.md` § *The transport audit*.

**W167–W169 closed 2026-09-14, from one report — *"combat flight simulator and plus plasma ball have
a gray box background I suspect should not be showing"*, then *"look how bad the controls look in the
new version"*, then *"fix the other skins that were addressed with plus egg commit"*.** Three
unrelated rules about one attribute pair. **W167**: `clippingColor="auto"` resolved to no key at all,
so `Plus! Plasma Ball`'s `screen_MASK.gif` cut nothing and the whole player drew opaque over a plasma
globe that had never been on screen; the value comes from the corner of the bitmap the declaration
governs, which is where all four `auto` authors in the corpus put it. **W168**: a container's
clipping shape did not reach its children, so `Combat_Flight_Simulator_3`'s keyless `main_bg.jpg`
child kept the 67% matte its parent's mask existed to remove — guarded by `Gorillaz` (a tiled swatch
is a ground, not a shape) and `YIL!OMA2K` (artwork with a keyed hole is not a mask). **W169** is the
big one: `clippingColor` was keyed out of the *artwork* as well as the mask, at a JPEG's
64-component tolerance, deleting **85.7%** of `Plus! Plasma Ball`'s `eq_panel_normal.jpg`, **52.1%**
of `TDK`'s `info_bg.jpg`, **39%** of `elvis`'s `elvis_tray.jpg` and **27%** of
`Plus! Hard Boiled`'s `Egg_Body_Normal.jpg`. Sweep: 522 identical, 13 moved, every one a gain.

**W169 is the row to read for process.** W160 measured the clipping masks two days earlier, found
their *edges* clean, and wrote them off in `plus-family.md` § *Ruled out* — then landed Lanczos
resampling on the same pixels the attribute was erasing. **A mechanism cleared is not an attribute
cleared**, and a *"low res"* report about photo-real artwork is not necessarily about resampling. The
instrument that named it was neither a probe nor the sweep: decode each archive's artwork and count
how much of it matches its own declared key at the format's tolerance. Two further notes, both paid
for in this session: a **1x render dump is not evidence about Retina sharpness** — comparing one
against the reporter's 2x window capture sent a whole round down the wrong path — and a second
NullPlayer already running makes `first process whose name is "NullPlayer"` pick the wrong window, so
raise and capture by `unix id`.

**W163–W166 closed 2026-09-14, from one report — *"colorchooser skin looks totaly broken from the
UI I do nto have a refrence image"*, plus a second observation in the same session, *"the window has
no backing when a track plays and it clicks through to the background"*.** Four unrelated engine
rules, none of them about that skin. **W163**: a program was registered only from a `scriptFile`
attribute, and **7 archives declare none** while shipping a same-named `.js` they call into — all
seven threw on their first handler. **W164**: a `<VIEW>` stretched background artwork to its declared
canvas; **4 of the 17 views that declare both** author a size the artwork does not have, and
stretching puts the frame out of register with its own contents. **W165**: a colour was read from the
markup and nowhere else, so neither a `wmpprop:` mirror nor a script assignment painted — the reach
was 8 further corpus images, every one a colour a skin's own script had always set. **W166**: a
script-assigned `zIndex` was ignored, which on `Colorchooser` left the opaque panel the player sits
on classified as artwork *above* a **windowed** visualizer; `windowedEffectsRects` punched it out and
the window had a 164x130 click-through hole for as long as a track played.

**W166 is the row to read for process.** No headless probe and no corpus sweep can see it: the sweep
runs a stopped player, which is the one state in which that skin is correct, and
`WMP_RENDER_HOST=playing` seeds the snapshot without raising the `playstatechange` the write lives
in. `reference/harness.md` § *A sweep runs a stopped player* is the general form. Closure notes in
[`docs/wmp-skin/wmp-backlog-archive.md`](docs/wmp-skin/wmp-backlog-archive.md); dossier in
[`reference/skins/colorchooser.md`](skills/wmp-skin-guide/reference/skins/colorchooser.md).

**W161 and W162 closed 2026-09-14, from one report — *"the 2 windows_xp skins the eq does not
work"*.** Neither was an equaliser defect. **W161**: a finished one-shot GIF held its last frame, so
`Windows_XP_Media_Center_Edition`'s opening shutter — an opaque plate — stayed over the display and
buried the metadata, the status line, the clock, the seek arc **and the equaliser panel the skin
opens in the same rectangle**. The rule is the *degenerate terminator block*, not the disposal
method: reading disposal alone matches **379 corpus files** and erases artwork, the terminator
matches **79 across 33 archives**, and `Age_of_Mythology` holds both halves down inside one skin.
**W162**, opened by W161 uncovering a blank `STATUS:` line: `player.status` was inert *and* missing
from the binding registry *and* empty as an event argument — three resolutions of one path, none
answering, for **69 of the 180 archives**. **A host path has more than one resolution and a live
member does not make a live binding** — `reference/object-model.md` § *What a property read answers*
rule 6 is the general form, and it is the thing to check when the next host property is added.
Closure notes in [`docs/wmp-skin/wmp-backlog-archive.md`](docs/wmp-skin/wmp-backlog-archive.md);
dossier in
[`reference/skins/windows-xp-media-center.md`](skills/wmp-skin-guide/reference/skins/windows-xp-media-center.md).
**No headless probe can see W161's class**, which is the process note it leaves: the equaliser was
correct in the scene graph the whole time and every flag said so.

**Tier 1a has no remaining open row.** **W156 closed 2026-09-13** — a `.wmz` seek is committed once,
on release, and no longer per mouse-move. Its closure note carries the measurement the row demanded
and the answer it was waiting on: `corona` and `New Super Mario Bros` are **identical** here, 21
commits apiece, so the reported difference between them was never structural.

**Tier 1b has no remaining open row.** W103, W104, and W105 are deferred. **W124 closed 2026-09-10** — `<VIDEO>` readiness now keeps its
event state across a same-media output rebuild while leaving the live surface state empty, so the
skin receives a matching `videostart` after a transient teardown without losing button input.
**W102 closed 2026-09-10** — `<VIDEO>` is hosted, the picture is
parked in the authored rect at the authored scale, and W105's `.video` routing went in with it, so
the Windows-menu item no longer opens our window over a skin that declares its own box. What it left
behind is ranked here: W103 is now answerable: the video path exists, so `<VIDEOSETTINGS>`'s four
sliders are a decision about what to bind, not a question about whether there is anything to bind to.

**Tier 0 is empty and the magenta class is closed.** W78 landed on 2026-09-08, **W78a closed the
same day**, and W125 closed the one remaining declared-key JPEG rounding case on 2026-09-11. The
former residual was `portals/mode1` (829 px, 0.38%) — **actually closed by W154 on 2026-09-13**,
not by W116: that patch was its `sysbuttons_group` sheet's magenta surround, and a
`<BUTTONGROUP>`'s sheet is painted through its mapping mask. The corpus residual is now
`Plus! Pulsar/mainView` alone (49 px, 0.04%), a button that declares
`transparencyColor="#ffffff"`, where standing aside is correct. **Do not open another magenta row without a screen to point at.** Their closure notes are
in [`docs/wmp-skin/wmp-backlog-archive.md`](docs/wmp-skin/wmp-backlog-archive.md).

**W129 closed 2026-09-11 and it closes the largest row of the SDK conformance audit.** It also
produced the rule that should govern every remaining row of that audit: *reading a handler's reach
is not reading its result*. Of its four host attributes only `currentEffectType_onchange` moves a
pixel — 96 of the 105 `currentPosition_onchange` uses write a number **W120 already supplies**, and
all 9 `currentMedia_onchange` uses are the album-art call that became W137. The census delta,
the corpus sweep and the live verification are in
[`docs/wmp-skin/wmp-backlog-archive.md`](docs/wmp-skin/wmp-backlog-archive.md).

**W144 closed 2026-09-12 and it is four rules, not one defect.** One live report against
`xsn_sports`' settings drawer produced four unrelated engine defects — centring beaten by a scripted
`left`, an authored `JScript:` geometry expression re-applying every transaction and undoing the
script that moved the node, skin artwork drawn over a **windowed** `<EFFECTS>`, and `onClose` having
no dispatch site at all (**373 handlers across 133 of 180 archives**, all dead). The last two are
capability rows in their own right and neither was on this page. Its two process lessons are in
[`reference/harness.md`](skills/wmp-skin-guide/reference/harness.md): a render dump is flat and
cannot answer a layering question, and a single-transaction sweep cannot measure a per-transaction
rule. Closure note and the ruled-out list are in
[`docs/wmp-skin/wmp-backlog-archive.md`](docs/wmp-skin/wmp-backlog-archive.md) § *Phase 20*; dossier
at [`reference/skins/xsn-sports.md`](skills/wmp-skin-guide/reference/skins/xsn-sports.md).

**W128 closed 2026-09-11 and it is the row the rest of the SDK conformance audit hangs off.** That
audit is the first time this engine was read against Microsoft's Skin Programming Reference as a
*specification* rather than against a corpus sweep, and its point is that a corpus scan can only
find what some skin already calls. W128 brought `elementMethodVocabulary` up to the SDK's
element-method list, which changed what every later measurement can see: an unimplemented SDK method
was being counted `INERT` — Tier 2b, the tier you do not take runtime work from — and is now
`UNRECOGNISED` where it belongs. **W136 and W132–W133/W135 are that audit's remaining rows, ranked
 in that order** (W136 in § 2a; W132–W133 and W135 in Tier 3), and § *2c-note* is its
disproved list: read that before opening a row that came from reading the SDK against a scan. The
closure note, with the census delta and the render-sweep result, is in
[`docs/wmp-skin/wmp-backlog-archive.md`](docs/wmp-skin/wmp-backlog-archive.md).

### Tier notes that were only closure announcements

Paragraphs lifted from the tier introductions of the live backlog in the same pass — Tier 1c's six-plus-one
reproduced defects, the `WoW` trio, the Phase 3 `corona` live-QA pair, W70-W72, W107-W116, W55 and W38.
Each opened by announcing work that had already closed.

**Six of the reporter's defects were captured, reproduced and closed on 2026-09-08** — a borderless
window that was never key (so no `hoverImage` in the corpus ever drew), a script repaint that erased
hover artwork, `<TEXT>` rows that were not hit targets, a tooltip showing the view's `description`,
`Halo 2` opening on a thumbnail view its own `onLoad` blanks, and every GIF looping forever over a
view timer that had never once fired. All six are in
[`docs/wmp-skin/wmp-backlog-archive.md`](docs/wmp-skin/wmp-backlog-archive.md) § *Phase 7*, and the
instrument that found all of them is `WMP_TRACE_INPUT=1`.

**A seventh closed on 2026-09-08, and it was made visible by the sixth.** Once the view timers ran,
every animation restarted from frame zero on every scene rebuild — reported as "the animations keep
opening and closing constantly… when you try to interact they are just opening and closing all the
time". `startAnimation` rewound its epoch on every call and is called by every rebuild, so a view
declaring `timerInterval="100"` restarted a 2.16s one-shot intro ten times a second, and a hover
crossing did it again. Archived as **W85** in § *Phase 8*; the mechanism and the `INPUT animation` trace line
that found it are in `reference/harness.md` § *The one probe that is not in the test binary*.

**Three more closed on 2026-09-09, all from one report on `WoW`** — "wow skin is empty and shows no
player or skin windows", then "adding to the playlist does not work", then "why does the now playing
look like this? it should fit and marquee". They were three unrelated engine defects, each of which
hid the other two: a panel opened with `theme.openView` was persisted as the session's view (**W96**),
an unanswerable `wmpprop:` on `visible` deleted the playlist control outright (**W95**), and a
`<TEXT>` was drawn unclipped while no skin in the corpus could turn its marquee on (**W94**). All
three are in [`docs/wmp-skin/wmp-backlog-archive.md`](docs/wmp-skin/wmp-backlog-archive.md)
§ *Phase 12*, with the sweep that bounded the second. One thing the report did **not** turn out to be:
"launching a track from library does not play it" did not reproduce — playback started every time
from the Plex browser, and the queue reached the engine; what was missing was any way to *see* it.

**Two more closed on 2026-09-09, and the reason neither had ever been captured is that no probe
here could render a playing player.** "The timer display and seek/progress are broken in wmp for all
skins" was **W119** — a 100 ms position tick dispatched as `status_onchange`, which is WMP's *status
string changed* event, so 70 of the 177 measurable archives re-ran their metadata handler ten times
a second (all 75 authored sources are metadata updaters; 35 of them re-ran the readout off
`player.status`, which was then inert and empty — it is a live sentence since W162 and the trap is
unchanged, because it was always the *rate*) and every script timer in the skin was cancelled
inside 100 ms of pressing play —
and **W120**, a seek slider whose `max` is the media duration and whose `value` no skin states,
which is 73 sliders across 61 archives sitting on frame 0 for the length of the track. Both are in
[`docs/wmp-skin/wmp-backlog-archive.md`](docs/wmp-skin/wmp-backlog-archive.md) § *Phase 14 (fifth
pass)*. **The instruments came first and they are the transferable part**: `WMP_RENDER_HOST` seeds a
playing host for a whole sweep and `NULLPLAYER_PLAY` starts a debug launch on a track, so the
playback half of W73 is now measurable rather than argued about. With the first of them seeded, 88 of
the 89 measurable archives that author the elapsed binding draw the right string, which is what moved
the search out of the scene and into the app's event dispatch. **The clock half of the same report closed the same
day as W51** — a control is bound both ways, so the host moving it raises `value_onchange` too, and
`Catwoman`'s digit strips now count the track down. That one carries new measured demand with it: 42
handlers that had never run now run, and 30 abort on an **`event` object in a handler** that nothing
binds on either direction of `change`.

**The Phase 3 `corona` live-QA pair is closed and both are in the archive** (§ *Phase 13*). W43 —
the player going black while a track played — was fixed when the two overlay views were found
filling `dirtyRect` rather than `bounds`. W44 — four buttons in the top cluster all opening the file
dialog — was closed on the test the row itself nominated: `WMP_RENDER_CLICK="vPlayer@366,12;400,12;420,12;444,12"`
now resolves `bOpenFile`, `bPlaylist`, `bVis` and `bEq` distinctly with **`handlers=1` each**, and
only `bOpenFile` posts `openFileDialog`. That disproves the row's own suspicion of a `nil`
`targetID` fanning one click out across every `onClick` in the view: dispatch carries the exact
`targetStableID` from both the app and the harness, and an exact node beats an authored id.

**W71, W72 and W70 landed and are in the archive.** The harness now hosts every scene in the real
`NSView` stack and diffs it (`WMP_RENDER_APPKIT`), drives a captured drag along a slider's own axis
(`WMP_RENDER_CLICK` with a `>`-joined path), and ranks every view by how much of it failed to
resolve (`starved.tsv`, every census run). What they measured on their first run is in
`skills/wmp-skin-guide/reference/harness.md` § *After Phase 6*; the two findings are W74 and the
re-ranking of W68.

**W112-W116 closed 2026-09-09 too**, from the second report on the same skin — a tween endpoint
readable by the handler that started it, a script that could not resize its own window, a `fontSize`
that never reached the drawing beside a baseline that sat above its own box, and two host members
that aborted the handler filling every readout, and a `BUTTONGROUP` painting its whole hover
sheet over the window. **Two of the four were reachable headlessly and two
were not**: no sweep here has a host snapshot, so nothing but `INPUT script-diag` in the running app
could see a `psPlaying` branch dying on its first statement. They are in
[`docs/wmp-skin/wmp-backlog-archive.md`](docs/wmp-skin/wmp-backlog-archive.md) § *Phase 14 (third
pass)*.

**W107-W110 closed 2026-09-09** and are in
[`docs/wmp-skin/wmp-backlog-archive.md`](docs/wmp-skin/wmp-backlog-archive.md) § *Phase 14*: an
unsized `<TEXT>`, an unsized `<BUTTONGROUP>`, a mapping-region `<…ELEMENT>` laid out as a control,
and half of WMP's transport vocabulary missing from `WMPElementKind`. Together they were **83% of
the corpus's 2,380 unresolved nodes**, and closing them took the corpus to **1,067** while adding
689 nodes, 611 paint commands, 253 hit targets and 609 widgets. The evidence, the sweep and the two
rules that came back narrower are in `skills/wmp-skin-guide/reference/harness.md` § *After the
starvation classes*. What is left of the class is one row.

**W55 closed 2026-09-09 and took 438 of those uses with it** — `onEndMove` 247, `onDragEnd` 141,
`onEndAlphaBlend` 50 — so the 4,114 above is stale by that much and the rows below are otherwise
unmoved. It also settled the shape of a *negative* answer: `onEndResize` is **zero uses corpus-wide**
and was deliberately left unimplemented rather than added for symmetry.

**W38 then closed against the same 179 archives and did it again.** `WMP: unimplemented` calls
corpus-wide fall **83 → 43** — the 42 that went are its own 40 `alphaBlendTo` and 2
`setColumnWidth` — while `Can't find variable` / `TypeError` stays at 45, because this row was never
a name the runtime could not find. Thirty views changed on screen and none of them is a fade: they
are the rest of those `onLoad` handlers running. The rows below are otherwise unmoved; the
scripted-size path it exposed later closed as W113.

## W178 — the borrowed caption report

Reported 2026-09-15 as *"in many skins including half life the library window does not properly draw the top right
window controls"*, and closed on the reporter's own screen after three placements. The row carries the corpus
measurement (`WMP_HOSTED_FRAME`), the rule both painters now share, and the two traps that cost the most: a harness
that renders at 1x while the app renders at 2x, and a caption measured off a screenshot whose columns do not line up
with window points.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W183 | Nothing of ours is drawn over a borrowed ring, and W178's whole caption is withdrawn | **88 archives lend a ring** (installed corpus, `WMP_HOSTED_FRAME=575x464`, 2x, 2026-09-15); every one of them is affected | **Closed 2026-09-15, accepted by the reporter, and it reverses W178 rather than extending it.** W178 shipped a caption in the skin's own band and then took four rules to place it: contrast against the ring, a plate per control, centring on the lit title bar found in the pixels, and a close inset by the ring's right border. Two more were added the same day — the inset capped at the band's height, after `Star Wars`'s `plView` (a 164pt side rack of 575) stranded the × a third of the way into the band, measured across the corpus as **21 right racks and 31 left ones** against a 32pt median border; and the corner bitmap rejected as the cap because these corners are decorative and come out *wider* than the border (202pt `Star Wars`, 296 `Half-Life_2`, 190 `Halo 2`, kept as the probe's `corner=`). **`NVIDIA` is where the model broke rather than the tuning**: an 84pt band with too little contrast to call a bar (`strip=none`), so the controls centred in the whole band and landed on the curve where its body starts, directly under the restore, minimise and close the skin paints there itself. Reported as *"issue after issue — what is the problem with your implementation"*, and the answer is that **all six rules are inferences about someone else's finished chrome and `.wmz` markup states none of it**. So: no title, no close glyph, nothing of ours in the band at all — the ring is the window's chrome, whole — and `SkinnedSurfaceChrome.closeButtonRect` is a **40x26 hit area flush into the window's top-right corner**, capped by the band, over whatever × the skin painted there. Drawing a small × inside the client hole was tried in between and rejected on sight (*"remove that close button, it needs to go in the correct corner"*); the hit area was then widened leftward on the same report, `NVIDIA`'s painted × sitting 20-30pt in behind a rounded corner. `titleStrip`, `CaptionStrip`, `captionBandRect`, the plate/contrast sampler and `WMP_STRIP_TRACE` are deleted with the rules that read them, and `WinampModernChromeTests` now asserts the band comes out of the painter as the ring's own pixels. **This also closes W178's leftover row**: `EQView` and `WaveformView` read the shared rect now, so the corner closes them too. Verified live on the debug build — NVIDIA's own × closes the library, CGEvent click at the window corner — and `swift test` 2,324 tests, 0 failures. **The lesson worth keeping is the `.wal` contrast**: a Winamp Modern skin declares its frame (`<Wasabi:StandardFrame:*>`, a measured client rect, declared buttons), so a hosted window is mounted in it and nothing is inferred — which is why this class of defect has never existed there. When a `.wmz` question can only be answered by reading the artwork, stop answering it. |
| W178 | A borrowed ring's caption band loses the library's own title and close control (**superseded by W183 — the caption it added is withdrawn**) | **87 of 184 installed archives lend a ring**, captions 7px–104px, measured 2026-09-15 with `WMP_HOSTED_FRAME=550x464` | **Closed 2026-09-15, accepted by the reporter.** The measurement killed the leading hypothesis: `WMP_HOSTED_FRAME` (new probe, documented in `harness.md`) renders the derived ring per archive at the library's own default size and prints the four insets our chrome lays a hosted window out from. **No archive lends a caption shorter than one character**, so the `captionHeight >= classicCharHeight` guard both painters carried never fired on a real skin. The case that exists is the opposite: a band shorter than the lettering *asked for* — `The_Sentinel_v.1.0` 7px, `TheUnit`/`The` 9px against the library's 1.6x glyphs — so the lettering is now scaled to the band and the caption is never dropped, because dropping it takes the window's only close control with it. `PlexBrowserView.drawBorrowedFrameCaption` is four lines into `SkinnedSurfaceChrome.drawBorrowedCaption` instead of a copy of it. **Two things the reporter found that headless work did not**: sampling the ring per glyph and outlining against it reads as mess on `Half-Life_2` ("works but looks bad"), so each of the two now sits on a **plate** in a palette tone the artwork behind it cannot be confused with; and a ring's corner routinely carries the skin's *own painted* close button — `Combat_Flight_Simulator_3` draws a round × and ours landed 15px to its right, so the user clicked artwork ("cant close library from the x"). `SkinnedSurfaceChrome.closeButtonRect` now insets the column by the ring's right border and **every close hit test reads it**, so what is clickable is what is drawn. **And the band both are centred in is the ring's own title bar**, not the gap above the client hole: reported as *"you are not vertically centering the x and title text in the title bar"* on `Half-Life_2`, which leaves 46px there and paints its bar across 12 of them. No markup states where the bar ends — the ring pieces overlap the client area — so `WMPHostedFrameTemplate.titleStrip` reads the lit run off the rendered frame — the widest run above a third of the band's range, in a profile smoothed over 3px (**55 of 87** archives resolve a bar shorter than their band; the other 32 are flat and use all of it). **Two earlier rules passed the harness and drew the old layout in the app**: the harness renders at 1x and the app at 2x, and a one-pixel highlight that averages away at 1x outshines the bar at 2x — `WMP_HOSTED_FRAME_SCALE` exists for that and both scales must agree. Verified live on `Combat_Flight_Simulator_3` (the library and the Cava window both close from the drawn plate, CGEvent clicks) and on `Half-Life_2`, where three placements were needed before the reporter accepted one: centred in the 46px band reads low, centred on the 29px bar reads top-heavy, and the controls now centre **half way between the two centres** (plate at 10.25-26.25, traced out of the running app with `WMP_CAPTION_TRACE`), 2026-09-15. **Still their own rows**: `EQView` and `WaveformView` hit-test close in 9x9 classic boxes of their own and do not read the shared rect, so under a borrowed ring their drawn glyph and their hit box are in different places. |

## W177 — the Half-Life 2 Cava report

| ID | Item | Landed |
|---|---|---|
| W177 | A borrowed ring is painted over the Cava window's bars, so the visualiser is a still picture | Closed 2026-09-15. Reported as *"in half life skin the cava window does not show cava, there is a static image there"*. **A borrowed ring is the frame *around* a hosted surface, never wallpaper behind it.** `SkinnedSurfaceChrome.drawSkinFrame` drew the ring bitmap across the whole window with nothing cut out of it, and all seven spectrum-family windows call `drawSpectrumFamilyWindow` as an overlay **after** their content — so every opaque ring in the corpus painted a still picture over a running visualiser. `Half-Life_2` builds its panels out of solid `f_*.png` strips, which is why the bars vanished rather than dimmed. The fix is the even-odd clip `PlexBrowserView.drawWinampModernChrome` had been cutting for the library since the rings arrived, moved into the shared painter where it serves all seven windows: the client hole is cut out of the ring, and corners, edges and the caption band are untouched. The `fillBackground` fill still runs first, so the windows that rely on the chrome to paint their ground are unchanged. **Measured live, not reasoned about**: debug build, `-uiMode wmp`, `wmpSkinName=Half-Life_2`, a sweep playing, Cava opened from the Windows menu, two `screencapture -l` shots 3 s apart — green bars inside the skin's ring and the peak moved between them. The reporter confirmed the other six windows the same day. Pinned by `WinampModernChromeTests.testABorrowedRingIsNotPaintedOverTheSurfaceItFrames`, which drives an opaque synthetic ring over a sentinel-filled surface and asserts the client hole survives while the sides, caption and bottom still carry the artwork. **What it did not settle**: the caption band's own legibility — the title is drawn in the palette's lettering over whatever the ring's top piece happens to be, and over `Half-Life_2`'s orange strip it is barely readable. That is W178's contrast question, seen from the other six windows rather than from the library. |

## W175 — the XBOX Music Mixer report

| ID | Item | Landed |
|---|---|---|
| W175 | A windowless dispatcher's `theme.openView` calls were read as a redirect, so the **last** panel it opened became the player | Closed 2026-09-15. Reported as *"xbox music player skin is not showing the main window. it opens to the playlist and there is no route to get to the main window"*. The initial-load walk took `hostCommands.last(where: setCurrentView \|\| openView)` as the single successor of a view with no window. **The two commands are not the same request**: `theme.currentViewID` replaces the calling view, so the last write wins, while `theme.openView` opens a window per call and leaves the caller alone. `XBOX Music Mixer` opens on `mediaSwitcherView`, whose `onLoadPreview()` blanks it and redirects to a windowless `controlView`, whose `onLoadSkin()` ends `theme.openView('mainView'); theme.openView('eqView');` — so the walk followed `eqView`, made the 265x207 equaliser the app's player window, and never presented the 344x422 `mainView` that carries the skin's whole transport and every button that reaches its other views. `WMPMainWindowController.windowlessSuccessors` now separates them: a `setCurrentView` is still last-wins and still outranks everything beside it, while `openView` commands are ranked by the **skin's own declaration order** (all 21 corpus archives that declare both a `mainView` and a panel view declare `mainView` first, scanned 2026-09-15; the authored call order breaks ties for a view the skin does not declare), the earliest becomes the player, every one of them stays in the candidate list so a player that is itself windowless falls through to the next, and the rest are replayed whole — `openViewRelative`'s offset intact — through `applyHostCommands` after `restoreOpenAuxiliaryViews`, where an already-open panel is a raise rather than a second window. **No probe in `harness.md` can see this class**: the sweep renders each view independently and performs no candidate walk, so every flag reported this skin healthy — and it was. The measurement is a window list per launch (`osascript … get {name, size} of every window`), on a profile with `wmpSkinViewID` deleted, because that key is written on every present and the engine's own wrong answer otherwise outranks the fix (W153). Driven live, debug build, one launch each: `XBOX Music Mixer` 1 window → player 344x422 + `eqView` 265x207; `Halo 2` 1 → player 327x294 + `plView`/`eqView`/`visView`/`infoView`; `xsn_sports` 1 → player 409x277 + four panels; `Plus! Mecha` 1 → player 446x282 + `plView`/`eqView`; `XBOX Live Skin` 1 → player 364x221 + `eqView`; `9SeriesDefault`, which authors no dispatcher, unchanged at one 859x468 window. **The old rule was right by luck wherever a skin opened its player last** — `Halo 2` does, which is why the corpus's purest dispatcher skin never showed this — and the panels its own preferences said were open had never been opened at launch at all. 7 tests in `WMPWindowlessSuccessorTests`, one of which drives a dispatcher's JScript through `WMPScriptRuntime` to prove the commands arrive in authored order. |

## W174 — the Ovoid report

| ID | Item | Landed |
|---|---|---|
| W174 | An `<EFFECTS>` rect over a container's `transparencyColor` hole was a hole through the window | Closed 2026-09-15. **A `<VIEW>` that declares both `clippingColor` and `transparencyColor` has said two different things and only the first one is "the window is not here."** `Ovoid`'s `background.bmp` is 153x200 in exactly three colours — 12,732 px of grey artwork, **11,400 px of `#FF00FF`** for the screen in the middle of the oval and **6,468 px of `#FF0000`** for the corners outside it — and with both keyed out of the artwork alike the screen was a hole through a borderless `isOpaque = false` window: nothing drawn, and the window server passing the clicks to the desktop. Behind it sits `<EFFECTS id="myeffects" zIndex="-1" left="24" top="29" width="105" height="142">`, whose surface is transparent whenever no visualizer runs (W9) on the assumption that the skin painted something there. **An `<EFFECTS>` that authors no backdrop of its own still has one, and in WMP it is black** — two corpus rects restate it as `backgroundColor="#000000"` and none names another colour. `WMPEffectsGround` carries the frame, the colour (the node's authored `backgroundColor`, else black) and the shape; `WMPSceneBuilder` derives it from a `groundShapeStack` of the containers above the node; `WMPRenderer` draws it **under every command in the below layer**, so a skin that backs its own rect covers it completely and W9 is intact. It is drawn whether or not the command list is split, because it is the *skin's* backdrop rather than the hosted surface — which is what lets a flat render dump arbitrate the class. **The shape comes from `clippingColor` alone, at the container's own size (the `Gorillaz` guard), and this is the one place W172's widening to `transparencyColor` must not reach**: `circle`'s `visfield.bmp` states both keys and its 1,122 magenta pixels are a one-pixel antialias fringe between the field and the red matte, so a ground keyed off them draws a black halo round the skin, and `Plus! BubbleSkin` would take 44% of its rect black outside its silhouette. Both are now in the counter-evidence table. **The reach was measured by rendering, not from the markup**: dumping the corpus and counting fully transparent pixels inside each `WIDGET … effects` frame gives **17 partly transparent rects of 95**, which the clipping-colour gate narrows to 5. **Corpus sweep, 184 archives: 5 images move and every changed pixel is a former hole becoming opaque black** — `rad` 27,090 px, `Ovoid` 11,400 px (both exactly their bitmaps' magenta counts), `Goo` 2,993 px through its `bigGoo` subview, `digitaldj/DigitalDJMini` 1,973 px, and `cerulean` 20 isolated pinholes along its vis hole's antialiased curve. Nothing already painted moved. 3 tests in `WMPEffectsGroundTests`, including the guard that a container stating no clipping colour grounds nothing. |

## W171–W173 — the HueShifter report

| ID | Item | Landed |
|---|---|---|
| W171 | A `clippingImage` declared with no `clippingColor` clips nothing | Closed 2026-09-15. **169 of the corpus's 172 `clippingImage` declarations write a `clippingColor` beside it; the three that do not were being read as "no key".** All three masks — `Plus! HueShifter`'s `body_lower_MASK.gif`, `Charlies_Angels_Full_Throttle`'s `vis.gif`, `gnome`'s `viz.bmp` — are **fully opaque with a white 0,0**, so `clippingMask`'s source-alpha test kept every pixel and the node drew its whole rectangle. On HueShifter that is `body_lower.jpg`, a 213x66 lavender plate carrying two wings, painted as a hard-edged box across the bottom of the player with the skin's green bottom candy behind it. The key now falls back to the mask's own corner, which is exactly the derivation `clippingColor="auto"` already uses (W167) and is white in all three files — the same `clippingColor="white"` their sibling layers state by hand. **Scoped to a mask with no transparency of its own**: one that authored alpha has said what it cuts and a corner key would cut it twice. `testAClippingImageWithNoKeyTakesItsOwnCorner` and `testAClippingImageWithItsOwnAlphaTakesNoCorner` pin both halves. |
| W172 | A `<SUBVIEW>` that states its shape with `transparencyColor` was a plain rectangle, and a container's shape honoured its mask's alpha | Closed 2026-09-15. **Two changes, the second forced by the first.** `clipMask` read only `clippingColor`, so `Plus! HueShifter`'s five subviews — `transparencyColor="white"` over `body_Mask.gif`, `playlist_tray_wholemask.gif`, `eq_tray_wholemask.gif`, `video_tray_wholeMASK.bmp`, `body_lower_wholeMASK.gif` — shaped nothing: its bottom candy hung 22 px below the player's silhouette and the body's own edge was fringed with keying speckle, because `bodyNormalMask.gif` is a dithered 254-colour GIF carrying 2,108 px of near-white noise in its white region. **127 nodes across 17 archives qualify**, every one naming a file `…mask`, under the three guards W168 already had — untiled, authored at the node's own size, `isShapeMask`. `clippingImage` was deliberately not widened: a node naming a mask file outright has one key attribute for it. **The widening then broke `Ice`**, whose `Clip.png` is 379x183 in exactly two values — 17,558 px of opaque `#FF00FF` outside the player and 51,799 px of **alpha-zero** white over it — so honouring the mask's own alpha cut the keep region and the key alike and both `Frost` layers disappeared. `WMPSceneClipMask` now renders through `regionMask` (not the keyed colour, whatever the alpha); every other corpus mask is opaque and reads identically either way. **`testTransparencyColourAloneShapesNothing` asserted the opposite and was deleted**: it cited `cerulean`, and that skin writes `clippingColor="#FF0000"` beside its `transparencyColor` — so the shape came from the clipping colour regardless — while `face.bmp` is 18,601 colours, which `isShapeMask` rejects. Both guards independent, neither reached. Replaced by `testTransparencyColourShapesTheContentsToo`, `testAClippingImageIsNotShapedByTransparencyColour` and `testAContainersShapeIgnoresItsMasksOwnAlpha`. **Corpus sweep: 4 of 180 archives moved** — `Plus! HueShifter` (plate gone, silhouette clean), `Secura` (its panel no longer spills outside the round body), `portals` (EQ ticks no longer over the frame ornament), `elvis` (a 124 px sliver) — plus `Scooby-Doo_2`, which is nondeterministic by construction. |
| W173 | `hueShift` is unimplemented, so the button `Plus! HueShifter` is named after does nothing | Closed 2026-09-15. **Ten writes, one archive, all from script** — `changeHue()` steps a JS global by `360.0 / 11` and assigns it to `topCandy`, `botCandy`, `leftCandy`, `rightCandy` and `botCandyFacade`, and `loadPrefs()` restores the saved angle on load. Inert, the five candies were frozen at their native green and the paintbrush did nothing. **The reported colour was never the defect**: the green is the artwork, which the skin's own shipped 600x600 `hueshifter_final.jpg` settles — cropped at the coordinates the markup puts `botCandy` with the video tray open, `(208,454)-(396,537)`, it is the same clamshell as `hueshifter_bottom.bmp`, black wedges and yellow highlight included. **The unit is degrees and the skin is the authority**: its ten stops are 33°, 65°, 98° … 327° and `savePrefs` clamps to `0…360`, so a -1…1 reading would clamp every one of them to the same value. `hueshift` joins `standardNumericProperties` (it is rendered, so a write must commit as a mutation); `WMPSceneBuilder` resolves it per node — script override, then authored attribute — onto `WMPSceneImage`; `WMPImageStore.hueRotated` does the work, **folded into the decode and keyed on the angle**, so the crop, the Lanczos upscale (W160) and every mask see the shifted colour and five elements at five angles are five cache entries. **The NTSC YIQ matrix is the trap and the first version used it**: it rotates the opposite way — 120° takes red to blue, `(24, 42, 255)`, where every other implementation of `hue-rotate` gives `(0, 113, 0)` — and its blue row's 1.25 / -1.05 coefficients drive saturated pixels out of gamut and then clamp them. The standard SVG/CSS matrix turns the chroma about the luma axis: across all ten of the skin's stops on in-gamut colours the worst luma drift is **0.45 of 255**, and greys do not move at any angle, which is what preserves the candies' black wedges and white specular highlight. A fully saturated pixel always clips — inherent to the operation, not to the matrix. **A corpus sweep cannot see this class**: the property defaults to 0, so 179 archives are byte-identical and the one that moves does so only after a handler runs. Verified by driving the paintbrush with `WMP_RENDER_CLICK`, which prints `topCandy.hueshift=33 … rightCandy.hueshift=33`, and by rendering the ten stops through the skin's own `loadPrefs()` restore path — the player body is byte-identical at every angle, which is correct, because only the five candies carry the property. 9 tests in `WMPHueShiftTests`. |

## W134 — inert equalizer-settings members

| ID | Item | Landed |
|---|---|---|
| W134 | `<EQUALIZERSETTINGS>` is read for `enable` and nothing else | Closed 2026-09-11. `enableSplineTension`, `splineTension`, and `bypass` retain authored/script-written values, but each access is reported as `INERT`; NullPlayer has no spline-tension DSP or separate bypass state. They post no audio command and no scene mutation. In particular, `bypass` is not silently mapped to the inverse of `enable`. `testUnsupportedEqualizerSettingsRoundTripAsInertState` pins retained values, call-trace classification, and the no-mutation boundary. The 72-skin `enableSplineTension` / 67-skin `splineTension` markup reach is distinct from W39's one-skin script-host spelling. |

## W137 — built-in album art

| ID | Item | Landed |
|---|---|---|
| W137 | Album art is a WMP **built-in image**, not a file in the skin, and this engine resolves no such name | Closed 2026-09-11. `WMPImage_AlbumArtLarge` and `WMPImage_AlbumArtSmall` resolve as the WMP session's only two in-memory pseudo-resources (200px and 75px), not archive paths. `WMPArtworkLoader` asynchronously supplies them from local embedded tags, Plex, Subsonic, Jellyfin, Emby, or a direct stream artwork URL; a track change cancels the prior request and redraws the existing scene without rerunning JScript. The names are transparent while loading and preserve the artwork aspect ratio. `WMPImage_AdBanner` remains unresolved. A Plus! WMP skin visibly displayed the artwork after this change. `testBuiltInAlbumArtworkSuppliesBothWMPSizesWithoutTreatingItAsSkinArtwork` pins both sizes and the refusal. |

## W154 — a `<BUTTONGROUP>`'s sheet is painted through its mapping mask

| ID | Item | Landed |
|---|---|---|
| W154 | `portals/mode1` draws a white slab over its transport and its controls drag the window instead of clicking | Closed 2026-09-13. **Three defects, two causes, and the paint half explains a third thing nobody had connected to it.** A group's `image` is a sheet the size of the whole group and the dead area around its controls is keyed by the *mapping image*, not by the group's `transparencyColor` — an author names the map's dead colour there because it is the one colour every one of the group's bitmaps shares. `portals/mode1` states it three times: `cbuttons_play`'s sheet is white around the transport ovals against 24,997 black mask pixels (the reported slab at `13,236 280x140`, which was also hiding the brass casing beneath it); `sysbuttons_group` is the same shape in magenta, 829 against 829; and `shufrep_buttons` is the **control case**, 3,723 magenta in the art against 3,723 magenta in the *map*, where the one declared key covered both and nothing was ever wrong. The sheet is now painted through the mask in every state, the base sheet over the union of every registered child. **`showBackground="true"` is the author's exemption and the corpus states both polarities** — 41 declarations across 7 of 177 archives, every one `true` except `Compact`'s two `false`; without it `elvis`'s 335x396 body, `Plus! HueShifter`, `Plus! Plasma Ball`, `Plus! Hard Boiled` and `Plus! SlimLine` mask to their mapped regions and leave a hole where the player was. The base sheet also keeps the natural-size anchoring every other foreground image has (W122), which `Plus! SlimLine`'s `perfectV_SideBar_normal.jpg` is what noticed. **Corpus sweep: 125 of 535 views changed, every structural invariant line byte-identical**, and the opaque-magenta PNG residual the Tier 0 note carried drops from **878 px across 2 views to 49 px across 1** — the 829 px `portals/mode1` patch is gone, leaving only `Plus! Pulsar`'s declared-`#ffffff` button where standing aside is correct. Every changed view was reviewed as a base/current pair: all are slabs removed or artwork revealed (`YIL!OMA2K` 201,235 px, `New Super Mario Bros`'s magenta window border, `Ocean`, `tubeframe`, `Mandalay`, `Navigator`, `XBOX`, `gadget`). The drag half is a separate and general cause: `interactiveTarget` answered nil for a *host-disabled* control exactly as it does for bare artwork, so `mouseDown` read "no control here" and dragged the window — `refreshHostState` disables every transport child while `player.controls.play` is unavailable, which is most of the corpus's five-button groups on a cold start. An authored `enabled="false"` is not that case and still drags, which is what keeps `portals`' own 305x400 `main_button` backdrop movable. `testButtonGroupSheetIsPaintedThroughItsMappingMask` pins both polarities of `showBackground`; `testPressOnAHostDisabledControlDoesNotDragTheWindow` pins the drag and fails without the fix. |

## W155 — a group's mapping mask was rebuilt per draw

| ID | Item | Landed |
|---|---|---|
| W155 | The W154 mask made every render walk every group's mapping image | Closed 2026-09-13. **Opened by W154 the same day and found on the running app, not in a sweep.** Masking only the one *lit* group had hidden the cost; masking every group's base sheet exposed it, and `WMPRenderer.rasterize` called `WMPMappingImage.maskImage` — a full pixel walk, an allocation and a `CGImage` — **per draw, per group**. Reported as the app stuttering and hanging while clicking `New Super Mario Bros`'s playlist and equalizer buttons. The main thread was **idle** (3513 of 3565 samples in `mach_msg`); what was saturated were six `com.apple.root.user-initiated-qos.cooperative` threads at 3565/3565, with `maskImage` at 3510 of them — the renderer runs off-main, so it starved the pool everything else was awaiting rather than blocking the UI thread. The mask is a pure function of the bitmap and the child set and never changes with interaction state, so `WMPImageStore.mappingMask` caches it on the same LRU and eviction budget as the clipping masks, keyed by resource path plus sorted node ids (`WMPSceneMappingMask` gained `resourcePath` for it). `maskImage` also stopped hashing a `WMPColor` per pixel — a mapping image registers a handful of colours, so the accepted set resolves once and the inner loop compares three bytes, which is what the `swift_retain`/`swift_release` traffic in the profile was. **Measured on the reported skin, 20 renders after a warm pass: 173.1 ms → 0.3 ms per render.** The corpus re-sweep is 534 of 535 images identical to the pre-optimisation capture; the one mover is `Scooby-Doo_2/infoView`, which is nondeterministic by construction. **The lesson is the row**: a render sweep draws each view once, so a per-draw cost that only bites from the second frame on is invisible to it — `sample` on the running app was the only instrument that could see this, and W154 shipped without it. |

## W156 — a seek is committed once, on release

| ID | Item | Reach | Notes |
|---|---|---|---|
| W156 | A `.wmz` seek slider commits a seek on **every mouse-move**, and dragging one is audibly harsh | **Every seek slider in the corpus** takes this path — `WMPMainView.performSlider` runs from `mouseDragged` — but the audible complaint is so far **one skin**, `New Super Mario Bros`, with `corona` explicitly reported clean. Reported 2026-09-13 while streaming; unmeasured against the rest of the corpus | Reported as *"there is a harsh audio artifact at the time adjustment"* and *"it seems related to this skin, corona did not have the same issue. I am using streaming content"*. **Measured, live, with `WMP_SEEK_TRACE=1` and a `CGEvent` drag of 200 px across Mario's bar: 21 `performSlider` commits in ~0.5 s**, each one `onAction(.seek, fraction)` → `engine.seek(to:)`, then a 22nd from the skin's own `onDragEnd`. **Classic mode has never done this** — `MainWindowView.mouseUp` commits the position bar once, on release, and only moves the thumb during the drag. What each seek costs is in `AudioEngine.seek`: a local file does `playerNode.stop()` + `scheduleSegment` + restart with **no ramp**, a hard discontinuity per seek; streaming is debounced 0.15 s but only while `isSeekingStreaming` is up, and once that resets the next drag event seeks immediately again. **The hole to close first is why `corona` is clean**, because the obvious structural difference does not explain it: Mario is `<slider value="wmpprop:player.controls.currentPosition" … onDragEnd="player.controls.currentPosition=value;">` and corona is a bare `<SEEKSLIDER>` with no release handler, but **both resolve to `.seek` and both commit per move** — corona through `authoredAction` on the tag, Mario through its `value` binding. Do not fix this from the mechanism alone: that is exactly what was tried on 2026-09-13 and it **made seeking worse**, landing at roughly double the target time, so it was reverted in full (the tree is unchanged here). Two things that attempt learned and the next one should not re-derive: coalescing to a release-only commit **cannot** simply drop the per-move commits, because most corpus seek sliders author no `mouseup`/`dragend` at all and nothing else would ever commit them — corona is that shape; and a synthesized `mouseDown`/`mouseDragged`/`mouseUp` sequence against `WMPMainView` showed the release commit **never firing**, which contradicts the doubling seen live and means the release path is not understood yet. **One trace line settles both questions**, and it already prints both numbers: `hostCommand seekSeconds=<n> duration=<d>` — run one drag on each skin and compare. An untested hypothesis for the doubling, worth nothing until measured: `seekSeconds` divides by `host.snapshot.duration`, so a snapshot duration lagging the stream's real duration resolves the same absolute position to a larger fraction. Reproduce with `WMP_SEEK_TRACE=1 ./.build/arm64-apple-macosx/debug/NullPlayer -uiMode wmp` and a `CGEvent` drag; take the window rect from `CGWindowListCopyWindowInfo` filtered on owner `NullPlayer`, **not** from System Events, which returns whichever NullPlayer window it likes and cost a launch per miss. Note also that `defaults write NullPlayer wmpSkinName` does **not** select the skin at launch — `AppStateManager` restores its own persisted selection over it. |

Closed 2026-09-13.

**The hole the row said to close first is closed, and the answer is that there is no difference.**
Both skins were driven live with `WMP_SEEK_TRACE=1` and a 20-step `CGEvent` drag across their seek
bars, against a 21:49 local track: **21 `performSlider` commits apiece**, the same values, the same
`.seek` per mouse-move. `New Super Mario Bros` reaches `.seek` through its `value` binding and
`corona` through `target.action` on a bare `<SEEKSLIDER>`, and the two paths meet in the same
`onAction?(.seek, …)`. The only thing the markup changes is the **22nd** commit: Mario's authored
`onDragEnd` posts `seekSeconds` after release and corona's `handlers=0` posts nothing. So
*"it seems related to this skin, corona did not have the same issue"* does not correspond to a
structural difference, and nothing in the fix rests on one. Anything built on the obvious
explanation would have been built on a skin that does not actually behave differently.

**What it costs, and why one skin can sound worse than another anyway.** `AudioEngine.seek` on a
local file stops the player node and reschedules the file from the new frame with **no ramp** — a
hard discontinuity per commit, 21 of them in ~0.5 s. Streaming is debounced 0.15 s, but only while
`isSeekingStreaming` is up, so once it resets the next mouse-move seeks immediately again. Both
skins pay the same price; how harsh it sounds is a property of the material and of how far the
pointer travels, not of the markup.

**The fix: the gesture asks for one seek, at the end.** `WMPMainView.performSlider` holds a `.seek`
in `pendingSeek` instead of sending it, and `mouseUp` hands it to `onSliderRelease`;
`cancelInputCapture` drops it, because a cancelled drag asks for no seek. Every other slider action
still commits per move — a volume drag the user cannot hear would be a broken control, and the
balance and equaliser bands are the same argument.

**Who commits it is decided after the skin's own handlers have run, not from the markup.**
`WMPMainWindowController` already awaits the release transaction; it now commits `pendingSeek` there
**only if** that transaction issued no `seekSeconds` of its own (`scriptDidCommitSeek`, set in
`applyHostCommands`). This is what the row warned could not be dropped, from both sides: 111 of the
corpus's 141 `onDragEnd` sources are `player.controls.currentPosition = value`, so committing
unconditionally would be two `AudioEngine.seek` restarts where the user asked for one — the very
click being removed — while corona and every seek slider that binds `value` and nothing else author
no release handler at all and have no other committer.

**The thumb is not deferred, only the audio.** `widgetValues` and `onElementValueChanged` are
untouched, and W151's hold keeps the host from settling the implicit
`player.controls.currentPosition` binding over the user's value for the length of the gesture — which
covers a bare `<SEEKSLIDER>` too, because `WMPPropertyRegistry` gives it that binding implicitly.

**The doubling the previous attempt hit did not reappear, and the trace says why it could not.**
`hostCommand seekSeconds=1014.577 duration=1309.727` resolves to 0.7746, which is exactly the
`pendingSeek` fraction the pointer left — the value and the divisor now come from the same gesture.
Measured after the change: corona commits once through the engine and lands at 16:12, Mario once
through its own handler and lands at 16:54, both still playing. `swift test` 2241 tests, 0 failures.
No render sweep: the change is input dispatch and a host command, and cannot move a headless render.

## W152 — not a defect: a skin's own access gate

| ID | Item | Landed |
|---|---|---|
| W152 | A skin's whole control strip takes no clicks until some *other* handler has run | Closed 2026-09-13, **not a defect**. `digitaldj`'s `loadDJ()` disables the entire strip — `bgToggle`, `bgTransport`, `bgFull`, `seek_slider`, `mute_button`, `volume_slider` and a dozen more — behind `var fLoad = (theme.loadPreference('ACC') != '--')`, and `--` is WMP's absent-preference sentinel, which this engine already answers correctly. The four `<TEXT>` handlers at `y=394.5` whose running "made it start working" are the **No access / Read-only access / Full access** links on the skin's own AutoDJ access-rights splash, which `loadDJ()` raises in the same branch (`intro_sv.visible = true`); clicking one calls `setAccess(n)`, which saves `ACC` and re-runs `loadDJ()`. The splash renders pixel-identical to `AutoDj_splashwcopy.jpg` and covers the whole 640x458 view at `zIndex=100`, so the strip is both disabled and buried — exactly as real WMP presents it on a first run. Nothing in the engine changed. **What the row did expose is an instrument gap, and that is what was built**: `WMP_RENDER_CLICK` now prints a `refused=<node>#<id> kind=<kind> <reason>` line per candidate under a `MISS` — `disabled`, `clipped`, `not-drawn-here`, `unmapped-pixel`, `mapped-to-unregistered#<id>`, `child-disabled#<id>` — which named this in a single run after two rounds of theorising about the hit map. See `reference/harness.md`. |

**When you close a `.wmz` item, move its row here in the same change** — an entry left behind in
`WMP_TASKS.md` reads as open work and gets picked up twice.

## Phase 1

| ID | Item | Landed |
|---|---|---|
| W10 | `WMP_SKIN=<path>` accepts a **directory**, sweeping the corpus in one process | Phase 1 |
| W11 | The nine probe flags, documented canonically in `skills/wmp-skin-guide/reference/harness.md` | Phase 1 |
| W12 | `scripts/wmp_skin_census.sh` and `scripts/wmp_render_sweep.sh` | Phase 1 — 14 rows, 18 PNGs, both halves of `compare` proven against a change that can be seen |

## Phase 2

| ID | Item | Landed |
|---|---|---|
| W2 | `WMPXML`: the `XMLParser` wrapper replaced with a port of `WalLenientXMLParser` | Phase 2 — **14 / 14 archives load**, from 10. Attributes keep document order and authored spelling; duplicates collapse last-wins with a `WMP0034` warning (19 occurrences corpus-wide — a hand-written regex over the same four files found 3, which is the argument for the instrument); a tag left open at EOF is a `WMP0036` warning that keeps its children. All 18 pre-existing PNGs byte-identical; the only invariant movement is that diagnostic locations now point at the `<` rather than at the end of the tag, verified against `corona.wms:42`. |
| W1 | `WMPTextDecoder`: cp1252 (already present) plus a BOM-less UTF-16 sniff | Phase 2 — added to **both** engines, positional rather than statistical, because an `iconv`-style density guess cannot tell the two byte orders apart. It claims nothing in either corpus today and is not why anything loads. It is there because neither fallback can *fail*: Windows-1252 and `isoLatin1` accept every byte sequence, so such a file decodes into null-interleaved mojibake instead of reporting a wrong guess (`.wal` B93). `.wal` is a shipped mode, so that half is measured, not reasoned about: across all 80 installed `.wal` archives, 827 of 2,384 XML and script entries are not valid UTF-8 and so reach the changed fallback, and the sniff claims **none** — the `.wal` decode path is byte-identical. |
| W3 | `WMPNode`: the case-insensitive tag fold covers every comparison | Phase 2 — verified, no change needed. Every consumer routes through `WMPElementKind(tagName:)` (which lowercases), `WMPPath.fold` for ids, or `caseInsensitiveCompare` for attributes; `authoredTagName` is only ever displayed or counted. |
| W4 | `WMPAttributeValue`: an unresolvable `res://` entry skipped with a diagnostic, siblings still loaded | Phase 2 — verified already working. `WMPSkinLoader` splits a `scriptFile` list on `;` and tests each entry, so Corona's `res://wmploc.dll/RT_TEXT/#132` warns as `WMP0029` and its four real programs still register. |
| W5 | The installed corpus wired into `swift test` as a **default-on** target | Phase 2 — `WMPCorpusLoadTests` reads `WMPSkins/` and skips only when it is absent. It asserts whole-corpus, naming every rejected archive with its diagnostic, and a second test asserts the deterministic graph dump is identical across two loads. `swift test`: 1998 passed, 0 skipped. |
| W36 | The corpus gate converted from an absolute to a **ratchet** | Phase 2 — the corpus grew to 180 and 21 rejections turned the suite red. `Fixtures/WMPSkin/corpus-baseline.tsv` records the outcome per sha256; a recorded `ok` that now fails is a regression and fails the suite, a recorded `failed` that now loads asks for a re-record, an unrecorded archive never fails the build. Re-record with `scripts/wmp_corpus_baseline.py <census outdir>` **only after improving the loader**. Proven against a regression it should catch, not just observed passing. |

## Phase 3

| ID | Item | Landed |
|---|---|---|
| W20 | One persistent `JSContext` per skin session, replacing the fresh-process-per-transaction model | Phase 3 — `WMPScriptRuntime` + `WMPObjectModel`, with `Sources/WMPScriptIsolationHelper/` and its `Package.swift`/`assemble_app.sh`/signing/verification wiring retired in the same change, recorded as **Amendment 2** to the Phase 0 decision record including what the process boundary bought that is genuinely weaker now. Proven on Corona: `OnLoad` runs to completion (ten `eq.presetTitle`, ten `popupPreset.appendItem`, `ipl.setColumnResizeMode` ×3, `theme.loadPreference` ×3) with **zero** script diagnostics, and two clicks on `bPlaylist` open the playlist pane and then close it again — state held between events, which the old model could not do at all. |
| W21 | The probe pass evaluated expressions with no scripts loaded | Phase 3 — expressions now run in the same context the skin's programs were evaluated in, so `JScript:GetEqSliderLeft(1)` resolves; a failing expression costs itself alone instead of emptying the ordered list, and a cycle costs only the keys inside it. Corpus-wide the whole class is down to **1 `expression-error` and 8 `invalid-geometry` across 482 views**. Three semantics came out of measuring rather than reasoning: the owning element is in scope (`svBottomLeft.width-left`), the `with` proxy must answer `has` only for properties the element genuinely owns (claiming every name swallowed `GetEqSliderLeft` and cost all ten equaliser sliders their geometry), and the corpus authors a trailing `;` inside the attribute. |
| W22 | `theme.loadString` | Phase 3 — implemented as `inert()`: every corpus use names a string inside `wmploc.dll`, which does not exist on macOS, so the empty string is the whole of what can honestly be answered. It gets its own `INERT` word in the call trace and its own `inert_calls` census column, because a stub that reads as working is worse than a missing member. |
| W30 | `WMP0005`'s ratio bound applies only above a 1 MiB size floor | Phase 3 — recorded as **Amendment 1** to the Phase 0 decision record, not edited in. 200:1 and `WMP0005`'s meaning both stand; the bound is simply not asked about entries below `entryCompressionRatioFloorBytes`. A ratio is not the quantity a bomb is dangerous in — expanded bytes is, and `WMP0003`/`WMP0004` already cap it — while below the floor a ratio measures how *uniform* a file is, and an uncompressed flat-colour BMP squashes 240:1 to 850:1 by being boring. Every entry over 200:1 in all 180 archives is a `.bmp`; largest expands to **842,636 bytes** (`Israeli/map.bmp`), worst ratio **847:1** (`anime/background_blank.bmp`), against a 32 MiB entry bound. Effect: archives loading **159 → 171**, layouts **469 → 482**, 12 of the 13 draw. Collateral: all 469 pre-existing PNGs byte-identical, 13 new, none lost. `The_Doobie_Brothers` trades `WMP0005` for a genuine `WMP0015` the rejection had been hiding (W33). Both halves proven by fixture: `small-high-ratio.wmz` (64 KiB, ~830:1) admitted, `excess-ratio.wmz` (2 MiB, ~1000:1) still rejected. Baseline re-recorded — 180 rows now, from 177, because W35 was dropping three of them. |
| W7 | An **empty** resource attribute costs one image, not the whole view | Phase 3 — `WMPResourceProviding.resolve` now returns nil for an empty authored path instead of throwing `WMP0024`. An empty attribute names no entry, which is what every caller already means by "no such resource"; it is an authoring omission, not a sandbox escape, and the loader has always warned `WMP0023 Optional image resource is empty` for the same attribute — only the view's survival was missing. Measured over 180 archives: **`WMP0024` 40 → 0**, layouts **429 → 469**, and six skins that drew literally nothing (`Beck`, `Melvin`, `MSN`, `Spider-man`, `springflower`, `tubeframe`) now draw. Collateral: all **429** pre-existing PNGs byte-identical, 40 new, none lost; `WMP0032` unmoved at 82. Not taken on trust — `springflower/base@1x.png` and `tubeframe/TubeFrameView@1x.png` were opened and show real skins. `testAnEmptyResourceAttributeCostsOneImageAndNotTheView` was proven by reverting the one-line guard and watching it fail on `[WMP0024]`. |
| W35 | The harness stopped losing its own measurements | Phase 3 — every harness line is now one unbuffered `write(2)` (`WMPHarnessOutput.emit`) instead of `print`. The 180-archive run lost **three** blocks, not one: `CALL vSKIN Windows_XP_Media_Center_Edition.wmz` cost the Enhanced_for_XPS9 block and swallowed the next skin's, and `amped2` and `Plus! Hard Boiled` were truncated with **no splice at all** — the collision consumes the record prefix a prefix-scan needs, so the detector saw one of three. Byte-identical across two full sweeps and absent on a two-archive corpus, so it was the buffered stream, not the content. After: `load failed=21, ok=159`, zero damaged, zero not-run, and the recovered blocks match their solo runs line for line. Both scripts additionally now check each loaded block's `RENDER-DUMP` count against the `views=` its own `LOAD` declares, which flags `amped2` on the old capture and nothing on the new one. `testEmitsEveryLineWholeUnderConcurrentWriters` proves the emitter, and was itself proven by splitting one write in two and watching it fail. |

## Phase 4

| ID | Item | Landed |
|---|---|---|
| W33 | `WMP0015` oversized image | Phase 4 — **the bound was the wrong shape for the format, and the guard it was standing in for was never the one it provided.** `imageDimension` was 8,192, a texture-size number, in an engine that produces no textures. A WMP slider, progress bar or volume control is authored as one horizontal filmstrip of frames, so an ordinary skin resource is thousands of pixels wide and a few dozen tall. A header scan of all **3,684** `.bmp` entries in the 180 archives found exactly **four** images over 8,192 on an axis and all four are filmstrips: `pharaoh/seek_steps.bmp` 15990×20, `Nautical/vol_slider.bmp` 9494×144, `The_Doobie_Brothers/vol_anim.bmp` 9152×45, `Ice/Vid-set.bmp` 9144×12. The largest is 412 Kpx against the 32 Mpx `imagePixels` bound sitting beside it — three orders of magnitude — so the old value cost three skins their entire load and a fourth its only view while protecting nothing. Raised to **32,768**, with the argument written down rather than assumed: `imagePixels` is the memory guard, it is unchanged, and it binds first for anything remotely square (32,768 wide *and* under 32 Mpx means at most 976 tall), leaving the axis bound only its two real jobs — keeping `bytesPerRow` far from overflow at 128 KiB/row, and rejecting a declared dimension that is nonsense on its face. `WMPPhase0Limits` is the sandbox contract, so "never relax a limit to make a skin load" was met on its terms and not waived: the test applied was *name what the bound protects against, then show something else still provides it at the new value.* Effect over 180 archives: loading **177 → 180**, layouts **508 → 515**, `WMP0015` **4 → 0**, and **the corpus now has no rejections of any kind** — Tier 1a is empty and load level has stopped being a number that can rank anything. All four skins were opened, not counted, and two facts came out of looking that no census column carries: `Nautical/vol_slider.bmp` is a **GIF** with a `.bmp` extension (`GIF89a` magic), which is why the archive-level BMP sniff never saw it and the rejection arrived later from ImageIO — so a rejection count undercounted this code's reach by a whole skin; and `Ice`, `pharaoh` and `The_Doobie_Brothers` draw their transparency key out of the box, joining **W8**. Re-measuring W8 while there found the larger error: it had been scanned for `#FF00FF` only, and counting `#FF0000` too takes it from 23 views/21 skins to **37 views across 34 skins**, 11 of them pure red. Test coverage was repaired rather than assumed — `oversized-image.wmz` (8193×8193) had silently stopped testing the axis bound and now passes on the *area* bound alone, so `oversized-image-axis.wmz` (32769×10, 328 Kpx, rejectable by nothing else) pins the axis bound and `filmstrip-image.wmz` (15990×20) pins the admitted case a future narrowing would break. Corpus ratchet re-recorded: exactly three rows flip `failed WMP0015` → `ok`, no others move. |
| W32 | `WMP0022` multiple `.wms` in one archive has no selection rule | Phase 4 — **the corpus names the right answer without naming the rule, and that gap is recorded rather than papered over.** Both archives ship a second `.wms` that is an author's leftover, not a second skin: `Nautical` carries `sample.wms` beside `Nautical.wms`, `Sports` carries the `saltmine.wms` template it was authored from beside `ExtremeSports.wms`. Both are skins Microsoft shipped with WMP 7, so the Player plainly picks one, and a rejection was a black window over a working skin. Ground truth came from resource resolution: `sample.wms` references 22 images and scripts and **all 22** are absent from the archive, `saltmine.wms` references 39 and **38** are absent, while both shipping definitions resolve **every** resource they name. That identifies the file; it is deliberately *not* the implemented rule, because resolving every candidate to choose between them is work the loader should not do and would decide nothing in the other 178 archives. Against that ground truth three cheap rules are indistinguishable — archive order, case-insensitive alphabetical order, and newest mtime each pick the shipping file in both. **Archive order** is implemented because it is the only one with warrant outside this corpus: it is what a loader that enumerates and takes the first match does, and the WMP SDK's packaging guidance to add the skin definition to the archive first is only meaningful advice if written order is what the Player reads; alphabetical and mtime agreeing here is a coincidence of two archives whose leftovers sort late and are older. `WMP0022` is now a **warning** naming the discarded files, so the first archive this rule picks wrong appears in the census instead of being decided in silence — it fires exactly twice corpus-wide, both correct. Effect over 180 archives: loading **175 → 177**, layouts **506 → 508**, `WMP0022` rejections **2 → 0**, leaving W33's three `WMP0015` as the only rejections left and emptying Tier 1a of everything but it. `W6` is unmoved at 86 views across 47 skins and the same 12 skins draw nothing. Collateral: closing this exposed a **census defect** — `Nautical` lays out its view and then fails to rasterize it (`vol_slider.bmp` 9494×144, a second W33 case), emitting both a stats `RENDER-DUMP` and a `RENDER-DUMP … FAILED` for one view, which the damaged-log detector's `views= == dumps` arithmetic read as a lost block. It now counts **distinct view ids**; the full run reports zero damaged. A live defect misread as a lost log is the exact failure that check exists to catch, pointed the wrong way. |
| W31 | `WMP0021` "one `.wms` at root or inside one wrapper directory" is too narrow | Phase 4 — **the premise was wrong and the layout rule needed no change.** All four rejected archives (`bruteforce`, `Need_for_Speed_Underground`, `QuantumRedshiftWMPSkin`, `SplinterCellWMPSkin`) hold exactly one `.wms` at their root. They also hold `01 00 01 00` where the local file header at file offset 0 should hold `PK\03\04` — one damaged signature per archive, always the physically first entry, with the EOCD, the whole central directory, every other local header and every deflate stream intact. `unzip` and WMP both read them because both work from the central directory; `ZIPFoundation` reads each entry's local header through a signature-validating serialiser and **ends its iteration** on a `nil` rather than skipping the entry, and in all four the damaged header belongs to the first central-directory record. Enumeration therefore yielded **zero** entries and the loader named the last rule the empty list failed. `WMPArchiveHeaderRepair` walks the central directory and rewrites a local header signature only where the header already agrees with the record pointing at it — same file-name length, same file-name bytes — so arbitrary data can never be promoted into an entry; a file that is merely not a ZIP still fails `WMP0001`. Gated on four bytes, so the other 176 archives pay one read and take the untouched file-backed path; ZIP64 and misplaced central directories are left alone; nothing is extracted to disk; CRC verification of every repaired entry is unchanged. The one new bound, `repairableArchiveFileBytes` (32 MiB), is a ceiling on a case that previously could not load at all, not a relaxation. Effect over 180 archives: loading **171 → 175**, layouts **482 → 506**, `WMP0021` **4 → 0**, and the five remaining rejections are exactly W33 (`WMP0015` ×3) and W32 (`WMP0022` ×2). `SplinterCellWMPSkin/mainView@1x.png` was opened, not counted: it draws the real skin, and shows the magenta W8 keys out of the box. Both halves proven by synthetic fixture — a real ZIP with that one signature scribbled over now loads, and 8 KiB of `0x01` still fails `WMP0001`. |

## Phase 5

| ID | Item | Landed |
|---|---|---|
| W34 | `WMP0033` image decode failed | Phase 5 — **the bitmaps are fine; ImageIO is stricter than Windows.** Filed as 4 views in 4 skins from a census column; a sweep of **all 3,687 `.bmp` entries in the 180 archives** through ImageIO found **9 files in 5 skins**, so the row was short by a whole skin (`circle`, whose two casualties are both mapping images — invisible to a render dump, and the reason a blackout count undercounts this code). Eight of the nine share one header shape: `biClrUsed` zero with `biClrImportant` set to 150–255. Windows reads the palette size from `biClrUsed` alone and treats `biClrImportant` as advisory; zeroing that one field makes ImageIO accept all eight, which is the proof that the defect is the reader and not the art. The ninth, `YIL!OMA2K/jmap.bmp`, is a BI_RLE8 stream that walks clean — 440 rows, every row exactly 530 px wide, a proper end-of-bitmap marker, structurally indistinguishable from `xMain Body.bmp` in the same archive, which ImageIO reads — and no header field ImageIO objects to; it is simply refused. **`WMPBitmapDecoder`** is therefore a bounded in-house BMP reader (core/40/52/56/64/108/124 headers, 1/4/8/16/24/32 bpp, BI_RGB, BI_BITFIELDS, BI_RLE4/RLE8, both row orders), used **only** when ImageIO has already failed on a `.bmp`, under the same `maximumDimension`/`maximumPixels`/`maximumDecodedBytes` bounds applied before any allocation — an oversized bitmap still fails `WMP0034`, and no limit was relaxed. Effect over the 179-archive corpus: `WMP0033` **4 → 0**, views laid out **574 → 579 of 595**, `WMP0032` unmoved at 28. All five skins were opened rather than counted: `bluegrid`, `cerulean`, `Radio`, `YIL!OMA2K` and `circle` draw their real artwork, colours in the right channels. Two facts came out of looking. `circle` was never in the row because a broken *mapping* image costs clicks, not pixels — the class is wider than "views that draw nothing". And the first live click on the newly-drawing `bluegrid` found **W47**, which had been unreachable because nothing that uses a mapping mask had ever drawn. |
| W47 | Mapped button state artwork was mirrored vertically | Phase 5 — **found live, and only findable live: no skin using a mapping mask drew until W34 landed.** Reported as "clicking the top left icon makes the bottom left icon highlight" on `bluegrid`. Hit testing was cleared first and headlessly: a `WMP_RENDER_CLICK` scan down the sidebar resolves `bgPl`/`bgVis`/`bgEq` in the right order, and an independent decode of `SideBar_MAP.bmp` puts its four colour bands at rows 7–22, 41–60, 78–94, 113–127 — every hit *and* every miss in the scan matches, and the fourth button is silent because its own script disables it. So the wrong thing was what got painted. `WMPRenderer` clipped the `hoverImage`/`downImage` through the mapping mask with a bare `context.clip(to:mask:)`, and Core Graphics maps that mask through the current CTM — which in scene space is y-flipped, while every image draw goes through `drawImage`'s counter-flip. The mask therefore landed mirrored against the artwork it was masking. Fixed with a `clip(to:mask:context:)` applying the same counter-flip; it cannot use `saveGState`/`restoreGState`, because restoring would discard the clip along with the transform, so the CTM is undone by hand after the clip is resolved. The pre-existing mapped-render test could not see this: its map splits left/right, where a vertical flip is invisible. `testMappedStateArtworkIsNotMirroredVertically` splits top/bottom and was proven by reverting the fix and watching it fail with the two halves' colours exchanged. |
| W8 | A view draws its transparency key instead of keying it out | Phase 5 — **the engine knew one key per image and the corpus authors two.** The row was scored on colour (magenta, then magenta and red) and the cause was an attribute: `clippingColor` — the colour WMP cuts out of a subview's own artwork to shape the window — existed nowhere in `Sources/`, `Tests/`, `scripts/`, `docs/` or `skills/`, and **103 of the 180 archives author it**. A node commonly declares it *alongside* `transparencyColor` with a **different** value (`Alpine7618_v09`'s main subview: `clippingColor="#FF0033"` and `transparencyColor="#FF00FF"`), so even the skins whose transparency key was honoured painted the other one as a flat slab over most of the window. Four small parts: `clippingcolor` joins `WMPAttributeValue.colorNames` (without it `#FF0033` classified as a literal and the builder's `color()` never saw it), `WMPSceneImage.colorKey` becomes `colorKeys: [WMPColor]` filled in authored order and deduplicated, `WMPColorKey.applying(_:to:)` clears every key in one pixel pass, and `WMPImageStore` carries all of them in its cache key. Measured the same way on both sides — opaque pixels equal to a colour that skin's own `.wms` declares, over the dumped PNGs: `Alpine7618_v09/view-2` **80.2% → 14.4%**, `v2_underworld/start` **78.6% → 1.1%**, `pharaoh/view-2` **51.0% → 0.0%**, `Plus! Mecha/mediaSwitcherView` **50.5% → 5.9%**, `gadget/view-2` **33.3% → 0.5%**, `polygon/view-2` **33.0% → 0.0%**, `Tomb Raider 2/view-2` **32.0% → 0.0%**. Corpus-wide, views at or above the 5% threshold fall to **28 across 26 skins** from the 37/34 this row recorded, and every worst case it named is gone. No collateral: all 180 archives still load, **580 views still lay out**, and the 28 remaining `RENDER-DUMP … FAILED` are all `WMP0032` (W6's known remainder) with no new decode failures. Accepted by the reporter in the running app on the shaped skins, which is the only place a window shape can be judged. `testClippingAndTransparencyColorsAreBothKeyedOut` pins both halves — the scene's key list and the rendered pixels — and was proven by reverting the builder to `transparencyColor` alone and watching it fail with `[#FF00FF]` against `[#FF00FF, #FF0000]`; `testEachKeySetIsDecodedAndCachedSeparately` pins the cache key, which would otherwise hand the two-key request the one-key image. What the row was measuring but not caused by this defect is refiled as **W48**: a `BUTTONGROUP` blits its whole sheet regardless of its mapping image, and `Main_Street` shows a flat colour its markup never declares as a key at all. |
| W6 | A view whose size is computed in script must still lay out | Phase 5 — closed in three parts, and the last of them was not the cause the row named. It began at **89 views across 48 skins** with 12 skins drawing nothing; sizing a view like every other node (authored literal, then script override, then the natural size of its own `backgroundImage`, then the union of the subtree it can place from literals and artwork alone) took it to **28**. **The row's account of that remainder was wrong.** It blamed a script-computed size, `width="jscript:theme.loadPreference('WD')"` in `cyberchannel/playview`; that attribute does not exist — `cyberchannel.wms` authors no `jscript:` geometry at all, only `onclick` handlers. Measured over the 180-archive corpus, all 28 were one shape: **a view with no drawable content**. 25 skins author `<view id="controlView" backgroundColor="none">` holding only `<player>` and a hidden `<video>` — a windowless view whose whole job is to run an `onLoad` with host bindings and hand off; `pharaoh` writes the same idea explicitly as `<view id="vGhost" width="0" height="0">`, which is the direct evidence that WMP supports it; `cyberchannel/playview` is a bare `<VIEW><PLAYLIST/></VIEW>`. So the fix was to stop rejecting them: a literal or scripted `0` is an authored answer rather than a missing value, and a view nothing sizes and that can place nothing is `0x0`. The builder still invents no geometry — **`WMPMainWindowController` is what refuses to make a window out of one**: initial load walks its candidate list (persisted view, then `vPlayer`, then document order) running each view's script and following its `setCurrentView` until a view has a canvas, and `switchView` runs a windowless view's script, honours its host commands, and stays put. Effect over the 180-archive corpus: **608 views dumped, zero `RENDER-DUMP … FAILED`, and `WMP0032` is zero corpus-wide.** The sweep diff also moved 34 views that were *not* in the row, and every one is a correction: a `previewView` / `mediaSwitcherView` / `versionView` splash whose own script does `view.width = 0; view.height = 0; view.backgroundImage = ""; theme.currentViewID = "..."` and was being ignored because a `0` override failed a `> 0` test. Microsoft's own `auto.js` in `Official_Xbox_XP` does exactly this, with a comment saying it is deliberate. No player view changed. Accepted by the reporter in the running app on `WALL-E` and `AlienMorph`, which now open on `mainView` instead of a static preview bitmap. `testViewWithNoSizeAndNoContentIsEmptyRatherThanRejected`, `testViewAuthoringAnExplicitZeroSizeKeepsIt` and `testScriptOverrideOfZeroCollapsesAViewThatHasArtwork` pin the three halves; the first replaces `testViewWithNoSizeAndNoArtworkIsStillRejected`, which asserted the contract this reverses. **What running `controlView` for the first time exposed is refiled as W49:** `theme.openView` is unimplemented and **83 skins call it**. |
| W49 | `theme.openView` | Phase 5 — **the row's reach and its account of the cause were both off, and measuring them was most of the work.** It read `Error: WMP: unimplemented theme.openview (theme member)`, filed at 83 of 180 skins and attributed to the 25 windowless `controlView`s W6 had just made runnable. The archives that name `theme.openView` at all are **57 of 180**, and **not one of them authors a `controlView`** — the two facts W6 left next to each other are unrelated. Counting them is its own trap: neither a raw `grep -a` over the decompressed archive nor `strings` finds all 57 alone, each missing skins the other sees (they split the `Revert` pair between them), so the honest number is the union. What the member actually costs is ordinary buttons: `circle` opens `vPl`, `vSettings` and `vVid` from three `onClick`s, `pharaoh` opens `vGhost`, `vRos` and `vGhostAutoDetect`, and before this the click did nothing at all — the unimplemented member aborted the handler on its first statement. **The decision the row asked for, made rather than deferred:** WMP opens the named view as an additional window and this app has one WMP window, so `openView` is neither aliased to `setCurrentView` nor given a second `WMPMainWindowController`. It posts its own `openView` host command; the controller presents the view and pushes the one it covered onto `openedViewStack`, and `theme.closeView` pops back to it instead of ordering the window out. The return path is the point: without it, opening a settings panel is W46 with no way home, and `closeView`'s old `orderOut(nil)` would have made the window disappear. It is **live**, not `inert()` — a view is presented and the skin can come back — and the one thing lost, the extra window, is recorded in `reference/object-model.md` because no call trace can show it. Initial load treats `openView` and `setCurrentView` alike in exactly one place, the windowless-view redirect, where neither can be a window operation. Measured over the 49 archives a text sweep found: `theme.openview` is **gone from the handler-error tally entirely**, 229 views dumped, zero skin failures, and the errors left are other rows (`mediacenter` ×61 = W37, `eq.speakersize` = W39, `alphaBlendTo` = W38, `theme.closeview` = W41). Accepted by the reporter in the running app. `testOpenViewPostsItsOwnHostCommandAndKeepsTheHandlerRunning` pins the command, the non-aliasing, and the statement *after* the call still running — proven by reverting the member and watching it fail — and `testOpenViewWithNoViewIDStaysUnrecognised` pins the empty-id case, which must stay in the tally rather than post a command the controller would discard. **Found while closing this and deliberately left out of it: `theme.openViewRelative`, filed as W50.** |
| W65 | The skin draws its own controls — sliders, `alphaBlend`, `passthrough`, text faces | Phase 5 — **the largest single hole in the engine was that a slider had no thumb.** 163 of the 177 archives `scripts/wmp_markup_census.sh` can read author a `SLIDER` and 163 give it a `thumbImage`; the builder drew the track and stopped, so every seek bar, volume control and equaliser band in the corpus rendered as an empty groove that could still be dragged invisibly. `WMPSliderMetrics` is the pure geometry — `direction`, `borderSize`, `min`/`max`/`value` — and the builder emits the thumb and the `foregroundImage` progress fill as ordinary paint commands, so nothing new reaches the renderer. Three rules in it are claims about WMP that the census forced: **vertical is the common case** (1,968 `direction` attributes, 1,312 of them vertical — every equaliser band), **maximum is at the top** of a vertical slider, and **`borderSize` is dead track at both ends** (2,309 uses across 171 skins) that a thumb drawn without it overhangs its own artwork by up to ten pixels. `WMPMainView.performSlider` reads the pointer back through the same metrics, replacing a `frame.width`-only calculation that gave a 9 px-wide equaliser bar its full 28 dB range in nine pixels of *sideways* travel. **Where a bound slider writes was the other half:** a `.wmz` almost never uses the semantic `<VOLUMESLIDER>` tag, it authors a plain `<SLIDER value="wmpprop:player.settings.volume">`, so `WMPTransportAction.boundAction` derives the action from the binding the skin declared, and `WMPObservablePropertyRegistry` learned `eq.gainLevel1`…`10`, `eq.enabled`, `eq.preamp` and the two network progress paths it needs to answer them. Three attributes landed with it, each measured before it was written: **`alphaBlend`** (38 skins, and 717 of its 778 uses are `alphaBlend="0"`), inherited down the subtree and dropped from the command list entirely rather than drawn at zero opacity; **`passthrough="true"`** (82 skins), which stops a decorative overlay swallowing the controls it covers; and **`TEXT`'s real attributes** — `fontFace` is authored by **109** skins against `fontType`'s 21, and reading only the latter had been rendering every one of them in the default face, plus `fontStyle` italic/underline as a *set* (`"UNDERLINE, bold"` is authored), `fontSmoothing` (95 skins) and `disabledForegroundColor`. Two elements stopped being wrong: `CUSTOMSLIDER` (93 skins) is a slider rather than an unknown tag, and **`EQUALIZERSETTINGS` is not a widget at all** — 163 skins author `<equalizerSettings id="eq" enabled="true"/>` with no geometry, and treating it as one hung an AppKit panel of `NSSlider`s over the artwork the skin draws its own bands with. **W9 closed with it**: `WMPVideoPlaceholderView` filled every `<VIDEO>` frame with opaque black over the skin's own art in 166 of 177 archives, and an audio player has nothing to put there instead, so the overlay is gone and the class with it. Measured by full corpus sweep, 179 archives: **198 of 545 images changed, none lost, none new, and no skin stopped loading.** The differences were looked at, not counted. `bruteforce/eqView` gains ten thumbs where it had ten empty outlines; `corona/vPlayer` gains its seek and volume thumbs; `xsn_sports` (6 views) and `livin_it_skate` switch from a white shell to the orange and green ones their markup actually asks for — both stack eight `mainBackN` subviews of which only `mainBack1` is `alphaBlend="255"`, so the engine had been drawing the topmost of eight rather than the one authored visible. Exactly one skin draws *less*: `QuickSilver` (both releases) loses the equaliser panel it had been showing over its player, because `eqsubview` is `alphaBlend="0"` and is faded in by script — which is the authored default state, and is **the cost of honouring `alphaBlend` before `alphaBlendTo` (W38) exists**, recorded there. `WMPPhase5Tests` pins each rule with the corpus number that motivates it, including a rendered check that the thumb's red pixels and the fill's green ones land where the scene placed them; `testAlphaBlendZeroHidesTheNodeAndItsSubtree` was written expecting the child to be absent, failed against a command emitted at alpha 0, and is why an invisible node no longer reaches `visibleBounds` or any dirty rect derived from it. **The instrument is new too**: no existing probe could see an attribute the graph parses and the engine ignores — not an unknown tag, not an unknown member, not a diagnostic — so `scripts/wmp_markup_census.sh` measures authored demand directly, and it exists in the shape it does because `grep` silently reports **nothing** on these UTF-16-derived files rather than reporting matches: the first census run returned a confident table of zeros. |
| W58, W59, W60, W61, W62, W63 | The rest of the skin's own controls — position maps, animation, cursors, tab stops, clipping images, and the native three | Phase 5 — the second half of the phase, and **three of the six were answered by reading the corpus's own art rather than by choosing a design.** *W58, `CUSTOMSLIDER` (93 skins):* `ALXMorph/seek_map.png` is 86x10 whose every column is one grey stepping 0, 2, 5 … 252, so `positionImage` is a **greyscale ramp whose luminance is the fraction**; its `seek.png` is 86x600 against that map and its `volume.png` is 2232x38 against a 72x38 one, so **`image` is a filmstrip** whose axis is whichever is a whole multiple of the map and whose frame the value picks. That makes the control the size of the *map* — sizing it from `image` makes it 2,232 px wide — and makes a drag read its value out of the map, which is why the element exists: its track need not be a straight line. *W59, animation:* the corpus was measured before it was ranked, and it is **not** a tail item — 2,166 multi-frame GIFs across **90 of 180 archives**, most three to six frames. The clock lives in `WMPRenderer.render(clock:)` rather than in the scene, so a 10 fps GIF costs a re-render and never a rebuild (a rebuild runs the skin's script transaction), and `animationCadence(for:)` hands the repaint loop the union of only the animated frames. `WMP_RENDER_CLOCK` exists because **a render dump is a still**: frame zero is indistinguishable from an engine that never animates, so the flag was proved before it was trusted — `Xbox Live Skin` at 0, 1.5 and 3 seconds gives three different images (4,475 and 3,917 pixels apart) with its logo visibly moving. *W60, `cursor` (145 skins):* the named set is the whole feature — 2,246 of 2,319 non-empty values are `hand`, `sizenwse`, `system` and peers — and the fix was as much a *measurement* repair as a feature: `cursor` was classified as artwork by name, so every named cursor was reported as a **missing bitmap**, 546 such lines corpus-wide, now zero. The ~70 `.cur`/`.ani` files stay resources and resolve to no cursor (W67). *W61, `tabStop` (119 skins):* `"false"` is authored 544 times against `"true"`'s 170 — a skin marks most of its controls *out* of the ring — and the ring was built from every enabled control. *W62, `clippingImage` (25 skins with a non-empty one):* the attribute was **not in `resourceNames` at all**, so it parsed as a literal and could never resolve — found because the test asserted the scene carried the mask rather than only checking pixels. It is what makes a shaped window shaped: `TDK`, `elvis`, `Secura`, `portals` and the six `US *` service skins each drew a black or grey rectangle behind their round artwork, and `US Navy/MainPlayer` alone drops 43,948 opaque pixels it should never have had. *W63:* `POPUP` is an equaliser preset menu in all four skins that author one, filled by their own `appendItem` calls (`WMPScriptOutput.listItems` carries them out of the transaction) — the four hardcoded entries it used to show appear in no skin's markup or script; `EDITBOX` is a real text field whose `value` is a **string**, needing its own `setWidgetText` path, since nine of the ten are `plSearchEdit`. `LISTBOX` is the one thing this phase could not finish, and it is refiled as **W66**: the control draws and reports its selection, but its rows come from a script walking `player.mediaCollection`, which this object model does not answer — a host-surface decision, deliberately not faked with rows the player invented. **Two defects were caught by the tests rather than by the corpus, both of them mask orientation.** The clipping mask was built as a `CGImage` *image mask*, which `clip(to:mask:)` reads inverted against the grayscale convention `WMPMappingImage` already set, so it kept exactly the half it should cut; and the row order was then "corrected for CoreGraphics" when a `CGImage` drawn into a bitmap context already arrives top-row-first — W47 by a second route. Only a **top/bottom** fixture can see either, which is why `WMPPositionMap` gained a vertical-ramp test: a horizontal ramp is identical under a vertical flip. Measured by full corpus sweep against the pre-phase baseline, 179 archives: **272 of 545 images changed, none lost, none new, no skin stopped loading**, `RENDER-DUMP … FAILED` unmoved at 62 (all of them the zero-area `controlView`s W6 admits and the renderer refuses by contract), and 231 fewer invariant lines, all of them retired false cursor-resource reports. |

## Phase 6

| ID | Item | Landed |
|---|---|---|
| W70 | Nothing ranks a view by how much of it failed to resolve | Phase 6 — **the rule is a ratio, and the reporter's own control is why.** `unresolved` had sat in every capture since the sweep existed and no rule looked at it, so `ALXMorph/mainView` — 15 nodes, 15 unresolved, five hit targets where a whole player's controls should be — was invisible until a human opened the skin. A raw count ranks nothing: `unresolved > 0` is true of most views in the corpus, and corona, the skin the reporter called working, carries 8 on `vPlayer` against 66 nodes. `scripts/wmp_skin_census.sh` now scores every view as `unresolved / (nodes + unresolved)` — the denominator is every node the view *declared*, because `nodes` is `resolvedNodeCount` and dividing by it divides by zero exactly where the defect is worst (`Alienware Invader`: 2 resolved, 18 unresolved) — and writes `starved.tsv` plus `hits == 0` and `commands == 0` columns every run, naming the worst rows on stdout. Measured 2026-09-08 over 179 archives and 607 views: **41 views across 36 skins resolve under half of what they declare, 79 across 49 have no hit target, 65 across 37 draw nothing.** The ranking immediately disagreed with the hand-written one: the worst are `Disney_Mix_Central/mainView` (2 of 25), `Batman Begins/mainView` (2 of 21), `Alienware Invader/mainView` (2 of 20) and `Cablemusic/mainview` (35 of 98), and ALXMorph — the skin the row was written about — sits at exactly 0.50, one of the milder cases. **A promoted view is one worth dumping and looking at, never a defect on its own**: `hits == 0` is correct for a view that is pure artwork, which is why the file ranks and the census does not assert. |
| W71 | The harness cannot see AppKit, and it can | Phase 6 — **it can, the corpus is almost clean, and two of the three numbers it first reported were the instrument rather than the app.** `WMP_RENDER_APPKIT=1` hosts each scene in a real `WMPMainView`, runs `cacheDisplay(in:to:)` — the actual `draw(_:)` of the view and every overlay over it, with no window on screen and no screen-recording permission — and reports what the AppKit layer adds over the artwork. Two corrections were needed before a single number could be believed. **The rep comes back at the display's backing scale, not the view's point size**: indexing a 2x buffer in points reads the top-left quarter and calls it the window, which reported 34% of Corona as differing; presenting a 1x image into a 2x rep then diffs AppKit's upscaler against the renderer, which reported 47%. **And the baseline cannot be the renderer's own image**: `cacheDisplay` composites through the display's colour space and the renderer's context does not, so the comparison is a colour conversion as much as a measurement — 6.8% of Corona, and 61% of a four-colour fixture at deltas up to 64. The baseline is now a **second AppKit pass with the overlays hidden**, which cancels colour management exactly and gives a corpus-wide noise floor of **zero**, not "small". Attribution is by *hosted* widget only — `WMPMainView` builds overlays for `playlist`, `dropdownPlaylist`, `popup`, `editBox`, `listBox` and `effects` and nothing else, so a difference inside a slider's frame is a defect and not hosting doing its job. Measured over 179 archives: **545 of 607 views hosted and diffed, and exactly two paint outside any widget frame** — `Revert.wmz` and `Revert (1).wmz`, the two releases of one skin, refiled as **W74**. That is the whole W43 class in the corpus's default state. `testAppKitProbeSeesAnOverlayAndReportsNothingWithoutOne` proves both directions, because without the zero half "no defect" and "blind instrument" print the same line. |
| W72 | Nothing exercises a drag | Phase 6 — `WMP_RENDER_CLICK` gained a `>`-joined path form (`x,y>x,y>x,y`) rather than a second flag, because a click is a drag of one point and the two share every line of their setup. It presses, moves with the pointer captured on the object the press landed on, and releases, computing the value the way `WMPMainView.performSlider` does — the same `WMPSliderMetrics` and the same `positionImage` short-circuit, read out of the scene rather than reimplemented — and reports the value and the **drawn thumb frame** at every step. The two claims it settles are the two it exists for: `follows-pointer` and `thumb-travel`. A value that tracks while the thumb does not is a rendering defect; a thumb that tracks a value nothing else sees is a binding defect; both were previously invisible. `flat` is a distinct answer from `yes`/`no` on purpose — a slider stuck at one value is trivially monotonic and a boolean would pass it. Proved on both axes before anything was claimed from it: Corona's horizontal volume gives `0 -> 100 follows-pointer=yes thumb-travel=48`, its vertical `eq1` gives `-14 -> 14 follows-pointer=yes thumb-travel=34`, a zero-length drag gives `flat`, and a drag starting on a button gives `not-a-slider`. It looks handlers up through `WMPMainWindowController.handlers(in:event:…)`, **the app's own matcher and never a second one** — 175 of 179 archives author `value_onchange` rather than `onChange`, and a private lookup would have reported every slider in the corpus as having no handler. |
| W52 | `openstate_onchange` / `playstate_onchange` are the spellings the corpus actually uses | Phase 6 — **confirmed aliases, not a different payload, and closed together with the user-driven half of W51.** The evidence is the markup: all three are authored on the element that owns the property, `<player PlayState_onchange="onPlayStateChange();" OpenState_onchange="onPlayStateChange()" status_onChange="updateMetadata();">` being the standard template — the same element and the same handler as `PlayStateChange`/`OpenStateChange`, with `status_onchange` already carried in the `_onchange` spelling beside them. The wider family confirms it is general rather than 140 separate events: the corpus writes `width_onchange`, `left_onchange`, `height_onchange`, `visible_onchange`, `enabled_onchange` and `down_onchange` too, all naming a property. The three that this engine already dispatches are accepted in **one place** — `WMPMainWindowController.handlers(in:event:…)`, which every dispatch site already goes through — so a site cannot raise one spelling and miss the other, and no dispatch site was added. Measured over 179 archives: event demand **6,823 uses → 4,114**, 2,709 uses and 40% of the whole class drained by one change; `onkeydown` at 501 is now the largest item left. It also removed a phantom `UNKNOWN member player.settings.volume = value;updatevoltooltip()` — a handler body being read as a member path. Sweep across the change: **545 images identical, 0 differing, 0 lost, 0 new**, 2,070 tests green. `testTheOnchangeSpellingsResolveToTheEventsTheEngineDispatches` pins both spellings *and* the negative half — a `_onchange` this engine never raises must stay unmatched and keep ranking, or the tally stops measuring it while nothing runs. **What is left of W51 is the host-driven half** and stays open there: nothing yet raises `value_onchange` when a bound host property moves a control on its own. |
| W75 | A script assignment to `backgroundImage` never reaches the scene | Phase 6 — **the fix is three lines of policy, and the sweep found the one that mattered.** `WMPSceneBuilder.resolveResource` now consults `overrides.properties` before the authored attribute, for the view root as well as every other node: artwork was the one property class the script-override path skipped while geometry, colours, slider metrics and text all went through it. Reach, measured from `WMP_CALL_TRACE=1` over the 179-archive corpus rather than deduced: **45 skins** write an artwork property from script in the default state (55 writes — `backgroundImage` 49, `image` 4, `downImage` 2), of which **36 write `""`** (the store-thumbnail collapse) and **9 write a real path**. The sweep: 533 of 545 PNGs identical, **12 changed and none of them a loss** — 10 `mediaSwitcherView`s now obey their own `backgroundImage = ""` before redirecting, `Scooby-Doo_2/infoView` draws the character its `onLoad` picks, `tubeframe/TubeFrameView` gains a scripted button image. `Alienware Invader/mainView`, the skin the row was written from, goes from **0 commands and an empty PNG** to its full 406x380 player under `WMP_RENDER_SETTLE=32`. **Two things it cost, both written down rather than smoothed over**: the corpus's "draws nothing" tally moves **65 → 75 views / 37 → 45 skins**, because a collapse that now works is indistinguishable from a starved view to the ranking; and the first version resolved with `try`, where `WMPArchive.resolve` *throws* for a path outside the provider — a skin assigning a `res://wmploc/RT_IMAGE/#2024` it read off its own markup took its whole view down with `WMP0024`, **5 views across 3 skins** (`corona` and `9SeriesDefault` each lost `vPlayer` and `viewTiny`, plus `Compact/compact`). An override is runtime data and nothing it carries may reject a view: `try?`, a `WMP0023` warning, and the authored artwork left in place. `""` is an authored absence, not a missing file. `view.backgroundImage` joined the `view` compatibility list in the same change so the demand tally does not call an implemented member unknown. Evidence: `skills/wmp-skin-guide/reference/harness.md` § *After the cascade*; contract in `reference/object-model.md`. |
| W38 | `alphaBlendTo` on an element, and `setColumnWidth` | Phase 6 — **the largest row on the page, and the sweep says the fix is one line of policy plus two of arithmetic.** Filed at 26 skins / 40 uses of `alphaBlendTo` and 2 of `setColumnWidth`, re-measured at the pre-change tree over the same 179 archives and confirmed exactly: `unimplemented <id>.alphablendto` ×40 across 26 `SKIN` blocks, `.setcolumnwidth` ×2. After the change both are **0**, and the corpus's whole `WMP: unimplemented` tally falls **83 → 43** — the 42 that went are precisely these. The endpoint is applied immediately, exactly as `moveTo`/`resizeTo` are; the tween and its `onEndAlphaBlend` completion are W55. Three details were load-bearing and none of them is the call itself: (1) `alphaBlend` had to join `standardElementProperties` or a write to an element whose markup never authored it is stored inert and never reaches the scene — that alone removed `UNKNOWN member videoresetbutton.alphablend ×12` from the corpus tally; (2) it must **not** join `standardNumericProperties`, because an unset numeric property answers 0 and an unset `alphaBlend` is 255, so a skin stepping its own alpha would start from invisible; (3) `WMPJScriptCompatibility.members["element"]` is now derived from `WMPObjectModel.implementedElementMethods` rather than restating properties alone — `moveTo` and `resizeTo` had been counted as unimplemented demand since Phase 3 despite working, which is part of why this row read as the largest. **The sweep's 30 changed images are the point of the row and every one was looked at.** Nothing regressed and nothing is a fade: the calls sit in `onLoad` handlers that used to abort *at* the call, so what moved is the rest of those handlers finally running. `Rave-MP` and `Plus! Professional` now apply their own colour scheme (purple→red, wood→grey) across all five and three views; `livin_it_skate/displayView` draws one board instead of four stacked; `WoW`'s button glyphs settle at the `alphaBlendTo(100,0)` resting alpha the skin asks for; the Alienware/ALX family's `videoView` closes its brightness/contrast/saturation/hue drawer, which is what `alienware.js` does when `player.controls.isAvailable("Stop")` is false. Invariants are otherwise clean: `LOAD` differs only in `loadms`, `SCRIPT inline:` only in the tie order of equal counts, `FINDING` not at all, and no skin's load changed. **It did not do what W68 predicted.** `mainView` for `ALXMorph`/`AlienMorph`/`AlienwareTeleport` went 8 commands → **7**, not up: `mainAnimCoolantChamber` is faded *out* by the same handler, and the animation W68 wants needs W53/W54 to raise the hover and key events that fade it back in. **W77 came out of it**: the drawer ALX closes is followed by `view.width = 297; view.height = 316;`, and that write reaches no window. |
| W37 | `mediacenter` is not a host object | Phase 6 — **the largest single cause of a dead handler in the corpus, and it really was one object with nine members.** Filed at *102 of 171 loading skins*; re-measured over the 179-archive corpus at the pre-change tree it was **159 `ReferenceError: Can't find variable: mediacenter` across 110 skins**, each killing an `OnLoad` on whichever line first touched it. The row asked for the decision to be made before implementing, and the measurement made it: **every one of the nine members is `inert()`**. There is no video surface to zoom (`imageSourceWidth`/`Height` already answer 0 for the same reason), the engine draws exactly one effect with no type and no presets, and there is no high-contrast mode — nothing is behind any of it. The trap the row named was avoided a second way as well: an inert member that answered a *constant* would have looked identical from every instrument and still been wrong, because skins round-trip these (`Plus! Professional` writes `mediacenter.effectPreset` in one view and reads it back in another), so a write stores session state and the next read answers it, exactly as `player.settings.autoStart` does. `testMediaCenterRoundTripsSessionStateAndStaysInert` pins that, **proven by reverting the read to the constant and watching it fail**; `testMediaCenterDefaultsAnswerAndItsSurfaceStaysClosed` pins the documented defaults, the read-only `contrastMode`, and a tenth member still aborting its handler. Corpus-measured against a same-tree baseline worktree: **159 → 0**, runtime member errors 252 → 127, skins with a dead handler 119 → 70, and **490 images identical, 55 differing, none lost, none blank**. The differences were looked at rather than counted. `WALL-E/mainView` gained its **entire artwork** — a blank frame before. Where pixels were *lost* the skin's own default-state logic was finally running, which is what WMP does: `Gorillaz/noodle` ends its `OnLoad` with `screen.visible = video.visible = effects.visible = false`, and the Rave-MP/Back-to-the-Future drawers close because nothing is playing. **The one loss that is a real defect belongs to another row**: `Plus! Professional/videoView` lost its right drawer tab because `loadVidPrefs` reads `theme.loadPreference('vidRightDrawer') != '--'`, and W76's unset-key answer of `''` inverts the sentinel — W37 closing is what made W76 cost drawn pixels instead of two expressions in one skin. Two deliberate omissions, both recorded in `reference/object-model.md`: the paren form (`jscript:mediacenter.effectType();`, 9 skins) is not answered, because IDispatch allows a property get with parentheses and JavaScriptCore does not, and it fails visibly as an `expression-error` on an attribute nothing reads; and `effectType`/`effectPreset` are **not** wired to NullPlayer's visualization subsystem, which would be a capability (a `<WMPEFFECTS>` that can host one, and a snapshot field to answer from) rather than a member. What the queue surfaced behind it is the new top of the backlog: `alphaBlendTo` went 18 → **26 skins / 40 uses** and W38 is now the largest row on the page, plus new demand for `player.dvd` (3), `eq.bypass` (2) and `vidinfo`/`vidZoom`/`videoWin` (W40's cross-view class). |

## Phase 7 — hover, and the live input session that came with it

Every row here was closed on 2026-09-08 in one session: W54 was the work, and the other five are
what driving the app to prove it uncovered. **None of the five was visible to any headless probe on
this page**, and all five were found with one instrument — `WMP_TRACE_INPUT=1`, now documented in
`skills/wmp-skin-guide/reference/harness.md`.

| ID | Item | Landed |
|---|---|---|
| W54 | Hover events are parsed and never raised | Phase 7 — `WMPMainView.setHover` owns the transition and raises **both edges in order**: `mouseout` on the node left, then `mouseover` on the node reached, and nothing while the pointer stays inside one node. Hover is the only dispatch site gated on the markup actually authoring a handler (`WMPMainWindowController.hoverEvents`): a transaction rebuilds and re-renders the whole scene, and the pointer crosses a row of buttons on the way to the one it wants. `onmouseover`/`onmouseout` joined `supportedEvents`; `onmousemove`, `ondblclick`, `onfocus` and `onblur` deliberately did not — same shape, still unraised. New probe `WMP_RENDER_HOVER=<view>@x,y[;…]` walks a pointer path through the same `handlers(in:event:…)` call the app dispatches through. Proven on `Melvin` (36 authored `onMouseOver`, the corpus's heaviest): the character's eyes follow the pointer across two buttons and return when it leaves |
| W79 | A borderless `.wmz` window is never key, so **no** mouse-moved event is ever delivered | Phase 7 — **the whole of hover, not just its script half.** `WMPMainView`'s tracking area is `.activeInKeyWindow` and the window was a plain `NSWindow`; AppKit's default `canBecomeKey` is false for `.borderless`, so `mouseMoved`, `mouseEntered` and `mouseExited` never arrived — killing every `hoverImage` in the corpus and `keyDown` with them, while clicks worked and hid it. `WMPSkinWindow` is the same two-line override the `.wal` engine landed in its Phase 43 (`WinampModernSkinWindow`) and the modern-skin windows carry as `BorderlessWindow`. Symptom in the trace: `dispatch click` lines and not one `hover` line |
| W80 | A script transaction repaints without the interaction state, erasing hover artwork | Phase 7 — the controller now carries the view's last reported `WMPInteractionState` into the script build. Before it, `Melvin`'s buttons swapped to their `hoverImage` and the `onMouseOver` transaction overwrote them milliseconds later: 16 changed pixels where there should have been 1,236, which reads as hover never working |
| W81 | A node the markup gives a mouse handler is not a hit target unless its kind is a control | Phase 7 — `WMPSceneBuilder.authorsInputHandler`, with `passthrough="true"` still winning. **537 nodes across 143 of 179 skins** author input on a kind `isInteractive` does not list — 326 `<TEXT>` across 69 skins, 90 `<EFFECTS>` across 81, 21 `<VIDEO>` across 21 (`python3 scripts/wmp_input_kinds.py`). `Sports` is the reason: ten `<TEXT>` playlist rows whose `onmouseover` hit the equaliser slider behind them. Corpus effect, measured against a HEAD worktree: hit targets **4,391 → 4,528**, with `starved`, `hits==0` and `commands==0` all unchanged. (`Sports` itself stays broken and stays in the corpus: `hilightMe`, `playMe` and `vidOnEndMove` are defined nowhere in the archive, and real WMP throws on them too) |
| W82 | Tooltips: the owner conformance was never declared, and only widgets ever answered | Phase 7 — `WMPMainView` did not declare `NSViewToolTipOwner`, so AppKit ignored the correct method it already had and showed the view's `description`: `<NullPlayer.WMPMainView: 0x…>` over every pixel of every skin. With that fixed, hit targets answer too, resolved per drawn state in `WMPSceneBuilder.toolTip` and read through the scene overrides so a script's `toolTip='Volume'` wins. Nothing had ever shown `upToolTip` — **4,712 uses across 175 of 177 archives**, `toolTip` 3,749 / 174, `downToolTip` 517 / 104 |
| W83 | `Halo 2` opens on a thumbnail view its own `onLoad` blanks | Phase 7 — reported as "no UI at all". `previewView` is the skin-chooser thumbnail, sized 280x348 by its own `preview.png`; `onLoadSkinPreview()` writes `view.width = 0`, `view.height = 0`, `view.backgroundImage = ""` and redirects to `controlView`, which opens the real player. Judging a view only on the canvas it had *before* its script ran presented the thumbnail and let the handler blank it — then the size was saved under `wmpViewSizes` and handed back on every launch after. A view that writes zero to its own width or height is now windowless and its redirect is followed: `previewView → controlView → mainView`. The same shape is authored by the ten `mediaSwitcherView`s W75 uncovered |
| W84 | Every GIF looped forever, and **no view timer in the corpus had ever fired** | Phase 7 — two defects behind one report, "the shutter closes after it opens". `WMPImageAnimation` ignored the loop count, so `Halo 2`'s 34-frame `m_shutter_open.gif` (`LoopCount = 1` — play once, hold the last frame) slammed shut and reopened every 3.4 seconds forever; loop count is now decoded, a finished animation holds its last frame, and `WMPAnimationCadence.endsAt` stops the repaint loop when the scene stops moving. With that fixed the shutter sat closed, because `scheduleTimers` calls `cancelScriptTimers()` on every transaction and that function also stopped the **view's own** `timerInterval` — set by `apply` one line earlier — and the animation loop with it. A load transaction requesting no script timers therefore killed the view timer immediately, so `introStart()` never ran, and with it every authored `onTimer` in the corpus: clocks, seek readouts, `checkRemoteViewStatus`, ALXMorph's animations. Split into `cancelScriptTimers` (script only) and `stopAllTimers` (teardown and view switch). The trace that found it is two lines: `view-timer 1000ms` followed by `view-timer 0ms` |

## Phase 8 — the implicit transparency key

One rule, reported live on 2026-09-08 as magenta "all over the place", measured before it was
written and swept after. The instrument the row demanded is `scripts/wmp_implicit_key.py`, now
documented in `skills/wmp-skin-guide/reference/harness.md`; the rule itself is a contract in
`skills/wmp-skin-guide/SKILL.md`. Its measured residual, **W78a**, closed the same day and is the second row below.

| ID | Item | Landed |
|---|---|---|
| W78 | Magenta shows through wherever a sprite has no alpha and its markup names no `transparencyColor` | Phase 8 — Found while confirming the `Halo 2` shutter, and reported live as everywhere. `m_trans_no.png` — the transport cluster at `205,172`, 99x98, **no alpha channel, 1,084 `#FF00FF` pixels** — hangs off a `<BUTTONGROUP>` that declares no `transparencyColor`, while its siblings `mainBack`, `shutterSub` and `shutterStatic` all declare `#ff00ff`. So the engine draws the key colour and the skin shows magenta triangles in the bottom-right of the window and beside the transport row. **The hypothesis to test first, before writing any code: WMP treats magenta as the implicit transparency colour for a bitmap that carries no alpha of its own**, which is what the author of this skin plainly relied on — they keyed three siblings by hand and left this one to the default. Confirm it against a second skin before defaulting anything: a sprite that legitimately paints magenta would lose those pixels, and this is an engine-wide default, not a per-skin fix. **Measure the class, then fix, then re-render the corpus** — `scripts/wmp_render_sweep.sh capture` before and `compare` after is the check that a default this broad changed only what it should. It is at the top of this page rather than in Tier 1c because it is not one skin: it is one rule, and the reporter is seeing it everywhere. **Measured, then fixed, then swept — 2026-09-08.** The class is **527 node/attribute references across 66 skins and 437 distinct sprites** (`python3 scripts/wmp_implicit_key.py --tsv <file>`, the instrument the row asked for, documented in `reference/harness.md`), out of 22,649 drawn artwork references of which 8,833 declare a key themselves. The hypothesis holds well past the second skin: **4,979 of the corpus's 6,076 `transparencyColor` declarations (82%, 142 skins) are `#ff00ff`**, and the sprites in the class read as cut-outs at every scale — `Main_Street`'s button sheets are magenta filler between the mapped regions, `cerulean`'s close button is four magenta corner pixels, `circle`'s next/prev are seven. The fix is `WMPSceneImage.implicitColorKey`, set by the builder only when the node declares *nothing*, applied by the store only when the file authored no alpha (`kCGImagePropertyHasAlpha`), and never passed on a mapping image, position map or clipping mask. Corpus sweep over 179 archives: **87 of 545 images changed, 458 identical, none lost, none new, and all 7,996 structural invariant lines byte-identical** (the 522 differing lines are `loadms` and unordered handler tallies). **315,157 of the 377,809 changed pixels were opaque magenta before**; corpus-wide opaque magenta fell **322,410 px across 100 views → 7,253 across 15**, and the remainder that is not magenta is artwork the magenta was covering (`Plus! Bionic Dot/mainView` 29,934 px of black shell revealed). It also closes both halves of W48 as observed: `The_Doobie_Brothers/view-2` (50.4%, the `tranparencyColor` misspelling) and `Main_Street` (mini/slim/normal) draw clean. `swift test` 2,081 tests, 0 failures. What it does not prove is what a corpus sweep never proves — the window on screen; W78a is the measured residual. |
| W78a | The magenta the implicit key did **not** remove: a sprite that authored an alpha channel and paints `#FF00FF` anyway | Phase 8 — The residual W78 left, **7,253 opaque magenta pixels across 15 of 545 views**, and the row said to establish what WMP does with an alpha PNG holding the key colour before touching the rule. The corpus answered it. `scripts/wmp_implicit_key.py --alpha only` measures the complement — **76 references across 21 skins and 62 sprites** — and the falsifying check is not that count but a pairing inside it: **11 of those nodes hold two states of the same button, one exported without an alpha channel and one with, with pixel-for-pixel identical magenta** (`Half-Life_2` `m_pause_no.png`/`m_pause_hov.gif`, both 1,394; `Harry_Potter…` `bottomgroup_no.png`/`bottomgroup_hover.gif`, both 5,866; also `Dreamcatcher` and `Half-Life_2`'s logo group). Under W78's alpha veto the normal state keyed and the hover state did not, so the button turned magenta under the pointer — which no author wrote. **The alpha channel is an export format, not a statement about the key**, and the veto was a guess made without measuring the complement. `WoW/mainView`, the residual's 3.5% headline, is the same thing through a `CUSTOMSLIDER`: `volume_1.png` is a 31-frame filmstrip against an 86x84 `volume_map.png` and every frame carries the same flat magenta wedge beside a genuinely antialiased knob — the crop was already correct. The fix is one gate: `WMPImageStore.keys(_:implicitKey:)` no longer consults the sprite's alpha, and the rest of W78 is unchanged (only a node declaring no key, only blitted artwork, never a mapping image, position map or clipping mask). Corpus sweep over 179 archives: **corpus-wide opaque magenta 7,253 px across 15 views → 878 across 2**, `WoW/mainView` 3.55% → 0 and `MSN/view-2` 2.14% → 0; **13 of 545 PNGs changed and all 8,854 structural invariant lines are identical**. A fourteenth, `Scooby-Doo_2/infoView`, is nondeterministic on its own — `scooby.js` picks its character at random, three runs of one binary give two hashes — and is not collateral. The two views left are not implicit-key work: `portals/mode1` (829 px) is a `BUTTONGROUP` declaring `transparencyColor="#000000"` whose magenta sheet filler is blitted whole rather than drawn through its mapping, which is W48(a), and `Plus! Pulsar/mainView` (49 px) is a button declaring `transparencyColor="#ffffff"`, where standing aside is correct. `swift test` 0 failures. **Confirmed on screen by the reporter the same day** — the hover states that used to go magenta under the pointer draw clean. |
| W85 | Every animation restarts from frame zero on every repaint, so an intro plays over and over | Phase 8 — Reported live: "the animations keep opening and closing constantly", and "when you try to interact they are just opening and closing all the time". Found with `WMP_TRACE_INPUT=1` in one launch, after an `INPUT animation` line was added to print the clock each `startAnimation` runs on. **`animationEpoch` was rewound on every `startAnimation` call, and `startAnimation` is called by every scene rebuild** — a hover repaint, a script transaction, an `onTimer` tick. It was harmless while no view timer ever fired; closing that (Phase 7) made it continuous. The trace on `Half-Life_2`, whose script sets `timerInterval="100"`, read `epoch-was=0.008s-old`: a 2.16s one-shot intro restarted ten times a second and never reached its second frame. **The second half was invisible until the first was fixed** — every rebuild also rendered at the default `clock: 0`, so a transaction painted frame zero even with the epoch preserved. Both halves are the fix: the clock now belongs to the view (`animationEpochViewID`, reset only when the presented view actually changes or on teardown), and the four call sites that rebuild the *same* view pass `animationClock(for:)` instead of defaulting to zero; a one-shot whose `endsAt` has already passed no longer starts a repaint loop at all. Confirmed live by driving the app: the clock advances 176.4 → 179.5s across a hover sweep and two clicks where it previously reset to ~0 on each, and four window captures taken during continuous hover activity are byte-identical. `swift test` 0 failures. |

## Phase 9 — a view switch that never loaded the view it switched to

Reported live on 2026-09-08: "there are major issues with any skin that has compact mode. pressing
the compact mode button has no visual difference on any skin… you cannot access the playlist and eq…
there is no way to leave compact mode while in the skin." The reporter's own diagnosis was the exact
one: *"the only way you can tell is the playlist and eq stop working"* — the view **had** switched,
and it drew the same picture.

| ID | Item | Landed |
|---|---|---|
| W45 | No way to reach the compact view from the skin | Phase 9 — Closed by W46's fix, and the button half was already closed by W44: clicking Corona's unnamed "Mini Player" `<BUTTON>` posts `setCurrentView value=viewTiny` and the controller switches, confirmed in the live `INPUT` trace. What remained was that arriving there looked like arriving nowhere, which is W46. |
| W46 | `viewTiny` is indistinguishable from `vPlayer`, and the switch is a trap | Phase 9 — **`switchView(to:)` did three fewer things than the initial-load path, and a `.wmz` compact mode is built out of all three.** It called `transact(event: nil)`, so the new view's `onLoad` never ran; it dropped `output.hostCommands` on the presented path (they were honoured only in the windowless early return); and it never called `scheduleTimers`. Corona's `viewTiny` is authored `timerInterval="0"` and animates *itself* into the mini player from `OnTinyLoad`, which registers a timer event and writes `view.timerInterval` — a `setViewTimerInterval` host command. With the load event dropped the handler never ran, and with the commands dropped the interval never arrived, so the view sat at frame zero: **the same artwork at the same size as `vPlayer`**, which is why the render dumps of the two views are near-identical stills and why the only symptom was the drawers going away. `RestorePlayer()` is driven by the same timer, so there was no way back either. The fix raises `load`, applies the host commands after `apply` (which sets the markup interval first, the default the script overrides), and schedules the timers; the initial-load `collapsed` guard comes with it, because a view can now blank itself in an `onLoad` this path finally runs. `viewchange` is gated on an authored handler for the same reason hover is — a transaction's `timerRequests` are what *that* transaction registered, so an unconditional binding-only `viewchange` posted an empty set and cancelled the timers `load` had just scheduled. **Confirmed by driving the app** (`WMP_TRACE_INPUT=1`, CGEvent clicks at the frames `WMP_RENDER_PROBE` reports): on `corona`, clicking Mini Player at `550,313` now collapses `svVideo` and slides `t1` in — the window becomes an unmistakable mini player — and clicking Restore at `550,72` posts `setCurrentView value=vPlayer` and returns, after which the playlist drawer opens again. `swift test` 0 failures. **It did not close the whole report on its own**: the WMP9 family reaches the same dead end by a second route, which is W86 below. |
| W86 | The WMP9 family still cannot leave compact mode: a chained timer event dropped by JavaScriptCore's `for-in` | Phase 9 — Found by driving `9SeriesDefault` after W46 landed and seeing the same dead end with none of W46's causes: the view switches, `OnTinyLoad` runs, `setViewTimerInterval value=50` arrives, the timer ticks, **no diagnostic is raised**, and the video panel never collapses. **This is a JScript-vs-JavaScriptCore dialect difference, and it is fixed in the engine, never in a skin.** WMP9's `TimerDispatch` enumerates `g_grpTimerEvents` with `for-in`, copying survivors into a fresh array, and calls `eval(tEvent.end)` on an event that has just finished; that `end` string appends the *chained* event to the array being enumerated — the `ResizeY` that collapses `svVideo`, and, for `RestorePlayer()`, the one whose own `end` is `theme.currentViewID = "vPlayer"`. **JScript enumerates live and visits the appended index; JavaScriptCore snapshots and does not** (ES5.1 §12.6.4 permits either), so the chained event is dropped on the tick it was registered. The live signature is unmistakable once you know it: `setViewTimerInterval value=50` — the chain registering — immediately followed by `value=4000`, `SetTimerInterval` recomputing from the array that no longer holds it. Corona's 2002 script splices the array it is iterating instead of rebuilding it, which is why `corona` was the control and passed. **Reduced to a standalone repro before any code was written**: the skin's real `corona_tiny.js` under a bare `JSContext` with stub host objects reproduces it exactly (`svVideo.height=241`, `currentViewID` never set), and the same script with one `for-in` changed to an index loop gives `svVideo.height=0` and `vPlayer`. The fix is `WMPJScriptDialect`: a bounded source rewrite of `for (LHS in OBJ)` into a live enumeration over `__wmpEnum`, applied to every program and markup handler at evaluation. It stays a `for` statement in place, so labels, `break`, `continue` and brace-less bodies are unaffected; `var` heads stay declarations and bare heads keep JScript's implicit global; strings, both comment forms and regex literals are skipped. **The bug inside the fix is worth more than the fix**: the first version silently did nothing at all, because the scanner compared against `"\n"` and **Swift folds `"\r\n"` into one `Character` that is not equal to `"\n"`** — so the line-comment scanner ran to the end of every CRLF file, and every script in this corpus opens with a `//` banner. It passed all nine LF-only unit tests and changed the real skin not at all. `WMPJScriptDialectTests` now carries CRLF and CR-only cases for exactly that. **Reach**: 3 of 180 archives use `for-in` in script at all and **one** uses the snapshot-sensitive rebuild idiom, so the corpus blast radius is one skin — which the sweep confirms. **Corpus sweep over 179 archives: 544 of 545 images identical**, the one difference being `Scooby-Doo_2/infoView`, already known nondeterministic (`scooby.js` picks its character at random; two runs of one binary differ), and **every one of the 504 changed invariant lines is a `loadms` timing or an unordered `SCRIPT inline:` handler tally — zero lines of any other kind**. `swift test` 2,098 tests, 0 failures. **Verified live on three skins from three different families**: `corona` (Corona 2002) compact and back; `9SeriesDefault` (WMP9) compact and back, with the playlist and equaliser drawers opening again afterwards; `Main_Street` (unrelated author) 516x496 → 214x49 mini → back. |
| W87 | The compact view tears into two pieces with a gap down the middle, and closes only seconds later | Phase 9 — Reported live the moment W86 made the animation visible at all: "there is a large horizontal gap that divides the window into 2 parts when you switch to compact and then it comes together and resolves into 1 window after a few seconds." Both compact skins position their transport bar off the video panel they collapse, and both declare the wiring for it — `height_onchange="svTransports.top=svVideo.top+svVideo.height"` on the panel — which nothing raised. The dependent therefore only moved when *something else* re-laid the view out, so it trailed the panel by a frame the whole way down, and the last frame is the one that lasts: the animation ends, the timer drops to the skin's idle period, and the halves close on the next tick — 4,000 ms for `9SeriesDefault`, exactly the "few seconds" reported. Measured before any code: `WMP_RENDER_SETTLE=0.3` put `svVideo` at 25..128 with `svTransports` at 198, **a 70 px gap**. The fix registers `height/width/left/top_onchange` as dispatchable handlers and raises them in the *same* transaction as the write, bounded and once per property per transaction so two panes positioned off each other cannot loop. **The first attempt was wrong and the corpus said so.** Re-resolving the view's `JScript:` geometry expressions after the handlers looks like the general form of the same fix and is not: those expressions are an initial layout, not a live binding, and several read the property they write (`left="JScript:svBottomLeft.width-left"`), so re-running them moved **175 of 545 corpus images** and turned `Back to the Future Trilogy`'s `videoView` (33 commands / 15 hits → 28 / 8) and `ALXMorph`'s frame into scattered fragments. Restoring the pre-pass baseline first did not rescue it — the approach was wrong, not the bookkeeping — and it was reverted. The skin's own declared wiring is the mechanism; the expression set is not. **Reach**: 16 geometry `_onchange` attributes across 6 archives, `9SeriesDefault` and `corona` among them. After: every frame is flush on both skins (`svVideo` bottom == `svTransports` top at 168/103/95 px and at collapse). **Corpus sweep over 179 archives: 544 of 545 images identical**, the one difference being the known-nondeterministic `Scooby-Doo_2/infoView`, and **zero non-noise invariant lines**. Two new `UNKNOWN member` rows (`metadata.left`, `metadata.width`) appear because a handler that never ran now runs and asks for them — the demand tally recording real new demand, not a regression. `swift test` 2,100 tests, 0 failures. Confirmed on screen by the reporter: "the skin looks great". |
| W88 | A skin's own intro reveals the player and then closes it again | Phase 9 — Reported live on 2026-09-08: "the alien invader skin animates and opens to reveal controls but then it closes and is no longer responsive to the open button". **`applyHostCommands` ran after the scene was built and presented, inside the same cancellable block.** The build and the render are the slow half of a transaction, so a view timer firing during them cancels the task at `guard !Task.isCancelled` — correct for the *drawing*, because a newer transaction is already building a newer scene, and it discarded the commands with it. `Alienware Invader`'s 568-frame intro ends on the heaviest tick in the skin: `toggleShutter()` swaps `mainBack` to `main_back.png`, turns `mainBackGroup1` on and posts `view.timerInterval = 0` to stop its own animation, and building that one frame decodes the whole player's artwork, overrunning the 50 ms period. The reveal was never presented and the `0` was never applied, so the timer kept firing with the skin's own `introStatus` now true and the very next tick took the *other* branch of `toggleShutter()` — 82 frames back down to the closed shutter, which is why nothing on it answered afterwards: the buttons that were showing belong to `mainBackGroup2`. The fix applies `applyHostCommands` / `scheduleTimers` / diagnostics the moment `transact` returns, before the build, in both `dispatchScriptTransaction` and `dispatchTimer`; only the drawing is skipped when superseded, and a command that switches views abandons this transaction's scene rather than drawing it over the new view's. **Two runs of inference got the cause wrong before one line of instrumentation got it right.** The trace showed `dispatch timer` twice with no `present` between them, which reads as the second tick cancelling the first *before* it ran; a fix built on that guard is a no-op, and the second trace came back byte-identical. A temporary `txn <n> begin` / `txn <n> ran superseded=… hostCommands=[…]` pair named it in one launch — `txn 207 ran superseded=false hostCommands=["setViewTimerInterval=0"]` with no `command` line after it, and `txn 208 begin timer` immediately below. **The corpus sweep is not the arbiter here**: the sweep uses only `WMPMainWindowController`'s static helpers, none of which this touches, so it can neither regress nor confirm it — the app is the only instrument that reaches this path. Verified live: `txn 207` now stops the timer before building and presents `commands=7`, the full player, and it stays there. Pinned by `testATimerHandlerThatStopsItsOwnTimerIsObeyed`, which holds the contract rather than the overrun — nothing can make a 120x80 scene overrun a timer period — and says so. `swift test` 0 failures. Accepted by the reporter: "shutter fix looks good". |

## Phase 10 — the view the skin keeps running, and the view it only covered

Reported live on 2026-09-09: "none of the interior buttons on Alienware Invader work except the
playback and file open. all others are dead." That is not a vague report — it is exactly the split
between the buttons that call the host and the buttons that write a preference, and it named a class
of 24 corpus skins. Closing it made a second defect reachable for the first time, which the same
reporter found within the minute: "when you close an interior window it also closes the whole UI."

**Both rows are one lesson.** A `.wmz` has views that are never windows and views that are only
covered, and this engine had been treating both as "not the presented view, therefore gone". A
windowless dispatcher has to keep running; a covered view has to come back as it was left.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W89 | A skin's panel buttons write a preference that nothing reads: a windowless `controlView` keeps no timer | **25 corpus skins author a `controlView`**; confirmed live on `Alienware Invader`, where playlist, equaliser, visualisation, meta, close and minimize are all dead. Reach across the corpus — how many of those 25 use it as a *dispatcher* rather than only for an `onLoad` handoff — is unmeasured | Reported live on 2026-09-08: "none of the interior buttons work except playback and file open", which is exactly the split. Playback and Open call the host directly (`player.controls.play()`, `theme.openDialog('FILE_OPEN')`) and work. Every other button only writes a flag — `onClick="theme.savePreference('remoteCallPl','true')"` — and the thing that acts on it is `controlView`, a 0x0 windowless view the skin declares as `timerInterval="100" onTimer="checkRemoteViewStatus()"`, whose handler polls those flags and calls `toggleView(...)`, `view.minimize()` and `view.close()`. **Real WMP keeps `controlView` open alongside the player as a background dispatcher; this engine walks past it at load and only ever ticks the presented view.** The trace is one line long: `INPUT candidate controlView canvas=0.0x0.0` at load and no `view-timer 100ms` ever. The residue is visible in the user's own defaults — `remoteCallEq/Meta/Pl/Vis` all stuck `true`, written by clicks nothing consumed. **This is the other half of W6's contract, not a contradiction of it**: a windowless view correctly never becomes the window, and it also has to keep running. The work is a design call before it is code — the script context installs one view's elements at a time (`WMPScriptRuntime.contextViewID`), so ticking two views means either reinstalling elements per transaction at 10 Hz or holding a second context, and neither is free. Decide that first, then decide whether `view.close()` and `view.minimize()` from a non-presented view act on the window. Reproduce by selecting `Alienware Invader`, waiting out its intro, and clicking any of the four top buttons with `WMP_TRACE_INPUT=1`: the click dispatches, `handlers=1`, the preference is written, and nothing else ever happens. | **Closed 2026-09-09.** Reported live a second time — "none of the interior buttons on Alienware Invader work except the playback and file open" — and fixed as diagnosed. `WMPScriptContext` can now lift a view's live elements out whole and put them back (`WMPObjectModel.ElementRegistry`), so a background view runs a transaction without destroying the presented view's element state — the ids collide, every view root being `view`. `WMPScriptRuntime.dispatch` is that transaction: it commits no overrides and does not consume the observable-property changes, because a dispatcher has no window and therefore no scene; its output is host commands, preference writes and diagnostics. `WMPMainWindowController.adoptDispatcher` finds it and ticks it at its authored period, and it survives a view switch because the panel it opens is closed again by the same handler. **The reach was measured rather than left open: 24 of the 180 archives**, every one of them a `controlView` at 100 ms — the whole Skins Factory family. **The first attempt keyed the discovery off the candidate walk and worked only on a profile with no persisted view**: `wmpSkinViewID` is written on every present, so from the second launch the walk stops at the player and never reaches `controlView`. It is a scan now — a live `timerInterval` and an authored `onTimer` make it a dispatcher, not being the presented view makes it a *background* one, and a zero canvas is what makes it windowless, without which an equaliser that happens to declare a clock would run off screen. Verified by driving the app: `INPUT dispatcher controlView 100ms` at load, btnPl → `command openView value=plView`, and **Minimize — a button that writes only a preference — actually miniaturizing the window after a view switch**. |
| W90 | Closing an interior window closes the whole UI: a covered view is rebuilt from markup instead of restored | **57 of 180 archives ask for a panel by name**; confirmed live on `Alienware Invader` | Found and closed 2026-09-09, in the change that closed W89 and reported by the same reporter the moment W89 made a panel reachable at all: "when you close an interior window it also closes the whole UI". **`theme.openView` opens a second window in WMP and never touches the first; only `theme.currentViewID` replaces a view** — so a `closeView` return is a restore, and this engine was routing it through `switchView`, which loads exactly like a launch (W46, correctly, for every *other* route). The covered view therefore came back with its overrides discarded and its markup `timerInterval` reinstated. On `Alienware Invader` that is the whole player: its 568-frame intro reveals the controls by writing `mainBack.backgroundImage` and `mainBackGroup1.visible` and then stopping its own timer with `view.timerInterval = 0`, so the rebuilt `mainView` drew **nothing** — `present-view mainView 406.0x380.0 commands=0` — and the restored `view-timer 500ms` re-fired `toggleShutter()` with the skin's own `introStatus` already true, closing the shutter over the player. The user sees the entire control surface vanish, which is what "closes the whole UI" is. **The fix is a restore, and it needs all three pieces**: `openedViewStack` remembers the covered view's overrides and timer period rather than just its name, `WMPScriptRuntime.prepareForRestore` puts those overrides and the view's own live elements back instead of wiping them, and the return raises **no second `load`** and no `viewchange`. Nothing else changes: `restoring` is nil on every path but `closeView`, so a genuine view change still loads like a launch. Verified live over five open/close cycles across `eqView` and `plView` — `commands=7` and `view-timer 0ms` on every return, the player intact each time. |


## Phase 11 — NullPlayer's own windows, and the surfaces the skin already owns

Asked for directly on 2026-09-09: "implement the nullplayer native windows. use stylings from the
skin like in all other skin modes." The auxiliary-window policy had been `wmpUnavailable` since
Phase 3 — honest, and the reason the mode had no route to a track of its own. Two of the three rows
below were reported by the same person, on screen, within minutes of the first build.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W91 | NullPlayer's own windows are unavailable in `.wmz` mode | every skin | **Closed 2026-09-09.** `AuxiliaryControllerStyle.wmpUnavailable` is gone: playlist, equalizer, library, spectrum, analysis, PeppyMeter, Flow, Cava, waveform and the visualizer all open in WMP mode, in chrome derived from the active skin and never from another family's artwork. **The route was already built by `.wal` and only needed making family-neutral**: `WinampModernSurfaceStyle`/`Chrome` moved to `App/Skinning/` as `SkinnedSurfaceStyle`/`SkinnedSurfaceChrome`, built from seven colours (`SkinnedSurfaceRoles`) and nothing else, with the Wasabi derivation left behind as an extension and the old names as typealiases — so no `.wal` call site moved and its behaviour is byte-identical. The 11 shared views now read one property, `WindowManager.hostedSurfaceStyle`, a `switch` on the controller family. `WMPSurfacePalette` supplies the `.wmz` half, declaration-first: the skin's `PLAYLIST` roles, then `VIEW`/`SUBVIEW` background plus `TEXT` foreground, then the **dominant opaque colour sampled from the presented view's own rendered bitmap**, then an app-authored WMP-neutral pair. **The sampling step is measured, not decorative: only 96 of the 180 archives declare any background colour and 95 any foreground**, so declarations alone leave nearly half the corpus with no palette. Verified live on `Creed` (declares a full list palette), `9SeriesDefault` and `corona` (black-and-green from their own `SUBVIEW`/`TEXT` declarations) with playlist, equaliser and library open together. 12 new tests in `WMPHostedSurfaceTests`; `swift test` 2,117 tests, 0 failures. |
| W92 | Text in the hosted windows is unreadable on some skins, and the titles are huge | every skin | **Closed 2026-09-09**, both halves reported live against the first build of W91. **(a) Legibility.** The declared colours were passed through ungated. `.wal` needs the guard only for a selected row; a `.wms` needs it everywhere, because it declares colour per *element* — the ground can come from a `VIEW` and the lettering from a `PLAYLIST` three levels down that was never drawn on it, and a sampled ground is one no author ever chose text against. Every foreground now goes through `SkinnedSurfaceStyle.legible` (WCAG 3.0:1) **against the ground it is actually drawn on**: the playing row's text on the window background, the selection's on the highlight. Guarding both against one background is what leaves an unreadable current track. The candidates are the skin's own colours in intent order, so a readable declaration is never overridden. **(b) Scale.** `playlistChromeScale` is `mainWindow.width / Skin.baseMainSize.width` — true of a *classic* player, whose 275px grid makes its width the zoom the user picked, and meaningless for a `.wmz`, whose window is the skin's own canvas: Corona's 596px read as 2.2x and drew the playlist title and every row at that size ("the windows and title fonts for corona are huge"). WMP now falls back to the app's own scale, and `PlaylistView.scaleFactor` and the playlist's snapped default width route through the same property so the three cannot drift. |
| W93 | A second, foreign-looking playlist opens over a skin that has one of its own | **171 of 180 archives declare a playlist, 164 an equaliser**, 164 both — measured 2026-09-09 | **Closed 2026-09-09.** Reported the moment W91 shipped: "when the skin provides windows … do not create redundant nullplayer windows and instead use the skin native. this is how it works in modern". Exactly right, and the corpus says it is the common case rather than an edge: for these two surfaces NullPlayer's window is the *fallback*. `WMPSkinSurfaces` reads what the skin declares and `WindowManager.routeWMPSkinSurface` takes the toggle first, the way `routeWinampModernSurface` does for `.wal`. Three shapes, and the corpus splits almost evenly between the first two (87 / 84): declared **in the view on screen** (Corona's drawer — nothing opens, the menu item is checked and inert), declared **in another view** (WoW's `plView` — the toggle opens that view, the way the skin's own button does through `theme.openView`), declared **nowhere** (9 skins for playlist, 16 for EQ — our window opens). **Match on the authored tag, not only on `WMPElementKind`**: `ITEMSPLAYLIST` is unmodelled, so a kind-only test calls Corona playlist-less and opens ours on top of it — what decides routing is what the skin declares, not how much of it this engine hosts. The restore path passes `switchingViews: false`, so a saved session never moves the user to another view at launch. Verified live on all three shapes: Corona (both items inert, no window), WoW (`wmpSkinViewID` `mainView` → `plView`, no window), `Classic.wmz` (items enabled, our playlist opens). |


## Phase 12 — the three defects behind "the WoW skin is empty"

Reported live on 2026-09-09 as three symptoms of what turned out to be three unrelated engine
defects, each of which the other two hid. None is visible to a headless sweep of the same tree: the
first is an app path, the second needs a host string longer than the box the skin drew for it, and
the third only shows once you ask what is *missing* from a scene.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W94 | A `<TEXT>` is drawn unclipped, and no skin in the corpus can turn its marquee on | **`scrolling` 358 uses across 114 of 180 archives**; `textWidth` 133 / 92 | **Closed 2026-09-09.** Reported as "why does the now playing look like this? it should fit and marquee I think" — `WoW`'s 77x30 `metadata` box painting "- AC/DC - Shoot to Thrill / Playing" straight across the shield's buttons. Three defects in a row, and fixing any one alone changes nothing. **(a)** `WMPRenderer.draw(_:in:context:)` set no clip at all. **(b)** `scrolling`/`scrollingDelay`/`scrollingAmount` were not in `WMPSceneText`, so even an authored marquee was a static string. **(c)** the skin decides for itself — `metadata.scrolling = (metadata.textWidth > metadata.width)` — and `textWidth` fell into the object model's open property surface and answered the unset-numeric **0**, so the comparison was false for every skin that has ever run here; `scrolling` then could not have committed anyway, being neither authored on that element nor a standard property. `WMPTextMetrics` is now the one place a `<TEXT>`'s face becomes a CoreText line, shared by the renderer and the object model so the skin's comparison is against what is drawn. A scrolling text contributes to `animationCadence` — endless, bounded to its own box — because it is the only animation a skin turns on from script rather than by naming a GIF. **The vertical half of the clip is deliberately absent, and that was measured**: clipping to the authored height shaved `v2_underworld`'s eight About links to a sliver and moved 11 other images, because the baseline here comes from `fontSize` rather than the face's real metrics. Cut the overflow that is measured; leave the one that is not. |
| W95 | An unanswerable `wmpprop:` resolves to false, and on `visible` that deletes the control | **1,459 unrecognised uses**, of which `visible=` is 150; `WoW`'s playlist, and 4 other archives' `plView`s | **Closed 2026-09-09.** Reported as "with WoW adding to the playlist does not work" — and the playlist control was not in the scene *at all*: no paint command, no hosted widget, no rows, whatever was queued. `WoW` authors `<PLAYLIST id="playlist1" visible="wmpprop:plMode.visible">`, `plMode` being a name WMP's own UI owns and this skin never declares; `WMPObservablePropertyRegistry` answered every unrecognised path with `.string("")`, and `WMPSceneBuilder` deletes a node whose `visible` override is falsy. **The rule now has three cases and each was arrived at by a sweep.** A **host root** this engine does not implement stays falsy — `xsn_sports` hangs its whole SRS WOW panel off `visible="wmpprop:eq.enhancedAudio"` (101 uses / 33 skins) and showing the "SRS ON" badge would claim a feature that does nothing; the first attempt lit that panel up and the sweep is what caught it. An **element the skin does declare** is mirrored by the builder, one hop, which is what keeps `WoW`'s CD-rip bar hidden behind `wmpprop:playlist2.visible` (8 skins share that line) and what restored `Disney_Mix_Central`'s entire player. An **element it does not declare** answers nothing, leaving the markup's value. Only `visible` declines to default: on every other property the empty string is the honest answer for content, and `wmpenabled:` still disables. `scripts/wmp_render_sweep.sh compare`: **521 of 545 identical**, and all 24 accounted for — 8 `visView`s whose rating bar now appears, 5 `plView`s that now have a playlist, 9 text boxes that now stop at their edge, `Scooby-Doo_2/infoView` (documented non-deterministic) and two 1-pixel antialias deltas. |
| W96 | A panel opened with `theme.openView` is persisted as the session's view | **57 of 180 archives ask for a panel by name**; every skin whose panels are `openView` | **Closed 2026-09-09.** Reported as "wow skin is empty and shows no player or skin windows", with a screenshot of `plView` alone. `apply` wrote `wmpSkinViewID` on **every** present, including a covering one, so quitting with the playlist open recorded `plView` — and the covered view is not persisted, so the initial candidate walk started at a panel, presented it, and stopped. There was no route back to the player at all: the skin's close button calls `theme.closeView`, and with an empty `openedViewStack` that orders the window out. The user's own defaults confirmed it (`wmpSkinName = WoW`, `wmpSkinViewID = plView`). Only a present with an empty `openedViewStack` writes the key now; `closeView` popping back to the base rewrites it. A value already written is not migrated — nothing can distinguish it from a legitimate one — so an affected profile is recovered by clearing the key once. |


## Phase 13 — the playlist a skin declares and the completion it chains from

Two rows, and neither alone fixes the case that named them. `corona`'s playlist drawer opens onto
nothing without both: W97 gives the control a widget to be, and W55 is what ever makes it visible.
Reported live and confirmed fixed by the reporter: "corona playlist works fine".

| ID | Item | Reach | Notes |
|---|---|---|---|
| W97 | `ITEMSPLAYLIST` is a playlist the object model does not model, so the skin's own drawer draws nothing | **13 of 179 archives**, and **not one declares a `PLAYLIST` beside it** — measured 2026-09-09 with a BOM-aware decode, and the engine's own tag census agrees exactly | **Closed 2026-09-09.** Opened by W93, which routed the playlist toggle to the skin whenever the skin declares one — correct, and it left `corona` users with an empty drawer, because `ITEMSPLAYLIST` fell to `.unknown`, never became a `WMPWidget`, and nothing hosted a `WMPPlaylistSurfaceView` over it. **It maps onto `.playlist` wholesale and the corpus is the evidence, not the name**: every one of the 13 authors list geometry (226x174, 187x139, 155x116 …) and `PLAYLIST`'s own attribute vocabulary — `backgroundColor`, `foregroundColor`, `itemPlayingColor`, `backgroundImage` — so a separate kind would have bought nothing, and `authoredTagName` retains the spelling for reporting. Since all 13 declare no `PLAYLIST`, this was the *only* playlist those skins had. `dropdownVisible` (12 of 13) is left unhonoured exactly as it is on `PLAYLIST`: it needs `player.mediaCollection`, which is W66's question and the thing W66 exists to refuse faking. **The first measurement of this row was wrong and the method is the lesson**: a scan that let Python's `utf-16` swallow BOM-less cp1252 files counted 8 archives and missed 5; the engine's own census said 13, and a BOM-aware decode reconciled them. Corpus sweep: **545 of 545 images identical** — a playlist is an AppKit overlay and never appears in a PNG — with the whole substantive diff being 13 `UNKNOWN tag itemsplaylist` lines going to zero. Verified live: `pharaoh/vRos` hosts `playlist id=pl frame=20,29 156x122`. |
| W55 | Animation and drag completion callbacks | `onEndMove` **247 uses / 113 skins**, `onEndAlphaBlend` **50 / 21**, `onDragEnd` **141 / 88**, measured 2026-09-09 over the 179 archives; **`onEndResize` is zero** | **Closed 2026-09-09.** The endpoints have landed since W38, so what was missing was the callback a skin chains its next step from. `WMPObjectModel` records `(stableID, event)` per `moveTo`/`alphaBlendTo` and `WMPScriptContext.raiseCompletionHandlers` raises the authored handler in the same transaction — before the geometry cascade, so a chained step's writes still propagate, and bounded once per `(element, event)` exactly as W87's cascade is. **`onEndResize` was deliberately not implemented**: no archive authors one, so it would be a dispatch site with nothing to prove it — the `INERT` trap in its other direction. **`onDragEnd` needed a second dispatch site and one semantic**: it is raised from `WMPMainView.mouseUp` for a captured slider, and 111 of its 141 sources are `player.controls.currentPosition = value` — a bare `value`, which WMP supplies by evaluating a handler against its element. Only that identifier is bound, for the duration of the event; a bare *assignment* (`toolTip='Seek'`, 6 uses) creates a global either way, so only reads were blocked and `with(element)` would have changed name resolution corpus-wide to buy six. **What it moved, and the measurement that matters is not the images**: 22 of 545 images changed, none lost — but **widgets went 1,863 → 1,711 across 57 views**, invisible to an image diff because widgets are AppKit overlays. Every changed skin authors a completion handler. Seven views *gained* (`Stars and Stripes`, `US Air Force/Army/Coast Guard/Marine Corps/Navy` each 0 → 4 widgets, drawing a whole player where a closed shell had been). Thirty-six *lost* them, all `mainView`/`videoView`/`videoBox`, and that is Microsoft's own drawer template working: `loadVidPrefs` sets `drawerStatus = true` so `toggleVidDrawer()` takes the close branch at load and `checkVidDrawer()` hides the frame. Verified rather than assumed — `Ginger Man`'s drawer button goes **0 widgets → 6 sliders** on a click, and its own `upToolTip="Show Video Settings"` says shut is the intended state. Those controls had been stranded outside a drawer that had already slid closed. |

**What closing W55 uncovered, and it is not W55.** Live QA on the same build reported three skins
misbehaving; all three were reproduced against a **baseline worktree at the parent commit and behave
identically there**. `xsn_sports`'s video drawer is "resistant to opening" because `vidDrawerButton`
drifts 20px up (`61,291` → `61,271`) once the view's 500 ms timer has run — clicking its settled
position opens the drawer and yields `4 widgets[slider×4]` — and the baseline drifts to the same
pixel and misses the same click. `BlueCrush`'s two top-right buttons call `view.returnToMediaCenter()`,
which exists nowhere in the engine. `Ginger Man` has no track display because its `mainView` is
starved: 10 nodes, 2 widgets, **6 unresolved**, squarely in `starved.tsv`'s class. What W55 changed
is that a drawer now correctly hides its contents when shut, so a drawer that fails to open is
visibly empty instead of showing usable controls in the wrong place. **Removing an accidental
compensation is not a regression, and it is not a reason to keep one** — the rows those three belong
to are open in `WMP_TASKS.md`.

### Phase 13 addendum — the Phase 3 `corona` live-QA pair

Both were found by the reporter driving the real app during Phase 3 live QA and both were left in
Tier 1c after the fact — W43 struck through and labelled FIXED, W44 never re-tested. A backlog row
that is closed but still listed reads as open work, so they move here. Audited 2026-09-09.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W43 | The player goes black while a track plays | corona, live | **Closed during Phase 3 live QA; moved out of the open backlog 2026-09-09, where it had been sitting struck-through and reading as open work.** Root cause was neither of the two suspects recorded here. `WMPEffectsSurfaceView.draw` and `WMPPlaylistSurfaceView.draw` filled `dirtyRect` rather than `bounds`; AppKit hands a view a dirty rect larger than itself (measured: `{{-269, -26}, {596, 468}}` against `bounds` `320x240`) and a layer-backed view does not clip it, so the overlay's translucent wash covered the whole window. Not playback-specific and not `WMPVideoPlaceholderView` — no video widget is ever built for corona. Found by comparing the renderer's own output against a screen capture of the same rect; see `live-ui-testing`. |
| W44 | Four different buttons in the top cluster all open the file dialog | corona, live | **Closed 2026-09-09 on the row's own nominated test.** `WMP_RENDER_CLICK="vPlayer@366,12;400,12;420,12;444,12"` resolves `bOpenFile`, `bPlaylist`, `bVis` and `bEq` distinctly and dispatches **`handlers=1` for each**, with only `bOpenFile` posting `openFileDialog` — so neither suspect survives. The second one, dispatch fanning a `nil` `targetID` across every `onClick` in the view, is answered by `handlers=1`: `WMPMainWindowController.handlers(in:event:targetStableID:)` matches the exact node ahead of any authored id, and both `WMPMainView.mouseUp` and the harness pass the stable id. Original note follows. `bOpenFile`, `bPlaylist`, `bVis` and `bEq` are `BUTTONELEMENT`s inside one `BUTTONGROUP`, separated only by their `mappingColor` in `player_top_controls_left_map.bmp`. A coordinate scan along `y=12` resolves them correctly and distinctly (`WMP_RENDER_CLICK="vPlayer@366,12;400,12;420,12;444,12"` gives `bOpenFile`, `bPlaylist`, `bVis`, `bEq`), so the mapping table is right at that row — check other rows before assuming the sampler is wrong. The other candidate is dispatch rather than hit testing: `dispatchScriptEvent(name:targetID:)` filters handlers by `xmlID`, and a `nil` `targetID` runs **every** `onClick` in the view, one of which is `OpenMedia()`. Confirm which by clicking each button once with `WMP_RENDER_CLICK` and reading the `handlers=` count. |


## Phase 14 — the visualization surface the corpus declares, and the four gaps behind one skin's

Closed 2026-09-09. One row, and four object-model gaps that only became visible once the surface
existed to be starved.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W101 | `<EFFECTS>` is not an element kind, so the visualization surface of 166 skins is hosted on nothing | **183 uses across 166 of 177 archives**, against `<WMPEFFECTS>`'s **5 / 5**, measured 2026-09-09 with `scripts/wmp_markup_census.sh <outdir> EFFECTS WMPEFFECTS` | **Closed 2026-09-09.** Two halves. The tag: `WMPElementKind(tagName:)` mapped `wmpeffects` and not `effects`, so the whole corpus's spelling fell to `.unknown` and `widgetKind` never made a widget; both spellings now map to `.effects`. What goes in the rect: `WMPEffectsSurfaceView` hosts a `VisualizationGLView` — the same ProjectM / Geiss / Tripex stack NullPlayer's own visualization window runs — with the WMP-style bars this engine drew by hand kept as the fourth entry and the fallback when no pixel format is available. `WMPEffectSelection` is the one place the choice lives, because **96 archives bind `currentEffectType="wmpprop:mediacenter.effectType"`**: `mediacenter.effectType`/`effectPreset` left the inert class and answer it, the element answers `currentEffectType`/`currentPreset`/`currentEffectTitle`/`currentPresetTitle`, and `next()`/`previous()`/`nextPreset()` (82 / 74 / 4 archives) cycle it. **Not W9's mistake**: nothing playing creates no engine and paints nothing, so the skin's own artwork stands; and the surface never takes a click, because 51 archives wire an `onClick` on the node and that handler is the scene's. Right-click gives the same `VisualizationContextMenu` the visualization window and the `.wal` AVS surface have (minus Fullscreen and Close), and the arrow keys step presets there too, offered only after the skin has refused the key. **Measured**: `WMP_RENDER_PROBE` over the 180 archives reports **91 hosted effects widgets across ~78 skins** where 5 archives could ever have had one, and the app's new `INPUT widgets hosted=` line is what proves it on screen. |

**The four gaps behind "I see no evidence of visualization on corona", and none of them is W101.**
Corona authors its `<WMPEFFECTS>` `visible="false"` and turns it on from `OnPlayStateChange`, so the
surface was correct and the script never reached it. In order:

* **The state-change event was dropped before it was dispatched.** `refreshHostState` wrote
  `lastScriptSnapshot` at comparison time and scheduled the dispatch 16 ms out; the next time tick —
  five a second during playback — then found nothing different and cancelled the pending task with
  `playstatechange` still inside it. Nothing raised it again. Events now accumulate in
  `pendingHostEvents` until a dispatch actually runs, in the contract's open/play/status/mode/
  buffering/reception order.
* **`NewState` and `status` were unbound**, so `playstatechange="OnPlayStateChangeTransport(NewState);
  OnPlayStateChange();"` died on statement one. `WMPJScriptEvent.Handler` carries the event's own
  arguments — per handler, because `NewState` is a different enumeration in the two events that
  raise it. See `reference/object-model.md` § *Event arguments*.
* **`osMediaWaiting` and the rest of `WMPOpenState`** (14–21) were missing from
  `WMPScriptConstants`, and a skin switches over the whole enumeration.
* **`player.dvd`, `player.network.sourceProtocol` and `player.currentPlaylist.getItemInfo`** were
  unrecognised. All three now answer the true thing — no DVD, no source protocol, no playlist
  attributes — and are counted inert.

**What that moved outside Corona, because a script that finally runs is a script that finally hides
panes.** Probe sweep over the 180 archives, before and after the object-model additions: script
diagnostics **95 → 89**, and `Plus!`'s `videoView` lost 9 widgets — its `onLoad` now runs past
`player.dvd` instead of dying at line 16, so it hides the video-settings controls it always meant to
hide. One new error surfaced behind the fixed ones (`checkForContent`). This is W37's cascade, and
the rule it wrote stands: re-measure the whole table in the same capture, never read one row falling
as progress.

**And one defect this row introduced and fixed inside the same day.** The surface's PCM observer
called `MainActor.assumeIsolated` on the notification thread; `.audioPCMDataUpdated` is posted from
inside `AudioEngine.processAudioBuffer`, so it is a `dispatch_assert_queue` failure and the process
traps the moment a hosted surface exists and a track plays. `VisualizationGLView` takes its own lock
and is written to directly from the posting thread. It reached live QA, where a crashed player reads
as "the playlist and the open folder are broken" — see `live-ui-testing`.

---

## Phase 14 (later the same day) — the three rules behind "most buttons don't work, there is no track display"

Closed 2026-09-09, from one report on `Cablemusic`. Four rows, all of them corpus-wide classes
`starved.tsv` had been ranking for two phases without naming: **83% of the corpus's 2,380 unresolved
nodes**. The instrument that named them, the sweep that bounded them, and the two rules that came
back narrower are in `skills/wmp-skin-guide/reference/harness.md` § *After the starvation classes*.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W107 | A `<TEXT>` has no intrinsic size, so a script-laid-out readout never draws | **1,441 nodes across 127 of 179 archives**, 1,058 missing width *and* height | **Closed 2026-09-09.** Every other node falls back to the natural size of its `backgroundImage`; a text has none, and WMP sizes it from the face and the string — so a skin never states it. `Cablemusic`'s `LayoutProgramInfoExpanded()` sets `txtShow.top/left/width/fontSize` and no `height`, because in WMP there is nothing to set, and the whole show/clip/author/copyright/bitrate block had no frame: "there is no track display". `WMPTextMetrics.lineHeight` is the height and the measured value the width, both through the caller's **override-aware** resolvers — the string being measured is what a script just wrote, and reading the markup answered nil for every one of them. An empty value is honestly zero-wide and starts drawing on the transaction that gives it one. |
| W108 | A `<BUTTONGROUP>` has no intrinsic size, so every control in it is dead | **31 groups across 16 of 179 archives** | **Closed 2026-09-09.** The group's normal state is usually the window's own background artwork, so the skin authors no `image` and no geometry at all. With no frame it registered no hit target while the artwork beneath still drew the buttons — `Cablemusic`'s presets, stop, close, minimize, next/previous effect, shrink, bandwidth and all three drawer tabs are one such group each. The mapping image is definitionally the group's own pixel grid, so it is the fallback, with the state images behind it. **It also fired a latent trap**: reaching that code for the first time on this skin hit `Dictionary(uniqueKeysWithValues:)` over the children's `mappingColor`s, and `Cablemusic` authors `bnpb6` and `bnpb7` both `#00C0FF` — a dead control became a crash on load. First in document order wins, as WMP does. |
| W109 | Half of WMP's transport vocabulary is not an element kind | `PAUSEELEMENT` **80 uses / 69 skins**, `PLAYBUTTON` 50 / 45, `PREVBUTTON` 50 / 45, `NEXTBUTTON` 49 / 44, `STOPBUTTON` 48 / 42, `MUTEBUTTON` 10 / 9, `REPEATBUTTON` 5 / 4, measured with `scripts/wmp_markup_census.sh` | **Closed 2026-09-09.** WMP spells every transport control twice — `<…ELEMENT>` a `BUTTONELEMENT` subtype, `<…BUTTON>` a `BUTTON` subtype — and the table had `playElement` but no `playButton`, `pauseButton` but no `pauseElement`, and so on for every pair. An unknown kind still paints its `image` and is not interactive, so the button **drew and did nothing** and the pointer fell through: `WMP_RENDER_CLICK` on `Cablemusic`'s play button answered `hit=ffw`. `MUTEELEMENT`, `REPEATELEMENT`, `SHUFFLEELEMENT` and `RETURNELEMENT` are zero in the corpus and stay absent. The `*ELEMENT` half is now `isNonLayout` — 494 nodes across ~90 skins that were never boxes — keyed on `mappingColor` **under a `BUTTONGROUP`**, because `polygon` puts a `mappingColor` on a `<SUBVIEW>` with real geometry as a self-mask and the attribute-only rule lost its panel. |
| W110 | An origin the markup never stated cannot be written by script | every skin that positions an element from a handler; `Cablemusic`'s two 17-row drawers are the worked case | **Closed 2026-09-09.** `left`/`top` default to 0 when unauthored, and the check was `attribute == nil ? 0 : resolve` — short-circuiting *before* the scene overrides were consulted. Size never had it, so a script-positioned element came out the right size in the wrong place: `InitPrograms()` writes `pr<N>.top`/`.left` for thirty-four station rows and all of them drew on top of one another in the corner of the drawer. Overrides first, then the markup, then the default. The sweep's one decrease is this fix working — `LostPlanet/infoView` goes 5 hits → 1 because its four gallery thumbnails are `moveTo`'d off-stage by `onLoadInfo()` and used to be pinned at the gallery's corner as invisible stacked hit targets. |

Two more things closed alongside them, neither a row of its own:

* **`justification`, `fontFace`, `fontStyle` and `fontSize` were not scriptable.** All four are read
  by the builder's text path, so a write has to commit as a mutation rather than be stored inert —
  and each was only reached when the markup happened to author the same attribute. `justification`
  alone is **788 authored uses across 150 of 172 archives**, and `Cablemusic` sets it on ten
  readouts that declare none, drawing a right-aligned label column flush left.
* **The compatibility tally was wrong in the direction that ranks finished work.** `effects` and
  `customslider` were absent from `WMPCorpusReport.supportedTags` — both hosted since Phase 6 and
  W101 — so a skin drawing both was reported as demanding two unimplemented tags.

---

## Phase 14 (third pass) — the four defects behind "still many problems"

Closed 2026-09-09, from the second report on `Cablemusic` after the starvation classes above landed:
"when you click the compact button there is a large overlay, the track information does not appear
and the track text is shifted up too high in the track window, the playlist is always showing."
Five unrelated engine defects in one skin again — the fifth found by a follow-up report on hover. The measurement, the two rules the sweep sent back,
and the two rows only `INPUT script-diag` could find are in
`skills/wmp-skin-guide/reference/harness.md` § *The second report on the same skin*.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W112 | A tween's endpoint is readable by the rest of the handler that started it | every skin that reads a position back after moving it; `moveTo` is 247 uses across 113 archives | **Closed 2026-09-09.** WMP animates over the duration argument, so `left` still answers where the element *is* for the remaining statements. `Cablemusic`'s playlist tab is `onClick="PlayListMove();HidePlist();"` and `HidePlist()` reads `subPlayList.left` to decide whether the drawer is open — applying the endpoint inside the call made it read the destination, so closing the drawer never hid the playlist and it stayed over the player forever. `WMPObjectModel.tween` queues the endpoint; `WMPScriptContext` flushes at each handler boundary, so W38 and W55 both still hold. A duration of zero is not a tween and applies immediately, which `movePlayButton()` depends on. |
| W113 | A script cannot resize its own window, so a `.wmz` compact mode draws inside the full-size one | `Cablemusic` confirmed live; `view.width`/`view.height` assignment is the compact-mode idiom, and 34 skins use the same write to collapse a `previewView` | **Closed 2026-09-09.** Three parts, each found by the one after it failing. The view root now reads its size overrides **before** its markup, like every other node. The size a script assigns is **not** the size alignment is measured from — `ownAuthoredSize` stays the markup's, because `LostPlanet`'s `onLoadInfo` writes `view.width = view.minWidth` and collapsing the delta to zero punched holes through its window frame (the sweep's 10 lost images). And it is committed in the **uncancellable** half of the transaction beside the host commands: with a track playing a `status_onchange` cancels the click's task after its render (W88), so the overrides landed and the present that carried the resize did not — a 475x373 player in a 593x600 window, which is the reported overlay. `WMPScriptOutput.viewSize` is keyed off the mutations so an expression-driven `<VIEW width="jscript:…">` is not mistaken for a resize request, and a non-positive result is the store-thumbnail collapse rather than a size. |
| W114 | A script's `fontSize` never reached the drawing, and a glyph-sized `<TEXT>` drew above its own box | `justification` **788 uses / 150 of 172 skins**; the baseline floor moved 142 of 545 corpus images | **Closed 2026-09-09.** Two halves of one readout. `WMPSceneBuilder.literal(_:_:)` reads the attribute and nothing else — geometry has `parseDimension`, a slider has `sliderMetrics`, the rest had nothing — so `txtShowLabel.fontSize = 7` over a `fontSize="10"` markup measured *and* drew every label three points too large and ran "Copyright:" off the left edge of the LCD. `literalNumber` is the override-aware resolver, and `justification`/`fontFace`/`fontStyle`/`fontSize` joined `standardElementProperties` so a write commits as a mutation. The second half: the baseline was `max(fontSize, (height + fontSize) / 2)` from the box's bottom, which sits four pixels *above* a box sized by its own glyphs (W107). `CTFontGetAscent` is the floor; it moves nothing that was already inside its box, and the sweep changed 142 images without changing a single node, command, hit or widget count. |
| W116 | A `BUTTONGROUP` with no normal `image` paints its whole hover/down sheet over the window | `Cablemusic`'s six groups confirmed live; every group that authors `mappingImage` + a state image and no `image` is in the class | **Closed 2026-09-09.** `hoverImage`/`downImage` are the entire player redrawn with one control lit, and the mapping mask is what cuts out the lit region. The normal `image` was *required* before any of that ran, so a group whose normal state is the window's own background artwork fell through to the generic single-image path and painted the whole sheet — 593x600 with a dark green surround on this skin, so hovering any button covered the player. Reported as "when you mouse over the compact button there is a huge overlay". The normal artwork is now optional and only the mask is required; a group with no artwork of its own and nothing lit draws nothing, which is its normal state. **Nothing reached this before W108 gave those groups a frame**, and no corpus sweep can see it: a default-state capture never enters a hover or a down state (W73), and the 535-image sweep across the fix is byte-identical. Measured with `WMP_RENDER_HOVER` and `WMP_RENDER_CLICK` instead. |
| W115 | `player.currentMedia.sourceURL` and `player.network.bitRate` abort the handler that fills every readout | `sourceURL` 3 uses / 1 skin and `bitRate` likewise in the corpus's *static* tally — but both sit before the payload in the same handler | **Closed 2026-09-09.** Neither was findable headlessly: the harness has no host snapshot, so no sweep can reach a `psPlaying` branch. `INPUT script-diag` named `player.network.bitrate` in one launch and, once that was closed, `player.currentmedia.sourceurl` behind it — § *After W37*'s rule arriving twice in one session. `Cablemusic`'s `handlePlayStateChange` reaches `UpdateBitrate()` and then `GenericProgramInfoBig()`, whose third statement is the `sourceURL` read, so one missing member cost the whole show/clip/author/copyright block on every track. `Track.bitrate` is kilobits and WMP's unit is bits per second. `Thomas/main` gained `0 kbps` and `0%` from the same fix. |

## Phase 14 (fourth pass) — the equaliser nobody switched on, and the slider nobody told anything

Closed 2026-09-09, from two live reports on the same session: "the EQ is not enabled in WMP for any
skin", then "balance/pan is fully to the left by default on all skins". Both are the same shape and
neither is a drawing defect: **a control the skin declared by *tag* rather than by *binding* was
reachable and unreadable.** `<EQUALIZERSETTINGS>` and `<BALANCESLIDER>` are both elements a skin
states once and never mentions again, and this engine read the attributes of neither.

Counts below are `scripts/wmp_markup_census.sh` over the 180 archives in `WMPSkins/`, cross-checked
against the loader itself (`WMPDeclaredHostState` over every archive: `true=148 false=0 silent=32
unloadable=0`) — the census reads 177 because it excludes `Darkling` and two repaired-header
archives `unzip` cannot open and the engine can.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W117 | The audio equaliser is never switched on, under any skin | **148 of 180 archives declare it on**; 155 bind band sliders; exactly **one** skin (`gnome`) ever writes `eq.enabled` from script | **Closed 2026-09-09.** Everything downstream already worked — a band bound to `wmpprop:eq.gainLevelN` dragged, wrote, and reached `AudioEngine.setEQBand` — into an equaliser node that was still bypassed, because `setEQEnabled(true)` was only reachable from a script write no corpus skin makes. What a skin does instead is state it in markup: `<equalizerSettings id="eq" enable="true"/>`, and since W65 made `EQUALIZERSETTINGS` a non-layout element nothing read its attributes at all. `WMPDeclaredHostState.equalizerEnabled` is the new reader; both spellings count (`enable` 88 skins, `enabled` 57) and only a **literal** decides — a `wmpprop:` binding asks the host what the host is about to be told. It is applied **once per skin load** in `reloadSelectedSkin`, deliberately not in `apply(skin:…)`, which re-runs on every `switchView` and would undo a user who had turned the equaliser off. The 19 skins with band sliders and no declaration are covered by `WMPAudioEngineHost.engageEqualizer`: a band, preamp or preset write engages the equaliser if it is off, which is what `EQView`, `ModernEQView` and `WinampModernComponentBridge` already do on a preset and the only way a `.wmz` with no toggle can ever get there. **No archive anywhere authors `enable="false"`**, so nothing in the corpus is overridden by that. Note that the enable state is global and persisted: a WMP skin turning it on carries into the other skin modes, exactly as toggling it in the equalizer window does. |
| W118 | A semantic slider tag binds itself to nothing, so balance draws hard left | `BALANCESLIDER` **16 uses / 16 skins**, one of which authors a `value`; `VOLUMESLIDER` **31 / 23** and `SEEKSLIDER` **18 / 15**, and none of those author one | **Closed 2026-09-09.** `<SLIDER value="wmpprop:player.settings.balance">` states where a control reads; `<BALANCESLIDER>` states the same thing by *being* one, which is why a skin that uses the tag authors no `value` and usually no `min`. Two defaults then collided: `WMPSceneBuilder.sliderMetrics` falls back to *the value of a slider nobody has told anything is its own minimum*, and the range defaulted to 0-100 — so 15 of the 16 balance sliders in the corpus drew their thumb at the bottom of the track, which on balance means hard left. Volume drew empty and seek stuck at the track start for the same reason; balance is the one where the wrong end of the track *means* something, which is why it is what got reported. `WMPObservablePropertyRegistry.implicit` synthesizes the binding the tag stands for, so the value arrives through the same coalesced, echo-guarded path an authored `wmpprop:` does and follows the host live. **The seek slider needs both halves**: WMP puts the position on it in *seconds*, so `max` is synthesized onto `player.currentMedia.duration` and `value` onto `player.controls.currentPosition` — two paths the registry already answers, rather than a new percent path it does not. Ranges are the other half of the same statement and stay in `sliderMetrics`: `defaultRange(for:)` is `-100…100` for `.balanceSlider` and 0-100 for every other kind, byte-identical to before. An authored attribute always wins, which is what the one balance slider that states its own `value` relies on. **The audio was never wrong** — `AudioEngine.balance` defaults to centre and `WMPMainView.performSlider` already converted `fraction × 2 − 1` — so this was a drawn thumb lying about a centred pan. Verified with `WMP_RENDER_PROBE` on `corona`, whose `<BALANCESLIDER>` authors nothing but artwork: thumb travel is `493 + f × 34` and the thumb now draws at 510 (`f = 0.5`) where it drew at 493 (`f = 0`). |

## Phase 14 (fifth pass) — the event a clock tick is not, and the timers it cancelled

Closed 2026-09-09, from "the timer display and seek/progress are broken in wmp for all skins" and,
in the same session, "should there be track information in 9SeriesDefault?". **Nothing here is
visible to any capture the harness could take**, because the harness had no way to render a playing
player at all: every probe ran against `WMPHostSnapshot()` — stopped, empty playlist, zero-length
track — so the whole class lived in the gap W73 names. `WMP_RENDER_HOST` and `NULLPLAYER_PLAY` close
the playback half of that gap and are documented in `reference/harness.md`; with the first of them
seeded, **88 of the 89 measurable archives that author the elapsed binding draw the right string**,
which is what moved the search out of the scene and into the app's event dispatch.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W119 | A clock tick is dispatched as `status_onchange`, so 10 Hz of playback re-runs every skin's metadata handler and cancels every script timer it has | `status_onchange` is authored by **70 of the 177 measurable archives**, and **all 75 of its sources are metadata updaters** — `updateMetadata()` ×35, `updateMetadata('status')` ×33, `OnStatusChangeTransport(status)` ×5, `updateMetadata2('status')` ×2. The timer half is every skin with a script timer (`setTimeout`, 2 skins / 9 uses) and every chained one | **Closed 2026-09-09.** Three defects on one path, none of which can be seen without a track playing. **(a)** `WMPMainWindowController.refreshHostState` raised `status_onchange` whenever `currentTime` changed, which with `AudioEngine`'s 100 ms time updates is ten times a second. WMP's event means *the status string changed*; `player.status` is inert and empty here, so raising it made 35 skins run `metadata.value = player.status` at 10 Hz and blank their own track readout — `9SeriesDefault` runs `ShowStatus(player.status)` and drew an empty metadata line beside a correct clock, which is exactly what got reported. The bindings still have to settle at that rate (the elapsed readout of 108 archives and the seek slider of 89 are `wmpprop:` reads), so a tick now raises `positionchange`, **a name no corpus archive authors** — measured 0 uses — and therefore resolves to no handler and runs as the binding-only transaction `dispatchScriptTransaction` already documents. A `duration` change is a media that opened rather than a clock that ticked, so that keeps the status raise. **(b)** `scheduleTimers` replaced the whole script-timer set on every transaction, and a transaction's `timerRequests` are only what *that* transaction registered — so any transaction that registered none cancelled every running timer, and 10 Hz of position ticks killed every script timer in the skin within 100 ms of the user pressing play. `applyTimerDelta` applies a delta instead: registering is additive, `clearTimeout` is what removes one (the context now reports cleared tokens as well as new ones, since a cleared token may belong to a transaction long past), a token already running is left alone rather than restarted, a one-shot retires itself when it fires, and the Phase 0 active-timer limit is enforced on the resulting set rather than per transaction. **(c)** `dispatchTimer` dropped what a timer handler registered, so the WMP chain idiom — a callback that ends by calling `setTimeout` for the next step — fired exactly once. It applies the delta too. Verified live with `WMP_TRACE_INPUT=1 NULLPLAYER_PLAY=…`: 1,352 `status_onchange` transactions in two minutes became 0, position transactions present at 10 Hz, and the corpus invariants are unchanged across the fix (163 skins, one line differing and it is `LostPlanet/infoView`'s clock-driven gallery frame). |
| W120 | A slider whose maximum is the media duration has no value, so every seek bar in a third of the corpus sits at frame 0 | **73 sliders across 61 of the 177 measurable archives** author `max="wmpprop:player.currentMedia.duration"` and no `value`: 58 `<CUSTOMSLIDER>`, 15 `<SLIDER>`. Reproduce with `scripts/wmp_markup_census.sh` plus the range scan recorded in `reference/harness.md` | **Closed 2026-09-09**, from "catwoman skin is not fixed, the clock does not work and seek does not work". W118 synthesized the seek binding for the `<SEEKSLIDER>` *tag*; this is the same statement made by the declared **range**, which is how the Plus!, Xbox, Alienware, BlueCrush, Halo and Catwoman families all write it — `<customSlider id="seek" min="0" max="wmpprop:player.currentMedia.duration" image="seek.png" positionImage="seek_map.png">`, a filmstrip and a position map and nothing to say where the value comes from, because in WMP a control whose far end is the end of the track is a position control. Nothing in those skins' scripts writes the value either, so the strip stayed on frame 0 for the whole track: `Catwoman/mainView` drew `seek.png crop=0,0` at 42 seconds into 137. `WMPObservablePropertyRegistry.positionSliderPaths` reads the range rather than the tag, so it applies to any slider kind, and an authored `value` still wins (112 corpus sliders state their own). Measured with `WMP_RENDER_HOST="t=42,dur=137"` over 163 archives: **68 rows changed across 52 skins, 0 lost, 0 new**, and every one of them a seek filmstrip stepping off frame 0 — Catwoman's own goes `crop=0` → `crop=225` → `crop=750` at 0, 42 and 137 seconds of an 11-frame strip. 2,154 tests green. **Half of that report is still open and is W51**: `value_onchange` is not raised when a bound host property moves a control, and Catwoman draws its clock with `value_onchange="drawSeekDigits(value)"` — four digit strips positioned from the slider's value — so the seek bar now follows the track and the digits still do not. |
| W51 | Nothing raises `value_onchange` when the **host** moves a control, so a readout driven off a slider never moves | the host-driven remainder of **2,170 uses across 175 of 179 archives**; **19 handlers on a position-bound slider** are the clock half. The user-driven half closed 2026-09-08 with W52 | **Closed 2026-09-09**, as the second half of the Catwoman report. A `<SLIDER value="wmpprop:…" value_onchange="…">` is bound both ways in WMP: the handler runs when the *user* moves the control **and** when the host does, which is how a seek bar's readout follows playback and how a preset moving ten gains re-runs each band's handler. `WMPScriptViewPlan.valueChangeHandlers` collects the attribute (both spellings, the same two the app's matcher accepts) and `WMPScriptContext.raiseValueChangeHandlers` raises it, with the bare `value` bound and cleared exactly as the event path does it. **Two things had to change besides**: the registry's binding changes are now resolved **before** the handler pass rather than folded into the overrides after it — a control the host moved used to read as unmoved for the whole transaction — and the element model is synced with those values, so `seek.value` answers the host's number instead of the markup's (which, for the corpus's seek bars, is nothing at all). Committing them into the scene is unchanged. **Measured before it was written, because the blast radius is the whole corpus**: 2,488 host-bound sliders carry 2,141 of these handlers and most are write-backs (`eq.gainLevel1=value`, `player.settings.volume = value`), which settle because the registry only reports values that *moved* — a handler handing the host the number it was just given produces an identical snapshot and no further change. And **every one of the 19 handlers on a position-bound slider is a readout painter** (`drawSeekDigits(value)` ×17, `DrawTimeNormalView(value)`, `seek2.value=seek.value`), so this direction cannot re-seek. Bounded like the cascades beside it and raised before them, so a repaint that writes geometry still propagates through W87 in the same frame. **Result, seeded sweep over 163 archives: 44 rows changed across 17 skins, 0 lost, 0 new**, all of them clocks — `Catwoman`'s digit strips read `02:17`, `01:35`, `00:00` at 0, 42 and 137 seconds of a 137-second track (it counts down by default; `SetTimeShowState` swaps to elapsed). 2,156 tests green. **New measured demand, not a regression**: 42 handlers that had never run now run, and 30 of those abort on `event.shiftKey` — an **`event` object in a handler**, which nothing binds on either direction of `change`, and which is what the Skins Factory equaliser uses to link its bands. That is a new row's worth of demand rather than something this change broke: before it, those handlers were never reached at all. |

## Phase 14 (sixth pass) — the digit a skin swaps in, drawn ten times its own size

Closed 2026-09-09, from "in all the alien type skins the numeric display is illegible", with a
screenshot of `ALXVortex` showing two blue smears where a clock belongs.

**A default-state corpus capture cannot see this and can see all of its collateral**, which is the
only reason to run one here. The defect needs a *playing* host: the ten-digit strip **is** the
authored frame until a script swaps it, and `drawSeekDigits()` returns early on an empty playlist.

Counts are reproducible over the 180 archives in `WMPSkins/` by scanning every `.js`/`.wms`
(decoded utf-16/utf-8/cp1252) for `\w+\s*\.\s*image\s*=`, for `drawSeekDigits|DrawTimeNormalView`,
and by comparing each `time<N>` button's authored `width` against the natural width of the
`time<N>_*` artwork it swaps in.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W122 | An element's artwork is scaled to its authored frame, so a script-swapped bitmap is drawn at the wrong size | **563 script `.image` assignments across 51 of 180 archives**; **23** paint a clock out of digit strips; **6** give the digit a frame wider than the digit — `ALXVortex`, `ALXMorph`, `AlienMorph`, `AlienwareTeleport`, `Alienware Invader`, `Crimson_Skies` | **Closed 2026-09-09.** The readout is not text: it is four `<BUTTON>`s authored the width of a ten-digit strip (`<button id="time1" width="250" height="23" image="time1.png">`, and `time1.png` is 250x23), each inside a 25 px `<SUBVIEW>` that clips it to the first cell, with `drawSeekDigits()` assigning a single 25x23 `time1_<n>.gif` per tick. `WMPRenderer` drew every image scaled to the node's frame, so the 25 px digit was blown up 10x into the 250 px frame and then clipped back to 25 px — one tenth of one digit, magnified. `WMPSceneBuilder` now clamps the **foreground** image command to the artwork's own size, anchored at the frame's top-left, so the smaller bitmap lands exactly where the strip's first cell did; the parent's clip is untouched. `PROBE mainView/46 button id=time1 frame=114,131 250x23` becomes `25x23`, and under `WMP_RENDER_HOST=playing` the four digits resolve to `0 1 : 0 3`. **`backgroundImage` is deliberately exempt** — a `stretch`-aligned subview grows with a resizable window and its background covers the delta (`LostPlanet`) — as are position-map slider strips, which already crop rather than scale. **Corpus sweep, 179 archives / 545 images: invariants byte-identical (no `RENDER-DUMP`, `COMPAT`, `FINDING`, `BITMAPS` or `PNG` line moved), 529 images identical, 16 differing, and none of the 16 is a clock.** All sixteen were opened: `portals/mode2` loses a black smear scaled over its top-left and stops drawing its artwork zoomed; the five `US …` `videoUSM` logos, `tubeframe`'s button bank (whose status line was also clipped), `Ice/mainView`, `Charlies_Angels/viewEQ` and both `QuickSilver` `plView`s go from upscaled and blurry to crisp; `9SeriesDefault/viewTiny`, `Nautical/view-2` and `portals/mode1` are neutral; `Scooby-Doo_2/infoView` is the known `Math.random()` case in the counter-evidence table. **One is half-right and is W123**: `Ice/videoView`'s `Pl-xp.bmp` button is authored `height="144"` over a 196x44 bitmap and is now correct, but its parent subview still stretches the same bitmap to 313x144, so a seam appears where the two used to agree by both being wrong. 2,157 tests green. |

## Phase 14 (seventh pass) — the video the corpus declares, drawn at the size the skin asked for

**W102 and W105's `.video` case, closed 2026-09-10.** `<VIDEO>` is the largest surface the corpus
declares and this engine hosted nothing in it. It is hosted now: the existing `VideoPlayerWindowController`
lends its output window to the skin as a **child window** parked over the authored rect — not a
reparent of the video view, which is the shape that does not survive contact with VLCKit — and gives
it back when the film ends.

**The defect that made the row worth reopening after the first implementation was a default.**
`WMPVideoPresentation.shrinkToFit` shipped `false`, so `imageRect` clamped every scale below 1 back
to 1 and drew the stream at its native pixel size, centre-cropped inside the box. The corpus settles
the direction and it is not close: of the **97 sized `<VIDEO>` elements across the 180 archives, 77
author no `shrinkToFit` at all and 73 of those are boxes under 640x480** — `Heart_Butterfly` is
89x130, `Creed` 131x88, `Cablemusic` 341x215 — and **not one archive anywhere authors
`shrinkToFit="false"`**, while 19 author `stretchToFit="true"` and one `"false"`. A flag no skin
ever turns off, in front of boxes no 2000s stream was ever smaller than, is a flag that defaults on.
`shrinkToFit` now defaults true, `stretchToFit` false, `maintainAspectRatio` true, in all three
places that state it (the struct, `WMPSceneBuilder`'s parse, and `WMPObjectModel`'s read-back, so a
skin reading a flag it never authored is told what is actually drawn).

**Verified live, not only headlessly** — this is a screen-only class and a corpus sweep cannot see it,
because the render dump does not draw the picture at all. Against `Cablemusic` playing a 1920x1080
film: `INPUT video hosted id=VidScreen frame=(18.0, 105.0, 341.0, 215.0) source=1920.0x1080.0`, the
output window reports 341x215 — exactly `<VIDEO id="VidScreen" width="341" height="215">` — and the
picture is letterboxed inside it instead of showing the centre sliver of a 1080p frame. Dragging the
skin moved it by (-192, -95) and moved the picture by (-192, -95), landing at offset (18, 105).

**Three defects found by driving it that were not in the original row**, all closed here:

- **The parked window stops being a child.** `isVideoOutputHosted` is our flag; being a child window
  is AppKit's fact, and they drift. Reported as three separate symptoms that are one cause: the
  picture went black while audio played and seeking still worked (it had fallen *behind* the skin,
  which a real child window cannot do); it lagged out of the window frame on a drag (what was left
  was the 10 Hz reposition trailing a tick behind); and switching apps put it right (activation makes
  AppKit re-collect child windows). `hostOutputWindow` re-parents only when `!isVideoOutputHosted`,
  so once the link went nothing restored it. `WMPVideoSurface.update` now re-asserts the
  *relationship* every tick, not just the ordering, and traces which case it hit.
- **A paused film stops reporting time, and that was the only thing refreshing the host.**
  `VideoPlayerWindowController.updatePlayingState` set `isPlaying` and told nobody; in `.wmz` mode
  the host tick came from `videoDidUpdateTime`, driven by VLC's time-changed callback. Pausing
  silenced it, so the skin went on drawing *and hit-testing* a pause button. The next click then died
  in `WMPMainView.mouseUp`: its `mousedown` triggered the rebuild that finally saw `paused` and
  swapped the button, leaving `mouseup` over a different element than the one captured, and the
  `result.activated == capturedTarget.stableID` guard dropped it. **The click was destroyed by the
  state change it triggered.** Reported as "play then pause then play just breaks it". Verified by
  six consecutive toggles, all honoured, where the second press had previously been dead. The new
  `videoDidChangePlaybackState` hook is **gated to the WMP family** — the other three drive their
  transports from their own sources and none was measured against it.
- **`<VIDEO>`'s fit flags were unreadable and `fullScreen` unwritable.** `shrinkToFit`,
  `stretchToFit`, `maintainAspectRatio` and `fullScreen` now read and write through the object model,
  `player.currentMedia.imageSourceWidth`/`Height` answer the decoder instead of a hard zero, and
  `setVideoFullScreen` is a host command.

**Subtitles and audio-track selection reach the parked picture** through
`WMPMainView.menu(for:)`, which already served the `<EFFECTS>` rect and now answers for the
`<VIDEO>` rect too: the picture itself stays click-through, so the skin's own `<VIDEO>` `onClick`
(21 uses) keeps working, and the right-click that lands on the skin returns the video view's menu.
Confirmed working by the reporter on 2026-09-10.

**A caution recorded because it briefly became a filed defect:** a *synthetic* `CGEvent` right-click
does not open this menu and leaves no `INPUT menu` line, while a real one does. That was written up
as "no right-click on a `.wmz` reaches `menu(for:)`" — an engine defect that does not exist — and
withdrawn the same day when the reporter used the feature successfully. See
`skills/live-ui-testing/SKILL.md`; **never conclude a menu is missing from a synthetic right-click.**

**What it left open is W124** in `WMP_TASKS.md`: a `videoend` with no matching `videostart` leaves
the skin in its ended state. It is not claimed as fixed.

**And one defect that is not a skin defect at all: V1** in
[`docs/video-playback/backlog.md`](../video-playback/backlog.md), which this work surfaced and which
had nowhere to be filed. A playing film is silently re-opened from the start and the reload hangs;
because the picture just stops, it presents as a skin or decoder fault. It was misread here first as
VLC buffering, and the reporter's own account — *no visible reload, the video is just hung* — is what
corrected it. **Suspect it before suspecting the skin when a picture stops.**

2,165 tests green.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W102 | `<VIDEO>` is hosted on nothing, and this player has a video window | **268 views across 170 of 179 archives**, 165 of them in a view of their own; `<WMPVIDEO>` a further 16 / 16 | W9 removed the opaque `WMPVideoPlaceholderView` for the right reason — it filled its frame with black over the artwork of 166 skins and an audio player had nothing to put there — and the note it left (`WMPMainView.swift:431`) says "an audio player has no video to put there instead", which **is no longer true**: `Windows/VideoPlayer/VideoPlayerView.swift` exists and plays. The row is therefore conditional hosting, not a placeholder: host the video layer in the authored frame **only while the current track actually has a video track**, and keep standing aside otherwise. Two things fall out of it rather than being separate work — W56's `onVideoStart`/`onVideoEnd` (114 and 105 skins) become raisable off a real surface, and `fullscreen` (80 skins), `shrinkToFit` (87) and `stretchToFit` (83) become answerable. Settle what a `.wmz` may see of the video path before writing any of it, the way W66 is held on the media-collection question. |

## Phase 14 (eighth pass) — video events through an output rebuild

| ID | Item | Reach | Notes |
|---|---|---|---|
| W124 | A skin is told the video ended and never told it came back, so it stays in its `onVideoEnd` state | `onVideoStart` **105 uses / 91 skins**, `onVideoEnd` **77 / 70**, measured 2026-09-10 over the 180 archives | **Closed 2026-09-10.** VLC can briefly report no `hasVideoOut` and no usable `videoSize` while rebuilding the output for the same open media. `WMPAudioEngineHost` now latches a separate `videoEvent` snapshot by media identity and clears it on a media change or `didReachEndOfMedia`; `video` remains live. That distinction is required because `WMPVideoSurface` must detach during the gap, otherwise its child window can remain over the skin and intercept buttons. The pure latch test covers teardown, a genuine `videoend`, and replayed `videostart`; the accepted fix compiles and preserves the real end event. |

2,167 tests green.

## Phase 15 — WMP preference defaults

| ID | Item | Reach | Notes |
|---|---|---|---|
| W76 | `theme.loadPreference` returns `""`, so a `"--"` default sentinel never fires | Plus! Professional, the Plus! family, `digitaldj`, and the ALX/Alienware family; exact corpus reach remains unmeasured | **Closed 2026-09-11.** An unset skin-scoped preference now answers WMP's `"--"` sentinel, while a saved value (including an explicitly saved empty string) still round-trips unchanged. The previous empty answer inverted `Plus! Professional`'s `loadVidPrefs()` branch and hid its right video-drawer tab on a fresh profile; it also made ALXMorph's coolant-animation preference start in the wrong branch. `testThemeLoadPreferenceUsesWMPAbsentSentinelAndPreservesSavedValues` pins both the missing-key and saved-value cases. A post-fix corpus capture completed for all 179 in-scope archives with no loader or render failures. A pixel before/after comparison could not run because a freshly created baseline worktree lacked the locally bootstrapped VLCKit framework; that limitation is recorded rather than replaced with an unmeasured claim. |

## Phase 16 — Plus! Professional’s transparent controls and marquee timing

| ID | Item | Reach | Notes |
|---|---|---|---|
| W125 | JPEG `transparencyColor` leaves a magenta slab | Confirmed on Plus! Professional; applies to every declared JPEG color key | **Closed 2026-09-11.** The skin declares `#FF00FF` on its `s_main_no.jpg` button sheets, but JPEG decoding makes its matte a blue-channel ramp from `#FF00FE`; an exact comparison rendered the filler as two bright magenta rectangles beside the transport. JPEG color keys now tolerate the bounded 64-value compression fringe; PNG, GIF and BMP remain exact, and non-keyed JPEG artwork remains opaque. `testJPEGColorKeyAllowsTheOneValueRoundingIntroducedByLossyDecoding` pins both sides. |
| W126 | Invalid marquee delay runs at the invalid speed | Every skin that authors `scrollingDelay` below 30 ms; Plus! Professional is the screen repro | **Closed 2026-09-11.** WMP specifies a 30 ms minimum and an 85 ms default; its `scrollingDelay="10" scrollingAmount="2"` must therefore move at the default cadence, not 200 px/s. The renderer and animation scheduler now share that normalization. `testTooFastScrollingDelayUsesWMPs85MillisecondDefault` pins the 85 ms cadence. |
| W127 | The macOS window close control strands a player covered by `theme.openView` | Every skin that opens an auxiliary view; Plus! Professional is the screen repro | **Closed 2026-09-11.** WMP opens `plView` beside its player, while this app presents it in the one WMP window. Its in-skin close already popped `openedViewStack`, but the macOS window X bypassed that command and minimized/ordered out the only window. `windowShouldClose` now cancels the close and restores the covered view whenever the stack is non-empty; closing the actual player is unchanged. `testWindowCloseRestoresAPlayerCoveredByAnOpenedView` pins the route. |

## Phase 17 — the SDK conformance audit's first row

| ID | Item | Reach | Notes |
|---|---|---|---|
| W128 | The element method vocabulary is narrower than the SDK, so an SDK method this engine does not implement fails **untallied** | `plListBox1/2.deleteAll()` 10 skins, `playlist2.copy()` 8, `playlist2.abortCopy()` 8, `view.returnToMediaCenter()` 7, `playlist1.deleteSelected()` 5, `fileList.insertItem()` 3 — corpus scan of the `.wms`/`.js` in the 177 measured archives | **Closed 2026-09-11.** First row of the SDK conformance audit, taken first because it changes what every later measurement can see. `WMPObjectModel.elementMethodVocabulary` held 25 hand-accumulated names; it is now the SDK's element-method list (64 names) transcribed from `ambient-attributes`, `view-element`, `playlist-element`, `listbox-element`, `popup-element`, `editbox-element`, `effects-element` and `buttongroup-element`, commented by source element, plus the eight non-SDK names that were already there and already tallied. **Vocabulary only — no new implementations**: `elementMethod(_:_:)` and `implementedElementMethods` are untouched, so `WMPJScriptCompatibility.members["element"]` is unchanged and `setFocus` stays in the vocabulary and out of the compatibility table. Evidence below. |

### What the census delta actually showed, and the one correction it forced

Baseline `scripts/wmp_skin_census.sh /tmp/wmp/census-base` from a `git worktree add ../nullplayer-base HEAD`, then `/tmp/wmp/census-w128` on the change; both 179 archives, 535 views, `render.txt` 56,188 lines in each.

`UNRECOGNISED` element-method rows, tallied by name and by containing `SKIN` block:

| member | base | after |
|---|---|---|
| `deleteall` | **absent** | **7 uses / 7 skins** (`Alienware Invader`, `Batman Begins`, `Constantine`, `Disney_Mix_Central`, `LostPlanet`, `STALKER`, `WoW`) |
| `speakersize`, `closeview`, `setcolumnresizemode`, `enablesplinetension`, `enhancedaudio`, `setiteminfo`, `bypass` | 30 total | unchanged |

`inert_calls` 2,214 → 2,200 (−14: the 7 `CALL` lines and their 7 `CALLS` aggregates), `ok` 26,553 unchanged, `handler-error` **119 in both**.

**The audit's claim that such a call "never appears in the demand tally" is half right, and the census corrected it.** The call was not invisible — it reached the open property surface, answered `""`, and was counted **`INERT`**: `CALL plView pllistbox1.deleteall read value= INERT` in the baseline against `… value=null UNRECOGNISED` after. So an unimplemented SDK method was ranking in Tier 2b, "recognised, answered, and nothing behind it", when it belongs in Tier 2a. The defect is a **misclassification**, not an absence, which is worse for ranking than it looks: Tier 2b is explicitly the tier you do *not* take runtime work from.

**Only `deleteAll` moves, and that is expected rather than short.** The other five names in the reach list sit in click handlers; the headless census drives each view's `onLoad`, so it cannot see them. They become visible to the live loop or to a click-driving sweep, and are ranked in `WMP_TASKS.md` § 2a accordingly.

**Why no screen can change, measured rather than argued.** In all seven skins the call is inside the skin's *own* `try`/`catch` — `fillListBox()` in `warcraft.js:1584` is the shape — so the throw is caught by the skin, not by the handler boundary, and `handler-error` is identical at 119 in both captures. A `TypeError` on `""()` and an unrecognised-member throw abort at the same statement.

### Render sweep: 535 images, zero changed

0 lost, 0 new, **1 changed** — `Scooby-Doo_2/infoView`, which is the counter-evidence table's own entry and not a regression. Its `randomPic()` (`scooby.js:799`, `parseInt(Math.random() * 10)`) picks one of ten character images per capture. Proven rather than asserted: base vs change is 5,522 differing pixels, and **two captures on the *same* tree differ by 9,031** — more than the cross-tree delta. `reference/skins/README.md` now records the mechanism and the numbers.

### The regression check the vocabulary needs, and its result

The vocabulary gates *reads* as well as calls, so a newly added name could newly abort a handler that reads it as an unauthored bare property. All 39 new names were grepped as `\.<name>\s*[^(]` across the `.wms` and `.js` of every archive Python's `zipfile` can open (392 files, 177 archives). **One read class, and it is safe**: `mediacenter.effectType`, **376 uses across 192 files / 130 archives**, every single one on the `mediacenter` host receiver — answered by `readMediaCenter` before the element path is reached. Zero reads on an element receiver. `x.size`, `x.show`, `x.click`, `x.copy` and `x.next` as property reads: zero hits corpus-wide.

**That scan had to be run twice, and the first run was wrong in the way `harness.md` § *Counting a tag across the corpus* predicts.** It decoded every file as UTF-8 with `errors="replace"`, so the **153 of 392 files that are UTF-16** became null-interleaved mojibake and `\.deleteAll` could not match in any of them — 39% of the corpus silently skipped, reported as 141 uses. Re-run with `WMPTextDecoder`'s order (BOM, then a positional BOM-less UTF-16 sniff, then cp1252) the same scan finds 376. **The conclusion did not change and got stronger** — still zero element-receiver reads — but the number in it was wrong by 2.7x, and nothing about the first run looked wrong. The corpus file-encoding mix, measured here: 153 UTF-16-with-BOM, 143 cp1252, 87 UTF-8, 9 UTF-8-with-BOM.

`testSDKElementMethodsAreCountedWhenUnimplemented` and `testUnimplementedSDKMethodsAreTalliedRatherThanSilent` pin both halves: the SDK names resolve unrecognised and stay out of the compatibility table, a name the SDK does not define stays out of the vocabulary, and `deleteAll`/`copy`/`returnToMediaCenter` each abort their own handler and only their own.

W129–W135, the rest of the audit, are open and ranked in `WMP_TASKS.md`.

## Phase 17 (second pass) — the ambient event mechanism, and what its reach did not say

| W129 | `<attribute>_onchange` is a five-property whitelist against a general SDK mechanism | **387 authored handlers across 104 of the 177 measured archives**, 20 distinct properties: `currentPosition_onchange` 77 skins, `currentEffectType_onchange` 57, `currentPlaylist_onchange` 48, `currentPreset_onchange` 30, `textWidth_onchange` 17, `selectedItem_onchange` 12, `playlist_onchange` 9, `currentMedia_onchange` 9 | **Closed 2026-09-11.** Largest row of the SDK conformance audit. Three pieces, each a separate place a name could go missing: **classification** — `WMPAttributeParser.parse` now makes any `*_onchange` attribute a `.handler`, where the closed list left 387 handlers across 104 archives sitting in the graph as literals; **collection** — `WMPScriptViewPlan.attributeChangeHandlers`, keyed by folded attribute and carrying the **authored** spelling, with `value` deliberately excluded so W51/W52's own path cannot fire twice; **dispatch** — `WMPScriptContext.raiseAttributeChangeHandlers` for element writes (W87's bound, now over every attribute instead of the four geometry ones) and `WMPMainWindowController.refreshHostState` for the player attributes off the snapshot diff. **The bare-name binding is what decides whether any of it runs**: 68 of the 77 `currentEffectType_onchange` uses are `mediacenter.effectType=currentEffectType`, a `ReferenceError` on the first statement without it, so the attribute is bound under its authored spelling for the duration of its own handler and cleared after — the same shape `value` and `NewState` use. `currentMedia`/`currentPlaylist` are **not** bound: WMP's are objects, and all 77 of their sources call a skin function rather than reading the name. Evidence below. |

Census pair, `git worktree add ../nullplayer-base HEAD` vs the change, 179 archives / 535 views:

| | base | after |
|---|---|---|
| `UNKNOWN event` lines / uses | 1,179 / 2,763 | **1,002 / 2,536** |
| `currentposition_onchange` / `currenteffecttype_onchange` / `currentplaylist_onchange` / `currentmedia_onchange` | 80 / 66 / 49 / 5 skins | **0 / 0 / 0 / 0** |
| `selecteditem_onchange`, `currentpreset_onchange`, `textwidth_onchange` | 12, 38, 21 | **unchanged** |
| `handler-error` | 119 | **119** |
| commands / hits / widgets / unresolved | 10,879 / 4,603 / 2,450 / 1,141 | **all four unchanged** |
| `traced_calls` | 34,568 | 34,571 |

**The three names leaving the tally is the whole structural delta, and nothing entered it.**
`WMPCompatibilityReport` already counted any `_onchange` suffix as an event regardless of how the
attribute was classified, so widening classification adds no name — it only lets the four that now
have a dispatch site drop out. A name still without one stays put, which is why
`currentpreset_onchange` reads 38 in both columns: it is authored on the same `<EFFECTS>` element by
the same idiom as `currentEffectType_onchange` and was deliberately left unimplemented.

**535 PNGs: 0 lost, 0 new, 1 changed** — `Scooby-Doo_2/infoView`, whose `randomPic()` differs
between any two runs of any binary (`reference/harness.md`). So the headless corpus is unmoved, as
predicted: nothing changes an attribute in a still.

**The three new `traced_calls` are one skin and they are the element half working.** `Main_Street`
authors `visible_onchange="vidmodebut()"`, which had never run; it now reads
`player.currentMedia.ImageSourceWidth` and writes `nmsm.enabled` / `nmmm.enabled` — two buttons
that were left disabled. No pixel moves in the default state because `enabled` there gates input,
which is exactly why a sweep could not have found this row and cannot close it.

**Verified live by the reporter, 2026-09-11**, on the one signature that exists:
`currentEffectType_onchange` → `setVisEffectsText()` → `visEffectName.value = currentEffectTitle
+ " - " + currentPresetTitle` (both implemented by W101). Switching visualization effect now
repaints the label, which previously kept its load-time value forever and threw nothing. `corona`
confirmed unmoved — it authors 10 `enabled_onchange`, newly live, each
`cursor=enabled?'hand':'system'`, an unqualified write that lands on a JS global rather than the
element because this engine deliberately has no `with(element)`.

**`currentPreset_onchange` landed with it after the breadth question was put properly.** It was held
out of the first pass as "outside the decided four", which is a process answer and not an
engineering one. The engineering answer is that it is the same `<EFFECTS>` element, the same
write-back idiom (all 40 uses are `mediacenter.effectPreset=currentPreset`) and safe for a reason
that had to be checked rather than assumed: `WMPEffectSelection.setPreset` early-returns on an
unchanged value, so the handler cannot loop or restart the visualizer. A setter that re-applied
would have made it the wrong call.

**The same pass found the hole underneath all five: nothing refreshed the snapshot on an effect
change.** Every other path into `refreshHostState` is a track, a 10 Hz clock tick, a transport
action or a file open, and choosing a visualization from NullPlayer's own menu is none of them —
`WMPEffectSelection` posts its own notification and the controller did not observe it. With a track
playing the position tick hid it completely (the event lands inside 100 ms, which is how the live
verification passed); with the player **stopped**, `currentEffectType_onchange` would never have
been raised at all. The controller now observes `WMPEffectSelection.didChange`. **A host-side
`_onchange` is only as live as whatever refreshes the snapshot** — check that before counting the
diff as a dispatch site.

**The rule this row leaves behind: reading a handler's reach is not reading its result.** Three of
the four host attributes were described as visible and are not. 96 of the 105
`currentPosition_onchange` uses are `seek.value = player.controls.currentPosition`, a number **W120
already supplies** from the declared range; all 9 `currentMedia_onchange` uses are
`updateAlbumArt()`, whose body asks for `WMPImage_AlbumArtLarge`, a built-in this engine does not
resolve — **opened as W137**. Read the body before naming a skin to look at.

## Phase 17 (third pass) — named colour values

| ID | Item | Reach | Notes |
|---|---|---|---|
| W130 | Two colour parsers and only one knows names, so declared chrome is invisible to the palette | `backgroundColor` authored as an SDK name in 92 skins (`black` 124 uses, `pink` 14, `blue` 3, `white` 1); `foregroundColor` in 22 skins (`white` 52, `black` 37), measured over 177 readable archives | **Closed 2026-09-11.** WMP's Color Reference permits 140 named colours for every colour attribute, but `WMPAttributeParser.color(from:)` had accepted only `#RRGGBB`; `WMPSceneBuilder` separately recognized five names while `WMPSurfacePalette` recognized none. The parser now owns the full SDK table, case-insensitively, and both scene fills and palette roles route through it. `"none"` remains unparsed, preserving WMP's absence/transparent semantics. `testAttributeClassificationDoesNotExecuteAuthoredCode`, `testColorAttributesAreParsedAsStrictlyAsTheEngineDoes`, and `testNamedColorsDriveTheSceneAndSurfacePalette` pin classification, raw palette attributes, a rendered `pink` fill, and a named foreground role. The named-colour census and the resulting declaration counts are recorded in `wmp-skin-guide`; 165 of 177 readable archives now declare a parseable background colour and 171 a foreground. |

## Phase 17 (fourth pass) — TEXT interaction colour roles

| ID | Item | Reach | Notes |
|---|---|---|---|
| W131 | `hoverForegroundColor` and the TEXT hover-colour family are never read | `hoverForegroundColor` **212 uses / 40 skins**, `hoverBackgroundColor` 5 / 1, `disabledFontStyle` 20 / 2 | **Closed 2026-09-11.** `WMPSceneBuilder` already tracked a TEXT hit target's hover state, but used it only for image artwork. It now resolves `hoverForegroundColor` and `hoverBackgroundColor` before their normal roles, and uses `disabledFontStyle` in the disabled state. The pre-fix live probe against Plus! Bionic Dot's `videoView/resetButton` recorded `onMouseOver resetButton#235` while it still painted its normal `#666666` foreground despite authoring `hoverForegroundColor="#CCCCCC"`; that control now has an observable hover paint role. The named `blue` test input proves this row uses W130's shared parser rather than a second colour table. `testTextUsesItsHoverColorsAndDisabledFontStyle` pins normal, hover, and disabled behavior. |

## Phase 18 — the z-order an `<EFFECTS>` declares, and the engines that ban rested on

Closed 2026-09-11. Reported live as "visualizations in `.wmz` skins are circular everywhere":
Cerulean looked close, Corona's square pane and Plus! Professional's tilted oval showed a foreign
circle, and the newly added Cava / vis_classic were circular too. The investigation found two
independent defects, one documented rule that was **backwards**, and a second rule whose evidence
turned out to be the first defect's symptom.

**The first attempt was wrong on screen and the reporter's screenshot is what caught it**, which is
the row's most useful lesson. Capturing the split index at the point the effects node was *visited*
is not the boundary: a parent emits its own paints before walking any child, so `face.bmp` landed
*below* the visualizer and Cerulean drew bars across the whole face. A negative `zIndex` means
behind the parent's own artwork, and DFS order cannot express that at all — the walk now visits a
node's negative-`zIndex` children **before** the node paints anything. Siblings were already sorted,
so `bEye` (`zIndex="-2"`) still lands under the visualizer (`-1`).

What had been "verified" before that screenshot was a structural probe (the split index falls where
expected) and a render dump — **and the effects surface is not in a render dump at all**. Neither
could see the defect. `coverage probe is not proof` applies exactly here.

**Verification.** Corpus render-dump sweep over all 180 archives against a same-tree baseline
worktree: 536 PNGs, **29 views changed, none lost, none blank** — the reach of the negative-`zIndex`
reordering. `Asimov_Radio/view-2` is the worked case: the black slab over its dial is gone and the
round bezel and its markings survive. Cerulean's own dump is *unchanged*, which is itself a check —
the eye disc moved from after `face.bmp` to before it, and the face keys out a 73px hole exactly
there, so the composite is identical either way. `swift test` green (2,186). Classic and Winamp
Modern confirmed untouched by grep rather than assumed: no file under `Skin/`,
`Windows/MainWindow/`, `ModernSkin/` or `Windows/WinampModern/` names any WMP type. **The on-screen
confirmation came from the reporter driving the app**, not from the harness.

| ID | Item | Landed |
|---|---|---|
| W138 | A paint command's index into `WMPScene.commands` was not stable | Whole corpus; **zero image change** | **Closed 2026-09-11 with W139, which needed it.** `WMPSceneBuilder` ran `commands.removeAll { $0.alpha <= 0 }` *after* the DFS returned, so any index captured during the walk was silently shifted by every zero-alpha command before it — 717 of the corpus's 778 `alphaBlend` uses are exactly `alphaBlend="0"`. Nothing read an index into `commands`, so it had never fired. The filter now runs at each `emit` call site, where alpha is already computed, and the post-hoc `removeAll` is gone. Pure refactor: the same commands survive in the same order. Verified byte-identical over the 180-archive corpus dump (536 PNGs). |
| W139 | An `<EFFECTS>` surface could never be occluded by the skin's own artwork | **32 `<EFFECTS>` across 30 skins author a negative `zIndex`**; 107 rects carry numeric dimensions, of which **19 square, 83 wider than tall, 5 taller** | **Closed 2026-09-11.** Reported live as "visualizations in `.wmz` skins are circular everywhere". Two independent defects. **(A)** `WMPMainView` blitted the scene as one flattened image and hosted every widget over it with a plain `addSubview`, so no skin artwork could cover the surface; the stand-in was a centred inscribed circle, which approximated Cerulean's real 73px keyed-out hole and was wrong everywhere else. **(B)** `drawSpikes` (the default), `drawBars` and `drawAmbience` drew rays and rings about `bounds.mid` at `min(w,h) * 0.46` and were never clipped at all — removing the clip changed nothing for them. Fix: a node's negative-`zIndex` children are walked **before** it emits its own paints (DFS order cannot express "behind the parent's background", which is what a negative `zIndex` means), `WMPWidget.commandSplitIndex` then records where the walk was when the effects node was visited, `WMPRenderer` emits a second "above" raster from that index, `WMPMainView` hosts the surface between the two layers (`effects` → overlay `NSImageView` → interactive widgets, re-enforced every `synchronizeWidgetViews` pass), and the three polar renderers were re-authored against the rect. The split is an **index, not a zIndex threshold** — `walk` sorts only siblings. **It corrected a rule in `SKILL.md` that was backwards**, which is what had made the circle look like the answer; see § *An `<EFFECTS>` rect is never shaped by this engine*. |
| W140 | ProjectM, Geiss and Tripex in the `<EFFECTS>` slot | Catalogue goes 5 → **8**; the slot reaches **171 skins** | **Sequenced behind W139 and deliberately a documented reversal** — `SKILL.md` forbade hosting these three, and `WMPEffectsSurfaceView.makeEngineView()` / `applyPreset(to:engine:)` are the dead code left behind by that decision. Its evidence was the black ProjectM panels reported in Asimov Radio and Cerulean, and **those were W139's defect**: an opaque renderer nothing can occlude *is* a black rectangle over the artwork. With the split landed, opacity stops mattering — WMP's own visualizers were opaque too. The reversal is recorded in `SKILL.md` § *The ban on hosting ProjectM / Geiss / Tripex … is reversed*. **The work is not re-enabling the dead code.** `VisualizationGLView` is an `NSOpenGLView` that clears to opaque black, drives itself from its own `CVDisplayLink`, and must **not** be mounted live between the two raster layers: a legacy CGL drawable's ordering against sibling `CALayer`s is not guaranteed the way layer z-order is, and its independent clock tears against the overlay's alpha-blended edge. It has to render **offscreen** (FBO + readback, or a small offscreen `NSOpenGLContext`) into a `CGImage` that `draw(_:)` presents like the CPU paths, and **no readback path exists anywhere in `VisualizationGLView.swift`** — `renderFrame()` draws straight to the onscreen drawable. Readback at 60fps for three engines has a real cost; measure it before choosing. Selection stays WMP-session-scoped either way: `WMPEffectSelection` must never write `visualizationEngineType`. |
| W50 | `theme.openViewRelative` is not implemented | **2 skins** (`Revert.wmz`, `Revert (1).wmz`, the two releases of the same skin) | **Closed 2026-09-11 with W141**, which is the row it was always waiting on: it was left out of W49 on the explicit grounds that *"it is only worth doing with somewhere for a second window to go, so rank it with whatever answers that question, not before"*, and W141 is that answer. The offset is now the new window's first placement — `dx,dy` skin pixels from the opener's top-left, y flipped and scaled by UI Size, then clamped by `rescuedOrigin` — in place of the tiler, and only on the first show, so a window the user has dragged is never yanked back. It rides the action (`openViewRelative:<dx>,<dy>`) the way `setEQBand:<n>` already does, because a host command carries one value and the view id is it. **A non-finite offset falls back to a plain `openView`** rather than placing a window at NaN. Measured after the change with `scripts/wmp_skin_census.sh`: `theme.openviewrelative` is **absent from the `UNKNOWN member` tally entirely** (it was `×4`), and the whole tally was re-measured in the same capture — its top rows are other backlog items (`view.returnToMediaCenter` 156, `player.launchURL` 135, `player.url` 116, `theme.openDialog` 113) and no new `theme` row appeared behind it. The corpus's own default-state sweep cannot exercise it: `Revert`'s calls are in click handlers, so **the live check is the one that counts**, and it is `Revert` with `WMP_PLACE_TRACE=1`. |
| W41 (`theme.closeView` half) | `theme.closeView(name)` was unrecognised and aborted the handler that called it | **84 of 180 archives, 183 uses** — measured 2026-09-11, an order of magnitude above the "5 skins" the row carried from a hand count | **Closed 2026-09-11 with W141.** The row was filed as small and was not: a `grep` for the member under-counted it the way W49's own reach was under-counted, and the honest number came from the census. What it cost is not a missing feature but a **truncated handler** — an unrecognised member aborts the handler on that statement, so `Halo 2`'s `checkRemoteViewStatus()` died on `theme.closeView('vidRemoteView')` and never reached the four statements after it, which is why that skin's remote could open panels and never close them. It is now live: it closes the window showing the named view and is a silent no-op when that view is not open; with no argument it keeps the meaning `view.close()` already posted. `theme.closeview` is **absent from the `UNKNOWN member` tally** in the post-change census. **Budget for what a truncated handler was hiding** — 84 skins' worth of statements are running for the first time, and per `reference/skins/README.md` that is where a latent trap fires (the `Cablemusic` `Dictionary(uniqueKeysWithValues:)` crash is the precedent). The post-change capture shows `load ok=179` and no new runtime-error causes; the remaining table is `eq.speakersize` ×18 (W39) and a long tail of ones. |
| W141 | A skin's extra views could not be windows | **90 of 180 archives call `theme.openView`, 579 times**; `view.close()` 424 uses / 170 skins; `theme.closeView(name)` 183 / 84; `theme.currentViewID` 196 / 68 | **Closed 2026-09-11.** Reported on `Halo 2`, whose playlist, equaliser, visualisation, info and video panels each *replaced* the player instead of opening beside it. WMP opens the named view as an additional window and leaves the opener alone; this engine had exactly one WMP window, so `openView` was reduced to "present the view here and remember the one it covered" (`openedViewStack` / `CoveredView`). **The reduction was not merely a deviation — it was the cause of three separate reported defects**, each of which is deleted by making the second window real rather than fixed on its own: W90 ("closing an interior window closes the whole UI", a covered view being *rebuilt* instead of left alone), W96 ("the skin is empty and shows no player", a panel persisted as the session's view) and W127 (the macOS close control stranding the user on a panel). `WMPViewWindowMaterializer` is modelled directly on `WinampModernHostedWindowMaterializer` — one borderless window per open view, all against **one shared script runtime**, placed once by `WindowManager.tiledOrigin` with `rescuedOrigin` as the never-`nil` fallback, joining the app's docking through a `.wmp`-gated branch of `managedWindowRecords` as a snap target and never a centre-stack member. It is the only one of the three other families whose recipe transfers: a `.wmz` view is an arbitrary authored canvas (Halo's panels are 406x209 against a 327x294 player) with no stack to join. **The first view presented binds the app's own window** and is the player, so the `MainWindowProviding` anchor, the restore anchor, the tiler's anchor and the unskinned fallback host are all unmoved. `WMPViewPresentation` is the seam: everything per-window (scene, overrides, limits, interaction state, the view timer, the animation clock and epoch, the script timer set, pending host events) moved onto it, and the session (loaded skin, image store, script runtime, dispatcher, host, one `WMPVideoSurface`) stayed on the controller. `WMPScriptRuntime` keys its committed overrides **and its observable-property registry** per view — a separate registry is required rather than cosmetic, because the registry only reports values that *moved since it last looked*, so two windows sharing one would each see half the changes. **Deleted, not adapted:** `openedViewStack`, `CoveredView`, `switchView(to:restoring:)`'s whole restoring path, `WMPScriptRuntime.prepareForRestore`, the W127 `windowShouldClose` stack check and the W96 `openedViewStack.isEmpty` guard (now simply "is the player"). **The drawer exception is the thing this must not touch and does not**: Corona's sliding playlist and equaliser and NVIDIA's embedded playlist/video are `<SUBVIEW>`s of the presented view's own canvas, never reach `openView`, and `WMPPhase9Tests.testNVIDIAEmbeddedPlaylistCloseReturnsToAudioMode` stayed green unchanged throughout. Closing the **player** closes the whole skin UI, panels and all — the alternative readings each strand the user, which is the W96 shape. Host refresh fans out to every open window and **skips one with no `wmpprop:`/`wmpenabled:` binding and no authored handler for anything raised**, because the runtime's 120 transactions/second is a session budget and Halo with five panels plus its 10 Hz dispatcher spends about 60 of it. Verification: full suite green (2188 tests); `WMPPhase9Tests` rewritten to the window model with five new cases; census `load ok=179` with `theme.closeview` and `theme.openviewrelative` both absent from the `UNKNOWN member` tally; accepted live by the reporter. **A byte-identical render sweep proves nothing here and was not the arbiter** — this is entirely an AppKit/controller change and a default-state corpus capture cannot see it (W73); a baseline capture was additionally not constructible, because the working tree already carried unrelated in-flight changes to `WMPRenderer`/`WMPScene`/`WMPSceneBuilder` when the work started, so a diff against `HEAD` would have measured those too. |
| W142 | The animation frame rate was well below what every scene asked for | **Whole animated corpus: 90 of 180 archives carry a multi-frame GIF (2,166 files)**; the frame-delay half touches **768 GIFs across 62 of those 90 skins**, and the loop half touches every one of them | **Closed 2026-09-11.** Reported as "the animation fps is low in general", with `AlienMorph` named as the case. **Two independent defects wearing one symptom, and nothing headless could see either**: `ANIMATION` reports what a scene *asks for*, a render dump is a still, and a byte-identical corpus sweep is exactly what both defects produce. The instrument is new and is the finding — `WMP_ANIM_TRACE=1` (documented in `reference/harness.md`), whose first live line was `want=25.0fps got=20.0fps frames=21 restarts=10 sleep=42.3ms render=4.5ms` and carries both diagnoses in it. **(A) Every rebuild restarted the repaint loop.** `startAnimation` is called by every rebuild and a `.wmz` rebuilds constantly — AlienMorph's 100 ms view timer alone restarted it **ten times a second** — and each cancel discarded a partly-elapsed `Task.sleep`, so a 40 ms frame period inside a 100 ms rebuild window landed exactly two frames: 20 fps against 25, with the shortfall growing as the rebuild period approaches the frame period. The loop now survives a rebuild whose cadence compares equal (`WMPRenderer.WMPAnimationCadence` is `Equatable`, held on `WMPViewPresentation.animationCadence`) and reads `activeScene` per frame instead of capturing one, so a rebuild replaces *what* it draws without interrupting *when*; a cadence change, a view change and teardown still stop it. Frames are also scheduled against absolute deadlines off the animation epoch rather than `sleep(period)` per frame, which absorbs both the overshoot (42.3 ms for a 40 ms request) and the serial render after it, and a whole period behind skips to the next boundary rather than bursting. Measured after: `got=25.0fps restarts=0`, held for 90 seconds. **(B) A 0- or 1-cs GIF delay was clamped to the browser's 0.1s.** 768 of the 2,166 multi-frame GIFs author a minimum delay of 0 or 1 cs — "as fast as possible" — and **625 of those author nothing else**; at 10 fps `AlienMorph`'s 119-frame shutter took 11.9 seconds to open. `WMPImageStore.animationFloor` is now 0.0667s. **679 of the 768 are one-shot**, so the floor decides how long a *transition* takes rather than how fast a loop spins, and exactly one endless corpus GIF is short enough for the rate to read as a flicker (`Creed`'s 3-frame `CloseGates`). **The floor is set by eye against the running app and no measurement can set it**: 0.04s was tried first, argued from the delays the corpus authors when it names one (1,112 of 2,166 state 4 or 5 cs), and the reporter called it too fast on sight — do not re-derive it from the corpus, that argument is what produced 0.04. **Verification.** Corpus render sweep against a baseline worktree at `HEAD`: **534 of 535 PNGs identical**, the one differing being `Scooby-Doo_2/infoView`, which `reference/harness.md` records as nondeterministic by construction. Zero changed `RENDER-DUMP`, `COMPAT`, `FINDING`, `BITMAPS` or `UNKNOWN` lines; the 494 changed invariants lines are **entirely** `loadms` timings and `SCRIPT inline:` tie-ordering (both verified as the same multiset with the timing and ordering normalised away). 88 `ANIMATION` lines before and after — no view gained or lost an animation — with `shortestDelay` moving only where a 0/1-cs GIF is now the scene's fastest image. `swift test` green (2,197). Accepted live by the reporter on the second value. |

## Phase 19 — a centred piece is centred, not offset

Closed 2026-09-12. Reported live against AlienMorph, with "it applies to many skins": "the playlist
and eq windows are not properly contructed and hte winodw border and details are not correct and
there are large gaps", followed by "video window has the same issues". One line of layout math, and
the widest single-line blast radius in this engine so far — **139 of 535 corpus images**.

**The distinction is what identified it.** `horizontalAlignment`/`verticalAlignment` have four
values and three of them are margins: `right`, `bottom` and `stretch` hold an authored edge distance
against the parent's edge, which is the delta form and a **no-op at the view's own authored size**.
`center` is not a margin — the element stays centred, so its coordinate is `(parent − own) / 2`
computed fresh and the authored coordinate on that axis is not an offset into it. The frame was
already broken at AlienMorph's authored `389x247`, with no resize anywhere in the reproduction, and
that is only possible for the one value that is not a margin. Reading it as a margin collapsed every
centred piece to the parent's origin.

**Why a frame and not a decoration.** The Alienware/ALX family — six skins sharing one
`alienware_dl.wms` — builds each of its five auxiliary windows out of nine pieces, two of which are
175-wide side columns positioned by `<subview id="plLeftCenter" verticalAlignment="center"
backgroundImage="f_left_center.png"/>` with no `top`, with a tile above and below hung off
`top="wmpprop:plLeftCenter.top"`. The corner bitmaps those columns landed on top of are what carry
the window's title bar and the top of its inner border, so the visible result was a black bar with
white stubs in it — the reporter's "large gaps" — and the side accents sitting at the top instead of
mid-height.

**`mainView` is byte-identical across every skin in the family**, and that is the process lesson:
a non-resizable player authors no centred pieces, so this entire class lived in the windows a skin
opens *beside* its player. Four phases of `mainView` work never saw it, and W68 — the row that has
tracked this family since Phase 8 — is about the player alone.

**Verification.** `scripts/wmp_render_sweep.sh` capture/compare over 179 archives: **396 identical,
139 differing, 0 lost, 0 gained, 0 unreadable.** The 514 changed invariants lines are entirely
`loadms` timings and `SCRIPT inline:` tie-ordering — no `RENDER-DUMP`, `COMPAT`, `FINDING`,
`BITMAPS` or `UNKNOWN` line moved, so no view gained or lost a node, command, hit target or canvas.
Ten of the 139 were opened side by side, chosen to be unrelated to each other and to the report, and
**every one is a repair**: `WALL-E/mainView` (its logo and the transport row), `PowerToys/view-2`
(the cancel button), `xsn_sports/msgView` (its progress panel now sits over its own pointer arrow),
`TripleX for XP/videoView` (a clipped `X3-080902` readout and the `xXx` badge), `US Army/videoUSM`
(the placeholder and its bevel), `Plus! Pulsar/videoView` (a side-drawer tab moved from the top edge
to the middle of the left edge), `Project Gotham Racing 2/plView` (`f_top_stripe.png`,
`f_bot_stripe.png`), `STALKER/plView`, `QuantumRedshiftWMPSkin/plView`, and
`T3-Skynet_Media_Player/plView`, which had been drawing a half-width frame with its own buttons
outside it. Also checked at `WMP_RENDER_SIZE=700x450`, since centring and the delta form disagree
only away from the authored size. `swift test` green (2,207), `WMPAlignmentTests` new. Accepted live
by the reporter: "that seemed to have fixed a lot of skins".

**What it does not close.** The reference shots also show WMP's own list chrome — the
`Title`/`Artist`/`Album`/`Type`/`Length` headers and the `Selected:` / `Total Time:` footer — which
the hosted overlay draws none of. That is W133, untouched.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W143 | `center` alignment was offset like a margin instead of computed from the parent | **139 of 535 corpus images** moved; the attribute is 283 uses / 67 skins horizontally and 101 / 27 vertically, and the Alienware/ALX family puts two in every one of its five auxiliary windows | **Closed 2026-09-12.** Reported live on AlienMorph's playlist, equaliser and video windows as "not properly constructed … large gaps". `WMPSceneBuilder` resolved all four alignment values as `authored + parentGrowth`, which is right for `right`/`bottom`/`stretch` and wrong for `center`: a centred element's coordinate is `(parent − own) / 2`, and a skin that wants one **authors no coordinate at all**, so the margin reading collapsed it to the parent's origin. Broken at the authored size, with no resize involved — the tell that separated it from the delta form W113 protects. The two rules are now each other's counter-evidence and are listed as such in `reference/skins/README.md`: `LostPlanet` holds the delta form, the Alienware family holds the computed one. The `isComputed` guard still wins on the centred axis, so WoW's `left="JScript:view.width-202"` beside an alignment is not counted twice, and the axes stay independent (AlienMorph's `plRightCenter` is centred vertically and pinned right). **`mainView` is byte-identical for all six family members** — a non-resizable player has no centred pieces — which is why four phases of player work never saw a class this wide. Dossier: `reference/skins/alienmorph.md`. |

## W69 — the flicker was frame pacing, not compositing

Closed 2026-09-12. Reported as "xbox live skin animated/flickers" and confirmed gone live by the
reporter after W142, with nothing in the compositing path touched. The row is preserved verbatim
below, including the three candidate causes it carried, because **all three were wrong and that is
the most useful thing it recorded**: a symptom that reads as a compositing defect can be a timing
defect, and the only thing that separated them was the instrument. See
`skills/wmp-skin-guide/SKILL.md`, "the rate a user sees is not the rate `ANIMATION` reports, and
nothing headless can tell them apart (W142)".

| ID | Item | Reach | Notes |
|---|---|---|---|
| W69 | `Xbox Live Skin` animates and flickers | 1 skin confirmed live; the flicker class covers **90 of 180 archives** that carry a multi-frame GIF | Reported as "xbox live skin animated/flickers", so the clock and the repaint loop both work and the compositing does not. Its `mainView` is also in W68's class — `19 nodes, 15 commands, 11 hits, 15 unresolved` — so some of what looks like flicker may be a starved layout rather than the repaint loop; separate the two before diagnosing either. It reports `ANIMATION shortestDelay=0.030 bounds=23,9 248x195` — a **33 fps full-scene re-render** with a sub-rect invalidation, which is the most demanding case in the corpus and therefore the right one to fix against. Candidates, none of them confirmed and all of them cheap to distinguish: (a) `present()` replaces the whole `NSImage` while `setNeedsDisplay` invalidates only the animated bounds, so the untouched region keeps older pixels against a newer image; (b) the animated `bounds` union is computed once at `startAnimation` from the scene's commands and never revisited, so a node that moves leaves its old frame un-erased; (c) 145 frames of `intro_anim.gif` decoded and cached separately may be thrashing the image store's 64 MiB LRU, forcing re-decodes mid-loop. **Instrument before reasoning**: the loop is the only thing in this engine that repaints without a script transaction, so log what it presents and what it invalidates before changing either. **That instrument now exists — `WMP_ANIM_TRACE=1`, built for W142 — and W142 closed two things this row was standing on.** The loop no longer restarts on every rebuild and no longer paces by `sleep(period)`, so the frame timing under this flicker is now correct and steady (`got=25.0fps restarts=0`); anything still flickering is compositing, which is what this row always suspected. It also **moves this skin's cadence**: `Xbox Live`'s 145-frame `intro_anim.gif` is in the 0-cs population, so the 33 fps in this row was the old scene minimum and must be re-measured before candidate (c) — the LRU-thrash theory — is argued from a frame rate at all. Candidates (a) and (b) are untouched by W142 and are still the place to start; re-run with the trace *and* a log of what `present()` invalidates. **Closed 2026-09-12 by W142, and it was never the thing this row suspected.** The reporter confirmed live that the flicker is gone, with no compositing change of any kind: candidates (a) the whole-`NSImage` replacement against a sub-rect invalidation, (b) the animated `bounds` union computed once at `startAnimation`, and (c) the 145-frame `intro_anim.gif` thrashing the image store's 64 MiB LRU were **none of them implemented, and none of them needed to be**. The cause was entirely *when* a frame was drawn: the repaint loop restarted on every rebuild and discarded a partly-elapsed sleep, and this skin's 0-cs GIF was floored at the browser's 0.1s — so the picture was a correct composite of frames arriving at an irregular rate, which is what a flicker looks like. **The lesson is the direction the diagnosis ran**: three plausible compositing theories were written down from the symptom, and the instrument (`WMP_ANIM_TRACE=1`) named a timing defect on its first line. The row was right that the loop is the only thing in this engine that repaints without a script transaction, and right to say instrument before reasoning; what it got wrong was assuming that a steady clock was already established. It was not — no view timer in the corpus had ever fired. |

## Phase 20 — a skin's drawer, and the four things between it and working

Closed 2026-09-12. One live report against `xsn_sports`, and four unrelated engine defects under it:
*"there is a bug with video screen on xsn sports skins and others… this does not open reliably… when
clicking this it can grow to double size on the border… there also seems to be a mini drawer that
opens into the the frame with a seconds selector, this never closes."* Followed, across three rounds
of live QA, by *"it still does not open and the content still show when retracted"*, *"now it open
but 2 bugs, 1. when the skin launches it is open 2. the contents still bleed through when it is
close"*.

**The four are independent and each had to be measured separately.** The report reads as one broken
drawer, and treating it as one is what made the first two rounds feel like the same fix failing.

**What the reporter's own framing was worth.** *"i dont think a sweep is needed since we have a case
to test against"* — correct, and `cerulean` (the skin they named) is what killed the theory the
engine was about to be rebuilt around. The obvious reading of the bleed-through is that WMP's
documented "z-order **within the view**" means a flat order, which would put `xsn`'s
`<effects zIndex="25">` over its `<subview id="visDrawer" zIndex="17">`. Cerulean disproves it in
two moves: its `<statusText zIndex="2">` sits inside `<subview zIndex="4">` and must draw *over* the
seek slider beside it, and `xsn`'s own drawer artwork is unauthored `zIndex` 0, which a flat order
would drop behind the video permanently. The discriminator was `windowed`, not z. **A named
counter-example is cheaper than a sweep and settles more.**

**Two instruments were being read wrong, and that is the process lesson.** `WMPRenderer.dump` is
deliberately flat (`splitAtEffects: false`), so a render dump *always* contains the overlay artwork
the running app does not draw — three rounds of "still broken" came from PNGs that could not have
shown the fix. And `wmp_render_sweep.sh` renders one transaction per view, so the
expression-stickiness change is byte-identical across it: **485 identical, 50 differing, 0 lost, 0
gained** with and without it. `WMP_RENDER_APPKIT`/`WMP_RENDER_APPKIT_DUMP` and `WMP_RENDER_SETTLE`
are the instruments that answer those two questions, and both rules are now in
`reference/harness.md`.

Verification: `swift test` green (2,213) with `WMPEffectsOcclusionTests` new and three tests added to
`WMPScriptRuntimeTests`; `WMPAlignmentTests.testAComputedCoordinateOutranksCentring` replaced,
because it asserted the rule W144 removes. Corpus sweep 485/50/0/0, invariants moving only `loadms`
timings and `SCRIPT inline:` tie-ordering — no `RENDER-DUMP`, `COMPAT`, `FINDING`, `BITMAPS` or
`UNKNOWN` line. `cerulean`'s render is byte-identical to the baseline. Dossier:
`reference/skins/xsn-sports.md`.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W144 | An `xsn_sports` settings drawer that was in the wrong place, would not stay open, showed through the video when shut, and opened itself on every launch | Four separate rules. Centring: amends W143. Expression re-application: every view with an `onTimer`. Windowed `<EFFECTS>`: **18 nodes / 17 skins**. `onClose`: **373 handlers / 133 of 180 skins**, all previously dead | **Closed 2026-09-12.** (1) *"two drawers… double size on the border"* — the `isComputed` guard W143 carried onto the `center` case let `moveTo(0, …)`'s scripted `left` beat the centring, pinning a 141-wide drawer to the window edge while its own cover artwork stayed centred. `moveTo` takes both axes and the horizontal one is how an author says "unchanged" for a centred piece. Nothing outranks centring on the centred axis now; the guard protected only 3 corpus nodes, all in `Ice`, and all three are repairs. (2) *"it still does not open"* — an authored `JScript:` geometry expression was re-committed every transaction ahead of the mutations, so the 500 ms `onTimer` put the drawer back at `view.height-123` within half a second of every click. Expressions re-apply only when their own value changes, which keeps resize working. (3) *"the contents still bleed through when it is close"* — the drawer retracts 26px (`visView`) / 108px (`videoView`) **inside** the effects rect and relies on the windowed surface to hide it; the skin's overlay raster was being drawn over it. `WMPScene.windowedEffectsRects` is now punched out of the overlay. Ruled out and recorded: it is not `visible` (the hosted widgets do hide — what remained is `vis_drawer_1.png`, which *pictures* a button and a slider row), not `onEndMove`, not z-order (`cerulean`), not "drop the overlay" (the surface is transparent while idle, and the drawer must still draw below the rect), and not "make the surface opaque" (a stopped player draws nothing, and the hole belongs to whatever the skin painted before the effects node). (4) *"when the skin launches it is open"* — `onClose` had no dispatch site anywhere, so `saveVisPrefs()` never ran, `theme.loadPreference` answered the `--` absent sentinel every launch, and `loadVisPrefs` took its first-run branch. Dispatched before `discardView` at both window-close sites, and `flushCloseHandlersOnTermination` covers quitting, which an async close never survives. Dossier: `reference/skins/xsn-sports.md`. |

## Phase 21 — a visualization that is hosted when it should be hidden, and square when it should be shaped

Closed 2026-09-12. One live report against `Plus! Bionic Dot`: *"bionic dot spectrum is displaying as
rectangle on top of the player and look bad it should be layered in the opening"*, then, on a second
capture, *"the spectrum is just slapped on top of the UI covering controls"*. The reporter's own
framing carried two of the three findings: *"cereleon is your groundtruth and must not break"*, and
*"all plus skins seem to have unique issues I suspect they are a different sub family of skins"* —
both correct, and the second is what turned a skin fix into a rule.

**It is two defects in one rectangle, and the first hides the second.** The `<EFFECTS>` at
`120,45 169x160` is wrong in the stopped state *and* in the playing state, for unrelated reasons, so
either one alone reproduces the screenshot and neither alone explains it.

### W146 — a hosted surface ignored its container's inherited `alphaBlend`

`alphaBlend` inherits, and the scene's paint commands have honoured it since they were filtered at
`WMPSceneBuilder.emit`. A hosted `NSView` is not a paint command, and `WMPWidget` carried no alpha at
all — so `Plus! Bionic Dot`'s `<subview id="visMask" … alphaBlend="0">` correctly drew none of its
own artwork while the `<EFFECTS>` inside it drew a full-opacity visualizer over the face.

The skin closes that pane in two separate places and both were being overridden: `toggleVis()` fades
it with `visMask.alphaBlendTo(255,500)` / `(0,500)`, and `checkPlayerState()` — reached from the view's
`onLoad` — runs `visMask.alphaBlendTo(0,500)` and `visButton.enabled = false` whenever
`player.controls.isAvailable("Stop")` is false. **A stopped player is supposed to show no visualizer
and a greyed-out vis button.** Patching the markup to `alphaBlend="255"` and then patching the script
both failed to open the pane in the harness, which is the engine's script runtime getting this right.

Reach: 7 widget elements in 6 archives sit inside a fully transparent subtree — `Plus! Bionic Dot`
(twice, it ships as two archives), `Plus! Professional`, `Plus! HueShifter`, `Plus! Plasma Ball`,
`Plus! Pulsar` and `Halloween`. Five of six are Plus!. **Cerulean is not among them.**

Fixed by carrying the walk's inherited alpha on `WMPWidget` and hosting **no view at all** at
`alpha == 0` — rather than `alphaValue = 0`, so a shut pane runs no GL engine and no 30fps readback —
with partial fades applied on every sync, because `Plus! Plasma Ball`'s `alphaBlend="110"` layer is a
real state.

### W147 — a windowless `<EFFECTS>` was clipped to its container's rectangle, not its shape

`main_vis_back.png` is 169x160 and **paints 1,369 pixels — 5% of the file**. It is not artwork that
covers the visualizer; it is a shape mask, and it carries the lens in two further values the author
chose deliberately: 9,865 pixels of `#ff00ff` marking the *outside*, and 15,806 fully transparent
pixels marking the *inside*, with an arc swept out of the lower left to clear the transport ring.
Dumped:

```
##################OOOOOOO##################
#########O.......................O#########
O.........................................#
######O.OO#############O.................O#   ← the arc that clears the play controls
###############################O..O########
```

**The trap is that a keyed container means opposite things, and the corpus contains both.** Reading
every keyed container as a shape would have erased Cerulean's visualizer outright — its `face.bmp` is
56% key, 44% opaque paint, **0% transparent**, and there the key is the *hole* the visualizer shows
through while the paint occludes the rest through `WMPWidget.commandSplitIndex`. The discriminator is
a property of the file, not a threshold and not a skin name: *does it carry transparent pixels
alongside keyed ones*. Measured over all 30 `<EFFECTS>` whose container declares both a background
image and a transparency colour, in 27 archives: **28 two-state, 2 three-state** — `Plus! Bionic Dot`
(36/58/5) and `Plus! Professional`'s `vis_mask_s.png` (23/59/18, a slanted lens the hand survey had
missed and the measured rule caught).

Fixed with `WMPWidgetRegionMask` + `WMPImageStore.regionMask`, counter-flipped exactly as
`WMPRenderer.clip(to:mask:)` is. Corpus sweep after: **3 of 117 effects widgets are masked**, and
nothing else moved.

### What the instruments cost

`WMP_RENDER_APPKIT` reported `outside=0` on the unfixed skin and again on a capture whose mask was
never applied — the probe builds `WMPMainView` by hand and had not been given the mask provider the
controller installs, so it hosted the surface unclipped and the skin's own artwork drawn over it read
as the mask working. Both new `WIDGET` fields (`alpha=`, `mask=`) and the probe's provider exist
because of that round; see `skills/wmp-skin-guide/reference/harness.md`.


## Phase 22 — a player that hovered and did nothing

Closed 2026-09-12. Reported against one skin — *"plus pulsar skin seems to ignore most clicks despite
showing hover graphics"* — followed by *"you might want to test other plus skins for the same
defect"*, which is what turned it from a skin fix into three engine rules.

### W148 — hit testing asked the wrong question in three different ways

**Hover and click take the same path.** `WMPMainView` resolves both through `interactiveTarget(at:)`,
so "it highlights but does not respond" cannot be a dispatch defect: it is a control the pointer
reached for hover on one set of pixels and never reached at all on the rest. That is what made the
report legible, and it is worth stating because the next one will sound the same.

`Plus! Pulsar` authors its equalizer, playlist and three visualization buttons as one
`<BUTTONGROUP>` inside a `<SUBVIEW zIndex="10">`, and lays a `<CUSTOMSLIDER zIndex="55">` on either
side of it in `<SUBVIEW zIndex="5">` siblings whose 79x136 rects cover the group completely.
`WMPHitTester` sorted a *flat* array by the authored `zIndex`, so `55 > 0` handed all five clicks to
a slider. `WMP_RENDER_CLICK="mainView@218,100"` returned `hit=volume#34 kind=customSlider`.

**No probe could see this class, so the first work was building one.** `starved.tsv` ranks views
that failed to *lay out*; `Pulsar/mainView` lays out completely and its `RENDER-DUMP` line —
`27 nodes, 19 commands, 9 hits, 4 widgets` — is healthy. A fully resolved view whose controls are
buried reads as a pass in every count the harness had. `WMP_RENDER_OCCLUDED=1` samples each target's
own rect and reports the ones nothing reaches, under both the old rule and the new, with the blocker
named; `reference/harness.md` carries it.

**Each of the three rules was landed on a measurement that killed the previous attempt.** The
sequence is the point:

| Attempt | recovered | lost |
|---|---|---|
| Paint-traversal order alone | 91 | **75** |
| + artwork coverage | 101 | **144** |
| + "an all-transparent sprite is a hit catcher" | 101 | 24 |
| + `<EFFECTS>`/`<VIDEO>` rank last | 103 | **16** |

The 75 says ordering alone is wrong: `Navigator` puts its `close` button in a `zIndex="-1"` subview
under a `progress` slider and cuts holes in `progress_map.bmp` where the button sits, so it needs
coverage, not order. The 144 says coverage alone is worse: `holiday_skin`, `Grinch` and
`Josie_and_the_Pussycats` build whole transports out of fully transparent `<BUTTON>`s laid over
artwork their parent draws, and reading those as "drawn nowhere" removed 104 working controls. Both
numbers came from the same sweep on the same tree and neither was predictable from the markup.

Of the 16 that remain, 10 are `<BUTTONGROUP>` *containers* with no mapping children, which dispatch
nothing in any case. The rest are open in `WMP_TASKS.md`.

**The fixture that pushed back is in the suite already.**
`testAMagentaMappingColorStillAnswersThePointer` reuses a mapping image as artwork, so coverage read
its `#FF00FF` region as the implicit transparency key and deleted the button from its own map. That
is the third guard: **a node with a `mappingImage` takes its hit region from the map, never from its
art** — `WMPHitTester` already consults the map per colour and per child, and asking the artwork as
well can only contradict it.

Reach: **103 controls across 32 archives**, `WMP_RENDER_HOST=playing`. 7 of the 13 Plus! archives
(`Pulsar` 3, `HueShifter` 5, `Bionic Dot` ×2, `Plasma Ball`, `Professional`, `SlimLine`), and the two
worst are not Plus! at all — `Beck` 16 and `Spider-man` 13.

### W150 — the seek arc, and the square it lives in

Reported the same day, against the same skin, once W148 made its buttons reachable: *"the seek area
does not work properly"*, then *"there is also a clickable artifact to the right of the seek that
does nothing"*. **Three defects in one control**, and the second report is the tell for the third —
an "artifact that does nothing" is something advertising itself as a control while hitting nothing.

`Plus! Pulsar`'s `seekMain` and `volume` are diagonal **arcs inside 79x136 squares**. Only 29% of
each square is the control.

1. **A keyed colour in a position map read as a fraction.** `WMPPositionMap` treated only
   alpha-zero pixels as outside the control. `seek_map.png` marks its 7,111 non-arc pixels — **66%
   of the file** — as opaque `#ff00ff`, which averaged to a luminance of 170 and therefore a
   fraction of `0.667`. Clicking anywhere in the dead corners seeked to 67% of the track. Predates
   W148. Fixed by passing the node's `transparencyColor`/`clippingColor` into the map and marking
   those pixels unmapped; the store's cache key had to take the colours too, since it was keyed by
   path alone on the assumption that "nothing about the node changes what the map decodes to".
2. **W148's coverage asked the artwork instead of the map.** `seek.png` is a 13-frame filmstrip, so
   its opaque area is a property of whichever frame the *current value* selects — and even at one
   frame it disagrees with the map by **577 pixels on seek and 551 on volume**, all of them the
   arc's soft edges, which is exactly where a pointer aims. A `CUSTOMSLIDER` with a `positionImage`
   now takes coverage from the map, the same way a `<BUTTONGROUP>` takes it from its mapping image.
3. **The cursor and the tooltip still covered the square.** `resetCursorRects` and the
   `stringForToolTip` widget fallback both scan bounding boxes, so the dead corners kept a hand
   cursor and a "Seek" tip. Both consult `WMPHitCoverage` now. The cursor is added as one rect per
   run of covered pixels per scanline — `addCursorRect` is a list AppKit scans, and the arc is ~136
   bands where a pixel mask would be thousands.

**The grey check is why this was safe to land.** Excluding keyed colours from a position map would
clip a legitimate ramp value if any skin keyed a grey, since the ramp *is* greyscale. Scanned across
the corpus before the change: 335 `<CUSTOMSLIDER>` tags, 173 declaring a key on a node with a
position image — `#ff00ff` 148, `#00ffff` 21, `#473f3f` 2, `#665577` 1, `#ff0000` 1 — and **not one
is a grey**. Re-run that scan before widening this rule.

Corpus after, `WMP_RENDER_HOST=playing`: **112 controls in 33 archives recovered, 11 lost**, from
W148's 103/16. Both `lost` and `unreachable-either-way` (155 → 146) moved down, which is the shape a
correct narrowing has.

### W151 — the seek committed to wherever the track already was

Reported as *"seek is still not working"* after W150, then *"it snaps back when you release the
mouse"*. Diagnosed by one sentence from the reporter: *"the volume is fine and has the same control
shape"* — which exonerates everything the two controls share (geometry, coverage, position map, hit
ordering) in a single move and leaves the markup.

**The cause is an implicit binding the engine adds, fighting the user's own gesture.**
`WMPPropertyRegistry.positionSliderPaths` gives any slider whose `max` binds to
`player.currentMedia.duration` an *implicit* `value` binding to `player.controls.currentPosition`,
even when the markup declares no `value` — that is W128, and it is right: without it the filmstrip
never advances and the clock never moves. But it settles on **every transaction**, including the one
raised by the release, and `Plus! Pulsar` commits its seek by reading the control back:

```xml
<customSlider id="seekMain" max="wmpprop:player.currentMedia.duration"
              onmouseup="player.controls.currentPosition=seekMain.value;"/>
```

So the binding overwrote the dragged value microseconds before the handler read it. `volume` is
immune because its `value` binds to `player.settings.volume`, which `performSlider` recognises
through `WMPTransportAction.boundAction` and commits **natively**, never through the script.

Fixed by holding the element for the length of the gesture:
`WMPPropertyRegistry.changes(for:origin:holding:)` skips `value` for elements the pointer is
dragging (only `value` — `enabled` and `max` still settle, so a track ending mid-drag still disables
the control), and `WMPMainWindowController.sliderCaptureActive` suppresses the two position events
that would otherwise raise the skin's own write-back handler. Two ordering traps came with it, and
both produced a *plausible* wrong answer rather than a failure:

- **`dispatchScriptTransaction` cancels the presentation's previous script task**, so dispatching
  `mouseup` and then `dragend` cancelled the first before it ran. Both handler sets now go into one
  event.
- **`dispatchScriptTransaction` only *creates* a task.** Releasing the hold on the line after it
  released the element before the transaction ran, and the binding settled anyway. The release now
  `await`s `presentation.scriptTask?.value` first.

Measured live at each stage, dragging to the middle of the arc on a 1,155 s track:

| | committed by the release | reached the engine |
|---|---|---|
| before | 520.99 s | `seekSeconds=18.95`, `positionBefore=18.95` |
| after | 520.99 s | `target=520.99`, `positionBefore=926.71` |

**Reach: 148 sliders across 112 of the 180 archives.** That is every slider whose `max` binds to the
track duration *and* which commits the seek in its own `onmouseup`/`ondragend`/`onchange` handler —
measured by decoding each `.wms` the way `WMPTextDecoder` does and matching both conditions on the
same tag. 114 archives carry the implicit binding at all. This was never a Pulsar defect; Pulsar is
where it was looked at.

### What the instruments cost, and what found this

**Four headless "proofs" in a row were all consistent with a seek that does not work.** A
hand-built sequence through the real runtime committed `seekSeconds=150` and was wrong about the
app, because it did not contain the implicit binding's settle. The lesson is the one
`measurement-is-not-its-interpretation` already states, in its sharpest form yet: *every* link in
this chain is plausible in isolation and only the live sequence is wrong, so nothing short of
driving the running app could have found it.

What worked: a debug build launched with `NULLPLAYER_SKIN` + `NULLPLAYER_PLAY`, `AXRaise` on the WMP
window, a CGEvent drag tool, and `WMP_SEEK_TRACE=1`. Three traps on the way in, all of which look
like "the fix did not work":

- **A redirected `print` is block-buffered.** The first capture produced an empty log while the app
  was working. Live traces write to **stderr**.
- **The first click on an inactive window is consumed activating it**, so the first whole drag
  produced no trace at all. Drive an activation gesture, then the real one.
- **A 5-second track cannot show a seek** — the reporter caught that one. `NULLPLAYER_PLAY` wants
  something long; the capture above used a 19-minute recording.

## W153 — the view a skin declares it opens in

**Closed 2026-09-13.** `WMPMainWindowController`'s candidate walk was
`[persisted view, "vPlayer", document order]`, and `<THEME currentViewID="…">` — WMP's authored
startup view — was in none of it. `portals` declares `currentViewID="mode1"` and defines `mode2`
first, so document order decided on the skin's behalf and the player opened on its info mode: a
359x465 window where `mode1` is 550x400, with the mode button nowhere near where anyone was
clicking. Reported 2026-09-12 in the compact-mode audit as the one skin of eleven whose mode button
did nothing.

`WMPDeclaredHostState.authoredStartupViewID(in:)` reads it and the walk inserts it **after** the
persisted `wmpSkinViewID` and **before** `vPlayer`: a skin naming its startup view is not a skin
overriding where the user last left it. A literal decides and nothing else — a `wmpprop:` value here
would be asking the host which view to show before any view exists.

**Reach is one skin and that was measured before the fix, not assumed**: 16 of the 180 archives
author the attribute and `portals` is the only one whose walk lands elsewhere. Verified live —
`defaults write NullPlayer wmpSkinName portals`, `defaults delete NullPlayer wmpSkinViewID`, debug
launch: the window opens 550x400 and `wmpSkinViewID` persists `mode1`, where both were `mode2`
before.

**It closed one row and opened another, which is the point of it.** `mode1` had never been on
screen, so nothing in it had ever been looked at: W154 is what was waiting behind this. A fix that
makes a dead view live is expected to uncover what was sitting in it — that is not evidence the fix
was wrong.

## W100 — *Return to full mode*, the corpus's most widely authored dead control

**Closed 2026-09-13.** `view.returnToMediaCenter()` is authored by **162 of the 180 archives — 196
controls, 179 of them tooltipped exactly "Return to full mode"**, and **107 skins carry one in the
view the player opens in**. It was unrecognised, so every one of them died on its own first
statement. Reported live 2026-09-09 as "the 2 top right windows do not work" and again 2026-09-12,
from the other end, as *"all skins seem to have a compact button"* — which is what this button is
mistaken for, because a real compact mode exists in only 11 archives and this one is everywhere.

**The count the row asked for could not come from the census**, and that is why it stood unmeasured
for three days: `wmp_skin_census.sh` drives `onLoad`, these sit in `onClick`, and W136's figure of 7
is what that blind spot sees. The corpus number came from a script-text scan decoded the way
`WMPTextDecoder` does — 153 UTF-16-BOM / 145 cp1252 / 88 UTF-8 / 9 UTF-8-BOM text members, matching
the harness's own calibration — with each located control then driven by a click.

**What it does now: it opens the Library Browser.** WMP leaves skin mode for the player's own shell
— menu bar, library, playlist — which this player has no single equivalent of. The decision was
taken against three candidates: the unskinned default player (`WMPUnskinnedMainView`, the structural
twin of WMP's full mode, rejected because it takes the user's skin away and offers no way back),
leaving WMP mode for Classic/Modern (a different product), and the library (chosen: the closest
surface NullPlayer has to what full mode is *for*). **Not `closeView`**, which the row forbade by
name, and not `inert()` — see below.

`WMPObjectModel` posts `openLibrary` from `case (.view, "returntomediacenter")`, the way `close` and
`minimize` post `closeView` and `minimizeWindow`; `WMPMainWindowController` calls
`WindowManager.showPlexBrowser()`. **Show, never toggle**: the button says one thing, and a second
press meaning "put it away" is not what the artwork claims. The skin is untouched and the browser
opens beside it in chrome derived from the active `.wmz`, like every other NullPlayer-owned window
in this mode.

**`inert()` was the cheap option and it would have bought nothing**, which the measurement settled
rather than taste: across all 196 controls the call is the **last** statement — 189 are the bare
call alone, 6 have `savePrefs()`/`saveVars()` before it, and **0 have anything after it**. So
recognising the name without acting on it would have removed a diagnostic and changed nothing a user
sees. That is also why `testReturnToMediaCenterOpensTheLibrary` asserts the handler *continues* past
the call: it is what separates an implementation from an `inert()`.

**Dispatched on the `<VIEW>` kind, never on the receiver's spelling**: 13 of the 196 call it on a
named view element — `vFull` ×2, `ballview`, `ErectorView`, `KidsView`, `military`, `normal`,
`ExtremeSportsView`, `tvView`, `main`, `animeView`, `digitaldj` — and the test pins both forms.

**Verified 15 of 15 headlessly** (`Navigator`, `Gorillaz`, `Plus! Plasma Ball`, `Vario`,
`BlueCrush_MP7`, `Creed`, `springflower`, `Stealth`, `Ducky`, `Plus! Bionic Dot`, `Thomas`,
`BlueCrush_MPXP`, `Secura`, `Jaws`, `Beck`): each now prints `command=openLibrary` with
`unrecognised=[]` where it printed `[handler-error] … unimplemented view.returntomediacenter`.
**Live on `BlueCrush_MP7` and `Thomas`**: the browser opens beside an untouched player, wearing the
skin's own chrome. `maximize`, `restore` and `size` remain the unimplemented `<VIEW>` methods and
the corpus calls none of them; `restore` took this name's place as the census exemplar in
`WMPScriptRuntimeTests`.

## W157 — the host refresh that fed itself

**Closed 2026-09-13.** Reported as *"the nvidia skin is very clunky moving between the video window,
playlist and the main window"*, and it was never NVIDIA's: with a track playing, **every** `.wmz`
skin was rebuilding and re-rendering its whole view about 40 times a second, forever.

`dispatchScriptTransaction` ended on

```swift
let hostStateBeforeCommands = host.snapshot
defer { if host.snapshot != hostStateBeforeCommands { refreshHostState() } }
```

which is right about what it is for — a command the transaction posted changes what its own bindings
resolve to, and nothing else was going to notice — and wrong about how to detect it.
`WMPAudioEngineHost.snapshot` is **computed live off the engine and carries `currentTime`**, so the
two readings are taken ~10 ms apart on a moving clock and *always* differ. The diff was therefore
non-empty on every pass, including the overwhelming majority that posted no command at all;
`refreshHostState` then raised `currentposition_onchange`, which dispatched another transaction,
whose own `defer` raised another. A loop with no governor but the pipeline's own speed.

**Measured live, release build, `NVIDIA`, one local MP3, audio mode:** `refreshHostState` called
**39.9x/s from the defer against 9.9x/s from the real 10 Hz clock tick**, and every one of those
transactions posted **zero** host commands. Roughly three quarters of all repaint work in the engine
was the loop chasing its own tail. The guard is now taken only when `output.hostCommands` is
non-empty: a pass with no commands cannot have moved the host, and the tick that genuinely moved is
already delivered by `updateTime`.

**Before → after, same skin, same track, measured with a temporary transaction trace** (release,
`mainView`; the trace was removed in the same change):

| | before | after |
|---|---|---|
| audio mode 285x301, playing | 39.8 transactions/s, 32 presents/s, 45% CPU | 17.7/s, 15.4 presents/s, 30% CPU |
| playlist mode 730x574, playing | 30 transactions/s, 22 presents/s, 56% CPU | 17.8/s, 13.6 presents/s, 28% CPU |
| click → first correctly-sized frame | +40 ms | +18 ms |

**Debug builds are where this was reported from and they are 6x worse, which is worth knowing before
reading a bug report against one.** A debug scene build is ~31 ms against release's ~4.6 ms, so in
debug the arrival rate (33/s) beat the completion time (49 ms) and almost every transaction was
cancelled mid-flight: playlist mode ran at **0.8 presents/s and 130-160% CPU** — literally about one
frame a second — against 9.2 presents/s after the fix. See `reference/harness.md`; a perf claim from
a debug build is a claim about debug.

## W158 — a transaction whose script moved nothing still redrew everything

**Closed 2026-09-13**, alongside W157 and found by the same trace. Every script transaction rebuilt
the scene and re-rendered the whole window, whatever its handler had done — and a skin's own
`onTimer` is a transaction per tick. `NVIDIA` authors `timerInterval="100"` and its handler only
pokes `btnEq.down`, so it spent 17 ms of build-and-render ten times a second (release, playlist mode)
redrawing an identical picture; **442 `timerInterval`/`onTimer` uses across 91 archives** are in the
same position.

`transact` returns the view's **cumulative** committed overrides, not a delta, so an output equal to
the ones the presented scene was built from is a statement that every geometry value, every property
and every `wmpprop:` binding resolved exactly as it already had — the readouts included, because a
clock that advanced moves `currentPositionString` and a bound slider's `value` through the same
registry. There is no third source: `WMPSceneBuilder.build` takes no host snapshot, only these. So
the transaction returns before building when the overrides, the list items and the canvas size are
all unchanged and no `view.width`/`view.height` was assigned. `presentedListItems` is new on
`WMPViewPresentation` for the one input that is not an override — a `LISTBOX` is filled from script.

**What it does and does not reach, measured.** Stopped, after its intro, `NVIDIA`'s 9.5 timer
transactions/s are **all** skipped: 0 presents, CPU 22% → 9.5%. *Playing*, it skips nothing, and that
is correct rather than a shortfall — the trace names what moves, and it is `seek.value` at 16/s (the
position binding) plus the metadata marquee's `left` at 10/s. Something really did change; what is
still wrong there is that a moved clock digit repaints the entire view, which is the dirty-region
work `dispatchScriptTransaction` documents itself as not doing and is not this row.

Hover and press artwork are untouched — those never come through here, they come through
`renderInteraction` on its own task — and animation is untouched too: `startAnimation` runs its own
loop, and a *skipped* rebuild is one fewer epoch rewind (W85), not a frozen GIF. Full suite green
(2253 tests, 0 failures, 18 skipped).

## W159 — an authored expression taking back a property the script assigned

**Closed 2026-09-13.** Reported live on `NVIDIA` as *"the timer in the playlist draws at the wrong
location"*. The digits were the symptom; the defect is one line of layout policy, and it took two
corpus A/Bs to get the policy right.

**What the skin does.** `setModesMinWidth('playlist')` assigns `mainModeMetadata.left = 220` and
`mainModeMetadata.width = view.width-266`, then resizes the view from 285 to 700 in the same handler.
The element authors `left="55"` — a literal, which yields to a script assignment permanently — and
`width="jscript:view.width-101"`, which does not: W144 re-applied an expression whenever *its own*
value changed, and the resize changed it. Measured in the running app with a temporary frame trace:
`mainModeMetadata` settled at `left=220 width=629` — the script's left beside the *expression's*
width — giving it a frame of `220,468 629x25` in a 730-wide window, 119 px past the right edge and
clipped to 510. The time group hangs off `left="jscript:mainModeMetadata.width-80"`, resolved against
629 instead of 464, and drew at `x=769`: off-window. Audio mode was correct throughout, which is why
it read as a playlist-only defect.

**Reach: 18 of 180 archives, 86 element/property pairs** — a script assigning `left`/`top`/`width`/
`height` on an element whose markup authors that attribute as `jscript:…`. `Plus! Nature` 16,
`Plus! Space` 14, `Plus! da Vinci` 14, `Plus! Aquarium` 12, `WALL-E` 8, `digitaldj` 6, `Halo 2` 3,
then singles. Measured by decoding each archive and matching `id="X"` + expression attribute against
an `X.prop =` assignment.

**The rule is two halves, and each half was found by measurement after the previous form was wrong.**

1. *Retire the expression.* `WMPScriptRuntime` records every geometry address the script writes and
   skips the authored expression for it — in `WMPScriptContext.resolveExpressions` too, not only on
   the way to the overrides. That second place is load-bearing and was missed on the first attempt:
   the expression still wrote its answer into the element model so dependants could read it, so
   `metadata.width` and the time group went on resolving against 629 while the bar itself sat at the
   script's value. The live trace is what showed it — the bar corrected and the digits did not move.
2. *Anchor it at the canvas it was assigned against.* Retiring alone freezes a script-placed node in
   absolute terms, and the corpus A/B at a forced `WMP_RENDER_SIZE=900x700` drew `xsn_sports`'s
   drawer **floating in the middle of `visView`** — the one skin W144 was reported against. A script
   assignment is a plain number written at whatever size the view had at the time, so
   `WMPSceneBuilder` treats it as a literal for `right`/`bottom`/`stretch` and re-anchors it by the
   growth **since the assignment**. `visDrawer.moveTo(0, view.height-73, 400)` on a
   `verticalAlignment="bottom"` node then stays 73 up from the bottom at any size, and `NVIDIA`'s bar
   is 19 + the 445 the view grew = 464, which is `view.width-266` at the new size.

**Measuring that growth from the *authored* size instead is the trap, and the sweep caught it.**
That form moved 15 default-state views — `Catwoman`'s video settings drawer, the Alienware/ALX
`videoView` family, `Windows_XP_Media_Center_Edition`, `Scooby-Doo_2`'s info panel — because those
skins size their own view by script at load, so the authored-size delta is not zero for them and
their panels slid open on sight.

**Verification.**

- **Corpus render sweep, default state: 535/535 images byte-identical** for half 1 alone; with both
  halves, **13 views change and 0 structural invariant lines do** (the 498 flagged lines are all
  `loadms=` timings and unordered tally ordering; normalising both leaves zero).
- **The 13 are the same defect being fixed, checked by reading the skins rather than by eye.**
  `Catwoman`'s `onLoadVid()` calls `toggleVidDrawer('0')` with `drawerStatus` false, which takes the
  branch that sets `vidDrawerFrame.visible = true` and `btnVidDrawer.down = true`: its drawer is
  *meant* to be out, and the authored `top="jscript:view.height-242"` was pulling it back behind the
  picture. `Scooby-Doo_2`'s info art lands where its script puts it.
- **Live**: `NVIDIA` in playlist mode, frame trace — `mainModeMetadata` `220,468 464x25` fully
  visible, the time group's left override `384`, digits at `604/621/643/660` each clipped to their
  15-px slot, and the readout reads `00:29` inside the bar where audio mode puts it.
- **Headless**: `WMP_RENDER_CLICK='mainView@200,95'` still reports `viewSize=700x480`, so the mode
  switch dispatches unchanged.
- Full suite green: **2254 tests, 0 failures, 18 skipped**.

**One test changed meaning and was rewritten rather than deleted.**
`testAResizeStillLetsTheExpressionOverrideTheScriptedPosition` asserted the *old* policy — that a
resize hands the axis back — on the reading that nothing else would carry a script-placed element to
the new size. Alignment is what carries it, so the case now asserts the script's value survives, and
`WMPAlignmentTests.testAScriptedCoordinateReanchorsFromTheCanvasItWasAssignedAt` pins the half it
hands off to, including the un-aligned node that correctly stays put.

## W160 — the Plus! artwork looked low resolution on Retina

**Closed 2026-09-14.** Reported live as *"several of the plus skins have a low res look to the
grapics, plus hard boiled, plus hue shifter, plus slimline"*, and after the first fix landed, *"it
does not look better. can the lines be crisp?"* — which is the sentence that decided the
implementation.

`WMPSceneBuilder` passed `interpolation: .low` for every image, so a `.wmz`'s 1x artwork took a
bilinear 2x upscale on a Retina display. Not a property of these skins: their density is identical
to skins nobody complained about (`Plus! Hard Boiled` 190x253 art in a 190x253 subview,
`New Super Mario Bros` 582x435 in 582x435). Photo-real JPEG bodies simply do not survive bilinear
where flat cartoon art does.

**Neither CoreGraphics filter is acceptable.** `.low` and `.high` are byte-identical on this path
(measured at 2x on `Egg_Body_Normal.jpg`), and `.none` — which is what Classic and Winamp Modern
already do for their own 1x artwork — is crisp on pixel art and *blocky* on a photograph, which is
what the second report rejected. The resample therefore moved out of the draw:
`WMPImageStore.upscaledImage` runs a Lanczos upscale (vImage `kvImageHighQualityResampling`) plus a
3/16 luminance sharpen once per bitmap and caches it in the existing LRU, and the renderer blits it
1:1.

`WMPBitmapInterpolationPolicy.decision` gates it on three conditions — authored size, whole-number
device scale, pixel-grid-aligned destination — each added after a corpus sweep showed the version
without it moving artwork nothing was wrong with: **159 → 148 → 146 → 8** of 535 views at 1x.

**Verification.** Corpus sweep 527/535 byte-identical (the 8 are four at `maxdelta=1`, the
nondeterministic `Scooby-Doo_2/infoView`, and three genuine sharpenings with no geometry shift);
`swift test` 2254 tests, 0 failures; live before/after captures on all three reported skins. A 1x
render dump cannot see this defect at all — the device scale is 1 there and no draw qualifies.

Full account, including the two Core Image traps and the over-sharpened first kernel, in
`skills/wmp-skin-guide/reference/skins/plus-family.md` § *W160*.

## W161 — a finished intro animation buried the player it opened

**Closed 2026-09-14.** Reported live as *"the 2 windows_xp skins the eq does not work. I suspect
there may be other issues"*.

The equaliser was never the defect. Both `Windows_XP_Media_Center_Edition` archives open with
`introAnim()` assigning `shutter_open.gif` to a `zIndex="20"` `<SUBVIEW>` over the display and never
hide that subview again; `WMPImageAnimation` held the finished animation's last frame, which in
these files is an opaque blue plate at `29,32 176x135`. `eqBack` is `47,45 140x108` — entirely
inside it — so the panel opened, its ten sliders built and drew, and every pixel was covered. So
were the metadata, the `STATUS:` line, the elapsed readout and the seek arc.

**The skin's own markup is the argument for the rule**: the *closed* state is held by a separate
static child (`shutterStatic`) the same handler toggles, which only makes sense if the animation
leaves nothing behind. `WMPGIFTerminator` reads the GIF block stream for the final image block's own
size and the disposal method of the extension that introduced it; a **degenerate** final block (1x1,
on a larger canvas) that **disposes to background** means the animation ends drawing nothing, and
only `WMPRenderer` consults it — hit testing and coverage still read the sprite.

**Disposal alone is not the test**, and that is most of what this row measured. One-shot with a
full-size disposal-2 final frame matches **379 corpus files** including `ALXMorph`'s six-frame idle
logo; the degenerate final block matches **79 files across 33 archives**, almost all named
`shutter_open`, `shutter_close` or `intro_anim`. `Age_of_Mythology` settles it inside one skin —
`open_shutter.gif` carries the terminator and `close_shutter.gif` does not, ending on a full-size
80%-opaque closed shutter that has to persist. `Halo 2` is the null case: its `m_shutter_open.gif`
ends on a full-size frame that is entirely the key colour, so it was already invisible.

**Verification.** Corpus render sweep: 520 identical / 15 differing, **none of them from this
change** — a sweep draws at clock 0, before any animation has finished, so it proves only that
nothing else moved. The measurement is live: `screencapture` of the window before and after, with the
display restored, the equaliser panel visible, a band dragged to +14 and holding across later host
settles, and the shutter closing to its static plate and reopening. `WMPGIFTerminatorTests` pins the
walker, both halves of the discrimination, the endless-animation guard, the `Data`-slice index trap
and the end-to-end "the face shows again" render.

**No headless probe can see this class.** `WMP_RENDER_CLICK` reported the EQ opening with
`unrecognised=[]` and 12 widgets, and a `DRAG` on `eq1` reported
`value 1.273 -> 14 follows-pointer=yes` — the scene graph was correct throughout. Dossier:
`skills/wmp-skin-guide/reference/skins/windows-xp-media-center.md`.

## W162 — `player.status` was inert, so 69 archives painted a blank readout

**Closed 2026-09-14.** Opened by W161: the `STATUS:` line it uncovered was empty.

`player.status` answered `inert()` and the empty string in `WMPObjectModel`, was **absent entirely**
from `WMPObservablePropertyRegistry`, and the `status_onchange` argument bound `""`. Three
resolutions of one path and none of them answered — a skin could not reach it any way it tried.
All three now read `WMPHostSnapshot.statusText`: `Playing` / `Paused` / `Stopped`, and `Ready`
before anything is open, which is the same split `isEnabled(.play)` already makes.
`status_onchange` is additionally raised when the string itself changes, which is bounded by the
state transitions `playstatechange` already rides and so does not reopen W119's trap — that was
about the *rate*, a clock tick raising a status event 10 times a second.

**There is deliberately no `Buffering (n%)`** although WMP spells one: `bufferingProgress` is 0-100
with 100 meaning *full* and nothing outside the harness ever writes it, so a `< 100` test would
report every skin permanently buffering on the default `0`.

**Why the wording is free.** Of the corpus's **128 uses across 69 of the 180 archives, not one
compares it against a literal** — every one prints it, either straight into a readout or prepended
to the track name (`metadata.value = player.status; if (metadata.value != "") …`, the Alienware
family's idiom). No handler can branch on it, so no handler can be broken by it.

**Verification.** Corpus render sweep, baseline worktree at HEAD: **534 identical, 15 differing**,
of which `Scooby-Doo_2/infoView` is the harness's own `Math.random()` (proved by a curr-vs-curr
capture pair). The remaining **14 are all the same change** — a readout that painted nothing now
painting `Ready` in the skin's own font — checked by cropping every diff bbox and comparing side by
side: `9SeriesDefault`, `corona` (two views each), `Alpine7618_v09`, `Asimov_Radio`,
`Charlies_Angels_Full_Throttle`, `Classic`, `Compact`, `aoe`, `circle`, `pharaoh` (two),
`springflower`. The prediction beforehand was 7 — the archives with a markup binding — and the extra
7 are skins whose `onLoad` reaches a metadata updater.

Live: `Windows_XP_Media_Center_Edition` reads `Playing` and flips to `Paused` on the transport, and
`corona`'s green line now rotates `Playing → NullPlayer 20-minute sweep`, which is what WMP 9's own
skin does — `player.status` is literally the first entry in its rotating `MetaDataObject` list.

## W163 — a skin that names no `scriptFile` had no script at all

**Closed 2026-09-14.** Opened by *"colorchooser skin looks totaly broken from the UI"*.

`WMPSkinLoader` registered a program only from a `scriptFile` attribute. **Seven corpus archives
declare none** and ship exactly one `.js` whose basename is the skin definition's own:
`Colorchooser`, `Charlies_Angels_Full_Throttle`, `Cubist`, `cyberchannel`, `Kids`, `PowerToys` and
`Tomb Raider 2`. All seven call into that file from their handlers — `Colorchooser`'s `onLoad` ends
in `checkForContent();` and its three RGB sliders commit through `changeColor(…)`, both defined only
in `colorChooser.js` — so each one threw on the first statement of its first handler and came up
with none of its state applied.

The fallback is deliberately narrowed to **both** of its conditions: only when the skin declares no
`scriptFile` anywhere, and only the companion whose basename matches the `.wms`. A skin that names
its scripts has said what it wants loaded, and a stray `.js` beside a `.wms` is not something WMP
ever runs. `WMPPhase0Limits.scriptBytes` still bounds it.

**Verification.** `SCRIPTS programs=0 → programs=1` on exactly those seven archives and no others,
diffed across the whole corpus sweep. The visible one is `Charlies_Angels_Full_Throttle`, which went
from a blank speaker grille to its full player — transport, `EQ`/`PL`/`WEBLINKS`/`PREVIEW`/
`VISUALISER`/`GALLERY` buttons and a readout — because its `onLoad` builds the face. Pinned by
`WMPGraphTests.testASkinThatNamesNoScriptFileLoadsItsSameNamedCompanion` and
`…testTheCompanionScriptFallbackIsNarrowedToBothOfItsConditions`.

The command that enumerates the class, and the two ways it fails silently, are in
`skills/wmp-skin-guide/reference/loading.md` § *The script a skin never names*.

## W164 — a `<VIEW>` stretched background artwork to a size the artwork does not have

**Closed 2026-09-14.** Part of the same report.

`Colorchooser` declares `width="300" height="200"` over a 246x202 `colorBack.bmp`, and the root's
background was drawn into the whole canvas. Stretched by 1.22 its drawn box landed at x=87…299 while
`mainBackground` — the opaque white panel that belongs *inside* that box — stayed at the authored
77…241. The frame and its contents were visibly out of register, which is most of what "totally
broken" was. Root background artwork is now anchored at the origin at its own size.

**Scoped to a mismatch the markup states, not one a resize produced.** Where the authored size and
the artwork agree, a canvas the user or a script grew still stretches the background exactly as
before. **17 corpus views declare a literal `width`/`height` alongside a resolvable background
image and exactly 4 disagree with it**: `Colorchooser`, `Cubist` (508x189 art in a 508x350 view),
`Radio` (265x128 in 265x167) and `Tomb Raider 2` (343x351 in 543x551). The last three all author a
band or a plate rather than a full-window picture, so stretching was wrong on every one.

`Ice` is the counter-evidence this does **not** settle and was not asked to: its `videoView` is
about a `<BUTTON>` sized against a background image, which is the natural-size rule (W122), not the
root's own artwork.

**Verification.** Corpus sweep moved exactly those four images. Pinned by
`WMPPaintOrderAndColorTests.testAViewDrawsBackgroundArtworkAtItsOwnSizeWhenTheMarkupDisagrees` and
its mirror, `…testAViewWhoseArtworkMatchesItsAuthoredSizeStillStretchesWithTheCanvas`.

## W165 — a colour was read from the markup and nowhere else

**Closed 2026-09-14.** Part of the same report.

`WMPSceneBuilder.color` consulted only the authored attribute, so two of the three places a WMP
colour comes from answered nothing: a `wmpprop:<element>.<property>` mirror, and a value the script
assigned. `mirroredColor` now resolves all three in WMP's order — the script's write, the authored
attribute, then one hop through the named element (its own override first, then its markup). One
hop, like `mirroredVisibility`, and for the same reason: a mirror of a mirror is authored nowhere in
the corpus.

`Colorchooser` needs all three at once and is the **only archive in the corpus that binds a colour
with `wmpprop:`** — three attributes, measured over the installed corpus. Its caption takes
`foregroundColor="wmpprop:style.foregroundColor"` from an invisible `<TEXT id="style">` held purely
as a palette, so it was drawn in the unset-colour white on a white panel and the one affordance the
skin has was invisible; its transport strip takes `backgroundColor="wmpprop:mainBackground.background
Color"` and painted no fill at all; and its three sliders drive `mainBackground.backgroundColor`
from script, which nothing repainted.

**A write the colour parser cannot read is no answer, not black.** `theme.loadPreference` returns
WMP's `--` sentinel for a key that was never saved and skins assign it without checking, so an
unparseable override leaves the authored colour standing.

**Verification.** This is the half of the change with reach beyond the report, and it is the reach of
the mechanism rather than of a heuristic: the corpus sweep moved **8 further images, every one a
colour the skin's own script had always assigned and nothing painted** — `amped2`'s time readout to
its scheme colour `#d1d9e3`, `Thomas`'s and `holiday_skin`'s active-source label lighting up,
`Batman Begins`'s EQ bars, `springflower`'s readouts, `Plus! Professional`'s video backdrop, and
script-set playlist backdrops on `Halo 2`, `Rave-MP`, `LostPlanet`, `WoW` and `STALKER`. Every one
was checked by cropping its diff bbox. **No `RENDER-DUMP` count went down anywhere in the corpus**;
the plView rows gain one command each, which is the fill that was missing. Pinned by three tests in
`WMPPaintOrderAndColorTests`.

## W166 — a script-assigned `zIndex` was ignored, and on a windowed visualizer that punched a hole through the window

**Closed 2026-09-14.** Reported live, separately from the rest of the same session, as *"the window
has no backing when a track plays and it clicks through to the background"*.

`WMPSceneBuilder.nodeOrder` read `zIndex` from the markup only, so a handler that reorders the scene
reordered nothing. **Seven archives assign it from script — 58 assignments** across `Beck`,
`Cablemusic`, `Charlies_Angels_Full_Throttle`, `Colorchooser`, `Plus! Professional`, `Spider-man`
and `cyberchannel`.

On `Colorchooser` it reached the window itself. Its `checkForContent()` raises `viz.zIndex` from -5
to 5 to bring the visualizer out in front of the player body. With the node still sorted at its
authored -5, everything the skin painted after it — including `mainBackground`, the opaque white
panel the whole player sits on — counted as artwork *above* the surface, and `windowedEffectsRects`
punched it out of the overlay (W144). The view's own artwork keys white to transparent, so below the
surface there was nothing: a transparent, click-through region 164x130 through a borderless
`isOpaque = false` window, for as long as a track played. Stopped, the skin was correct.

**W144's rule is unchanged and `xsn_sports` is untouched** — what belongs in a windowed rect is
still whatever the skin painted *before* the effects node, and that skin paints `visMask`'s own
black there. The defect was never the punch; it was that the node the punch is measured from was in
the wrong place in the list.

`cerulean` is the counter-evidence to check beside this: `zIndex` is ordered **among siblings**, not
flat across the view, and that is unchanged — `paintOrder` still sorts a node's own children and
`behindOwnArtwork` still splits them at zero. Only where the number comes from moved.

**Verification.** Corpus sweep moved exactly one image, `Charlies_Angels_Full_Throttle`, which is one
of the seven; the other six swap `zIndex` on play state and the sweep runs stopped. Live:
`NULLPLAYER_PLAY` with `Colorchooser`, `screencapture` of the window before and after — the
visualizer drawn over an opaque white panel instead of over the desktop. Pinned by
`WMPPaintOrderAndColorTests.testAScriptAssignedZIndexReordersTheSceneAndKeepsTheWindowBacked`, which
asserts on the **split index** because that is the fact the punch is derived from, and by
`…testAScriptAssignedZIndexReordersOrdinarySiblings` so the rule is not read as an `<EFFECTS>`
special case.

**No headless probe saw this class**, and the reason is worth keeping: the sweep runs a stopped
player, and stopped is the one state in which this skin is correct. `WMP_RENDER_HOST=playing` is not
enough on its own either — it seeds the snapshot but the `zIndex` write arrives from
`playstatechange`, so the headless capture rendered the panel and the live window did not. The
instrument that settled it was `screencapture` of the running window with a track playing.

## W170 — `openstatechange` rode the play state, so pausing restarted playback

**Closed 2026-09-14.** Reported live as *"in hue pressing pause does not pause the stream and play is
not responsive at all"*, then, in the same session, *"stop does not stop"*.

`refreshHostState` raised both state events off one comparison —
`if previous?.state != snapshot.state { events += ["openstatechange", "playstatechange"] }` — so a
pause, a resume and a stop each told every open view that the **open** state had changed. It had
not: `player.openState` is derived from whether anything is open (`playlistCount > 0`), which a
transport gesture never touches.

**109 of the 180 installed archives author `OpenState_onchange`**, and three answer it by playing:
`Plus! HueShifter`, `Plus! Plasma Ball` and `Plus! SlimLine` share one handler whose `osMediaOpen`
arm is `UpdateMetadata(); Play();`, and `Play()` ends in `player.controls.play()`. The transaction
is dispatched 16 ms after the edge, which is exactly the gap in the log:

```
16:32:56.431  StreamingAudioPlayer: State changed from playing to paused
16:32:56.455  play(): Starting streaming playback via AudioStreaming (state: paused)
```

After a **stop** the same re-play found the player stopped, so it took the reload branch and
restarted the track from 0:00 — which is why "stop does not stop" and "play is not responsive" are
the same defect: playback never actually stopped, so there was nothing for play to resume.

**The fix** is `WMPMainWindowController.stateEdgeEvents`: `playstatechange` compares `state`,
`openstatechange` compares `openState` — the same `playlistCount > 0` derivation the object model
and `arguments(for:)` already use, so the edge and the `NewState` argument can never disagree. It
only ever *removes* raises; a track change never raised this event before either (state is unchanged
across one), and media opening and the queue emptying still do.

**Verification.** `swift test --filter WMP`: 382 tests, 0 failures, including
`WMPHostEventEdgeTests` — the pause/stop/resume edges, the open/close edges, and the agreement
between the edge and the argument. Live, `Plus! HueShifter` with a Plex track: pause logs
`State changed from playing to paused` and nothing follows; play resumes from the pause point; stop
logs `playing to stopped` with no reload. The other two archives share the handler and were not
separately driven.

**Why nothing here saw it, and it is the sharpest case on file.** The same session's corpus click
audit drove 284 decoded play/pause points across 149 skins in two host states and reported the
transport healthy — correctly. The defect is in what the engine raises *after* the click, and a
sweep seeds one host snapshot and never transitions, so the edge is never computed. Worse, the first
live pass used `NULLPLAYER_PLAY` with a local file and **cleared the skin**: on an already-loaded
local engine the spurious re-play is invisible, and only the streaming path turns it into a real
restart. Reproduce a transport report on the source the reporter uses.

## W180 — `Half-Life_2`'s shutter intro, closed as authored behaviour

Reported 2026-09-15 as "in half life the skin animation triggers the opening on load, i think it
should be closed and you click the open button to open it". **No code changed.**

The row said the thing to prove was not "it opens" but **"it settles"** — an intro that opens the
player and then hands its button over is the skin's own design, and the failure mode worth ruling
out was the scripted `view.timerInterval = 0` not taking, which would re-enter the sequence forever
and never enable the button. It settles. `WMP_RENDER_PROBE=mainView` at three settle values:

| `WMP_RENDER_SETTLE` | `topShutterSub` | `centerShutterSub` |
|---|---|---|
| 3 | `shutter_f02.png` | `shutter_static.png` |
| 11 | `shutter_f09.png` | `shutter_open.gif` |
| 20 | `shutter_f09.png` | `shutter_open.gif` |

It animates frame 2 → 9 and stops; 11s and 20s are byte-identical, so the timer is genuinely off and
nothing re-enters. `WMP_RENDER_CLICK 'mainView@201,55'` after settling reports
`hit=shutterButton#14 … handlers=1`, with `shutterButton.enabled=true` and `mainBackFrame.visible=true`
in the changed set — the frame-9 branch handing the button over — and the click steps the shutter
back to `shutter_f08.png` at `setViewTimerInterval value=100`. Opens on load, settles, button works,
exactly as `hl2_se.wms:17`/`:31` author it.

**What it produced instead.** Verifying it established that no render dump can see an animation's
*timing*, only its scene, which is what sent the next report to the running app — see **W182**, the
per-view animation clock, still open.

Original row:

| W180 | `Half-Life_2` plays its shutter-opening sequence on load — **probably authored, verify before fixing** | 1 skin, reported 2026-09-15 | Reported as "in half life the skin animation triggers the opening on load, i think it should be closed and you click the open button to open it". **The markup says WMP does this too.** `mainView` declares `timerInterval="1500" onTimer="toggleShutter()"` and authors `shutterButton` `enabled="false"` (`hl2_se.wms:17`, `:31`), and `toggleShutter()` (`hl2.js:120`) walks `shutter_out_open.gif` → `shutter_f01..f09.png` → `shutter_open.gif` with a sound per stage, then at frame 9 sets `view.timerInterval = 0`, `centerShutterSubStatic.visible = false`, `mainBackFrame.visible = true` and `shutterButton.enabled = true`. An intro that opens the player and *then* hands the button over is the skin's own design, so the row to prove is not "it opens" but **"it settles"**: if the scripted `view.timerInterval = 0` does not stop the view timer, or a scene rebuild re-enters the sequence, the shutter re-opens forever and the button never becomes clickable — which is what this report would look like from the outside, and is the shape of the animation defect already closed on 2026-09-08 (§ *Phase 7*). Reproduce with `WMP_SKIN=…/Half-Life_2.wmz`, watch whether `mainBackFrame` ever appears and whether the shutter button takes a click; close as authored behaviour if it does. |

---

## W181 — an unauthored `visible`/`enabled` read **false**, and a whole main face stayed inert

Reported 2026-09-15 as "the subwindow buttons on the main window face do not work" against
`Combat_Flight_Simulator_3`. Closed the same day.

`WMPObjectModel.readElement` answered `""` — falsy — for any standard property the markup never
authored and no script had written. `Combat_Flight_Simulator_3`'s markup declares `mainIntro`
without a `visible` attribute and its 5s view timer tests exactly that property, so `mainTimer()`
took the `!visible` branch on every tick, `hideIntro()` never ran, and the buttons `disableButtons()`
hides while the player is stopped never came back. The face was inert forever.

**The fix is one line**, beside the `alphaBlend` default in the same function: an unset `visible` or
`enabled` answers `true`, which is what WMP answers and what this engine's renderer already drew —
the two halves disagreed and only the script side was wrong. Authored values and script writes both
still win, because the read reaches the default only after `element.properties[name]` misses.

**Measured before it was written**, over the 184 installed archives — 399 script files decoded BOM-
first then positional UTF-16 then cp1252, breakdown 155 UTF-16-BOM / 146 cp1252 / 89 UTF-8 / 9
UTF-8-BOM, with `Need_for_Speed_Underground` and `SplinterCellWMPSkin` refusing their `.wms` as
always:

| Property | Reads | Reads of an element whose markup authors no such attribute |
|---|---|---|
| `.visible` | 513 across 67 archives | **81 across 21** |
| `.enabled` | 35 across 9 archives | **25 across 5** |

**Three measurements of reach, because the default-state sweep cannot see this one.** The full
183-skin corpus sweep against a baseline worktree at `7ce0adf6` is **byte-identical** in its
invariants once `loadms` timings and the hash-ordered `SCRIPT inline:` tallies are removed, and
546 of 547 images are identical — the one that differs is `Scooby-Doo_2/infoView`, the known
`randomPic()` nondeterminism. That is the correct result and not a null one: these reads happen on
timers and handlers, never at load. Driving the timers is what shows the change — a
`WMP_RENDER_SETTLE=6` pass over the 25 archives the scan flagged, baseline against current, moves
**exactly one line in 142**:

```
- RENDER-DUMP mainView: 584x321, 13 nodes,  7 commands, 2 hits, 2 widgets, 1 unresolved
+ RENDER-DUMP mainView: 584x321, 18 nodes, 11 commands, 6 hits, 4 widgets, 1 unresolved
```

and it is `Combat_Flight_Simulator_3`. The row's own evidence point flipped with it:
`WMP_RENDER_CLICK 'mainView@252,92'` with `WMP_RENDER_SETTLE=11` was `MISS` and now reads
`hit=wbuttonsInfo#45 → command=openView contentView`, with `mainIntro.visible=false` and
`wbuttons.visible=true` in the changed set.

**The trap in the corpus scan, recorded because the first pass fell into it.** Filtering out every
target the script also assigns somewhere — a reasonable-looking way to find reads that must precede
a write — removed `Combat_Flight_Simulator_3:mainIntro` itself, since `hideIntro()` assigns it. The
question is which runs *first*, and no static scan answers that. Count both populations and say
which is which: 37 element+skin pairs read an unauthored `.visible`, 28 of them also assigned.

Original row:

| W181 | An unauthored `visible`/`enabled` reads **false** from script, so `Combat_Flight_Simulator_3`'s whole main face stays hidden | 1 skin confirmed headlessly and live 2026-09-15; **unmeasured across the corpus**, and the property is read by every skin that scripts its own layout | Reported as *"the subwindow buttons on the main window face do not work"*. Not the buttons: `mainStartUp()` calls `disableButtons()`, which hides `wbuttons` (close, minimize, full mode, shutter, info, playlist, EQ), the seek dial, the volume dial and the pin-up button whenever the player is stopped, and only `hideIntro()` or playback brings them back. The 5s view timer runs and `mainTimer()` reads `mainIntro.visible` — an attribute the markup never authors — and `WMPObjectModel.readElement` answers `""` for any unset standard property (`SkinnedSurfaceChrome`-style defaults are held there for `alphaBlend` and the video flags only), so the handler takes the `!visible` branch and `hideIntro()` is never called. The face is inert forever. **Evidence**: `WMP_RENDER_CLICK 'mainView@252,92'` is `MISS` stopped and after `WMP_RENDER_SETTLE=11`; with `WMP_RENDER_HOST=playing` the same point resolves `hit=wbuttonsInfo → command=openView contentView`. WMP's own default for both `visible` and `enabled` is **true** — which is what the renderer already draws — so the fix is a default in `readElement`, and the reach number is a corpus scan of `\.visible`/`\.enabled` reads against the attributes the markup authors. **Measure before fixing**: this flips a value every scripted skin can read. |

---

## W182 — the animation clock belonged to the view, so a GIF assigned later started part way in

Reported 2026-09-15 as "why does the AlienMorph skin animation sometimes not fully run when first
opened — it runs what appears to be half of the animation". Closed the same day.

`WMPViewPresentation.animationEpoch` was set **once per view**, on the first scene containing any
animated GIF, and `animationClock` handed `now - epoch` to every GIF in that view for
`WMPImageAnimation.frameIndex(at:)` to index its own delay table. A skin animates by assigning a new
GIF to an element it already drew, so any animation that arrived after the first one was entered by
exactly the gap between them — and `cadence.endsAt`, measured from the same epoch, decided when the
repaint loop stopped.

`AlienMorph` walks into it because `mainView` is authored `timerInterval="1000"
onTimer="introStart()"` and `introStart()` → `toggleShutter()` is what assigns
`m_anim_shutter_open.gif`, a second after the view loads. So whether the intro played in full
depended on whether anything else had animated first — which is why it was intermittent rather than
broken.

**The fix is a clock per slot**, where a slot is `WMPRenderer.WMPAnimationSlot(stableID:resourcePath:)`
— the node **and** the resource. Node alone keeps the stale epoch across the script's assignment,
which is the defect; resource alone makes two elements drawing one GIF share a clock and restarts an
animation whenever a rebuild moves it between nodes. Together, the same picture in the same place
keeps running and anything else starts now, which is also what preserves W142's no-flicker property:
a scene rebuilt unchanged produces identical slots.

Three seams:

* `WMPRenderer.render` takes `slotClocks:` and falls back to the scene clock per image. **An empty
  table renders exactly as before**, which is what leaves every render dump and `WMP_RENDER_CLOCK`
  untouched — they name one clock for the whole scene and still get it.
* `WMPViewPresentation.animationSlotClocks(for:)` seeds a slot's epoch the first time it is drawn
  and drops slots the scene no longer has, so the table cannot grow across a session.
* `cadence.endsAt` still decides *whether* the scene ends — it is the half that knows about a
  marquee, which never does — and `animationsEnd(for:)` decides *when*, from each slot's own epoch.

**Measured live, before and after, by frame-differencing a `screencapture` series** (see
`reference/harness.md` § *A dump cannot see when a GIF was entered* — no headless instrument here
can see this class, and the scene was correct at every settle value throughout):

| Case | Before | After |
|---|---|---|
| `AlienMorph` cold open, pointer away | 9.80s | **9.81s** (unchanged, the control) |
| `AlienMorph` cold open, pointer on the button group | 8.69s | **9.86s** |
| `ALXMorph` shutter toggled 6s after launch | 2.04s | **8.49s** |
| `ALXMorph` shutter toggled 12s after launch | a single 110ms interval | **8.52s** |

The two `ALXMorph` rows are the proof, and it is that they now **agree with each other**: the
animation no longer depends on when the click happened. `WMP_ANIM_TRACE` reports `restarts=0` for 21
of 23 trace seconds afterwards, so the loop is still not restarting per rebuild.

**How it was found, and the reporting order that mattered.** The floor change landed first
(`asFastAsPossibleCentiseconds`, making the Alienware family's two shutters the same length) and the
reporter came back with "this fix made W182 worse". It had not: it removed W182's camouflage. While
`ALXMorph`'s close animation was 4.69s the view clock was almost always past the whole thing, so the
early return fired and the shutter snapped shut in one frame — a 100% truncation, which reads as
"it just closed". At 9.64s the clock lands *inside* the animation and it visibly starts from the
middle — an 80% truncation, which reads as broken. **A defect that is total can be invisible, and
making it partial is what exposed it.**

Original row:

| W182 | The animation clock is per **view**, not per image, so a GIF a skin assigns later starts part way through — and a one-shot is cut off at the same offset | **1 skin measured live 2026-09-15 across 8 runs; unmeasured across the corpus**, and every skin that assigns a `backgroundImage` GIF from script is a candidate — count them | Reported as "why does the AlienMorph skin animation sometimes not fully run when first opened, it runs what appears to be half of the animation". `WMPViewPresentation.animationEpoch` is set **once per view**, on the first scene containing any animated GIF (`WMPMainWindowController.swift:2201`), and `animationClock` then hands `now - epoch` to every GIF in that view for `WMPImageAnimation.frame(at:)` to index its own delay table. A GIF that enters the scene later is therefore entered by exactly the gap between the two, and `cadence.endsAt` is measured from the same epoch so the tail is lost as well. `AlienMorph` walks into it because its `mainView` is authored `timerInterval="1000" onTimer="introStart()"` and `introStart()` → `toggleShutter()` is what assigns `m_anim_shutter_open.gif` — one second *after* the view loads. **Measured in the running debug build** by frame-differencing the 282x282 shutter region of a `screencapture` series (the harness renders at an explicit clock and is blind to this whole class): pointer away from the window, motion runs 1.10s→10.91s, span **9.80s**, the GIF's full duration, reproduced 5/5; pointer parked on the player's button group, span **8.69s** — `m_set1_hov.gif` is 10 frames at 40ms with `loop=0`, so hovering starts the epoch ~1.1s early and the intro loses precisely that much at the head. A later toggle is worse and is the same defect: clicking `btnShutter` 4s after launch runs **1.73s** of the 8.46s close animation, and clicking it at 12s moves for a **single 110ms interval** — the scene renders once at a clock already past `endsAt` and snaps to the last frame. So "sometimes" is "whenever anything animated in that view first". **The fix is an epoch per image slot rather than per view**; before taking it, count the archives that assign a GIF to `backgroundImage` from script — the W128 scan shape in `reference/harness.md` § *Counting a tag across the corpus* is the one to copy, because the write is as often in an inline handler as in a program. Reproduce with the recipe in `reference/skins/alienmorph.md` § *How to drive it*. |

## W213 — a visualizer that owned every click, stood on nothing, and grew its own window

Reported 2026-09-17 against `circle`, in three messages: *"the circle skin has multiple issues, it
cannt be dragged and looks to be missing parts of the UI. also the vizulization opens below it"*,
then *"it is still missing hte backing on the volume and the vizulization still pops under it"*,
then *"the only thing fixed was the drag"*. Four independent defects; the skin dossier is
[`skills/wmp-skin-guide/reference/skins/circle.md`](../../skills/wmp-skin-guide/reference/skins/circle.md).

**None of the four is a drawing defect and no render dump shows any of them.** The scene `circle`
builds was correct in every capture throughout.

| # | Defect | Cause | Fix |
|---|---|---|---|
| 1 | The window could not be dragged anywhere | The `<EFFECTS>` hit covered its whole rect, and that rect is the entire player, so every press answered `visEffects` and never reached `beginWindowDrag` | `WMPHitCoverageBuilder.surfaceCoverage` — a hosted surface is reachable only where the skin has not painted over it, honouring each command's inherited container shapes |
| 2 | "the visualization opens below it" — the window opened 63 px too tall with a bar spectrum in the extra | `WindowManager.tightenClassicCenterStackIfNeeded` is Classic's stack repair, `isRunningModernUI` answers false for the WMP controller, and it grew the borderless skin window to `Skin.mainWindowSize.height` from `windowDidFinishDragging` | Gated on `isRunningWMPUI`. Two smaller gates ride with it: a stored size is read and written only for a view that declares `resizAble`, and `renderCurrentSize` lays a fixed view out at its authored canvas |
| 3 | "missing the backing" — the window had holes in it that showed the desktop | `WMPEffectsGround` was granted only where an **ancestor** states a shape; `vMain` states none, so the rect took no ground and every pixel the artwork keys away was transparent | The ground fills the rect where no shape is in scope, permitted by a `clippingColor` on a full-canvas child — the signal that keeps `Plus! Plasma Ball/BubbleSkin`, which names no matte |
| 4 | The track length never drew | `<DURATIONTEXT>` was not an element kind: no host value, no glyphs, and a `<TEXT>` is sized by its glyphs, so the node was dropped as unresolved | A kind bound to `player.currentMedia.durationString`, right-aligned by default |
| 5 | *"when i streched the window the visulization popped out and stretched bu the app didnt"* and *"the volume doesnt seem to work"* — **one defect, not two** | `configureWindow` set `window.minSize` to `unskinnedSize` (440x170) and nothing moved it again, so every `.wmz` window smaller than that carried a floor four times its own size. AppKit enforces `minSize` **after** the delegate answers, so refusing in `windowWillResize` cannot help: the first edge drag snapped the 192x82 player to 440x170 with the scene still 192x82 | `applyWindowSizeLimits` tracks the presented scene — floor from `resizeLimits`, both ends pinned for a view that is not resizable — and `presentUnskinned` gives the unskinned floor back. `windowWillResize` refuses a fixed view's resize as well, so the stretch never starts |

**Why (5) is one defect and reads as two.** The artwork is rasterized at the *scene's* size and sits
in the window's corner, while everything laid out from `bounds / canvasSize` follows the *window* —
the hosted surfaces, and `WMPMainView.skinPoint(from:sceneSize:)`, **which is where every click is
resolved**. So the visualization stretched while the skin did not, and simultaneously every control
moved out from under the pointer. The volume was simply the control that got tried.

**Measured.** `swift test` 2363 tests / 0 failures. Corpus render sweep over 184 archives: **552 of
553 images identical**, the one being `circle`'s own ground; plus the two `<DURATIONTEXT>` readouts
(`circle`, `pharaoh`) and `Scooby-Doo_2`'s documented nondeterministic `randomPic()`.
`WMP_RENDER_OCCLUDED` corpus-wide: the `rect-only` set is **byte-identical to the baseline** — no
control lost anywhere — with 20 surfaces tightening.

**What this row is worth keeping for is the two wrong answers it produced first.**

- **A clean corpus sweep blessed a change that deleted a readout.** Confining the surface to
  `visfield.bmp`'s keep region — reading a full-canvas sibling's `clippingColor` as the window's
  outline — measured perfectly: 550 of 553 images identical, `rect-only` unchanged, one `shape=`
  population change and an `offshape=0` no-op. It is wrong, because `circle`'s track-number panels
  cycle ten `num*.bmp` that are **entirely** key colours, so the digit is whatever the surface
  paints behind it. A sweep renders scenes; it cannot see what a *surface* draws.
- **Two reports, one cause — and the second report is what located it.** "The volume doesn't work"
  and "the visualization stretched but the app didn't" were filed as separate observations and are
  the same window state; reading them together is what pointed at `bounds` rather than at the
  slider. Measured after the fix with the visualizer stopped, which gives the volume's own rect a
  **zero** noise floor: a drag to the arc's low end moves 758 px in it and back moves 2,437.
- **A plausible cause that reproduces the symptom is not the cause.** The frame store did hold
  `192x145` for a 192x82 player, and a fixed view taking a size from outside itself is a real
  defect — it was found, fixed, and was **not** why the window grew. Clearing the record still gave
  192x82 at launch and 192x145 on the first click. `WMP_SIZE_TRACE=1` (`reference/harness.md`)
  printed the backtrace and named `tightenClassicCenterStackIfNeeded` on its first run.

## W209, W210, W212 — the borrowed window frame, and what empties Tier 1h

Three rows closed 2026-09-17, in that order, each opened by the one before it. All three are about
the pixels a donor lends a NullPlayer-owned window (`WMPHostedFrameTemplate`), and in all three
**the donor's own view was correct throughout** — the asymmetry is the clue. The case studies are
[`back-to-the-future-trilogy.md`](../../skills/wmp-skin-guide/reference/skins/back-to-the-future-trilogy.md)
and [`alienware-invader.md`](../../skills/wmp-skin-guide/reference/skins/alienware-invader.md); the
rules landed in `skills/wmp-skin-guide/SKILL.md` § *Every NullPlayer window in WMP mode is the
skin's or is themed*.

**W209 — a ring assembled from selected pieces is not the frame the skin drew.** The borrowed frame
is now the donor view **drawn whole** with the skin's own content subtracted, instead of a ring
built from pieces chosen by role. **88 rings of 185 archives draw a frame (was 67) and nothing is
refused as open (was 21).**

**W210 — a donor's own furniture is told from its border by the order it paints them.** Opened by
W209 against `Alienware Invader`, whose left border is a *furnished* column: its own hole starts
right of the rack, `reclaimingSideRacks` handed that 134pt strip to our content, and the frame
paints over content — so the rack landed on the library's rows. Position cannot separate a rail from
a rack: both sit in the reclaimed strip, touch no edge, and are more than half inside the widened
hole, which is why measuring the furniture test against the reclaimed rect took `Ice`'s right rail
with it. **Paint order can, because it is the donor's own answer to the same question**: a piece
drawn *before* the client subview is behind the skin's list and behind ours; a piece drawn *after*
it is over both. `Ice` paints its rail under a `zIndex=50` list, this skin paints its racks over a
list with no `zIndex`. **Read it off `scene.commands`, the render order — never off `zIndex`, which
is sibling-ordered.** The skin's own `plView` was fixed in the same change for a different reason: a
view laid out at a size it was never authored at has already been resized, so its `onResize` now
runs on both the player and auxiliary open paths before anyone sees it.

**W212 — the three white blocks and the grey column.** Three rules landed, and the first is not
about the frame at all:

1. **A `wmpprop:` read of another element's geometry answers where that element was *laid out*.**
   `plView` hangs each side column off a centred piece and states the tile beside it as
   `top="wmpprop:plLeftCenter.top"`. Centring computes a coordinate the markup does not carry, so
   the static resolver — reading the target's *authored* attribute — answered 0 and both tiles
   painted over the corner pieces, putting the white those bitmaps carry for the skin's own list to
   cover into the caption band. WMP answers that read from the live object model and the skin's own
   window does the same through the script runtime; the frame build has no runtime, which is why the
   one surface without one was the one that was wrong. It now answers from the target's resolved
   frame, or from the coordinate its centring computes when the paint-order walk has not reached it.
2. **A rack is reclaimed only as far as the donor leaves it *unpainted*** (`clearOfTheDonorsOwnRail`)
   — the reclaim stops where the donor paints something that is neither transparent nor its interior
   fill. **Excluding the interior fill is the rule, not a detail**: `f_right_tile` is 96px wide with
   73 of them opaque white, and alpha alone reads that as a 96pt border.
3. **The span repair is reachable under the whole-view render**, with three guards: furniture is
   classified on the first pass (or a stretched rack reaches the bottom edge and the edge exemption
   readmits it), only the axis that came out bare is spanned (or the top tile's white lands over both
   rails), and the repair is refused if the window's content rect moves — which is what `KungFuChaos`
   and `The_Last_Samurai` do.

**Measured.** Corpus at 357x238 over 185 archives: **4 of 167 frame lines move, every one an
improvement** — `Alienware Invader` (gaps 0.201 → 0.000), `T3-Skynet` (caption band and bottom bar
close, `whole=no → yes`), `Frostbite` (bottom 0.235 → 0.134), `livin_it_skate` (content off its
opaque button rail). `Ice`, `Star Wars`, `Halo 2` and `Back to the Future Trilogy` untouched. The
553-image render sweep is 552 identical and 1 differing (`Scooby-Doo_2`'s documented random picture)
with no `RENDER-DUMP`, `FINDING`, `COMPAT` or `BITMAPS` line changed — which is what says a builder
change moves nothing that already had a runtime. Verified live on PeppyMeter, waveform and Flow with
a track playing, and on `Ice` and `anemone`.

**What these three rows are worth keeping for.** A `HOSTED-FRAME` line alone measured clean twice
while the window was visibly wrong, and W212's `gaps=` read 0.000 on all four edges in the same
state — **the white was not a hole, it was the donor's border bitmaps carrying its interior colour
baked in as opaque white.** Three fixes were built, measured and reverted before the three rules
above. Verify a borrowed-frame row by driving the app and capturing the live window.


---

## W228 — the rail that was only open on the tallest window, 2026-09-18

Reported as *"alien invader media library window draws broken. the other nullplayer windows draw
ok"*. The dossier is
[`skills/wmp-skin-guide/reference/skins/alienware-invader.md`](../../skills/wmp-skin-guide/reference/skins/alienware-invader.md)
§ *W228*; the durable rule is in `SKILL.md` beside W212's, which this row is the missing half of.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W228 | The span repair that closes a script-sized rail is gated on a **fraction** of the edge, so the same bare run is repaired on a short window and left open on a tall one | **1 archive of 185** moves at 710x810 (`Alienware Invader`), 0 at 550x464; the shape is every ring whose rails are sized in `onResize` — this is the one the corpus has | **Closed.** `Alienware Invader` sizes both rails in `onPlResize()`, which the frame build never runs, so the ring comes out **107pt** short down each side at every size. That is 0.231 of a 464pt-tall window and trips `ringEdgeGapLimit`; it is 0.132 of the library browser's 810 and does not — and the library is the only hosted window that opens taller than 107 / 0.15 = 713pt. `edgeCameOutBare` now takes either test, the fraction **or** `ringEdgeGapPointLimit` = 40pt along that edge. Forty is in the same empty middle 0.15 sits in: at 710x810 the rings that close run 0 to 24.3pt and the ones with a piece missing measure 49.7 (`Half-Life_2`), 85.2 (`Combat_Flight_Simulator_3`) and 106.9 (this skin). Corpus at 710x810: **one line moves**, `gaps 0.132 → 0.000`, with `content=99,34 588x740` and every inset byte-identical; at 550x464 nothing moves — the only line the point limit newly reaches is `Half-Life_2` at 0.091/50pt and its repair is rejected. The repair's own guards are what make the wider gate cheap: it lands only if it closes the gap *and* leaves the content rect where the first pass put it. Verified live on the library at 746x931: zero bare pixels on all four edges, against `y=1288..1501` left 198px / right 46px fully transparent before. Pinned by `Tests/NullPlayerAppTests/WMPHostedRingSpanTests.swift` |

**The process note worth keeping: a `gaps=` fraction is the frame's defect divided by the window's
size.** W219-W222 established that a defect appearing on *every* hosted window is a property of the
frame and one window differing is a property of that window's own layout. This row is the exception
that completes the rule — one window differed and the frame was still the cause, because the
*measurement* the gate read scales with the window. Read the run back into points
(`gaps[1] × height`) before concluding anything about the window it showed up on.

## W225 — the bracket a skin wraps around its own resize

**Closed 2026-09-18.** Accepted live on `Compact` by the reporter, driving the grip with
`WMP_RESIZE_TRACE=1`: *"that fixed it"*.

Reported as *"when you stretch compact skin it breaks the drawers and the main body will absorb them
and also not allow them to close"*, with a second round of *"the drawer and resizing is totally
broken in every way"* against the first fix. W193 made `view.size(corner)` run the drag; this row is
what the skin does *around* the call.

**WMP's `view.size` does not return until the button comes up**, and the corpus's grips are written
against exactly that — 235 calls in 88 of the 185 archives, every one of them `onMouseDown`.
`Compact`'s `DoSize()` pins `playlistDrawer` to `right` and `settingsDrawer` to `bottom` so both ride
the window's corner, calls it, and unpins them. Nothing here can block, so the pin and the unpin both
landed before the first pixel moved: the drawers held their absolute positions while `playerView`
(`stretch`) grew over them. Measured at 900 wide, `WMP_RENDER_PROBE=all` puts the playlist tab at
`403,140` — under the body, where no click reaches it, which is both halves of the report.

**Three claims, and the report needed all three.**

1. **The mutation count is the seam.** `WMPObjectModel.resizeCallMutationIndex` records where the
   call fell; `WMPScriptRuntime` holds the tail in `deferredResizeMutations` and
   `resumeAfterWindowResize` replays it against the size the window finished at. Gated on
   `animatesTweens` for the same reason a tween is (W194) — that is the caller promising it is a
   window, and only a window runs a drag — so a render dump, the corpus census and the windowless
   dispatcher still run the handler straight through and **every measurement taken against them
   holds**. A grip that starts no drag (button already up, view not resizable) resumes at once, so a
   bracket can never be stranded half-applied.
2. **The tail is the last word on the release, not the first.** Raised at the top of `mouseUp`, it
   fell straight through into the ordinary control path, whose `mouseup`/`click` dispatch calls
   `presentation.scriptTask?.cancel()`. The unpin lost that race: `playerView` stayed pinned
   `left`/`top` while both drawers stayed pinned to the corner, for the rest of the session — a
   player drawn small in the top-left with its drawers stranded at the window's edges. Raised from a
   `defer`. The grip authors no `onClick`, so what it supersedes is a binding-only pass.
3. **Assigning an alignment freezes the element where it is drawn — and the extent half of that must
   stay out of the geometry overrides.** WMP re-measures the margins at the write, so the unpin must
   not teleport the drawer back to its authored `left`; without this the drawer jumped 478 px back
   into the middle of a stretched player. But `WMPSceneBuilder.ownAuthoredSize` reads the geometry
   overrides and **is what every child's own alignment delta is measured from**. Written there,
   `SetAlignment(true)` made `playerView`'s authored 422 read as the 754 it had been dragged to, and
   its whole chrome — tiles, corners, transport strip — saw a zero delta and collapsed back to the
   authored arrangement inside a 754-wide frame, while both drawers sat correctly at the edges. That
   is the second report, and it is the one the *live* trace could not name: every number in
   `[wmp/resize]` was correct while the picture was wrong. The origin half stays an ordinary
   script-assigned coordinate; the extent half is `WMPSceneOverrides.scriptAlignmentExtent`,
   consulted only by the `stretch` case.

**Blast radius, measured rather than cited.** A decoded scan of all 185 installed archives for a
script *assignment* to `horizontalAlignment`/`verticalAlignment` finds **one**: `Compact`. So claim 3
can move nothing else in the corpus, which is why this closed on that scan plus the skin's own
headless invariants (`33 nodes, 33 commands, 14 hits, 3 widgets, 4 unresolved`; `viewSize=601x378`
and `422x480`) rather than on a full render sweep.

**Why no headless probe found it.** `WMP_RENDER_CLICK` raises `onClick` and every grip is
`onMouseDown`; the builder takes its canvas from the overrides, so a capture agrees with the skin
whether or not the window would ever have moved. `WMP_RESIZE_TRACE=1` was added for it — the pair to
read is `release script=true` followed by a `resume`. **And `bottomright` drags both axes**: two
rounds of this were spent on a replay that moved only the width and therefore never reproduced the
bottom drawer's half.

**Still open from the same report:** the window-edge band runs no bracket at all. This engine lets
the user drag a borderless `.wmz` window's edge; WMP has no such affordance, so no skin anticipates
it and `DoSize()`'s pin never runs on that path. Stretching `Compact` by the edge leaves the drawers
behind exactly as the pre-W225 grip did.

---

## W193 — a skin's own resize grip, the only resize a `.wmz` window has

**Closed 2026-09-17.** `view.size(corner)` now runs the drag. Accepted live on `Compact`: press the
20x20 grip at scene `385,340` and the window follows the pointer from its bottom-right corner.

`onMouseDown="view.size('bottomright')"` is the corpus's standard grip — **235 calls in 88 of the 185
installed archives** — and a `.wmz` window is borderless, so in WMP it is the only resize the window
has. Inert, the user reached for the macOS window edge instead, which skips whatever the skin does
*around* its own resize: `Compact`'s `DoSize()` pins both drawers to their edges for the duration and
unpins them after, and a window widened any other way leaves the drawer behind.

**The implementation is smaller than the row expected, because W192 had already landed.** No modal
loop: `WMPObjectModel` posts `sizeWindow` with the corner as its value, and
`WMPMainView.beginScriptResize(corner:)` arms the **same** borderless edge drag the window's own
6pt resize band runs — so the clamp against the view's `minWidth`/`maxWidth`, the anchored edge and
the relayout are one implementation rather than two. Corners are matched as substrings:
`bottomright` (86 archives), `topright` (4), `right` (3), `bottom`/`bottomleft`/`left`/`topleft`
(2 each); `Revert` is the only skin authoring all seven.

Two gates, and the second is the one that is not obvious:

- **`scene.isResizable`**, the permission the edge band already asks for. Measured over the installed
  corpus: all 88 archives that call `view.size` author `resizAble="true"`, so it costs them nothing
  and stops a view with no authored maximum from being dragged open without one.
- **The left button must still be down.** The call arrives from an *asynchronous* script
  transaction, so a quick click's command can land after the release; arming the drag then would
  resize the window on whatever the user pressed next.

`WMPMainView.mouseUp` no longer returns early while a target is captured. An edge-band drag starts on
bare artwork and has nothing to release, but a grip is a real element — returning there would leave
it drawn pressed for good and skip its `onMouseUp`/`onClick`.

**What it could not reproduce, and why the row was closed anyway.** In WMP `view.size` *blocks* until
the drag ends, so `DoSize()`'s unpin runs afterwards. Here a script transaction completes before its
host commands are applied, so both brackets have landed by the time the first pixel moves. The drag
is right; the bracketing is early, and no arrangement of this pipeline changes that. Recorded in
`reference/skins/compact.md` § *Still open*.

**The harness could not see this row at all**, which is the process note worth keeping:
`WMP_RENDER_CLICK` raises `onClick` and only `onClick`, and every grip in the corpus is an
`onMouseDown`, so the probe reports `handlers=0` — identical to an inert control. It was closed
against the running debug build. Noted on the flag's own row in `reference/harness.md`.

Original row:

| W193 | `view.size(corner)` is unimplemented, so a skin's own resize grip is dead | **88 of 185 archives, 235 calls** (decoded `.wms`+`.js` scan, 2026-09-16) — `Revert` ×7, `The Unit` ×6, `QuickSilver` ×5, the whole Alienware/ALX family, `Halo 2`, `Star Wars`, `xsn_sports`, `Tomb Raider 2`, the Plus! skins, `Compact` | Found while closing W184-W192 (`reference/skins/compact.md`), not from a report of its own — though it is what makes the *stretch* half of that report behave oddly. `onMouseDown="view.size('bottomright')"` is the corpus's standard grip and **a `.wmz` window has no OS frame**, so in WMP it is the only resize the window has. Here it is inert and the user drags the macOS window edge instead, which skips whatever the skin does *around* its own resize: `Compact`'s `DoSize()` pins both drawers to their edges for the duration and unpins them after, and without that a widened window leaves the drawer behind. The implementation is a modal drag loop in `WMPMainWindowController` driven from a host command, honouring the view's `minWidth`/`maxWidth` — and with W192 landed, the alignment dance the skins wrap around the call already works. Corners authored: `bottomright` overwhelmingly, plus `topleft` (`Revert`), `topright` (`The Unit`) and `right` (`Alienware Invader`). |

## W219-W222 — what `TheUnit` lends a NullPlayer window, 2026-09-17

**Four defects from one report, opened and closed the same day, and every one of them in the frame a
skin *lends* rather than in anything it draws for itself** — every `TheUnit` view rendered correctly
throughout. Reported as *"theunit skin has broken nullplayer windows similar to past ones"*, then
*"its not fixed. every window has major defects and they vary from window to window"*, then *"the
issue is the right top corner"* / *"every window"*. The skin dossier is
[`skills/wmp-skin-guide/reference/skins/the-unit.md`](../../skills/wmp-skin-guide/reference/skins/the-unit.md);
the durable rules are in `SKILL.md` § *Every NullPlayer window in WMP mode wears the skin*.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W219 | The rack reclaim hands our content the donor's **own rail**, and the rectangular cut then erases it — no left bezel on any hosted window | **7 skins of 185** move at 550x464 (`TheUnit` ×2, `livin_it_skate`, `Blinx`, `Crimson_Skies`, `KungFuChaos`, `The_Sentinel_v.1.0`, `WWC`); the two shapes behind it are corpus-wide | **Closed.** `clearOfTheDonorsOwnRail` made two assumptions this donor breaks at once. Its run measured **in from the window's edge** — `left_stretch.png` is 37px wide with its outer 30 the transparency key and the rail in the inner 7, so the run is starved by 30 bare columns and answers zero; it now skips the bare lead-in, which is a no-op wherever a border does reach the edge. And it **declined to measure at all** when the hole carried no dominant fill, which is the reclaim at its most dangerous rather than its safest: a `<WMPVIDEO>` client subview has no fill, because its contents are ours and are subtracted, so the hole renders 97% transparent. Excluding nothing counts every opaque pixel in the strip as border and can only make the reclaim smaller. `Star Wars`, `STALKER`, `WoW` and `Halloween` — the racks the reclaim exists for — are byte-identical |
| W220 | A borrowed frame that arrives after the first layout pass is only **repainted**, so a subview framed for the old hole covers the ring — Visualizations showed no frame at all | **3 of the 10 hosted windows host a subview** (`ProjectMView`'s GL view, `AudioAnalysisView`'s SwiftUI host, `SpectrumView`'s); the notification reaches all 10 | **Closed.** The ring is derived asynchronously for the window's own size and lands after the view has laid out against the classic fallback metrics; `hostedSurfaceStyleDidChange` did nothing but `needsDisplay = true`. All nine hosted views now mark the layout dirty there and `ProjectMView` re-frames its GL view explicitly. **No probe can see this class** — the `HOSTED-FRAME` line, the frame dump and the artwork were all correct while the window was wrong; it was found by driving every hosted window and capturing each one alone |
| W221 | `hostedGroundRect` returns the artwork's **top-left** rect to three views that fill it in AppKit's **bottom-left** space, mirroring the hole vertically | **3 windows** (cava, `flow`, PeppyMeter) × every ring donor whose caption and bottom border differ | **Closed.** Latent for as long as every donor was roughly even top and bottom; `TheUnit` lends a 5pt caption over a 60pt bottom bar and all three grounds landed 55pt low — the top of each hole left transparent with the desktop showing through and the ground running out under the bottom bar. The hole now crosses as **insets** (`artwork.scaled(to:).metrics`), which is orientation-free. The same rect is used correctly elsewhere in already-flipped contexts (Playlist, EQ, the library, `drawSpectrumFamilyWindow`), so the fix is at the one call site that crosses spaces, not at the rect |
| W222 | A **resize grip's backing** is subtracted as a control's backing, taking the donor's top-right corner off every hosted window | **9 skins of 185** at 550x464 (`Halo 2`, `Ice`, `Official_Xbox_MP7`, `Official_Xbox_XP`, `XBOX`, `WWC`, `TheUnit` ×2, `Plus! Pulsar`), against W193's **235 `view.size(corner)` calls in 88 archives** | **Closed.** Subtraction rule 4 — a subview whose `backgroundImage` is also a control child's `image` is that control's backing and goes with it — is right for a glyph painted twice (`Back to the Future Trilogy`) and wrong for corner artwork authored as a button because that is the only node a `.wmz` can hang a mouse handler on. `isWindowGeometryGrip` exempts a control whose handlers reach `view.size`/`view.dragMove` and never touch `player.`: the backing stays, the control walk still drops the button, and our window keeps its own resize. Every one of the 9 changed lines is a `gaps` value **falling** — bare edge becoming artwork — with no content rect moving except `Plus! Pulsar`, whose donor is larger than the window (`content=-191.111,38` before and after) and whose crop therefore moved; that is a pre-existing defect and is not this one |

**The process note worth keeping: "every window has it" is a fact about the *frame*.** Three of these
four are properties of the borrowed frame and appear identically on every hosted window; W220 was one
window and was a property of that window's own layout. The first round of this report fixed W219
alone, verified it on two windows, and reported it fixed — the reporter's *"you did not check them"*
is what a per-window sweep would have preempted. Drive every hosted window, capture each one **alone**
(park it clear of the others: a `-R` capture picks up what is behind it, and a capture by window id
silently returns a full-screen image for a window that is off-screen), and sort the defects by whether
they vary window to window before theorising about any of them.

## W223-W224 — a script-driven pane, and the repaints behind it, 2026-09-17

Both were reported against `claw` ("the playlist does not display properly… the button doesn't
properly display it", then "it's mechanically working… it displays then goes black and then
displays"), and neither is visible in any headless probe: the pane switch itself is correct in
`WMP_RENDER_CLICK` (`pl.visible=true`, `2 widgets[playlist×1 text×1]`) and always was. Found with
`WMP_WIDGET_TRACE=1`, added for them — see `reference/harness.md`.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W223 | An **artwork repaint presents the pane state a script transaction has already replaced**, so a pane opens, is covered by the one it replaced, and comes back ~300 ms later | Every skin whose pane switch is a script write and whose button has a hover/down image — `claw` is the report; the corpus's pane switches are script writes almost without exception | `renderInteraction` read `presentation.sceneOverrides` **before** its task and presented whatever came back. Measured on the running app: `946.471 present src=transaction widgets=[playlist:6]` (the click opens the list) → `946.483 present src=interaction widgets=[effects:4]` (the mouse-up repaint, built on `pl.visible=false`: the list is dropped and a fresh `WMPEffectsSurfaceView` is created in its place, which is the **black** — an empty GL surface until its first frame) → `946.785 present src=transaction widgets=[playlist:6]` (the next transaction brings it back). **Closed 2026-09-17.** The overrides are read per attempt and re-checked after the render; a transaction that landed in between owns the pane and the repaint rebuilds against what it wrote, up to three attempts. **Giving up is safe rather than a compromise**: `state` is stored on `presentation.interactionState` before the task and every other build path passes it, so the down/hover image is drawn by whichever present lands next. Verified live: three clicks, three pane switches, no `interaction` present contradicting a `transaction`. |
| W224 | **A repaint of the same structure did all the work of a new scene**, including a full redraw of every hosted surface, at the animation loop's rate | Every skin with anything moving in it; `claw` with its list open and **no** visualizer still presents 11.8x/s off one scrolling `<TEXT>` | The animation loop re-renders `presentation.activeScene` — the *same* scene — so each frame is a new picture and nothing else, but `present` rebuilt the hit tester, re-synced the widgets, reset the tooltips, invalidated the cursor rects, rebuilt the accessibility tree and, through `synchronizeWidgetViews`'s `refreshHostState`, redrew the whole playlist: **106 list redraws in 9 s with the list unchanged**. **Closed 2026-09-17.** A present whose `hits` **and** `widgets` both equal the last one's skips all of it (`structure=same` on the trace line), and `WMPPlaylistSurfaceView.update` marks itself dirty only when the rows, the play marker, the highlight or the scroll position moved. `overlayView.frame` and the widget frames were already re-set in `layout()`, which AppKit runs on any bounds change, so nothing is left stale by the skip. **Two controls, because a guard that is simply stuck measures identically to one that works**: a pane switch is still one `structure=new` present with one `drop`/`create` pair, and skipping to the next track of the 3-track cue row produced exactly one `playlist draw` with `selected=` 0 → 1. After: 114 presents in 9 s, all `structure=same`, **0** playlist redraws. |

## W194 — a tween that runs for the duration it was given, 2026-09-18

Reported on 2026-09-16 against `Compact`'s drawers as *"its not a smooth opening"*. For four phases
`moveTo`/`resizeTo`/`alphaBlendTo` landed their endpoint at the handler boundary (W38) and raised
`onEndMove` in the same transaction (W55), so a 1,000 ms slide took one frame and **nothing in the
corpus ever animated**.

**Closed 2026-09-18.** The shape is a split, and it is what made the row safe to take: **a tween
animates only where something is drawing frames, decided per transaction.**
`WMPScriptRuntime.transact(animatesTweens:)` is a caller promising a clock, and only a window has
one — `WMPMainWindowController` passes it on the click and view-timer paths and nowhere else. A
render dump, the corpus census and the windowless dispatcher (W89) get exactly the behaviour they had
before, so **the settled state is identical either way and not one headless measurement on this
subsystem moved**. With a clock, `WMPObjectModel.tweenGroup` emits a `WMPScriptTween` and writes
nothing; the runtime holds the live set per view scope and `startTweenLoop` drives
`WMPScriptRuntime.tweenFrame` at 30 fps until no frames are owed. A frame is a **real transaction** —
the interpolated value goes through the object model, becomes a mutation and therefore a scene
override — so the element reads where it *is* mid-slide, which is W112 preserved rather than
re-litigated. The mechanism is written up in `reference/object-model.md` § *Tweens*.

**The callback was the risk and it is where the visible behaviour changed.** `onEndMove` moved from
end-of-handler to end-of-tween, which changes when 36 views chain their next step: `Compact` shrinks
its own window inside `Playlist_OnEndMove`, so the window now shrinks a beat after the drawer starts
closing — what WMP does, and the reason the row warned about it. Load, resize and close deliberately
stay instant: an `onLoad` sequence chained through `onEndMove` (`Alienware Invader`'s intro, the
drawer template's 36 views) would otherwise present its pre-tween state and complete a beat later.

**Three cases still arrive instantly under a clock**, each because a frame would be a guess: a
duration of zero (never a tween — `movePlayButton()` reads it back), a channel already at its
destination (its completion is raised at once, or a sequence chained off a no-op move stalls), and a
channel whose current value the model does not hold — which is why `alphaBlendTo` on an **unauthored**
`alphaBlend` arrives rather than fading, keeping the Alienware/ALX `m_anim_*` subtrees as they were.

**The process note worth keeping: no probe on this subsystem can see this row.** `WMP_RENDER_CLOCK`
pins the GIF clock and a tween is not on it, and the headless paths are the ones deliberately left
instant — so a capture at any clock value cannot tell a skin that slides from one that jumps. It was
closed against the running debug build, driven by the reporter across `Compact`, `xsn_sports`,
`corona`, `Cablemusic` and the Alienware family: the first three for the motion and the callback
ordering, the last two as the regression checks for W112 and for `alphaBlendTo`'s arriving subtrees.
`Tests/NullPlayerAppTests/WMPTweenTests.swift` is where the motion is falsifiable at all, because the
frame step can be called directly; its first test is the no-clock invariant the sweep rests on. Noted
on `WMP_RENDER_CLOCK`'s own section in `reference/harness.md`.

Original row:

| W194 | `moveTo`/`resizeTo`/`alphaBlendTo` ignore their duration, so nothing in the corpus ever animates | **the duration form is corpus-wide**; the completion callbacks it would move are **36 views** (`onEndMove`, the drawer template Microsoft shipped) | Reported 2026-09-16 as *"its not a smooth opening"* against `Compact`'s drawers, which jump rather than slide. `WMPObjectModel.flushPendingTweens` writes the endpoint at the end of the handler and `WMPScriptContext.raiseCompletionHandlers` raises `onEndMove` immediately, so a 1,000 ms slide takes one frame. **The tween is the easy half; the callback is the risk.** Moving `onEndMove` from *end of handler* to *end of tween* changes when 36 views' sequences chain — W55 is the row that made that callback load-bearing, and `Compact` itself shrinks its window inside `Playlist_OnEndMove`, so a real tween means the window shrinks a second after the drawer starts closing, which is what WMP does. Sweep the corpus either side and drive at least `Compact`, `xsn_sports` and `corona` live; a render dump cannot see motion (`WMP_RENDER_CLOCK` pins frames for GIFs only). |

## W227 — the window edge, and who gets the press, 2026-09-18

| ID | Item | Reach | Notes |
|---|---|---|---|
| W227 | **The window-edge band runs no skin resize bracket** | every `.wmz` view that authors a `view.size` grip — **88 of 185 archives, 235 calls** | Opened by W225, which closed the grip path only. This engine lets the user drag a borderless `.wmz` window's edge; **WMP has no such affordance**, so no skin anticipates it and whatever the skin wraps around its own resize never runs. Stretching `Compact` by the edge leaves both drawers behind exactly as the pre-W225 grip did — the same picture, reached a different way. Two shapes, neither measured: raise the view's own grip handler on an edge-band press, or refuse the band on a view that authors a grip (which is what WMP does, and costs the user the affordance on the 88). **`WMP_RESIZE_TRACE=1` prints `edge-band press` for this path**, so the two are distinguishable in a log. Rank against how often a user reaches for the edge before finding a grip they cannot see. **Closed 2026-09-18, and the row's own premise was wrong about the path it named.** `WMP_RESIZE_TRACE=1` was recorded here as printing `edge-band press` for this path. It never did for a real drag: a `.wmz` window is `[.borderless, .resizable]`, and `.resizable` alone is enough for AppKit to claim a press near the frame in `NSWindow.sendEvent` and run its own resize loop, so `WMPMainView` was sent no `mouseDown`, no `mouseDragged` and no `mouseUp` and the window was resized entirely outside the skin. Measured live on `Compact`: the `leftMouseDown` arrives at the window, nothing arrives at the view, and the window grows by exactly the drag. A *click* on the same pixel **does** reach the view, so the trace printed only for gestures that resized nothing and the band read as live for two phases while it had never once run. **Of the two shapes this row left open, the measurement chose the first.** A decoded scan of the 87 archives authoring `view.size`: **69 have a real tail after the call**, and in 68 of them it is one idiom — `saveVidSize()` / `onVidSetSize()` / `g_fUserHasSized = true`, persisting the size the user just dragged to. A bare edge drag did not merely skip a bracket, it made the skin forget the size the moment the view closed, which is worth keeping the affordance for rather than refusing it as WMP does. `WMPSkinWindow.sendEvent` claims the band press before `super`, and only where the view says no control is there, so a control drawn against the window edge keeps every pixel it had; the band then raises the view's own grip handler exactly as a press on the grip does. `WMPResizeGrip` names the grip node and its corner from the markup — **233 of the 234 corpus calls are spelled straight into the handler attribute**, and the one that is not is `Compact`, the archive the whole bracket exists for (`onMouseDown="DoSize()"`), so it resolves one hop through the skin's scripts; deeper is authored nowhere. `beginScriptResize` **adopts** a drag already under the pointer instead of refusing it: refusing answers `false`, which is the caller's signal that no release is coming, so the held tail would run mid-drag against the size the window started at — the stranded bracket W225 exists to prevent. Verified live on `Compact`, both axes: `edge-band press edges=.right grip=size#51` → `hold 2 of 4 at 601x480` → `beginScriptResize ADOPTED` → `release script=true band=true size=(722,480)` → `resume … 2 writes`, with `playlistDrawer` riding 397 → 518 and both drawer tabs still clickable. The skin's own grip is unchanged (`band=false`, 422x378 → 482x418), window drag by bare artwork still works, and `corona` — no grip, not resizable — is untouched. |
