---
name: skin-subsystem-blueprint
description: How to add or extend a skin family (Classic, Original, Winamp Modern .wal, Windows Media Player .wmz, and the VLC family next) — the shared-code seams a new family must touch, the isolation rules, the harness and corpus pattern, and the skill/backlog layout every family is expected to produce. Use when starting a new skin engine, reviewing a change that touches PlayerUIMode or WindowManager routing, or deciding where a new subsystem's documentation goes.
---

# Adding a skin family

NullPlayer hosts several independent skin engines. Four exist — `classic`, `nullPlayerModern`
(Original/Original-Metal), `winampModern` (`.wal`), `wmp` (`.wmz`) — and the pattern below is what
the last two paid to discover. Follow it rather than re-deriving it.

**The reference implementation is `winamp-modern-skin-guide`**: the most successful engine here, and
the model for the engine rules, the harness, the corpus census, the demand-driven backlog and the
skill layout. `wmp-skin-guide` is the same shape at an earlier phase. Read whichever is closer to
what you are building before writing anything.

## The rule that outranks everything

**A new skin family must never change how the existing families behave.** They work; yours is the one
under construction, and a regression there is a regression in what people already rely on.

The trap is not `import` — CLAUDE.md already forbids `ModernSkin/`/`Windows/Modern*/` importing from
`Skin/`. It is **shared code every mode runs**, `App/WindowManager.swift` above all. Adding behaviour
there and reasoning that it "should be a no-op for the other modes" is not good enough and has
already produced live regressions (B56 in `.wal`). Gate explicitly on
`uiMode.controllerFamily == .<yours>` so the other families run the identical code path, and the
claim is enforced by the compiler rather than by an argument.

The rule forbids side effects, not deliberate fixes: a genuine bug in shared code may be fixed as its
own scoped change with the impact stated up front. See `winamp-modern-skin-guide/SKILL.md` for the
worked version of both halves.

## Prefer an enum the compiler checks over a boolean it cannot

This is the whole modularity story. `PlayerUIControllerFamily` exists so a routing decision is a
`switch` the compiler forces you to update when a case is added; a `Bool` silently folds a new family
into whichever branch it is not.

Measured on this tree today: **72 `controllerFamily` seams** (safe — adding a case breaks the build
until each is answered) against **58 `isModernUIEnabled` / `isRunningModernUI` seams** (36 of them in
`WindowManager.swift`, 10 in `ContextMenuBuilder.swift`). Every one of the latter is a place a new
family may quietly inherit Classic's or Original's behaviour.

- **Never add a new boolean** of the form `isRunningXUI` used at more than one call site. Add the
  case to `PlayerUIControllerFamily` and switch on it.
- `isModernUIEnabled` is **safe**: it is derived (`controllerFamily == .nullPlayerModern`).
- `isRunningModernUI` is **not**: it is a negative allow-list of controller types
  (`is ModernMainWindowController` → true; `is MainWindowController`, `is WMPMainWindowController`
  → false) with a fall-through to `isModernUIEnabled`. `WinampModernMainWindowController` is absent
  and is correct only by accident of the fall-through, and only while `uiMode` and the live
  controller agree — i.e. **not during a mode switch**.
  **Before the VLC family lands, replace that ladder with one `runningControllerFamily` computed
  property mapping controller type → family, and derive `isRunningModernUI` / `isRunningWMPUI` from
  it.** Do it as its own scoped change with the app driven afterwards, not folded into feature work:
  the transitional semantics genuinely differ (today, switching *out of* `winampModern` into
  `.modern` reports `true` while the old controller is still installed; a family-mapped version
  reports `false`), so it is a behaviour change in a transient window, not a pure refactor.

## The shared-code seams

Everything a new family must touch outside its own directories. This is the complete list the `.wmz`
family needed (`git diff main...HEAD -- Sources/NullPlayer/App` on the WMP branch: 6 files):

| File | What a new family adds |
|---|---|
| `App/PlayerUIMode.swift` | the `PlayerUIMode` case, its `PlayerUIControllerFamily` case, and answers in `usesModernEQLayout` / `modernSkinFamily` |
| `App/AppCapabilities.swift` | an `AppFeature` case, so an edition can turn the family off and DEBUG-only exposure is expressible |
| `App/WindowManager.swift` | `makeMainWindowController(for:)`; the auxiliary-window policy; the init-time default-skin gate; `prepareUIRuntime(for:)`; the `reloadUI` availability guard; the fallback main-window size; compact-mode/window guards |
| `App/AppDelegate.swift` | menu-bar items |
| `App/ContextMenuBuilder.swift` | context-menu items |
| `App/AppStateManager.swift` | persistence and restore |

Adding the `PlayerUIControllerFamily` case **first** turns the rest into a compiler worklist. That is
the intended workflow: let the build tell you the seams instead of grepping for them.

