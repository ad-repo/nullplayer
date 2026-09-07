# Winamp Modern (`.wal`) — Phase 31 Handoff

**For:** the agent picking up `.wal` work after Phase 31

**From:** Phase 31 (two input-layer gaps, found from one user report about Defix's round buttons)

**Date:** 2026-08-19

Read first:

- `skills/winamp-modern-skin-guide/reference/rendering.md` §*A skin's own right-click menus* and
  §*A skin opening its own windows* — the two engine contracts this phase added
- `skills/winamp-modern-skin-guide/reference/harness.md` — `RENDER_CLICK` gained three outputs
- `skills/winamp-modern-skin-guide/skins/defix-hi-end-200.md` — the per-skin record, including the
  bug left open

---

## 0. What this phase was

One user report: *"there is a menu that is supposed to show up by the playlist button on the main
player that controls opening other windows (library etc)"*. It turned out to name two independent
engine gaps, both in the input layer, neither visible to any probe.

**The state at the end: it works well enough to use, and one real bug is left open** (§3). This is a
deliberate stopping point, not a finished feature.

## 1. The two gaps

### `onRightButtonDown` was never dispatched

Wasabi's right button is a **pair** of events and a skin is free to use either half.
`WinampModernMainView` sent only `onrightbuttonup`. Defix hangs all four of its "what does this
button open" menus off the **down** half — so the skin, `popAtMouse`, the popup presenter and the
whole `PopupMenu` implementation all worked, and not one of those menus could be opened.

`WinampModernMainView.swift` now sends `onrightbuttondown` on the press, and
`onrightbuttonup` + `onrightclick` on the release. The release is delivered to whatever the **press**
claimed, mirroring the left button: `popAtMouse` runs its own tracking loop inside the down handler,
so by the time the up arrives the pointer is wherever the user dismissed the menu — usually not over
the control any more.

### A script showing a container didn't open its window

Not every window request is a host action. `skin.xml`'s `onAction` answers the skin's own
`sendAction("opentab", …)` with `getContainer("SUI").show()` — no `TOGGLE`, no host action, nothing
for the host to see. The runtime flipped the `visible` attribute on the graph and stopped there, so
four of Defix's six button assignments re-drew the button and opened nothing.

`show`/`hide` on a **top-level container** now raises
`WinampModernScriptRuntime.containerVisibilityRequested`, which
`WinampModernMainWindowController` answers by opening or ordering out the matching auxiliary window.
Two constraints, both load-bearing:

- **Idempotent.** Skins call `show()` from timers; acting on a request for the state the window is
  already in would re-front it 30 times a second. The controller compares `window.isVisible` first.
- **Wired after `scripts.start()`** (in `makeSurfaceCoordinator`), so a `show()` from
  `onScriptLoaded` cannot pop windows open at launch.

## 2. Why one report took two round trips: three blind probes

`WINAMP_MODERN_RENDER_CLICK` drove five events and reported attribute changes. Against Defix's round
buttons it printed *"onrightbuttonup -> 0"* and *"nothing changed"* — a perfect description of four
dead controls, and wrong on every count. It could not see:

1. **the right-button *down*** — so the menu the skin builds was invisible, and
   `skins/defix-hi-end-200.md` carried "the skin builds no `PopupMenu` of its own" for several phases
   on the strength of it;
2. **`actionRequested`** — nothing was wired to it, so a button that reaches its target through an
   invisible proxy's `leftClick()` (Defix's `PLSBt`/`EQSwitch`) measured as inert;
3. **`containerVisibilityRequested`** — there are no windows in the harness, so a skin opening its own
   was unobservable.

All three are now printed (`CLICK   onrightbuttondown`, `CLICK action:`, `CLICK window:`). With them,
the whole feature resolves in one run:

```
MainBtn1=PL     CLICK action: TOGGLE param=guid:{45f3f7c1-…}
MainBtn1=EQ     CLICK action: TOGGLE param=Eq
MainBtn1=ML     CLICK window: SUI visible=true | CLICK action: opentab param=ML
MainBtn1=VS     CLICK window: SUI visible=true | CLICK action: opentab param=VS
MainBtn1=BR     CLICK window: SUI visible=true | CLICK action: opentab param=BR
MainBtn1=Video  CLICK window: SUI visible=true | CLICK action: opentab param=vd
```

This is the third phase running in which a probe's silence was read as a statement about a skin.
Phase 30 recorded the same lesson about `RENDER_SHOW` and `RENDER_VU`. **Before concluding a skin
does not do something, check that the probe drives the event.**

## 3. Open — the bug this feature stops on

- [ ] **Defix's round buttons mis-target after a re-assignment.** Reported live 2026-08-19 with both
      fixes in: the menu opens and the windows mostly open, but picking an item shuffles the buttons
      around and afterwards a button does not reliably open what its artwork says it opens.

      The shuffle itself is correct and deliberate — each `onRightButtonDown` reads all four
      `MainBtn1..4` values, and after the pick walks the other three swapping the picked target away
      from whichever button already held it, so no two buttons can share one. The defect is that a
      button's **target** and its **artwork** part company after that swap.

      The suspect is the read-back, not the menu: the artwork is set from the handler's local
      variables while the next left-click re-reads `getPrivateString`. Measure it with `RENDER_CLICK`
      (right-click then left-click at one point in one run, read `CLICK action:` / `CLICK window:`),
      seeding the start state with `WINAMP_MODERN_RENDER_CONFIG="Winamp Defix;MainBtn1=ML"`. The
      probe's presenter answers 0, so a run that needs a *pick* must be taught to return one.

- [ ] **Menu #2 from the original report was never started:** the playlist window's right-click
      context menu, and Defix's five `PE_Add/Rem/Sel/Misc/List` button menus, which are host actions
      and remain unimplemented. The user deferred this; nothing was touched.

- [ ] Everything still open from `phase-30-handoff.md` — the `<vis>` analyzer's linear scale,
      `getcurrentindex`, the dead time readout, `refreshBoundText`'s poll.
