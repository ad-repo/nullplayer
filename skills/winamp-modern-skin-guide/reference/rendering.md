# Rendering a `.wal` skin

Reference for the `winamp-modern-skin-guide` skill: clipping, hit testing, text and fonts, the drawable elements, colour themes, and animated layers.

#### Region clipping

A script can clip one control to a shape taken from a greyscale **map** bitmap. `Region` is created
by the same bare `new` as `Map`/`Timer`/`List`, and `Region.loadFromMap(map, threshold, reversed)`
settles its role; the map's red channel is read as a 0–255 position, `reversed` keeping every pixel
at or below the threshold and the plain form everything at or above. `Layer.setRegion(r)` applies it,
`Layer.setRegionFromMap(map, threshold, reversed)` is the same without the intermediate object, and
`Region.offset(dx, dy)` moves the shape in map pixels.

The renderer draws from the graph and nothing else, so `setRegion` stamps the region onto the object
as namespaced `nullplayer.script.region.*` attributes and calls `graphDidMutate` — the same route
`play`/`gotoFrame` take. `WasabiSceneRenderer.applyRegionClip` turns them into a `CGContext.clip(to:
mask:)`, and the mask is decoded **without** the colour theme's gamma: a map's channels are data, not
artwork, and skins routinely put maps in a `gammagroup` (T800 puts its in `Background`) which would
move every threshold. The mask is placed at its **natural size** at the object's origin, not
stretched to the object's rect — a region is a set of map pixels. A map that cannot be resolved
leaves the object unclipped, and regions deliberately do not affect hit testing: T800 drags its
volume by tracking the mouse across the whole strip, most of which the region has clipped away.

#### Hit testing: who owns a point

`object(at:)` walks the scene in reverse (`sceneNodes()` is a pre-order DFS, so reversing puts every
object ahead of its own parent and every later sibling's subtree ahead of an earlier one), then
alpha-tests the node's bitmap. **The region is every pixel the skin actually painted — `alpha > 0`,
Wasabi's own rule** (`WasabiRenderer.regionAlphaFloor`). It was `> 8` until B27, to shrug off
anti-aliased fringes, and that threshold quietly assumed artwork drawn at full opacity. A skin is
under no obligation to oblige: LOBE draws its entire button set as glassy discs whose **maximum**
alpha is 79/255, each icon engraved into its disc at alpha **3** — a hole exactly where a user aims.
Thirteen of its twenty-three main-window controls were dead at their own centre, and because the
click then fell through to whatever layer sat behind them the window read as *inert* rather than as a
button that had missed. Two things make that diagnosis reachable: its `toggle-always-on-top` uses the
same artwork and worked, because `rectrgn="1"` skips this test (the control experiment), and
`RENDER_CLICK` names the object the click **fell through to**, never the one it rejected — so check
the intended target's own artwork alpha before theorising about z-order. When lowering a region
threshold, check the skin's hover/pressed overlays: they sit directly above the control and are often
opaque, and what keeps them out of the way is `ghost="1"`, which `object(at:)` honours first.

**The gate this change needed, and its result.** Lowering a hit-test floor moves no pixels, so no render sweep applies; the regression vector is the opposite direction — a non-ghost layer with faint-but-non-zero alpha drawn *above* a control, which used to let a click through and now takes it. `WINAMP_MODERN_RENDER_CLICKABLE=1` across the installed corpus at both floors settles it: **28 skins, 231 layouts, 124 → 111** rejected-but-scripted objects and **zero rises anywhere** (2026-08-21). A *fall* is the fix working — LOBE `main/normal` 7 → 1, `main/switch` 4 → 0, micro 7 → 4. Run it that way for any future change to `object(at:)`.

Two rules about *which* objects may claim a point:

- **A container has no region of its own — its children supply one.** A `group` (or `layout`) is
  claimable only where it paints a `background`. MMD3 declares `<group id="main.mmd3" move="1">`
  **last** in its layout, covering the whole window, so accepting a bare group for `move="1"` made it
  swallow every click that was not over one of its own children: the drawer tabs, the colour-theme
  strip, and the EQ tabs (all declared *before* it) were completely dead while the play buttons
  *inside* it worked, which is exactly what the bug report said. Window dragging is a separate policy
  (below) and is unaffected.
- **`rectrgn="1"` *is* the object's region — its whole rect, artwork or not.** Skins use a bare layer
  with it as an invisible click target (Love is War Miku switches its visualization mode through
  `visual.trigger`, a layer with no image at all), and a hit test that insists on a bitmap can never
  reach one. It also **settles the alpha question**: `object(at:)` skips its bitmap alpha test for a
  `rectrgn` object, because testing the artwork anyway contradicts the attribute. Defix's four
  main-window buttons are `rectrgn="1"` icons drawn as outlines, and a click landing in a transparent
  gap fell straight past the button onto the `ButtonBG` panel behind it — so its first and fourth
  buttons (playlist and video) were completely dead while the second and third, denser under the same
  point, worked. That reads as "two of my buttons are broken", not as a hit test disagreeing with a
  declared region. Only objects that *have* a bitmap are affected; a bare `rectrgn` layer never had an
  alpha test to skip.
- **`animatedlayer` is clickable like `layer`.** MMD3's rotary volume/bass/treble knobs are animated
  layers whose scripts hook `onLeftButtonDown`; leaving the type out of `isInteractive` meant no click
  ever reached them.
- **A command on the *second* click or the right button makes an object claimable too** (Phase 36).
  `dblclickaction=` / `rightclickaction=` are commands like `action=`, and for a `<text>` they are
  usually the only one it has: a song title is not one of the interactive types and carries no
  `action`, so before this every double- and right-click on one fell through to the background layer
  behind it. `ghost="1"` still outranks the attribute — `object(at:)` drops a ghost before
  `isInteractive` is consulted at all, which is what keeps multipass's `ghost="1"` playlist ticker
  (which carries `dblclickaction` anyway) from swallowing clicks meant for the list.

#### The three action attributes (Phase 36)

An object may carry `action=`, `dblclickaction=` and `rightclickaction=` **independently**, and skins
do: multipass's song title has the last two and not the first. The view performs each on its own
gesture — `action` on the click, the other two after `onleftbuttondblclk` / `onrightclick`, both gated
on press and release agreeing on the target. Only `action` flips a togglebutton or falls through to a
`cfgattrib` binding; the other two are plain commands.

The parameter has two spellings, decoded once in `WasabiClickAction` so the view and the probe cannot
disagree:

- a `;`-separated **tail on the action itself** — `dblClickAction="SWITCH;shade"`, 45 of the 62
  measured uses. Only the first `;` separates, so `action="SWITCHTO;optionsgroup.notifications;subpage"`
  keeps its second field.
- a sibling **`dblclickparam=` / `rightclickparam=`**, which wins when both are present.

The tail split is applied in the view's action switch, so it serves `action=` as well.

The corpus is wider than the button-shaped reading of it suggests: 62 declarations in 9 of the 17
skins, and most are not `TRACKINFO` at all but the **winshade switch** — a bitmap-less mousetrap layer
over the titlebar with `dblclickaction="SWITCH;shade"` (mmd3, multipass, winampmodern566, ZDL,
Overdrive_2), with the shade layout's own background layers carrying `SWITCH;normal` back. mmd3 also
puts the attribute on the `<layout>` itself. `RENDER_CLICK` prints `CLICK dblclickaction:` /
`CLICK rightclickaction:` for whatever it hits, which is how a mousetrap is told from the background
under it — and note the trap is only 18px tall, so a click 30px down the titlebar reports the
background and looks like a bug in the fix.

`TRACKINFO` opens a File Info **sheet** for the playing track. Never `runModal()`: the action is
reachable from a script (`sendAction`), and a modal run loop an untrusted skin can enter at will is a
hang the user cannot dismiss the app out of. `TRACKMENU` opens a track menu (File Info, Copy Title,
Reveal in Finder) at the pointer, disabled items and all when nothing is playing — a right-click that
produces no menu reads as a dead control. Neither is `SYSMENU`, which stays the host's main menu.

#### Dragging the window

`WinampModernMainView.shouldDragWindow(from:)` decides whether a press moves the window, from the
object the hit test returned:

- the **`layout`** itself — the window's own background. A skin that paints its whole frame there and
  hangs nothing but controls off it (T800) has no other handle, and without this it cannot be moved.
- **anything carrying `move="1"`** that is not a control. This is the skin *affirmatively* naming a
  handle, and it says so on far more than groups: across the 30 installed skins `move="1"` appears
  **981 times on 14 element types** — `group` 421, `rect` 233, `layer` 151, `text` 66, `grid` 36,
  `grouplist` 34 — and honouring it only on `<group>` left 560 declarations doing nothing. Big Bento
  Modern is the measured case: its titlebar is `<grid … move="1">` over a
  `<rect id="vic_mover" move="1" fitparent="1">`, so the window could only be dragged wherever a bare
  background happened to be topmost, and it went **undraggable after a trip through shade mode and
  back** as the topmost object under the pointer changed.
  Controls are excluded even when they say `move="1"` (17 of the 981 do): a button that both acts and
  drags would swallow its own click. Winamp distinguishes those by press-and-hold, which this hit
  test does not model — see `WinampModernMainView.controlTypes`.
- a **`layer`** with no `action` — *unless a script hooks a mouse event on it*, which makes it a
  control rather than a handle (the same thing `move="0"` says explicitly, for the skins that do not
  bother to say it). Dragging the window off an invisible trigger eats the click it exists for.
- never anything with `move="0"` (T800's volume strip is a layer whose script owns the drag), and
  never the named transport/title objects on the exclusion list.

`WINAMP_MODERN_RENDER_CLICKABLE=1` is the check for both hit-test rules: it lists objects a script hooks the mouse on
that the markup-only hit test rejects. It is not expected to be empty — several objects legitimately
share a rect and only the topmost can win — but a control the user can see should never be in it.

#### `sysregion` is signed, and a **negative** one means "do not paint" (Phase 34)

A layer can contribute its bitmap to the **window region** instead of to the picture. The attribute
is a signed combining mode, and only the sign matters to the renderer: a negative value is
*region only*. The bitmap behind such a layer is a silhouette, not artwork — Ujola Cat's
`window-regions.png` is a magenta-and-white mask — and painting it puts a coloured slab across the
window. `standardframe.xml` is where this bites: its `wasabi.frame.layout` carries five
`sysregion="-2"` layers and is inherited by every `Wasabi:StandardFrame:*` flavour, so the mask landed
on the playlist window, on the synthesized library window, and on anything else framed the same way —
reported as "layered full backgrounds in different colours" and "multiple top menubars".

`sysregion="-2"` appears in **11 of the 18 installed skins** (winampmodern566 alone uses it 24
times), so this is a corpus-wide rule, not one skin's quirk. Absent, `0`, a positive value (Ujola's
own console art is `sysregion="1"` over real bitmaps) and the non-numeric forms skins write (`"AND"`,
which Anexa uses 15 times) all paint exactly as before. The region itself is still not *applied* —
the windows are rectangular — so what changes is only that the mask stops being drawn: the corners of
winampmodern566's framed windows go from opaque black to transparent.

#### `<vis mode>` — the skin says whether it wants a visualization at all

`1` = **spectrum analyzer**, `2` = **oscilloscope**, `0`/`3` = **off**; an undeclared mode is the
analyzer. A skin's own menu script pins the pairing: Love is War Miku's `visualizer.maki` writes
`bandwidth` (`wide`/`thin`) then `setMode(1)` for its *Spectrum Analyzer* commands and `oscstyle`
(`Solid`/`Dots`/`Lines`) then `setMode(2)` for its *Oscilloscope* ones. Reversed, every skin drew the
other visualization than the one its menu had just asked for, and this skin's shipped default
(`Visualizer Mode` = 1) came up as a scope where its own screenshot shows bars.

MMD3 ships `mode="3"` and its `ShowVISBg` switches between all three, because for six of its nine
display styles the box is filled by the skin's *own* animated layer and the vis must be silent.
Ignoring the mode painted our bars straight over the skin's artwork. `setMode` writes the same
attribute, so honouring it in the renderer is the whole implementation.

A `<vis ghost="1">` takes **no** clicks — Love is War Miku puts an invisible `<layer rectrgn="1">`
beside it as the click target instead, so the menu is reached through that, not the box.

#### The oscilloscope reads PCM, and the host has always had it (B51)

`mode="2"` is drawn from Winamp's own `visdata` waveform — 576 `UInt8` samples per channel centred on
128, **left channel only**, one column per pixel of box width. The mirrored second box is the *skin's*
job (`fliph`), not the renderer's.

It was a spectrum-derived zigzag for a long time on the stated premise that *"the host publishes a
spectrum, not raw PCM"*. **That premise was false the whole time**: `AudioEngine` posts exactly this
array on `.audioWaveform576DataUpdated`, consumer-gated, and vis_classic and the waveform views were
already consuming it. The lesson is the general one — *check what the host already publishes before
building a substitute for it*; a placeholder that survives long enough acquires a rationale.

**The tap is demand-gated and the demand is graph state.** `WinampModernWaveformTap` runs only while
some `<vis>` in the graph asks for a PCM-fed mode — **any**, not all: one scope among five analyzers
still needs it. `WasabiSceneRenderer` recomputes that against the graph's `mutationGeneration` (the
key `sceneNodes()` already uses) and pushes it to the host only on a change. `mutationGeneration` is
the right key because **`mode` has two writers**: `setVisualizationAttribute`, and MAKI's `setMode` /
`setXmlParam` writing the object directly — and a skin's own visualization menu is entirely the
second kind, so anything keyed on the setter alone would miss it.

