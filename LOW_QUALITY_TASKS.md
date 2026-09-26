# Low-quality backlog rows, moved out of the live task files

Rows removed from a subsystem backlog because of a defect in the **row**, not a decision about the
work. A row lands here when it is stale past the point of trust, is not a unit of work at all, has
lost its own stated justification, is a bundle assembled to game a ranking, or describes itself as
not worth doing.

**This is not a rejection of the underlying work and not an archive of closed items.** Closed `.wmz`
rows go to [`docs/wmp-skin/wmp-backlog-archive.md`](docs/wmp-skin/wmp-backlog-archive.md) with the
evidence they closed on; work that was declined on its merits stays in the owning skill as a
documented refusal. A row here could still be real — it just cannot be taken in the shape it is in,
and leaving it in a ranked file makes every row above and below it harder to trust.

Each entry keeps the row **verbatim**, so nothing is lost, and states what is wrong with it and what
reviving it would take.

**Before reviving one, re-measure it.** Every number in these rows is at least as stale as the day it
was moved, and staleness is why several of them are here.

The live backlogs are [`WMP_TASKS.md`](WMP_TASKS.md) and
[`WINAMP5_TASKS.md`](WINAMP5_TASKS.md). A `.wmz` row goes in the `.wmz` section below; when the
`.wal` backlog needs the same treatment it gets its own section here rather than its own file.

## `.wmz` — Windows Media Player

### W103 — A question about what to bind, carried in a ranked file as work

**Moved 2026-09-21 by decision, with no behavior change.** The row has been **blocked on a decision,
not on drawing work** in its own words since W102 landed on 2026-09-10, and it names the two answers
itself: `inert()` the brightness/contrast/hue/saturation panel, or add the four controls to the video
path and bind them honestly. Nothing in it can be taken, verified or closed until someone picks one,
so it is a question rather than a unit of work, and a ranked file is the wrong place to keep a
question — it sat at the top of Tier 1e making the tier read as though it had available work.

**Its own content is sound and nothing here disputes it.** The prohibition it carries is the most
valuable line in the row and survives the move: **do not resolve the four sliders to a value this
player never applies** — a slider that moves and changes nothing is worse than one that is plainly
inert. The `<VIDEOSETTINGS>` element and what a skin asks of it are documented independently in
`skills/wmp-skin-guide/reference/object-model/elements.md` § *The `<VIDEOSETTINGS>` element (W103)*, which is
where a reader should start whichever way the decision goes.

**Its numbers are stale and must not be carried forward.** 94 uses across 94 of 177 archives was
measured 2026-09-07; the corpus has been 184-185 archives since. Re-run
`scripts/wmp_markup_census.sh` before quoting the reach again.

**To revive it, answer the question first and open the answer as the row.** "Make the panel inert"
is a small, closable row with a definite end state. "Add brightness, contrast, hue and saturation to
the video path" is a video-subsystem project that a `.wmz` row then consumes, and it belongs to the
video path's own backlog rather than to this page. Either is takeable; the choice between them is
not.

**The row, verbatim:**

> | W103 | `<VIDEOSETTINGS>` binds 94 skins' sliders to controls this player does not have | **94 uses across 94 of 177 archives**, one per skin, 93 of them in a view of their own | **Blocked on a decision, not on drawing work**: either `inert()` the brightness/contrast/hue/saturation panel, or add the four controls to the video path and bind them honestly. **Do not resolve them to a value this player never applies** — a slider that moves and changes nothing is the worse outcome. Answerable since W102 landed. Evidence: `object-model/elements.md` § *The `<VIDEOSETTINGS>` element (W103)*. |

### W251 — Live network numbers sourced from statistics that do not exist

**Moved 2026-09-21 on a source audit, with no behavior change.** The row's one instruction is
"feed both from the streaming player's own statistics", and the streaming player has no such
statistics to feed from. `Audio/StreamingAudioPlayer.swift` exposes an `AudioPlayerState` that
includes `.buffering` (`:173`), the bare edge `audioPlayerDidFinishBuffering` (`:901`),
`audioPlayerStateChanged` (`:905`) and `audioPlayerUnexpectedError` (`:926`). There is no loaded
byte range, no buffered duration, no bitrate-against-throughput, and no packet or rebuffer counter
anywhere beneath it.