### The auxiliary-window policy is a decision, not a default

Every family must answer what happens to NullPlayer's own windows (playlist, EQ, library, visualizer,
spectrum, waveform, analysis, PeppyMeter, Cava, Flow). `WindowManager.auxiliaryControllerStyle` is
the seam. The answers in use:

- reuse the **classic** providers (`winampModern` does, by Phase-1 policy),
- use the **nullPlayerModern** providers,
- **your own** — the shared NullPlayer window controllers, painted in chrome derived from your skin
  (`wmp`, 2026-09-09),
- **unavailable** — hide or disable the window until it has chrome of your own. A holding answer,
  not a destination: `wmp` shipped in this state for eight phases and it left the mode with no route
  to a track at all (`wmp-skin-guide`: *`.wmz` mode must offer a route to a track*).

Never fall back to another family's chrome. Two things make the third answer cheap, and both already
exist because `.wal` paid for them:

- **The style is family-neutral.** `SkinnedSurfaceStyle` (`App/Skinning/`) is built from seven
  colours — `SkinnedSurfaceRoles` — and every shared view reads exactly one property,
  `WindowManager.hostedSurfaceStyle`, which switches on the controller family. A new family supplies
  a palette and inherits a complete flat-drawn playlist, equalizer, library and spectrum family.
  Nothing in it may learn your markup.
- **Run every foreground through `SkinnedSurfaceStyle.legible`.** A skin format that declares colour
  per element hands you pairings the skin itself never shows, and a palette sampled from artwork was
  never chosen against any text colour. Guard each role against the ground it is *actually* drawn on.

**And ask what the skin provides before opening a window of your own.** This is the half `.wmz`
missed on the first pass: 171 of its 180 corpus skins declare a playlist and 164 an equaliser, so an
unconditional NullPlayer playlist put a second, foreign-looking one over nearly every skin in the
corpus. `routeWinampModernSurface` and `routeWMPSkinSurface` are the same idea in both families —
the skin's own surface takes the toggle first, and NullPlayer's window is the fallback for the skins
that declare none. Answer all three shapes: declared in the view on screen (nothing to open, and the
menu item should say so), declared in another view (open that view the way the skin's own button
does), declared nowhere (your window).

### The skin's *own* extra windows are a second, separate decision

