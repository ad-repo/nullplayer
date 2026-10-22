# Winamp Modern (`.wal`) — Corpus Runner Plan

**Status (2026-10-19): instruments frozen; the work is fixing.** The corpus tooling is built and
documented in `skills/winamp-modern-skin-guide/reference/harness.md`. What is open is the backlog
in `tasks/WINAMP5_TASKS.md` — that file, not this one, records what is done.

## The loop

1. Take the top row of *Corpus plan queue* in `WINAMP5_TASKS.md`. Skin-dead loader gaps
   (B175–B181) first, then the MAKI method rows (B182–B201, B206–B207).
2. Batch rows that share a seam — several effort-S method rows are one session.
3. Implement, with a unit test per method or loader rule.
4. Re-measure: `scripts/wal_demand.sh` for method rows, the quarantine census for loader rows, and
   the sharded render sweep (`scripts/wal_render_sweep.sh --shards 10`) as the regression gate.
5. Close the row into `backlog-archive.md` with its before/after number. Nothing else to update.

**No new instruments.** A row may need a probe to find its cause; that probe serves the row and is
not a plan step. Parked (§7): the rest of the menu sweep, state-space enumeration, the
supported-surface manifest. Re-open one only when the queue runs dry or a fix needs it.

**Parked rows:** B208–B210 are investigations from noisy suspect rules (a `Timer` also drives clocks
and tooltips). Re-run `wal_motion_sweep.sh` / `wal_interaction_sweep.sh` after the method batch
lands — many of those suspects are handlers aborting on the methods above — and only then decide.

### Done: the B169 intake, promoted to gold (2026-10-22)

The 25 skins B169 admitted to Silver were tried in the app, fixed skin by skin, and **promoted to
gold on 2026-10-22** (manifest tier, files moved to `WinampModernCorpus/gold/`), with rows on
`skin-compatibility.md` (24 B, 1010 Fullscreen C). Each fix is
general, so it applies to every skin with the same shape, named after the skin that showed it.

| Skin | What was wrong | Fix (where) |
|---|---|---|
| Mac OS X Panther, New_Night | A library or browser wider than either side of the player was clamped onto the player. | The tiler also tries the region's corners and takes the least-covered candidate, counting the player 4× (`WinampModernTiler`, `App/WinampModernTiler.swift`) |
| CopperdeckII | Every window hung 178px off the player; the shade collapsed to 1px; the video window opened 2147 wide | Tiling uses the player's `snapadjust*` edges; a `linkwidth` entry keeps the entered layout's declared height; the content fit ignores an axis the skin sized with an absolute number |
| Anunaki | The LCD was empty | A sizeless `<CustomObject>` takes the size of the group it hosts |
| WinampAzenis2 | Switch, Prev, Next and the search buttons were blank | A plain `<button text=…>` draws its label; an `embed_xui` wrapper passes its label down |
| NEO_CLASSIC | The 259px album-art pane was missing; the invisible crossfade toggle drew a font sheet | A sizeless group redefinition keeps the earlier size; a bare `image=` falls back only when `activeimage` is set |
| Symplicipod | The library mounted twice (once blank white) and the playlist had no window | A container's actual contents outrank a `component=` that contradicts them; `:componentname` resolves inside a longer title |
| Official_Tristania | The ticker drew small, in the default font | An `embed_xui` wrapper passes typography down to its `<text>` |
| BOOM (97 skins) | Window titles were not uppercased | `forceuppercase`/`forcelowercase` |
| krazyPlayer | Every frame title read `@COMPONENTNAME@` | `@COMPONENTNAME@` resolves |
| Prakrit | The equalizer window was an empty frame; the player body was see-through | A plain `<group>` gets `onSetXuiParam` for the params it does not use itself; a `sysregion="1"` `<rect>` is backed black |
| Simple | Every button drew its symbol's group id as a label | `onSetXuiParam` arrives in document order |
| Nitrous_Audio_CTI_2_Glass | Monitor mode never moved; the title bar was under the menu bar | Only a write after its own origin was read counts as a round trip (B61); monitor height leaves out the menu bar |
| 1010_Fullscreen | The transport left the canvas; the window was taller than the screen | `getGui*` on a relative axis returns the skin's markup value, not the resolved box; viewport is the work area; a window taller than the screen keeps its top on screen |
| --Vortex-- | The 505-wide player became a 180×1169 strip | A write to a layout that is not showing is not applied to the window; winhelper crops a glued window group |
| Alpha_Media_Player_X5 | The player scaled itself past both screen edges | A skin's `setScale` is capped at the largest UI Size that fits on screen |
| wTunes | The right 25px were cut off | Layout sizes are trimmed (`w=" 300"`) |

