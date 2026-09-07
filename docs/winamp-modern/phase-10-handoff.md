# Winamp Modern (`.wal`) — Phase 10 Handoff

**For:** the agent picking up Winamp Modern work after Phase 10

**From:** Phase 10 (MMD3 fidelity — colour themes, script-built UI, UI Size — COMPLETE except the GUI pass)

**Date:** 2026-08-16

Read first:

- `skills/winamp-modern-skin-guide/SKILL.md` — the durable subsystem guide. **Start here**, not with
  this document; the Phase 10 findings are folded into it (colour themes, animated-layer ranges, `Map`).
- `skills/winamp-modern-skin-guide/compatibility.md` — supported/unsupported surface, limits, the
  robustness rules, and the measured-demand lists
- `TASKS.md` — Phase 10 section, with the one open item
- `~/.claude/plans/i-want-to-support-frolicking-rabbit.md` — "Post-Phase-10 state and next work"

## 1. What Phase 10 was

The first phase driven by a **user running the app and reporting what they saw**, not by a headless
suite. The report was three sentences: MMD3's drawers and knobs do not work, the text is washed out,
the window is too small. All three were real, and none of them was visible to any test in the repo.

The whole diagnosis came from two existing tools, used together, before any code was read:

```sh
WINAMP_MODERN_WAL=~/Downloads/mmd3.wal \
WINAMP_MODERN_RENDER_DUMP=/tmp/render \
  swift test --filter WinampModernRenderDumpTests
```

The dump answered "washed out" (a green, pale render against the skin's own `screenshot.png`, which
ships inside the archive and is the free ground truth), and the compatibility report — which the dump
harness now prints, including a per-finding list — answered "dead drawers and knobs" in one line: two
`error`-severity unsupported methods. **Read them together.** A skin that loads, builds a graph, and
paints pixels can still be running none of its scripts.

## 2. What landed

### Colour themes (`WasabiRenderer.swift`, `WasabiSkinInitializer.swift`)

- A `<gammagroup value="r,g,b">` is a per-channel **multiplier**, `(4096 + v) / 4096` — 0 leaves a
  channel alone. It was applied as an additive bias (`v / 4096` added), which pushes every midtone
  toward white. `WasabiGammaTransform` now parses and carries multipliers; applied to bitmaps
  (`themed`) and to `<color>` resources (`resolvedColor`, which also desaturates first when the group
  says so).
- The default theme is the **first gammaset in the document** — skins name it freely
  ("clean | orange (default)") — not the alphabetically first name. The theme *list* also keeps
  document order now, which is what Winamp's ColorThemes list shows.
- `gray` is a mode, not a flag (MMD3 ships `gray="1"` and `gray="2"`); any non-zero desaturates.
- `gammagroup` is no longer registered as a global resource. Its id is scoped to its gammaset, and
  registering it made each of MMD3's 83 themes "replace" the previous one's groups: **1404** bogus
  duplicate-id warnings, which is also why the report was too noisy to read at a glance.

### MAKI surface (`WinampModernScriptRuntime.swift`)

Two missing methods aborted `System.onScriptLoaded()` in *both* of MMD3's main scripts — and that
event is where a skin wires up its drawers, knobs, LEDs, and menus, so everything after the abort was
dead. Added, each with a signature and a dispatch path:

- **`Map`** — `loadMap` / `inRegion` / `getValue`. A bitmap the script *samples* rather than draws:
  MMD3's `map.png` is a 44×44 grayscale sweep encoding the knob's angle per pixel. `new Map` and
  `new Timer` are indistinguishable at construction (class GUIDs are not in the archive), so a dynamic
  object takes the map role on its first `loadMap`. Decoded maps are cached, bounded at 16.
- **Animated layers** — `getLength`, `setStartFrame`, `setEndFrame`, `setSpeed`, `isPlaying`, with
  `play`/`stop`/`gotoFrame` reworked. `WasabiAnimation` (in `WasabiRenderer.swift`) makes the play head
  a pure function of the time since `play()`, so the renderer and the runtime agree without either
  owning a clock. `stop()` freezes the head where it *is*; an explicit `playing` beats XML `autoplay`.
- **`Text.setAlternateText`** — a temporary override of whatever the object would show; `""` restores.
- **EQ + cursor** — `getEQ`, `getEqBand`/`setEqBand` (MAKI's −127…127 ↔ the engine's ±12 dB), `atan`,
  and `getMousePosX`/`getMousePosY`. The cursor is reported in **skin pixels**: knob scripts combine it
  with a mouse event's x/y in a single expression, so it must share those units — and that is what
  keeps UI Size out of the scripts' world entirely.
