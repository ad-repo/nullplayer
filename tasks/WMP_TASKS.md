# Windows Media Player (`.wmz`) — open backlog

The only live backlog for the WMP skin subsystem, and a list of open rows — nothing else. Read
`skills/wmp-skin-guide/SKILL.md` before picking anything up.

- `.wal` work goes in [`WINAMP5_TASKS.md`](WINAMP5_TASKS.md); the shared video path goes in
  [`MISC_TASKS.md`](MISC_TASKS.md) (read M5 before any `.wmz` video work), as do the local library
  and the playlist-playback path.
- Closed rows move to [`docs/wmp-skin/wmp-backlog-archive.md`](../docs/wmp-skin/wmp-backlog-archive.md)
  in the change that closes them. That file's § *Issuing a number* holds the next free number.
- A row with a defect in the row itself goes to [`LOW_QUALITY_TASKS.md`](LOW_QUALITY_TASKS.md);
  re-measure before reviving anything from it.
- Retired tier prose and post-mortems of closed rows:
  [`docs/wmp-skin/wmp-backlog-notes-archive.md`](../docs/wmp-skin/wmp-backlog-notes-archive.md).

**Every Reach below is authored demand, not result, and several are stale — re-measure a row before
taking it**, especially one whose evidence predates a change to the same subsystem. `harness/instrument.md`
§ *Numbers that are void, and why* lists which classes of count must be re-derived; a corpus number
taken with bare `grep` is not a corpus number. Only a dumped PNG or a `SCRIPT-DIAG` line sees a
rendering defect, and no headless instrument here reaches a hover, drag, tab, scroll or playing
state — that work needs the live loop (`skills/live-ui-testing`, `harness.md` § *Debugging a live
defect*).

## Script runtime

| ID | Item | Reach | Notes |
|---|---|---|---|

Do not add a name to `handlerNames`/`supportedEvents` without its dispatch site — `object-model/classification.md`
§ *Recognising an event is not dispatching it*. Candidate gaps already disproved (incl. the author-typo
list) are in that file § *Verified **not** gaps*; `INERT` members are § *Recognised, answered, and
nothing behind them*.

## Drawing the skin's own controls