**Chunks are queued and played out in real time, not overwritten.** `processAudioBuffer` runs once per
2048-frame buffer (~46 ms) and posts every 576-sample chunk it can from inside that one call, so they
arrive three or four at a time. Keeping only the newest discarded three quarters of the audio and left
the survivors 46 ms apart — which reads as a scope that jumps, and is a *discarded-data* problem, not
a frame-rate one. The queue is capped (6 chunks ≈ 78 ms) so the trace cannot drift behind the music,
and a read is a pure function of the clock so every box in a frame draws the same chunk. The renderer
takes the waveform **once per frame** for the same reason: two boxes reading microseconds apart can
straddle a 13 ms boundary, and in Big Bento's butterfly that is a mirror that does not mirror.

Every other `<vis>` attribute is read too — `oscstyle`, `coloring`, `peaks`, `falloff`,
`peakfalloff`, `colorosc1`…`5` — see `compatibility/wasabi-surface.md` for the list and the measured
0…4 falloff scale. **Both falloffs are per second, not per draw**: draws are not a clock (the vis
clock below drops frames when a scene is expensive), so a per-draw constant would make
"Slower…Faster" mean different things on different skins, window widths and splitter positions.

#### What the analyzer actually draws (Phase 34)

Three rules, all of them measured on Ujola Cat, all of them engine-wide:

- **Vis colours take the object's `gammagroup`.** `colorband1`…`16`, `colorallbands`, `colorbandpeak`
  and `colorosc1`…`5` are usually inline `r,g,b` triples, and the named-resource path
  (`resolvedColor`) leaves an inline triple untinted — so an analyzer stays its declared colour while
  the skin recolours around it. Resolve them through `objectColor(_:gammaGroup:)`, which hands a named
  `<color>` back to `resolvedColor` so a themed colour is never tinted twice. Ujola Cat declares all
  22 of its vis colours inline under `gammagroup="Energy"`, and its author's one request was to go and
  play with the skin's colour themes. **`<eqvis>` is deliberately left out**: that skin's own comment
  reads *"note: eqvis doesn't support gammagroup; known bug"* and works around it with white — which
  is Winamp's behaviour, so matching it is correct.
- **Bar height is a decibel, not a magnitude.** `host.spectrumLevels` is a linear FFT magnitude, and
  scaling it straight to the box puts ordinary music along the floor. Map it through
  `WinampModernScriptRuntime.visByte(forMagnitude:)` — 20·log10 over a 60 dB window — the same
  function `getVisBand` and the VU meters answer in, so the drawn analyzer and a skin's scripted
  meters can never disagree about the same audio. (Phase 29 fixed the VU meter, Phase 30 `getVisBand`;
  the drawn analyzer was the third and last site.)
- **`bandwidth` picks the band *count*.** `wide` is 19 bands, `thin` up to 75, each collapsed from the
  tap by max-per-bucket and clamped so a bar is at least 1px wide. It used to pick only the bar
  *thickness* while the bars stayed one per FFT bin, so every skin drew the same 64 hairlines — and
  silently dropped the top 11 of the tap's 75 bands. Bars are laid out on **whole pixels**: at a
  fractional slot the 1px gap antialiases into a smear and a `wide` row reads as one solid block.

`colorbandpeak` is the falling cap over each bar, held at the running max and decayed a fixed amount
per draw, and painted in the band's own colour when the skin declares no peak colour.

#### NullPlayer's own analyzers in a skin's `<vis>` box (B53, 2026-08-26)

The `<vis>` box stays the skin's — its geometry, its colours, its `mode` — and **what paints it** is a
per-skin choice between three engines, all `WasabiVisRenderer` implementations behind B51's seam:

| Choice | Engine | Input |
|---|---|---|
| `Skin's Own` (default) | `WasabiBuiltInVisRenderer` — Winamp's analyzer and oscilloscope | spectrum bands / the 576-sample tap |
| `Cava` | `CavaVisRenderer`, a `CavaPresenter` on the `winampModernVisBox` scope | its own full-stereo tap |
| `vis_classic` | `VisClassicVisRenderer`, scope `winampModernVisBox` | **B51's existing 576-sample tap** — no second audio consumer |

Selection lives on `WasabiSkinRuntime.spectrumAnalyzer` (skin-wide, beside `componentBucket`, because
one skin draws its `<vis>` in several containers) and persists per skin in `@nullplayer.vis` /
`engine`, stored **by name** so a list reorder cannot re-point it. The default is always the skin's
own: a skin looks the way its author drew it until the user says otherwise.

**Two of the skin's compositional habits do not transfer, and both are decided in `WasabiRenderer`.**
`fliph` is dropped for a non-skin engine (`flipTransform(…, suppressHorizontal:)`) — Winamp's
butterfly mirrors a row of *bands*, and a mirrored frequency sweep runs backwards. And a **run** of
adjacent boxes is handed the whole run's rect with a clip to each box
(`visualizationRows(boxes:)` — same top edge, same height, touching within 2px), so Big Bento's
`main.vis` + `main.vis2` show one continuous analyzer instead of two copies of the same one. Its 10px
`flipv` reflection strips are a run of their own and still reflect.

**vis_classic processes once per buffer, draws once per box.** `processAndDraw` runs the FFT *and*
ages the core's bar/peak decay, so calling it per box would make the falloff a function of how many
boxes a skin declares. An identical input buffer means "another box of the same frame" — the renderer
samples the waveform once per frame — and takes `drawAtSize` instead.

##### Gain: three engines, one loudness — where to tune it

The three measure the same audio on scales that were never meant to agree. Winamp's analyzer maps its
bands through a **decibel** curve (`visByte(forMagnitude:)`), so ordinary music fills the box and it
reads *hot*; Cava normalises linearly under its own slow auto-gain; vis_classic scales against a
canvas cut for a 128px-tall window. Side by side in a 30px skin box, the first is hot and the other
two are cold. Reported live, and settled by eye — which is the only instrument that settles "hot".

