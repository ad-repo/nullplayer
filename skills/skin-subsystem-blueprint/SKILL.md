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

## Debugging a live defect

**Route to `skills/live-ui-testing` from the first version of your skill**, and read
`winamp-modern-skin-guide/reference/harness.md` § *Debugging a live defect* before diagnosing
anything that only reproduces on screen. The `.wmz` session that produced this file spent hours
rediscovering five rules already written there, because nothing pointed at them.

Every family skill carries a *Debugging a live defect* section that does that routing and adds only
what is specific to its engine. That is a required section, not an optional one.

## What a family's documentation looks like

Mirror `winamp-modern-skin-guide`; `wmp-skin-guide` is the smaller version of the same shape.

```
skills/<family>-skin-guide/
  SKILL.md              a router: the safety rule, working modes, symptom → file table
  reference/harness.md  the ONLY place a probe flag or corpus command is documented
  reference/loading.md  what is tolerated, what stays fatal
  reference/<area>.md   rendering, scripting, components — split when a file gets long
<FAMILY>_TASKS.md       the ranked backlog
docs/<family>/          phase handoffs and the closed-entry archive
```

- `SKILL.md` is a **router**, not a manual — a symptom table pointing at one focused file.
- Put new subsystem detail in the owning skill, never in `CLAUDE.md` (which only gains a one-line
  index entry), and never in the always-loaded file.
- **Treat phase handoffs as unverified narrative.** Check their claims against the code before
  relying on them — `.wmz`'s phase 7 asserts a capability gate that does not exist, and its census
  numbers were wrong in both directions.
- Keep a measured number next to the command that produces it. A number pasted into prose goes stale
  silently and nothing fails.

## Before the VLC family starts

- [ ] Land the `runningControllerFamily` refactor above as its own scoped, app-verified change.
- [ ] Add the `PlayerUIControllerFamily` case first and let the compiler enumerate the seams.
- [ ] Decide the auxiliary-window policy explicitly, and the route-to-a-track question with it.
- [ ] Build the harness — corpus dir, probe flags, census, render sweep, baseline — before coverage.
- [ ] Create `skills/vlc-skin-guide/SKILL.md` with a *Debugging a live defect* section routing to
      `live-ui-testing`, on day one.
