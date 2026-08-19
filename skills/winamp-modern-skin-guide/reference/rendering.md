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
alpha-tests the node's bitmap. Two rules about *which* objects may claim a point:

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

#### Dragging the window

`WinampModernMainView.shouldDragWindow(from:)` decides whether a press moves the window, from the
object the hit test returned:

- the **`layout`** itself — the window's own background. A skin that paints its whole frame there and
  hangs nothing but controls off it (T800) has no other handle, and without this it cannot be moved.
- a bare **`group`** with `move="1"` — a group has no artwork, so a click reaching one landed on the
  background it covers, and `move="1"` is the skin calling that background a handle.
- a **`layer`** with no `action` — *unless a script hooks a mouse event on it*, which makes it a
  control rather than a handle (the same thing `move="0"` says explicitly, for the skins that do not
  bother to say it). Dragging the window off an invisible trigger eats the click it exists for.
- never anything with `move="0"` (T800's volume strip is a layer whose script owns the drag), and
  never the named transport/title objects on the exclusion list.

`WINAMP_MODERN_RENDER_CLICKABLE=1` is the check for both hit-test rules: it lists objects a script hooks the mouse on
that the markup-only hit test rejects. It is not expected to be empty — several objects legitimately
share a rect and only the topmost can win — but a control the user can see should never be in it.

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

`display=` values: `time`, `songname` → `trackDisplayTitle` ("Artist - Title", which is what Winamp's
song name is), `songinfo` → `songInfoText` — the **stream info** line, not the artist/album. See
[Track metadata](#track-metadata-the-skins-actually-read) for why the shape of that string matters.

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
  mirrors in another window always agree.

> Not every attribute a skin registers appears in its own configurator. Defix's songticker mode
> (`Disable`/`Modern`/`Classic Songticker Scrolling`) is registered with `newAttribute` for **Winamp's**
> preferences dialog and appears nowhere in its Skin Settings window — so with no Winamp preferences
> UI here, there is currently no way to reach it. The skin ships `Disable = 1`, which is why its song
> ticker does not scroll.

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

`WINAMP_MODERN_RENDER_CLICK` prints the menu a right-click builds, which is the fastest way to see
whether the failure is the menu or what it does afterwards.

#### Colour themes (`gammaset` / `gammagroup`)

A theme is a set of per-channel adjustments keyed by `gammagroup` id, which bitmaps and `<color>`
resources opt into with `gammagroup="…"`. Two rules, both of which cost MMD3 its entire look when
they were wrong:

- The value triplet is a **multiplier**, `(4096 + v) / 4096` — 0 means "leave this channel alone".
  Treating it as an additive bias (`v / 4096` added) pushes every midtone toward white; MMD3's amber
  display rendered as washed-out pastel.
- The **default** theme is the first gammaset in the document (skins name it freely — "clean | orange
  (default)"), not the alphabetically first name.

`WasabiColorThemeCatalog` reads the gammasets straight from the document, so `gammagroup` is
deliberately *not* registered as a resource: its id is scoped to its gammaset, and registering it made
each of MMD3's 83 themes "replace" the previous one's groups (1404 bogus duplicate-id warnings).

#### Animated layers are played as a range

`animatedlayer` is a sprite sheet plus a play head, and scripts drive it as a range:
`setStartFrame(getCurFrame())`, `setEndFrame(target)`, `setSpeed(msPerFrame)`, `play()`, then poll
`isPlaying()` (MMD3's rotary volume/bass/treble knobs are exactly this). `WasabiAnimation` makes the
play head a pure function of the elapsed time since `play()`, which is what keeps the renderer and the
script runtime agreeing on the current frame without either owning a clock. `stop()` freezes the head
where it actually is, and an explicit `playing` beats the XML's `autoplay`.

