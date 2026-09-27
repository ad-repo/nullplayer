# `.wmz` rendering: the static scene, images, and the skin's own controls

A router. The rules moved verbatim from `SKILL.md` on 2026-09-24 and were split by topic into
`reference/rendering/` on 2026-09-25. Before an engine-wide change here, check the
counter-evidence table in `reference/skins/README.md`.

## Static scene and image contracts

How the scene is laid out, keyed, ordered and painted before any control is drawn. `artwork`, `keys-and-shapes` and `text` also carry a few rules from the controls section below.

| File | What it owns |
|---|---|
| [`rendering/artwork.md`](rendering/artwork.md) | Natural size of an element's own art, the 2x Lanczos upscale, `hueShift`, colour sources, BMP fallback, the render dump, `cursor`, GIF frames and animation rate |
| [`rendering/keys-and-shapes.md`](rendering/keys-and-shapes.md) | `transparencyColor`/`clippingColor`, the implicit magenta key, mapping masks, `clippingImage`, and how a body shapes a view |
| [`rendering/geometry.md`](rendering/geometry.md) | Alignment, `wmpprop:` geometry reads, empty or unreadable attributes, zero overrides, `JScript:` expressions versus script assignment, container clipping, the static layout grammar |
| [`rendering/paint-order.md`](rendering/paint-order.md) | `zIndex` ties and scripted `zIndex`, colour-only grounds, `clippingColor` beside `transparencyColor`, windowed and windowless `<EFFECTS>` |
| [`rendering/views.md`](rendering/views.md) | View size, windowless views, `openView` versus `currentViewID`/`switchView`, views kept running, `onClose`, `visible` on a view, the persisted view |
| [`rendering/compact-mode.md`](rendering/compact-mode.md) | Which skins really have a compact mode, a script resizing its own window, `view.size(corner)`, the window edge, `<RETURNBUTTON>` |
| [`rendering/script-timing.md`](rendering/script-timing.md) | The ES3 dialect, `_onchange` in the same transaction, tween endpoints and clocks, the `event` global, `wmpprop:visible`, a script-shown node inside a hidden container |
| [`rendering/text.md`](rendering/text.md) | `player.status`, `res://wmploc.dll` strings, script-written text values, `fontSize` in points, skin-shipped faces, baselines, `STATUSTEXT`, clipping and `scrolling`, `fontFace` |
| [`rendering/video.md`](rendering/video.md) | `<VIDEO>` `backgroundColor`, shrink-to-fit, the child-window loan, video readiness, natural end, a paused film's time |

## Drawing the skin's own controls

What a skin's controls draw and host. `controls` also carries the transport-control and
`BUTTONGROUP` rules from the static section.

| File | What it owns |
|---|---|
| [`rendering/controls.md`](rendering/controls.md) | Transport-control spellings, `BUTTONGROUP` state sheets, `hoverDownImage`, slider tags, metrics and filmstrips, `alphaBlend`, `passthrough`, host settle, `<POPUP>`, `<EDITBOX>` |
| [`rendering/hosted-surfaces.md`](rendering/hosted-surfaces.md) | Hosted `PLAYLIST` chrome, hosted AppKit surfaces under `alphaBlend` and the window shape, windowless `<EFFECTS>` shaping, popup height, the visualization slot and its settings, PCM delivery |