So the row cannot be taken in the shape it is in. What the available signals would actually support:

- `bufferingProgress` could only be *state*-derived — `0` while `.buffering`, `100` once playing.
  That is a two-valued field rather than progress, and it sits a hair from the constant `100` the
  row itself records as **declined as unmeasured**. It is a decision, not the work the row describes.
- `receptionQuality` has no honest source at all. Counting rebuffer events would be a metric this
  codebase invented, not the one WMP means.
- Local files are the only clean case: no network is involved, so a settled full value is truthful
  rather than a guess.

**The cost the row describes is real and was not re-measured here** — `tubeframe.wmz` reading
`Playing: 0% downloaded`, and the buffer bars riding the same field. It is the *source* that is
false, and W104's own closure is untouched by this: the members answer instead of aborting the
handler, which is what that row claimed.

**To revive it, bring the statistics first.** Real numbers mean work below the skin layer — reaching
StreamingKit's internal buffer accounting, or moving the streaming path onto `AVPlayer`, where
`loadedTimeRanges` and `isPlaybackLikelyToKeepUp` exist. That is an audio-subsystem project with its
own justification, and a `.wmz` row is one small consumer of it. Re-measure the corpus reach at that
point rather than carrying the numbers below forward. If instead the two-valued state-derived field
is wanted on its own merits, open it as a *decision* row alongside W103 and say plainly on the page
that it is a state flag spelled as a percentage.

**The row, verbatim:**

> | W251 | `<NETWORK>`'s live numbers: `bufferingProgress` and `receptionQuality` are fields nothing writes | **26 + 9 script uses across 11 and 4 of 184 archives**, plus **55 `wmpprop:` buffer-bar bindings across ~36** riding the same field (measured 2026-09-21; `harness/corpus.md` § *Grepping the corpus's script text*) | Successor to **W104, closed 2026-09-21** ([archive](docs/wmp-skin/wmp-backlog-archive.md)), which made the member surface answer instead of abort but left the value a dead `0`. **Feed both from the streaming player's own statistics, never from Flow** — `NetworkMonitor` measures interface throughput for the whole machine and would draw a confident wrong number. **The cost of leaving it is already on screen**: `tubeframe.wmz` reads `Playing: 0% downloaded` on every track because its `GetMetaData` prints the field whenever it is under 100, and ~36 archives draw a permanently empty buffer bar. A constant `100` was declined as unmeasured; the live field corrects both together. Flow is still the right *window* for a `<NETWORK>` view — the object and the window are two separate answers. Evidence: `object-model/elements.md` § *The `<NETWORK>` element (W104)*. |

### W249 — A pre-resize trace was read as a refused resize

**Moved 2026-09-20 after live measurement on `caffef9e`, with no behavior change.**
The row's decisive line is emitted by `HostedWindowBorderLayout.apply()` **before**
`apply(size:to:)`. `frame=550x890 … target=550x893` therefore says what the rule is about
to request, not that the dock refused it. The settled frame and interior are needed too.

The reported AlienMorph / ALXVortex pair was driven in the local debug app with
`WMP_BORDER_TRACE=1 WMP_FRAME_TRACE=1 WMP_SIZE_TRACE=1 WMP_PLACE_TRACE=1
./scripts/kill_build_run.sh --debug --log /tmp/w249-before.log -- -uiMode wmp
-rememberStateEnabled false` (one shell command). Select AlienMorph through the temporary
`wmpSkinName` defaults preference, not a launch argument: an argument pins the selection
and defeats menu switching. Open Windows → Library Browser; switch using
`osascript skills/app-control/scripts/menu.applescript skin <pid> 'Media Player' <name>`.
Read the settled trace after each prewarm completes, and independently measure with
`skills/app-control/scripts/winhelper windows` and capture with
`screencapture -o -x -l <window-id> <output.png>`.

| Run | Settled outer heights | Interior heights throughout |
|---|---|---|
| AlienMorph → ALXVortex → AlienMorph → ALXVortex | 890 → 887 → 890 → 887 | 822 |
| ALXVortex → AlienMorph → ALXVortex, after resizing and explicitly side-docking the library | 890 → 893 → 890 | 825 |

