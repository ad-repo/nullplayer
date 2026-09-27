# `US Army` and its five siblings

`US Army`, `US Navy`, `US Marine Corps`, `US Air Force`, `US Coast Guard` and `Stars and Stripes` —
one Skins Factory build (2001) re-skinned six times. The markup and script are the same shape in all
six; only the artwork and a few script lines differ.

## What it is

A round 370x370 player with no title bar. Four `<BUTTONGROUP>` quadrants (But1–But4, each an 87x95
mapping image) carry every control; four stars on the rim call `player.launchURL`. The centre
disc swaps between the metadata display, a playlist, the equaliser and a visualizer, one at a time,
each opened and closed by a JScript toggle (`playlistpop()`, `eqpop()`, `banan()`). An Info mode
(`infomode`, authored hidden) covers the face with a Help page and a Credits page, each a tall opaque
bitmap scrolled inside a 191x143 pane.

## What it exercises that little else does

- **The corpus's only `clippingImage` larger than its node on both axes** — `helpmask`/
  `creditsmask`, 191x143, clipped by the 370x370 `infomask.gif`. 12 nodes, all in this family
  (scan of every `clippingImage` against its authored `width`/`height`, 2026-09-25).
- **An `<EFFECTS>` shaped by its own `clippingImage`** (`vismask.gif`) inside a container whose
  background is the same opaque plate, which the Cerulean guard refuses as a shape.
- **`eq.visible` on the `<EQUALIZERSETTINGS id="eq">`** — 10 archives write a non-equaliser member
  on `eq` (`scripts/wms_grep.py -c '\beq\.(visible|enabled|alphablend|moveto)\b'`).
- **A pane that is authored hidden, opened by script and closed again** with script-shown children
  inside it — the counter-case to W263's pass-through.

## Defects it found

All four in one report, W309 (2026-09-25). Reported: *"you cant toggle the playlist off, the
vizulizer is outside the window, in general the buttons dont toggle"*, and later *"the help left an
artifact link after closing it"*.

- **Toggles open and never close.** `eq` resolved to the host equaliser, `eq.visible = false`
  threw, and the handlers set their flag after that line. `eq` now falls through to the element —
  `object-model/elements.md` § *The `<EQUALIZERSETTINGS>` element*.
- **Visualizer over the whole window.** The surface's own `clippingImage` was never read —
  `rendering/hosted-surfaces.md`, the `<EFFECTS>` shape bullets.
- **Pink block over the Help and Credits text.** The oversized `infomask.gif` was stretched to the
  pane and cut a hole in the text, showing `backgroundcolor="pink"` — `rendering/keys-and-shapes.md` § *A
  `clippingImage` larger than its node on both axes shapes nothing*.
- **The Skins Factory link and a scroll arrow left on the face after Info closes.** W263's escape
  let them draw through the closed `infomode`/`creditsmask` — `rendering/script-timing.md`, the W263/W308/W309
  pass-through bullet.

## What was ruled out

- **Any placement of `infomask.gif` over `helpmask`.** Stretched (hole in the middle), at the pane's
  origin (hole in the bottom-right corner) and at the parent's origin (the whole pane keyed out,
  text included) were each built or reasoned through and are wrong. The black key sits exactly on
  the pane's rect in parent coordinates, which reads as the author laying the mask out for `help`'s
  `transparencycolor` and reusing it here.
- **Hit testing.** Every click reached the right `buttonElement` (`WMP_CLICK_TRACE=1`); the toggles
  failed inside the handler.
- **The stars.** `player.launchURL` is unimplemented across the engine (132 archives call it); the
  reporter chose to leave it that way. The stars doing nothing is expected.
- **Stars and Stripes / US Air Force's first Vis click doing nothing.** Their own flag logic, with
  no handler error — not an engine defect.

## How to drive it

Window-local coordinates (the window is 370x370). Wait ~8 s after launch: `Init()` runs a 7 s
`drawer2.moveTo` intro, and the `But*init` overlays swallow clicks until `metapop()` hides them.

| Control | Point |
|---|---|
| Playlist (But3 red) | 38,258 |
| Equaliser (But3 blue) | 56,281 |
| Visualizer (But3 yellow) | 94,301 |
| Info (But2 black) | 278,53 |
| Info → Help / Credits | 220,296 / 125,296 |
| Info scroll down / up | 301,243 / 301,111 |
| Info close | 299,69 |

`WMP_RENDER_CLICK='MainPlayer@38,258;38,258'` reproduces the toggle headlessly; the visualizer,
Help and Credits need the live loop (`../harness/live-loop.md` § *Driving the app*), because each is a
post-click state the render dump never reaches.
