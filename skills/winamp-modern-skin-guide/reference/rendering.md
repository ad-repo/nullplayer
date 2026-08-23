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

#### `<Wasabi:Frame>` — the splitter that builds its own children

Most objects are declared where they appear. A frame is not: it **names** two groups and instantiates
them itself (`WasabiFrame`). cPro-Bento's entire body is one —
`left="centro.components" right="centro.playlist1" from="right" width="200"` — so treating it as an
ordinary group left the library tree, the playlist and the tab strip out of the graph completely.

- `left`/`right` → vertical divider; `top`/`bottom` → horizontal. The pair present decides the axis;
  `orientation=` is written both ways (`vertical`, `v`, `h`) and is not trusted on its own.
- `from` is the edge the divider is measured from (`left`/`top`/`right`/`bottom`, often abbreviated).
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
- A divider pushed flush with an edge (`setPosition(0)`, how ClassicPro closes its side view) offers
  no grab strip, so a closed split cannot be reopened by dragging where it used to be.

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

#### `offsetx` / `offsety` move the string, not the box

A `<text>` can shift its own drawing without moving its rect. The box still measures, hit-tests and
**clips** where it was declared, so a large enough offset pushes the string entirely out of view —
which is not a degenerate case but the mechanism a skin uses. Big Bento Modern's SUI tab captions are
`offsetx="35"`: in the icons+text tab mode that clears the 40px icon, and in the icons-only mode
(a 40px-wide strip) the same 35 puts the caption outside the clip. Ignoring the attribute drew every
tab's caption straight over its own icon.

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

