## `.visualization` — the skin's AVS window (B20a, Phase 48)

**Two different things are called "the visualization", and a `.wal` skin declares both.**

- **`<vis>`** is Winamp's *built-in* analyzer/oscilloscope — the little box in the player. It stays
  engine-drawn (`drawVisualization`, `mode=`, `bandwidth=`, the `colorband*` palette). See
  [rendering.md](rendering.md).
- **`<component param="{0000000A-000C-0010-FF7B-01014263450C}">`** is the *plugin* surface — the box
  AVS and MilkDrop drew into, in a container of its own (`avs`, `avs_window`, `AVS`, `AVS_window`).
  That one holds NullPlayer's real visualization engine: **ProjectM/MilkDrop, Geiss, Tripex**.

Before Phase 48 the second was painted with the first, so a skin's dedicated visualization window was
a second, larger analyzer.

### It is a subview, unlike the video picture

`WinampModernVisualizationSurfaceView` puts a `VisualizationGLView` in the skin's view tree at the
holder's frame — the `.library` seam's shape. That works here and did **not** work for video because
`NSOpenGLView` is self-contained: it installs no view above itself and sizes no ancestor, where
VLCKit does both (see the video section above). The GL view's `hitTest` returns nil, so every click
over the box still reaches the skin — which is what lets `rightMouseDown` open the engine's controls.

It is a **second** engine instance, not a lend of the visualization window's: each `VisualizationGLView`
owns its GL context, display link and engine, and lending would make opening a skin's AVS window
steal the picture out of a window the user had already placed. One per skin, owned by the component
bridge (a layout switch that removes and re-adds the holder must not stand up a second engine), and
released in `tearDownSkin` — a display link left running behind a torn-down window is a frame a
second nobody sees.

### Routing — the reason it needed to be routed at all

There was **no way to open one of these windows**. A container carrying a `component=` GUID is kept
out of the Skin Windows menu on purpose (`WinampModernContainerTopology.isListedInWindowMenu`
requires `kind == nil`) so a routed surface cannot be reached twice — and nothing routed
`.visualization`. It is now a **routed but not managed** surface, exactly like `.video`: never
synthesized (a skin with no AVS window is served by NullPlayer's own), never embedded, so the catalog
answers `.declaredContainer` or `.classicFallback` and nothing else.

`WindowManager.showProjectM` / `toggleProjectM` consult the catalog first, so **Show Visualizations
Window**, a skin's `TOGGLE guid:vis` and `VIS_MENU`'s window item all reach the same window. Two
callers pass `routeToSkin: false` deliberately: `showProjectMFullscreen` (a borderless `.wal`
container has no fullscreen of its own to enter) and the coordinator's own classic fallback (which
would otherwise route straight back into itself).

**And it is listed in Skin Windows** — the correction the first live pass forced. Routing a surface
gives it a route; it does not give anyone a way to *ask*. `isListedInWindowMenu` kept every container
with a `component=` GUID out of that menu, so the AVS windows were invisible there, and **no skin in
the corpus binds a button to its own AVS window**: all eight containers are named (`Visualization`,
`Visualizer`, `Visualizations`), none is `nomenu="1"`, and Winamp opens them from *its* Windows menu.
The rule now admits `WinampModernSurfaceInventory.windowMenuRoutedKinds` — `.visualization` and
`.video`, the two routed surfaces with no menu item of their own — and `toggleSkinWindow` routes
those two through the coordinator, so the menu entry and the Visualizations menu cannot reach
different windows (and the video window still gets its picture parked on it). The managed three stay
out: they each have a menu item already, and a second entry would be the double route this rule
exists to prevent.

### `{0000000A}` is a plugin *host*, and not every holder gets the engine (BB9, 2026-08-24)

The GUID does not mean "MilkDrop's box". It is Winamp's **visualization plugin host**: what renders in
it is whichever plugin is selected, and Winamp's own default there is its built-in **spectrum
analyzer**. MilkDrop/AVS appears only when the user has picked it. Big Bento Modern ships a `MILKDROP`
preset-folder button under its stretched pane *and* its screenshots show an analyzer there; both are
true, and the button is not evidence about the default.

We used to mount the engine over **every** such holder unconditionally, and `VisualizationEngineType`
is only `projectM`/`geiss`/`tripex` — so an analyzer in that slot was unreachable by construction,
not a setting nobody had found. `WinampModernVisualizationHolder` now routes them on the **box**,
never on a skin's object ids:

- A holder at or above **3:1** width-to-height is a letterbox strip and never takes the engine — that
  is an analyzer's shape. Big Bento's three placements measure 7.3 (stretched), 1.0 (mini) and ~2.5
  (the Visualization tab), so the boundary is nowhere near any of them.