**All four numbers live in one place: `WasabiVisStyle.Gain`.** Change them there and nothing else
moves.

| Constant | Value | Applied |
|---|---|---|
| `builtInAnalyzer` | 0.8 | to the band fraction, after the dB byte |
| `builtInOscilloscope` | 1.0 | to the sample excursion, **clamped** to the box so a hot scope flattens instead of drawing outside the author's rect |
| `cava` | 1.45 | to the bars, clamped at 1 |
| `visClassicInput` | 1.6 | to the **input** samples about the 128 centre line — the core runs its own FFT and paints its own bars, so there is no output height to scale without stretching its artwork |

On top of that sits **Sensitivity** (`WinampModernVisSensitivity`), the user's five-step adjustment as
a percentage of the calibration: 60 / 80 / **100** / 130 / 160, so `Normal` is exactly the tuned value
and a step means the same thing for every engine. It is stored **per engine, not per skin** — it
calibrates an engine's own scale, so a Cava turned up once stays up everywhere, which is the opposite
of the engine *choice*. The skin's own engine has one Sensitivity covering both its modes and two
calibrations under it. Reading it is memoized (`invalidateCache()` for tests); a change repaints
through `WindowManager.repaintWinampModernVisualization()`, because the visualization clock only runs
on audio and would otherwise not show the new gain until playback resumed.

##### The menus, and the one that is not ours

