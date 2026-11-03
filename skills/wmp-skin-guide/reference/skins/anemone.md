# `anemone.wmz`

## What it is

A Microsoft sample from July 2000, the same summer as `cerulean` and `colorchooser`. A 321x268 sea
urchin: a spiky blue ring around a black lens, with two gold blades of controls laid over it. Its
"windows" are two drawers — `playlisttray` and `controlstray`, parked at `left="307"` outside a
321-wide view — and opening one widens the player to 635 from script. One `<VIEW>`, one `.js`.

## What it exercises that little else does

**It states its visualizer's shape with the backdrop behind it, not with the container around it.**
`<effects id="visEffects" left="39" top="37" width="240" height="190" windowed="false"
zindex="-1">` is a child of the `<VIEW>`, and that view has `backgroundColor="none"` and no artwork
at all — so the container rule (W147) and `groundShape` (W174/W198) both have nothing to read. Its
own player art **must never** be read as the shape: `background.bmp` keys the lens hole and the
matte outside the urchin in the same `#00FF00`, 19,433 px of hole exactly coincident with the lens
and 30,943 of matte, which is the hazard W174 states. What does state it is the sibling immediately
behind the surface — `<subview id="blback" zIndex="-1" backgroundImage="blback.bmp"
transparencyColor="#00FF00">`, 239x187 in **exactly two colours**. See W205, and `Mandalay`, which
holds down both halves of the nearest-sibling rule.

**Its drawers are the corpus's reference case for a sticky latch read by the handler its own click
raised.** `plb` and `acb` are `sticky="true"` with `onclick="setVisibility('openPlaylist')"`, and
`setVisibility` branches on `plb.down` / `acb.down` — the value WMP flips on release, *before* the
handler runs. It also writes the latch back by name from inside the tray (`plb.down = false` in the
`closePlaylist` case, raised by the tray's own ×), so the skin exercises both directions. See W206.

**It lends no frame.** It has no ring, so NullPlayer's own windows wear the fallback glass. It was
the reference *panel* donor from W207 until 2026-11-02, when the panel path was dropped: its tray,
nine-sliced, carried the tray's own close box and keyed-out edges into our windows (W318). See
`windows/hosted-chrome.md`.

```bash
WMP_SKIN="$HOME/Library/Application Support/NullPlayer/WMPSkins/anemone.wmz" \
  WMP_RENDER_PROBE=all WMP_RENDER_CLICK='myview@185,71;206,86' \
  swift test --filter WMPRenderDumpTests/testSweepsSkinOrCorpus 2>&1 | grep -E '^WIDGET|^CLICK'
# WIDGET myview/5 effects id=visEffects frame=39,37 240x190 clip=0,0 321x268
#   visible=39,37 240x190 mask=blback.bmp@39,38 239x187 keys=#00FF00
# CLICK myview@185,71 hit=plb#9 kind=button action=- sticky=true handlers=1
# CLICK myview@185,71 changed=[… plb.down=true playlisttray.visible=true …] viewSize=635x268
# CLICK myview@206,86 hit=acb#10 … changed=[acb.down=true controlstray.visible=true]
```

The clicks are at `185,71` (playlist) and `206,86` (audio controls) — the centres of `plb` and `acb`,
decoded from the markup rather than from the picture.

## Defects it found

- **W205 — *"anemone skin has a problem with the visualization outside the skin"* (2026-09-16).**
  Confinement by a sibling backdrop. No `mask=` and no `shape=` on its `WIDGET` line before the fix,
  because it declares no `clippingColor` anywhere and so was not even in W198's population.
- **W206 — *"the playlist/eq buttons do not work"* (same report).** The sticky latch was the
  artwork's state and never the script's, so both drawers took their handler's `else` branch on
  every press. **A headless click reproduced the defect rather than the behaviour**, which is why
  `WMP_RENDER_CLICK`'s own `drive()` now keeps the latch too.
- **W207 — the panel donor.** Three answers to "a window shorter than the borders" were shipped
  and reported wrong in one session; this skin was the case for each. Dropped on 2026-11-02.
- **W318 — a square outline and shadow around the skin.** The window's skin shadow was traced
  from the palette chrome a hosted window wore before its sliced-panel frame landed. Gone with the
  panel path (2026-11-02).
- **Drawers that would not open while a track played (2026-11-02).** The 100 ms host tick
  cancelled the scene rebuild in flight, and this skin's opened drawer takes longer than that in a
  debug build, so it never landed. A tick now waits for the transaction (`hostEventTask`).
- **The cava / `flow` / PeppyMeter black box.** Not a defect of this skin's, but this skin is what
  exposed it: those three views filled their whole window before drawing the chrome, which is
  invisible under a ring and is the window under a silhouette. `SkinnedSurfaceChrome.hostedGroundRect`.