For the second run, the ALXVortex player was `(680,279,339,329)` and the library
`(1048,279,550,887)` in `winhelper` screen coordinates. Resize its bottom edge with
`winhelper drag 1320 1163 1320 1166`, then dock it with
`winhelper drag 1300 297 1271 297`. The library landed at `(1019,279,550,890)`, exactly
against the player's right edge. On AlienMorph, the row's **exact cited trace** appeared,
followed by `frame=550x893 interior=490x825 border=42/30/26/30 target=550x893`.
The reverse switch settled at `frame=550x890 interior=490x825 border=42/30/23/30 target=550x890`.
Each switch queued just its target size, not a second conflicting size. The live window
captures `/tmp/w249-morph-825.png` and `/tmp/w249-vortex-825.png` showed the content in its
borrowed frame. The 3-point upward shift on growth was the existing screen clamp, not an
interior-height change.

This is counter-evidence to the row's stated universal mechanism, not proof that every
possible docking configuration is sound. **Reviving it requires a reproducible setup and a
settled before/after interior change without a user resize**, with the frame mutation that
caused it identified. Do not infer refusal from a pre-apply line or a normal change of outer
height: `890 − (42 + 26) == 887 − (42 + 23) == 822`.

**The row, verbatim:**

> | W249 | **A docked hosted window's height is owned by two rules at once, so every skin change slides its interior by the difference between the two skins' borders** | every `.wmz` session in which a hosted window is docked and the skin it is changing to lends a different border — the corpus's rings and panels differ freely, so this is most pairs, not an exotic one | Reproduced on demand 2026-09-20 on the reporter's own pair: **AlienMorph** lends 42/30/**26**/30 and **ALXVortex** 42/30/**23**/30, and the docked library walks 890 → 887 → 890 across switches while its recorded interior walks 825 → 822 → 825. The trace is one line of `WMP_BORDER_TRACE`: `frame=550x890 interior=490x825 border=42/30/26/30 target=550x893` — `HostedWindowBorderLayout` asks for 893, **the dock refuses the three points because it owns that height**, and the interior is then re-read against the new border from a frame the dock imposed. It is the W238 residue class in a new place and the same shape: two halves of a rule disagreeing about one number, each pass leaving a residue. **Do not answer it by widening the 2 pt `lastApplied` tolerance** — that constant is a guess about how far the docking pass settles, and the defect is that a frame we did not choose is read as the user's intent at all; W238 closed by making a read a round trip rather than by loosening one. The question the row has to answer first is which rule owns a docked window's height, because today both do. **W248's outgoing-frame hold makes this invisible, not absent** (`skills/wmp-skin-guide/reference/windows/hosting.md` § *Every NullPlayer window in WMP mode is the skin's or is themed*): the window now wears the outgoing skin's ring across the gap, so the slide costs a full donor render per switch rather than a second of bare chrome. Verify by driving the app — no headless instrument sees a dock. |

The following entries moved 2026-09-19 by an audit of the whole page, at rev `2f59b4e3`.

### W68 — The Alienware/ALX family draws a shell and nothing in it reacts

**Why it was moved:** Its central measurement is false, and it is the row every other tier was ranked behind.

Re-measured 2026-09-19: the row quotes `ALXMorph/mainView` as `15 nodes, 8 commands, 5 hits, 0 widgets, **15 unresolved**` and builds its whole case on "as many nodes failed to resolve geometry as laid out". The view now reads `15 nodes, 7 commands, 5 hits, 0 widgets, **3 unresolved**`, and **all three are classes since proven phantom**: one `<controls>` (W111), one `locSub` string table of twelve `<TEXT>` (W232), and one anonymous wrapper whose six subview children all resolve (W231). Twelve of the fifteen were string-table text — the ALX family led that population at 26 each. **Zero of ALXMorph's unresolved nodes are real.** `eqView` has drifted the same way (`45/44/26/8` → `44/43/24/1`), and the row's "everything below is 0.000" is not true either: 259 views are non-zero on `starved.tsv`'s own formula.

Beyond the stale numbers, the row had become a research log rather than a task — a single table cell of roughly 1,500 words quoting six rows that have since closed inside it (W38, W54, W75, W76, W143, W71) and deferring its own ranking to a file that disagrees with it.

