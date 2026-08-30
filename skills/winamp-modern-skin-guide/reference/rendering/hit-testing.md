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

#### Resizing the window (Phase 89, B77)

A `.wal` window is borderless, so **the skin nominates its own resize handles**: `resize="left"`,
`"topright"`, `"bottomleft"` and the rest, hung on the layers that draw the border.
`WasabiSceneRenderer.resizeEdges(at:)` reads it, `WinampModernMainView` drags it, and
`WinampModernMainView.resizedFrame(...)` is the pure geometry form.

**597 handles in 32 of the 36 corpus skins, every one of them on a `<layer>`** — winampmodern566 83,
S7Reflex 43, Nullsoft SP4 Lite 35, Styx and Itemskin 30 each, Shield_Amp 26. Most come from the
shared `standardframe` include, which is why one implementation reaches nearly the whole corpus; the
four that declare none (cPro-Bento, Overdrive_2, both Big Bento *Light* variants) resize through the
`<Wasabi:Frame>` splitter or not at all. Reach:
`rg -i -o 'resize="(topleft|topright|bottomleft|bottomright|top|bottom|left|right)"' "$corpus" --glob '*.xml' --glob '*.xui'`
— which answers 599, two of them commented out in Nullsoft SP4 Lite.

Four rules, and the first is what makes the other three cheap:

