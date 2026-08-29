# Rendering a `.wal` skin

Reference for the `winamp-modern-skin-guide` skill: clipping, hit testing, text and fonts, the drawable elements, colour themes, and animated layers.

#### An `<nstatesbutton>`'s three artwork attributes are all *prefixes* — and a click has to count

`image`, `hoverImage` and `downImage` on an `nstatesbutton` name a **family**, not a bitmap: the id
that resolves is `<attribute><state>`. ClassicPro's mute is `image="mute.1." hoverimage="mute.2."
downimage="mute.3." nstates="2"` and the bitmaps it declares are `mute.1.0` … `mute.3.1`. Suffixing
only `image` leaves the hover and the press naming ids nothing answers, and an unresolved id draws
**nothing** — so the button vanishes under the pointer and whatever is behind it shows through. On a
near-black skin that reads as "the button turns black on mouseover", and it hid three of cPro-Bento's
controls (mute, shuffle, repeat), two of which were driving the engine correctly all along. Fall back
down the family — pressed → hover → the rest state's own artwork → the bare base — so a skin that
ships no hover frame stays visible rather than blinking out.

**Which state is showing has three sources, in this order** (`WasabiSceneRenderer.nStatesButtonState`):

1. A `cfgattrib` binding — the preference **is** the state, and `cfgvals="0;1;-1"` maps its *values*
   onto the states positionally, so the state is the value's **index** in that list, not the value.
   ClassicPro's repeat is `nstates="3"` with exactly that list (off / playlist / track); NullPlayer's
   engine has one repeat flag, so only the first two are reachable.
2. The object's own counted position (`value`), which is what a **click** advances.
3. The `id`, for a skin that draws shuffle/repeat and binds nothing (boom names its artwork
   `Player.shuffle-Selected`); the view's click path reads the same host flags back.

An `nstatesbutton` is a togglebutton that counts, so `toggleActivation` has to accept one and cycle
it `(value + 1) % nstates`, dispatching `onToggle` as it does for a plain togglebutton. ClassicPro's
mute is unbound and `mute_but.onToggle` — save the volume, zero it, restore it — is the *whole* of
its behaviour, so while only `togglebutton` was accepted the button was inert however completely the
engine implemented it. `setActivated` must write `value` alongside `activated` for the same reason:
they are one state spelled twice (`getActivated()` reads the first, `getCurCfgVal()` the second), and
a persisted mute restored with `setActivated(true)` otherwise came up lit while still counting itself
on state 0.

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

#### Bitmap interpolation follows UI Size × backing scale, not the asset's stretch

Ordinary `.wal` artwork uses nearest-neighbour filtering only when the scene's effective device
scale is an exact integer and the bitmap is not actually being reduced. On Retina that makes 100%
UI Size a crisp 2× and 150% a crisp 3×, while 125% stays smoothly filtered at 2.5×. Any real
downscale stays smooth even if the surrounding UI scale is an integer; nearest would discard source
pixels and alias.

The integer test belongs to the CTM's basis vectors, **not** to
`device destination size / bitmap source size`. A skin may deliberately stretch a 79px logo to 83
skin pixels without changing the fact that its whole UI is at 2×. Using the asset ratio there picks
smooth filtering at an integer UI Size and makes one stretched icon disagree with every native-sized
icon beside it. `WasabiBitmapInterpolationPolicy` makes this decision once, and both the direct draw
and `WasabiSceneRenderer`'s pre-scaled cache use its answer.

Do not diagnose every soft edge as interpolation. Big Bento's 79×15
`window.titlebar.text.winamp` source contains many partially transparent white edge pixels — the
anti-aliasing is authored into `window/window.png`. Nearest preserves each of those pixels as a 2×2
block; it cannot turn baked alpha into a hard binary outline. During live B47 QA the hamburger icon
was the useful control (hard edges became crisp), while the WINAMP word remained intentionally soft.
Inspect the source alpha before changing the filter to chase that look.

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

##### `<Wasabi:TitleBox>` is a body, not just a border

A title box **names its body by group id**, exactly as a standard frame does:

```xml
<Wasabi:TitleBox id="radarbox" x="1" y="12" w="-3" h="70" relatw="1"
                 title=" THIS BUTTON MUST BE TURNED ON FOR GRAPHICS SMOOTHING"
                 content="dtabox.content" />
