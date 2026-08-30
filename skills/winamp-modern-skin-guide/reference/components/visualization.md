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

**The box a holder is routed on is the one its markup declares, where the two differ (BB9,
2026-08-29).** Big Bento's stretched pane is `w="0" relatw="1"` — the whole holder, 7:1 — and the
side-by-side Multi Content View layout narrows it to whatever the cover and mini pane leave, which is
about 2.3:1. Measured on that box it stopped being a letterbox, claimed the engine and went black,
which is precisely the placement BB9 settled is a **spectrum analyzer**. `prefersAnalyzer(holder:)`
asks `WinampModernBentoMultiContentView.isStretchedVisualizationPane` first and the box second; every
other holder is still routed on the box alone. The general rule this is an instance of: **a holder
the host has resized is not evidence about what the skin meant to put in it.**

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

### An unhosted pane is a surface with a choice of its own (BB9a, 2026-08-29)

**A pane that draws the analyzer is not stuck with it.** Right-clicking one opens the same question a
`<vis>` box answers — Winamp's own analyzer, Winamp's oscilloscope, Cava, vis_classic, or `Off` —
against a selection that is **this surface's**, not the `<vis>` boxes'.

The split is `WinampModernVisSurface` (`.visBox` / `.componentHolder`), and it exists because the two
boxes are not the same kind of thing. A `<vis>` is the skin's artwork: cut to size, coloured by its
author, and in Big Bento Modern mirrored into a butterfly. A `{0000000A}` pane is an **empty plugin
slot** with no markup at all. Wanting Cava in the big pane is not a request to overpaint the artwork,
which is exactly what one skin-wide choice did.

| | `<vis>` boxes | `{0000000A}` pane |
|---|---|---|
| Engine | `@nullplayer.vis/engine` | `@nullplayer.vis/engine.holder` |
| Mode | the skin's own `mode=` attribute | `@nullplayer.vis/mode.holder` |
| Colours | the skin's `colorband*` / `colorosc*` | the host palette, so a theme switch recolours it |
| Menu | `showVisualizationMenu` | `showVisualizationHolderMenu` |

The **selections** are separate; the **engine objects** are not. `WinampModernSpectrumAnalyzerState`
keys its renderers by suite, so one `CavaVisRenderer` serves both surfaces — two instances would be
two audio consumers against the same audio, and their per-box state is keyed by object anyway. The
one thing that has to be conditional is `select`'s discard: dropping the outgoing engine's taps and
cores while the *other* surface is still drawing with it wipes the bars out from under a box the user
never touched.

Drawing routes in `drawVisualizationHolder`. Winamp's own analyzer stays `drawVisualizationBars` and
is not `WasabiBuiltInVisRenderer`'s: that one takes its band count from `bandwidth` (19 or 75, cut for
a 144px `<vis>`), and 19 bands across a 1400px pane is a row of slabs — this surface counts bands off
its own width. Everything else goes through the same `WasabiVisRenderer` seam the `<vis>` boxes paint
through, handed a style synthesized from the palette. The tap demand asks the pane on its own terms
too: a pane on the oscilloscope turns the PCM tap on in a skin whose every `<vis>` is an analyzer, and
one on Cava turns both taps off.

> **The modes and the engines are one radio group, so picking a mode is also a choice about the
> engine.** `Spectrum Analyzer` and `Oscilloscope` are Winamp's *own* two, and they mean the box goes
> back to Winamp's engine. Writing only the mode is a **one-way door** and it reached the running app:
> the row ticked, vis_classic kept painting, and the pane could not be got off it. The rule lives once,
> in `WinampModernSpectrumAnalyzer.chosen(byPicking:current:)` — `presentScriptPopup` applies the same
> one to a skin's own mode rows. `Off` is the exception: it is the absence of all of them rather than a
> peer, so it leaves the selection alone (switching back on returns the last engine) and it sits at the
> **end** of the group rather than third in Winamp's enum order.

Two conditions guard the click, both the skin's right to be left alone. A pane the view layer *has*
filled with the real engine answers with that engine's own menu instead. And because
`componentHolder(at:)` finds a holder whatever is stacked on it, a skin control sitting over a pane —
Big Bento's `vis.full.buttons` overlap theirs — keeps its own right-button handler.

The same gap still exists in the host's `<vis>` menu (`applyVisualizationModeFromMenu` writes only the
mode). It is unreachable on Big Bento, whose butterfly menu comes through the skin-popup route that
already hands back, but a skin that leaves the right button alone over its `<vis>` would hit it.

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

### One surface, two holders — unmount before you mount (BB35, 2026-08-30)

`makeVisualizationSurface()` vends **one** surface per skin, and `engineHolder(among:)` moves it
between holders as the eligible set changes. So the holder the engine moves *to* and the holder it
moves *from* hand back **the same object**, and the order of the two passes in
`WinampModernMainView.reconcileHostedSurfaces()` is load-bearing.

