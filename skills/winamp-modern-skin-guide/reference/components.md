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

#### `default_visible="1"` — the windows a skin opens with itself

An auxiliary container that declares it is on screen the moment the skin loads, in Winamp and here
(Phase 40). The corpus: **10 containers in 8 of the 17 skins** — Defix's `Config` *and* its `pledit`,
the stock Winamp Modern skin's `Pledit` + `winamp.albumart`, Ujola Cat's `PLEdit` + `ujolaCat`, ZDL's
`EQ` + `thinger`, Overdrive_2's `Pledit`, Love is War Miku's `notifier`, Rika's and T800's
`Warp Browser`. Four parts:

- **The attribute** is decoded in `WinampModernContainerTopology` with everything else a container
  declares (`opensByDefault`; the main player is always true whatever it says), and applied by the
  controller right after `scriptsDidStart()` — so a window that opens at load is told `onSetVisible`
  with its geometry already dispatched. It opens **non-activating**: the player is what should be in
  front after a load, not the configurator behind it.
- **It is a default, not a command.** What the user last decided about that window wins over it, so a
  settings window they closed does not come back at every launch — which is why this sat unimplemented
  for eight phases. The decision lives in the **skin's own namespaced configuration**
  (`WinampModernConfiguration`, section `@nullplayer.windows`), so two skins that both ship a `Config`
  window do not share one answer, and "never said" is distinguishable from "said no"
  (`opensAtLoad(opensByDefault:remembered:)`). Only *explicit* routes record — a menu item, a skin
  button, a close box. A script's own `show()`/`hide()` does not: a skin opening one of its windows
  from a timer is describing this run, not the next one.
- **`default_x` / `default_y`** place it. Winamp reads them as desktop coordinates around a player at
  the origin; the player here is wherever the user left it, so they are applied **relative to the
  player's own** `default_x`/`default_y`, in skin pixels, y flipped, scaled by UI Size
  (`arrangedOrigin`). Winamp Modern's playlist at `default_x="354"` lands beside the player and its
  album art under that. A container that declares neither is stacked under whatever is already on
  screen, as every auxiliary window was before.