**Its live remainder was preserved, not discarded**: `mainView` drawing its shell with only 5 hit targets became **W242**, asked as a hits question instead of an unresolved one. **W242 retired 2026-09-20**: the 5 is a transport authored behind an 800 ms intro and the family is clean under `WMP_RENDER_OCCLUDED=1`, while the *reacting* half of the original report was real and closed as **W243** — one click dispatched twice. Both are in [`docs/wmp-skin/wmp-backlog-archive.md`](docs/wmp-skin/wmp-backlog-archive.md).

**The row, verbatim:**

> | W68 | The Alienware/ALX family draws a shell and nothing in it reacts | 6 skins named below, inside a corpus-wide class of **41 views across 36 skins** resolving under half the nodes they declare, **79 views / 49 skins** with no hit target and **65 / 37** drawing nothing, measured 2026-09-08 over the 607 views of the 179-archive sweep. **The ranking is now automatic** (W70): `starved.tsv`, every census run | Reported as "ALXMorph does nothing — no animation and nothing reacts". **This is not an AppKit defect and it did not need a live session to find: the sweep has been printing it all along.** `RENDER-DUMP mainView` for `ALXMorph` is `339x329, 15 nodes, 8 commands, 5 hits, 0 widgets, **15 unresolved**` — as many nodes failed to resolve geometry as laid out, and five hit targets is a whole player's worth of buttons missing. `AlienMorph` and `AlienwareTeleport` are identical at `368x426`; `Alienware Invader` is worse still at `2 nodes, 0 commands, 0 hits, 18 unresolved` — it draws nothing whatsoever. The absent animation is the same cause, not a separate one: the family's big `m_anim_*` GIFs hang off subviews that are either unresolved or authored `alphaBlend="0"` and faded in by script (`mainAnimCoolantChamber` is the one confirmed by hand), so W38 `alphaBlendTo` was expected to be load-bearing here. **It was not, and W38 is now closed**: with the call implemented, `ALXMorph`/`AlienMorph`/`AlienwareTeleport` `mainView` goes 8 commands → **7**, because `alienware.js` fades `mainAnimCoolantChamber` *out* in the handler that used to abort at the call. **The artwork comes back on a click, and the preference-default path, now closed as W76, not W53/W54**: `toggleCoolantChamberAnim()` is raised by `animTrigger`'s `onClick`, and which branch it takes is decided by `theme.loadPreference("coolAnim") == "true"` — before W76, an unset key answered `''` and took the `else` branch; it now answers `"--"` and preserves the authored default. Clicks already dispatch, so the animation half of this row is one preference read away, not an unraised event. Hover is load-bearing elsewhere in the same skin — `volumeText` and `seekText` fade in and out of `onMouseOver`/`onMouseOut` in `alx_dl.wms` — so W54 buys those readouts, not the coolant chamber. **W54 closed 2026-09-08** — hover now dispatches, and with W79 the window can receive a pointer at all — so this row's hover half is testable live rather than pending. **It is one view, not the skin.** `ALXMorph`'s other seven views are healthy — `eqView` is `45 nodes, 44 commands, 26 hits, 8 unresolved` and `videoView` `35/33/12/6` — so only `mainView`, the view it opens on, is starved. That is why the skin reads as dead while its equaliser and playlist would work if you could reach them. **W70's ranking disagrees with this row about where to start.** ALXMorph scores exactly 0.50 and is one of the *milder* cases; the worst in the corpus are `Disney_Mix_Central/mainView` (2 of 25 nodes resolved), `Batman Begins/mainView` (2 of 21), `Alienware Invader/mainView` (2 of 20) and `Cablemusic/mainview` (35 of 98). Take the top of `starved.tsv`, not the top of this row. **Those four names are the pre-2026-09-18 ranking and three of them were phantoms.** The ranking was taken at its word for two phases and never checked against its own PNGs; when it was, `Batman Begins/mainView` (0.90) and `Alienware Invader/mainView` (0.90) both turned out to draw their *whole* player once their intro animation has run — Batman's is 154 frames, `WMP_RENDER_SETTLE=160`, `2 nodes, 0 commands` → `40 / 29 / 27` — and `Constantine` (0.76) and `Disney_Mix_Central` (0.72) both render substantially. What ranked them was a Skins Factory **string table**: a `<subview id="locSub">` of `<text id="locShowPl" toolTip="Show Playlist"/>` string constants, 733 of the corpus's 1,183 unresolved nodes across 87 of 184 archives, now excluded by `WMPSceneBuilder.isStringTableText`. Corpus unresolved **1,181 → 456**, starved views **14 → 2**, and 553 of 553 PNGs byte-identical. **So re-read `starved.tsv` before taking anything from this row, and settle a `0 commands` view before opening its markup** — an intro skin at the top of the ranking is the ranking working and saying nothing. **The honest ranking, measured 2026-09-18 at rev `8935e4c8`, is four rows deep and two of them are already explained**: `cyberchannel/playview` 0.50 (1 of 2 nodes), `Batman Begins/mainView` 0.50 and `Alienware Invader/mainView` 0.33 (both the intro, settle them), `Disney_Mix_Central/mainView` 0.30 (7 of 10, 6 commands, **0 hits**, 5 widgets). Everything below is 0.000. **Both of those were taken, on 2026-09-18, and neither was a starved view.** `cyberchannel/playview` — `<VIEW id="playview"><PLAYLIST/></VIEW>`, a bare list in a view that states no size — is 0x0 in WMP's own arithmetic too and can never become a window; the defect was that routing handed our playlist toggle to it anyway (commit `49f64442`). `Disney_Mix_Central/mainView`'s `0 hits` is a **frame-0 phantom**, the third after `Batman Begins` and `Alienware Invader`: `mainBack` is `visible="false"` until a 31-frame intro finishes, and at `WMP_RENDER_SETTLE=6` the view is `39 nodes, 24 commands, 14 hits` with play, prev, next, the time readout and `toggleLibrary` all dispatching. **Its "five widgets" were the real defect and nothing had ranked them** — five `<TEXT>` string constants painted on top of one another in the corner of the player, closed as W232 across 42 archives. **So settle a `0 hits` row before opening its markup, exactly as with a `0 commands` one**, and note that W232 pushes this view *up* `starved.tsv` (0.300 → 0.600) by removing five nodes from its denominator: what is left of its ratio is the string subviews' own parents, which was W231 — **closed 2026-09-19**: they author no placement and carry no bitmap, so they are grouping wrappers and the ratio is right to be left alone. Nothing in this row's remaining count is a container dragging its children in; **zero** of the corpus's 178 unresolved subviews have an unresolved parent. See the archive. **The AppKit half is cleared**: `ALXMorph/mainView` diffs to zero against its own hosted render (W71), so nothing here is an overlay defect and the whole of it is scene-side. **The expression-cascade theory is dead — measured 2026-09-08 and it was the probe.** `WMP_RENDER_EXPR` used to report 34,314 of 42,015 rows corpus-wide reaching no evaluator (82%), which was read here as the cause; 34,300 of those were **another view's** expression printed under this view's name, each already ordered and evaluated under its own view. With the probe scoped the way both evaluators are (`WMPHarness.expressionLines`), the corpus reads **7,569 / 7,569 reaching the live evaluator, zero unreached**, and `starved.tsv` does not move: 41 views / 36 skins, unchanged. Expressions are not what starves a view. All three named skins were opened and looked at: `Cablemusic/mainview` declares **no geometry expressions at all** yet carries 63 unresolved nodes and draws a nearly complete player; `ALXMorph/mainView` has 4 and all of them resolve live, and it draws its whole shell — so "does nothing" is interaction and animation (W38, W53/W54), not layout; `Alienware Invader/mainView` has 6 and all of them resolve live, and it is blank because `toggleShutter()` plays a **568-frame intro** off a 50 ms timer and only at frame 568 sets `mainBack.backgroundImage` and `mainBackGroup1.visible = true`. **Start from what `unresolved` actually counts, not from `EXPR`** — and note that a high ratio does not mean a blank view: two of the three worst-ranked views in `starved.tsv` render substantially. The evidence is `skills/wmp-skin-guide/reference/harness-history.md` § *After the cascade*. **W75 came out of it, was load-bearing here, and is now closed**: a script assignment to `backgroundImage` never reached the scene, which is exactly what Alienware's intro is made of — `Alienware Invader/mainView` now draws its full 406x380 player under `WMP_RENDER_SETTLE=32` instead of an empty PNG. Its `2 nodes / 0 hits` in the *default* state is unchanged and is not that defect: frame 0 of a 568-frame intro is still frame 0. The worst of the wider class are `digitaldj/DigitalDJ` (**91** unresolved against 101 nodes), `Cablemusic/mainview` (63 against 35), `WALL-E/mainView` (35 against 37) and `NVIDIA/mainView` (32 against 43); `Disney_Mix_Central`, `Batman Begins` and `Alienware Invader` all draw a `mainView` of 2 nodes and 0 hits. **W143 closed this family's other five windows and did not touch this row, which is the sharpest statement of what it is about.** Reported 2026-09-12 as "the playlist and eq windows are not properly contructed … there are large gaps": their nine-piece frames were collapsing both 175-wide side columns onto the corner bitmaps that carry the title bar, because `verticalAlignment="center"` was offset like a margin. Every `mainView` in the family is **byte-identical** across that fix — a non-resizable player authors no centred pieces — so `plView`/`eqView`/`visView`/`videoView`/`infoView` now draw their frames correctly while the player this row names is exactly as starved as it was. Do not read the family being "fixed" as this row moving; the dossier is `skills/wmp-skin-guide/reference/skins/alienmorph.md`. |