- Of the rest, the **largest** takes the engine. `makeVisualizationSurface()` deliberately vends one
  surface per skin — two GL contexts, two display links and two spectrum consumers against the same
  audio is what that cache prevents — so a second holder asking for it got the same view moved out
  from under the first, which is why "the tab works and the mini doesn't".
- Every other holder draws the analyzer rather than sitting black.

### A `<component>` can name its holder in `hold` (Defix, 2026-08-28)

Three elements can hold a component, and they do not read the same attribute. `windowholder` /
`componentbucket` take `hold` (then `component`, then `guid`); `<component>` is documented with
**`param`**, which is what mmd3, CornerAmp and Winamp Modern all write. Defix writes its detached
visualizer's box the fourth way:

```xml
<component id="VISCON.component.vis" … hold="guid:{0000000A-000C-0010-FF7B-01014263450C}"/>
```

Both readers took `param`/`guid` only on that element, so this box resolved to **no kind at all** —
not `.visualization`, not even `.other`. That is worse than it sounds: an unrecognized holder is not
drawn by `drawComponent` and is not in `componentHolders()`, so it got neither the host's engine nor
the BB9 analyzer fallback. **Detach Visualizer** opened a correctly framed window with an empty slab
of the frame's own colour where the visualization should be, and every probe that keys on holders
(`HOLDERS`, `VIS holder`) reported nothing to explain it.

`hold` is now read **last** on a `<component>`, in both readers, which must stay in step:

- `WasabiRenderer.componentReference(of:)` — what draws and what hosts
- `WasabiSurfaceInventory.holderKind(of:)` — what the surface catalog reaches

Last, not first, so `param` still wins wherever a skin declares both and nothing that already
resolved moves. This changes no routing: `.visualization` is not in `managedKinds` and `VISCON`
declares no `component=` GUID of its own, so Defix's catalog still reads
`visualization=classic(the skin declares no visualization surface)` and **Windows ▸ Visualizations**
still opens NullPlayer's own window.

> **The render dump does not see this container.** `RENDER-DUMP containers:` lists Defix's other
> nine but not `VISCON`, so no `VIS holder` line is printed for it either — before *or* after the
> fix — even though the app parses it, opens it and now renders in it. `VISCON` declares
> `default_w="406" default_h="360"` and no `visible=`, so it is neither hidden nor collapsed and
> should survive `windowContainers`. Unexplained, and the reason the corpus table below undercounts.
> Confirm a visualization holder **in the app** (`WINAMP-MODERN-VIS: resume`) before trusting a
> headless zero.

### What the renderer draws

`WasabiSceneRenderer.hostedVisualizationHolders` is the set of holders the view layer has actually
filled — now at most one. Those boxes are painted **black and nothing else**; bars under a live engine
are a second visualization nobody can see, costing a repaint every frame. Every *other* `{0000000A}`
holder gets `drawVisualizationBars`, which is a real analyzer (see
[rendering.md](rendering.md) → *The analyzer a `<component>` box draws*). Headless — the render
sweep, the golden images, `WinampModernRenderDumpTests` — there is no view layer, the set is empty,
and every `<component>` box draws the analyzer.

### The menu

