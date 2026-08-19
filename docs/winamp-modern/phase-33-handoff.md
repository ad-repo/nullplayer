# Winamp Modern (`.wal`) — Phase 33 Handoff

**For:** the agent picking up `.wal` work after Phase 33

**From:** Phase 33 (multipass: a whole skin behind one missing MAKI method)

**Date:** 2026-08-19

Read first:

- `skills/winamp-modern-skin-guide/reference/harness.md` §*The order that made Phase 33 cheap* — the
  method, and the single most transferable thing this phase produced
- `skills/winamp-modern-skin-guide/skins/multipass.md` — the skin's own file, including the traps it sets
- `skills/winamp-modern-skin-guide/compatibility/maki-surface.md` — the six new methods, the
  `onToggle` change, and the **arithmetic** rule (division is real division)

---

## 0. What this phase was

A report that multipass "opens no drawers, and the whole skin is locked behind that". It was locked
behind that, and behind six more things underneath. The skin is now `full` compatibility, confirmed
live by the user.

The root cause is the engine's fail-closed dispatch meeting a skin that does everything in one
handler. `System.onScriptLoaded` runs eleven initialisers in a row; the **eighth statement of the
first one** calls `System.newGroupAsLayout`, which was not in `signature(for:)`. A missing method
aborts the *whole handler*, so drawers, seek, time, visualizers, sliders, the notifier, shade sizing,
behaviors and style switching never initialised. The skin was a static picture.

## 1. What was built

**Six MAKI methods**, all with measured multi-skin demand (`WinampModernScriptRuntime`):

| Method | Why | Skins |
|---|---|---|
| `System.newGroupAsLayout(id)` | the blocker | multipass, Itemskin |
| `System.strUpper(s)` | mirrors `strLower` | multipass, mmd3, Itemskin |
| `GuiObject.getClassName()` | the style switcher branches on it | multipass |
| `System.isAppActive()` | gates the drawer timer's Focus Mode | multipass, Defix, Itemskin |
| `ToggleButton.setActivatedNoCallback(b)` | state sync without re-entering `onToggle` | multipass |
| `Container.close()` | the notifier | multipass |

`newGroupAsLayout` is an **overlay child of the layout the groupdef's `owner=` names**, appended last,
keeping a `group` type (typed `layout`, its `resize` would resize the window). The coordinates confirm
that reading rather than a real floating window: the skin resizes it to `getLeft()+54, getTop()+217`,
our root layout answers 0 for both, and `RENDER_CLICK_WATCH` measures it landing at exactly (54, 217) —
where the author's own commented-out `<group x="9" y="62"/>` inside drawer.bottom (45,155) would have
been. No `owner=` falls back to the calling script's layout; a caller with no layout answers null.

**Four engine faults found *underneath* the abort**, each invisible until the one above it was fixed:

1. **A user click on a togglebutton never dispatched `onToggle`.** The only sender was `setActivated`
   — scripts talking to themselves. multipass's bottom drawer opens from that event and nothing else.
   `toggleActivation(of:)` now flips `activated` and notifies, from the view and from `RENDER_CLICK`;
   `cfgattrib`-bound controls are excluded (their state *is* the preference, and they have their own
   route).
2. **An `animatedlayer` with no `w`/`h` took its whole sheet as its size.** The seek bar resolved to
   139×**364** instead of 139×13, was clipped to a transparent sliver, and drew nothing.
3. **Its hit region was neither the frame nor the union.** It is the **union of all frames** now: a
   fill animation is transparent ahead of the playhead, which is exactly where a seek click lands.
4. **MAKI division truncated when both operands were Ints.** `mapValue / 255 * 100` and
   `seekTo(len * (pos / 255))` were both 0, so every seek click sought to 0:00. Division is real
   division now; narrowing happens on the **store** into a declared Int (opcodes 48 and 3), where the
   language puts it.

**The main-menu button.** `SYSMENU` / `CONTROLMENU` / bare `MENU` opened nothing — nine dead buttons
across five skins. They open the host context menu now, positioned under the button.

## 2. Corrections to earlier phases

- **Phase 32's "multipass ships no `<ColorThemes:List>` at all" was our bug, not a skin trait.** The
  list is at `xml/player-normal.xml:262`, inside the groupdef only `newGroupAsLayout` instantiates.
  Measured after the fix: 58 themes / **1** list / 3 actions, all resolving. `skins.md`,
  `rendering.md`, `manual-qa-checklist.md` and `phase-32-handoff.md` §2 are corrected.
- **The blind spot behind that misdiagnosis**, now recorded in `harness.md`: an object a *script*
  creates is in neither the document, the graph, nor the scene until the script runs, so no walk of
  any of the three can see it. Check `RENDER_SCRIPTS` for a failed handler before drawing any
  conclusion about what a skin contains.

## 3. Verified

- `swift test` — 785 tests, 0 failures (9 skipped, the fixture-gated ones). 17 new in
  `WinampModernPhase33Tests`, all synthetic fixtures.
- `RENDER_SCRIPTS` on multipass: `unsupported` (5 unsupported methods, `onScriptLoaded` failing) →
  **`full`**, no failed handlers.
- `RENDER_THEMES`: 58/**1**/3, `player.colorthemes` resolving.
- `RENDER_CLICK 'main/normal@17,137;148,313' SETTLE=2`: the toggle opens the bottom drawer
  (y −178→0, graph 54 → 118 nodes) and the Color Themes page puts the list at (54, 217) 164×78.
- `RENDER_CLICK 'main/normal@200,110'`: the seek bar reports and performs `SEEK TO: 3:56 / 4:05`.
- **17-skin render sweep, clock pinned**, before/after: multipass (`unsupported` → `full`),
  cPro-Bento (`Volume: 0%` → a real percentage), mmd3 (volume bar draws), winampmodern566 and
  CornerAmp (volume slider fill). Nothing else changed. **Anexa's `main-shade` differs run-to-run on
  an unchanged build** — render noise; diff a sweep against itself before calling a difference a
  regression.
- **Confirmed live** (user, 2026-08-19): "multipass looks great."

## 4. Owed

Recorded, not built — each has measured corpus demand:

| Gap | Demand |
|---|---|
| `onKeyDown` not dispatched (needs a first-responder seam) | multipass, Defix, Rika, T800, winampmodern566 |
| `onEqBandChanged` / `onEqPreampChanged` not dispatched | multipass, mmd3, Rika, winampmodern566, Overdrive_2 |
| `dblclickaction=` / `rightclickaction=` attributes read nowhere — so `TRACKINFO` / `TRACKMENU` are unreachable | 6 / 5 skins |
| `PAN` (balance slider) inert | 6 skins |
| `PE_*`, `VID_*`, `VIS_*`, `CB_*` command families inert | playlist / video / vis buttons |

Also open from Phase 32: nothing. Also open engine-wide: the `<vis>` analyzer's scale (see
`SKILL.md`, the unit rule).
