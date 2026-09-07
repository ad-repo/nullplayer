# Hal's Eye

`1-Hal__s_Eye_v1_2.wal` · 1,555,039 B · SHA-256 `77dbb83f…cc3e3679` · author "-=RoNtZ=-", version 1.0,

- **Grade: B (provisional · confidence: low)** — from a headless pass; nobody has driven this skin. Everything it declares routes, draws and resolves, and it calls no unimplemented script method. A provisional letter is worth about ±1 (see [skin-compatibility.md](../../../docs/winamp-modern/skin-compatibility.md)); a driven `/wal-skin-report` replaces it.

**Known outstanding:**

- 1 bitmap id(s) it references do not resolve, leaving a visible gap: `about.bg`
- 2 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click

`flo@metaskins.net`. Built for the GUIOlympics '04. First worked on **B91, 2026-08-31**
(confirmed live); no `/wal-skin-report` run yet.

The archive declares `<screenshot>hals_eye.png</screenshot>` and **does not ship the file**, so there
is no reference render to check semantics against — but it ships something better, and the point of
this file is that we nearly missed it. **The skin's own user manual is the specification.** Six pages
of `imgs/manual-ani.png`, and every behaviour below is described there in the author's words. Read it
before theorising about what a control is for.

> The manual pages are drawn **white on transparent**. Opened directly, or through anything that
> composites onto white, they look like six pictures of an eye with no text at all. Flatten onto a
> mid-grey first.

A 142×142 circular player — HAL 9000's eye — with a ring of eight buttons around the rim, a display
that toggles in and out of the pupil, and four auxiliary windows (`eqth`, `config`, `manual`,
`Credits`), three of which open with the skin. `separateWindows`; the playlist and library are
synthesized. 12 MAKI programs. Compatibility **`full`** as of B91.

## State

Everything the manual describes works. Transport, the display toggle and its double-click vis toggle,
the ring's two invisible zones, the rotating eye, the four vis styles, the page-turning manual, the
credits, and the config window's latency slider, chrome toggle, desktop-alpha radios and 60-odd
colour themes.

## What B91 fixed, and what each one really was

Four causes, and only one of them was about this skin. Three were engine capabilities that had never
been exercised.

- **The manual's Back/Next buttons did nothing** (reported). `manual.maki`'s `onScriptLoaded` caches
  `getCurFrame()` and `getEndFrame()` off the six-frame page sheet, and both handlers clamp against
  the cached pair. `getEndFrame` had no **signature**, dispatch fails closed on a missing signature,
  and so the initialiser abandoned there with the end frame still 0 — which is also the current
  frame. Both guards then read *already at the end* and returned. The buttons drew, highlighted,
  pressed, ran their handler and did nothing, which is the most misleading shape a dead control can
  have. `getStartFrame`/`getEndFrame` now answer, and an unset range means the whole sheet.
- **The credits window showed one clipped line** (reported). `wrap="1"` was not implemented at all,
  and our synthesized `<Wasabi:Text>` seeded neither `wrap` nor `valign="top"`. Both are Winamp's own
  definition of the tag. The paragraph also spells its breaks `\n`, which is the only way XML can
  carry one inside an attribute value; the escapes were drawn literally.
- **The eye never rotated.** `rotate.maki`'s `onScriptLoaded` aborted on `Region.loadFromBitmap`,
  taking the rotation timer, the Layer FX warp and the region clip with it. This was found while
  probing the vis, not reported — the reporter had no way to know the eye was supposed to spin,
  because the manual page that says so is on page 3, behind the Next button that did not work.
- **Double-clicking the ring opened no menu** (reported, second round). Not this skin at all: a menu
  opened from an `onLeftButtonDblClk` runs `NSMenu.popUp` while the left button is still physically
  down, and the release that ends the double-click dismisses it before it draws. The right-click menu
  on the same object always worked, because that one is dispatched from `rightMouseUp`. See
  [reference/rendering.md](../reference/rendering.md) — *A skin's own right-click menus*.

## What the manual says the controls are

Worth keeping in full, because almost none of it is guessable from the markup:

| Page | Behaviour |
|---|---|
| 1 | Intro — the buttons and display are deliberately invisible until hovered |
| 2 — *the Controlbuttons* | Eight buttons in the outer ring, from top clockwise: Play/Pause, Open, Next, Display, Exit, Minimize, Back, Stop. Every one has a tooltip and an animation, and the animation runs as long as the pointer is over it |
| 3 — *the Display* | Toggled from the button at bottom right. Upper bar is the volume control, the second is the seek bar. **Double-clicking the display's visualisation hides it; double-clicking its location again brings it back** (`disvis.maki`) |
| 4 — *the Visualisations* | With the display off, the eye itself is the vis. It is **two invisible zones**: the inner one drags the window, the outer one switches to another vis. **Double-clicking the outer zone opens a menu of the current vis's rotation speed** — `Stop / Slow / Moderate / Fast / Change Rotate direction` |
| 5 — *the Outfit* | A chrome layout, reached by **right-clicking the ring and choosing "Configure"**, then the toggle in that window. "And don't forget the Color themes!" |
| 6 — *the Config* | Latency slider (0–1 s) sets how fast the hover animations run; the Chrometoggle button; two radio buttons for desktop alpha, which the author says to leave off — "it takes less cpu-usage and there's almost no difference" |

## Traps this skin sets

- **The two menus on the ring are on the same object and fail differently.** `vistoggle` carries
  `vis.maki`'s `onRightButtonUp` (choose the visualisation) *and* `rotate.maki`'s
  `onLeftButtonDblClk` (rotation speed). A report of "the menu does not work" is ambiguous here, and
  the difference between the two is the whole diagnosis — ask which button.
- **`RENDER_CLICK` reports both menus building correctly, and one of them does not appear.** The
  harness's popup presenter never holds a mouse button down, so it cannot see the double-click
  dismissal. This is the blind-instrument shape from
  [reference/harness.md](../reference/harness.md), and the instrument is right about everything it
  can measure.
- **`vistoggle` the button and `drag` the layer swap images.** `<button id="vistoggle" image="drag">`
  sits over `<layer id="drag" image="vistoggle">`. Both are `alpha="0"`. Do not read the ids as the
  artwork.
- **The two invisible zones are a *region*, not two objects.** `rotate.maki` builds one from the
  `vistoggle` bitmap and applies it to `MaskVis2`, so nothing in the markup says where the boundary
  is. Before `loadFromBitmap` existed there was no boundary at all.
- **The startup abort was invisible in the render.** The eye draws the same whether or not
  `rotate.maki` finished; only the *motion* and the region were lost, and a still dump cannot see
  either. `RENDER_SCRIPTS=1` and its one `failed=onscriptloaded:` line is what named it — read that
  before reading pixels.

## Confirmed live

2026-08-31, by the reporter: the manual pages turn, the credits window reads in full, and the
double-click rotation menu opens.

## Not yet measured

The chrome layout end to end, the eight hover animations against the latency slider, the colour
theme list's full range, and the `eqth` equalizer/thinger window.
