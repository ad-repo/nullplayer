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
| W136 | SDK element methods this engine does not implement | `plListBox1/2.deleteAll()` **10 skins** (7 census-visible), `playlist2.copy()` 8, `playlist2.abortCopy()` 8, `playlist1.deleteSelected()` 5, `fileList.insertItem()` 3 | **Blocked on W66's media-collection decision** — every `deleteAll` call is inside the skin's own `try`/`catch` (`fillListBox()`, `warcraft.js:1584`) and the box has nothing to put in it until `player.mediaCollection` answers. The census sees only `deleteAll`; the rest sit in click handlers, so measure them through the live loop before ranking them. Reproduce by tallying `UNRECOGNISED` in `render.txt`. |
| W266 | A skin's write to `event.keyCode` is refused, so its timer throws every tick | **3 archives**, measured 2026-09-24 by scanning every `.js`/`.wms` for an `event.<member> =` write over 179 archives (two `.wms` unreadable to the scan: `Need_for_Speed_Underground`, `SplinterCellWMPSkin`) — `Official_Xbox_XP`, `Official_Xbox_MP71`, `XBOX`, all the same `xbox.js` | Not blocked. `resetCode()`, the view's `onTimer` every 400 ms, does `event.keycode = 65`, and the engine answers `unimplemented event.keycode (read-only or unknown member)`. It clears the key the X-key Easter egg reads: `pressButton(event)` runs on `onMouseOver`/`onmousemove` as well as `onKeyDown`, and the reset is there so a stale `88` cannot launch `xbox.com` on hover. What our engine's `event.keyCode` reads in a mouse handler is **unmeasured**. **Decide what WMP's `event` is between key events** (a writable object that keeps the last value, or a fresh one) before making the member writable. Check what the throw costs per tick too: `SlimLine`'s throwing `OnTimerTick` showed up in `sample` (harness.md § `WMP_SCRIPT_TRACE`). Reproduce with `WMP_SKIN=…/Official_Xbox_XP.wmz WMP_RENDER_SETTLE=2` and read the `SCRIPT-DIAG mainBox … onTimer[0]` line. |

Do not add a name to `handlerNames`/`supportedEvents` without its dispatch site — `object-model.md`
§ *Recognising an event is not dispatching it*. Candidate gaps already disproved (incl. the author-typo
list) are in that file § *Verified **not** gaps*; `INERT` members are § *Recognised, answered, and
nothing behind them*.

## Drawing the skin's own controls

