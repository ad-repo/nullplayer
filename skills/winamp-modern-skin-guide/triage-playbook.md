# Winamp Modern (`.wal`) — Corpus Triage Playbook

- **Written:** 2026-08-18. **Last reconciled against the tree:** 2026-09-06.
- **Problem:** the long tail. Nine skins were fixed one at a time over 26 phases. There are tens of
  thousands of `.wal` skins in the wild, each one a bespoke program, and every one of them can fail
  differently. Per-skin heroics do not scale to that.
- **Companion:** [SKILL.md](SKILL.md) and [compatibility.md](compatibility.md) (how the engine works),
  [reference/harness.md](reference/harness.md) (**every probe and both corpus scripts, with their
  commands** — this file never restates a command), [skins.md](skins.md) (per-skin status),
  `docs/winamp-modern/skin-compatibility.md` (the user-facing list),
  `docs/winamp-modern/state-of-the-engine.md` (where the engine stands overall)
- **The corpus is what is installed**, not a fixed set: 79 archives / 75 distinct skins on 2026-09-06,
  and it moves. Every count below carries the corpus it was measured against; do not rewrite an old
  numerator against today's denominator.

---

## 0. Why this is a different beast from classic skins

A `.wsz` is a **fixed contract**: a known set of BMPs at known coordinates. The surface is bounded, so
"support classic skins" is a finite, once-and-done job, and a broken skin is almost always a sprite
we cropped wrong.

A `.wal` is a **program**. The skin ships its own layout engine input, its own bytecode, its own
widgets, and its own idea of where the playlist lives. The supported surface is unbounded in
principle, and our coverage is demand-driven — so the question is never "is the engine done?" but
**"what does the corpus actually ask for, and what fraction of it do we answer?"**

That flips the working unit. Phases 2–26 worked **skin-first** (pick a skin, make it work). Beyond a
handful of skins the only tractable unit is **capability-first**: measure the whole corpus, rank
missing capabilities by how many skins they kill, implement the top cluster, re-measure. One fix that
unblocks 200 skins beats ten fixes that unblock one each — and you cannot see that ranking without a
corpus harness.

---

## 1. The four defect classes

Triage starts by naming the class, because each one has a different detector, a different cost, and a
different owner. Misclassification is what cost Phase 25/26 two passes ("the SUI body is empty" was
read as a missing widget; it was three routing bugs behind a surface the harness structurally cannot
draw).

| Class | What it is | Detected by | Typical cost |
|---|---|---|---|
| **A — Missing capability** | The skin declares a tag/attribute or calls a method we never implemented | Static scan (§3) + `unsupportedMethods` | Small each, high volume |
| **B — Wrong semantics** | Implemented, but behaves differently from Winamp | Nothing automatic. Pixels, the skin's own `screenshot.png`, or a user report | **The expensive class** |
| **C — Missing content/host data** | Resource unresolved, host property `nil`, surface not routed | `BITMAPS … missing=`, report `resources`, holder census | Small |
| **D — Out of scope by policy** | Sandbox or product decision (`<Browser>`, layer FX, arbitrary filesystem/network access) | Won't-do registry lookup (§5) | Zero — but must be recorded once |

> Class D is only what policy **rejects**, not what it **narrows**. ClassicPro's three filesystem-shell
> methods are *adapted under restriction* (`exploreFile`/`openFile` on existing non-URL paths, `findFiles`
> a bounded no-op) — that is an implemented capability with a tight contract, and filing it as a policy
> reject would hide a real, working surface from triage.

**Class B is why the compatibility report can be clean while the skin looks wrong.** Every corpus-scale
instrument below detects A, C and D. B is only ever caught by looking, so the corpus tooling's real job
is to *drain A/C/D automatically* so human attention is spent exclusively on B.

---

## 2. What our current instruments can and cannot see

Know the blind spots before trusting any batch output. **What each probe is and every environment
variable it takes is documented once, in
[reference/harness.md](reference/harness.md)** — this section is only about what they cannot see:

| Instrument | Sees | Blind to |
|---|---|---|
| Load-time compatibility report | Archive/resource/group/script problems at load | Anything a script only reaches on an event. A handler that dies on a missing method records **nothing** until something drives it |
| `unsupportedMethods` tally | Methods actually *called* | Methods on paths nobody drove. A method with a `signature(for:)` entry but a stubbed dispatch is **invisible** — it looks implemented |
| `RENDER_DUMP` PNGs | Initial static scene, **including** renderer-drawn embedded surfaces (the playlist and EQ are drawn by `WasabiSceneRenderer`, coloured by the skin's palette) | Everything time-driven; everything a click changes; the embedded **library**, which is a live AppKit view whose holder paints only a flat fill. And in the dump harness specifically, the playlist/EQ come out as empty panels because no `componentHost` is set — a harness artifact, not a missing feature |
| `RENDER_CLICK` | One point, its handler chain, attribute deltas | Whatever you didn't think to click |
| `RENDER_SCRIPTS` | Which handlers actually ran and how they failed | Only for events that were driven |
| **Corpus census** (`wal_skin_census.sh`) | One structural row per archive: level, findings by code, where every surface landed, resolved/unresolved bitmaps, which hosted windows wear the frame | **Whether anything is drawn right.** Its `fully-skinned` rating says every declared piece found a home with its artwork resolved — three skins rate `fully-skinned` while rendering an *empty main window* (B145). It is a structural rating, never a grade |
| **Corpus render sweep** (`wal_render_sweep.sh`) | Whether an engine-wide change moved any invariant line or any pixel of any dumped PNG | **Every state that is not the stored default.** A change can pass 287 of 288 images and still break a skin whose defect lives behind a tab, a setting or a drag (measured 2026-08-24 on Big Bento Modern) |

Three corollaries that shape everything downstream: **runtime demand must be provoked**, **animation is
invisible to a single frame**, and **a clean corpus pass proves the default state and nothing else.**
The first two would be addressed by the unbuilt stages in §3; today, provoke them by hand.

---

## 3. The pipeline — what exists, and what is still done by hand

**Partly built.** The five-stage pipeline was specified in 2026-08-18 as S0 ingest/tier, S1 load
census, S2 static MAKI demand, S3 motion + interaction sweep, S3.5 state-space enumeration, S4
aggregate and rank. Two of those now exist as committed scripts, and the rest is still manual. Know
which half you are standing on before planning work:

| Stage | State | What to run |
|---|---|---|
| S0 ingest/tier | **Partly.** No committed manifest and no Gold/Silver tiering; the census enumerates whatever is installed and emits a **sha256 per row**, which is what makes duplicate archives and a moved corpus visible | — |
| S1 load census | **Built** — `scripts/wal_skin_census.sh`, one TSV row per archive | [reference/harness.md](reference/harness.md) → *The corpus census* |
| Regression sweep (§6) | **Built** — `scripts/wal_render_sweep.sh capture` / `compare`, invariants **and** every PNG | [reference/harness.md](reference/harness.md) → *The corpus render sweep* |
| S2 static MAKI/XML demand | **Not built.** The stand-in is the hand-run `grep` set under *Reproducible reach commands* in `TASKS.md`, which is where every measured Reach number in the backlog comes from | `TASKS.md` |
| S3 motion + interaction, S3.5 state space, S4 rank | **Not built.** Provoke motion and interaction by hand | — |

Two rules follow from the built half, and both are already paid for — the full versions, with the
measurements behind them, are in [reference/harness.md](reference/harness.md):

- **A sweep or census is a build. Freeze the tree.** Both scripts refuse a dirty tree without
  `--allow-dirty`, because a binary that will not compile writes an *empty* capture that diffs as
  "everything changed".
- **A damaged log is a first-class outcome, not a finding.** Interleaved writes eat whole blocks of
  the capture in about half of all passes, and the result looks exactly like a dropped container.
  `damaged.txt` names those skins; re-run each alone before believing anything about it.

The specification for the unbuilt stages, and the build order that would deliver them, are in
`docs/winamp-modern/corpus-runner-plan.md` — a project plan, kept where the phase handoffs live. As
each further stage is built, its commands land in [reference/harness.md](reference/harness.md), that
part of the plan becomes history, and the row above changes to **Built**.

---

## 4. Isolating one issue, once it is ranked

The corpus tells you *what* to fix; this is how you find *why*, and the order matters because each
probe is cheap only if the previous one has narrowed the space. Never change renderer code before
step 3 answers.

1. **[skins.md](skins.md) → `skins/<skin>.md`** — is this a known trap for this skin? Two phases have already been lost to
   re-deriving one.
2. **Report after driving** (`RENDER_CLICK`'s post-report, not the load-time one) — is it a missing
   method? If yes, it is Class A, stop, add it to the demand cluster, do **not** hand-fix it here.
3. **`RENDER_PROBE` + `RENDER_BITMAPS`** — missing art (C), bad geometry (B), or a script that never
   ran (A/B)? `missing=` separates an unresolved resource from one drawing wrongly.
4. **`RENDER_SCRIPTS`** (not `RENDER_XUI`) — did the handler *run*? Per-object binding state does not
   answer that question, and reading it as if it did cost two phases.
5. **`RENDER_CLICK` chain** — a chain that ends one hop early is a missing script-to-script route; a
   chain that completes and changes the right attributes with no pixel change is a renderer gap.
6. **`RENDER_DISASM=@<source>`** — read the skin's own bytecode. (For **ClassicPro** specifically, the
   engine ships its MAKI `.m` sources next to the bytecode, so read those instead of disassembling;
   ordinary skins ship bytecode only.) Read the script that owns the feature rather than inferring
   semantics. Three
   semantics (`getARGBValue` channel order, `getDateYear`'s epoch, the `isInvalid` probe idiom) were
   pinned this way rather than guessed.
7. **The skin's own `screenshot.png`**, when it ships one — the author's reference render is ground
   truth for Class B, and it is the only ground truth we have that isn't real Winamp.

### A unit is settled by the minority

When a host API answers a *number* — a time, a level, an angle — the corpus does not vote on its unit.
Most call sites divide two of our own values into a ratio (`255 * getPosition() / getPlayItemLength()`)
or hand one straight back to another of our own methods (`integerToTime(getPlayItemLength())`). Every
one of those is **invariant** under a change of unit and therefore says nothing, however many of them
there are. Counting them is how the seconds reading survived 60 phases.

Read the unit off the few sites that do **absolute** arithmetic instead — a division by a literal, a
comparison against a constant, a hand-rolled formatter. Two of those settled milliseconds in B64
(Styx's `getPlayItemLength()/1000` and Anexa's `int devby = len/255`), against a dozen ratio sites that
were equally happy either way. `grep` the API name across every `.m` in the corpus and discard every
hit whose other operand is also ours.

Two corollaries:

- **A unit belongs to a family, not a method.** Change every producer and every consumer in one edit —
  in B64 that was `getPosition`, `getPlayItemLength`, `seekTo`, `onSeek`'s argument, `integerToTime`'s
  argument and the `length` metadata key. Split it and a skin disagrees with its own readout, which is
  a worse defect than the one being fixed and a much quieter one.
- **Then the change is no-worse by construction.** Once the family moves together, every invariant
  call site renders exactly as before, so the blast radius is only the absolute sites — which is what
  makes such a change safe to make on two skins' evidence.

The general shape: **an instrument that cannot distinguish the two answers is not evidence for
either.** It is the same failure as a [blind probe](reference/harness.md), one level up.

### The backlog entry is a report, not a spec

A ranked entry carries a diagnosis, a proposed expression and a safety claim. Treat all three as
**the previous investigator's hypothesis**, and re-derive each before touching the code — B68 shipped
with all three subtly wrong, and each would have produced a defect of its own:

- **The proposed expression was wrong.** The entry said `autowidthsource` should answer `x + width`.
  That is right only when the source's width does not depend on its parent; every offset source in
  the corpus states `w="-N" relatw="1"`, where the answer is `width - w`. Following the entry would
  have left impulse 1px short and the tab sheets 8px short — a fix that looks applied and is not.
  **Derive the rule from the resolve** (solve `resolve()` for the unknown), not from the shape of the
  numbers in one skin.
- **The safety claim named the wrong skins.** The entry said the 27 must-not-move declarations were
  ClassicPro's menu bar; they are stock Winamp Modern's and The_Nokia_5220's, plus three title-box
  bodies. The claim's *conclusion* survived — all of them source at `x="0"` — but only because it was
  re-run. Re-run it: the entry tells you which measurement to repeat ([M22] here), and that is what
  the reach commands are for.
- **The reach count was reproducible and correct.** Which is the point: the numbers a `grep` produces
  survive; the prose around them decays.

### A demand count is a count of calls, not of consequences

`unsupportedMethods` ranks what to implement by how often the corpus asks for it, and that ranking is
sound — but a `×1` says one call site, and says **nothing** about how much sits behind it. B100 was
filed as *"`onLeaveArea` is unimplemented, ×1 — expect something in the SUI to stay lit after the
pointer goes"*, a cosmetic prediction from a count of one. What it actually cost was cPro2's entire
Now Playing selector: five call sites in one script the count never saw (they are calls, not
bindings), each one able to abandon its whole handler, two of them on the path every menu pick takes.

So when an entry predicts a *symptom*, treat that prediction as the weakest thing in it. The count is
reproducible; the guess about what the missing call was holding up is prose, and prose decays. Read
the call sites before you believe the severity — `grep -rn "\.<method>(" ` over the engine and the
extracted corpus takes seconds and is the difference between "cosmetic" and "a dead menu".

The corollary for the *other* direction: a defect the reporter describes as one broken thing can be
one missing arity behind several. Do not stop at the first call site that explains part of it.

The cheap discipline is to re-run the entry's own measurement command first, before reading any
source. It takes a minute, it either confirms the entry or hands you a corrected one, and it is the
difference between fixing the defect and fixing the description of it.

---

## 4b. Historical ranking (B1–B10, closed; 2026-08-20)

The live list is the tracked **`TASKS.md`**, whose Reach, Effort, and Tier columns are the demand
index. It is the whole backlog and where new items go; `BB*` remains an identifier family, not a
separate file. There was once a tracked copy at `docs/winamp-modern/open-items.md` holding the ranked
reasoning behind B1–B23a; it was **deleted on 2026-08-23** after an audit confirmed nothing in it was
unique (B19 shipped as `ea4d9472`, B22 as `df9d1028`, and B23a moved to `TASKS.md`). Do not recreate
it. The table below is the head of that ranking, kept here as history so a reader does not have to go
looking — it is ordered by **bang for buck**, corpus impact ÷ effort:

| # | Open item | Reach |
|---|---|---|
| ~~B1~~ | ~~A missing `<include>` fails the **whole skin** instead of warning~~ — **closed in Phase 35**; the corpus is 17 skins wide | ~~2 of 17 skins do not load at all~~ (Itemskin, Overdrive_2 both render) |
| ~~B2~~ | ~~`dblclickaction=` / `rightclickaction=` read nowhere~~ — **closed in Phase 36**: decoded (including `ACTION;PARAM`), hit-tested, and `TRACKINFO`/`TRACKMENU` implemented | ~~`TRACKINFO` 6 skins, `TRACKMENU` 5~~ — the scan found **62 uses in 9 skins**, most of them the winshade switch |
| ~~B3~~ | ~~`PAN` (balance) has no case beside `SEEK`/`VOLUME`~~ — **closed in Phase 37**: the drag writes the engine's balance, the thumb is drawn from it, and a drag now moves the object's own position and dispatches `onSetPosition` | ~~6 skins~~ — the scan found **8 uses in 7 skins** |
| ~~B4~~ | ~~`valign` ignored — text is always vertically centred~~ — **closed in Phase 38**: decoded for both draw paths, and the bitmap-font path (which was pinned to the box's top edge) centres by default | ~~every skin's text~~ — the scan found **63 uses in 9 skins**, 54 of them `top` |
| ~~B5~~ | ~~`VIS_*` / `PE_*` / `VID_*` / `CB_*` host actions inert~~ — **closed in Phase 39**: the five visualization, five playlist and two video commands implemented; `VID_1X`/`2X`, `VID_TV` and `CB_*` accepted and inert with a recorded reason | ~~75 button uses~~ — the scan found **108 uses in 11 skins** |
| ~~B6~~ | ~~`default_visible="1"` not honoured on auxiliary containers~~ — **closed in Phase 40**: honoured as a *default* the user's own choice overrides, placed by `default_x`/`default_y`; the notifier remains suppressed, while browser windows now open with real WebKit content | ~~Defix's `Config`~~ — the scan found **10 containers in 8 of the 17 skins** |
| ~~B7~~ | ~~`onEqBandChanged` / `onEqPreampChanged` never dispatched~~ — **closed in Phase 41**: one funnel that dispatches only what moved, on every route including a 1 Hz poll for the ones nothing calls back on, with the skins' own EQ sliders synced first | ~~5 skins' EQ readouts~~ — all five answer under `RENDER_EQ` |
| ~~B8~~ | ~~The playlist-editor script API (`getCurrentIndex`, `getNumTracks`, `playTrack`, …)~~ — **closed in Phase 42**: the cause was the parser reading *every* `system`-flagged global as the System object, so `PlEdit.x()` arrived as a call on System; the twelve methods are keyed on `PlEdit`'s class GUID, not by name | ~~Defix's known gap~~ — and every skin that drives its own list |
| ~~B9~~ | ~~`onKeyDown` never dispatched~~ — **closed in Phase 43**: it carries Winamp's accelerator *string*, not a keycode, and the missing seam was a borderless window's `canBecomeKey` rather than first responder. `complete;` is the consumption signal; `isActive()` implemented alongside, because the corpus gates on it | ~~5 skins~~ — the measurement found **3** that bind it (Rika's and T800's are the edit control's `onKeyDown(Int)`, in a program neither skin loads) |
| ~~B10~~ | ~~No CI cover for the render sweep~~ — **closed in Phase 44**: five committed golden images over synthetic fixtures (`WinampModernGoldenImageTests`) cover group clipping, frame slicing, animated-layer framing, text placement and `alpha`, each verified to fail under a reintroduced regression. §6 still stands for the corpus half — CI now catches the *mechanism*, not a change against real artwork | all |

The pattern worth noticing across B1–B9: each is a **single attribute or policy** that nothing reads,
and each makes a *visible* control dead in several skins at once. That is what the demand index is
for — one of these outranks any amount of work on a widget only one skin declares.

## 5. Dispositions

Every triaged issue ends in exactly one of four states, recorded once:

- **Implement** — goes into a capability cluster with the skins that need it as its test set.
- **Degrade gracefully** — we cannot do the real thing, but the skin must not look broken (a missing
  optional resource warns; a `truetypefont` a skin never shipped falls back to a substitute face).
- **Accept and inert** — the call succeeds and does nothing, because the skin only needs to get past
  it (`switchSkin`, install/update prompts, `fx_*`). **Never** silently, and never with a
  `signature(for:)` entry that hides it from the demand tally.
- **Won't do** — sandbox or product policy (`<Browser>`, arbitrary filesystem, network). Gets a row in
  a **won't-do registry** with the reason, so the next person triages it in ten seconds instead of
  ten minutes.

The registry matters more than it sounds: at corpus scale the same fifty exotic features will surface
in every batch forever, and an un-recorded "no" is re-litigated every time.

---

## 6. Regression safety at corpus scale

In 2026-08-18 this section asked for two halves — synthetic cover for the mechanisms and a corpus
sweep for the artwork — and **both now exist as committed, runnable checks** rather than an afternoon
of manual comparison. What they cover, and the three things they still do not, follow.

- **Synthetic goldens** cover the *mechanisms*: group clipping, `<Wasabi:Frame>` slicing,
  animated-layer framing, bitmap-font text placement and per-object `alpha`, as whole-canvas
  assertions over fixtures needing no third-party artwork (`WinampModernGoldenImageTests`, Phase 44 /
  B10). Each was checked to fail under a deliberately reintroduced regression before being trusted,
  which is the only thing that tells a golden apart from a [blind instrument](reference/harness.md).
  These run in CI, which has no corpus.
- **The corpus sweep** covers the *artwork*, which no fixture can stand in for.
  `scripts/wal_render_sweep.sh capture` dumps every layout of every installed skin in one invocation
  (~100 seconds over the 69 then installed, against ~25 minutes for the shell loop it replaced), and
  `compare` diffs the invariant lines **and** every PNG, reporting per image identical / `maxdelta=N`
  over a pixel count and bbox / present on one side only. It is the pre-merge gate for any
  engine-wide change, and its output is what gets attached to the PR.

What §6 asked for in 2026-08-18 and what shipped are not quite the same thing, and the difference is
worth keeping straight: it asked for **render hashes**; what exists is a **per-pixel delta**, which is
strictly better, because a hash tells you a skin changed and a delta tells you by how much. Read the
magnitude before calling a difference a regression — a `maxdelta` of 1 is one LSB. The traps that
apply to every run (freeze the tree, redirect don't pipe, damaged logs, capture the baseline in a
worktree and never by `git stash`, and the one genuinely nondeterministic image in the corpus) are
documented once in [reference/harness.md](reference/harness.md); do not re-derive them here.

**Still not built**, and still the honest gaps:

- **Motion signatures** — a change that freezes an animation passes the sweep, because a single frame
  has no motion in it. This waits on S3.
- **Interaction signatures** — the dead-control count per skin, so a routing or hit-test change that
  kills controls in an unrelated skin shows up as a number moving. This waits on S3.
- **State beyond the default.** Every skin renders in its *stored default configuration*. Reproduce a
  non-default state explicitly (`WINAMP_MODERN_RENDER_CONFIG` / `RENDER_SET` seed it headlessly) and
  hand the build over to be checked on screen; a clean sweep is "no regression in the default state",
  never "verified".

And one rule that has not changed: **re-measure after every change, never work down a static list.**
Each fix lets scripts run further and reach the next thing they need.

Provisioning is part of the contract, because a comparison is only meaningful between runs over the
same corpus. There is no committed manifest — the census's **sha256 column** is what makes the corpus
a reproducible input, so record the census alongside a sweep whose result you intend to cite, and say
which corpus a claim was measured against. CI, having no corpus, runs the synthetic goldens only.

---

## Appendix A — How do we even know what functionality a skin contains?

The corpus pipeline stands or falls on this question, so it is worth being precise: **a `.wal` is
almost entirely self-describing, and nearly all of it can be read without executing a single
instruction.** There are three different sets in play, and every triage question is a difference
between two of them:

- **Declared** — what the archive says it contains (static, complete, cheap)
- **Reachable** — what actually gets exercised in a session (runtime, partial, expensive to provoke)
- **Implemented** — what our engine answers (a manifest we control)

`Declared − Implemented` is the work queue. `Reachable − Implemented` is what the user is complaining
about *today*. `Declared − Reachable` is how much of the skin we have never even tested.

### What the archive tells you, statically

**1. The expanded XML document — the UI inventory.**
After include/glob expansion and group expansion, the document is a complete list of what the skin
draws and what it wires up. Every one of these is a countable declaration:

> **Count syntax in context, not substrings.** A search for `wasabi.panel` also matches bitmap and
> colour ids such as `wasabi.panel.top`, and comments preserve abandoned declarations. B15's first
> 36-skin count therefore reported 192 "declarations" in 19 skins, while a comment-stripped scan for
> `<group id="…">` and `<groupdef inherit_group="…">` found 19 actual edges in eight. Resource-name
> demand proves that artwork exists; it does not prove that the group body is instantiated. Record
> resource declarations, group edges, and container/layout reachability as three separate counts.

- containers and layouts → how many windows, and their declared sizes
- every element tag (`layer`, `animatedlayer`, `button`, `togglebutton`, `slider`, `text`,
  `songticker`, `vis`, `grid`, `component`, `windowholder`, `Wasabi:Frame`, custom `xuitag`s…)
- every attribute per tag → the exact feature surface asked for (`tile`, `rectrgn`, `fitparent`,
  `ticker`, `forcefixed`, `regionmap`, `fliph`, `fx_*`…)
- `action=` values → the built-in commands wired to controls, **including every `MENU` action and its
  param** — a skin button asking the *host* for one of Winamp's own menus (`MENU presets`, the
  playlist ADD/REM/SEL/MISC menus) is inert unless we provide that menu, and the param census is the
  complete list of which ones a skin expects
- `display=` bindings → which host data the skin expects (`time`, `songname`, `songinfo`)
- `cfgattrib=` → every preference the skin exposes, with its GUID
- component GUIDs and holder types → where the playlist / EQ / library are expected to live
- `gammaset` count → how many colour themes ship
- `groupdef`/`inherit_group`/`embed_xui`/`xuitag` → the skin's own widget vocabulary

We already walk exactly this document for surface synthesis (`WasabiSurfaceInventory`, in
`Windows/WinampModern/WinampModernSurfaceCoordinator.swift`), so the census is a second visitor over a
structure that is already built. `scripts/wal_skin_census.sh` now emits the part of this that falls out
of a load — container/layout/node counts, where each surface landed, resolved and unresolved bitmaps —
but **not** the per-tag/per-attribute demand census, which is still S2 and still unbuilt. The only
thing that has to be **authored** is the other side of that diff: a curated manifest of which tags and
attributes we actually honour. Without it, "unimplemented" stays folklore. The nearest thing that
exists today is [compatibility.md](compatibility.md) and `compatibility/wasabi-surface.md`, which are
prose, not a machine-diffable set.

**2. The MAKI symbol tables — the behaviour inventory, without running anything.**
Every compiled `.maki` carries, in the file:

- `classes` — the class GUIDs it touches
- `methods` — every method name it can call (class + lowercased name)
- `variables` — its typed storage, including which objects it holds
- `bindings` — **(object variable, handler method, entry-point instruction)** triples
- `instructions` — the full instruction stream

Two things fall straight out of that, and both are the answer to "what does this skin *do*":

- **`methods` minus our `signature(for:)` set = a complete per-skin list of API the skin can call
  that we do not implement** — including every branch nobody ever clicked. This is the single
  highest-value measurement available, and it needs a parse, not a run. It is **still not
  implemented**; the backlog's Reach numbers come from the hand-run greps in `TASKS.md` instead, which
  read the extracted corpus rather than the method tables and are therefore an approximation of it.
- **`bindings` is the event map.** It says which object handles which events. Composed with the
  instruction stream — walk from a binding's entry point to the next one — you get *per handler* the
  methods it calls. That is a **static per-control requirement list**: "this button's `onLeftButtonUp`
  needs `isMouseOverRect`, `getScriptGroup`, `sendAction`", and if one of those is unimplemented, that
  control is statically predictable-dead before anyone clicks it.

Note this also cures a structural weakness of the current process: runtime demand is a **queue** (each
fix lets a script run further and reveal the next need), so discovering capability by execution
converges slowly and only along paths you happen to drive. Static extraction gives the whole set at
once.

**3. The resources — the content inventory.**
Declared `<bitmap>`/`<bitmapfont>`/`<truetypefont>`/`<cursor>`/`<color>` versus what the archive
actually contains; sprite-sheet dimensions versus declared frame counts (an `animatedlayer`'s frame
count is arithmetic on its sheet); which bitmaps opt into which `gammagroup`. This is where Class C
lives, and `RENDER_BITMAPS`' `missing=` already reports it per layout.

For a colour complaint specifically, two greps settle in seconds what running the skin cannot tell you
apart — whether an asset carries its own colour or is a template the theme paints:

```bash
unzip -p skin.wal '*.xml' | grep -o 'boost="[^"]*"' | sort | uniq -c   # which gamma model it wants
python3 -c "from PIL import Image; im=Image.open('skin/player/x.png').convert('RGBA'); \
  px=[q for q in im.getdata() if q[3]>16]; print(max(max(q[:3]) for q in px))"   # 0 = black template
```

A skin whose themed PNGs come back max-RGB **0** gets *all* of its colour from gamma offsets, and its
`<color>` resources will be `value="0,0,0"` to match. Anaheim Player 01 is the type specimen.

**4. What some skins hand you outright.**
The ClassicPro engine ships its MAKI **`.m` sources** beside the bytecode — read the script that owns
the feature rather than inferring its semantics. Many archives ship a `screenshot.png` (the author's
own reference render — the ground truth for "wrong, not missing") and a readme naming features. Free
signal; use it before reverse-engineering anything.

### What is only knowable by running

Three things resist static analysis and always will:

- **Dynamic construction.** `System.newGroup(id)` builds UI at runtime, and the id can be computed;
  `setXmlParam("image", prefix + suffix)` swaps artwork from a preference. Static census sees the call,
  not the result.
- **Whether a branch is taken.** A skin can declare a feature and gate it behind a config value or a
  `isInvalid()` probe. Static demand is an **upper bound** on what matters.
- **Timing and ordering.** Animation, tickers, and timer-gated transitions have no static signature
  beyond "a timer exists" — hence the motion ladder in S3.

Which is exactly why the pipeline pairs them: **rank on static, confirm on runtime.** The gap between
the two sets is itself a finding — a method the tables declare but the runtime never records is either
an untested path or, worse, a stub of ours that is quietly answering for it.