Both routes offer the same thing: the engines are **mode rows in one radio group** beside Winamp's own
`Spectrum Analyzer` / `Oscilloscope` / `Off`, followed by the running engine's own settings
(`<Engine> Settings ▸`, or Sensitivity alone for the skin's engine). They are one answer to one
question — what is in this box — so they are one group, and picking a skin mode hands the box back to
Winamp's engine while picking an engine switches a box the skin had turned off back on.

- **Skins → Modern → Spectrum Analyzer** in the menu bar, which no skin can intercept.
- **Right-click on the box**, including on skins that trap that click: a skin's own menu is *ours to
  build* (`presentScriptPopup` turns MAKI's `PopupMenu` tree into an `NSMenu`), so the section is
  inserted into Big Bento's own visualization page. Its `Classic Visualization` row is dropped there —
  it is Winamp's *plugin* switch, which NullPlayer does not host, and it is the same question the
  group now answers.

> **The bug worth remembering.** Our rows leave the script's command id at `0` deliberately —
> "nothing chosen" — and a **submenu parent carries `0` too**, which is exactly what Big Bento's own
> `Spectrum Analyzer ▸` row is. Collecting `0` into "the skin's mode rows" made every pick of ours
> select an engine and then hand the box straight back to the skin's, four milliseconds later, with
> nothing on screen to say why. `commandIDs(of:)` excludes zero.

#### The analyzer a `<component>` box draws (BB9, 2026-08-24)

A `{0000000A}` holder that the view layer has *not* filled with the host's engine draws a spectrum
analyzer — see [components.md](components.md) for which holders those are. It is no longer a
placeholder: the slot's default content in Winamp *is* an analyzer.

`drawVisualizationBars` has **no `<vis>` element** to take its styling from, and deliberately borrows
none:

- **Band count comes from the box** (~1 band per 6pt, clamped to the tap's own resolution), not from a
  donor's `bandwidth`. Borrowing was tried and is wrong — `bandwidth="wide"` is 19 bands, sized for
  that skin's own 144px box, and 19 bands across a 1400px pane is a row of slabs.
- **Colours come from `WasabiPalette`** — the same route every other NullPlayer-owned surface inside a
  `.wal` takes, so a colour-theme switch recolours it with everything else. Bars are a vertical
  gradient from `listText` down toward `contentBackground`; peak caps are `listText`.
- Whole-pixel bar slots and the `<vis>` analyzer's falling caps and decay, sharing the same
  `analyzerPeaks` store — a `<component>` holder and a `<vis>` are different objects, so the keys
  cannot collide.

#### `<Wasabi:Frame>` — the splitter that builds its own children

Most objects are declared where they appear. A frame is not: it **names** two groups and instantiates
them itself (`WasabiFrame`). cPro-Bento's entire body is one —
`left="centro.components" right="centro.playlist1" from="right" width="200"` — so treating it as an
ordinary group left the library tree, the playlist and the tab strip out of the graph completely.

- `left`/`right` → vertical divider; `top`/`bottom` → horizontal. The pair present decides the axis;
  `orientation=` is written both ways (`vertical`, `v`, `h`) and is not trusted on its own.
- `from` is the edge the divider is measured from (`left`/`top`/`right`/`bottom`, often abbreviated).
  **The pane *opposite* `from` absorbs any extra width**, which routinely reads as a defect on a
  wide window: Big Bento's `from="left"` pins the divider near the left edge and lets the
  right-hand playlist-info pane take the rest, and its `maxwidth="-300"` says so out loud.
  cPro-Bento is the same attribute the other way round (`from="right" width="200"`), which
  confirms the reading. Check `from` before calling a lopsided split wrong.
- The offset is seeded from `width`/`height` and thereafter owned by the `position` attribute, which
  `setPosition()` writes. **On a frame, `getPosition`/`setPosition` are the divider offset**, not a
  slider value — ClassicPro closes its side view with `setPosition(0)` and asks `getPosition()==0`.
- Layout is expressed by writing the panes' *own* geometry attributes, so `WasabiGeometrySpec`
  resolves them like anything else and a parent resize needs no frame-specific code. A pane that
  would go negative collapses to zero instead of flipping inside out.
- The divider is draggable. Its 8px grab strip (`frameDividers()`) takes the resize cursor and wins
  the hit test over whatever is beneath it; a drag rewrites `position` through the same
  `setPosition` path a script uses, so the panes re-lay out and hosted subviews follow.
  `minwidth`/`maxwidth` bound it — skins spell them that way for a horizontal frame too
  (ClassicPro's `centro.plframe`), and a **negative** limit is measured from the far edge
  (`maxwidth="-224"` = "always leave 224px for the other pane"). `jump` (snapping) is not honoured.
  **When a skin declares both spellings, the split axis's own name wins** (BB32): Big Bento's
  `playlist.dualwnd` is horizontal and carries `minheight="100"` beside a leftover `minwidth="313"`,
  and reading the first name found made 313 the floor for a *height* — one drag snapped the
  album-art pane to a third of the window with no way back. The width names stay as the fallback,
  which is all `centro.plframe` ever needed.
- A divider pushed flush with an edge (`setPosition(0)`, how ClassicPro closes its side view) offers
  no grab strip, so a closed split cannot be reopened by dragging where it used to be.

##### Where the user left the divider survives a relaunch — where the *skin* put it does not (B44, 2026-08-24)

Nothing a `.wal` skin's own state amounted to used to survive a quit. The graph is reseeded from the
markup every load and the skin's scripts then re-run their own `setPosition`, so a splitter dragged
wide came back narrow. It stayed invisible for the whole B35–BB22 run because of what it hides: Big
Bento's header analyzers (B43) live past the divider's default column, so on a fresh launch nobody had
ever seen them.

The rule is narrow on purpose. **Only a drag is stored** — `persistFramePosition(of:)` is called from
mouse-up and from nowhere else. A script moving its own splitter is the *author's* layout speaking:
Bento's `setPosition(434)` with `from="left"` genuinely ships "narrow player, wide playlist" and pins
the left pane at 434 however large the window grows, and there is no clamping bug on our side to fix.
Storing that would freeze the opening layout into a preference the user never expressed, and
overriding it outright is not ours to do. This is also why it is **not** a `WasabiSkinQuirks` entry:
that file's bar is *arithmetic the skin gets wrong, derivable from the skin's own numbers*, and this
fails both halves.

- Stored in the skin's existing namespaced configuration (`WinampModernConfiguration`, the same store
  behind `setPrivateInt`) under section `@nullplayer.frames`, keyed **`container-id/frame-id`**. Those
  are the two names that survive a reload; `stableID` is a per-load counter and would address a
  different object next launch. A frame with no `id` is skipped rather than given a positional key a
  markup edit would silently reassign.
- `-1` is the "never dragged" sentinel, because **`0` is a legal stored position**: ClassicPro closes
  its side view with `setPosition(0)` and a user may leave it closed.
- Restored from `layoutNodes()`, not `sceneNodes()` — Wasabi lays a hidden object out anyway, and a
  splitter inside a drawer that happened to be shut at quit still has a position the user set.
- **Also restored on every layout activation**, not only at launch: `persistableFrames()` sees the
  *active* layout only, so a divider dragged in a layout the user switched to later was stored and
  then never put back (B44a).
- The stored offset is **re-clamped against the box as it is now**. A negative `maxwidth` is measured
  from the far edge, so an offset that was legal in a wide window is out of bounds in a narrow one.
- **The ordering trap, and it is the whole difficulty.** The skin's `setPosition` runs at load, so a
  restore has to land after the scripts settle or it is simply stomped — the same trap B38.2 hit. Each
  view restores its own splitters in `scriptsDidStart()`, *before* the seeding resize dispatch, so a
  script whose state is only assigned in `onResize` is told the geometry the user actually left. That
  is enough when the skin calls `setPosition` from `onScriptLoaded`, which is the common case and
  Bento's. It is **not** enough when the call comes from a timer, so the window controller re-asserts
  once at 1.0s — comfortably past the 700 ms one-shot Bento's own `mcvcore` starts (BB9). The
  re-assert **re-reads the store** rather than replaying what it restored, so a divider dragged inside
  that first second is not pulled back to where the window opened.

##### What else the host remembers about a skin, and what it must not (B44a, 2026-08-24)

The splitter is one entry in a short list, and the list is short for a reason: **a skin's own
preferences already survive on their own.** `setPrivateInt`/`setPrivateString` and `cfgattrib` write
straight into the same namespaced store, so anything a skin chose to remember about itself already
works. What the *engine* owns is only what lives in the object graph, which is rebuilt from the markup
on every load. All of it is collected in `WinampModernSkinState`:

| State | Section | Key | Written when |
|---|---|---|---|
| A `<Wasabi:Frame>`'s divider offset | `@nullplayer.frames` | `container-id/frame-id` | mouse-up on the divider |
| Which layout a container is on (shade) | `@nullplayer.layouts` | `container-id` | a `SWITCH` on a control the user clicked |
| Whether one of the skin's windows is open | `@nullplayer.windows` | `container-id` | a menu item, a skin button, a close box |

Two things are deliberately **not** in it. The active colour theme is already persisted by
`WasabiColorThemeList` under `appearance/theme` — check before duplicating it. And a window's frame on
screen belongs to the *player's* window rather than to the skin, so it goes through `AppStateManager`
with everything else the app restores (with `clampRestoredFrame`, R1).

###### …but a `.wal` window's *size* is still the skin's (BB2c, 2026-08-25)

"The frame belongs to the player" is right about the **position** and wrong about the **size**, and
the difference is not cosmetic. A `.wal` window is sized by the skin's layout: Big Bento Modern's
`main/normal` is 1536×878, winampmodern566's is 354×280, and each declares its own resize range.
`AppState.mainWindowFrame` is one global key, so a size saved under one skin was restored under the
next — after the skin had already sized the window correctly, so the restore *won*.

It reads on screen as the skin coming apart into two windows: winampmodern566 anchors its titlebar to
the top and its player bar to the bottom, so at 1536×878 they sit at opposite ends of a near-empty
window. There is no clamp to catch it either, because 566 declares `max=16384x16384` and is genuinely
meant to widen — `clampRestoredFrame` had nothing to reject.

`AppState.winampModernSkinName` records which skin the frame was saved under, and
`AppStateManager.mainFrameForRestore` keeps the saved **origin** while substituting the loaded skin's
**own size** whenever the two names differ. A state written before that key existed decodes as `nil`,
which never matches, so old preferences self-correct on the next launch.

**The same rule was missing on the live mode switch (B49, 2026-08-25).** Launch restore was fixed
here; `WindowManager.recreateModeDependentLayout` was still stamping the *outgoing* mode's whole
frame onto the freshly created target-mode window, so `.wal` (Ebonite, 197×297) → Classic drew the
275×116 classic skin scaled down inside a 197×297 box. Same shape of defect, same fix —
`WindowManager.mainFrameForModeSwitch(outgoing:ownSize:)` keeps the origin and takes the incoming
window's own size — and a test asserts it agrees with `mainFrameForRestore` on the same input, so the
two paths cannot drift. Details in the `ui-guide` skill's live-switch section. **The lesson to carry:
a "keep position, not size" rule has to be applied at *every* point that re-stamps a saved frame**;
fixing the restore path alone left the switch path wrong for months.

Two things worth knowing when this class of bug is suspected again:

- **The dev loop manufactures it.** `kill_build_run.sh` does `pkill -9`, which never writes saved
  state, while `winampModernSkinName` is written the moment a skin is selected. So the frame in
  preferences routinely belongs to a *different* skin than the one that will load.
- **The harness cannot see it.** Scene geometry is correct headlessly (`RENDER-DUMP main/normal:
  354x280` before and after); the defect lives entirely in the window layer. `resizeWindow` logs
  `WinampModern R1: resizeWindow(…) reason=…` in DEBUG, and comparing that line against the window's
  size afterwards is what separates "the skin asked for the wrong size" from "something overwrote it".

The write points are the whole design. **Every one of them is a user gesture**, and a script's
`setPosition`, `switchToLayout` or `hide()` writes nothing — that is the skin describing *this* run.
The layout entry is the one where the distinction takes care: a `SWITCH` click action is a control the
user pressed, while `scripts.layoutSwitchRequested` is the skin's own `switchToLayout` and is
ambiguous (a skin switches its own layout both at load and from its own click handlers), so only the
former records. Restoring a layout is also the one entry **not** re-asserted a second later the way a
divider is: switching layout resizes the window and rebuilds the scene, and doing that a second after
launch would read as the player flinching, so a skin that switches its own layout from a timer keeps
the last word.

##### What outranks a splitter on its own grab strip (BB21, 2026-08-24)

"The cursor changes but it drags the whole window" is the signature of this one, and it is a hit-test
question, not a frame question. A grab strip spans the full height of its frame, so it crosses
whatever the skin laid over that column — cPro's tab strip runs straight through the 8px seam, and a
control the user can see must always win. The old rule was simply "the divider claims the click when
`object(at:)` is nil", and that is too generous: Big Bento Modern covers **every pixel of its window**
with `<layer id="player.resizer.disable" move="1" alpha="0">` plus four alpha-0
`player.mainframe.grabber.mousetrap*` layers laid directly on the seam. The splitter never claimed a
single press, so every drag moved the window while `resetCursorRects` promised a resize.

`renderer.objectOverridingDivider(at:)` is the rule instead. Two things do **not** outrank a splitter:

- **an object the user cannot see** (`alpha="0"`) — a mousetrap, not a control;
- **a surface whose only interactivity is `move="1"`** — window dragging, which is exactly the gesture
  a splitter exists to reinterpret over its own strip. An object that also carries an action, or is a
  button or a slider, keeps its claim.

It applies only inside a divider's grab rect. Big Bento's own `mousetrap3`/`mousetrap4` are
`alpha="255"` and sit *above and below* the strip, so they are untouched — check a blocking layer's
alpha and rect before widening this rule.

#### Text width is a layout input, not just a drawing detail

A skin lays *itself* out from `getAutoWidth()`: ClassicPro sizes every SUI tab to
`label.getAutoWidth() + 14` and positions its five menu-bar groups by accumulating theirs. So the
script's measurement and the renderer's drawing must be the same measurement, or the skin builds
boxes that do not fit their own contents. Both go through `WasabiTextMetrics` (fonts, point-size
clamp, content resolution, width incl. `leftpadding`/`rightpadding`); it hangs off the loaded skin
because the runtime must be able to measure before any renderer exists — the dump harness runs the
scripts first.

Two auto-sizing rules in the renderer, both only when the object declares no `w`: a group with
`autowidthsource="<id>"` takes the width of the descendant it names, and a `<text>` takes its own
content's width.

#### How big the font is, and which one

Three rules, all measured against Love is War Miku's shipped `screenshot.png` (a skin's own reference
render is the ground truth for this kind of thing):

- **`fontsize` is a pixel height, not a point size.** Winamp hands it to GDI as a font height and the
  em it draws is measurably smaller: `fontsize="30"` draws digits 17px tall, Arial's cap height at a
  **24pt** em, and `fontsize="10"` matches an 8pt em — the same 0.8 ratio
  (`WasabiTextMetrics.pixelHeightToPointSize`). Taken at face value every string is a quarter too big
  and overflows the box the skin drew for it: this skin's song ticker spilled its descenders onto the
  seek bar below and its `0:00` collided with the title.
- **`font=` is an id *or* a plain family name.** A skin that ships no `<truetypefont>` simply names one
  it expects the system to have (`font="Arial"`), exactly as it asks GDI. Resolving only declared
  resources drew every such string in the monospaced fallback. `bold="1"`/`italic="1"` are their own
  attributes, not part of the name.
- **Text is centred in its box**, not drawn from the top edge the way `NSString.draw(in:)` does. On a
  30px-tall readout that is a whole line's leading; on a tight one it is the difference between a
  ticker inside its slot and one sitting on whatever is under it.
- **`valign` moves it** (Phase 38) — `top`, `center` (the default, and what an unrecognised value
  falls back to) or `bottom`, decoded by `WasabiTextMetrics.verticalAlignment` and applied as one
  offset down from the box's top edge (`VerticalAlignment.offset(cell:in:)`). 63 declarations across
  9 of the 17 skins, 54 of them `top`: Defix's songticker and Infoticker, every readout in Nokia
  5220's screen, multipass's whole display. The Core Text inset is **clamped at zero**, so a string
  taller than its own box starts at the top rather than above it.
  **The bitmap-font sheet path shares this**, and used to be pinned to `frame.minY` — that is
  `valign="top"` and nothing else, so every sheet-drawn readout with no `valign` (and every playlist
  row NullPlayer draws into a skin's own list) sat half a box too high. `valign` on a `<layer>` is
  inert, here and in Wasabi.

`forcefixed="1"` gives every glyph the same advance (the widest digit's) so a clock's digits do not
shuffle sideways as they tick, and `timecolonwidth` gives the colon a narrower cell of its own. Both
go through `WasabiTextMetrics.fixedPitch`, so `getAutoWidth()` measures what the renderer draws.

#### A bitmap font's `file=` is an id **or** a path

`<bitmapfont file="…">` is written both ways and a skin picks one freely: the stock Winamp Modern skin
names a previously declared `<bitmap>`, MMD3 names a path inside the archive
(`file="player/tickerfont2.png"`). The loader resolves the path form into `logicalFile` and simply
registers without one when that fails, so the identifier form still resolves through the registry;
`WasabiResourceCache.fontSheet(for:)` tries both, in that order, and applies the font's own
`gammagroup`.

> **Gotcha:** a font with no sheet draws *nothing at all* and records no diagnostic, so the failure
> looks like "this skin has no text" rather than a missing resource. Supporting only the identifier
> form silently removed every string MMD3 draws — song title, time, KBPS, KHZ, crossfade — while the
> compatibility report stayed clean.

The glyph map is Winamp's fixed three-row sheet layout. The two trailing spaces on row 0 are
load-bearing: they map the space character onto a blank cell instead of onto the fallback glyph (0, 0).

#### What a `<text>` shows

Resolution order in `WasabiTextMetrics.content` — and `getText()` answers with the same string,
because `songinfo.maki` reads a text object back out and tokenises it:

1. a script's `setAlternateText`, while it is non-empty — an **override** (MMD3 puts its SEEK, VOLUME,
   BASS and TREBLE readouts on the song ticker this way). `setText` clears it, which is how a skin
   takes it back down a second later.
2. the `display=` binding (below), else a `songticker`'s implicit track title, else `text`/`default`.
3. the XML `alternatetext` attribute, when everything above is empty — a **placeholder**, not an
   override. These are stored apart (`WasabiTextMetrics.scriptAlternateTextKey`) precisely because
   they are different things: promoting the declared one to an override pinned MMD3's whole display
   to its shipped placeholder, "updating songticker", for the entire session.

A script measures the same strings two ways, and the difference matters: **`getAutoWidth()`** is how
wide the object *wants to be* (a named `autowidthsource`, else a declared `w`, else its artwork, else
its text), while **`getTextWidth()`** is how wide the string it currently shows actually draws. Skins
compare them — `if (t.getWidth() < t.getTextWidth()) t.hide(); else t.show();` — to decide whether a
caption fits. `getAutoHeight()` is `getAutoWidth`'s vertical twin, resolved from the same three
sources plus a one-line font height for text.

`display=` values, all of them measured demand from the installed corpus:

| Binding | Answers | Note |
|---|---|---|
| `time`, `timeelapsed` | `currentTime` as `m:ss` | the same value under two spellings; both ship |
| `songlength` | `duration` as `m:ss` | |
| `songname` | `trackDisplayTitle` | "Artist - Title" — what Winamp calls the song *name* |
| `songtitle` | `trackTitle` | the title **alone**, a different field from `songname` |
| `songartist`, `artistname` | `trackArtist` | |
| `songalbum` | `trackAlbum` | |
| `songbitrate` | `bitrateKbps` | a bare number; the skin draws its own `KBPS` label |
| `songsamplerate` | `sampleRateHz` in **kHz** | Big Bento gives the field 35px — "44", never "44100" |
| `songinfo` | `songInfoText` | the **stream info** line, not the artist/album |
| `PE_Info` | the playlist status line | matched by `display=` *or* `id=` — see above |

`timerhours="1"` on a clock readout widens it to `h:mm:ss` past the hour; without it a 93-minute set
reads `93:20` in a box the skin sized for `1:33:20`.

Everything else falls through to `text`/`default`, which is what makes an unmapped binding degrade to
the placeholder the skin ships rather than to a blank. See
[Track metadata](#track-metadata-the-skins-actually-read) for why the shape of `songinfo` matters.

#### A `<text>` with no `h` is one line tall (BB27, 2026-08-25)

A `<text>` that declares no height at all sizes to the height of the font it draws in. It is not a
degenerate case: Big Bento's notifier declares all three of its readouts that way
(`<text id="title" w="0" relatw="1" fontsize="46">`), and so do skins across the corpus.

The geometry resolver defaults a missing dimension to the object's **intrinsic size** — artwork for a
layer, a frame for an animated layer, `autowidthsource` or its own text for a width. A `<text>` had
no intrinsic *height*, so it fell through to 0 and the renderer's `context.clip(to: frame)` erased it.
The height it takes now is `WasabiTextMetrics.lineHeight(of:)`, which is the same number
`getAutoHeight()` answers — so the box a script measures and the box we draw cannot drift apart.

> **Gotcha:** this is the fix for text that *overlaps the row beneath it*, not only for text that
> does not appear. Before it, `setNotifierText` pasted `ceil(fontSize * 1.4)` onto the notifier's
> text objects so that something would draw; 1.4 × 46 is 65 where the skin spaced its rows 42 apart,
> so the title ran down through the artist. A per-surface height guess anywhere else in the engine is
> the same bug waiting to happen — auto-sizing belongs here, in the intrinsic-size rules.

Only `<text>` auto-sizes vertically. Everything else with no `h` keeps taking its height from its
artwork or from nothing, which is what the corpus is laid out against.

#### A container's `x`/`y`/`w`/`h` are its window's (BB27, 2026-08-25)

Every other object's geometry is read back out of the graph when the scene is next drawn, so writing
the attribute is the whole job. **A container is not drawn.** Its size lives in the window and its
position on the desktop, and both are the host's to set, so the two ways a script asks for either
have to be forwarded rather than stored:

- `container.resize(x, y, w, h)`
- `setTargetX/Y/W/H` + `gotoTarget()`, per animation tick and at the instant path

`WinampModernScriptRuntime.applyContainerGeometry` is called from both and splits the request in
two: the size through `layoutResizeRequested` (the same callback a layout resize uses, keyed by the
container's id), the origin through `containerMoveRequested`. The controller answers the second by
setting that window's frame origin — **Winamp's screen space is top-left origin**, the space
`getViewportWidth`/`getViewportHeight` answer in, so the y flips into AppKit's. It is in screen
points, not skin pixels: the script derived it from the viewport rather than from the scene, so UI
Size does not enter into it. Clamped to `visibleFrame`, because Winamp's viewport excludes the
taskbar and ours does not — a toast that puts itself two pixels above the bottom of the screen would
otherwise land under the Dock.

Dropping these is a silent failure with a very misleading shape: the skin's script runs clean, every
handler counts, `RENDER_PROBE` shows the layout it addressed laid out perfectly, and the window on
screen is untouched.

#### `offsetx` / `offsety` move the string, not the box

A `<text>` can shift its own drawing without moving its rect. The box still measures, hit-tests and
**clips** where it was declared, so a large enough offset pushes the string entirely out of view —
which is not a degenerate case but the mechanism a skin uses. Big Bento Modern's SUI tab captions are
`offsetx="35"`: in the icons+text tab mode that clears the 40px icon, and in the icons-only mode
(a 40px-wide strip) the same 35 puts the caption outside the clip. Ignoring the attribute drew every
tab's caption straight over its own icon.

**A string whose origin lands in the clip's last pixel column is not drawn at all** (BB29). Bento's
caption starts on column 39 of that 40px strip, so the clip leaves exactly one column: a glyph with no
left side bearing (`V`, `W`) painted one bright column beside its icon plus one of antialiasing, and
because the amount depends on each caption's first letter the strip looked *notched*, differently on
every tab. One column of a 24px letter is never information — it is the fringe of a string the clip
was meant to swallow — so a left-aligned, non-scrolling string with `drawFrame.minX >= visible.maxX-1`
returns early (`visible` is `context.boundingBoxOfClipPath ∩ frame`, read before the flip). Measured
on the corpus: 310 images, 305 identical, the 4 Bento `main-normal`s the fix, Anexa's nondeterministic
`main-shade` discounted.

#### A `cfgattrib` control has no `action` — the binding *is* what it does

`cfgattrib="{GUID};Name"` binds a control to a Winamp preference, and a skin both **writes** it from
its configurator and **reacts** to it. Defix's settings window is nine of these, each a *pair* of
togglebuttons over one rect: a `ghost="1"` one carrying `image`/`activeImage` that shows the state,
and a bare `rectrgn="1"` one that takes the click. Neither carries an `action`, so `performAction`
had nothing to run and every switch in that window was inert, while the indicator beside it painted
its "off" artwork whatever the stored value was.

Both halves are needed, and the second is the one that is easy to miss:

- `WinampModernScriptRuntime.toggleConfigAttribute(of:)` flips the stored value **and dispatches
  `onDataChanged`** to every dynamic object registered against the same attribute. A skin applies a
  setting from that event, not by polling — writing the value silently moves the switch and changes
  nothing on screen until the skin is reloaded. Turning off Defix's "Window control bar" is
  observable precisely because the event reaches its script: `playlist.CotrolBAR` and the SUI tab
  strip `grid.s2` hide, and `FRAMING_GROUP` re-lays out.
- `configStateProvider` lets the renderer read the binding for a togglebutton's active state, so the
  indicator follows the value. Every renderer shares the one runtime, so a switch and any control it
  mirrors in another window always agree. **Every path that draws a scene has to wire it** — both app
  paths do, and the render harness did not, which is why Defix's configurator dumped nine `OFF`
  indicators against three settings that ship as `1` (fixed Phase 45; a blind instrument reporting a
  defect the app does not have).

**There are three ways a value gets written, and they must all be the same way.** The host's Skin
Settings window and a `cfgattrib` control already shared `setConfigAttribute`; a **script's own
`ConfigAttribute.setData`** did not, and dispatched `onDataChanged` to the calling object alone.
That is not a detail: a skin registers the same attribute once **per script**, so every other window
holds a different object for it, and the whole point of the write is that they hear about it. Defix's
configurator changes its 31 backgrounds by storing a `BG` id and then pulsing a `Bg Chng` attribute —
one `setData`, five windows' `STANDARDFRAME` scripts each re-reading the id and re-imaging nine frame
slices. Dispatching to the caller alone repainted the configurator's own background and left the
player, both speaker cabinets, the playlist and the library wearing the old artwork (Phase 45).

##### Some `cfgattrib` values are the **host's**, not the skin's — and a bound control keeps no state of its own

Most bindings address skin-private preferences, and those live in `WinampModernConfiguration`. Four
do not: they are Winamp's own playback options, which the skin merely *draws*. Measured across the
30 installed skins they are also by far the most common bindings there are —
`{45F3F7C1-…};Repeat` ×52, `;Shuffle` ×50, `{FC3EAF78-…};Enable crossfading` ×32,
`{F1239F09-…};Crossfade time` ×12 — so `WinampModernConfigBridge` maps exactly those to
`WinampModernHost` (`shuffleEnabled`, `repeatEnabled`, `crossfadeEnabled`, `crossfadeSeconds`, the
last two backed by `AudioEngine`'s Sweet Fades). Everything it does not name still goes to the
skin's namespace.

**Storing one of these in the skin's namespace as well gives one setting two homes**, and they drift
the moment either side moves. Shuffle was stored twice — the attribute, plus `host.shuffleEnabled`
toggled by an `xmlID == "shuffle"` case in the view — so one click flipped it twice and came back
where it started. Keep the `xmlID` route for skins that bind *nothing* (boom draws shuffle and
repeat with `activeimage` artwork and no `cfgattrib` at all), but only in the `else` of the binding.

Two reads have to answer from the binding rather than from the object, and each one was a defect:

- **`getActivated()`**. For a bound control the stored preference *is* the activation — that is why
  `toggleActivation` refuses these and never writes `activated`. Answering from the attribute
  reported every bound button as off forever.
- **`getPosition()`** on a bound *slider*, in its own `low…high` unit. mmd3 seeds its crossfade
  readout with `slidercb.onSetPosition(slidercb.getPosition())` at load.

And a bound slider's **drag** is in that unit too, not Winamp's 0…255. Every explicitly-ranged
slider in the corpus is one of these: five crossfade sliders cut `high="20"`, and Anaheim's
`brightness.adjust` at `low="-4096" high="4096"`, which had been handed a 0…255 that meant nothing
to the script reading it. Skin markup is untrusted, so a bridged number is clamped into the range
the app itself offers (`WinampModernConfigBridge.crossfadeSecondsRange`) rather than accepted as
given — and because the control reads its position back from the host, the readout shows the clamped
value instead of lying about a duration the engine never took.

##### `onActivate` — how a skin shows that a toggle is on

Wasabi raises `onActivate(int activated)` whenever a button's activation changes, whoever changed
it. It is **not** `onToggle`: skins hang their *indicator* off this one, and it had no dispatch site
in the engine at all, so no `.wal` skin could show a toggle's state. mmd3's Crossfade/Shuffle/Repeat
buttons use the same bitmap for `image` and `activeImage` on purpose — the indication is entirely
six `ghost="1"` layers whose alpha `playertools.m` sets as `activated * 255` from `getActivated()`
at load and from `onActivate` thereafter. Every probe showed the buttons working and the skin
looking dead, because `RENDER_PROBE` read `activated=0` and `alpha=0` on a script that had run
clean. 8 of the 30 installed skins declare a handler.

Dispatch it from all three places activation can move — `toggleActivation`, `setActivated` (never
`setActivatedNoCallback`, which exists precisely to stay silent), and a `cfgattrib` write — and for
the last, to **every** object bound to that attribute: a skin declares the same switch once per
layout, and its indicators are per-layout too.

**A setting can also move from outside the skin**, and a `.wal` indicator is written once and never
polled — so a shuffle toggled in NullPlayer's own Playback menu left mmd3's lamp on the old state,
the same drift arriving by a different road. `WinampModernMainWindowController` observes
`.audioPlaybackOptionsChanged` and calls `refreshBridgedConfigState()`, which re-raises `onActivate`
(and `onSetPosition` for a bound slider) for a bridged value that actually moved. It caches the
settled value on the skin's own write too, so one click is still one event.

> The sweep earned its keep here. Making the crossfade slider report a real position pushed
> multipass's arithmetic onto `MakiValue.integerValue`'s `Int32(clamping: Int64(value))`, whose
> `Int64(_:)` **traps** on the infinity MAKI's unchecked `/` produces — a trap on skin input, which
> the security model forbids. A pre-existing engine bug that nothing had reached before.

> Not every attribute a skin registers appears in its own configurator. Defix's songticker mode
> (`Disable`/`Modern`/`Classic Songticker Scrolling`) is registered with `newAttribute` for **Winamp's**
> preferences dialog and appears nowhere in its own Skin Settings window. The host's
> **Winamp Modern → Skin Settings...** is where those live (Phase 27), and they work: the skin's
> `onDataChanged` writes `ticker="bounce"` for Modern and `ticker="scroll"` for Classic.
> **Its three modes are a radio group the skin does not enforce** — the handler tests `Disable`
> first, so ticking *Modern* while `Disable` is still `1` leaves the ticker off. Unticking `Disable`
> is the other half, and no host heuristic should guess that: Winamp's dialog offers the same three
> checkboxes and the same skin logic decides. The skin ships `Disable = 1`, which is why an untouched
> profile's ticker does not scroll.

#### `<AlbumArt>` needs a host that actually has the cover

`WinampModernHost.albumArtwork` has a protocol-extension default of `nil`, and for a long time the
production host never overrode it — so every `<AlbumArt>` in every `.wal` skin drew its
`notfoundImage` forever, which reads as "this skin has no cover art support" rather than as a missing
host property. `WinampModernAudioEngineHost` supplies it from `NowPlayingManager`, which already
fetches art for every source (local tags, Plex, Subsonic, Jellyfin, Emby) to feed the system Now
Playing panel — a skin's cover is that same image, not a second fetch.

Two things this must get right: the `CGImage` is cached **per track id**, because `albumArtwork` is
read inside `draw` and converting an `NSImage` there re-rasterises the art every repaint; and the
cache is dropped on a track change, or the previous track's cover stays on screen over the new one's
title. Art arrives asynchronously, so the window controller repaints on
`NowPlayingManager.artworkDidLoadNotification` — with playback paused nothing else would.

#### `alpha` belongs to the object, not to one kind of drawing

It is set once per scene node, before the type-specific draw, so text and bitmap fonts fade with
everything else. Skins stack several readouts in one slot and show one at a time purely by moving
their alphas — Defix does it with Kbps / KHz / Channels and again with Extension / Broadcasting — and
while only the bitmap paths honoured it, all of them printed on top of each other. `setAlpha` writes
the same attribute, so the script path needs nothing of its own.

#### `fliph` / `flipv` mirror the content inside the object's own box (B43, 2026-08-24)

Same shape of rule as `alpha` above, and it was missing for the same reason: both attributes were
ignored **engine-wide** — neither string appeared anywhere in `Sources/`. They are applied once per
scene node, at the seam every kind of drawing passes through, not in the bitmap path, because the
attribute belongs to the *object* rather than to one way of filling it.

The reflection is about the object's **own frame**, which makes it an *involution*: it maps `minX` to
`maxX` and back, so applying it twice is the identity and a flipped object still covers exactly the
rect it declares. Nothing about hit testing or layout changes when a skin turns one around. Two
placement details matter:

- **After both clips.** `node.clip` and any region mask are set in the unflipped space, so an object
  cannot escape its box by mirroring and a region map stays where its author put it.
- **Children are their own scene nodes**, so flipping a `<group>` turns its own background around and
  leaves the objects inside it alone.

Read the flags with `WasabiGeometrySpec.flag`, the same `atoi(value) != 0` reader `relat*` uses — a
second, subtly different reading of `"1"` in the renderer is exactly the bug that cost a session on
Big Bento's album art (B42).

**What skins use it for is a mirrored pair drawn as one figure.** All 16 declarations in the corpus
are on `<vis>`:

| skin | declarations | what it builds |
|---|---|---|
| Big Bento Modern, + Windows 10 edition | 4 each (inherited by both Light overlays) | the header **butterfly**: `main.vis` (`fliph="1"`) beside `main.vis2`, 144px each, so the two meet low-frequency-to-low-frequency in the middle, over two `flipv="1"` reflection strips |
| Styx | 4 | a 2×2 quad covering all four combinations — a kaleidoscope, and the best test case in the corpus |
| multipass | 2 | `player.vis.2b` / `player.vis.4b`, reflections |
| Enkera | 1 | `nvis2` |
| Nullsoft.Winamp.2000.SP4.Lite | 1 | the **same** `<vis id="shade.vis">` declared **twice in the identical box**, the second `flipv="1"` — the classic Winamp mirrored scope |

That last one is the pattern to recognise: two identical declarations in one box are not a skin bug
and not a double draw, they are a trace and its reflection. Ignored, the pair coincides exactly and
reads as a single thin line.

#### An image param is a *load*, and a failed load changes nothing

`setXmlParam("image", …)` (and `bitmap`, `background`, the button/slider state images) only takes
effect when the new id resolves to a registered resource; an unknown id — the empty string included —
leaves the object wearing what it already had, which is what Winamp shows for a bitmap that never
loaded. Defix builds every background id by prefixing a preference it never seeds
(`getPrivateString(getSkinName(), "BG", "")`), so taking those writes literally asked for
`"" + "_background_material.Element.top.left"` nine times per window and stripped the skin's wood
panelling off the player, both speakers, the playlist and the library.

#### Layer fill modes

- **Default (no `tile`)**: the bitmap **stretches** to the layer's rect. Resizable window chrome
  depends on this — `wasabi.frame.top` is a 10×18 sprite stretched across the whole titlebar, and the
  menubar/titlebar streaks are 5–10px sprites stretched to hundreds of pixels. Drawing them at
  natural size paints one sprite and leaves the rest of the bar blank.
- **`tile`/`tilex`/`tiley`**: repeat the bitmap instead. Bento-style frames tile their
  top/bottom/left/right/center strips. Tiles are blitted 1:1 with interpolation off, or the resampled
  edges leave a visible seam grid.

#### A skin spells the axis two ways, and `"v"` is not a typo

`orientation` decides whether a slider's thumb travels up or across, and skins write it **both** ways
for the same thing. Across the installed corpus:

| Spelling | Slider declarations |
|---|---|
| `vertical` | 158 |
| `v` / `V` | **49**, in 8 skins |
| `horizontal` | 21 |

Testing for `== "vertical"` therefore made 49 of them *horizontal* — Big Bento Modern ×4, Anexa,
Enkera, Lobe and The_Nokia_5220. It produced two symptoms that look unrelated:

- **The thumb drew along the wrong axis.** Anexa's, Lobe's and cPro-Bento's equalizers could never
  show a curve: ten band sliders whose thumbs all slid sideways within their own column.
- **A drag read the wrong coordinate.** `updateSlider` took its value from the pointer's **x** across
  a bar 16px wide, so the position snapped to one end rather than following the mouse — which is what
  made Big Bento Modern's settings scrollbar impossible to drag (BB19).

`WasabiSceneRenderer.isVerticalOrientation` is the single answer; use it rather than comparing the
attribute. Note `<ProgressGrid>` has its **own** vocabulary for this (`up`/`down`/`left`/`right`, the
edge it grows from) and is deliberately not folded in.

#### `<ProgressGrid>` — the bar's *filled* part

`left` cap + stretched (or tiled) `middle` + `right` cap, growing from the edge `orientation` names
(`right`/`down` anchor at the near edge, `left`/`up` at the far one). It carries no `action` of its
own, so the value comes from the sibling that does — the `<slider>` drawn over the same rect — and
both go through the renderer's one `normalizedValue(of:)`.

Skins pair the two and give the slider a thumb that is deliberately invisible: Love is War Miku's seek
"thumb" is a **1×1 pixel**, and the grid is the only thing that shows a position anywhere in the
window. Drawing nothing for the grid left its seek bar an empty white box — which reads as a blank
text field, not as a seek bar.

#### A skin's own right-click menus

A script builds them with `new PopupMenu`, `addCommand(title, id, checked, disabled)`,
`addSeparator()`, `addSubMenu(child, title)` and shows one with `popAtMouse()`, which **blocks** and
answers the id the user picked (0 = nothing). Three things this needs, and all three were missing at
once, so no `.wal` skin could show a menu at all:

- `addSubMenu` — without it the whole `onRightButtonUp` handler fails closed at the first submenu.
- A **presenter**: `WinampModernScriptRuntime.popupPresenter` is installed by the main view
  (`presentScriptPopup`), which builds an `NSMenu` from the resolved tree and runs it at the mouse.
  Unset, `popAtMouse` answers 0 and the skin concludes the user cancelled.
- `addCommand`'s fourth argument is **disabled**, not "separator" — storing it in the separator slot
  turns every greyed-out row into a divider.

**A fourth, found in Phase 31: the right button is a *pair* of events and a skin picks either half.**
The view sent only `onRightButtonUp`. Defix hangs all four of its "what does this button open" menus
off `onRightButtonDown`, so they were unreachable while the skin, the presenter and `popAtMouse` all
worked perfectly. `WinampModernMainView` now sends `onrightbuttondown` on the press and
`onrightbuttonup` + `onrightclick` on the release, and the release goes to whatever the *press*
claimed — `popAtMouse` runs its own tracking loop, so by the time the up arrives the pointer is
wherever the user dismissed the menu, usually not over the control any more.

`WINAMP_MODERN_RENDER_CLICK` prints the menu a right-click builds, which is the fastest way to see
whether the failure is the menu or what it does afterwards. **It drove only `onrightbuttonup` until
Phase 31**, and so reported four dead buttons on a skin that implements them fully — the reason a
skin file carried "builds no `PopupMenu` of its own" for several phases. A probe's silence is a
statement about the probe until you have checked it drives the event.

#### A skin opening its own windows

Not every window request is a host action. A skin may open one of its own containers from script —
`getContainer("SUI").show()` — with no `TOGGLE` and nothing else for the host to see; Defix's SUI is
reachable *only* this way (its round buttons send the skin's own `sendAction("opentab", …)`, which
`skin.xml`'s `onAction` answers with exactly that). `show`/`hide` on a top-level container therefore
raises `WinampModernScriptRuntime.containerVisibilityRequested`, and
`WinampModernMainWindowController` opens or orders out the matching auxiliary window.

Two constraints on that path, both load-bearing:

- **It is idempotent.** Skins call `show()` from timers; acting on a request for the state the window
  is already in would re-front it 30 times a second. The controller compares against
  `window.isVisible` and drops the rest.
- **It is wired after `scripts.start()`** (in `makeSurfaceCoordinator`), so a `show()` from
  `onScriptLoaded` cannot pop windows open at launch.

`Container.toggle()` is the same route with the direction read back first, and the direction must come
from the **window**, never from the graph's `visible` attribute (`containerVisibilityQuery`, the read
half of the pair). A window's visibility changes by four routes that never write that attribute — a
markup `TOGGLE`, the Windows menu, this call, and the window's own close button — so an
attribute-read toggle inverts after the first manual close. For the same reason the aux window's close
button goes through `setAuxiliaryWindow` rather than calling `orderOut` itself: closing a window is a
scene becoming invisible, and a skin that lights its console button from that window's layout
`onSetVisible` (Ujola Cat) was left with a lit button and nothing on screen.

#### How a colour resolves (BB2a, 2026-08-25)

Everything a skin colours — a `<rect color=…>`, a `<vis colorband1=…>`, and the `WasabiPalette` roles
NullPlayer's own surfaces draw with — goes through `resolvedColor` / `objectColor`. A colour that
fails to resolve does not disappear; it becomes a **fallback**, and the two fallbacks are loud:
`unparseableColor` is **white** and `contentBackground`'s literal is **black**. So the symptom to
recognise is *"a white slab"* or *"a black rectangle"* where the skin plainly names a colour — not a
subtly wrong shade.

Three ways a declared colour used to be lost, all fixed and all worth knowing because each has a
different signature:

1. **A colour resource may name another colour resource.** `<color id="wasabi.list.text"
   value="color.display"/>` — the value is an *id*, not a triple. Big Bento Modern writes nearly its
   whole palette this way. The walk to the literal is bounded and cycle-guarded, and the **referring**
   declaration's `gammagroup` wins where it has one, so the channels are tinted once, by the group the
   id that was asked for names.
2. **Bitmaps and colours are different tables.** Wasabi keeps them apart, and skins rely on it: Big
   Bento declares `wasabi.list.background` as a `<color>` in `system-colors.xml` *and* as a tiled
   `<bitmap>` in `system-elements.xml`. A single flat registry let the bitmap win, and a colour lookup
   then found an image with no `color=` — which the palette chain skips, landing on black.
   `WalResourceRegistry.resolvedColorDefinition` indexes the colour-carrying declarations separately;
   `resolvedDefinition` still answers the bitmap, so tiling that image is unaffected. A `$solid` /
   `$gradient` bitmap counts as colour-carrying, because its pixels *are* its `color=` attribute.
   **Within that colour table a real `<color>` outranks a generated bitmap**, whichever is declared
   last — Ebonite_2_1 declares the same id as a `<color>` at 70,70,70 ("lists/trees item background")
   and a `$solid` at 237,237,237 ("Tree background bitmap (tile)"), the tile last, and its list text
   is white: taking the tile painted white on near-white. Two `<color>`s of one id keep ordinary
   last-wins; the ranking is about *kind*, not order.
3. **`#rrggbb` is a literal.** Enkera declares its entire palette in hex; Sony_Walkman its analyzer
   (`colorband1="#808589"`), Big Bento its 22 analyzer bands. The parse is deliberately strict — only
   a `#`-prefixed token — so a bare `abcdef` stays a resource id, which is what the caller already
   tried it as.

`WINAMP_MODERN_RENDER_PALETTE=1` prints every role, every link of its chain, and why each link
answered or did not. **Use it before changing a colour path**: it distinguishes "the skin never
declared it" from "a colour theme crushed it" from "the chain skipped a bitmap", which look identical
on screen. See `harness.md`.

#### A resolved colour is not yet a *readable* one (B48, 2026-08-25)

Every role resolves from its **own** id chain, and nothing in Wasabi checks that a foreground and the
background it lands on can be seen together. A skin declaring two colour families therefore hands us
a mongrel pairing that neither family's author intended. Winamp never hits this: its Media Library is
a native Win32 list, so the OS guarantees a legible selection. We draw those rows ourselves, so the
guarantee has to be ours.

**Measured across all 36 installed skins:** 23 drew an unreadable selected row (< 1.5:1), **nine of
them at exactly 1.00:1** — text and highlight the same colour — and 5 an unreadable window title,
with 22 more weak (< 3:1). Big Bento is the type specimen: highlight from
`studio.list.item.selected` (orange `color.selected.active`), row text from
`wasabi.list.text.selected` (pale blue-grey `color.display`) — **1.06:1**; and a *current* row over
that same bar is orange on orange at **1.00:1**.

The guarantee lives in `WinampModernSurfaceStyle`, which already *derives* roles by blending rather
than inventing, and which is **nil in classic mode** — so classic cannot be reached by it:

- `legible(preferring:on:)` returns the **first of the skin's own colours** that clears
  `minimumContrast` (3.0, WCAG's large-text bar), and only falls back to black or white — whichever
  is further from the background — when every one of them would be invisible. That fallback always
  clears: for any background, one extreme is at least ~4.5:1 away. **Ordering is the policy**: a skin
  that gives us anything usable is never overridden.
- `selectedText` is the stored role for a highlighted row: `currentText` → `selectionText` →
  `listText` → `contentBackground`, judged against `selectionBackground`.
- `legibleDimText(on:)` is for inactive titles and hints. `dimText` is a 40% blend toward the
  background, so a naive guard fails it almost everywhere and would snap every inactive title to full
  strength — erasing the active/inactive distinction corpus-wide to fix five skins. It backs the
  blend off in stages (40% → 25% → 12% → full) instead.
- `composited(_:over:)` flattens a translucent fill first. `PlexBrowserView`'s focused search field
  draws over a **half-alpha** highlight; judging the written colour rather than the composited one
  leaves that one state unreadable while the opaque row beside it is fixed.

**Two draw paths need it, and missing the second is the easy mistake.** NullPlayer's AppKit surfaces
go through the style (`PlexBrowserView`'s four selection sites and its title, `WinampModernChrome`,
`PlaylistView`, `EQView`). But the skin's **own** playlist panel and `<ColorThemes:List>` are drawn by
`WasabiRenderer` straight from `WasabiPalette`, never touching a style — that is
`WasabiRenderer.legibleRowColor`, and it was the half that live QA caught after the first pass looked
complete on the library panel.

**Where it deliberately stops: text the skin declares for its own controls.** Formamp's window
background is `(0,0,0,206)` — translucent by design, never opaque anywhere — and its `<text>` objects
name `color=80,80,80` (title), `120,120,120` (artist), `100,100,100` (timer). Over a bright desktop
that composites to black-on-black, and it is still not ours to change: guarding a colour an author
spelled out is overruling the design, not fixing our legibility. Closed as won't-do. The same reading
applies to any quiet-by-design skin — Lobe, micro.

`PlaylistColors.selectedText` (declared **twice**, `Skin/Skin.swift` and
`NullPlayerCore/Skin/SkinTypes.swift` — out of step is a build error, not a silent regression)
defaults to `currentText`, which is exactly what the draw sites read before it existed. Classic `.wsz`
skins are a zero-pixel change by construction and `SkinLoader` needed no edit.

#### Colour themes (`gammaset` / `gammagroup`)

A theme is a set of per-channel adjustments keyed by `gammagroup` id, which bitmaps and `<color>`
resources opt into with `gammagroup="…"`. Three rules:

- The value triplet is a per-channel **amount** normalized to −1…1 (`v / 4096`); 0 means "leave this
  channel alone" under either model below.
- **`boost` picks the model, and the skin is the authority.** There is no single right answer here —
  picking one globally always breaks the other half of the corpus:
  - `boost="0"` or the attribute omitted → **multiply**, `channel × (1 + amount)`. Tints real artwork
    without washing it out. Every group in **Anexa** is `boost="0"`, as are MMD3's `Backgrounds` /
    `Display` / `Buttons` (which carry no `boost` at all) — forcing those additive pushes midtones
    toward white and renders MMD3's amber display as washed-out pastel.
  - `boost` non-zero → **add**, `channel + amount`. This is how a skin recolours a black template.
    **Anaheim Player 01** marks 57 of its 65 groups `boost="1"`; its themed bitmaps
    (`MiniControlWheel.png`, `MiniTickerBtns.png`, `MiniBodyBtn.png`) are pure black with only an
    alpha mask, and every `<color>` in its `studio-colors.xml` is `value="0,0,0"`. Multiplied, 0 stays
    0 — black text on black sub-windows and hover controls that never appear.

  Stock `winampmodern566` draws the same line inside one skin: `boost="0"` on `Backgrounds`,
  `boost="1"` on exactly the groups whose source colour is `0,0,0` (`wasabi.button.text`,
  `wasabi.list.column.text`, `drawer.color.text.dark`) plus the hover-glow bitmaps.

  `boost` is a mode, not a flag — MMD3 and Itemskin ship `boost="2"` alongside `boost="1"`, on the
  same label groups. Its exact difference from `1` is **unknown**; it is treated as additive, which is
  strictly closer than multiplying, and a spot-check of MMD3 (2026-08-23) turned up nothing visibly
  wrong. Do not re-derive the probe if this comes up again:

  - MMD3's heaviest `boost="2"` user is `MainLabel` → `label11.png`, the **"MMD3 / WINAMP-PLAYER"
    wordmark** at the top of the main window (`player-normal.xml` `mslabel11`, x=156 y=4), in 51 of
    83 themes. It proves nothing: the value there is `-4000,-4000,-4000` on a stencil that is already
    black, so both models render it black.
  - The **only clean A/B** is `CoverLabel` at value `3000,3000,3000`, identical `gray`, differing only
    in boost: `silver1 | xblue` is `boost="1"`, the `xbox | orange`/`blue`/`pink`/`red`/`yellow`
    family is `boost="2"`. It draws the drawer headings — `label7` "EQualizer MMD3" (EQ drawer),
    `label9` "VISualization MMD3" (VIS drawer), `label10` "COLORThemes" (ColorThemes drawer), all
    pure-black stencils. Open a drawer, switch between those two themes: we render both at the same
    mid-grey, so a brightness difference in real Winamp is the tell.
  - Secondary probe: `DisplayLabel` under `silver3 | slategray`/`slateblue`/`skyblue` or `xbox | blue`
    — `displaylabels.png` (the STEREO/MONO and play/pause/stop glyphs in the main display) is the one
    `boost="2"` target that is bright artwork (avg RGB 200), where the two models diverge most.
- The **default** theme is the first gammaset in the document (skins name it freely — "clean | orange
  (default)"), not the alphabetically first name.

`WasabiColorThemeCatalog` reads the gammasets straight from the document, so `gammagroup` is
deliberately *not* registered as a resource: its id is scoped to its gammaset, and registering it made
each of MMD3's 83 themes "replace" the previous one's groups (1404 bogus duplicate-id warnings).

##### The picker: `<ColorThemes:List>` and the `colorthemes_*` actions (Phase 32)

The catalog is only half the feature. The screen a user picks a theme from is
`<ColorThemes:List>` — an **unregistered XUI tag**, because in real Winamp the widget lives inside
Winamp and only the tag appears in the `.wal`. Until Phase 32 it expanded to a leaf object with no
bitmap, which `isRenderable` and `isInteractive` both rejected, so every colour-theme screen in every
skin was an empty box that could not be clicked.

- The renderer draws the rows (`drawColorThemeList`), from `themeNames` in catalog order, through the
  same `drawSurfaceText` path the embedded playlist uses — the skin's list font, the skin's list
  colours, the skin's active gamma. The **selected** row (`selectionBackground`/`selectionText`) and
  the **applied** one (`currentText`) are drawn differently, as Winamp draws them: "the row I am
  pointing at" and "the theme the window is wearing" are different facts.
- Per-object state (`WasabiColorThemeListState`, keyed by `WasabiObjectID`) holds the selection and
  the scroll, so a skin with a list in its player *and* in a standalone window — mmd3 has both — keeps
  them independent. The first draw **seeds the selection to the applied theme and scrolls it into
  view**; with 82 themes a list that always opened at row 0 could not answer "which one am I on?".
- A single click selects; a **double-click** applies. The skin's own `Switch` button is what a single
  click is waiting for.
- **No scrollbar.** The renderer has no scrollbar support at all, so a `<Wasabi:Scrollbar>` a skin
  places beside its list is inert and the wheel is the only way down the list. Scrolling the applied
  theme into view is the mitigation; growing scrollbar support is a separate piece of work.

The three host actions live in `WinampModernMainView.performAction`:

| Action | What it does |
|---|---|
| `colorthemes_switch` | applies the selection of the list its `action_target` names |
| `colorthemes_next` / `_previous` | steps the **applied** theme, wrapping, and drags every list's selection along |

`action_target="<id>"` is resolved with Wasabi's **wide** semantics, the ones `findObject` uses: the
button's own container subtree first, then the whole graph. The wide half is load-bearing — mmd3's
`ctsbig` window names `main.colorthemes.list`, which lives in another container. A button whose target
resolves to nothing falls back to the only list in the scene, and failing that to a **popup menu** of
the theme names. (multipass was the worked example of that fallback until Phase 33; it is not one. Its
`player.colorthemes` lives in a groupdef that only `System.newGroupAsLayout` instantiates, and that
method was refused — so the target was missing for a reason the skin had nothing to do with. It
resolves now, and the buttons act on a real 58-row list.) `action="TOGGLE"` with Winamp's Color-Themes preferences GUID
`{53DE6284-7E88-4c62-9F93-22ED68E6A024}` opens that same popup.

Skins that define themes and ship **no** picker at all (measured: Anexa, micro, T800, ZDL, Itemskin,
Overdrive_2) are covered by the host **Color Themes** submenu in the Winamp Modern menu, which is the
preferences dialog we do not otherwise have. It is gated on more than one theme.

##### An `<animatedlayer>` is one frame, not one sheet

Its `image` is a **strip** and `framewidth`/`frameheight` say how it is cut, so a layer that declares
no `w`/`h` of its own is one *frame* big. Taking the sheet made multipass's seek bar a 139×364 box
where the skin drew a 139×13 one — one frame stretched over twenty-eight frames' worth of height, then
clipped by the enclosing display group to a transparent sliver, so the skin's only seek indicator was
invisible while the script driving it worked perfectly.

Its **region** is the union of its frames: a point is clickable if *any* frame paints there. Testing
only the frame on screen is wrong for the commonest use of the type — a fill animation is transparent
ahead of the playhead, which is precisely where a seek click lands. Phase 33.

##### Artwork-less `<Wasabi:Button text="…">`

A deliberate exception to the identifier-only rule for the seeded Wasabi standard-library shells. Three
measured skins (CornerAmp, mmd3's `ctsbig`, Anexa) put a bare `<Wasabi:Button text="Switch">` under
their theme list, and **no** `.wal` ships `wasabi.button.*` artwork because in real Winamp the standard
library supplies it. The renderer draws a 1px border in `palette.listText` with the label centred, but
only when the instance resolves *no* bitmap and carries a non-empty `text=` — a skin with its own
button artwork never reaches the fallback.

#### Animated layers are played as a range

`animatedlayer` is a sprite sheet plus a play head, and scripts drive it as a range:
`setStartFrame(getCurFrame())`, `setEndFrame(target)`, `setSpeed(msPerFrame)`, `play()`, then poll
`isPlaying()` (MMD3's rotary volume/bass/treble knobs are exactly this). `WasabiAnimation` makes the
play head a pure function of the elapsed time since `play()`, which is what keeps the renderer and the
script runtime agreeing on the current frame without either owning a clock. `stop()` freezes the head
where it actually is, and an explicit `playing` beats the XML's `autoplay`.

