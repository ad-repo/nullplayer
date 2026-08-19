# Winamp Modern (`.wal`) — Corpus Triage Playbook

- **Date:** 2026-08-18
- **Problem:** the long tail. Nine skins were fixed one at a time over 26 phases. There are tens of
  thousands of `.wal` skins in the wild, each one a bespoke program, and every one of them can fail
  differently. Per-skin heroics do not scale to that.
- **Companion:** [SKILL.md](SKILL.md) and [compatibility.md](compatibility.md) (how the engine works),
  [skins.md](skins.md) (per-skin status), `docs/winamp-modern/state-of-the-engine.md` (where the engine
  stands overall)

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

Two corollaries that shape the whole pipeline: **runtime demand must be provoked**, and **animation is
invisible to a single frame**. Both are addressed in §3, stages S2 and S3.

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
  hash. Today: the nine in [skins.md](skins.md). Each Gold skin also gets a **reference
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
own record of this is one line in `skins.md` ("the analog VU meter styles configure a per-pixel warp we
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

## 4. Isolating one issue, once it is ranked

The corpus tells you *what* to fix; this is how you find *why*, and the order matters because each
probe is cheap only if the previous one has narrowed the space. Never change renderer code before
step 3 answers.

1. **[skins.md](skins.md)** — is this a known trap for this skin? Two phases have already been lost to
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

---

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

The single biggest process gap today: the evidence that a renderer change disturbs no other skin is a
**manual 15-skin before/after sweep**, and nothing in CI would catch a third skin regressing.

Replace it with the corpus:

- **Render hashes** for every Gold + Silver layout, clock pinned (unpinned, animation noise makes every
  skin look changed — it did on the first manual run). A diff surfaces the exact skin/layout/frame.
- **Motion signatures** from S3's ladder, so a change that freezes an animation fails a check instead of
  waiting for a user to notice.
- **Interaction signatures** — the dead-control count per skin. A routing or hit-test change that kills
  controls in an unrelated skin shows up as a number moving.
- **Re-measure after every change, never work down a static list.** Each fix lets scripts run further
  and reach the next thing they need.

Hashes are of *our own renders of user-supplied skins*, so they stay local like the corpus — which
makes **provisioning** part of the contract, not an afterthought. A hash is comparable only between
runs with the same three things pinned: the corpus tier (by the manifest's SHA-256 list, so a machine
either has the exact Gold set or is not running that gate), the harness version, and the clock/settle
ladder. Therefore:

- CI (no corpus) runs the **synthetic** tests only, plus a check that the manifest is well-formed.
- The corpus sweep is a **documented pre-merge gate run on a provisioned machine** for any
  renderer/dispatch/routing change, and its output (the hash set) is what gets attached to the PR.
- A machine missing a manifest entry **skips loudly** and reports partial coverage; it never silently
  compares a smaller set and calls it green.

---

## 7. Build order

Each step is independently useful; stop wherever the value runs out.

1. **Corpus runner + S1 load census.** Small — the loader and the `Codable` report already exist; this
   is a CLI wrapper, a JSON writer, and a folder walk. Immediately answers "what fraction of real skins
   load at all", which nobody currently knows.
2. **S2 MAKI static demand.** Also small — the method table is already parsed. First real ranking data.
3. **S4 aggregation + the demand index.** A script over the JSON. This is where capability-first
   working actually starts.
4. **S3 motion sweep.** Medium — a clock ladder around the existing render path plus per-object deltas.
   Directly targets the animation complaint.
5. **S3 interaction sweep.** Medium — generalises `RENDER_CLICK` from one point to every hooked object.
5b. **Coverage metric + S3.5 state-space enumeration.** The coverage number is nearly free once S1 and
   S3 exist (declared objects vs. objects ever visible) and is the cheapest way to find out which
   "supported" skins we have barely seen. Full state enumeration is the expensive half — do layouts and
   `cfgattrib` ranges first, script-invented preference spaces last, if ever.
6. **Supported-surface manifest + XML census.** The curation cost, deferrable until the method-level
   wins are exhausted.
7. **Corpus render/motion hashing as the pre-merge gate.** Retires the manual sweep.

**Rule of thumb for the work itself:** batch by capability, never by skin, and use each batch's own
re-measure as the definition of done. A skin is not a milestone any more — it is a test case.

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

We already walk exactly this document for surface synthesis (`WasabiSurfaceInventory`), so the census
is a second visitor over a structure that is already built. The only thing that has to be **authored**
is the other side of the diff: a curated manifest of which tags and attributes we actually honour.
Without it, "unimplemented" stays folklore.

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
  highest-value measurement available, and it needs a parse, not a run.
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
