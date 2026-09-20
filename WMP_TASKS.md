# Windows Media Player (`.wmz`) — ranked open backlog

This is the only live backlog for the WMP skin subsystem. It is the `.wmz` counterpart to
[`WINAMP5_TASKS.md`](WINAMP5_TASKS.md), and the two never share entries: a `.wmz` item goes here, a
`.wal` item goes there. Read `skills/wmp-skin-guide/SKILL.md` before picking anything up.

A defect in the **shared video path** belongs to neither and goes in
[`docs/video-playback/backlog.md`](docs/video-playback/backlog.md) — opened 2026-09-10 because
hosting `<VIDEO>` (W102) surfaced one that had nowhere to go. **V1 there is worth reading before any
`.wmz` video work**: a playing film is silently re-opened from the start and the reload hangs, and
because the picture simply stops it reads as a skin or decoder defect when it is neither.

A skin is a test case, not a milestone: take measured capability work from the top down. Closed
entries move to [`docs/wmp-skin/wmp-backlog-archive.md`](docs/wmp-skin/wmp-backlog-archive.md) in the
same change that closes them, so this file stays a list of work that is still open.

**A row with a defect in the *row* goes to [`LOW_QUALITY_TASKS.md`](LOW_QUALITY_TASKS.md), which is
neither the archive nor a rejection of the work.** Six went there on 2026-09-19 — W68, W239, W73,
W111, W135 and W67 — and two left real work behind, both now archived: **W241**, closed 2026-09-20
(the empty-value class; its corpus number came out **970 uses / 135 of 182 archives**, and the
geometry share of it was the whole defect), and W242, which was ranked here until 2026-09-20 (it
retired as measured and found W243 on the way). **Read that file before re-opening any number, and
re-measure before reviving anything from it.**

**Every table on this page is in rank order, top down, and the tiers themselves are ranked by the
order they appear.** Take the first row of the highest tier that is not blocked. A row whose Reach is
explicitly *unmeasured* is placed provisionally and says so in its own Notes; measure it before
letting it outrank a measured row.

## Ranking

### How a row is ranked

**Reach is corpus demand, not severity**, measured across the skins installed in
`~/Library/Application Support/NullPlayer/WMPSkins/`. **Every Reach number must be reproducible by a
command recorded next to it**, and must carry the date and the archive count it was taken over. The
measured corpus is **179 of the 180 installed** at the time these scripts were written and 185 by
2026-09-19; `scripts/wmp_corpus_exclusions.txt` holds the difference and
`skills/wmp-skin-guide/reference/harness.md` § *The corpus* says why.

**Two numbers on this page are produced by the census itself rather than by hand, and the files they
are written to outrank any row here that disagrees.** `starved.tsv` ranks every view by
`unresolved / declared` (W70); `appkit.tsv` ranks every hosted view by how much an AppKit overlay
painted outside any widget frame (W71). **Take work from the top of those, not from the top of a
paragraph** — and **dump the view before taking the row**, because `starved.tsv` ranks declared-
but-unresolved nodes rather than missing pixels and a `0 commands` view may be an authored blank.
What each file does and does not rank, with its measurement history, is `harness.md` § *What the
ranking files rank, and what they do not*.

**Load level is a constant: there are no loading rejections left in the corpus.** Every entry below
is a rendering or runtime defect, and only a dumped PNG or a `SCRIPT-DIAG` line can see one. A row
whose evidence is a census column is by that fact measuring structure, not result.

**Before quoting or scaling any number on this page, check `harness.md` § *Numbers that are void, and
why*.** Five classes of count here must be re-measured rather than carried forward: anything against
the 14-skin denominator, anything captured before rev `61f8955a`, any `COMPAT`/`UNKNOWN tag` number
taken before W215 closed on 2026-09-19, the stale view counts, and `WMP0035`/`WMP0032`/`WMP0033`.

**Before issuing a number, read `docs/wmp-skin/wmp-backlog-archive.md` § *Issuing a number*.** It
holds the next free number, the two renumbered IDs (W196 → W217, W171 → W218), the `W235` source-
comment collision, and which numbers were issued and closed without ever appearing here.