- **One suppression**, recorded in the skin's diagnostics rather than silently dropped
  (`defaultVisibilitySuppression`), and neither of them blocks the window — the menu, a skin button and
  the skin's own script still open it:
  - **`hostManagedTransient`** — a `notifier` or `tooltip` container. Matched on the id, which is the
    only name Wasabi gives these (there is no notifier GUID) — scoped to auto-opening only, so a
    mis-match costs nothing visible. The notifier *is* host-driven: `showNotifier(for:)` opens it on
    each track change (see [Notifier — track-change toast](#notifier--track-change-toast) below).

  Browser-only containers are not suppressed: their real, policy-gated WebKit surface opens when
  `default_visible="1"`, subject to the same remembered user choice.

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
- **`hold="none"` is not an unknown component — it is "this holder holds nothing", and it must draw
  nothing.** A holder naming a GUID we do not recognize falls through to `.other`, which fills its
  whole rect with the palette's content colour so an unrecognized surface is visibly inert rather
  than invisibly absent. Reading `none` that way put an opaque slab over the artwork underneath: Big
  Bento Modern's `wdh.waveseeker` — the box it reserves for WACUP's integrated Waveform Seeker, a
  plugin we do not have — sits directly on the seek bar, which is why the seek bar rendered as a
  solid black bar (BB12). `componentReference` therefore answers nil for `none`, on all three holder
  forms, case-insensitively, and **without falling through to the id heuristic** — that fallback is
  for a holder that names nothing at all, not for one that explicitly names nothing. The narrow
  reading matters: the same element also carries `autoopen="0"`, which would have explained the
  symptom equally well and is on real, wanted holders elsewhere in the corpus (micro's playlist,
  Defix's SUI), so honouring *that* would have blanked surfaces that work today.
- `WinampModernContainerTopology.analyze` classifies each container: a real visible window or an
  SUI-collapsed stub (1×1 / `window-overrides` invisible), its `kind` (from its own `component=`
  GUID), its layout's `minimumSize`/`maximumSize`, and whether NullPlayer synthesized it.
- `WinampModernComponentHost` is the sandboxed seam supplying app-side content per kind;
  `WinampModernComponentBridge` implements it over `AudioEngine` and owns the embedded library.
- The embedded playlist carries **two** selections since Phase 39: `selectedIndex`, the *anchor* a
  click and the Delete key mean, and `selectedRows`, the set `PE_SEL`'s Select All / Invert and
  `PE_REM`'s Crop work on (`playlistSetSelection` / `playlistRemoveRows`). A click collapses both to
  one row. Both new calls have protocol defaults over the single-row ones, so a host without a
  selection model of its own — every test fake — still conforms.
- **The selection bar follows playback.** On every track change the controller's `updateTrackInfo`
  calls `playlistFollowCurrentTrack()` and then `revealPlaylistRow` on every container view (the
  playlist holder usually lives in an auxiliary `pledit` window, not the player), matching what the
  classic and modern playlist views do from `.audioTrackDidChange`. Without it the bar sat on the row
  the user last clicked while playback moved on — and in skins whose palette names no
  `pledit.text.current` (mmd3) the bar is the *only* now-playing marker, so an advance looked like
  nothing happened at all. Relatedly, `drawPlaylistComponent` only lets `palette.currentText` win over
  a selected row's `selectionText` when the skin actually named a current colour; `currentText` falls
  back to `listText`, which is exactly the colour the selection background is drawn to avoid.

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

#### Which layout a container opens in

`WasabiSceneRenderer.primaryLayout(of:)` — the layout named `normal`, else the container's **first
declared** one, which is Winamp's rule. `WinampModernContainerTopology.normalLayout` picks the same
way, so the geometry the topology reports and the scene the renderer draws are the same window.

It used to be `normal` *or* the sole layout when a container declared exactly one, and anything else
threw out of the initializer. `setupAuxiliaryContainers` answered that with a bare `continue`, and
the main window's own renderer answered it with the load-failure placeholder — so a skin whose player
offers several named shapes did not load **at all**. Six containers in the 31-skin corpus were
affected (B26, 2026-08-21): BLAKK's `main` (`boombox`/`remote`/`stick`) and Ebonite_2_1's `main`
(six, starting `full`) — both whole skins — LOBE's `Color Themes` (six `about*` pages carrying its
43-theme picker), and the wasabi standard `Component` shell in Anexa, Sony_Walkman and boom.

Two rules came out of it:

- a container that still cannot be opened records a `WalDiagnostic` (warning,
  `container '<id>' has no window and is unreachable`) instead of vanishing;
- `isListedInWindowMenu` rejects a `name` beginning with `:` — a Wasabi string-table reference we do
  not resolve. The standard `Component` shell is `name=":componenttitle"`, and making it openable
  otherwise puts an empty frame under that name in three skins' **Skin Windows** menu.

#### Revealing an embedded surface: the script gets the last word, not the first

`revealEmbeddedSurface` sends the skin `System.onGetCancelComponent(guid, true)` and falls back to
Wasabi's `windowholder autoopen="1"` — walking up from the holder and un-hiding its ancestors — when
the scene still has no visible holder of that kind (B23, cPro-Bento, whose script *has* handlers but
declines to switch at startup).

**That fallback test is synchronous, and a script is not.** Big Bento Modern is the case that showed
it (B38.2). Its component pages are siblings — `sui.components` holds seven `<group … visible="0"/>`,
one per tab — and at launch a restored session revealed both a playlist and a library. All four
reveals legitimately fell through to the fallback, because at the instant each ran the tab genuinely
was not open; we forced the library page visible; and roughly **0.6 s later** `suicore.maki` opened
the playlist tab it had decided on all along, with no idea a second page was open. Two lists, one
area, drawn on top of each other.

Two rules, and the second is the one that matters:

- `openHolders` reverts what **it** previously forced when it opens a different page. Never anything
  the script set — that path returns early — and a shared ancestor survives because it is in the new
  chain's set.
- Exclusivity is re-checked on **every layout pass**, and always resolves the same way: **the page we
  forced yields to the page the skin opened.** A reveal-time check cannot see a page that does not
  exist yet, so there is no instant at which checking once is sufficient.

Two holders count as competing pages only when their paths diverge at **siblings that each carry an
explicit `visible` attribute**. That is the shape of a tab page and not of ordinary structure: Big
Bento's `wdh.pl` and `wdh.ml` are siblings under `sui.components` and both declare `visible="0"`,
while the top bar's own visualization holder diverges from them at `player.mainframe.big`, which
declares no `visible` at all — so the meter in the header is left alone while the tab switches.

`WINAMP_MODERN_DEBUG_HOLDERS=1` is how all of this was read, and it is the only way: none of it
reproduces headlessly, because the harness sets no component host. It now also logs after each
reveal, not only after a click. The line that named the bug was a holder list containing
`library#wdh.ml2` **and** `playlist#wdh.playlist` at once; the fix is confirmed by the same line
containing exactly one content page.

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
- **The `autoopen` fallback runs only when the skin did not do it itself** (B23). A skin can carry
  one component in several places — cPro-Bento holds video in its tab, its mini view *and* its
  drawer, three holders all declaring `autoopen="1"` — so forcing every one of them open after the
  script had already switched tabs put two more copies of the surface on screen. `revealEmbeddedSurface`
  now asks the scene (`hasVisibleHolder`) between the two halves.
- **`.video` can be embedded, `.visualization` cannot** (B23). B20 made video never-embedded to stop
  Winamp Modern's *invisible* in-player holder winning over its real video window; the rule is now
  conditional on the skin declaring a **visible** video container, so an SUI skin whose only video
  surface is a tab (cPro-Bento) hosts the picture there. `hostVideoOutput()` reveals the tab, lays
  out, attaches — and places the picture **twice**, because revealing a tab sets off the skin's own
  `onResize` cascade a turn later. `VID_1X`/`VID_2X` stay inert for an embedded box: sizing it to the
  stream would resize the whole player around a tab. Switching away from the tab mid-film unparks the
  picture into NullPlayer's own window, which is `detachVideoOutput`'s existing rule.
- **Two holders of one kind on screen: the biggest box wins.** `hostedVideoSurface` used to answer
  with a dictionary's first value, so the picture landed in a different box between runs of the same
  build.
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

#### NullPlayer-owned hosted windows are lazy

Spectrum, Cava, Flow, PeppyMeter, Audio Analysis, Waveform, and ProjectM use a second, typed window catalog.
They are application features, not Winamp component GUIDs, so they must never be added to
`WinampModernComponentRegistry` or to load-time component synthesis.

- `WinampModernHostedWindowRegistry` is the only production table for identity, title, geometry,
  hard minimum/maximum size, center-stack policy, and content construction. A new application-owned
  window needs one registry entry plus a `WinampModernHostedSurface` conformance on its existing
  content view; it does not need a feature branch in the synthesizer, main controller, or materializer.
- Loading a skin records only a `skinFrame` or `classicFallback` route for each id. It creates no
  graph objects, renderers, adapters, or `NSWindow`s. This is deliberately different from eager
  skin-authored auxiliary containers, whose scripts may address them during `onScriptLoaded`.
- The first show/toggle/restore request asks `WinampModernHostedWindowMaterializer` to instantiate
  one trusted subtree in the existing runtime. The container is marked
  `nullplayer_synthesized="1"`, has the synthetic host source path, and holds exactly one registered
  `guid:np.<id>` token. All three provenance checks are required; the same token written by a skin is
  unknown and inert.
- Close hides and retains the instance. Reopen reuses it; UI Size changes resize only materialized
  instances; skin/mode teardown destroys them once. If request-time construction fails, the partial
  graph/window is rolled back and the existing standalone controller opens immediately.
- The hosted surface is chromeless: the Wasabi standard frame owns drag, close, resize, keyboard,
  and artwork. The same existing feature view draws its shared `.wal`-palette fallback chrome only
  when it remains inside the standalone controller.
- Window size is per registry entry and then clamped by the selected skin frame's hard resize limits.
  Center-stack sizing is a preference inside those bounds, not a replacement geometry; PeppyMeter
  therefore retains its larger authored height instead of collapsing to the spectrum-family size.

Materialized hosted windows join `WindowManager`'s managed-window graph for snapping, docking,
always-on-top, ordering, Compact Mode, state capture, and orphan checks. Unopened route descriptors
never enter that graph and have zero native-window footprint.

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

- **Every palette role is normalised to `deviceRGB` in `WasabiPalette.init`, and no colour path here
  may vend `.white`/`.black`.** Those AppKit singletons are *greyscale* colours, and
  `redComponent`/`greenComponent`/`blueComponent` on a non-RGB colour raises an
  `NSException` — from inside `drawRect`, which means the process aborts with no Swift error to
  catch. Consumers read the channels directly (the library's star rating dims `accentTextColor`,
  `WinampModernSurfaceStyle` blends roles), so the conversion happens once at the palette instead of
  at ~7 call sites. `WasabiRenderer.unparseableColor` is the RGB white a malformed or missing colour
  resource resolves to; that path is exactly how the ART-button crash reached a greyscale colour.
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
reveal a holder.

**Hosted surfaces must clip to their holder frame** (`layer.masksToBounds = true`). Without this,
NSView's default non-clipping layer lets the browser's tab headers ("+ADD", "History", etc.) bleed
through the titlebar on skins like cPro-Bento. The clip is applied once at construction in
`WinampModernLibrarySurfaceView`.

**Unmounting is not teardown, and confusing the two is a bug the user sees.** The component bridge
owns **one surface of each kind per skin** and re-serves that same instance whenever a holder for it
reappears — that is what lets a browser survive a layout switch with its servers, tabs and history
intact. So a holder leaving the scene is answered with `unmountFromHolder()` (leave the view
hierarchy, stay reusable), and `prepareForUITeardown()` is reserved for the scene's own teardown and
the bridge's `release*Surface()`, where it is **terminal**: it latches `isTornDown`.

Routing holder removal to the terminal path is B24: the second visit to a tab re-added an
already-torn-down surface, and the third hit the latch, returned early, and never removed the view —
cPro-Bento's library browser then sat on top of every other tab (Media Library → Playlist → Media
Library → Playlist). The video surface never had the defect because B20 had already made *its*
teardown non-terminal; the visualization surface did, and is now unmounted by stopping its engine and
keeping it, with `resumeRendering()` starting it again on the way back in.

#### Repaint routes are per-window, and scripts are not

`graphDidMutate`, `repaintRequested` and `objectRepaintRequested` are **single-owner** callbacks on the
script runtime, and the main window owns them — correctly, since the theme, action, mouse and EQ
callbacks beside them do admit only one owner.

Repainting does not. A MAKI `Timer` belongs to the **runtime**, so `onTimer` fires for a script in any
container; the script mutates its own objects; and if that container is an auxiliary window, nothing
used to tell it to redraw. Two Defix symptoms that looked unrelated were this one gap: its playlist box
writes `Items:`/`Time:` from `onTimer`, and its speaker cones step `SpeakerVis` the same way. Both
updated the graph and neither ever reached a screen.

Auxiliary views therefore register a **container-scoped repaint sink**:

```swift
scripts.addAuxiliaryRepaintSink(owner: self) { object in … }   // and remove it on teardown
```

The scoping is the view's job, and it matters: a warped layer on the main window fires the
object-scoped path 30 times a second, and every other window must ignore it. `WinampModernMainView`
walks the retained graph's parent chain to decide whether it owns the object — which also keeps
"not laid out in my scene yet" (repaint) distinct from "belongs to another window" (do not).

**When adding a window**: if it renders the shared graph but does not drive it, it needs this sink.
A window with no repaint route shows its first frame and then silently freezes.

### Teardown order

Synchronous and idempotent — every async producer must stop before its resources are released:

1. `WinampModernMainView.teardown()` — interaction state, then scripts + renderer
2. `WinampModernScriptRuntime.teardown()` — graph/popup callbacks, timers, interpreter, vis consumer
3. `WasabiSceneRenderer.teardown()` — decoded resource caches
4. `WinampModernLoadedSkin.teardown()` — retained graph + VFS-owned state

Auxiliary container views tear down **before** the main view; the graph goes last. Hosted surfaces
(the embedded library) are told `prepareForUITeardown()` before step 1 removes their view, and the
component bridge releases its own reference behind them — which is also what destroys a surface the
scene had merely *unmounted*, since the scene no longer holds one of those at all.
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


## The video surface — the picture goes in a **child window**, not a subview (B20)

**15 of the 33 measured `.wal` skins declare a `<container>` for the video component** — chrome, a
`ledstatusbar`, the `VID_*` buttons, and a `<component param="{F0816D7B-…}">` holder — and until B20
every one of them was decoration over an empty box: playing a video opened NullPlayer's own window
somewhere else on screen while the skin's stayed shut.

### Why it is not shaped like `.library`

The obvious shape is the library seam's: move the host's view into the skin's holder. **It does not
survive contact with the video engine.** VLCKit installs its own output view under the player's host
view and sizes *that view's ancestors*, so the skin window's content view ran away at +46pt per
layout pass — measured from 372 to 14,219 in 80ms — and the picture did not appear at all until
something else forced a relayout.

So the surface holds only a **black box the skin lays out**, and
`VideoPlayerWindowController` parks its **own window** over that box with `addChildWindow`. AppKit
gives a child window its own layout tree, so nothing the decoder does can reach the skin's, while the
child follows the parent's moves, hides and closes for free. It is also what answers the lifetime
question: the video window is mode-independent and preserved across `reloadUI`, so parking rather
than owning means a layout switch, a skin switch or a mode switch *unparks* it — still playing —
instead of tearing the player down with the skin.

### The trap that cost the most: a window minimum derived from Auto Layout

`window.setFrame` **silently refuses** any size below the minimum AppKit derives from required
constraints in the window's content, and there is no error — the window simply comes back a different
size. `VideoControlBarView` lays its controls out with a required chain
(`10+30+5+30+5+30+5+30+10+50` leading, `10+30+5+30+5+30+10+50+10` trailing) that sums to exactly
**395pt**, so every parked frame narrower than that was quietly widened and the picture ran out
through the skin's own chrome. **A hidden view's constraints are still live** — `isHidden` does not
help; the bar has to leave the view hierarchy.

Two rules follow, and both are load-bearing:

- **`showsControlBar` adds and removes the bar from its superview**, it does not hide it.
- **The surface gates the bar on the box**: it goes in only when the holder asked for it *and* the box
  is at least `controlBarMinimumWidth` (the bar's own `fittingSize`, not a number written down
  twice). Ask for the frame again straight after the bar leaves — the refusal happened while the
  minimum was still in force.

When debugging any "the hosted thing is the wrong size" report, **compare the frame asked for against
`window.frame` afterwards**. A DEBUG log in `updateHostedOutputFrame` does exactly that
(`video: box … refused, window took …`); it is the line that ended this defect after three wrong
theories.

### The rest of the shape

- **Routing.** `.video` is a **routed** surface but not a **managed** one
  (`WinampModernSurfaceInventory.routedKinds` vs `managedKinds`). Never synthesized — a skin that
  draws no video window is served by the host's own. Never embedded — Winamp Modern's player also
  declares an invisible in-player `windowholder` for the component, and resolving there would leave
  the skin's real video window empty. So the catalog only ever answers `.declaredContainer` or
  `.classicFallback`.
- **`autoopen` / `autoclose`.** Playing reveals the skin's video window; stopping hides it and
  unparks, so no child window is left hanging off a skin window a mode switch may take away.
- **Casting never resurrects a local window.** Every `play*` entry point returns before reaching the
  video controller when a cast device is active, so the skin path is never entered.
- **Fullscreen** unparks first (a child window cannot go fullscreen), and re-parks **one runloop turn
  after** `windowDidExitFullScreen` — AppKit is still restoring the window's own frame as the
  notification lands, and re-parenting inside that leaves it parked at the fullscreen size.
- **The box carries no autoresizing mask** and reports its own geometry (`setFrameSize`,
  `setFrameOrigin`, `viewDidMoveToWindow`) so the parked window follows whatever moves it. Pushing
  placement from the layout pass alone leaves the picture behind on every path that moves the box
  without one.
- **Drag and resize zones are off while parked.** Both belong to the free-floating window; inside a
  skin's box they slide or stretch the picture out of the hole it is filling.
- **`VID_1X` / `VID_2X`** were inert before this (nothing read `presentationSize`). They size the
  *skin's* window so the box is the stream's own pixel size times N, clamped to the visible screen as
  well as the layout's range — Winamp's 1x on a 1080p film is a ~1940pt window, which is faithful but
  must not run off the display.
- **A declared container with no holder** (Hoop_Life_WA3, Media_Whore) routes but has no box;
  `hostVideoOutput()` answers false and the host's own window takes it. That is the correct outcome,
  not a gap.

### The corpus, measured

`cmdbar=` is the holder's `noshowcmdbar=` decoded (`WinampModernVideoHolder.showsCommandBar`).

| Skin | Box (skin px) | cmdbar |
|---|---|---|
| hatsune_miku_5 | 429×340 | 0 |
| Ujola Cat | 390×91 | 0 |
| mmd3 | 375×190 | **1** |
| winampmodern566 | 342×232 | 0 |
| multipass | 332×113 | 0 |
| corneramp_redux | 310×164 | 0 |
| Styx | 284×59 | 0 |
| Itemskin | 277×71 | 0 |
| Anaheim_Player_01 | 240×120 | 0 |
| Love is War Miku | 240×184 | 0 |
| Love Is War Miku V2 | 240×190 | 0 |
| Ebonite_2_1 | 227×172 | 0 |
| BLAKK | 192×125 | **1** |
| Hoop_Life_WA3, Media_Whore | declared, **no holder** | — |

Only mmd3 and BLAKK ask for the command bar, and both boxes are under 395pt, so **no skin in the
corpus actually gets one** — the gate decides every measured case in favour of the picture fitting
its box.

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

## `<browser>` — embedded WebKit browser

A `<browser>` element in a `.wal` skin hosts a real `WKWebView`. It is a completely separate
lifecycle from the component holder system — `<browser>` is NOT added to `isHolderElement` (doing so
breaks fills and hit tests). Each instance has an ephemeral website data store, so cookies, caches,
and local storage do not persist across a skin session.

The allowed navigation surface is deliberately narrow: HTTP and HTTPS are accepted; skin-local HTML,
CSS, script, image and font resources are served from `WalVirtualFileSystem` through the private
`wal-skin-resource:` scheme; `file:`, `javascript:`, `data:`, downloads, popup windows, and
application URL schemes are rejected. An allowed popup navigation is kept inside the same browser
surface. The browser exposes no JavaScript-to-native message bridge. `command-L` and
the WebKit context menu focus a host-owned search/address field that remains visible above the page;
non-address text searches DuckDuckGo.
The user may explicitly open the current HTTP(S) page in the default browser from that menu.

Initial navigation accepts Wasabi's two markup forms: a non-empty `url=` wins, then `home=` is the
fallback used by ClassicPro's `<Winamp:Browser>`. With neither, the surface opens NullPlayer's local
search/start page. This selection happens before lazy loading, so a hidden or zero-sized browser still
makes no request until it becomes visible. Both provisional and post-commit navigation failures show
the compact *Page unavailable* screen; handling only the former leaves WebKit's default white page
when an old server accepts a connection and then returns no response.

Security policy is centralized and headlessly tested in `WinampModernBrowserTests`: WebKit uses a
nonpersistent data store, media autoplay requires a user gesture, downloads are denied, and camera
and microphone requests are always denied. Only the exact internally-generated
`wal-skin-resource://resource/…` shape is admitted, with each response capped at 16 MiB. A skin cannot
forge that scheme through XML or MAKI; initial addresses accept only HTTP(S), while local paths must
resolve inside the read-only WAL VFS. Host paths, traversal, credentials/ports on the private origin,
and unsafe address-bar schemes are covered by synthetic tests. `System.navigateUrl` and calls on
non-browser objects never reach the surface.

### The typeName trap

The XML element is `<Browser>` in most skins (Defix, Bio-Nid, Itemskin, etc.) but ClassicPro engine
skins (cPro-Bento) use `<Winamp:Browser>`. The object graph stores the typeName as-is from the XML,
so cPro-Bento's browser object has `typeName = "Winamp:Browser"`, not `"Browser"`.
`WasabiSceneRenderer.isBrowserElement()` matches both: `browser` and `winamp:browser`
(case-insensitive). **This was the root cause of six failed attempts** — every approach that checked
only for `typeName == "browser"` silently missed cPro-Bento's browser element, and cPro-Bento was
the primary test skin.

### Why `layoutNodes()`, not `sceneNodes()`

Browser elements are typically inside a tab group that starts `visible="0"` (cPro-Bento's
`centro.browser`, Defix's `wdh.browser`). A MAKI script toggles visibility when the user clicks the
tab button. `sceneNodes()` filters by visibility — so a browser inside a hidden tab never appears in
it until the tab is first shown. If surfaces were only created from `sceneNodes()`, the first tab
switch would find no surface, and the layout would run before any surface existed.

`browserNodes()` uses `layoutNodes()` (which includes hidden elements) to discover ALL browser
elements eagerly and create surfaces for all of them at first layout. Each surface's
`view.isHidden` tracks whether the element is currently visible in `sceneNodes()`, so the surface
is ready the moment the tab becomes visible.

### Independent surfaces and lazy loading

Each `<browser>` gets its own **non-cached** `WinampModernBrowserSurface` via
`componentHost.makeBrowserSurface()`. This is deliberate:

- Browser history and page state belong to the individual browser object, not to the Media Library
  component or another browser tab.
- The view layer owns the surfaces in a
  `browserSurfaces: [WasabiObjectID: WinampModernBrowserSurface]` dictionary and tears them down with
  the skin runtime.
- Browser objects inside hidden tab groups are discovered eagerly so they can receive early MAKI
  navigation, but no page is loaded until the object is visible with a nonzero frame.
- `<browser>.navigateUrl(url)` routes by `WasabiObjectID` to that surface. A request during
  `onScriptLoaded` is buffered until the first layout. The global `System.navigateUrl` methods remain
  denied.

### The four routes a skin reaches the web by (B40)

A skin's web-facing buttons do **not** all go through the `<browser>` object, and reading them as one
thing is what left "some buttons do nothing" open for a phase. There are four routes and each needed
its own answer:

| Route | What it means | Where it lands |
|---|---|---|
| `<browser>.navigateUrl(url)` | that object's own surface | `browserNavigationRequested` → `WinampModernMainView.navigateBrowser` |
| `System.navigateUrl(url)` | **the user's default browser** — Winamp's meaning, not a synonym for the next row | policy → confirmation sheet → `NSWorkspace` |
| `System.navigateUrlBrowser(url)` | the *player's* browser | the scene's `<browser>`, visible one preferred |
| `sendAction("browser_navigate"/"browser_search", …)` | a skin's own reader, addressed as an action | the skin's script, and the host only if nothing answered |

Three traps live in that table, all of them measured on Big Bento Modern:

- **A scheme-less address is a web address, not a skin-local path.** Winamp readers write
  `www.google.com/search?q=<terms>` with no scheme and hand it to `<browser>.navigateUrl`. Everything
  after the scheme check in `destination(for:)` treats an address as a path inside the WAL VFS, where
  a hostname can only ever be missing — so the page came back *"The skin-local page could not be
  found"* and the search never reached WebKit. A host-shaped head (dotted labels, plausible TLD, not
  a resource extension — `looksLikeWebAddress`) is repaired to HTTPS through
  `WinampModernWebNavigationPolicy`; `reader_providers.xml` and `backgrounds/start.html` still
  resolve locally.
- **`browser_search` carries *terms*; `browser_navigate` carries a *URL*.** Bento's lyrics button
  sends `urlEncode(artist) + " " + urlEncode(title) + " lyrics"`, while its YouTube, album-cover and
  stream buttons send a complete `https://…`. Reading both as addresses turns a search into
  `https://<terms>`. Terms are **decoded once** before being re-encoded (the skin encodes each term
  itself, so encoding again searches for `%2520`), and the engine comes from the skin's own
  `Default Search Engine: Google` / `Bing` registration, DuckDuckGo when it registers neither.
- **A skin with a reader answers those two actions itself**, building the URL from its own engine
  setting and navigating its `<browser>`. The host route is therefore a **fallback**, taken only when
  no script handled the action — otherwise the same surface is loaded twice, the second time with a
  URL the skin did not choose.

The **external** route is the only place a `.wal` skin reaches `NSWorkspace`, and it is gated: the
address is untrusted markup, so the first request raises a sheet (Open / Always Allow / Cancel)
naming the URL, "always" is stored per skin in its own namespaced configuration, and one question is
outstanding at a time so a script on a timer cannot stack alerts. Never `runModal()` — a modal loop a
skin can enter at will is a hang the user cannot escape.

**Whose setting decides internal vs external?** The skin's, and it does not need asking: Bento's Web
Content page offers *Use Default Browser to open links* (its own default, `1`) against *Use internal
Web Reader*, and its scripts read that attribute and call `navigateUrl` on one branch and
`sendAction` on the other. Honouring the setting **is** answering both routes.

One thing the internal route deliberately does not do: it navigates the browser but does not open the
tab the browser sits in. A request for a browser in a closed tab waits in that surface (the same
buffering an early `onScriptLoaded` navigation gets) rather than driving the skin's own tab
bookkeeping from outside.

### The `SC:UpdateSystem` browser

cPro-Bento also has `<browser id="brw">` inside an `SC:UpdateSystem` XUI widget in the main
container. This is Winamp's update-check widget, not a content tab. It creates a browser surface but
does not load while it remains offscreen, hidden, or zero-sized.

### Files

- `WasabiRenderer.swift` — `isBrowserElement()`, `browserNodes()`, `isBrowserVisible()`
- `WinampModernComponents.swift` — `makeBrowserSurface()` protocol method
- `WinampModernComponentBridge.swift` — `makeBrowserSurface()` implementation (non-cached)
- `WinampModernBrowserSurfaceView.swift` — WebKit policy, search/address UI, VFS scheme handler,
  `looksLikeWebAddress` (the scheme-less repair)
- `WinampModernWebNavigation.swift` — the shared address policy, the search-URL builder, the engine
  the skin asked for, and where the external-route consent is stored (B40)
- `WinampModernMainView.swift` — `browserSurfaces`, `reconcileBrowserSurfaces()`,
  `layoutHostedSubviews(browsers:)`, `globalBrowserTarget()`, the `BROWSER_*` actions
- `WinampModernMainWindowController.swift` — `routeWebNavigation`, `navigateInternalBrowser`,
  `openInDefaultBrowser` (the confirmation sheet)
- `WinampModernScriptRuntime.swift` — object-scoped `navigateUrl`, the two global forms, `urlEncode`,
  and the `sendAction` fallback rule

## Notifier — track-change toast

A `.wal` skin's `<container id="notifier">` is a floating toast popup that appears when the track
changes. Winamp Modern, Love is War Miku, and cPro-Bento all ship one. The notifier is **host-driven**:
the host triggers it on track change, sets the text content, and auto-dismisses it — the skin's MAKI
scripts handle fade animation but do not reliably set text (the bytecode's condition check fails in the
`onTimer` handler body, so the timer-based text-setting chain does nothing).

### How it works — end to end

1. **Detection.** During `setupAuxiliaryContainers`, any container whose lowercased id is `"notifier"`
   or starts with `"notifier."` is tagged `isNotifier = true` and `noActivation = true`. Its window
   gets `level = .floating` and `hidesOnDeactivate = false` so the toast appears over other apps and
   survives app-deactivation.

2. **Suppression.** `WinampModernContainerTopology.defaultVisibilitySuppression` returns
   `.hostManagedTransient` for notifier containers, preventing them from auto-opening with the skin.
   Without this, a notifier with `default_visible="1"` would sit on screen reading its XML default
   text ("Nothing / Next track / Nithin Sawhney / Prophesy") for the entire session.

3. **Trigger.** `WinampModernMainWindowController.updateTrackInfo(_:)` calls `showNotifier(for:)` when
   a non-nil track is passed. This is the same path that fires `ontitlechange` to MAKI scripts (via
   `skinView?.updateTrackInfo()`), so the notifier appears on every track change.

4. **Text setting.** `showNotifier` dispatches `onshownotification` to MAKI **first** (so the skin's
   scripts run their setup/animation), then calls `scripts.setNotifierText(title:artist:album:)` to
   **override** the text with the actual track info. The override-after-dispatch order ensures the
   host's values win over anything the MAKI scripts set (or fail to set).

5. **`setNotifierText` internals.** This method on `WinampModernScriptRuntime`:
   - Finds the `<container id="notifier">` root in the object graph.
   - Iterates all layouts (typically `normal` and `desktopalpha`).
   - For each layout, walks the subtree with `setTextInSubtree` to set text on `title`, `artist`,
     `album`, and to clear `plentry`, `nexttrack`, and `endofplayback`.
   - Calls `ensureTextHeight` to fix 0-height text elements (see below).
   - Resizes the layout to 350px wide via `setAttribute("w", "350")`.
   - Fires `layoutResizeRequested` to update the renderer's canvas and window size.
   - Calls `noteGeometryChange()` + `notifyGraphDidMutate()` to invalidate the scene cache and
     trigger a full redraw.

6. **Display.** After text is set, `showNotifier` resets `window.alphaValue = 1`, shows the window
   via `setAuxiliaryWindow(id:, visible: true, activate: false)` (which uses `orderFrontRegardless()`
   for `noActivation` containers — no focus steal), and forces `needsDisplay = true`.

7. **Positioning.** The notifier is placed at the bottom-right of the screen with a 12pt margin
   (in `place()`, gated on `container.isNotifier`), unless the skin specifies `default_x`/`default_y`.

8. **Auto-dismiss.** A 5-second `Timer` hides the notifier. On a new track change, the timer is
   invalidated and restarted — so rapid track changes keep the notifier visible with the latest info.

9. **Fade animation.** MAKI scripts can call `container.setAlpha(n)` to animate the notifier's
   opacity. The `containerAlphaChanged` callback on `WinampModernScriptRuntime` is wired to update
   `window.alphaValue` for any container (notifier included), converting the 0–255 Wasabi alpha to
   0.0–1.0.

### The shadow element problem

Winamp Modern's notifier uses an unusual technique for text shadows: the XML comment says *"I know
this is an unusual way to get text shadow — but it creates a much better effect than the shadow
params."* Each `<text>` element has `shadow="1" shadowcolor="notifier.bright" shadowx="1" shadowy="1"`
attributes. The engine does not render these attributes directly. Instead, during groupdef expansion
the engine synthesizes paired text elements with IDs like `title.shadow`, `artist.shadow` — each
drawn 1px below its sibling, in the shadow colour, to create the shadow effect.

`setTextInSubtree` must therefore match not only the exact id (`"title"`) but also any text element
whose id starts with the target + `"."` (e.g. `"title.shadow"`). It also sets both the `text` and
`default` attributes, because the renderer resolves content as `text ?? default` — leaving `default`
at its XML value ("Nithin Sawhney") causes ghost text when the new `text` value is shorter.

### The zero-height text problem

The notifier groupdef defines `<text id="title" w="0" relatw="1" fontsize="17">` with no `h`
attribute. The geometry resolver defaults missing `h` to 0, and the renderer clips to the frame rect
(`context.clip(to: frame)`), so a 0-height text element is invisible. `ensureTextHeight` walks the
subtree after text is set and gives any 0-height text element a height of `ceil(fontSize * 1.4)`.
This only runs on the notifier's text elements (called from `setNotifierText`), not globally.

### The layout-width problem

The notifier's `<groupdef id="notifier.text">` is placed inside each layout at `x="75" w="-95"
relatw="1"`. With the layout's declared `w="128"`, the text group is only `128 - 95 = 33` px wide —
too narrow for any useful text. `setNotifierText` overrides the layout width to 350 and fires
`layoutResizeRequested` to resize the renderer's canvas, view, and window to match. The background
`<grid>` stretches to fill (`fitparent="1"`) and the `relatw="1"` text group recalculates to
`350 - 95 = 255` px.

### `getPlayItemMetaDataString` — per-field metadata

MAKI scripts use `System.getPlayItemMetaDataString("artist")` etc. to read track metadata.

**The key table is not here — it is `WinampModernHost.playItemMetadata(forKey:)`**, a method on the
protocol extension, and the runtime's `getplayitemmetadatastring` is a one-line delegation to it.
Putting it on the protocol is deliberate: the render harness and every test double then answer
identically to the live host, so a probe run is comparable to the real app. The full table, the units
and the rules for an unanswerable key are in
[compatibility/maki-surface.md](../compatibility/maki-surface.md) → `getPlayItemMetaDataString`; do
not restate it here, and do not add a key to the runtime's switch instead of to the table.

`trackTitle` / `trackArtist` / `trackAlbum` are properties on `WinampModernHost` (defaults `""`,
live implementations on `WinampModernAudioEngineHost` reading `engine.currentTrack`). These were
added alongside the notifier — earlier, both keys incorrectly returned the combined `host.trackInfo`
string. Everything past those three arrives through `host.trackMetadata`
(`WinampModernTrackMetadata`), which the engine host fills from the **library row** for the playing
file, looked up once per track id: a `Track` carries only `genre` of the panel's fields, and a
file-info panel asks for a dozen in a row, so a per-key lookup would take the library's queue a dozen
times per repaint.

### `onshownotification` system event

Registered in `dispatchableEventArity` with arity 0. Dispatched to all MAKI programs via
`.system` target. The skin's notifier script typically uses this to start a fade-in animation
timer. The host dispatches it, but the text is set by the host *after* the dispatch, so the MAKI
handler's text-setting (which doesn't work anyway) is overridden.

### Files

- `WinampModernMainWindowController.swift` — `AuxiliaryContainer.isNotifier`, `noActivation`,
  `showNotifier(for:)`, `notifierDismissTimer`, notifier detection in `setupAuxiliaryContainers`,
  bottom-right positioning in `place()`, `containerAlphaChanged` wiring
- `WinampModernScriptRuntime.swift` — `setNotifierText(title:artist:album:)`,
  `setTextInSubtree(_:id:text:)`, `ensureTextHeight(_:)`, `containerAlphaChanged` callback,
  `onshownotification` in `dispatchableEventArity`, `refresh` no-op
- `WinampModernHost.swift` — `trackArtist`, `trackAlbum` protocol properties and implementations;
  `WinampModernTrackMetadata`, `playItemMetadata(forKey:)` (the key table), `currentTrackRating`,
  and the engine host's `libraryRow(for:)` / `ratingCache` / `currentTrackRatingChanged`
- `TrackRatingService.swift` (`Data/Models/`) — the one owner of the 0–5 star ↔ 0–10 internal ↔
  per-server rating conversions, shared with the Library Browser's ART-mode star row
- `WinampModernContainerTopology.swift` — `.hostManagedTransient` suppression for notifier containers
- `WasabiTextMetrics.swift` — `content(of:host:)` resolves `text ?? default` for text elements