### W239 — **`blit=` is not reproducible across a sweep, so the only AppKit number safe to regression-diff is `outside=`**

**Why it was moved:** Instrument hygiene filed as a defect, and half of it was withdrawn in the same breath.

`blit=` is a harness number no user ever sees. The row's real hazard — that a future AppKit change produces a `blit=` diff indistinguishable from a real one — has a one-line answer the row itself supplies: stop printing it in sweeps and keep it for single-view debugging. Root-causing the drift buys nothing beyond that.

It was also opened and half-withdrawn on the same day, 2026-09-19, because its PNG half had re-measured a nondeterminism documented twice already (`randomPic()` in `Scooby-Doo_2`). The file's own preamble notes two rows in two days doing exactly this. That is a reader problem, and the lesson survives in `harness.md`; the row does not need to.

**The row, verbatim:**

> | W239 | **`blit=` is not reproducible across a sweep, so the only AppKit number safe to regression-diff is `outside=`** | **1 view measured, instrument-wide in scope**; found 2026-09-19 while closing W74 over 184 archives | `Scooby-Doo_2/infoView` reports `blit=5070`, `5042` and `5021` from three corpus runs of the *same* binary, and `5021` on three consecutive runs of that skin alone — so the variable is what ran before it in the process, not the code under test. It is `hosted=0/0`, which is what made it safe to dismiss as noise for W74: with no hosted widget, `layout()` cannot reach it. **That reasoning does not generalise and is why this is a row.** `blit=` compares the renderer's image against the view's blit of it, and `harness.md` already documents a legitimate non-zero for a split `<EFFECTS>` scene — the intermediate premultiplied buffer quantizes. What is new is that the number *moves between runs*, which makes it useless as a regression signal and, worse, makes it look like one: a future AppKit change will produce a `blit=` diff and the reader has no way to tell it from a real one. Establish whether the drift is the shared image context, an `NSGraphicsContext` left by the previous view, or accumulated colour-space conversion, then either make it deterministic or stop printing it in sweeps. Until then a capture's `blit=` is readable **only within one run**. Reproduce with `WMP_SKIN=<farm> WMP_RENDER_APPKIT=1 swift test --filter WMPRenderDumpTests/testSweepsSkinOrCorpus`, twice, and diff the `^APPKIT ` lines. **The PNG half of this row was widened into it on 2026-09-19 and is now withdrawn: it was already answered, twice, and nobody read either answer.** `Scooby-Doo_2/infoView` differs between runs because `loadInfoPrefs` calls `randomPic()` — `parseInt(Math.random() * 10)` over five character PNGs. It is recorded in `reference/harness/sweep-limits.md` § *A sweep has two nondeterministic outputs, and one of them is an image* and in W86's archive entry, both predating this row. **The finding that survives is about the reader, not the renderer**: two rows in two days have re-measured a documented nondeterminism and filed it as new, so read that section before attributing any lone collateral diff. It stays true that `Scooby-Doo_2/infoView` is the one image a corpus render diff cannot clear. **The sweep's other two nondeterministic outputs are now gone** (`d72c3970`): `loadms=` is stripped when `invariants.txt` is written and `SCRIPT inline:` breaks ties on the name, so two captures of one unchanged binary differ by 2 lines — both the `HARNESS` line naming the output directory — where they differed by 538. **That sharpens this row rather than closing it**: with the invariants quiet, a `blit=` drift is now the only thing left that manufactures a diff, and it has nowhere to hide. Reproduce with `WMP_SKIN=…/Scooby-Doo_2.wmz WMP_RENDER_DUMP=<dir>`, twice, and `cmp` the two PNGs. |