## Tier 1 — views that load and then draw nothing

**Empty, and both halves of it are closed.** Tier 1a held the loading rejections (W33 closed the
last); no view in the corpus fails to lay out (W6, W8). Nothing comes back here unless a *new*
archive is rejected or a view starts drawing nothing — which is indistinguishable from a rejection
to anyone using the app, and is why the tier stays.

## Tier 1c — live-reported, not yet reproduced headlessly

**The 2026-09-08 live-QA list was never captured, and that is still the largest known hole on this
page.** The reporter drove Phase 5, reported "tons of issues", the session ended before the list was
written down, and so no count here includes them: every Phase 5 closure in the archive is
*harness-verified only*. **Capture a reporter's list before ranking further Phase 5 work.** What
Phase 6 recovered of it is `harness.md` § *After Phase 6*; the traps a live report sets are
§ *Attributing a live report to the change in front of you*.

**W68 was this tier's other row and moved to [`LOW_QUALITY_TASKS.md`](LOW_QUALITY_TASKS.md) on
2026-09-19 with its central number false.** Do not re-derive anything from its figures; what survived
it was W242, **retired 2026-09-20 as measured** — the Alienware family's 5 hit targets are a
transport authored behind an 800 ms intro, `WMP_RENDER_OCCLUDED=1` is clean across all six archives,
and the live half of the report was the engine dispatching one click twice (**W243**, closed the
same day). Both are in [the archive](docs/wmp-skin/wmp-backlog-archive.md); **the rule W242 leaves
behind is that a `hits` count taken at t=0 is a count of a scene nobody sees in a skin that opens
behind an animation — settle before ranking one.**

**The tier is empty of rows and stays for the same reason the others do.**


## Tier 1d — what the Phase 6 instruments do and do not reach

**Empty as of 2026-09-19**, and the tier stays because a genuine gap in instrument reach ranks above
a skin-side defect when one is found. W239 and W73 moved to
[`LOW_QUALITY_TASKS.md`](LOW_QUALITY_TASKS.md); **W73's caveat is still true and still matters** — a
clean sweep proves only the default state, and a tab, a hover, a drawer, the window's shape and
anything driven by live playback remain outside every headless instrument here. It is prose in
`harness.md` § *The probe flags*, where a reader meets it before trusting a capture.

## Tier 1f — the residue of the starvation classes

| ID | Item | Reach | Notes |
|---|---|---|---|
| W240 | **An unresolved node that carries a bitmap takes zero instead of the image's size** | **6 `<SUBVIEW>` nodes across 5 archives** — was 7 across 6 until W241 closed `WWC`'s `introAnim` on 2026-09-20 — inside a wider class of **33 of the corpus's 458 unresolved nodes** that carry a bitmap, measured 2026-09-19 over 185 archives with the W231-extended `WMP_RENDER_UNRESOLVED`; **the 33 is pre-W241 and is a ceiling, not a count** | Not blocked. Re-count the 33 first (W241 closed part of it), then settle the rule together with W123 — `Radio` is in both. Not a one-line fallback, and `jsa:` is not part of it and must not be implemented. `STALKER`'s `vidBack` is still here and is the empty-`backgroundImage` case W241 deliberately left: an empty resource already falls through to the next name, so what it lacks is a size, not a bitmap. Evidence: `harness.md` § *After the subview class*. |
| W236 | **Two ids are read as a `fontFace` and a `scrollingDirection`, and answering them with the empty string is not the same as answering them** | **12 uses / 2 ids across 2 archives** (`Revert`, `Revert (1)`), measured 2026-09-19 by the W195 census | Not blocked. These are localisation plumbing, not labels, and `""` is not an answer for an attribute with a real default. First step: measure what the scene does with an empty `fontFace` — if it falls back to the view font the row closes as a note; if not, three readouts on both `Revert` releases draw in the wrong face. Not a W195 defect. Evidence: `SKILL.md` § *Static scene and image contracts*, the `res://wmploc.dll` bullet. |

## Tier 1g — the window system, not the scene