| ID | Item | Reach | Notes |
|---|---|---|---|
| W319 | A `<PLAYLIST>` pane showing a **library** playlist draws no EQ profile marker (`∿`) on rows whose track has a profile; the queue's rows do | **Read from code 2026-11-02, not seen on screen.** Found while checking the shared playlist row format across the four skin families (Classic, Original, `.wal` and the `.wmz` queue all draw the marker, checked live on `Xbox Live Skin`). Only skins that point a pane at a library playlist (W136, `playlist1.playlist = …`) reach it | `WMPObjectModel.widgetState()` builds the library rows from `WMPLibraryCatalog.Track` and never sets `WMPPlaylistItemSnapshot.hasEQProfile`. The queue's rows get it from `EQProfileResolver.shared.appliesProfile(to:)` in `WMPAudioEngineHost`. Three things stand in the way: a catalog track is not a `Track`, so it lacks the scope keys `appliesProfile` resolves; the object model runs on the script queue, not the main actor; and `playlistRowsCache` keeps the rows for the whole catalog, so an assignment made later would never reach them. **Direction:** resolve the marker on the main actor at draw time in `WMPPlaylistSurfaceView` (it already redraws on `playlistMarkersDidChange`), keyed by the row's `sourceURL`, rather than storing it in the cached rows. **First step:** find a corpus skin that shows a library playlist in a `<PLAYLIST>`, assign a profile to one of its tracks, and confirm on screen that the marker is missing. |
| W320 | `windows_media_player_8____redux__v2_0__by_shad0bi` (a remake of WMP 8's full mode) draws a yellow visualizer over the whole 670×482 window with none of its chrome | **Measured 2026-11-18** (intake of the crawled 46). Headless: `RENDER-DUMP View1: 10 nodes` of 746, `BITMAPS View1: resolved=0`, black PNG. Live (window census, 10 s of playback): the yellow visualizer plus a bottom strip, nothing else, and 11 of 15 Windows-menu items read `transient` (the window flashed at alpha 0). The WMP 9 sibling (`…9___redux__v1_0…`) draws properly | Three `SCRIPT-DIAG` lines name the first suspects: `onLoad[0]: ReferenceError: Can't find variable: btnRepeat (line 751)`, which aborts the rest of `onLoad`, and `[expression-error]` on `svEntireApp.left` and `plDropDown.width`: `SyntaxError: Unexpected keyword 'if'` (an attribute written as a statement, not an expression). `svEntireApp` holds the whole frame. Also 7 unknown tags (`app`, `mediacenter`, `listbox`, `editbox`, `dvd`, `currentplaylist`, `videosettings`). **First step:** find where `btnRepeat` should come from (an id the markup lacks, or one the graph dropped), then see what an `if`-statement attribute evaluates to, and dump `View1` after each. |
| W321 | `CleanRatingsSkin_0.2.2` is invisible: the window is there but nothing is drawn, headless and live | **Measured 2026-11-18** (intake). The archive's own `screenshot.png` shows a 195×61 rating bar. Live, after 10 s of playback, the 200×61 window draws nothing | The view is `backgroundImage="fullbg.gif" clippingColor="#FF0000"`, and `fullbg.gif` is **solid `#FF0000`**: every pixel is keyed out, so the view's own shape is empty. All the artwork is in the full-canvas `<subview id="big" backgroundImage="background3.gif" clippingColor="#abcdef">` and its children, which WMP plainly shows. So a view whose background keys out to nothing does not hide its subviews. The script's `fadeOut()` takes `main` to alpha 100 over 30 s, which dims the window but should not hide it. **First step:** find where the view's `clippingColor` shape confines the window (`WMPSceneBuilder.groundShape` and the window mask), and decide from the corpus what an empty view shape means. Enumerate every skin whose view background keys out completely before changing the rule (`check-what-a-new-rule-matches`). |

## NullPlayer's own windows beside a skin

| ID | Item | Reach | Notes |
|---|---|---|---|
| W317 | The borrowed frame has two answers to "is this edge tile sized by script?" | **Unmeasured.** Found in the PR #577 code review, not on screen: no skin is known to be drawn wrong by it | `WMPHostedFrameTemplate.note` (the repair-pass `stretchedDown`/`stretchedAcrossNodeIDs`) treats a tiled side piece as script-sized when `number(node, "height"/"width") == nil`, i.e. when the dimension is missing **or** is not a plain number. `isScriptSpannedTile` (`scriptSpans`) also requires `statedAttribute(named:) == nil`, so a dimension given as an expression (`height="jscript:…"`) counts there as authored. One of them is wrong for an expression-sized tile: `note` stretches it to the canvas over a length the build would resolve on its own, or `scriptSpans` leaves one alone that it should span. **First step:** list every tiled ring piece in the corpus whose relevant dimension is stated but not numeric. If there are none, make `note` call `isScriptSpannedTile` (a pure cleanup) and confirm every `HOSTED-FRAME` line is identical. If there are some, dump those frames under both rules and keep whichever matches what the skin draws. |

## Harness and tooling

Rows that make the harness cheaper to use or harder to misuse. Reach is agent effort and the
wrong-answer risk a script removes, not skins. Filed 2026-09-24 from the token-relief pass that split
`SKILL.md` into `reference/` and added `baseline_worktree.sh`, `wms_grep.py`, `png_diff.py`,
`wmp_corpus.py` and `winhelper raise|capture|capture-all`.

| ID | Item | Reach | Notes |
|---|---|---|---|

## Found during `.wmz` work, owned elsewhere

| ID | Item | Reach | Notes |
|---|---|---|---|
| W276 | A second NullPlayer instance stops a Sonos room it no longer owns | **Measured 2026-09-24** while investigating W271 (archived): with NullPlayer on another Mac still casting to **Dining Room**, a cast from this Mac stopped ~45 s in on every run — current build, the pre-main-merge build `32b20b85`, and the 2026-09-20 build `bf8d15f5` alike — and played through the moment the other Mac stopped casting. The other instance's log was not captured, so **what it sent and why always ~45 s in is unmeasured** | Not blocked, and **not a `.wmz` defect** — owned by `sonos-casting`. Nothing in `Casting/` notices that another controller has replaced its stream: `UPnPManager` never reads the renderer's `TrackURI`/`CurrentURI` back, so a displaced instance keeps its session and keeps acting on the room, and the displacing instance then reads the resulting `STOPPED` as "ended externally" and pauses. **Direction:** on each poll, compare the renderer's current URI with the one this session set; on a mismatch, drop the session quietly (return to a stopped local state, no SOAP to the room). **First step:** reproduce with two instances against one room and capture the *displaced* instance's log around the stop — that names the command. |

## Known hole

**The 2026-09-08 live-QA list was never captured** — the reporter drove Phase 5, reported "tons of
issues", and the list was lost, so every Phase 5 closure in the archive is harness-verified only.
Capture a reporter's list before ranking further Phase 5 work. What Phase 6 recovered is
`harness-history.md` § *After Phase 6*.