### W73 — A clean sweep still proves only the default state

**Why it was moved:** Not a task. It can never be started or closed.

"A clean sweep still proves only the default state", reach *every skin*. This is a standing caveat about what the instruments reach — true, important, and permanently open by construction. Nothing in it is a unit of work, and it has been narrowed twice (W71, W72) without ever being closeable.

It belongs in `skills/wmp-skin-guide/reference/harness.md` as prose about instrument reach, where a reader meets it before trusting a capture, rather than in a tier where it is scanned as work on every pass.

**The row, verbatim:**

> | W73 | A clean sweep still proves only the default state | every skin | **The playback half is now instrumented, 2026-09-09**: `WMP_RENDER_HOST` seeds a playing host for a whole sweep (and `NULLPLAYER_PLAY` starts a live debug launch on a track), which is what found W119 and W120 — two defects in the one state every transport readout in the corpus is authored for and no capture here had ever entered. Read the `HOST` line of such a capture before anything else in it. Narrowed by W71 and W72, not closed by them. The AppKit *overlay* class is now measured and closed — 545 hosted views, two defects, both in W74, both fixed 2026-09-19 — and every slider in the corpus is drivable. What no sweep here still says anything about: a tab, a setting, a **hover**, a drawer, the window's shape and its shadow (those live in the window server and stay a short, genuinely manual list), and anything driven by live playback. W69's flicker is in that remainder, which is why it needs its own instrumentation rather than another sweep. |