The surface's right-click menu **is** the visualization window's menu — `VisualizationContextMenu`,
which `ProjectMView`, `ModernProjectMView` and this surface all build. It was written twice,
identically, in the two window views, and this surface first shipped with a short hand-written one
(engine, next/previous/random, the host's Visualizations submenu). The first live report against it
was that it was "truncated" beside the real one — which is what a third, drifting copy of a menu looks
like from the outside. The shared builder takes a `VisualizationMenuTarget` (the engine plus every
action) and an `Options` value for what it only displays: the preset cycle mode and interval, and
whether **Fullscreen** and **Close** make sense at all. The embedded surface passes `false` for both —
a box inside the skin's window has neither — and keeps its own cycle timer against the same
`ProjectMPresetCycleSettings` keys, so a cycle set in one place is the cycle in the other.

### The engine will not start in a window nobody has shown yet

**The defect that kept every AVS window black but Bento's.** `VisualizationGLView.startRendering()`
requires `window.isVisible`, and the only thing that ever restarts it is an occlusion change that
resumes a link stopped *because* of occlusion. A skin's AVS window is an auxiliary container: created
hidden, laid out, ordered in later. So the surface built during that first layout pass asked to
render against a window nobody could see, was refused, and never asked again — the box stayed black
while the chrome around it drew perfectly. cPro-Bento was the single skin unaffected, because its
holder is script-built inside the **main player window**, which is already on screen.

So the surface has `resumeRendering()`, and it is called *after* the window is ordered in — from
`WinampModernMainView.setSceneVisible(true)` (which forces the layout pass first, so the surface
exists to be told) and from `setAuxiliaryWindow` on the visualization container, the same shape as
the video surface's attach. In DEBUG it logs `WINAMP-MODERN-VIS: resume window=… visible=… box=…
engine=… rendering=…`, which is the one line that separates "no surface", "wrong box" and "refused to
start" without a GUI session.

### One visualization window at a time

Ours and the skin's are mutually exclusive, and each is asked before the other is shown:
`isProjectMVisible` answers for **either**, showing the skin's window calls
`WindowManager.hideLocalVisualizationWindow()`, showing ours calls the reverse, `toggleProjectM`
gives a window of ours that is actually on screen the first refusal, and a skin that owns the surface
takes it over at load (`handOverVisualizationToSkinIfNeeded`) if our window was the one showing it —
a restored session, or the previous skin had no AVS window. Without all five, two engines rendered
against the same audio at once, which is what "the two windows compete" was.

### `VIS_FS` fullscreens the **engine**, not a window

Five of the eight AVS windows carry a `VIS_FS` button *inside* them. Answering it with
`showProjectMFullscreen()` opened NullPlayer's own window with a second engine in it while the skin's
box kept rendering — the fastest way to reproduce the clash above. A hosted surface answers it
itself: the `VisualizationGLView` **moves** into a borderless `.screenSaver`-level window filling the
screen and moves back afterwards (Esc, `f`, or a double-click). One view, two homes — it re-pins its
GL context and display link from `viewDidMoveToWindow`, so no second engine ever exists, and the
skin's window, chrome and buttons stay exactly where they were. `.screenSaver` is also what the GL
view reads as "presenting fullscreen" when deciding whether an occluded window may stop rendering.

### The keyboard

The visualization window's keys work in the skin's window too: **←/→** step (shift = hard cut),
**R** random, **F** fullscreen, **P** quality, **C** cycles Manual → Auto-Cycle → Auto-Random, **Esc**
leaves fullscreen. They are offered *after* the skin's own accelerators (`WinampModernMainView.keyDown`
→ `scripts.dispatchKeyDown` first), so a skin binding never loses its key, and a key the surface does
not take still falls through to the host's menu shortcuts. In fullscreen the whole map goes to the
surface — there are no buttons on screen at all there.

### The `VIS_*` buttons

`VIS_NEXT` / `VIS_PREV` step **the skin's own AVS engine first** (its presets for ProjectM, its
effects for Geiss and Tripex), then our visualization window's presets, then the `<vis>` box's mode —
each rule is "the visualization the user is actually looking at". `VIS_MENU` and `VIS_CFG` open the
surface's own menu when one is live: what is running, Next/Previous/Random, and the host's
Visualizations menu underneath. `VIS_FS` is unchanged — our own window, which is the only one with a
custom fullscreen.

### A layout below its own minimum

Unrelated to hosting, found on these windows: `defaultSize` took `default_w`/`default_h` literally,
and **11 layouts in 4 skins** declare a default *smaller* than their own `minimum_w`/`minimum_h` —
Anaheim_Player_01's `avs_window` (120 wide against a 180 minimum), Styx's `AVS` and `MLibrary`
(300×300 against 400×230), and both Love is War Miku skins in four windows each, whose `avs` is
200×150 against a **400×300** minimum. The window opened at the default while the standard frame's corner and edge art
laid itself out for the minimum, so the chrome came out cut off down one side. The opening size is
now clamped to the **declared** minimum — never to `layoutMinimumSize`, whose computed protective
half exists to stop a window being *shrunk* and has no business enlarging one its author sized.

### The corpus, measured (`VIS holder` in the render dump)

**8 of the 31 installed skins.** Every one is a separate container; none embeds the component in the
player.

| Skin | Container | Box (skin px) |
|---|---|---|
| hatsune_miku_5 | `avs` | 479×326 |
| winampmodern566 | `AVS` | 342×232 |
| multipass | `avs_window` | 298×134 |
| Itemskin | `AVS_window` | 277×71 |
| Styx | `AVS` | 220×200 |
| Anaheim_Player_01 | `avs_window` | 100×200 |
| Love is War Miku | `avs` | 190×84 |
| Love Is War Miku V2 | `avs` | 190×90 |

The other 23 declare no visualization container, and NullPlayer's own window serves them exactly as
before.

**This count is a floor, not a census.** It is what the render dump prints, and the dump does not
enumerate Defix's `VISCON` (see the `hold` section above) — a real, openable visualization container
with a real `{0000000A}` box in it. Treat the table as "at least these", and measure a specific skin
in the app before concluding it has none.

