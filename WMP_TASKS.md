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
why*.** Six classes of count here must be re-measured rather than carried forward: anything against
the 14-skin denominator, anything captured before rev `61f8955a`, any `COMPAT`/`UNKNOWN tag` number
taken before W215 closed on 2026-09-19, the stale view counts, `WMP0035`/`WMP0032`/`WMP0033`, and
**anything read out of a sweep `compare` before W245 closed on 2026-09-20**, which silently left 48
of 184 archives out of the invariants diff.

**Before issuing a number, read `docs/wmp-skin/wmp-backlog-archive.md` § *Issuing a number*.** It
holds the next free number, the two renumbered IDs (W196 → W217, W171 → W218), the `W235` source-
comment collision, and which numbers were issued and closed without ever appearing here.

## Tier 1 — views that load and then draw nothing

**Empty, and both halves of it are closed.** Tier 1a held the loading rejections (W33 closed the
last); no view in the corpus fails to lay out (W6, W8). Nothing comes back here unless a *new*
archive is rejected or a view starts drawing nothing — which is indistinguishable from a rejection
to anyone using the app, and is why the tier stays.

## Tier 1c — live-reported, not yet reproduced headlessly

**W256 was this tier's row and closed 2026-09-22** — three defects under one live report, all in
[the archive](docs/wmp-skin/wmp-backlog-archive.md). What it leaves behind is one measurement rule,
and it is the most expensive thing on this page: **a corpus number taken with `grep` is not a corpus
number.** `grep` calls a cp1252 `.wms` binary and exits 0 having printed nothing, which is how this
row came to state that `anemone` had no `<equalizerSettings>` and *"not one `slider` element at
all"* — it has both, ten of them — and how its "19 archives" (really **99 of 184**) and
`object-model.md`'s "14 name it something other than `eq`" (really **7**) were written. The row's whole
"two different surfaces" framing rested on that absence, and there was only ever one surface.
`harness.md` § *A corpus number taken with `grep` is not a corpus number* holds the rule; re-derive
any number on this page whose command was a bare `grep`.

**The "second, separate defect" this tier carried — the named `<EQUALIZERSETTINGS>` — closed with
W256 rather than taking its own number**, because it was not separate: it is what kept `elvis`'s
thumb from moving after the drag reached the control. It issued no new number. The corrected reach
is 7 of 184 archives and the rule is `object-model.md` § *The `eq` object and the element are one
surface (W39)*.

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

**Two rows opened here 2026-09-21, both reported live while W216 was being accepted; both closed
2026-09-22 and are in [the archive](docs/wmp-skin/wmp-backlog-archive.md).** Neither had a headless
signature — the first was a picture that never appears and the second is motion, and no instrument
on this page draws a second frame. **W252 is now the worked example of what does reach that class:**
it was closed against an app-side trace, `WMP_VIDEO_TRACE=1`, added in the same change and
documented in `reference/harness.md`. The trap it left behind is worth more than the fix —
**`WMP_CALL_TRACE` is a `swift test` flag and prints nothing in the running app**, so the route this
row itself recommended produces an empty capture that reads as "no member accesses".

**W253 was this tier's last row and closed 2026-09-22** — the `onLoad` tween that landed its
endpoint in one frame, because the load transaction promised no frame clock. It is in
[the archive](docs/wmp-skin/wmp-backlog-archive.md), and three things it leaves behind outlive it:
**a row's line number is a starting point, not the seam** (it named `WMPMainWindowController` ~1348,
which is `theme.openView`; the player opens on the skin-load walk at ~404, and fixing only the cited
site compiled, passed its tests and moved nothing on screen); **a skin that never settles cannot be
A/B'd by comparing settled captures** (`Alienware Invader` differed across four runs of the *same*
mode, having run zero tweens — take a same-mode control first); and **both of this row's corpus
numbers were void**, because 108 and a static walk's 67 both count markup rather than execution.
`WMP_TWEEN_TRACE=1` is the instrument the row needed and now has.