### W111 — Objects a skin declares inside `<PLAYER>` are laid out as controls, and count as starved

**Why it was moved:** Its only stated justification no longer holds.

The row says so itself: "costs no pixels and distorts the ranking, **which is the only reason it is a row**". That justification requires `starved.tsv` to be ranking work, and checked on 2026-09-19 it is not ranking this class into anything: the three views at the top are documented phantoms, and the live tail below them — `Revert/vwPL` 0.381, `Beck/view-2` 0.316 — contains **no `<controls>` node at all**. Beck's twelve are ten `<slider>` EQ bands and a `<statusText>`; Revert's eight are seven `<BUTTON>` and a `<TEXT>`.

So classifying `<controls>` and `<VIDEOSETTINGS>` as non-layout would move 133 nodes out of a denominator without changing which views rank or what anyone would look at next. W231 reached the same conclusion for `<SUBVIEW>` independently and closed rather than becoming work; this is that finding applied to the class that suggested it.

If a reason to take it reappears, it is a one-line rule in `WMPSceneBuilder.isNonLayout` and the row is cheap to reopen.

**The row, verbatim:**

> | W111 | Objects a skin declares inside `<PLAYER>` are laid out as controls, and count as starved | `<controls>` **103 nodes / 67 of 179 skins**, `<VIDEOSETTINGS>` 28 / 24, plus `durationText` 2 / 2 and `automenu` 4 / 3 as unknown tags, measured 2026-09-09 with `WMP_RENDER_UNRESOLVED=1` over the 179-archive sweep | **Costs no pixels and distorts the ranking**, which is the only reason it is a row: `starved.tsv` scores `unresolved / declared`, and ~154 of the 1,067 unresolved nodes left in the corpus are objects that were never boxes. **Re-measured 2026-09-18 after the string-table rule landed and this row is now the largest remaining block**: the corpus holds **456** unresolved nodes, of which `<controls>` is **104** and `<VIDEOSETTINGS>` **29** — together 29% of what is left, against 13% before. The rest is `subview` 180, `text` 61, `button` 49, `slider` 10, `statusText` 7, `automenu` 4. **`subview` is now answered and is not competing with this row**: W231 closed 2026-09-19 finding 171 of 178 to be grouping wrappers that authored no placement — the same shape as `<controls>`, reached independently — so if this row's one-line rule is taken, that class is the precedent for it. The `<TEXT>` string table that used to bury all of this is closed; see `skills/wmp-skin-guide/reference/harness-history.md` § *After the string table*. `<controls>` is a child of `<PLAYER>` carrying nothing but `currentPosition_onchange` handlers — `aom.wms` is the worked case — and `WMPSceneBuilder.isNonLayout` already treats `.player` and `.network` exactly that way, so this is the same one-line rule applied to two more kinds. `STATUSTEXT` and `CURRENTPOSITIONTEXT` are no longer part of this row: both are implemented as native text controls. `durationText` and `automenu` remain separate questions and need a census before a kind: decide whether each is a `<TEXT>` WMP fills in for the skin (which is drawing work, not classification) or an object. Do **not** batch them with `<controls>`. |