A row lands here when the defect is in `App/WindowManager.swift` or `App/AppStateManager.swift` —
where a window is placed, restored, rescued and reset — and would reproduce identically on a skin
that renders perfectly. Tier 1e is its nearest neighbour and is deliberately separate: that tier is
about *which* window a surface belongs in, this one about *where the window is*.

Three rules follow, and they are why these rows do not rank against a starved view:

- **Reach is not a corpus number.** A gate on `uiMode.controllerFamily` affects every `.wmz` session
  equally, so `scripts/wmp_skin_census.sh` says nothing about it. Both rows below reach every `.wmz`
  session and are ranked against each other by what a user can do about the result — a stranded
  borderless window has no route back at all.
- **No headless instrument reaches it.** `WMP_PLACE_TRACE` sees the one moment a window is *placed*;
  a render dump has no screen, no second display and no restore. Verify by driving the app —
  `skills/live-ui-testing`, and `harness.md` § *Debugging a live defect*.
- **The blast radius is the other three families.** Shared code, so `CLAUDE.md`'s binding rule
  applies at its strictest: gated on the mode, never justified as a no-op, Classic and Original
  byte-identical.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W217 | `.wmz` shares the `.wal` *placement* seams but none of its *recovery* seams, so a stranded WMP window has no route back | **every `.wmz` session**; the gaps are structural, not per-skin (code audit 2026-09-16, no corpus sweep needed) | **G4 closed 2026-09-18. Three gaps remain, and the audit's step 2 takes G2 and G3 together.** (G1) `WMPWindowRestorePolicy.safeFrame` (`WMPMainWindowController.swift:2621`) is a second, weaker definition of "on screen" — an 80pt strip and a 24pt bottom margin rather than `WindowPlacement`'s top-left-corner rule. (G2) `correctedRestoredFrames` is gated `appliesWinampModernPlacement` (`AppStateManager.swift:955`), so WMP gets neither the whole-session group offset nor the `savedScreenIsMissing` force. (G3) `ensureAllWindowsOnScreen()` returns early in WMP and all six call sites re-guard, so a display or resolution change strands WMP windows **permanently**. First step: read `~/.claude/plans/wmp-window-placement-compliance.md` — the rule-by-rule table, the line numbers and the four-step plan. **Verify live** (`WMP_PLACE_TRACE=1`, `Halo 2` as the load case, `Corona` as the control), reading frames back through `app-control`'s `winhelper windows`; Classic and Original must be byte-identical. Evidence: `SKILL.md` § *Window placement and recovery*. |
| W214 | **`isRunningModernUI` is a two-way switch in a four-family world, so every `!isRunningModernUI` branch treats a `.wmz` window as Classic** | 4 sites, every `.wmz` session (code audit 2026-09-17; no corpus sweep can see this) | Not blocked. This is W217's G4 generalised, and one instance already cost a full live-QA cycle (closed with W213). **Do not gate the four in one sweep** — each is a shared-`App/` path, so gate on the mode and prove Classic and Original byte-identical, separately per site. First step: `handleCenterStackWindowWillClose` (`:2036`), the one confirmed live. Verify with `WMP_SIZE_TRACE=1` and `WMP_PLACE_TRACE=1`. Evidence: `SKILL.md` § *`isRunningModernUI` is a two-way switch in a four-family world*, which ranks all four. |

## Tier 1h — the borrowed window frame

**A row belongs here when it is about the pixels a donor lends and how they compose against
NullPlayer's own content** — not which window a surface lives in (Tier 1e) or where that window is
(Tier 1g). It ranks below Tier 1g and above Tier 1e.

