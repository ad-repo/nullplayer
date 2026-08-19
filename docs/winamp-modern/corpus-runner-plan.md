# Winamp Modern (`.wal`) — Corpus Runner Plan

**Status: not built.** This is a build plan, not a description of tooling that exists. Corpus triage
is a **manual process today** — the durable method (defect classes, instrument blind spots, isolating
one issue, dispositions, regression safety) lives in
`skills/winamp-modern-skin-guide/triage-playbook.md` and is runnable by hand right now. What follows
is the specification for the automation that would make it unattended.

As each stage is built, its commands land in
`skills/winamp-modern-skin-guide/reference/harness.md` and that part of this plan becomes history —
the same lifecycle the phase handoffs have.

Extracted verbatim from `triage-playbook.md` §3 and §7 (2026-08-18).

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

