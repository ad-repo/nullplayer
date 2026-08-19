# Component hosting and surfaces

Reference for the `winamp-modern-skin-guide` skill: hosted components, surface resolution and synthesis, layout, teardown, and mode integration.

#### `TOGGLE`'s parameter is a component **or a container id**

`action="TOGGLE"` addresses a component by short name or GUID (`Eq`,
`guid:{45F3F7C1-…}`) *or* names one of the skin's **own containers**, and Winamp shows/hides whichever
window that is. Resolving only through `WinampModernComponentRegistry.kind(for:)` left every
container-addressed button inert, because that registry deliberately never matches a container id.

Defix's `CONF` button is exactly one — `<button id="CONF" action="TOGGLE" param="Config">` — so its
entire configurator was unreachable: the 31 changeable backgrounds, the eight display styles, and the
songticker scrolling mode. That last one is why the symptom looked like a renderer bug rather than a
routing one: the skin ships `Disable Songticker Scrolling = 1`, its own `onDataChanged` writes
`ticker="off"`, and the only control that could turn it back on could not be opened. `TOGGLE` now
falls through to `containerWindowToggleRequested`, matching an auxiliary container by id
(case-insensitively) — so a skin button and the View menu still resolve through the same windows.

> **Gotcha:** an auxiliary container's `default_visible="1"` is not honoured — every one is
> `orderOut` at setup and placed on first show. Defix's `Config` declares it, so in Winamp its
> settings window opens with the skin and here it does not. Deliberate for now (a settings window
> opening at every launch is worse), but it is a real difference.

### Component hosting

A `.wal` skin is a whole UI suite, and skins disagree about where the playlist, equalizer, and library
*are*: cPro-Bento embeds all three in one SUI window, mmd3 ships a playlist window and no library,
CornerAmp ships playlist + EQ, Winamp Modern ships playlist + library. The engine is therefore
**component-hosting-first**:

- `WinampModernComponentRegistry` maps the standard Winamp component GUIDs to a typed
  `WinampModernComponentKind`. **GUIDs never escape the registry**, and matching is *exact* — the
  fuzzy id rule lives in `kindFromHolderIdentifier` and is only ever applied to an engine holder's id
  (`centro.windowholder.library`), never to a container id or a menu parameter.
- Three element types are holders: `<windowholder hold=…>`, `<componentbucket>`, and
  `<component param=…>` (`isHolderElement`). The last is what separate-window skins use for their real
  content — mmd3's `pledit-normal.xml`, Winamp Modern's `ml-normal.xml`.
- `WinampModernContainerTopology.analyze` classifies each container: a real visible window or an
  SUI-collapsed stub (1×1 / `window-overrides` invisible), its `kind` (from its own `component=`
  GUID), its layout's `minimumSize`/`maximumSize`, and whether NullPlayer synthesized it.
- `WinampModernComponentHost` is the sandboxed seam supplying app-side content per kind;
  `WinampModernComponentBridge` implements it over `AudioEngine` and owns the embedded library.

There is **one** script runtime and **one** component host per loaded skin, shared by the main window
and every auxiliary container window. Only the main view (`drivesScripts: true`) owns the *global*
script callbacks (theme, actions, mouse, EQ) — layout switching and resizing are **container-scoped**
(below).

#### The window layer these views sit in

Every `.wal` window is `.borderless`, which changes what AppKit will do for you:

- **`performClose(_:)` does nothing.** It simulates a click on the window's close button, and a
  borderless window has none — it beeps and returns. A skin's `action="CLOSE"` therefore has to route
  to the controller, which quits from the player window (as the classic skin's close button does) and
  hides an auxiliary one. `MINIMIZE` likewise takes the whole set of the skin's windows down together,
  and their style masks carry `.miniaturizable` — no chrome is drawn for it, but AppKit will not
  miniaturize a window whose mask forbids it. Both go through `closeRequested`/`minimizeRequested` on
  the view; nothing in the view calls AppKit's window commands directly. Phase 24
- **A window created with `NSRect(origin: .zero, …)` opens at the bottom-left corner of the screen**,
  which is where every auxiliary container window used to appear. They are placed on **first show**
  — stacked under the main window, clamped to the screen — and never repositioned again, so a window
  the user has moved stays where they put it (`placedAuxiliaryWindows`). Phase 24

#### Where a surface lives

`WinampModernSurfaceCoordinator` is the single answer, for menus, skin buttons, and restore alike:
**embedded → declared container → synthesized container → classic fallback**. `WindowManager`'s
`show*`/`toggle*`/`is*Visible` consult it before their classic paths; the fallback has its own entry
point (`showClassicSurfaceForWinampModern`) because re-entering the public toggles would route back
into the coordinator. The *type* is still `classicFallback` and the entry point is still
`showClassicSurfaceForWinampModern` — it is the classic **controller**, not the classic look: since
Phase 16 those windows paint from the skin's palette (below).

Two things about the embedded case that are easy to get wrong:

- **Revealing one is a Wasabi contract, not a search.** Winamp calls
  `System.onGetCancelComponent(guid, true)` when a component wants to be visible, and an SUI skin uses
  that to switch to the tab/drawer holding it. Detecting a holder and returning does nothing visible.
- **The script is not enough.** ClassicPro handles that event but only `if (active_tab != 0)`, and its
  `active_tab` is already 0 at startup — so it concludes it is already showing the library while
  `centro.library` has never been shown. `windowholder autoopen="1"` is the other half: the holder
  opens its own surroundings. `openHolders(for:in:)` un-hides the ancestors between an `autoopen`
  holder and its layout.
- An embedded surface owns **no `NSWindow`** and must never reach docking, compact-mode snapshots, or
  frame persistence.
- **An embedded library is revealed once at launch** (`revealEmbeddedLibraryAtStartup`, right after the
  catalog is reconciled) — cPro-Bento opens on its Media Library tab, and without this that tab is an
  empty pane until the user picks Windows → Library Browser. Only for `isEmbedded(.library)`, so a skin
  with its own library window opens nothing at launch.

The four steps in full, since every request — a menu item, a skin button's `TOGGLE guid:…`, a restored
session — resolves through this one catalog in this one order:

1. **Embedded** — the skin already shows it inside a window it owns (above).
2. **Declared container** — the skin ships a window for it
   (`<container id="Pledit" component="guid:…">`).
3. **Synthesized container** — the skin ships none, so one is built *before initialization* from the
   skin's own `<Wasabi:StandardFrame:…>` around a `<component>` of that kind. Only in the
   separate-window arrangement, and only when a frame qualifies (see below).
4. **Classic fallback** — NullPlayer's own window, **with a diagnostic naming the prerequisite that
   failed**. Geometry is unchanged from the classic windows — same title-bar height, borders, and
   button boxes — so only the pixels differ.

Which skin lands on which step is measured per skin: see the routing table in
[compatibility.md](../compatibility.md#hosted-components).

#### Synthesizing a missing window

`WasabiSurfaceInventory` walks the *expanded document* before graph creation — through `<group id>`,
XUI tags, `inherit_group`, `embed_xui`, `Wasabi:Frame` panes, standard-frame `content=`, and typed
holders — and `WasabiSurfaceSynthesizer` appends a `<groupdef>` + `<container>` for each missing
surface in a **separate-window** skin. Both run before `WasabiSkinInitializer`, so synthetic XML is
registered, inheritance-validated, instantiated, and script-bound exactly like the skin's own.

- It has to be pre-graph: reading the live graph would come too late for synthesis *and* would mistake
  cPro's script-built holders for missing surfaces.
- Ambiguity suppresses synthesis. A duplicate skin window is a much worse failure than a classic
  fallback.
- A frame qualifies only if the skin declares it *and* it carries the script that instantiates its
  `content=` group. The built-in `wasabi.*` shells never qualify — synthesis reads the *document's*
  groupdefs, so a seeded shell is not a candidate, and one would produce a titled empty box.
- mmd3 declares `wasabi.standardframe.*` with **no `xuitag`** (real Winamp's standard library supplies
  it). `WasabiTypeRegistry.registerXUITagAlias` fills an *unclaimed* tag pointing at an *existing*
  groupdef, before the shells are seeded, so a skin's own `xuitag=` always wins.
- **Winamp defines no equalizer component GUID.** An equalizer is recognized by its controls
  (`EQ_BAND`/`EQ_PREAMP`/`<eqvis>`) and a synthesized one uses `guid:eq`. `EQ_TOGGLE`/`EQ_AUTO` do not
  count as evidence — a button that opens the EQ is not an EQ.
- **An equalizer is never synthesized** (`synthesizableKinds` excludes it). Synthesis always builds
  the same body — a standard frame around a `<component>` holder *we* invented — and never wraps the
  skin's own controls. For the playlist and the library that holder resolves to a complete NullPlayer
  surface, so the window earns its place. The equalizer's hosted surface is a stand-in:
  `drawEqualizerComponent` paints eleven tracks with 3px thumbs and nothing else — no on/off, no auto,
  no presets, no band labels, no dB scale.
  **Two routes reach an equalizer and they must agree.** The menu resolves through the catalog
  (`routeWinampModernSurface`), while a skin's own `TOGGLE Eq` button goes through
  `WinampModernMainView.routeComponentToggle`, which checks the *auxiliary containers* before falling
  through to the classic window. Leaving the container synthesized but unrouted made those two
  disagree: the menu opened the full classic EQ and the skin's button opened the stub. Not building it
  is what keeps them consistent — both now land on the classic window, which has painted from the
  skin's own palette since Phase 16. Defix and T800 are the measured cases (neither declares a single
  EQ control); a skin that draws its own equalizer is matched as embedded or declared first and never
  reaches synthesis.

#### Container-scoped layout callbacks

One skin, one runtime, several windows: `layoutSwitchRequested`/`layoutResizeRequested` carry the
container's `WasabiObjectID` (derived from the receiver), and the window controller routes each to the
view that owns that container. Without the id, a playlist script resizing itself resized the player.
The controller installs both **before `scripts.start()`** — a skin that resizes from `onScriptLoaded`
does it during `start()`.

#### Resize, and why a skin needs it

Wasabi resizes synchronously and notifies as it goes, and skins carry real state in `onResize` — often
state that is assigned **nowhere else**. Three rules, each earned:

- **Seed it once after `scripts.start()`** (`view.scriptsDidStart()`), after `onScriptLoaded` and XUI
  params but before the first `updatePlaybackState()`. ClassicPro's `beat.m` sets `showBeat`/`showPromo`
  only in `onResize`, so without a seeding pass the first `onPlay` hid its display permanently.
- **Fire it whenever a script's own mutation moves something,** not only on a canvas change. The
  runtime flags geometry-affecting mutations (`setXmlParam` on a geometry/visibility key, `resize`,
  `show`/`hide`, splitter `setPosition`, `init`) and calls `geometryDidSettle` once as the outermost
  event unwinds — a handler that moves five things produces one round of `onResize`, and a timer that
  only advances an animation frame produces none. cPro's "close side view" button collapses the pane
  and relies on `area_right.onResize` to swap in its **open** button, which ships `visible="0"`; without
  the settle, closing the playlist hid the only control that could reopen it.
- **Hidden objects are still laid out.** `layoutNodes()` resolves the whole active layout including
  invisible subtrees, and backs both `resizeTargets` and `resolvedGeometry`; drawing and hit testing
  keep using `sceneNodes()`. A hidden pane with no geometry can never hear that it is wide again — a
  one-way door.

Each target hears its **own** parent-relative `(x, y, w, h)`, and only if its own box actually moved.
A UI Size change dispatches nothing: it moves the drawing boundary, not the skin's canvas.

#### Colours and hosted AppKit content

`WinampModernThemeCoordinator` owns the one `WasabiColorThemeCatalog` per loaded skin; renderers and
views subscribe by identity token and drop their themed bitmaps on a switch. `WasabiPalette` gives
NullPlayer-drawn content (playlist rows, EQ sliders) colours from the skin's own resources, resolved
through the renderer's *own* resolver so gamma matches.

**The surfaces we draw are palette-themed, never classic-skinned.** `WinampModernSurfaceStyle` widens
a `WasabiPalette` into a whole chrome for the AppKit views NullPlayer supplies — the embedded library
(`PlexBrowserView` in embedded mode) and the playlist / EQ / library **fallback windows**. Before
Phase 16 all of those painted with `SkinRenderer` sprites, the 5×6 bitmap font, and
`skin.playlistColors` from whatever `.wsz` was selected: a foreign UI coloured by a skin the user is
not looking at.

- Chrome roles (`barBackground`, `border`, `divider`, `dimText`, `pressedFill`) are **blends of the
  roles the skin declared**, never fixed greys — real skins declare three of the seven, and the blend
  is what makes the chrome move the right way on a light skin as well as a dark one.
- `font(scale:)` solves for a monospaced point size whose advance is exactly
  `SkinElements.TextFont.charWidth * scale`, and `attributes` adds a `.kern` correction for the
  remainder. **This is load-bearing**: the views lay themselves out as
  `text.count * charWidth * scale` in ~77 places in the browser alone, so a font that measured
  differently would leave every one of those boxes wrong. `drawText` counter-flips about the cell.
- Chrome is redrawn at the **same metrics** as the classic version — same title-bar height, same 12px
  borders, same button boxes the hit tests already own — so only pixels change, never geometry.
- Reaching it: embedded surfaces are pushed a style through the existing
  `WinampModernLibrarySurface.applyPalette` seam; fallback windows read
  `WindowManager.winampModernSurfaceStyle`, which is **nil in every other mode** (and nil until a
  skin loads), so classic mode runs the untouched classic path. A theme switch posts
  `.winampModernThemeDidChange`; the style is re-derived per draw, so a repaint is the whole job.

Hosted AppKit surfaces (`WinampModernLibrarySurface`) are **reconciled from `layout()`, never from
`draw`** — creating and adding a subview inside a draw cycle is a re-entrant hierarchy mutation. A
script mutating the graph or switching layout sets `needsLayout`, because a script can create or
reveal a holder. Each surface is told `prepareForUITeardown()` *before* its view leaves the hierarchy,
so its in-flight tasks and timers do not outlive it.

### Teardown order

Synchronous and idempotent — every async producer must stop before its resources are released:

1. `WinampModernMainView.teardown()` — interaction state, then scripts + renderer
2. `WinampModernScriptRuntime.teardown()` — graph/popup callbacks, timers, interpreter, vis consumer
3. `WasabiSceneRenderer.teardown()` — decoded resource caches
4. `WinampModernLoadedSkin.teardown()` — retained graph + VFS-owned state

Auxiliary container views tear down **before** the main view; the graph goes last. Hosted surfaces
(the embedded library) are told `prepareForUITeardown()` before step 1 removes their view, and the
component bridge releases its own reference behind them.
`WinampModernMainWindowController.prepareForUITeardown()` drives this before a mode controller is
released.

## Mode integration

`PlayerUIMode` has four cases across three controller families
(`PlayerUIControllerFamily`): `classic`, `nullPlayerModern` (Modern + Metal), and `winampModern`.

> **Gotcha:** `WindowManager.isModernUIEnabled` means `controllerFamily == .nullPlayerModern`
> **only**. It is a documented shim, and it is `false` in Winamp Modern mode — the ~15 geometry call
> sites behind it deliberately route Winamp Modern down the classic path. Do not "fix" it to include
> the new family.

**UI Size** works in this mode through the shared `UIScaleLevel`: the scene stays on the skin's own
pixel grid and `WinampModernMainView` applies the scale once at the drawing boundary and undoes it
once at the input boundary, so no graph object, renderer path, or script ever sees it.
`applyDoubleSize` takes this mode's window size from the skin's layout rather than
`Skin.mainWindowSize`, and leaves `minSize` alone so a resizable `.wal` stays resizable.

Winamp Modern uses the **classic 10-band EQ** (`usesModernEQLayout == false`) and has no
`modernSkinFamily`. Since Phase 13 the playlist, EQ, and library are **skin-owned surfaces** routed by
`WinampModernSurfaceCoordinator`; the classic controllers are the explicit last resort, not the
default. Mode switching is live, and `AudioEngine` is owned by `WindowManager`, so playback survives a
switch untouched.

A frame restored from saved state is clamped to the active layout's `minimum_*`/`maximum_*` with the
saved top-left preserved (`MainWindowProviding.clampRestoredFrame`, a no-op for the fixed-size
families). Restoring verbatim is what brought a 500×500 cPro-Bento window back as 376×182.

Persistence writes `false` to the legacy `modernUIEnabled` bool so older clients degrade to classic
rather than reading a corrupt value.