**W257 was this tier's row and closed 2026-09-22** — the view switch that landed and was put
straight back, and it was never the *switch* that was wrong. `Plus! SlimLine` declares a different
`.js` on each of its two views, both define `Init`, `savePrefs`, `switchSkin` and `EndVideo`, one
script scope serves the whole skin, and so the arriving horizontal view ran the **vertical** view's
`Init()` — whose `EndVideo()` calls `switchSkin('perfectVSkin')` and saved the seven keys the row's
trace recorded. It is [in the archive](docs/wmp-skin/wmp-backlog-archive.md) and it **spent no
second number**: it is W204's defect, and it closed the scope half of that row on the way past.

**Three things it leaves behind.** *A ruled-out suspect is only ruled out in the file you read it
in* — the row cleared `Init()` by reading `perfect.js`, and the `Init` that ran was `perfectV.js`'s;
in a shared scope, "which function is this" is a question about load order, not about the file the
markup names. *A preference write that looks like a revert may be a different view writing the
truth it holds* — nothing was reverting the global, and the two careful checks the row recorded
(no new `WMPScriptContext`, `loadPrefs`'s shadowing `var`) were both sound and both aimed at a
defect that was not there. And *`Scooby-Doo_2/infoView` draws from its own
`Math.random()`*: three captures at one setting gave two hashes. Take a same-mode control before
reading any single image out of a corpus A/B — W42 and W40 both cleared that skin the same way.

**W246 was this tier's previous row and closed the day it opened, 2026-09-20** — the
`Xbox Live Skin` playlist would not scroll because every host refresh pulled it back onto the
playing track, which was every skin's playlist and not that skin's (174 of 182 archives share the
view; the numbers and the A/B are in [the archive](docs/wmp-skin/wmp-backlog-archive.md)).

**The tier stays, and it still ranks above every other, because no instrument here reaches it.** A
sweep renders the settled default state and never scrolls, hovers, drags or plays, so a
byte-identical sweep across a change like W246's is *unmeasured*, not unchanged. Work that only a
driven app can see belongs here and outranks anything a script can rank. W246 also left the live
loop better equipped than it found it: `winhelper` has a `scroll` verb
(`skills/app-control/SKILL.md` § Route C) and a long playlist now costs one environment variable
(`skills/app-control/reference/test-data.md` § *A playlist long enough to scroll*).

**Two rows could be opened out of W246 and deliberately were not**, because neither reproduces the
report and neither has been reached for: the hosted `<PLAYLIST>` has **no scrollbar** of any kind
(no thumb, no page scroll, no drag-to-position — and the corpus authors none against it either),
and the `columns` attribute is parsed and ignored (`Xbox Live Skin` asks for
`Title;Artist;Album;Type;Length`; the surface draws title and artist). **Measure the reach of
either before ranking it** — the census command is in the archive entry.


**W260 was reported into this tier 2026-09-22 and closed the same day** — the `Stealth` elapsed
readout that never moved, because a view authoring `onTimer` with no `timerInterval` got no timer at
all. It is in [the archive](docs/wmp-skin/wmp-backlog-archive.md), and **the rule it leaves behind is
this tier's own, sharpened**: the report was *"stealth does not play files at all"* and playback was
never involved. **A dead readout and a dead transport are the same picture**, so reproduce the
reporter's *sentence*, not their diagnosis — two headless probes had already agreed the reported
thing worked (the play button was reachable, hit-tested to `action=play` and issued `command=play`),
and agreeing with them would have closed a real defect as unreproducible. The second half:
**an absent attribute is not a zero**; `authoredTimerInterval` folded "unstated" and "stated as off"
into one return value and the SDK gives those two different meanings.

## Tier 1d — what the Phase 6 instruments do and do not reach

**Empty again: W245 opened this tier on 2026-09-20 and closed the same day**, and the tier exists
because a genuine gap in instrument reach ranks above a skin-side defect when one is found. What
W245 leaves behind is in [the archive](docs/wmp-skin/wmp-backlog-archive.md) and is worth reading
before trusting any run-to-run check: **an identical "damaged" set across two runs is arithmetic,
not interleaving**, and **a flagged count that exactly matches an already-explained one names its
own cause**. The sweep's damage detector had silently dropped 48 of 184 archives from every
invariants comparison, so any figure taken from a sweep `compare` before 2026-09-20 covers three
quarters of the corpus rather than all of it. W239 and W73 moved to
[`LOW_QUALITY_TASKS.md`](LOW_QUALITY_TASKS.md); **W73's caveat is still true and still matters** — a
clean sweep proves only the default state, and a tab, a hover, a drawer, the window's shape and
anything driven by live playback remain outside every headless instrument here. It is prose in
`harness.md` § *The probe flags*, where a reader meets it before trusting a capture.

**The tier is empty of rows and stays for the same reason the others do.**

## Tier 1f — the residue of the starvation classes

**Empty: W236 was this tier's last row and closed 2026-09-20.** Both of its ids were measured and
neither was a starvation defect in the sense the tier is named for. What it leaves behind is in
[the archive](docs/wmp-skin/wmp-backlog-archive.md) and is worth reading before answering any
unresolvable attribute with a blank: **a fallback this engine does not make itself is made for it
somewhere else** — `CTFontCreateWithName` never fails, so an unresolved `fontFace` was silently
Helvetica rather than the `Arial` an unstated one takes, and `""` would have landed in the same
place. The rule is W240's and W241's one step further out: *an unusable value is an unstated value*.
The other id, `scrollingDirection`, closed as a note because **nothing in `Sources` reads it** —
check that an attribute is consumed at all before ranking what it is answered with.

**The tier is empty of rows and stays for the same reason the others do.**

## Tier 1g — the window system, not the scene

A row lands here when the defect is in `App/WindowManager.swift`, `App/AppStateManager.swift` or
`WMPMainWindowController`'s presentation path — where a window is sized, placed, restored, rescued
and reset — and would reproduce identically on a skin that renders perfectly. **The controller was
added to that list on 2026-09-20 with W244, which closed the same day**: the tier's three rules
below are about a window rather than a scene and held verbatim there, and the alternative was a size
defect filed under a drawing tier. **W217 closed here on 2026-09-20, all four gaps** — G4 on
2026-09-18, G2 and G3 and then G1 on 2026-09-20 — and it is the tier's own second rule in miniature:
neither the restore correction nor the off-screen safety net has a headless instrument, all of them
were verified by driving the app, and the sweep that would have ranked them sees the settled default
state on one screen and never a display change at all. **What G1 leaves behind is in
[the archive](docs/wmp-skin/wmp-backlog-archive.md) and outlives the row**: the seam it deleted was
clamping the *saved* rectangle when the size that lands is the skin's, so it was enforcing a rule on
a rectangle that did not survive the next statement — **check what a validation is measuring before
porting it to the right rule** — and `restoreWindowPositions`, carried on this page as the last
`.wal`-only recovery seam, turned out to have **no callers at all**. Tier 1e is its nearest neighbour and is deliberately separate:
that tier is about *which* window a surface belongs in, this one about the window's own size and
place.

**What W244 leaves behind is in [the archive](docs/wmp-skin/wmp-backlog-archive.md) and is worth
reading before trusting a dump.** Its scene was right and its window was wrong, and the harness
could not have seen that: a dump's final rebuild passes no `requestedSize` unless `WMP_RENDER_SIZE`
is set, so it honoured the script assignment the app was discarding. **A dump that disagrees with
the window is a class no sweep can rank.** The row's second question — ~33 pt of unexplained window
growth, with `HostedWindowBorderLayout` named as the candidate — **did not reproduce**: the
backed-out measurement is the authored size exactly, so there is nothing there to take.

Three rules follow, and they are why these rows do not rank against a starved view:

- **Reach is not a corpus number.** A gate on `uiMode.controllerFamily` affects every `.wmz` session
  equally, so `scripts/wmp_skin_census.sh` says nothing about it. The row below reaches every `.wmz`
  session, and rows here are ranked against each other by what a user can do about the result — a
  stranded borderless window has no route back at all, which is why W217 outranked W214 until it
  closed.
- **No headless instrument reaches it.** `WMP_PLACE_TRACE` sees the one moment a window is *placed*;
  a render dump has no screen, no second display and no restore. Verify by driving the app —
  `skills/live-ui-testing`, and `harness.md` § *Debugging a live defect*.
- **The blast radius is the other three families.** Shared code, so `CLAUDE.md`'s binding rule
  applies at its strictest: gated on the mode, never justified as a no-op, Classic and Original
  byte-identical.

**W249 moved to [LOW_QUALITY_TASKS.md](LOW_QUALITY_TASKS.md) on 2026-09-20:** its claimed docking refusal did not reproduce. The cited border trace prints before applying the size; live return trips preserved both an 822-point and an 825-point interior. See that entry for the measurements and the evidence needed to revive it.

**Empty: W214’s remaining candidate, `expectedMainHeightForCurrentHT`, is unreachable in WMP.**
All callers require `isRunningModernUI`, directly or through their caller. Removed from the active
backlog after the call-site audit on 2026-09-20; no runtime change was needed.

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

**Empty: W234 was parked in [`skins/blinx.md`](skills/wmp-skin-guide/reference/skins/blinx.md) on 2026-09-21.** The defect is real and reproduces — `Blinx`'s borrowed frame splits at every window larger than the donor's own 475x332 — but it is **not ready to be picked up**: three fixes have been built, measured and reverted, and the remaining direction changes how every hosted window is sized. The row, its measurements and the two live-QA traps are in that dossier, verbatim. Take it out again deliberately, not because it was ranked.

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
| `<VIDEOSETTINGS>` | 94 | 94 | 93 | no | — |
| `<NETWORK>` | 6 | 4 | 4 | object-only, correctly (W104) | — |

**Empty since 2026-09-21: both rows moved to [`LOW_QUALITY_TASKS.md`](LOW_QUALITY_TASKS.md) the same
day, for two different defects in the rows.** **W251** instructed that `bufferingProgress` and
`receptionQuality` be fed from the streaming player's own statistics, and that player keeps no such
statistics — a `.buffering` state and a bare `didFinishBuffering` edge are the whole surface, so the
source it named was false while the cost it described stayed on screen. **W103** had been *blocked on
a decision, not on drawing work* since W102 landed on 2026-09-10: `inert()` the four
`<VIDEOSETTINGS>` sliders, or add brightness, contrast, hue and saturation to the video path and bind
them honestly. A question is not a unit of work, and keeping it at the top of a ranked tier made the
tier read as though it had work available. **Read both entries before re-opening either number, and
re-measure — W103's reach was taken over 177 archives on 2026-09-07.**

**The rule the tier is named for is unchanged and neither move weakens it**: a surface recognised for
*routing* and not hosted draws the user an empty drawer, so a hosting row still lands before the
routing that stands NullPlayer's own window aside. W103's own prohibition outlives its row and is the
reason it could not simply be answered with a number — **do not resolve a control to a value this
player never applies**; a slider that moves and changes nothing is the worse outcome.

**The tier stays empty of rows and stays on the page**, for the same reason the tiers above it do: a
new surface, or a hosted one that stops being hosted, comes back here.

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

**W39 headed this tier and closed 2026-09-22; it is archived.** Its Reach was void in both
directions and the row is the worked example of why a row is re-measured before it is taken: the
headline member, `eq.speakerSize` at 18 skins, had been **live since the WOW/TruBass work landed**,
and the class the row called an honest `inert()` candidate turned out to be **a feature this player
already has** — WMP's crossfade is NullPlayer's Sweet Fades, 123 uses across 38 archives. **Check
whether the player has the feature before ranking a member as inert**, and **re-measure a row whose
evidence predates a change to the same subsystem**. The re-measured class, the two members that
*are* honestly inert, and the rule that an inert value the corpus reads back must be *stored* rather
than constant are in [the archive](docs/wmp-skin/wmp-backlog-archive.md) and in
`skills/wmp-skin-guide/reference/object-model.md` § *The `eq` object and the element are one surface
(W39)*.

**W42 headed this tier and closed 2026-09-22; it is archived.** All three causes it named
measure **zero** across 184 archives — every declared `scriptFile` resolves (the only two
unregistered `.js` in the corpus are leftovers nothing calls), no program in the corpus evaluates
with an error, and **no callee anywhere traces to a `res://` script**: the 118 archives that declare
`res://wmploc.dll/RT_TEXT/#132` are correctly `status=unsupported` and nothing needs it. Four of the
row's six names — `skin_init`, `loadVidPrefs`, `checkForContent`, `Init` — had already gone with
W163's basename fallback, and `gears` is an element that exists in no `.wms`. **A row's stated
*cause* can be void while its class is real**: what was left under the name was a skin calling its
own function in the wrong case, 16 of 184 archives, closed in the same change. The measurement, the
last-resort alias and the three archives that forbid a blanket fold are in
[the archive](docs/wmp-skin/wmp-backlog-archive.md) and in
`skills/wmp-skin-guide/reference/object-model.md` § *A skin's own function, called in the wrong
case (W42)*.

**W40 closed 2026-09-22 and is archived** — a script naming an element in another view. Its
recorded Reach was void in the way this page keeps finding: `vidinfo` (8 skins) and `pl` (4), the
row's two largest numbers, name elements declared **nowhere** in their archives in any spelling, so
they are W42's phantom class and not this one. Classified against the sweep's own `raw.txt`, the
47 `Can't find variable` lines are **38 phantoms / 30 archives** against **10 cross-view errors /
9 archives**, and the fix is worth exactly the second number. What it leaves behind: **a
`theme.currentViewID` switch discards both views**, so anything keyed on a view's registry has to
survive the arriving view's own discard — and the row opened **W257** behind it, because making
`Init()` reachable is what let the corpus's view-restore idiom run at all.

**W216 closed 2026-09-22 and is archived**; it headed this tier as *unmeasured* and the measurement
is the part worth keeping. The recorded reach was 2 archives, the call half came back at **31 uses /
20 archives**, and the half nobody had counted — the element's own *properties*, read and written
bare in its handlers — came back at **255 unresolved reads + 249 silent writes across 100 of 184
archives**. **A row whose Reach is a count of one idiom is a count of one idiom**: `down` alone
(196 uses / 89 archives) outweighed the class the row was named for. The scan that produced it, the
two arbiter corrections the corpus sweep forced, and the `WMP_RENDER_CLICK` reproductions are in
[the archive](docs/wmp-skin/wmp-backlog-archive.md) and in
`skills/wmp-skin-guide/reference/object-model.md` § *An unqualified name in a handler resolves
against its own element first (W216)*.

**W41 closed 2026-09-22 and is archived**, and it is this page's own re-measure rule paying twice.
The member had answered **since W115, two days before the row's other half went** — so the row as
written had been done for a fortnight — and its "4 skins" was a hand count: the honest figure is
**19 uses / 14 archives**. What was actually left was **the value, not the member**: every corpus
consumer classifies the string and every classifier is Windows syntax, so a macOS `file:///Users/…`
took the *network* branch and nine archives lit their net lamp for every local track, two with a
buffering readout behind it. **A member that resolves can still be answered with a string nothing
can read** — an `unimplemented` tally is blind to that entire class, and only the running app saw
it. The spelling, the idiom split and the two secondary defects it left (a playlist item's
`sourceURL` answering the item's *title*; the local-video path rebuilding `metadata` without it) are
in [the archive](docs/wmp-skin/wmp-backlog-archive.md) and in
`skills/wmp-skin-guide/reference/object-model.md` § *`sourceURL` is spelled the way WMP spells it
(W41)*.

**W53 headed this tier and closed 2026-09-22; it is archived.** Its reach was a hand count and short
in all three numbers (`onkeydown` is **530 uses / 80 archives**, `onkeypress` **422 / 74**, `onkeyup`
**100 / 33**), and the contract it asked to have decided turned out to be one already measurable:
every corpus handler compares a Windows virtual key code, so there was no character-versus-code
question to settle — `object-model.md` § *The keyboard*. **Two things it leaves behind.** *A dispatch
site nothing can reach measures exactly like one that does not exist* — the view took first responder
only on `mouseDown`, so an unclicked window received no key at all and the whole class was invisible;
the first live run of a working implementation printed nothing. And *a diagnostic placed after the
decision it is meant to explain cannot explain it*: the first trace printed only the dispatched case,
which made "the key never arrived" and "no skin authored one" the same empty log.

**W260 was opened and closed 2026-09-22, found while verifying W41 in the running app** — a view
authoring `onTimer` with no `timerInterval` got no timer at all, because `authoredTimerInterval`
answered `0` for an absent attribute and every caller reads `0` as *"this view has no timer"*.
`Stealth` writes its elapsed readout from that handler and nothing else, so it sat at `00:00`
through a whole track and was reported as the skin not playing. It is in
[the archive](docs/wmp-skin/wmp-backlog-archive.md). **The rule it leaves behind belongs to Tier 1c
rather than here**: the reporter's words were *"stealth does not play files at all"* and playback was
never involved — a dead readout and a dead transport are the same picture, so **reproduce the
sentence, not the diagnosis**.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W136 | SDK element methods this engine does not implement, now that they are tallied at all (W128) | `plListBox1/2.deleteAll()` **10 skins** (7 census-visible), `playlist2.copy()` 8, `playlist2.abortCopy()` 8, `playlist1.deleteSelected()` 5, `fileList.insertItem()` 3 | **Blocked on W66's media-collection decision** — every `deleteAll` call is inside the skin's own `try`/`catch` (`fillListBox()`, `warcraft.js:1584`), and the box has nothing to put in it until `player.mediaCollection` answers. This row is what that decision would let the skins actually do. **The census sees only `deleteAll`**: the rest sit in click handlers, so measure them through the live loop or a click-driving sweep before ranking them against each other. Reproduce by tallying `UNRECOGNISED` in `render.txt`. |

### 2c. Events the markup declares and nothing ever raises

An entry here is markup asking for something. **Classification is one line; the dispatch site is the
real cost, and it is different per event.** Do not add a name to `handlerNames` or `supportedEvents`
without its dispatch site — the rule, the instrument that made this class visible, and the 4,114-use
measurement are in `object-model.md` § *Recognising an event is not dispatching it*.

| ID | Item | Reach | Notes |
|---|---|---|---|
| W56 | Video and playback-position events | `onvideostart` 190/140, `onvideoend` 132/130, `onpositionchange` 147/41 | Not blocked: W102 supplies the hosted video surface and W124 the live/event-state split, so the `onvideostart`/`onvideoend` half is directly measurable. **`currentposition_onchange` closed with W129 and must not be re-opened as a rendering row** — it changed no pixel, and that is the measured finding; `object-model.md` § *Ambient `<attribute>_onchange` handlers* says why. |
| W121 | A handler that reads the `event` object | **30 handlers across the Skins Factory equaliser family**, measured 2026-09-09; unmeasured for the other event kinds | Not blocked, and **smaller than it was: the key half closed 2026-09-22 with W53**, which bound `event.keyCode` — 405 of the 409 `event.` reads in a key handler, measured. What is left is the mouse and `value_onchange` half, where `event.shiftKey` is already answered from the live modifier flags, so **re-measure before taking it**: sweep the corpus's handler attributes for `event.` and split by event kind. Evidence: `object-model.md` § *Event arguments* and § *The keyboard* (W53). |

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
| W204 | The residue of per-view script scope: a *value* a second `scriptFile` overwrites, and the six archives verified only on paper | **7 of 184 archives** name a different `.js` per view where two of them define the same top-level function (`Plus! SlimLine` 17 contested names, `holiday_skin` 22, `Sports` 6, `pharaoh` 2, `portals` 2, `corona`/`9SeriesDefault` 1) — re-derived 2026-09-22 with a BOM-sniffing decoder, which is the whole census: the first pass read two CP1252 files as UTF-16 and reported 3 | **The function half closed 2026-09-22 with W257** — `WMPScriptContext.applyFunctionScope` binds a contested name to the installed view's own programs; see [the archive](docs/wmp-skin/wmp-backlog-archive.md). What is left is deliberately smaller than the row was. **(a)** Top-level `var`s are still one variable in one scope, and no corpus skin has been shown to need otherwise — **measure a case before scoping values**, because two views' `Init`s writing one flag is also how these skins share state. **(b)** Only `Plus! SlimLine` (live) and `holiday_skin` (sweep) were verified; the other five are unverified in a *driven* state. Reproduce with `WMP_RENDER_HOST=playing` and `WMP_VIEW_SCRIPT_SCOPE=0` as the A/B. Evidence: `skins/pharaoh.md` § *Still open*. |
| W149 | Controls still unreachable after W148, each for a different reason | **11 total**, re-measured 2026-09-12 after W150 (was 16) — `Sports` 7, `anime`, `STALKER`, `T3-Skynet_Media_Player`, `Plus! Professional` | Not blocked, and **smaller than it was: the `<BUTTONGROUP>`-with-no-mapping-children half closed 2026-09-22 with W259**, which took the corpus from 180 occluded rows to 165 and recovered 16 controls. **Re-measure before taking what is left** — the 11 predate it. **Name the node before ranking the count.** Reproduce with `WMP_RENDER_OCCLUDED=1` and read the `reached=rect-only` lines. Evidence: `harness.md` § *The residue `WMP_RENDER_OCCLUDED` does not explain (W149)*. |
| W203 | `<DURATIONTEXT>` never renders | **2 nodes in 2 archives** (`pharaoh`, `circle`) — a one-line row kept only because it is a *visible* readout on a shipped Microsoft skin | Not blocked. The missing piece is a glyph-height fallback this one tag does not get — `<currentPositionText>` beside it declares no `height` either and resolves to 45x10 — **so a `<DURATIONTEXT>` anywhere is dead, not just this one**. Evidence: `skins/pharaoh.md` § *Still open*. |
| W123 | A stretched `backgroundImage` and a natural-size foreground image draw the same bitmap at two different sizes | **1 view measured** (`Ice/videoView`); the wider class — every `backgroundImage` whose frame is not its bitmap — is **unmeasured** | Blocked on its own measurement: **measure the class before changing the rule**, and **not with W240**, which closed 2026-09-20: `Radio` left that row when `corner_pieces.bmp` was measured absent from its own archive, so the two never shared a skin and this row stands alone. It cannot be answered by extending W122, and `skins/README.md`'s counter-evidence table comes first. Evidence: `SKILL.md` § *Static scene and image contracts*. |
| W145 | A borrowed window frame is rendered from markup, so it never follows the theme the skin is *set* to | **`xsn_sports`** measured 2026-09-12; the pattern is stacked variants and is **unmeasured across the corpus** | Not blocked. **The fix is to run the donor view's `load` off-screen** and build the ring with the overrides it commits, keeping every candidate per ring role rather than the first declaration — settling on the chosen colour and **not** animating the phase. Evidence: `skins/xsn-sports.md` § *Defects it found (2026-09-12, borrowed window frames)*. |

## Closed

Closed entries live in [`docs/wmp-skin/wmp-backlog-archive.md`](docs/wmp-skin/wmp-backlog-archive.md),
verbatim and with their evidence. Move a row there in the same change that closes it — one left here
reads as open work.