Not to be confused with the policy above, which is about **NullPlayer's** windows. This one is about
the windows **the skin format itself declares**, and every family has them: a `.wal` names containers,
a `.wmz` names views its script opens with `theme.openView`. The question is whether they become real
windows, and the honest answer is yes — the alternative is to simulate one, and **a simulated second
window is a defect generator rather than a reduction**. `.wmz` ran that experiment for four phases:
presenting the opened view in the one window and remembering what it covered produced three separate
*reported* defects (an interior window's close taking the whole UI with it, a panel persisted as the
session's view so the next launch had no player, and the macOS close control stranding the user), and
all three were deleted by making the window real rather than fixed individually (W141, 2026-09-11).

**Copy `.wal`'s auxiliary containers, and copy them rather than the other two families.** Classic's
windows are a 275px grid with a rigid centre stack and Original's geometry is ours to decide; only
`.wal` already assumes nothing about the main window's geometry, which is what an arbitrary authored
canvas needs (`Halo 2`'s panels are 406x209 against a 327x294 player). The recipe:

- **One borderless `NSWindow` per container/view, all against one shared script runtime**, with a map
  from container/view to the window that owns it, so a script callback reaches the right one.
  `WinampModernHostedWindowMaterializer` and `WMPViewWindowMaterializer` are the same class twice.
- **Independent top-level windows, never `addChildWindow`.** A child window is for a foreign
  *rendering surface* glued to a layout tree it must not join — the VLC video output is the only one
  in the app (`wmp-skin-guide` § W102).
- **The first view presented binds the controller's existing window.** That window is
  `MainWindowProviding`'s anchor, the frame-restore anchor, the tiler's anchor and the host the
  unskinned fallback is swapped back into; binding to it means none of those move when the skin opens
  panels. **The trap that binding carries: the main window is the app's, not the skin's.** Ordering
  it out means *close* and nothing else — a skin reload or a mode teardown drops its presentation and
  leaves the window alone, because something is about to be put into it. Let a materializer share one
  teardown path between "close this window" and "release everything" and the main window goes off
  screen on reload; on `.wmz` that surfaced at **launch**, because restoring a saved frame reloads
  the skin (`main windows launch minimized`, 2026-09-11). Auxiliary windows are ordered out either
  way — they belong to the skin.
- **`WindowManager`'s placement seams are already family-neutral despite their names.**
  `winampModernTiler`, `tiledOrigin(for:avoiding:)`, `occupiedWindowFrames`, `rescuedOrigin`,
  `windowWillMove`, `applySnappedPosition` and `bringAllWindowsToFront` are generic; the tiler is
  anchored on `mainWindowController?.window`, whatever family owns it. Do not write a second one.
- **Place once, on first show, and never again** — a window the user moved must never be yanked back
  — with `rescuedOrigin` as the never-`nil` fallback. The failure mode is an *invisible* window, not
  a wrong-looking one, so give the family a placement trace flag on day one
  (`WINAMP_MODERN_PLACE_TRACE`, `WMP_PLACE_TRACE`).
- **Join docking through your own gated branch of `managedWindowRecords`**, as a snap target and
  **not** a centre-stack member: a skin-authored canvas has no column to join.
- **Per-window state has to actually be per window.** Whatever the controller holds that is really
  the presented view's — scene, overrides, timers, animation clock, interaction state, pending host
  events — moves onto one reference type per window (`WMPViewPresentation`), and the *script runtime*
  has to be keyed per view too. An observable-property registry is the trap: it reports only values
  that **moved since it last looked**, so two windows sharing one each see half the changes.

**And know which of the format's panels are not windows at all.** A drawer that slides inside the
main window is markup *inside* the presented view — Corona's playlist and equaliser, NVIDIA's
embedded playlist and video modes — and must keep being drawn by the scene like any other node. It
never reaches the open-a-window call. Getting this backwards hides the player behind its own drawer.

## Isolation

Generalised from all four families; `.wmz` states it most explicitly.

- Engine/model work in `Sources/NullPlayer/<Family>/`, AppKit work in
  `Sources/NullPlayer/Windows/<Family>/`, fixtures under the family's own test paths.
- Do not teach the other families' types about your markup.
- Change shared files only when no family-owned seam can satisfy the requirement; keep the seam
  minimal, gate it on the controller family, and record it.
- **Never** use another family's controller, preference, `skin.json` or artwork as your default or
  fallback. Ship an app-authored unskinned fallback of your own.
- Untrusted input work goes off the main thread — archive validation, inflation, decode, XML/graph
  construction, image work, expressions, script evaluation. Hand `MainActor` only completed immutable
  snapshots and typed commands. Never `DispatchQueue.main.sync`.
- Bounded loading with stable diagnostic codes, decided before implementation and then **not relaxed
  to make one input load**. Degrade with a warning instead. The one amendment in `.wmz`
  (`WMP0005`'s ratio floor) held only because the limit was mis-specified against its own threat
  model — argued about the threat, not about the skins.

## The harness comes before the coverage

The single most valuable thing `.wal` and `.wmz` both built early. **You cannot rank work you cannot
measure**, and structural cleanliness measures almost nothing: `.wal` shipped a vertical flip and a
wrong crop origin through 490+ green tests because nothing rendered a frame; `.wmz` reached 6,044
lines with every real-skin test skipped while 4 of 14 archives were rejected outright.

Build, in this order:

1. **A corpus location** outside the repo (`~/Library/Application Support/NullPlayer/<Family>Skins`),
   archives never committed. Enumerate case-insensitively, `-type f`, and **print the count you
   measured rather than asserting a fixed one**.
2. **Probe flags**, all `#if DEBUG`, all read once at process start, each printing one machine-readable
   fact per line under a documented grammar. Document every flag in **one** canonical reference —
   `reference/harness.md` — and nowhere else.
3. **A census** (one structural row per input, with a sha256 so duplicates are visible) and a
   **render sweep**. Sweep a whole directory inside one process invocation: `.wal` does 79 archives in
   ~5 minutes where a shell loop took 25, and one invocation cannot be invalidated halfway by an edit.
4. **A committed baseline the gate ratchets against**, so a regression is a diff rather than an
   opinion.
5. A **demand-driven backlog** (`<FAMILY>_TASKS.md` at the repo root, closed entries moved to
   `docs/<family>/…-archive.md`) ranked by what the corpus actually asks for. A test case is not a
   milestone: one fix that unblocks 200 inputs beats ten that unblock one.

**And know what the harness cannot see.** It builds scenes and rasterizes them; it never runs AppKit.
A completely green sweep is compatible with a black rectangle on screen — that is exactly what
happened on 2026-09-07. Anything hosted as an `NSView` over the rendered scene is invisible to it.

**A census measures the state it drives, and every demand number it prints inherits that bound.**
The `.wmz` census raises `load` and nothing else, so a member called from a button's `onClick` does
not appear in it — `view.returnToMediaCenter` was tallied at **7 skins** and is authored by **162 of
180**, and the row sat mis-ranked for three days because the number looked like a measurement. The
shape generalizes to any family: a sweep that drives one event ranks the subset of the corpus that
event reaches. **Say in the reference which events your sweep raises**, and when a row is about a
*control* rather than a layout, count it by scanning authored script text and driving the control —
`wmp-skin-guide/reference/harness.md` § *Auditing one authored control across the whole corpus* is
the worked method, and its traps (decode every encoding and print the breakdown; resolve handler
names through the call graph; take the **median** pixel of a mapping colour, never the first) are
family-agnostic.

## Debugging a live defect

**Route to `skills/live-ui-testing` from the first version of your skill**, and read
`winamp-modern-skin-guide/reference/harness.md` § *Debugging a live defect* before diagnosing
anything that only reproduces on screen. The `.wmz` session that produced this file spent hours
rediscovering five rules already written there, because nothing pointed at them.

Every family skill carries a *Debugging a live defect* section that does that routing and adds only
what is specific to its engine. That is a required section, not an optional one.

**One hop, not a fork.** The section routes to `live-ui-testing` for the epistemics; that file
forwards the mechanics — launching into a state, driving a control, capturing a window — to
`app-control`. A family skill must not restate either; it adds what its engine does differently.

## The shape of a process skill

`app-control` is the worked example, and these are constraints on the deliverable, not style
preferences. The guides it replaced failed weak agents because they were **narrative**: they
recount how a rule was learned rather than stating the rule, and an agent reading a narrative
writes a narrative.

- **Every route section has exactly this shape, in this order:** (a) one sentence saying when this
  route applies; (b) numbered steps; (c) one copy-paste block that runs as written; (d) one
  **"Confirm it took"** line naming the observable that proves the step worked.
- **No sentence begins with a date, an incident, or "we learned".** A rule earned from an incident
  is written as the rule. If the incident is genuinely needed to justify it, it becomes a one-line
  footnote pointing at the owning harness reference, which is where the story lives.
- **No prose paragraph longer than three lines.** Tables and steps otherwise.
- **Every command in the file has been executed by its author before being written down.**
- **≤ 300 lines.** If it does not fit, something belonged in a reference file.

The *Confirm it took* line is the one that separates a process skill from the docs it replaces:
a surface whose rows fail silently is a surface an agent cannot tell it has misconfigured.

## What a family's documentation looks like

Mirror `winamp-modern-skin-guide`; `wmp-skin-guide` is the smaller version of the same shape.

```
skills/<family>-skin-guide/
  SKILL.md              a router: the safety rule, working modes, symptom → file table
  reference/harness.md  the ONLY place a probe flag or corpus command is documented
  reference/loading.md  what is tolerated, what stays fatal
  reference/<area>.md   rendering, scripting, components — split when a file gets long
  reference/skins/      one dossier per skin that taught the engine something, plus the index
<FAMILY>_TASKS.md       the ranked backlog
docs/<family>/          phase handoffs and the closed-entry archive
```

- `SKILL.md` is a **router**, not a manual — a symptom table pointing at one focused file.
- Put new subsystem detail in the owning skill, never in `CLAUDE.md` (which only gains a one-line
  index entry), and never in the always-loaded file.
- **Treat phase handoffs as unverified narrative.** Check their claims against the code before
  relying on them — `.wmz`'s phase 7 asserts a capability gate that does not exist, and its census
  numbers were wrong in both directions.
- **A corpus sweep proves the default state and nothing else.** No sweep here hovers, drags, ticks a
  timer or plays a track, so a byte-identical capture across a change to any of those means
  *unmeasured*. Build a state-aware probe (`WMP_RENDER_HOVER`, `WMP_RENDER_CLICK`'s drag form) beside
  the sweep, and say which of the two a number came from.
- **A corpus is not a memory.** A skin that produced two or more unrelated defects, or one no probe
  could see, earns a dossier in `reference/skins/`: what it exercises, what it found, **what was
  ruled out**, and the decoded coordinates that reach its controls. The ruled-out section is the one
  that saves a session and the one most often left out. Its index also carries the family's
  *counter-evidence* table — the skins that disagree with a change that looked right, one rule each —
  which is what a sweep tells you once and nothing records. `wmp-skin-guide/reference/skins/` is the
  worked example; `Cablemusic` is the dossier to copy the shape from.
- Keep a measured number next to the command that produces it. A number pasted into prose goes stale
  silently and nothing fails.

## Before the VLC family starts

- [ ] Land the `runningControllerFamily` refactor above as its own scoped, app-verified change.
- [ ] Add the `PlayerUIControllerFamily` case first and let the compiler enumerate the seams.
- [ ] Decide the auxiliary-window policy explicitly, and the route-to-a-track question with it.
- [ ] Build the harness — corpus dir, probe flags, census, render sweep, baseline — before coverage.
- [ ] Create `skills/vlc-skin-guide/SKILL.md` with a *Debugging a live defect* section routing to
      `live-ui-testing`, on day one.