**Verify by driving the app and capturing the live window**: a `HOSTED-FRAME` line alone has twice
measured clean while the window was visibly wrong
([`back-to-the-future-trilogy.md`](skills/wmp-skin-guide/reference/skins/back-to-the-future-trilogy.md)
§ *Process lessons this skin taught*). The rules the closed rows established — W207 geometry, W208
slots, W209/W210/W212 pixels, W230/W238 arrival — are in `SKILL.md` § *Every NullPlayer window in
WMP mode is the skin's or is themed*, with the rows themselves in the archive.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W234 | **Broken borders and content in the wrong rectangle, on every hosted window at once, while the skin's own window is right** | unmeasured — reported 2026-09-18 as the standing condition of the hosted windows, not as one skin's defect; the population is every hosted window under a skin that lends a frame, ~120 of 185 archives (88 rings + 32 panels, W207's measurement) | **The reporter's framing is the finding: "the main windows are fine, it is all the other windows", "broken borders, misplaced center data", "all the same UI look over and over."** Ten windows failing the same way against a player view that never does is one contract unhonoured at ten call sites, not ten defects. Not blocked; W230 was the same seam at first open and may share a cause. First step is one capture, not a matrix: read `WMP_HOSTED_FRAME_DUMP` against the live window on one skin the reporter names. Evidence: `SKILL.md` § *Triage a hosted-window defect before choosing a seam* and § *Evidence proportional to a hosted-window change*. |

## Tier 1e — a surface the skin owns and this engine does not host

The corpus declares six surfaces; four are hosted. **The tier's rule is that a surface recognised for
*routing* and not hosted draws the user an empty drawer**, so a hosting row always lands before the
routing that stands NullPlayer's own window aside. Playlist kinds: `object-model.md` § *Playlist
kinds*.

Measured 2026-09-09 over 179 archives and 595 views (`skins` declare it anywhere; `own view` put it
in a view other than the one they open on). Reproduce with `scripts/wmp_markup_census.sh <outdir>
EFFECTS WMPEFFECTS VIDEO WMPVIDEO VIDEOSETTINGS NETWORK PLAYLIST EQUALIZERSETTINGS` — **never with an
ad-hoc script that decodes the `.wms` itself**; `harness.md` § *Counting a tag across the corpus* is
the trap that rule exists for.

| Surface | views | skins | own view | Hosted today | Row |
|---|---:|---:|---:|---|---|
| `<VIDEO>` / `<WMPVIDEO>` | 268 | 170 | 165 | yes (W102) | — |
| `<EFFECTS>` / `<WMPEFFECTS>` | 178 | 171 | 144 | yes (W101) | — |
| `<PLAYLIST>` family | 175 | 170 | 162 | yes (W93, W97) | — |
| `<EQUALIZERSETTINGS>` | 170 | 163 | 147 | yes, as the skin's own bound sliders | — |
| `<VIDEOSETTINGS>` | 94 | 94 | 93 | no | **W103** |
| `<NETWORK>` | 6 | 4 | 4 | object-only, correctly | **W104** |

| ID | Item | Reach | Notes |
|---|---|---|---|
| W103 | `<VIDEOSETTINGS>` binds 94 skins' sliders to controls this player does not have | **94 uses across 94 of 177 archives**, one per skin, 93 of them in a view of their own | **Blocked on a decision, not on drawing work**: either `inert()` the brightness/contrast/hue/saturation panel, or add the four controls to the video path and bind them honestly. **Do not resolve them to a value this player never applies** — a slider that moves and changes nothing is the worse outcome. Answerable since W102 landed. Evidence: `object-model.md` § *The `<VIDEOSETTINGS>` element (W103)*. |
| W104 | `<NETWORK>` answers nothing, and Flow is not what it means | **6 uses across 4 of 177 archives**; the smallest surface in the corpus | Not blocked. **Feed it from the streaming player's own statistics, never from Flow** — `NetworkMonitor` measures interface throughput for the whole machine, which would draw a confident wrong number. Flow is still the right *window*; the object and the window are two separate answers. Evidence: `object-model.md` § *The `<NETWORK>` element (W104)*. |


## Tier 2 — the script runtime, after Phase 3

The runtime is one persistent `JSContext` per skin session with a native Swift object model
(`skills/wmp-skin-guide/reference/object-model.md`). Reproduce the rankings below with
`scripts/wmp_skin_census.sh /tmp/wmp/census` and rank the `SCRIPT-DIAG [handler-error]` lines in
`render.txt`.

**Every number measured before Phase 3 is void** — that runtime could not run a handler to its
second statement — **and so is every number measured before W37 closed**, because closing the
biggest row lets handlers run further and *raises* the rows behind it (`object-model.md` rule 2:
unimplemented is a queue, not a set). What each phase measured is `harness.md` § *After Phase 3* and
§ *After W37*.