```

The difference is *who instantiates it*. A standard frame's own `standardframe.maki` does the
`newGroup(getParam("content"))` and every skin ships that script; the title box's equivalent lives
inside Winamp, so the tag resolved to nothing and **the entire content group stayed out of the
graph** — not merely undrawn, absent. Bio-Nid's only settings window is one title box, which is why
it came up as a slab of frame with a hole in it, and why "empty window" was the right description of
a missing *object*, not a missing paint. `WasabiTitleBox` supplies both halves: the initializer
expands `content` beneath the box (beside the `<Wasabi:Frame>` pane expansion, for the same reason),
and the renderer draws the label and the box.

Reach when this landed: **9 of the 35 installed skins, 33 declarations** — Bio-Nid, BLAKK, Core-X5,
Ebonite, Enkera, impulse, Itemskin, Shield_Amp, Styx.

Three things worth keeping:

- **The artwork is Winamp's.** No `.wal` in the corpus ships a `wasabi.titlebox.*` bitmap, so the box
  is drawn, on the same deliberate exception as an artwork-less `<Wasabi:Button>` above. It takes the
  instance's own `color=` when it states one (Bio-Nid, Core-X5) and the skin's list colour otherwise.
- **The label sits above the border, not in a gap cut through it.** Winamp cuts the gap; matching that
  means measuring the label in whatever font draws it, which may be one of the skin's bitmap fonts,
  and a gap that does not match the text is worse than no gap. The body inset clears both either way.
- **The inset is calibrated, not invented.** Shield_Amp and Itemskin each wrap one 20px row in
  `h="40"` with the row at `y="0"`, which puts the body 18px down with 6px under it —
  `WasabiTitleBox.contentInset`.

##### A title box that declares no height is as tall as its body needs

Four of impulse's five say `<Wasabi:TitleBox x="320" y="5" w="-325" relatw="1" title="Skin Options"
content="…"/>` and nothing more — no `h`, no `relath` — so the box resolved to no height and its body
was laid out inside nothing. In Winamp the standard library's own object supplies the height from the
content group.

**Measured, never a constant.** The height is the body's own content height plus the inset the body
already sits in (`WasabiTitleBox.contentInset`, 18 above and 6 below), which is the only number that
makes the box fit exactly what it was drawn around. The body's content height comes from the two
sources Wasabi resolves any auto height from, in order:

1. `autoheightsource="<id>"` naming a descendant — all four of impulse's content groups state one.
2. Otherwise the lowest edge any child reaches.

Both answer the child's **bottom** (`y + h`), not its own height: a group sized to the height of its
last row would clip everything above it, and impulse's Notifier Options names a 10px slider sitting at
`y="120"`. Relative geometry is skipped rather than resolved — a child anchored to the height being
computed has no answer, and one that states a relative height is asking to *fill* the box, not to size
it. A body that says nothing measurable leaves the box exactly as declared; inventing a number is
worse than leaving it.

Checked against impulse, the one skin that needs it: `Skin Options` measures 74 + 24 = 98 under a box
at `y="5"` with the next at `y="110"`, and `Glass Opacity` 13 + 24 = 37 at `y="273"` with the next at
`y="319"` — a 7–9px gap in all three cases, which is the spacing the skin's own *sized* box has.

##### The Wasabi standard form widgets are the primitives they wrap

`<Wasabi:Text>` (55 declarations / 13 skins), `<Wasabi:CheckBox>` (67 / 5), `<Wasabi:EditBox>` (14 /
5), `<Wasabi:HSlider>` (9 / 4) and `<Wasabi:DropDownList>` — 156 declarations across 15 skins, the
widest measured demand there was. Each is a conventional XUI tag whose body lives in Winamp, so each
resolved to a structure-free shell and became an inert node. **This is what an empty settings page
usually is**: with the title box implemented, Styx's Config drew three labelled boxes and two were
empty, because their bodies are these widgets.

The measured insight is that **Winamp's own definition of each is a thin wrapper around one primitive
this engine already has.** The three skins that ship a *replacement* for one all say so — Lobe, Big
Bento Modern and ZDL each write `<groupdef id="wasabi.text.group" xuitag="Wasabi:Text"
embed_xui="wasabi.text" h="12"><text …/></groupdef>`. So `WasabiFormWidgets` is a **type
substitution**, applied once in `WasabiSkinInitializer` where the object is created, and everything
downstream — drawing, hit testing, `cfgattrib` binding, script dispatch, geometry — follows with
nothing else to teach:

| Tag | Becomes | Notes |
|---|---|---|
| `Wasabi:Text` | `text` | |
| `Wasabi:EditBox` / `EditBox2` | `edit` | plus a drawn field, since Winamp fills one with a native child window |
| `Wasabi:HSlider` | `slider` | seeds the conventional `wasabi.slider.horizontal.*` ids |
| `Wasabi:CheckBox` | `togglebutton` | plus a drawn box; `radioid` makes it a radio |
| `Wasabi:DropDownList` | `button` | plus a drawn box, arrow and menu |

Four things worth keeping:

- **The `else` is the whole containment.** The substitution runs only when `types.definition(forInstance:)`
  resolved nothing, so a skin that defines the tag itself never reaches it. That is how Big Bento
  Modern keeps its own search box and how Styx and Shield_Amp keep their own `Wasabi:CustomDropDownList`
  wrappers — all three of that tag's users define it, which is why only the inner `Wasabi:DropDownList`
  needed implementing.
- **A slider is the case that argues against drawing.** 19 of the 36 installed skins ship
  `wasabi.slider.horizontal.button`, including all four that use the tag, so the substitution seeds
  those ids and the skin's own artwork draws. Only a skin shipping neither reaches the flat track and
  drawn thumb. A check box is the opposite — **no** `.wal` ships `wasabi.checkbox.*` — so it is drawn,
  on the same deliberate exception as an artwork-less `<Wasabi:Button>` above.
- **A `radioid` check box is a radio, and that is half the tag**: 32 of the 67 declarations carry the
  attribute. It draws round, its set is looked up from the top of its own tree (`radioid` is flat, and
  Styx's pairs live in two different content groups of one window), and clicking the member already on
  leaves it on. Only members that actually *change* are told, because `onToggle` is what a skin reads
  the choice from.
- **A drop-down needs an object to be found, not just drawn.** Styx's and Shield_Amp's
  `customdropdownlist.maki` are the same script: `findObject("dropdownlist.text")`, then
  `onTextChanged` writes the pick to a private string. The initializer expands an invisible `<text
  id="dropdownlist.text">` beneath the control for exactly that — the drop-down draws its own label
  from `default`, so a visible one would print the selection twice.

What still does not draw: `<Wasabi:RadioGroup>` (9 declarations) is a bare grouping id with no
geometry and is correctly inert; `<Wasabi:TabSheet>` is B14 and is why Shield_Amp's Configuration is
still an empty slab.

#### Animated layers are played as a range

`animatedlayer` is a sprite sheet plus a play head, and scripts drive it as a range:
`setStartFrame(getCurFrame())`, `setEndFrame(target)`, `setSpeed(msPerFrame)`, `play()`, then poll
`isPlaying()` (MMD3's rotary volume/bass/treble knobs are exactly this). `WasabiAnimation` makes the
play head a pure function of the elapsed time since `play()`, which is what keeps the renderer and the
script runtime agreeing on the current frame without either owning a clock. `stop()` freezes the head
where it actually is, and an explicit `playing` beats the XML's `autoplay`.