- **`Button.leftClick()`** and **event-as-method dispatch** (`slidercb.onSetPosition(getPosition())`),
  the latter limited to events with a known arity (`dispatchableEventArity`) because the stack cannot
  be unwound without one.

### Three robustness rules — read this section before touching dispatch

Each was earned from a real skin, and all three share one driver: **one skin defect must not take down
a whole script.**

1. **A call on a null object is a no-op** returning null, as in Winamp — not a thrown abort.
   MMD3 checks menu commands from a function that also runs before the menu is built. This is the
   deliberate counterpart to "unsupported methods fail closed": an unimplemented *capability* still
   fails closed, but a *null receiver* is the skin's own business.
2. **`setPosition` notifies only on an actual change.** Skins pair two sliders that write each other's
   position from `onSetPosition`.
3. **Event dispatch is re-entrancy guarded** per (target, event). Without #2 *and* #3, that slider pair
   recursed `dispatch → execute → invoke → dispatch` until the native stack overflowed — a hard
   SIGSEGV. **The interpreter's own call-depth budget cannot see this**: the recursion is native Swift
   frames, not MAKI call frames. Any future host method that dispatches an event needs the same care.

### Renderer culling

An object whose frame lies entirely outside its parent is culled **with its subtree**. Skins park
objects off-layout to hide them: MMD3 keeps a dummy volume slider at (400,400) whose `thumb` is the
44×1012 knob *sheet*, and a horizontal slider centres its thumb on its track — so the sheet painted a
column of knobs down the middle of the window from a control that is supposed to be invisible.

### UI Size (`WinampModernMainView`, `WinampModernMainWindowController`, `WindowManager`)

Wired into the **existing** `UIScaleLevel` and its "UI Size" menu — no new control, at the user's
direction. The scene stays on the skin's own pixel grid; the view applies the scale once at the drawing
boundary and undoes it once at the input boundary, so no graph object, renderer path, or script sees
it. `applyDoubleSize` takes this mode's window size from the skin's layout instead of
`Skin.mainWindowSize`, and skips the `minSize` pin so a resizable `.wal` stays resizable. Auxiliary
container windows take the same scale.

## 3. Verification completed

- `swift test` → **535 pass**, 8 opt-in skipped (was 527 + 8). Eight new tests in
  `WinampModernPhase10Tests`: gamma multiplier semantics, document-order default theme, a pixel test
  that fails under the additive form, animated-layer range playback (forward, backward, autoplay
  override), off-parent culling, and a hand-assembled MAKI script proving a null-receiver call no
  longer aborts.
- `mmd3.wal` compatibility: **unsupported → degraded**; 2 blocking script errors → 0; unsupported
  methods → 0; group findings 1404 → 10.
- Render dump matches the skin's shipped `screenshot.png`: silver body, amber display, drawers closed,
  EQ/VIS/COLORTHEMES tabs on the right edge.
- Live GUI: MMD3 renders correctly in the running app, and **UI Size 200%** scales window and contents
  together.

## 4. What is open

- **The GUI pass a human has to do** (the only open TASKS.md item): open and close each drawer
  (EQ / VIS / ColorThemes), drag the volume/bass/treble knobs, and switch colour themes. The code paths
  behind these now run — the scripts complete and the methods exist — but no one has watched them
  respond to a real click.
- **cPro-Bento's blocking list is stale.** `loadmap` was on it and is now implemented. Re-run the
  Phase 6 acceptance and re-read the report before working from the old five-method list.
- **`wasabi.*` predefined artwork** (279 group findings) is still what stands between "loads" and
  "looks like the skin" for cPro-Bento.
- MMD3's remaining 10 group warnings have not been investigated; they did not affect the render.

## 5. Advice for the next agent

- **Reach for the render dump and the compatibility report first**, together, before reading renderer
  code. Every Phase 10 defect was legible in one of the two within a minute.
- **The skin archive ships its own ground truth** — `screenshot.png`, plus (for MMD3 and the ClassicPro
  engine) the MAKI **`.m` source** next to the bytecode. Read the script that owns the broken feature
  rather than guessing at semantics; that is how `Map`, the frame-range animation model, and the −127…127
  EQ scale were pinned down instead of invented.
- **Tests passing is weak evidence in this subsystem** (Phase 7's lesson, and Phase 10's again): a green
  535-test suite had nothing to say about a skin launching in the wrong colour theme with every script
  aborted. Run the app.