Rows are in rank order, top down.

### 2a. What still stops a handler, ranked by reach

Reproduce with `scripts/wmp_render_sweep.sh capture <dir> --allow-dirty` and tally
`WMP: unimplemented <member>` and `Can't find variable: <name>` in `<dir>/raw.txt` by name and by
containing `SKIN` block.

**W216 is first and its Reach is unmeasured.** It is placed on the W100 precedent — the census drives
`onLoad` and this demand is in `onClick`, which is how W100 read as 2 skins when the true number was
162 — and it is the only row here that stops a *click* rather than a load. **If it comes back small
it drops below W39.**

| ID | Item | Reach | Notes |
|---|---|---|---|
| W216 | **An unqualified call in an event handler does not resolve against the element the handler is on** | 2 archives known (`circle`, `pharaoh`), **corpus reach unmeasured** | Blocked on its own measurement: **measure the reach before sizing it**, the way `harness.md` § *Auditing one authored control across the whole corpus* prescribes, because the demand is in `onClick` and the census never drives it. Verify with `WMP_RENDER_CLICK` on `circle` at `vMain@69,68`. Evidence: `object-model.md` § *An unqualified name in a handler resolves against its own element first (W216)*. |
| W39 | `eq.speakerSize` | 18 skins | Plus `eq.enableSplineTension` and `eq.enhancedAudio` at 1 each. WMP's speaker/spatial settings; the engine has no equivalent, so this is an honest `inert()` candidate rather than a feature. |
| W42 | A skin function is missing because its program never registered | ~12 skins, 1–2 each | `skin_init`, `loadVidPrefs`, `UpdateMetaData`, `checkForContent`, `Init`, `gears`… Each is one skin's own function, so the cause is upstream: a `.js` that failed to resolve, evaluated with an error, or is a `res://` entry. Diagnose from `SCRIPT`/`SCRIPTS` lines before writing any object-model code. |
| W136 | SDK element methods this engine does not implement, now that they are tallied at all (W128) | `plListBox1/2.deleteAll()` **10 skins** (7 census-visible), `playlist2.copy()` 8, `playlist2.abortCopy()` 8, `playlist1.deleteSelected()` 5, `fileList.insertItem()` 3 | **Blocked on W66's media-collection decision** — every `deleteAll` call is inside the skin's own `try`/`catch` (`fillListBox()`, `warcraft.js:1584`), and the box has nothing to put in it until `player.mediaCollection` answers. This row is what that decision would let the skins actually do. **The census sees only `deleteAll`**: the rest sit in click handlers, so measure them through the live loop or a click-driving sweep before ranking them against each other. Reproduce by tallying `UNRECOGNISED` in `render.txt`. |
| W40 | An element the skin names is in another view | 8 + 4 + 2 + 2 + 2 skins | `Can't find variable: vidinfo` (8, new behind W37), `Can't find variable: pl` (4), `playlistframe.setColumnResizeMode (no such element)` (2), `pl.setColumnWidth` (2), `vidZoom`/`videoWin` (2 each, also new behind W37). Handlers are now scoped per view, but a script's *globals* are the current view's elements only. Find out what WMP does with a cross-view reference before choosing. |
| W41 | `player.currentMedia.sourceURL` | 4 skins | Small and real. **`theme.closeView` was the other half of this row and closed 2026-09-11 with W141**; what is left is the source URL. |

### 2c. Events the markup declares and nothing ever raises

