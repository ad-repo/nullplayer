# Windows Media Player (`.wmz`) — open backlog

The only live backlog for the WMP skin subsystem, and a list of open rows — nothing else. Read
`skills/wmp-skin-guide/SKILL.md` before picking anything up.

- `.wal` work goes in [`WINAMP5_TASKS.md`](WINAMP5_TASKS.md); the shared video path goes in
  [`docs/video-playback/backlog.md`](docs/video-playback/backlog.md) (read V1 before any `.wmz` video work);
  the local library and the playlist-playback path go in
  [`docs/local-library/backlog.md`](docs/local-library/backlog.md) (**read L1 before any report that a
  skin "won't play" something** — an unreadable track halts the playlist and says nothing in WMP mode).
- Closed rows move to [`docs/wmp-skin/wmp-backlog-archive.md`](docs/wmp-skin/wmp-backlog-archive.md)
  in the change that closes them. That file's § *Issuing a number* holds the next free number.
- A row with a defect in the row itself goes to [`LOW_QUALITY_TASKS.md`](LOW_QUALITY_TASKS.md);
  re-measure before reviving anything from it.
- Retired tier prose and post-mortems of closed rows:
  [`docs/wmp-skin/wmp-backlog-notes-archive.md`](docs/wmp-skin/wmp-backlog-notes-archive.md).

**Every Reach below is authored demand, not result, and several are stale — re-measure a row before
taking it**, especially one whose evidence predates a change to the same subsystem. `harness.md`
§ *Numbers that are void, and why* lists which classes of count must be re-derived; a corpus number
taken with bare `grep` is not a corpus number. Only a dumped PNG or a `SCRIPT-DIAG` line sees a
rendering defect, and no headless instrument here reaches a hover, drag, tab, scroll or playing
state — that work needs the live loop (`skills/live-ui-testing`, `harness.md` § *Debugging a live
defect*).

## Script runtime

| ID | Item | Reach | Notes |
|---|---|---|---|

Do not add a name to `handlerNames`/`supportedEvents` without its dispatch site — `object-model.md`
§ *Recognising an event is not dispatching it*. Candidate gaps already disproved (incl. the author-typo
list) are in that file § *Verified **not** gaps*; `INERT` members are § *Recognised, answered, and
nothing behind them*.

## Drawing the skin's own controls

| ID | Item | Reach | Notes |
|---|---|---|---|
| W309 | `US Army`'s Help draws a pink block over its text, and the skin has other button problems | `US Army` measured 2026-09-25 (Info → Help, live, while verifying W308); its five US-forces siblings share the markup, **unmeasured**. The other button problems were **reported, not yet described or measured** | Not blocked. `helpmask` (89,106 191x143, `backgroundcolor="pink"`, `clippingimage="infomask.gif"`, `ClippingColor="#000000"`) is clipped by a **370x370** image whose black region is exactly the node's rect in *window* coordinates (89..279, 106..248); the engine stretches the image to the 191x143 node, so the black lands at node-local ~46..144, 41..96 and pink shows there. **First step:** find where `WMPSceneBuilder` scales a `clippingImage` to its node and check which reading the corpus's other oversized clipping images want — a clipping image larger than its node, placed at the parent's or window's origin, rather than stretched. `credits`/`creditsmask` use the same pair. Then ask the reporter which buttons, and drive each with `WMP_CLICK_TRACE=1`. |
| W299 | **Lower priority.** A view the skin reopens at launch never opens, so its toggle button takes two clicks | `Alienware Invader` measured 2026-09-25 (seen by agent and reporter); `Batman Begins` too, **intermittently** (1 of 3 launches the same day; another opened `plView` at launch as it should); the family's `onLoadSkin()` pattern is **unmeasured across the corpus** | Not blocked. `controlView`'s `onLoad="onLoadSkin()"` runs at launch (`[wmp/pref] view=controlView event=load`) and calls `theme.openView('plView')` because the saved `plViewer` preference is `"true"` — and no `plView` window appears. The first `btnPl` click then reaches `toggleView('plView','plViewer')` (`awi.js:813`), reads `"true"`, saves `"false"` and closes a view that is not open; only the second click opens it. **First step**: relaunch with `plViewer` true and find where that launch-time `openView` is dropped — the skin's other launch-restored views (`eqViewer`, `visViewer`, `infoViewer`, `metaViewer`) take the same path. Measured with `rememberStateEnabled` false; check whether it holds with it on. See `skins/alienware-invader.md` § *W274*. |
| W300 | **Lower priority.** A `<LISTBOX>` keeps the double-clicked row highlighted after the script moved the selection | `Alienware Invader` measured 2026-09-25; the other `NVIDIA`-family choosers end `playSelPlaylist()` the same way, **unmeasured** | Not blocked. `playSelPlaylist()` ends with `plListBox1.selectedItem = 0`, so WMP would highlight "Now Playing" after a play; here the played row stays highlighted (captures in the W274 pass, Local Files and Jellyfin both). `object-model.md` § *`<PLAYLIST>` panes and `<LISTBOX>` choosers* says the highlight is the one the script **wrote in that transaction**, and the double-click also writes the **clicked row** — so the first question is which of the two writes wins in the `onDblClick` transaction. Cosmetic: the next click reselects correctly. |