- **Topmost wins, with no special pleading.** The skins express every exception by declaration order,
  so the ordinary `object(at:)` already answers them. `standardframe.xml` lays a bare
  `<layer id="window.resize.disabler" x="10" y="15" w="-20" h="-24">` over the interior *after* the
  border layers — its own comment says *"prevents it from covering Buttons"* — declares the two corner
  grips after that again, and puts the close button on the top strip above all of them. None of those
  names appears in the implementation. (Nullsoft SP4 Lite is the same lesson from the other side: its
  author commented a full-width `resize="top"` strip out, *"causes some huge area to appear right
  around the switch button"*.)
- **The press claims only the first click.** 12 handles in 4 skins (winampmodern566, Nullsoft SP4
  Lite, mmd3, BLAKK) also carry a command on the second one, always a titlebar corner's
  `dblClickAction="SWITCH;shade"`. Claiming every press would take shade mode away from them:
  dragging resizes, double-clicking still acts. No handle in the corpus carries a plain `action=`.
- **The handle outranks the drag.** A border layer is a plain `<layer>` with no action, so
  `shouldDragWindow` accepts it — checked second, the window *moves* off the very strip the user
  grabbed to stretch it. 16 handles say `move="1"` outright (both Big Bentos, Ujola Cat, mmd3); the
  border is still a border, and each of those skins keeps a titlebar to drag by.
- **A fixed layout has no handles**, whatever its borders declare — the same rule `userResizeLimits`
  applies to the window's limits (see `compatibility/limits-and-policy.md`). Shield_Amp is the case:
  its player declares no `minimum_*`/`maximum_*` while inheriting border layers that do declare
  handles, and Winamp gives that window no affordance either.

The cursor comes from the same hit test, set in `mouseMoved` rather than from a cursor rect: a rect
can only describe the handle's *box*, and the exceptions above live in what covers that box. Promising
a resize cursor where the press does something else is precisely the BB21 defect. Corners get the
crosshair — macOS ships no diagonal resize cursor, the same substitution `BorderlessWindow` makes.

The size is clamped to the layout's range **before** the origin is derived from the anchored corner.
Clamping the finished frame instead leaves the origin where the unclamped drag put it, and a window
sitting at its minimum then walks across the desktop while the pointer keeps pushing.

Before this the only affordance was AppKit's own borderless edge band, about a pixel of it, which is
what a live report on Shield_Amp's playlist window described as impossible to grab.

#### `sysregion` is signed, and it shapes the window (Phase 34, B76)

A layer can contribute its bitmap to the **window region** instead of to the picture. The attribute
is a signed combining mode against the region built so far, and only the sign is read: a negative
value is *region only* — it paints nothing and **subtracts** its silhouette from the window; a
positive one paints as usual and **adds** its own shape back.

The bitmap behind a negative layer is a silhouette, not artwork — Ujola Cat's `window-regions.png` is
a magenta-and-white mask — and painting it puts a coloured slab across the window.
`standardframe.xml` is where this bites: its `wasabi.frame.layout` carries five `sysregion="-2"`
layers and is inherited by every `Wasabi:StandardFrame:*` flavour, so the mask landed on the playlist
window, on the synthesized library window, and on anything else framed the same way — reported as
"layered full backgrounds in different colours" and "multiple top menubars".

Absent, `0` and the non-numeric forms skins write (`"AND"`, which Anexa uses 15 times) paint as
before and shape nothing. Both negative magnitudes in the corpus are cut-aways: `-2` on the corner
and edge silhouettes of 28 skins, `-1` on winampmodern566's and S7Reflex's config drawer.

`WasabiSceneRenderer.isRegionOnly` answers the paint half; `regionCuts` / `buildWindowRegion` answer
the shape half, and `containsRegionPixel` gates `object(at:)` so a trimmed corner takes no click
either. **Measured: 108 of 312 corpus layouts change shape, across 22 of the 36 skins** — mostly a
1px border and 25px corners, up to 18% on skins whose frame region trims more than a corner (Ebonite,
Sony_Walkman, Styx, Ujola Cat).

Four properties of the composition are load-bearing, and each was found by a skin rather than
reasoned out.

**It composites once, over the finished scene.** The cut is a `.destinationOut` draw of the
silhouette image after the last node, *not* a `CGContext` clip mask. A clip mask is consulted by
every drawing operation, so fractional coverage is applied once per overlapping draw and accumulates:
two opaque layers through a 50% mask leave 75% alpha with their colours blended. Across
winampmodern566's stacked player artwork that moved **8451 pixels** the region never meant to touch,
and left Ebonite's whole playlist window at alpha 76.

**Order decides the shape.** A positive `sysregion` adds back what a negative one took, so the scene
order *is* the semantic and a set of "the negative ones" cannot express it. S7Reflex lays its config
drawer *behind* the player in `main/normal`, and the drawer's two 350 and 251 px silhouettes are
followed by the `player.main` group's `sysregion="1"` — subtracting every negative layer cut away
the left third of the window (**31,289 px, 16.6%** of the layout).

**The cut is binary, at half coverage.** A region is a shape, not a translucency — Win32's own is —
and a skin is entitled to hand over a silhouette that is neither opaque nor clear. Ebonite cuts its
four frame strips with `wasabi.frame.dummybg`, a crop of the window's own *background texture* at
alpha 179; as coverage that left the border of every framed window at 30% opacity, which reads as a
rendering fault rather than as a shape. Half coverage is also the midpoint of an anti-aliased edge,
so a rounded corner lands where the artwork draws it.

**A window is never shrunk by additions alone.** Winamp builds the region up from nothing; here it
starts as the window's own rect and a layout that declares no negative `sysregion` keeps the
rectangle it has always had. 672 of the corpus's 926 declarations are positive and most are ordinary
painted artwork saying "I am part of the window" — composing a shape purely from those would decide
the shape of every skin that uses the attribute at all, on the strength of whichever layers its
author happened to mark, and take a window away wherever the union fell short. Every framed window in
the corpus opens its composition with a full-bleed positive anyway (`wasabi.standardframe.*` and
`Wasabi:MainFrame:*` all carry `sysregion="1"` on the group that fills the window), so the seeded
rect gives the same answer wherever a skin does say.

The shape reaches the **window** without any `NSWindow` work: all three `.wal` window paths — the
player, auxiliary containers, and the hosted-window materializer — already set `isOpaque = false`,
a clear `backgroundColor` and `hasShadow = false`, so an erased corner is genuinely transparent. It
is cached against the region objects' own boxes and bitmaps rather than the graph's mutation counter,
which moves for anything a script writes; a canvas-sized rebuild per frame is not affordable on a
1526×868 window.

> **The corner-alpha check.** `main`, `main/stick` and `equalizer` in Shield_Amp were always alpha 0
> — hand-drawn layouts carry the rounded alpha in their own PNGs — while `Pledit`, `MLibrary`, `AVS`
> and `Video` were a flat opaque `rgb(95,110,127)`, `component.bg` through a square corner. Sampling
> the four corner pixels of every dump is the cheapest test that this still works.
