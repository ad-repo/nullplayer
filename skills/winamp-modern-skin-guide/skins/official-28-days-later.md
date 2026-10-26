## Official 28 Days Later (`Official_28_Days_Later_Skin.wal`)

*Per-skin notes, not a graded report. Index: [skins.md](../skins.md) · a full report: `/wal-skin-report <skin.wal>`.*

- **Seen live:** 2026-10-25, debug build, playing (intake #3).
- **The display is covered by its intro for the first ~3 s, by design.** `group.intro` (`int1`, `int2`,
  `intflash`, 132x130 over the LCD) fades out on three timers (750, 100 and 500 ms, each fade at speed 1)
  and `player.maki` hides the group when the last fade reaches its target. A headless `RENDER_CLICK` or
  `RENDER_CLICKABLE` at load lands on `layer#int1`; drive with a first click and `RENDER_SETTLE=5`.
- **The vis toggles are hit on their artwork.** `vis.change.spec`/`vis.change.osc` are 13x7 outlines
  with no `rectrgn`, so the centre pixel (6,3) is transparent and a click there falls through; (10,1)
  and (7,1) are opaque. The vis mode is saved, so a launch can open on the oscilloscope.
- **The volume knob is a Layer FX rotation.** `volume.knob` is a 90x90 layer whose only artwork is a
  6x2 dot; `fx_onGetPixelR` turns it, and the press is shaped by `volume.map` (`Map.inRegion`, a disc
  about x 25–65, y 28–64). See `reference/rendering/hit-testing.md` → *a hooked layer under Layer FX*.
- **`win.center` is never defined.** The skin's `wasabi.standardframe.nostatusbar` names it as its
  background; nothing visible uses that frame (the library is synthesized in the `statusbar` frame,
  which uses `frame.middle`).