## Harness and tooling

Rows that make the harness cheaper to use or harder to misuse. Reach is agent effort and the
wrong-answer risk a script removes, not skins. Filed 2026-09-24 from the token-relief pass that split
`SKILL.md` into `reference/` and added `baseline_worktree.sh`, `wms_grep.py`, `png_diff.py`,
`wmp_corpus.py` and `winhelper raise|capture|capture-all`.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W267 | The corpus control audit is a five-step manual procedure | every *"every skin has this button and it does nothing"* report; W100 sat **3 days** at a recorded 2 skins when the true number was **162 of 180** | Not blocked. Script it as `scripts/wmp_control_audit.py <handler-or-member>`: steps 1–2 on `scripts/wmp_corpus.py` (decode, then resolve handlers through the call graph to three levels — `wmp_handler_scope_census.py`'s `bare()` already does this); step 3 from an existing census `render.txt` (`WMP_RENDER_PROBE=all`) rather than a new sweep, **taking the median pixel of a mapping colour, never the first**; step 4's authored `left`/`top` fallback; step 5 printed as the `WMP_RENDER_CLICK` + `WMP_CALL_TRACE=1` runs to make. Reproduce the manual route from `harness.md` § *Auditing one authored control across the whole corpus*, and check the script against W100's 162/180. |
| W268 | `wmp_markup_census.sh` cannot open the two header-repaired archives, so every tally it prints is over 177, not 179 | **2 archives** (`Need_for_Speed_Underground`, `SplinterCellWMPSkin`), in every row it writes | Not blocked. It reads archives with `unzip`, which fails on their `01 00 01 00` local headers; it says so on stderr, but the denominator in `markup.tsv` quietly shrinks. Measured 2026-09-24: `EQUALIZERSETTINGS` is **161 of 177** there and **163 of 179** from `wms_grep.py`, which reads through `wmp_corpus.open_archive`. Read the entries through `wmp_corpus.py` instead of `unzip -p`. Done when both instruments agree on `<EQUALIZERSETTINGS`. |
| W269 | The before/after window-frame check and the remaining hand-written captures are not in `winhelper` | `harness.md` § *A live pass is a window frame, before and after* (eleven skins audited that way in one pass); osascript raise/`-R` snippets still in `skills/testing/SKILL.md` and `reference/skins/the-unit.md` | Not blocked. Add a `winhelper` verb that prints the NullPlayer windows' frames, clicks, and prints the frames again (the check the harness calls "two lines of Swift"), and point those two files at `winhelper raise` / `capture` / `capture-all`, which check what the snippets leave to the reader. `capture`'s group crop was verified live 2026-09-24 (a docked `Plex Browser` made `-l` return the whole 950x890 group). |
| W270 | The biggest `.wmz` reference files are still the biggest token cost | `harness.md` ~160 KB, `rendering.md` ~159 KB, `windows.md` ~104 KB, `object-model.md` ~98 KB | Not blocked. Split each behind a routing table the way `SKILL.md` was split on 2026-09-24 (320 KB → 25 KB): move sections verbatim, then check that the non-blank lines before and after are the same multiset and re-point every inbound `§` reference. **`rendering.md` needs subheadings first**: *Static scene and image contracts* is ~1,150 lines of bullets with no heading to route to, so name the bullet groups before moving any. |

## Found during `.wmz` work, owned elsewhere

| ID | Item | Reach | Notes |
|---|---|---|---|
| W276 | A second NullPlayer instance stops a Sonos room it no longer owns | **Measured 2026-09-24** while investigating W271 (archived): with NullPlayer on another Mac still casting to **Dining Room**, a cast from this Mac stopped ~45 s in on every run — current build, the pre-main-merge build `32b20b85`, and the 2026-09-20 build `bf8d15f5` alike — and played through the moment the other Mac stopped casting. The other instance's log was not captured, so **what it sent and why always ~45 s in is unmeasured** | Not blocked, and **not a `.wmz` defect** — owned by `sonos-casting`. Nothing in `Casting/` notices that another controller has replaced its stream: `UPnPManager` never reads the renderer's `TrackURI`/`CurrentURI` back, so a displaced instance keeps its session and keeps acting on the room, and the displacing instance then reads the resulting `STOPPED` as "ended externally" and pauses. **Direction:** on each poll, compare the renderer's current URI with the one this session set; on a mismatch, drop the session quietly (return to a stopped local state, no SOAP to the room). **First step:** reproduce with two instances against one room and capture the *displaced* instance's log around the stop — that names the command. |

## Known hole

**The 2026-09-08 live-QA list was never captured** — the reporter drove Phase 5, reported "tons of
issues", and the list was lost, so every Phase 5 closure in the archive is harness-verified only.
Capture a reporter's list before ranking further Phase 5 work. What Phase 6 recovered is
`harness-history.md` § *After Phase 6*.