### W135 — Small, real, individually cheap — the SDK audit's S4 table as one row

**Why it was moved:** A junk drawer, and the row says it was assembled to game the ranking.

Nine unrelated items bundled "because splitting them would rank nine one-line changes above work that moves a screen" — an explicit statement that the row's shape is about ranking mechanics rather than about the work. A bundle cannot be taken, verified or closed as a unit, and its reach column is nine different denominators.

Two of its items already belong to other rows by its own text: `toolbarMargin` "rides with W133", and `scrollingDirection`/`wordWrap` are to be "decided together" with W94. The rest (`<AUTOMENU>`, `authorVersion`, `effectCanGoFullScreen`, `fontWeight`, `textLimit`/`editStyle`, `showBackground`) are independent `inert()` calls or small read-throughs.

**To revive it, split it**: each item is its own row with its own reach, or it is dropped. Do not re-bundle.

**The row, verbatim:**

> | W135 | Small, real, individually cheap — the SDK audit's S4 table as one row | Per item below, measured 2026-09-11 over the 177 archives | Kept as one row because each item is an `inert()` or a read-through of a few lines, and splitting them would rank nine one-line changes above work that moves a screen. `<AUTOMENU>` (own element, **4 skins**) — the Quick Access Panel, no counterpart here, so `inert` rather than `unknown`. `authorVersion` on `THEME` (16) — metadata the skin chooser could show. `toolbarMargin` on `PLAYLIST` (14) — rides with W133. `scrollingDirection` on `TEXT` (13) — the marquee axis; W94 implemented one direction. `wordWrap` on `TEXT` (10) — W94 deliberately left the vertical clip open, so decide these two together. `effectCanGoFullScreen` on `EFFECTS` (10) — no full screen for the hosted rect, `inert`. `fontWeight` on `TEXT` (10) — the engine reads `fontStyle` only. `textLimit` and `editStyle` on `EDITBOX` (8 each) — one EDITBOX use case in the corpus, `plSearchEdit`. `showBackground` on `EFFECTS` (7) — interacts with W101's "do not fill the widget's rectangle". |

### W67 — `.cur` and `.ani` cursors

**Why it was moved:** Self-described as near-worthless.

"Worth doing only with a `.cur`/`.ani` decoder, and worth almost nothing without one." That is a decline, not a backlog item — and the row records the state correctly: Windows cursor formats resolve to *no* cursor rather than to a wrong one, which is the honest failure.

Reopen only if a `.cur`/`.ani` decoder arrives for some other reason, at which point this is a small consumer of it rather than a reason to write one.

**The row, verbatim:**

> | W67 | `.cur` and `.ani` cursors | **~70 uses**, a handful of skins (`resize.cur` 26, `over.ani` 23, `sizetopright.cur` 12, `size2_m.cur` 6) | The remainder after the named cursors landed: Windows cursor formats, which no macOS decoder reads. They resolve to no cursor rather than to a wrong one. Worth doing only with a `.cur`/`.ani` decoder, and worth almost nothing without one. |