Second pass, the remaining eight (Dronev11, JRS, shark5, cPro2__minimal_1_1, Zygote,
CPro_Winamp_for_Mac_Sync, LogicallityV1_0, machina):

| Skin | What was wrong | Fix (where) |
|---|---|---|
| machina | The help window drew on the bare desktop; its switch button drew 0 tall | A standard frame in a backgroundless layout paints `wasabi.frame.basetexture` (`WasabiRenderer.frameBaseTexture`); a labelled `<Wasabi:Button>` with no `h` is 20 tall |
| machina | An empty video window opened at launch, missing from the Windows menu | The B97 video exemption reads the container's own `hold=` — the catalog is not built yet at that point (`applyDefaultContainerVisibility`) |
| JRS (~220 skins) | The playlist had no Add/Rem/Sel/Misc/List anywhere | A playlist frame's `<LayoutStatus>` gets the command bar, hidden where the skin has its own `PE_Add` (`WasabiStandardFrames`) |
| Dronev11 | The compact player could not be dragged anywhere | Ghost artwork is window: `hitTest` counts it and `pressTarget` hands the press to the layout (`WinampModernMainView`) |
| Mac OS X Panther, Core-X5, Ebonite | Cover windows never showed a cover, local or streamed | One recogniser for "a cover beside the playing file, or the file itself" answers all three script families from the host's artwork, a late cover is offered again, a missing `Map` is 64x64, `new PlEdit` is the singleton (`WinampModernTrackFolderImage`) |

The other skins showed nothing more on a first look. Left: Dronev11's playlist info sits high in its
bar (cosmetic), and its own cover script (`behaviors.m`, `file://` only) still finds no cover. Filed from the code review: B216 (check `.wmz`
placement after the tiler change, then move the tiler out of `WindowManager.swift`) and B217 (one
type-name accessor; one button-label rule).

Third pass, at promotion (2026-10-22):

| Skin | What was wrong | Fix (where) |
|---|---|---|
| Nitrous_Audio_CTI_2_Glass, 1010_Fullscreen, ClassicPro maximize | Monitor/party mode opened 1.35× the screen at 135% UI Size | `getScale()` answers UI Size (`hooks.uiScaleQuery`); the skins size to `viewport / getScale()` |
| 1010_Fullscreen, corneramp_redux, Shield_Amp | EQ bands bunched left; theme buttons cut to "Pr…" | A literal `relat*="%"` is percent mode (`WasabiGeometry.percentFlag`) |
| 1010_Fullscreen, impulse | Clock colons drew as gaps | A bitmap colon draws its whole atlas cell; only the advance narrows to `timecolonwidth` (`BitmapRun`) |

Left open on 1010 Fullscreen (graded C): its song title draws ~12px low and overlaps the clock.
Aligning skin-shipped TrueType by cap top fixed it and moved ~50 other skins wrong (corneramp, Winamp
2000, CPro for Mac), so it was rolled back; the cause is unknown without a Winamp reference.

**Next:** `feat/wal-corpus-scale` (B169 intake → gold, B233) goes to PR. Then `fix/wal-scale-events`
(B238, B239), then intake #2 on `feat/wal-intake-2` — re-weight gain first (§8 *Progress*, B169
entry: count a new tag once, `tag@attr` only on known tags). B212 needs a second display; B216's
`.wmz` census waits on a go-ahead.

### Branch strategy for the intakes (2026-10-22)

