# Winamp Modern (`.wal`) — Phase 30 Handoff

**For:** the agent picking up `.wal` work after Phase 30

**From:** Phase 30 (the documentation split, and four GUI-only defects in Defix's auxiliary windows)

**Date:** 2026-08-19

Read first:

- `skills/winamp-modern-skin-guide/SKILL.md` — now a router; follow it to one reference file
- `skills/winamp-modern-skin-guide/reference/harness.md` § *Debugging a live defect* — the method
  this phase learned the expensive way
- `skills/winamp-modern-skin-guide/skins/defix-hi-end-200.md` — the per-skin record

---

## 0. What this phase was

Two unrelated halves.

**The documentation split.** `SKILL.md` was 1,208 lines loaded on every trigger; it is now a ~250-line
router over `reference/` topic files, with `compatibility.md`, `skins.md` → `skins/<skin>.md`, and the
unbuilt corpus-runner spec moved to `docs/winamp-modern/corpus-runner-plan.md`. Nothing was removed —
every move was verbatim and audited by heading census and content-line diff against the pre-split SHA.

**Then a user report** — "the playlist window shows art but not the track information", and "the
speakers don't animate and are very dark" — which took four engine fixes and three wrong hypotheses.

## 1. The defects, and why they took so long

### The playlist readouts: four faults stacked on one readout

Defix's playlist box writes `Items:` and `Time:` and showed neither. **Any one** of these kept it
blank, so the first two correct fixes looked like no change at all:

1. `display="PE_Info"` was never bound — the engine matched the status line on `id="PE_Info"` alone.
   The attribute form is what real skins use, **including the stock Winamp Modern skin**, whose
   playlist time had been silently blank for the same reason.
2. `System.getPlaylistLength()` was unimplemented, and the call sits *before* the write, so the
   refused method aborted the whole handler.
3. `onTextChanged` was never dispatched. The subroutine that writes both readouts has exactly one
   caller, and it is that handler.
4. Auxiliary container windows installed **no repaint route at all**, so even a correct write was
   never painted.

Lesson recorded in the router: *when a fix changes nothing on screen, look for the next fault before
reverting it.*

### The speaker cones: a scale bug, and an artwork limit

`getVisBand` was returning a linear FFT magnitude × 255. Measured live: **min 0, max 39, mean 4, p50
1** out of 255, and the 25-frame cone sat on frame 0 for **96.5%** of a track — which also reads as
"dark", frame 0 being the cone at rest. Now mapped through `20·log10` over 60 dB: **mean 139, max 232,
frames 10–15**.

This is the *second* instance of the same class (Phase 29 fixed `getLeftVUMeter` RMS→peak). **A third
is still open:** the `<vis>` analyzer reads the raw levels directly as a fraction of height, so a
full-scale band draws at ~15% height. Fix it the same way and check it the same way.

**Honest limit:** the cone animation is still nearly invisible, and that is the artwork, not the
engine. `SpAnim.png`'s frames differ from the rest frame by a mean of 0.2–0.4% brightness and at most
5.5% per pixel. Do not chase this further without an external reference showing the cone visibly
moving in Winamp.

## 2. Three wrong hypotheses, and what killed each

Worth reading, because each was plausible and each cost a round trip:

| Hypothesis | Killed by |
|---|---|
| "The readouts are written from `onTimer`" | `op25` is a **call**, not a jump — the block is a subroutine whose only caller is `onTextChanged` |
| "The spectrum isn't delivered in this mode" | A live trace: 2332 of 3347 `getVisBand` calls returned non-zero |
| "`setScale` drives the cone and is unimplemented" | `strings` hides `gotoFrame` behind a trailing index byte (`gotoFrame)`); `setScale` is never called at runtime |

The pattern: every one came from *reasoning* over source and bytecode. `WINAMP_MODERN_CALL_TRACE=1`
on the running app settled each in one launch.

## 3. Instruments added

Three probes were silently blind, and each made a real defect look absent.

- `WINAMP_MODERN_RENDER_SHOW=<container>[,…]` — open a `default_visible="0"` window in the harness,
  dispatching `onSetVisible` and settling again. Without it the cones could not be measured at all.
- `WINAMP_MODERN_RENDER_VU` now **scales the injected spectrum**. It was a constant ramp, which pins
  a `getVisBand`-driven meter to one frame however well it works.
- The dump harness stands a **synthetic queue** behind `PE_Info` when `SETTLE` is set; with no
  component host the value never changed, so `onTextChanged` could never be observed.
- `WINAMP_MODERN_SHOW_WINDOWS=<container>[,…]` (DEBUG, the **app**) — open skin windows at launch, the
  live counterpart of `RENDER_SHOW`.

## 4. Open

- [ ] **The `<vis>` analyzer is still on a linear scale** (§1). Same fix, same verification.
- [ ] **Is the cone animation visible in real Winamp?** The reference video in the per-skin record
      claims everything animates. One frame of it would settle whether 5% is all there is.
- [ ] `getcurrentindex` is unimplemented on the playlist window's hover/click handlers
      (`ontargetreached`, `onenterarea`, `onleftbuttondown`, `onrightbuttondown`, `onrightclick` —
      never `ontimer`). It takes those handlers with it; the readouts are unaffected.
- [ ] **Clicking Defix's time readout does nothing** and should toggle elapsed/remaining — a real dead
      control, and the `CLICKABLE` probe had named it before the user did.
- [ ] `refreshBoundText` is driven by host-state hooks plus a 1 Hz poll. `audioEngineDidChangePlaylist()`
      already exists and is the properer hook; switching to it would retire the poll.
- [ ] The `/` in `PE_Info`'s `N items/h:mm:ss` is inferred from Defix's parser, not verified against
      Winamp. One capture of Winamp's own playlist would settle it; it is one line to change.
- [ ] **Defix's `CONF` button, the display styles, and `Ovis 1`/`Ovis 2`** were all confirmed working
      live this phase. `Ovis 1`/`Ovis 2` appear under a raw GUID because the skin registers them into
      a different section than the other six — the skin's own bug, reproduced faithfully.