It mounted first and unmounted second. On an election flip that registered one object under both ids,
and the unmount pass then ran `unmountFromHolder()` — `stopRendering()` and `removeFromSuperview()` —
on the instance the mount pass had just added. The new id kept a **detached, stopped** surface, and
because the mount pass was guarded on `visualizationSurfaces[id] == nil`, every later pass skipped it
as already mounted. Nothing could put it back.

**Black is the tell, and it is louder than it looks.** A holder that has lost its surface this way is
still in `renderer.hostedVisualizationHolders`, which suppresses `drawVisualizationHolder` — so the box
does not fall back to the analyzer the way an unelected holder does. It draws nothing at all, for the
rest of the session. Reported as Big Bento Modern's Visualization tab going black once the Multi
Content View mini pane is ticked: ticking the pane adds the second eligible holder, opening the tab
flips the election.

Two rules follow, and both are now in the reconcile:

- **Unmount before mounting**, so a move cannot strip the surface it has just placed.
- **Attach every pass, not only on creation.** "Create it, add it, resume it once" can only ever start
  the engine on the pass that made the surface; anything that leaves the hierarchy afterwards needs a
  route back. A surface already attached is left alone, so this costs no per-layout engine churn.

The same shape is why `unmountFromHolder()` is deliberately non-terminal (the bridge caches one engine
per skin and the box coming back is a tab switch, not a stop) — the cache is what makes the aliasing
possible in the first place.

`WINAMP_MODERN_SURFACE_TRACE=1` prints each mount/unmount with its object pointer, which is the only
way to see the aliasing; the headless harness makes no surfaces at all. See
[harness.md](../harness.md).

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

**16 skins declare a `{0000000A}` surface; 6 of them embed one in the player.** Re-measured
2026-08-30 (B23a), replacing a table that read "8 of the 31 installed skins… every one is a separate
container; none embeds the component in the player." Both halves of that were wrong, and the reason
is in the next paragraph.

Embedded in the player's own container — the engine mounts here, in the player window:

| Skin | Container | Holder(s) |
|---|---|---|
| 2222-cPro__Bento | `main` | `centro.windowholder.visualization` + 2 unnamed |
| Big Bento Modern | `main` | `vis` ×2 (Multi Content View), `wdh.vis.object` (SUI tab) |
| Big Bento Modern Windows 10 edition | `main` | same three |
| BLAKK | `main` | `vis` — 144×125, in the `remote` layout |
| winampmodern566 | `main` | `myviswnd` (*and* a separate `AVS` container) |
| Defix Hi-END 200 | `SUI` | `wdh.vis.object` (*and* the separate `VISCON`) |

In a container of their own:

| Skin | Container | Box (skin px) |
|---|---|---|
| hatsune_miku_5 | `avs` | 479×326 |
| winampmodern566 | `AVS` | 342×232 |
| Defix Hi-END 200 | `VISCON` | 372×272 |
| multipass | `avs_window` | 298×134 |
| Shield_Amp | `AVS` | 285×104 |
| Itemskin | `AVS_window` | 277×71 |
| Love is War Miku | `avs` | 390×234 |
| Love Is War Miku V2 | `avs` | 390×240 |
| Styx | `AVS` | 320×200 |
| Anaheim_Player_01 | `avs_window` | 160×200 |
| Nullsoft.Winamp.2000.SP4.Lite | `AVS` | 88×2 |

Ebonite_2_1 names the GUID but declares no holder (it is a `cfgattrib`). The remaining 20 skins
declare no visualization surface at all, and NullPlayer's own window serves them exactly as before.

**Why the old table was wrong, and the trap it is.** `componentHolders()` filters on the visible
scene, and a skin routinely parks its visualization group off-screen: BLAKK puts the whole mini-AVS
group at `x="161"` in a 160-wide `remote` layout under a `visible="0"` group and slides it in from
`minivis.maki`. So every player-embedded holder in the corpus measured as absent, and the table
recorded that absence as "none embeds the component in the player" — the same blind spot
`VIDEO holder … hidden` and `PLAYLIST holder … hidden` each already needed a pass for. The dump now
has the third pass, and prints `VIS holder <container>/<layout>: <id> hidden` with no frame (an
object outside the scene has no resolved geometry).

It is **not** "a layout the probe never selects" — the dump activates every layout, and printed
BLAKK's `VIS box main/remote` from the same pass all along. Whenever a holder seems missing, check
visibility before layout selection.

Two skins in the *separate container* table above (Shield_Amp, Nullsoft.Winamp.2000.SP4.Lite) are
plainly visible holders that the old table also missed, so it was stale independently of the hidden
pass. The Love is War Miku boxes moved too (390×234, not the recorded 190×84) — those numbers
predate the declared-minimum clamp described earlier on this page. **Re-measure rather than trusting
any of these numbers after an engine-wide change**; the sweep is one `swift test --filter
WinampModernRenderDumpTests` per skin with `WINAMP_MODERN_WAL` set, grepping `^VIS holder`.

in the app before concluding it has none.

