# `Colorchooser`

## What it is

A Microsoft SDK sample from March 2000, and almost certainly the oldest authoring in the corpus. It
is a 300x200 line drawing — a black-outlined box with a grey ellipse for its close button — over
which the whole player is built out of `<TEXT>` elements in the `webdings` face. There is no
photography, no sprite sheet and no `<BUTTONGROUP>`: five `<TEXT>` nodes whose `value` is a single
webdings glyph are the transport, and a sixth reading `choose color...` is the only affordance the
skin has. A `<SUBVIEW id="colorChooser">` parked behind the player slides out on click to reveal
three RGB sliders that recolour the player body live, and the chosen colour is saved to and restored
from a theme preference.

Five files, 68 KB: `colorChooser.wms`, `colorChooser.js`, `colorBack.bmp` (246x202), `colorSub.bmp`
(66x153), and a 1x11 `sliderBack.bmp` with a 6x11 thumb.

## What it exercises that little else does

- **The only archive in the corpus that binds a colour with `wmpprop:`** — three attributes.
  Measured over the installed corpus by scanning every `.wms` for
  `([A-Za-z]+[Cc]olor)\s*=\s*"\s*wmpprop:`, with a UTF-16 sniff on the payload first.
- **One of seven archives that name no `scriptFile`** and rely on WMP finding the same-named `.js`
  (W163). The command is in the archive's W163 note.
- **One of seven archives that assign `zIndex` from script** (W166), and the only one where doing so
  decides whether the window has a backing at all.
- **One of four views whose declared size disagrees with its own background artwork** (W164):
  `width="300" height="200"` over a 246x202 bitmap.
- An `<EFFECTS windowed="true">` sitting directly on top of an opaque `<SUBVIEW>` rather than inside
  a keyed hole. `xsn_sports` is the other windowed case and is the opposite shape — there the
  artwork over the rect is a drawer that must be hidden, here it is the floor the surface stands on.
- Geometry chained one element at a time through intrinsically sized `<TEXT>`:
  `left="jscript:stopbutton.left+stopbutton.width"` on a node with no authored `width`. See *What
  was ruled out*.

## Defects it found

The first four came from one report on 2026-09-14, *"colorchooser skin looks totaly broken from the UI I
do nto have a refrence image"*, except W166, reported separately in the same session as *"the window
has no backing when a track plays and it clicks through to the background"*.

| Row | Cause |
|---|---|
| W163 | The loader registered a program only from a `scriptFile` attribute, and this `.wms` declares none — so `colorChooser.js` never loaded, `onLoad` threw on `checkForContent()`, and `changeColor()`/`getRGB()` were undefined for every slider |
| W164 | The root `<VIEW>`'s background was stretched to the declared canvas, putting the drawn box at x=87…299 against a `mainBackground` that stayed at the authored 77…241 |
| W165 | Colours were read from the markup only, so the `wmpprop:` caption drew white on white, the mirrored transport strip drew no fill, and the sliders' script writes repainted nothing |
| W166 | `zIndex` was read from the markup only, so `checkForContent()`'s `viz.zIndex = 5` never reordered the scene; the opaque panel stayed classified as artwork *above* a windowed surface and was punched out, leaving a click-through hole while a track played |
| W218 | A `<TEXT>`'s measured width was 0 until the first layout existed, so the four buttons chained off one another all resolved to `left=16`; the glyphs overprinted and the first click in the row fired `previous`. Found by the transport audit on 2026-09-14, not by the report above, and closed 2026-09-19 |

**W164 is the one that made the skin read as "totally broken"** — the others are missing detail, but
a frame out of register with its own contents is a wrong-looking picture.

## What was ruled out

- ~~**The transport buttons stacking on top of each other is not a defect.**~~ **It was one, it is
  W218, and this bullet is kept because being wrong here cost two phases.** Everything it says about
  the mechanism is accurate — the chain converges on the next transaction because the script model
  learns an intrinsic size from the geometry the last scene resolved (`WMPScriptRuntime.transact`'s
  `geometry:`). The conclusion drawn from it was not. *"The running app lays all five out
  correctly"* was never measured; it was inferred from the mechanism, and it is false for the frame
  that matters. **A skin gets exactly one first frame, and a user's first click lands on it.**
  Driven cold, `WMP_RENDER_CLICK=view-2@109,35` — the stop glyph's authored spot — reported
  `hit=prevbutton#14 … command=previous`, and `view-2@145,35`, where prev should be, reported
  `MISS`. `WMP_RENDER_SETTLE` does not repair it; only an event does, and the repair rides on the
  same click that misfired. Closed by measuring a `<TEXT>` before the first layout exists; the rule
  is in `reference/bindings.md` § *A `<TEXT>` is sized by its glyphs*.
- **`UNRESOLVED view-2/3 text id=style size=missing literal geometry (width+height)` is not a
  defect either.** `<TEXT id="style">` is a palette holder with no geometry on purpose; it is read
  through `wmpprop:` and never drawn.
- **`theme.loadPreference` was not the cause of the missing panel fill.** It already answers WMP's
  `--` sentinel for an unsaved key (`WMPObjectModel`), so `onLoad`'s
  `if (temp!='--') {mainBackground.backgroundColor = temp; …}` correctly does not run on a cold
  profile. Checked because W165 made an unparseable colour override reachable for the first time.
- **The white showing through was not the effects surface being opaque, and not `WMPMainView`'s
  blit.** `WMP_RENDER_APPKIT` hosts the real view stack and reported
  `differing=0/240000 outside=0 blit=0` with the panel drawn — the headless capture is correct and
  the live window was not, which is what pointed at the `playstatechange` write the harness never
  raises.
- **The view's `transparencyColor="white"` keying is correct** and is why the window has no square
  edge. Only the region the *panel* should have filled was wrong.

## How to drive it

```bash
skills/app-control/scripts/launch.sh Colorchooser
```

**A stopped player is the one state in which this skin is correct**, so a pass with nothing playing
measures the wrong thing — W166 is invisible without `NULLPLAYER_PLAY`. `WMP_RENDER_HOST=playing` is
not a substitute: it seeds the snapshot but does not raise `playstatechange`, which is where the
`zIndex` write lives.

The view is `view-2` (the `<VIEW>` carries no `id`), 300x200. Frames in scene coordinates, from
`WMP_RENDER_PROBE=all`:

| Control | Frame | Notes |
|---|---|---|
| close `x` | `50,4 8x17` | in the grey ellipse, outside the box |
| transport | `91,29`…`151,41`, 12x12 each | play, stop, pause, next, prev, left to right |
| `choose color...` | `82,180 64x11` | slides `colorChooser` out to `left=10` and back to `71` |
| `viz` (`<EFFECTS windowed="true">`) | `77,50 164x130` | hosted only while playing |
| `colorChooser` panel | `71,34 66x153` | `zIndex="-1"`, parked behind `mainBackground` |
| RGB sliders | `76,64` / `76,114` / `76,164`, 40x11 | `min=0 max=255`, thumb 6x11 |

The sliders are the round trip worth driving: a `WMP_RENDER_CLICK` drag written
`view-2@80,69>110,69` should move `mainBackground`'s fill, which is the whole point of the skin and
touches W163, W165 and the mirror on `transport_subview` in one gesture.