| ID | Item | Reach | Notes |
|---|---|---|---|
| W66 | A `LISTBOX` has a control and nothing to put in it | **8 skins**, 16 uses, measured 2026-09-07 over 177 archives | **Blocked on a decision, not on drawing work**: what a `.wmz` may see of this player's library. The control draws and reports its selection; nothing answers `player.mediaCollection` and it is deliberately not faked. Rank it with whatever answers that question, and W136 with it. Evidence: `object-model.md` § *Playlist kinds*. |
| W149 | Controls still unreachable after W148, each for a different reason | **11 total**, re-measured 2026-09-12 after W150 (was 16) — `Sports` 7, `anime`, `STALKER`, `T3-Skynet_Media_Player`, `Plus! Professional` | Not blocked, and smaller than it was: the `<BUTTONGROUP>`-with-no-mapping-children half closed with W259 (180 occluded rows → 165, 16 controls recovered). **The 11 predate that — re-measure, and name the node before ranking the count.** Reproduce with `WMP_RENDER_OCCLUDED=1` and read the `reached=rect-only` lines. Evidence: `harness.md` § *The residue `WMP_RENDER_OCCLUDED` does not explain (W149)*. |
| W203 | `<DURATIONTEXT>` never renders | **2 nodes in 2 archives** (`pharaoh`, `circle`) — kept because it is a visible readout on a shipped Microsoft skin | Not blocked. The missing piece is a glyph-height fallback this tag does not get — `<currentPositionText>` beside it declares no `height` either and resolves to 45x10, **so a `<DURATIONTEXT>` anywhere is dead**. Evidence: `skins/pharaoh.md` § *Still open*. |
| W123 | A stretched `backgroundImage` and a natural-size foreground image draw the same bitmap at two different sizes | **1 view measured** (`Ice/videoView`); the wider class — every `backgroundImage` whose frame is not its bitmap — is **unmeasured** | Blocked on its own measurement: **measure the class before changing the rule**, and not alongside W240 (`Radio` left that row when `corner_pieces.bmp` measured absent from its own archive, so the two never shared a skin). Cannot be answered by extending W122; `skins/README.md`'s counter-evidence table comes first. Evidence: `reference/rendering.md` § *Static scene and image contracts*. |
| W261 | Cover flow draws over the window's borders instead of inside them | **Unmeasured** — reported live 2026-09-22, not yet reproduced headlessly; it is one NullPlayer-owned window, so corpus reach is not the unit (every `.wmz` session that opens it) | Not blocked. The carousel in `Windows/ModernLibraryBrowser/CoverFlowView.swift` runs over the frame the skin lends, so it needs padding inside the border rather than the whole window's bounds. **Establish which border it is overrunning before changing a layout**: whether the browser window is wearing a donor frame at all, and whether the inset that frame reports is reaching the carousel's own layout or only its container. No headless instrument reaches it — a `HOSTED-FRAME` line has twice measured clean while the window was visibly wrong (`skins/back-to-the-future-trilogy.md` § *Process lessons this skin taught*), so **verify by driving the app and capturing the live window** (`skills/live-ui-testing`). |
| W264 | `portals`' EQ pane draws without its tray border | **1 archive** (`portals/mode1`), the one visible cost W263's reviewer accepted 2026-09-24 | Not blocked. Since W263 the script-shown `equalizer` is drawn inside `playlist_eq_video`, which the script leaves hidden (`showPlEQVid` defaults false), so the tray's own `mode1_playlist_mask.gif` border is missing around it. **Drawing a pass-through ancestor's artwork is not the fix** — it would put `Charlies_Angels_Full_Throttle`'s full face back under its gallery. Decide first whether the tray should be open at load (read `Portals.js` `detPlaylistEqVideo` and the saved `showPlEQVid` pref) or the pane hidden. Reproduce with `wmp_render_sweep.sh capture` and read `portals/mode1@1x.png`. |
| W265 | A mute control never shows its down face while muted | **2 archives seen live 2026-09-24** (`Frostbite`, `Plus! Professional`); the corpus population of both shapes is **unmeasured and is the number to take next** | Not blocked. Two shapes, both found while verifying W132. **(a)** A `<MUTEBUTTON>` with no `sticky="true"` (`Plus! Professional`'s `muteButton`) is not sticky, so `WMPMainView.refreshHostState` never latches it from `snapshot.muted` — decide whether the tag is sticky by definition. **(b)** A `<BUTTON sticky="true" down="wmpprop:player.settings.mute">` (`Frostbite`'s `mute`) toggles mute but draws `image` in both states: the binding never reaches the latch. Reproduce by clicking mute in the debug build with `WMP_CLICK_TRACE=1` and capturing the window; `setMute` itself is correct (`WMPAudioEngineHost`). |
| W145 | A borrowed window frame is rendered from markup, so it never follows the theme the skin is *set* to | **`xsn_sports`** measured 2026-09-12; the stacked-variant pattern is **unmeasured across the corpus** | Not blocked. **The fix is to run the donor view's `load` off-screen** and build the ring with the overrides it commits, keeping every candidate per ring role rather than the first declaration — settling on the chosen colour and **not** animating the phase. Evidence: `skins/xsn-sports.md` § *Defects it found (2026-09-12, borrowed window frames)*. |

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

## Known hole

**The 2026-09-08 live-QA list was never captured** — the reporter drove Phase 5, reported "tons of
issues", and the list was lost, so every Phase 5 closure in the archive is harness-verified only.
Capture a reporter's list before ranking further Phase 5 work. What Phase 6 recovered is
`harness-history.md` § *After Phase 6*.