An entry here is markup asking for something. **Classification is one line; the dispatch site is the
real cost, and it is different per event.** Do not add a name to `handlerNames` or `supportedEvents`
without its dispatch site — the rule, the instrument that made this class visible, and the 4,114-use
measurement are in `object-model.md` § *Recognising an event is not dispatching it*.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W53 | Keyboard events (now reachable: the window could not take the keyboard at all until W79) | `onkeydown` 501/78, `onkeypress` 409/72, `onkeyup` 94/30 | `WMPMainView.keyDown` handles focus traversal and activation and raises no authored handler. Needs a key-code/character contract at the object-model boundary — decide what a skin may see of a keystroke before implementing. |
| W56 | Video and playback-position events | `onvideostart` 190/140, `onvideoend` 132/130, `onpositionchange` 147/41 | Not blocked: W102 supplies the hosted video surface and W124 the live/event-state split, so the `onvideostart`/`onvideoend` half is directly measurable. **`currentposition_onchange` closed with W129 and must not be re-opened as a rendering row** — it changed no pixel, and that is the measured finding; `object-model.md` § *Ambient `<attribute>_onchange` handlers* says why. |
| W121 | A handler that reads the `event` object | **30 handlers across the Skins Factory equaliser family**, measured 2026-09-09; unmeasured for the other event kinds | Not blocked. **Count the whole class first**: sweep the corpus's handler attributes for `event.` and split by event kind — a mouse handler's modifier state and a key handler's `keyCode` come from different places, and W53 needs the key half anyway. Evidence: `object-model.md` § *Event arguments*. |

**Verified *not* gaps — check before opening a row here.** The SDK conformance audit (2026-09-11)
disproved nine candidate gaps, including the author-typo list (`scrollingAmmount`,
`horizontalAlignemnt`, `donwImage`…) that is the largest single false lead in the whole scan. They
rank nothing, so they are in `skills/wmp-skin-guide/reference/object-model.md` § *Verified **not**
gaps*.

**`INERT` — recognised, answered, and nothing behind them — ranks nothing either** and is in that
same file, § *Recognised, answered, and nothing behind them*. It is Phase 5 rendering work, not
runtime work.

## Tier 3 — drawing the skin's own controls (Phase 5)

**Reach here is `scripts/wmp_markup_census.sh` output, measured 2026-09-07 over the 177 archives it
could read** — the 180 in `WMPSkins/` less `Darkling.wmz` and the two whose local header signature
`unzip` cannot open and the engine can. Every number below is short by at most two skins, never long.
Reproduce with `scripts/wmp_markup_census.sh /tmp/wmp/markup`.

**This is authored demand, not result**: the census says a skin asks for an attribute, never that the
engine draws it right. Only a dumped PNG says that.