`feat/wal-corpus-scale` ran to 103 commits because it held the intake, the promotion, refactors
and fixes at once. One intake of 25 took about a week of in-app work, and ~950 candidates remain
(827 bronze + 54 quarantine + new crawl finds), so at that pace the whole set is ~38 weeks. The
branch shape has to make that sustainable:

- **One branch per intake, cut from `origin/main`**: `feat/wal-intake-<n>`. It holds the
  re-weighting or rule change (if any), the intake run, the manifest update, and that batch's
  in-app fixes. Nothing else rides along — a backlog row unrelated to the batch gets its own
  `fix/…` branch, and non-`.wal` work (marketing, other subsystems) never lands on an intake branch.
- **PR at two checkpoints, not one**: (1) *admitted* — `wal_intake.sh` run, manifest committed,
  sweep baseline green; (2) *promoted* — the in-app pass done and the batch moved to gold. A batch
  that runs past ~a week PRs what it has and continues on a fresh branch.
- **Merge `origin/main` in every few days** while a branch is open; never rebase a branch others
  may have pulled. Before opening the PR, confirm `gh pr view <N> --json files` matches the work.
- **Small rows found during a pass** (like B238/B239 from intake #1) are filed, then fixed on a
  short `fix/wal-<topic>` branch between batches, so the next batch's in-app pass doesn't trip on them.
- **Push with an explicit upstream** (`git push -u origin <branch>`); a branch tracking
  `origin/main` is one bare `git push` away from main.

**Not every candidate gets a week's share.** By the B169 curve only 123 candidates cleared gain ≥ 3
and 594 added nothing. Every fix is general (see the tables above), so a skin that adds no feature
is covered by the fixes its look-alikes earned. Intakes run while a batch still clears the gain
floor (re-measured after the re-weighting); once it doesn't, the rest is certified by the census
and the pre-merge render sweep, with a hand pass only where `wal_reach.sh` shows a feature that no
gold skin has.

Below is reference: the pipeline as designed (§3), what was built (§7), and the corpus-scale
decisions (§8).

---

## 3. The pipeline

Five stages. Every stage is headless, unattended, and emits **JSON** — the human-readable text dumps
stay for drill-down, but triage at corpus scale has to be queryable. Target: point it at a folder of
N skins, walk away, come back to a ranked table.

### S0 — Ingest and tier the corpus

Skins are **never committed** (see the provenance rules); the corpus lives in a local folder plus a
committed *manifest* of names + SHA-256 + source URL + observed licence, so runs are reproducible and
comparable between machines without redistributing anything.

Three tiers, and they earn different amounts of attention:

- **Gold (~10–15)** — the ones we have fixed and understand. Pinned in the regression sweep by render
  hash. Today: the nine in `skills/winamp-modern-skin-guide/skins.md`. Each Gold skin also gets a **reference
  capture** recorded once — the author's own `screenshot.png` if the archive ships a usable one, plus
  any demo video or skin-site gallery page. The archive can tell you what a skin *contains*; only an
  external reference tells you what it is *supposed to look like*, and that is the only ground truth
  Class B has. Defix's multiple animated VU displays were discovered from a YouTube video, not from
  anything in the repo.
- **Silver (~50–100)** — deliberately chosen for *diversity*, not popularity: one per era, per skin
  family (Bento/cPro, mmd3-style, standard-frame, single-window SUI), per feature cluster (heavy
  animation, script-built UI, own-EQ, own-library). This is the measurement corpus that drives ranking.
- **Bronze (all the rest)** — smoke-loaded only, for the load/crash/limit statistic. A skin here never
  gets individual attention; it exists so "does an arbitrary skin load?" is an answered question.

### S1 — Load census

Every skin, headless, through `WinampModernSkinLoader`. Emit per skin: level (`full`/`degraded`/
`unsupported`), findings by category with counts, container/layout topology, node counts, resolved vs
unresolved bitmaps, hard failures with their `WalSourceLocation`, wall time, peak memory.

This is nearly free — `WinampModernCompatibilityReport` is already `Codable`, and the loader is already
the single headless entry point. **Build this first.** It converts "some skins fail" into a
distribution, and it is also a standing fuzz corpus: any trap, hang, or limit breach on real-world
input is a security bug, not a compatibility one, and jumps the queue.

### S2 — Static demand extraction (the missing instrument)

The key insight: **a skin declares what it needs, and you can read that without running it.**

- **MAKI:** every program carries a method table (`MakiProgram.methods` → class GUID + lowercased
  name). Parse-only, no execution, no events to drive. `staticDemand − implemented(signature(for:))`
  is a complete per-skin list of methods the skin *can* call, including every path nobody ever clicked.
  This alone dissolves the "the blocking list is a queue, not a set" problem at corpus scale: the queue
  only exists when you discover demand by execution.
- **Wasabi XML:** census the expanded document (see [Appendix A](#appendix-a--how-do-we-even-know-what-functionality-a-skin-contains) for the full inventory) — every tag name, every attribute name per tag, every
  `action=` value, every `display=` binding. Diff against a curated **supported-surface manifest**
  (tag → attributes we actually honour). Authoring that manifest is the one genuinely new piece of
  work here, and it is worth it: it is also the thing that makes "unimplemented" reviewable instead of
  folkloric.

Static demand is an *upper bound* (a skin may never take that branch) and the runtime tally is a
*lower bound*. Rank on static, confirm impact with runtime — the gap between them is itself the signal
for "which of our stubs are lying".

### S3 — Motion and interaction census (animations + custom controls)

This is the stage aimed squarely at the user-visible complaint. Two sweeps, both fully automatic:

**Motion sweep** — and it has **two independent time axes**, which is the thing to get right or the
sweep manufactures false suspects:

- **The render clock** (`RENDER_CLOCK`). `WasabiAnimation` makes an animated layer's play head a pure
  function of elapsed time since `play()`, so a pinned clock ladder does capture pure sprite animation
  deterministically.
- **Wall time and the run loop** (`RENDER_SETTLE`). Anything driven by a script `Timer` — Love is War
  Miku's whole opening animation (a 300 ms timer moving the display panel and character), Defix's
  `if (anim.isRunning()) return;` gated tab transition — advances only when the run loop is actually
  pumped. A ladder that moves the render clock and never pumps reports both of those as **dead**.

So each rung is a *pair*: settle for the wall-clock interval, then render at the matching pinned clock
(t = 0, 0.25, 1, 4 s). Hash each frame and record a per-object frame/attribute delta. Note the known
caveat from Phase 26 — pumping can also let a timer *undo* a transition — so a rung that goes back to a
previous hash is "timer-reverted", not "static". Then cross-reference declarations:

> A skin declaring `animatedlayer` / `autoplay` / a script `Timer` whose pixels are **byte-identical
> across the ladder** is a suspect. Zero motion where motion was declared is the machine-detectable
> signature of a dead animation.

That converts "lots of animations don't work" from an impression into a per-skin, per-object list —
and it distinguishes the three real causes (never played, played but not repainted, played but drawn
at frame 0) which currently look identical on screen.

**Interaction sweep** — for every object a script hooks a mouse event on, drive input and record: did
the hit test reach it, did a handler run, did it fail on a missing method, did any attribute change
anywhere in the graph, did any pixel change. Emit the **dead-control list** per skin.

"Click the rect centre" is not sufficient input, and assuming it is would mark whole categories of
working control dead. The sweep needs **gesture classes**, chosen from what the object declares:

| Control shape | Gesture |
|---|---|
| Button / togglebutton / `rectrgn` trigger | click, and **double-click** where a handler exists |
| Slider / seek / volume strip | **press → drag → release** along the control's axis. T800's volume is a layer whose own script owns the drag and tracks the mouse across a strip most of which its region has clipped away |
| Rotary knob (`Map`) | drag an **arc**, and expect the script to read `getMousePosX`/`Map.getValue` — a centre click carries no angle and legitimately does nothing |
| Anything with a script `onRightButtonUp` | right-click, and capture the menu it builds |

**Menu sweep** — menus deserve their own pass, because there are two unrelated families and they fail
differently:

- **Script-built** (`new PopupMenu` + `addCommand`/`addSubMenu`/`popAtMouse`/`popAtXY`). Implemented,
  and a right-click gesture surfaces one that fails to open at all.
- **Host menus** (`action="MENU" param=…`). The skin is asking *Winamp* for a menu we may simply not
  have. The playlist ADD/REM/SEL/MISC buttons are the known case: they draw, they hover, they respond,
  and nothing opens. Detected statically from the `MENU` param census above — no run required.

The gap the click sweep alone leaves is **what is inside a menu and whether choosing it does
anything.** A menu can open, look correct, and have every item dead — Love is War Miku's visualization
menu writes `oscstyle`/`fliph`, so its items "appear to do nothing" even though the menu itself is
perfect. That is invisible to any sweep that only checks whether a menu appeared.

`WinampModernScriptRuntime.popupPresenter` is an injectable closure returning the chosen command id,
which makes the fix cheap: the harness installs its own presenter that (a) captures the entire built
tree — titles, ids, checked/disabled state, submenus — instead of showing an `NSMenu`, and (b) answers
command *k* on successive runs, so **every item gets selected** and its effect measured with the same
instruments as a click (handler chain, attribute deltas, pixel deltas, missing-method failures).

The output is a per-skin **menu inventory**: menu → items → per-item outcome (works / silent no-op /
blocked on an unimplemented method / host menu we do not provide). That is the artifact that answers
"Defix has several menus and one of them works" with a list instead of an impression.

Two sampling rules that go with it: pick the point from the object's **artwork alpha or declared
region**, not the rect centre (a centre pixel can be transparent, or outside the region entirely), and
supply a real mouse position at the point so `isMouseOverRect` and the `Map` lookups answer truthfully.
Pump the run loop between gestures, or a timer-gated control measures as one that only works once.

Both sweeps deliberately provoke the runtime demand that S1 cannot see. Expect the post-sweep
compatibility report to be much larger than the load-time one — that is the point.

### S3.5 — State-space enumeration (the part that finds what nobody knew was there)

Both sweeps above explore **one** state: the skin as it comes up. That is not the skin. Defix ships
**nine display styles** — the cassette is only the default, and several of the others are animated
analog VU meters — plus 31 background materials, all selected from its own configurator, all behind a
`TOGGLE` that was itself unreachable until Phase 26. A motion sweep of the default state renders the
cassette, reports it animating, and says nothing at all about the eight other displays. The engine's
own record of this is one line in `skins/defix-hi-end-200.md` ("the analog VU meter styles configure a per-pixel warp we
accept and ignore"); nothing has ever rendered one.

So enumerate the states, and get them from the skin itself:

- **Layouts** — every `<layout>` of every container, not just the default one (shade, mini, alternate
  arrangements).
- **`cfgattrib` value spaces** — every config attribute the skin registers, driven through its range.
  Booleans are two states; enumerations are discoverable from the configurator's own controls, since
  each declares the attribute it writes and the value it writes.
- **Tabs, drawers and script-switched groups** — anything the interaction sweep found that changes
  visibility. Explore breadth-first from the default state and record the transition that got there.
- **Script-invented preference spaces** — the hard case. Defix builds background ids by prefixing
  `getPrivateString(getSkinName(), "BG", "")`, a value that exists only once its configurator has been
  used. These are **not** statically enumerable in general, but the candidate values are usually
  sitting in the MAKI constant pool (the string variables the program ships), which is worth harvesting
  as *suggestions* even though it is a heuristic rather than a proof.

Then re-run the motion and interaction sweeps **per state**. This is the stage that turns "we support
Defix" into "we support one of Defix's nine displays, and here are the eight we have never drawn".

### S4 — Aggregate and rank

Invert everything per-skin into corpus-wide tables:

- **Demand index:** capability → number of skins that declare it, split Gold/Silver/Bronze, with a
  sample of skins to test against.
- **Impact score per skin:** a crude but honest "how dead is this skin" — `unresolved bitmaps`,
  `dead controls / interactive controls`, `still objects / animated objects`, `surfaces routed to
  classic fallback`.
- **Coverage per skin — the metric that would have found the VU meters:** *what fraction of the
  objects this skin declares has ever been made visible in any explored state?* A skin whose default
  scene draws 69 of its 240 declared objects is not a skin we have measured; it is a skin we have seen
  the front page of. Rank low-coverage Gold/Silver skins for state-space work the same way missing
  capabilities are ranked, and treat a large declared-but-never-rendered set as an explicit unknown
  rather than as absence of a problem.
- **Severity classes**, in descending order, because they are not comparable:
  1. **Skin-dead** — fails to load, crashes, or renders nothing
  2. **Surface-dead** — a whole window/tab/pane blank or unreachable
  3. **Control-dead** — individual controls inert
  4. **Motion-dead** — animation declared but static
  5. **Cosmetic** — wrong colour, wrong metrics, wrong font

**Ranking formula** (deliberately simple, tuned by hand afterwards):

```
priority = skins_affected × severity_weight × visibility ÷ est_cost
```

with `severity_weight` from the ladder above and `visibility` distinguishing "on the main window at
rest" from "three clicks into a configurator". Publish the top 20 as the work queue. **The queue is
the artifact** — no phase should start without pointing at a row in it.

---

## 7. Build order (frozen 2026-10-19)

Built:

1. **Corpus runner + S1 load census** — `wal_skin_census.sh`.
2. **S2 MAKI static demand** — `wal_feature_index.sh`, `features.tsv`.
3. **S4 aggregation + demand index** — `wal_demand.sh` (B182–B201).
4. **S3 motion sweep** — `wal_motion_sweep.sh`, `impact.tsv`, `ranking.tsv` (B209–B210, parked).
5. **S3 interaction sweep, click and drag gestures** — `wal_interaction_sweep.sh` (B206–B208).
7. **Pre-merge gate** — the sharded render sweep, ~25 s over Gold+Silver.

Parked, not owed: arc and right-click gestures, the menu sweep and its inventory, host-menu
detection, S3.5 state-space enumeration and coverage, the supported-surface manifest and XML
census, motion hashes in the gate.

---

## 8. Scaling the corpus past ~1,000 skins (locked 2026-10-19; built 2026-10-19 — history)

**History.** B166–B172 are closed into `backlog-archive.md`, and every command below is documented
in `reference/harness.md`, the copy to keep current. The decisions stand; the instructions to
sessions are spent.

**Why.** `scripts/wal_corpus_crawl.py` found 906 modern skins not in the 89-skin corpus
(winampheritage, archive.org `winampskinsmodern`, wincustomize). Admitting them as-is breaks every
corpus-wide action, so S0 is finished as below and the actions are re-scoped by tier. The work was the
**B166–B172** rows, in that order; this section is their spec, and each
row is closed against its own done-criterion.

**Update this section at the end of every session that touches it** — this is a multi-session plan and
the only record of where it stands. Mark the row's progress in `WINAMP5_TASKS.md` (or close it into the
archive), and record here any decision a measurement changed, with the measurement. A session that ends
without that update leaves the next one re-deriving it.

**Then hand the session's skins over for in-app evaluation.** Every skin the session admitted to
Silver or Gold is **copied** (never moved) into `~/Library/Application Support/NullPlayer/WinampModernSkins/`,
the app's own skin folder, so the user can try them in the app; the session's closing note lists them
by file. Copied, because the corpus copy is the measured input and must not change with the user's
use of the app. A session that admitted no skins (B166–B168 do not) hands over none, and says so.

### How deep each skin is evaluated

Three depths, and only the first is part of this plan for every skin:

1. **Automatic first round — every candidate, every tier.** The census (load, rating, surfaces, hosted
   windows) plus the static feature index. Headless, deterministic, no human. This is what rates and
   admits a skin (B169).
2. **Targeted runs — any tier, by selection.** Impact-selected sweeps (`--touching`, B170) re-render the
   skins a change could affect. Still automatic.
3. **Full audit — Gold, and Silver on request only.** The live pass and the hand letter
   (`/wal-skin-report`). Never for Bronze, and not part of this plan's work; admission to Silver makes a
   skin eligible for an audit, not owed one.

B166's per-skin log files are none of these — they change *where* the existing dump output is written
so a corpus run can't lose lines, not *what* is measured.

### Progress

- **B166 closed 2026-10-19.** Every skin's dump lines go to `png/<skin>.log`; two consecutive
  89-archive passes had zero damaged logs and matched the stdout-era pass for every skin it had not
  damaged. The table row "Damaged logs" below no longer scales with the corpus: there are none to
  re-run. No skins admitted, so none handed over. Next: B167.
- **B167 closed 2026-10-19.** The corpus is copied to `WinampModernCorpus/{gold,silver}/` (56 + 33)
  and recorded in `corpus-manifest.tsv`; every corpus script defaults to gold+silver. A sweep over the
  new location matched one over `WinampModernSkins/` at the same rev bar the two documented
  nondeterministic items. **Decision changed:** Gold is the `skins.md` status-table set, 56 archives,
  not ~10–15 — the table is what we have worked on. `WinampModernSkins/` still holds all 89 until the
  user prunes it to their own installs; nothing reads it as the corpus any more. No skins admitted, so
  none handed over. Next: B168.
- **B168 closed 2026-10-19.** `scripts/wal_feature_index.sh` writes `features.tsv` (`harness.md` →
  *The static feature index*). It ran over gold+silver (89, all load) and the 906 candidates (54 do
  not load and keep their XML rows) with no skipped skin, byte-identical twice, and four archive
  reach figures reproduced against an extract-and-`rg`. **Decision changed:** the MAKI half reads
  every `.maki` the archive ships as well as the bound programs, because a script in an
  uninstantiated `<groupdef>` is never bound at load — exactly the demand S2 is for. For B169: value
  should count `maki-*` and `xml-*` features but not `family`/`load`, and the bronze/quarantine split
  can start from the 54 `load failed` rows. No skins admitted, so none handed over. Next: B169.
- **B169 closed 2026-10-19.** `scripts/wal_intake.sh` rated all 906: **25 silver, 827 bronze, 54
  quarantine** (the 54 `load failed` rows). Two runs byte-identical, 48 min each — the census's
  hosted pass is ~40 of that, ~2.5 s a skin, so a full Bronze census is a batch job as planned.
  Post-admission sweep (the new baseline): 114 skins, 93 s of test time, the 25 new ones 28 s of it
  (~1.1 s a skin). **Gain curve** (new features per pick, first 60): `290 131 125 103 97 94 93 91 91
  81 72 62 61 52 52 47 42 39 39 37 36 35 35 34 33 | 31 30 27 24 23 21 19 19 19 18 17 17 17 16 16 16
  16 15 15 14 14 14 13 12 11 11 10 10 10 10 9 9 9 9 9`; 123 candidates clear gain ≥ 3, 55 clear 10,
  594 add nothing. So **the budget of 25 bound, not the gain floor** — rank 25 still added 33.
  **For the next intake, re-weight gain before raising the budget:** ~1,600 of the ~2,000 features
  the picks added are `tag@attr`, so one new tag with its attributes scores ~15 (rank 25, `machina`,
  is two new tags; rank 60 is one), and a typo (`container@miminum_h`) scores 1. Count a new tag once,
  `tag@attr` only on tags the corpus already has, and the gain floor becomes a real filter. Handed
  over (copied into `WinampModernSkins/`): the 25 silver files listed in the B169 archive entry.
  Next: B170.
- **B170 closed 2026-10-19.** `--touching <feature,…> --index <features.tsv>` sweeps every tier's
  skins whose index rows name a feature (`Wasabi:Frame`: 9 of 995, exact); `--shards K` splits the
  sha256 order over K `xctest` processes after one build. Gold+silver: 81 s at K=1, 30 s at K=4, 22 s
  at K=10, memory flat at under 3 GB, every K equal to K=1 bar the known nondeterministic pair. The
  core count is the ceiling, so **use `--shards` = cores** (10 here). **Decision changed:** shards
  run `xcrun xctest` on the built bundle, not `swift test` — SwiftPM's `.build` lock serialised K
  `swift test`s to the K=1 time. The pre-merge gate is now ~25 s, so the Silver budget is no longer
  bound by sweep time at this corpus size. No skins admitted, so none handed over. Next: B171.
- **B171 closed 2026-10-19.** `scripts/wal_reach.sh <kind> <regex>` prints reach per tier with the
  manifest rev, from an all-tier index at `WinampModernCorpus/index/features.tsv` (995 skins, 375,489
  rows). It reproduced B170's `Wasabi:Frame` 9 (4/1/4) and a per-file `getEndFrame` count (3/2/20).
  **Decision changed:** the manifest lists four byte-identical archives twice, in gold and as silver
  re-adds, so tier is joined by content and a duplicate counts once at its better tier — silver's
  denominator is 54 distinct skins, not 58 rows. No skins admitted, so none handed over. Next: B172.
- **B172 closed 2026-10-19.** The docs name `WinampModernCorpus/` as the corpus and
  `WinampModernSkins/` only as the install folder; the tier rules and the hand-over copy moved into
  `harness.md`, and the triage playbook's §3 marks S0 and S2 built. No skins admitted, so none
  handed over. §8 is complete.

### Decisions (fixed — re-open only with a measurement)

- **The corpus leaves the app's skin folder.** `WinampModernSkins/` is the importer's install folder
  (`WinampModernSkinImporter.swift`), so everything in the corpus is in the user's skin menu. The corpus
  becomes `~/Library/Application Support/NullPlayer/WinampModernCorpus/{gold,silver,bronze,quarantine}/`;
  `WinampModernSkins/` goes back to being the user's own install.
- **The manifest is the source of truth for tier**: committed `docs/winamp-modern/corpus-manifest.tsv` —
  `file, sha256, tier, source_url, internal_name, admitted_rev`. Skins are never committed.
- **Dedupe is by content, never by name.** ≥90% shared (path-under-skin-root, crc32) entries is the same
  skin. Filenames and `<skininfo><name>` both fail measured cases (three different `T-800`s; `K-jr.wal`
  vs `k_jr_winamp_skin_by_marisa85_d329ymw.wal`).
- **Two scores, never blended.** *Health* = the census rating plus the unimplemented-method count — how
  well we serve the skin. *Value* = static features it adds that the admitted corpus does not already
  exercise — what it is worth as a test case.
- **Admission is greedy set cover on value**, from the gold+silver feature union, ties to lowest sha256.
  Deterministic: a pure function of (candidate sha256s, corpus sha256s, git rev).
- **Tiers.** Gold = the `skins.md` set. Silver = admitted by value, budgeted per intake: **≤ 25 skins, gain ≥ 3
  features** (agreed 2026-10-19). Re-open it only after the first intake, from its measured gain curve in
  `intake.tsv` and the sweep time it added — the budget is the sweep's cost. Bronze =
  the rest, census-only. Quarantine = does-not-load, crash or hang — a trap on real input is a security
  bug first (S1).
- **Tier decides which actions run.** Pre-merge render sweep = gold+silver. Impact-selected sweep
  (`--touching <feature,…>`) = every tier, selected from the feature index. Full Bronze census = batch,
  after an intake or before a release. App-driven tools (`skin-screenshots`, `window-census`,
  `skin-pick-matrix`) = gold+silver only.

### Why each corpus-wide action has to change

Linear from the 79-skin timings in `reference/harness.md`:

| Action | ~80 skins | ~1,000 skins |
|---|---|---|
| Render sweep, the pre-merge gate | ~5 min per capture | ~1 h per capture |
| Census (render + hosted) | minutes | 1–2 h |
| Damaged logs (interleaved writes, ~half of passes) | 1–3 solo re-runs | dozens per pass |
| Reach greps over a hand `7zz` extract, hand-quoted denominator | seconds | not tier-aware |
| App-driven tools, one launch per skin | minutes | many hours |