Rows are in rank order, top down — corpus reach first, and the single-skin rows at the bottom are
kept because each names a *visible* readout, not because they rank with the rest. **What Phase 5
closed is in the archive** (W58-W63 and the rest); it closed the phase *as the harness measures it*,
and the 2026-09-08 live QA found defects that are still not enumerated — see Tier 1c before treating
any of this as done.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W133 | Hosted `PLAYLIST` chrome attributes are unread | `columnsVisible="true"` **74 skins**, `leftStatus`/`rightStatus` 27, `dropDownImage`/`dropDownBackgroundImage` 27/25, `toolbarVisible` 12, `toolbarMargin` 14 — what genuinely differs from the overlay, after verification halved the row | Not blocked. **The substance is column headers, which the overlay draws none of**; `dropDownVisible` is explicitly not part of this row and waits on W66. Evidence: `SKILL.md` § *Drawing the skin's own controls*. |
| W132 | `hoverDownImage` is never selected | **126 nodes across 62 skins** (`BUTTON` 86, `BUTTONGROUP` 38, `MUTEBUTTON` 2) | Not blocked but **deliberately ranked low**: all 126 also author `downImage`, so the fallback is the right artwork missing only its hover lighting. **The fix is not just a name** — `WMPInteractionState` collapses pressed and sticky-down into one `.down`, so the state machine needs a distinct hover-down face first. Needs the live loop. Evidence: `SKILL.md` § *Drawing the skin's own controls*. |
| W202 | An `<EFFECTS visible="false">` that a script later makes visible never gets a hosted surface | **57 nodes in 54 archives** declare `visible="false"` on an `<EFFECTS>`/`<WMPEFFECTS>`; **how many a script turns on is unmeasured and is the number to take next** | Not blocked. `pharaoh`'s scarab mode is the reproduction, but **rank it on the corpus population, not on pharaoh** — that hole is small. First step: drive pharaoh in the debug build and **read the log, not the screen**; no second `Setting up ProjectM` line is ever logged for the scarab. Evidence: `skins/pharaoh.md` § *Still open*. |
| W201 | An animated GIF whose frame image blocks are smaller than its logical screen is drawn at the screen's size | **27 files in 12 archives** of the corpus's 4,303 GIFs (header scan, first frame's image block against the screen descriptor); `pharaoh/pyrevolver.gif` is the extreme at 6.7% of its declared area | Not blocked. **The cause is an observation, not a diagnosis** — screen-versus-block size and the GIF's uninitialised screen area are both candidates and neither has been isolated. **Check `Age_of_Mythology`'s `open_shutter.gif` before changing anything**; it is load-bearing for the one-shot terminator rule. Evidence: `skins/pharaoh.md` § *Still open*. |
| W66 | A `LISTBOX` has a control and nothing to put in it | **8 skins**, 16 uses, measured 2026-09-07 over 177 archives | **Blocked on a decision, not on drawing work**: what a `.wmz` may see of this player's library. The control draws and reports its selection; it has no rows because nothing answers `player.mediaCollection`, and it is deliberately not faked. **Rank it with whatever answers the media-collection question**, and W136 with it. Evidence: `object-model.md` § *Playlist kinds*. |
| W204 | Every view in a skin shares one script scope, so a second `scriptFile` silently overwrites the first's functions | **7 of 185 archives** declare two or more `scriptFile` programs defining the same top-level function name — `Plus! SlimLine`, `Sports` and `holiday_skin` collide on six each; re-run the scan before ranking | Not blocked. **It is invisible with a stopped player**, so a default-state sweep cannot measure it — reproduce with `WMP_RENDER_HOST=playing`. `pharaoh`'s own symptom is bounded and the row is ranked on the other six. **The shape of the fix is per-view function scope; what that costs a skin whose views deliberately share a helper is the question to answer first.** Evidence: `skins/pharaoh.md` § *Still open*. |
| W149 | Controls still unreachable after W148, each for a different reason | **11 total**, re-measured 2026-09-12 after W150 (was 16) — `Sports` 7, `anime`, `STALKER`, `T3-Skynet_Media_Player`, `Plus! Professional` | Not blocked. **Decide whether a `<BUTTONGROUP>` with no mapping children should be a hit target at all before counting those as work** — they were 10 of the original 16. **Name the node before ranking the count.** Reproduce with `WMP_RENDER_OCCLUDED=1` and read the `reached=rect-only` lines. Evidence: `harness.md` § *The residue `WMP_RENDER_OCCLUDED` does not explain (W149)*. |
| W203 | `<DURATIONTEXT>` never renders | **2 nodes in 2 archives** (`pharaoh`, `circle`) — a one-line row kept only because it is a *visible* readout on a shipped Microsoft skin | Not blocked. The missing piece is a glyph-height fallback this one tag does not get — `<currentPositionText>` beside it declares no `height` either and resolves to 45x10 — **so a `<DURATIONTEXT>` anywhere is dead, not just this one**. Evidence: `skins/pharaoh.md` § *Still open*. |
| W123 | A stretched `backgroundImage` and a natural-size foreground image draw the same bitmap at two different sizes | **1 view measured** (`Ice/videoView`); the wider class — every `backgroundImage` whose frame is not its bitmap — is **unmeasured** | Blocked on its own measurement: **measure the class before changing the rule**, and settle it with W240 (`Radio` is in both). It cannot be answered by extending W122, and `skins/README.md`'s counter-evidence table comes first. Evidence: `SKILL.md` § *Static scene and image contracts*. |
| W145 | A borrowed window frame is rendered from markup, so it never follows the theme the skin is *set* to | **`xsn_sports`** measured 2026-09-12; the pattern is stacked variants and is **unmeasured across the corpus** | Not blocked. **The fix is to run the donor view's `load` off-screen** and build the ring with the overrides it commits, keeping every candidate per ring role rather than the first declaration — settling on the chosen colour and **not** animating the phase. Evidence: `skins/xsn-sports.md` § *Defects it found (2026-09-12, borrowed window frames)*. |

## Closed

Closed entries live in [`docs/wmp-skin/wmp-backlog-archive.md`](docs/wmp-skin/wmp-backlog-archive.md),
verbatim and with their evidence. Move a row there in the same change that closes it — one left here
reads as open work.
