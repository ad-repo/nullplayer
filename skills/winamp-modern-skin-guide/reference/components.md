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

The value may be Winamp's `@HAVE_LIBRARY@` markup macro rather than a literal `1`. It is resolved
across the expanded document before topology runs, so the Media Library containers in Styx,
Shield_Amp, S7Reflex and Defix enter this same path rather than being parsed as false.

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

#### `visible` on a container answers two questions, and only the declared one classifies it (B16)

`WinampModernContainerTopology` drops a container that is an **SUI-collapsed stub** — a window a skin
neutralises because its surface is embedded elsewhere. The evidence for that used to be the live
`visible` attribute, and it is the wrong attribute: `setVisible` writes the *same* key when a script
calls `hide()`, so a skin that closes its own detachable panel at startup — the ordinary thing to do
with one — erased the window from `windowContainers` for the rest of the session, taking its native
window, its Skin Windows entry and every probe line about it along with it.

The declared value is snapshotted at container creation (`declaredVisibleAttribute`,
`WasabiSkinInitializer`) and is what `isHidden` reads. **No container in the 36-skin corpus declares a
bare `visible=` at all**, so the check only ever fired on a runtime hide; the collapsed-stub case is
carried by the 1×1 size test beside it, which is what `window-overrides.xml` actually writes.

Measured on Defix, the only skin in the corpus that does this: `CORE_SCRIPT.maki` hides `VISCON` — a
406×360 detached-visualizer window with its own `{0000000A}` holder and control bar — from
`onScriptLoaded`. `RENDER-DUMP` prints its container list *after* `scripts.start()`, so for the whole
life of the subsystem that window was never listed, never rendered, and never measured. The app was
unaffected only by luck of ordering: `setupAuxiliaryContainers` runs **before** `scripts.start()`, so
it saw the container while it was still declared-visible. Any reader added after startup would not
have. Third confirmed instance of *a blind instrument reads as a working feature*.

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

#### The component bucket — Winamp's thinger (B34, 2026-08-25)

`<componentbucket>` is Winamp's scrolling strip of *installed component* icons: click one to open that
component, and the `<text display="componentbucket">` beside it names the focused one.
`CB_NEXT`/`CB_PREV` scroll it by an icon and `CB_NEXTPAGE`/`CB_PREVPAGE` by a screenful.

In Winamp the icons come from the **components**, not from the skin — no `.wal` ships thinger artwork
— so for as long as this engine published no icon set, every bucket in the corpus drew an empty box,
its caption stayed blank and all four `CB_*` were `.inert`. `WinampModernComponentBucketCatalog`
publishes one: the five surfaces `routeComponentToggle` can actually open (Playlist Editor,
Equalizer, Media Library, Visualization, Video), drawn as vector glyphs on a rounded plate. Four
things are worth knowing:

- **The strip's state is skin-wide, not per object** (`WasabiSkinRuntime.componentBucket`). One skin
  has one thinger however many layouts draw it — Mini_Me_2 declares ten (one per variant), mmd3 three
  (`normal` plus both shades) — and a `CB_*` button names no bucket, so a per-object scroll position
  would leave the arrow in one shape scrolling something the user cannot see. `WasabiTextMetrics`
  reads the focused title through `componentBucketTextProvider`, installed beside
  `componentTextProvider`, so a caption in a *different* container than its bucket (Styx's drawer,
  ZDL's window) still follows it.
- **The box is Winamp's, the icons are ours.** `WinampModernComponentBucketLayout` reads
  `spacing`, `leftmargin`, `rightmargin` and `vertical` — the two margins run along the **scroll
  axis** in both orientations — and sizes square icons from the cross axis, capped at Winamp's 32px.
  Negative margins are honoured, not clamped (mmd3's shade buckets use `leftmargin="-3"`), and a box
  narrower than one icon plus its margins still shows one: Lobe's is 40×25, and showing nothing there
  is the empty strip again.
- **A bucket has no bitmap**, so it has to be named in *both* `isRenderable` and `isInteractive` or
  it can neither draw nor be clicked — the same pair `<ColorThemes:List>` needed for the same reason.
  The draw dispatch tests `componentbucket` **before** the holder branch: a bucket is a holder
  element by `isHolderElement`, and a skin whose bucket id happened to name a component would
  otherwise draw a playlist in it.
- **Legibility is not the palette's job here.** The plate is `contentBackground` (`selectionBackground`
  for the focused icon) and the glyph comes from `WinampModernSurfaceStyle.legible`, because a bucket
  sits directly on the skin's artwork and `listText` alone can land invisible on it.

**The corpus table this was planned from was wrong, and the lesson generalizes.** It was built by
grepping the shipped XML; a `.wal` draws only what its **include graph** reaches from `skin.xml`.
Three skins ship a thinger they never include — corneramp_redux ("CornerAmp has never had the thinger
but you can add it if you like"), Bio-Nid and Rika — so all three have nothing to fix and nothing to
see, and one of them was the planned live check. Two mechanical traps when re-measuring: `<include
file=…>` paths resolve **relative to the including file** (a closure that only tries the literal
string finds one bucket in thirty-six), and `Lapis_Lazuli.wal` wraps its whole skin in a subfolder,
so it has no top-level `skin.xml` at all. Live buckets in the installed set are seven: mmd3 ×3,
Lobe ×2 (one `vertical="1"`), Overdrive_2, ZDL (own `thinger` container), Styx (in an `alpha="0"`
drawer), S7Reflex (`CB_*PAGE`, vertical) and Nullsoft.Winamp.2000.SP4.Lite, whose full-width
`w="-31" relatw="1"` Thinger window shows the whole five-icon set at once and is the cheapest live
check.

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

#### Where a skin's windows go — the tiling (B56)

**There is no center stack in Winamp Modern.** A `.wal` skin's windows are whatever shape and size the
author chose, so the arrangement is a **tiling generated in one deterministic sweep**
(`WindowManager.WinampModernTiler`), not a placement negotiated per window as each one opens. Columns
run down from the player, each window flush under the last; one that will not fit starts the next
column to the right. Fixed order, no scoring, no iteration. The player is the anchor and never moves —
its frame is restored user state.

Two entry points, one slot sequence: `arrangeWindows()` lays out everything at once, and
`tiledOrigin(for:avoiding:)` gives a window opened later the first slot clear of what is on screen, so
it lands where the arrangement would have put it without disturbing anything already placed.

Four attempts to solve this per-window failed before the sweep, and the reasons are the load-bearing
part of this section:

- **Nothing decided during skin load can be right.** Containers are created and shown *while the skin
  loads*, which is before `WindowManager` reveals the player at its restored frame, before hosted
  windows exist, and before the standard frame's layout pass settles sizes. Measured on Defix: every
  window was placed against a player at `{{0,695},{406,355}}` that finished at `{{0,677},{426,373}}`,
  and against its own size ~5% smaller than it ended up. `WindowManager.mainWindowController` is not
  even assigned yet, so its managed-window graph reports the skin as having no windows at all. The
  sweep therefore runs from the `restoreSettingsState` completion in `AppDelegate` — the first moment
  the inputs exist.
- **Lay the scene out before choosing a slot.** `setAuxiliaryWindow` calls `layoutSubtreeIfNeeded()`
  first. Placing before it picks a correct slot for a size the window is about to stop having, which
  is how two menu-opened windows overlapped by 153×174 under a tiling that cannot overlap.
- **`default_x`/`default_y` are not consulted.** They are Winamp's desktop arrangement for a player at
  the origin, and they do not survive contact: Defix's put `pledit` at x 822–1228 and the media library
  at x 1120–1920, overlapping by 108px before any NullPlayer window is counted. Honouring them "when
  the slot is free" cannot produce a clean layout for such a skin — check whether a skin's authored
  arrangement is self-consistent before building on it.
- **Never clamp a column back onto the screen.** A right-edge clamp can only move a column *left*,
  into the one already there — on a 1600pt region it dragged the media library from x=852 to x=760 and
  straight through its neighbour. When the screen is full, a window hanging off the right is the honest
  answer; non-overlap is the invariant, staying on screen is the preference. `WinampModernWindowTilingTests`
  pins this.
- **The notifier is not part of the arrangement.** A corner toast is host-driven and transient, and
  keeps its corner.

Verify in the running app, never on paper: `WINAMP_MODERN_PLACE_TRACE=1` prints every placement
decision ([harness.md](harness.md)), and the finished layout is read back through the accessibility
API rather than judged by eye. Every claim above is a measurement; four earlier claims that were not
were all wrong.

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
  otherwise puts an empty frame under that name in three skins' **Windows** menu.

The application menu keeps window ownership explicit. NullPlayer-owned surfaces are the first block
of the **Windows** menu. A loaded skin's named, menu-visible containers appear directly in a second
block after a separator, but only after `skinWindows` removes every container routed by the surface
catalog. That makes the blocks non-overlapping: playlist, EQ, library, video, and visualization use
their NullPlayer entries, while genuinely skin-owned windows use the skin block. Skin windows do not
belong in the **Skins** menu, whose loaded-skin section is for themes and skin settings. **Text Size**
is window presentation rather than skin selection, so it sits beside **UI Size** in the Windows menu
while retaining its per-skin value. The `.winampModern` Windows menu also omits NullPlayer's
**Compact Mode** and **Compact Window** entries because `.wal` skins own their compact/shade layouts.

#### Revealing an embedded surface: the script gets the last word, not the first

`revealEmbeddedSurface` sends the skin `System.onGetCancelComponent(guid, true)` and falls back to
Wasabi's `windowholder autoopen="1"` — walking up from the holder and un-hiding its ancestors — when
an explicit request leaves the scene with no visible holder of that kind (B23).

The launch-only library reveal is deliberately different (B25): it sends the event but does **not**
run the `autoopen` fallback. Correct object-typed `NULL` coercion repaired ClassicPro's first tab
activation, so cPro-Bento now opens its own library page and updates `active_tab` with it. Retaining
the old graph writes made the visible page disagree with the skin's bookkeeping. Explicit menu,
script-toggle, and video reveals still allow the reversible fallback because those are requests to
make a surface visible, not startup advice.

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
- **A skin-drawn equalizer is embedded only when the skin declares no equalizer window** (B73).
  Winamp defines no EQ component GUID, so an equalizer is recognised from ordinary sliders carrying
  `EQ_BAND`/`EQ_PREAMP` — cPro in a drawer, mmd3 and stock Winamp Modern in a main-window drawer,
  CornerAmp in its own `eq` container. That match used to be unconditional and beat the declared
  container, which is the same trap `.video` fell into below: impulse draws EQ sliders in its player
  **and** ships a 198×158 `Equalizer` container, so the drawer won the catalog and the window became
  unreachable — routed to as the equalizer surface, and therefore absent from **Skin Windows** too.
  The gate is measured, not assumed: over the 36 installed skins 14 declare an equalizer container
  and 4 embed, and impulse is the only skin in both sets, so this moves that one skin.
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
- Redefined group ids keep expanded-document order here just as they do in the initializer. Each
  reference follows the newest definition at or before its own position (or the first definition for
  a forward reference), so a later group body cannot change an earlier container's surface inventory.
  Template children inherit the outer instance's position; inheritance and `embed_xui` edges resolve
  where their definition was declared.
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
  surface, so the window earns its place. The equalizer's component holder is a stand-in:
  `drawEqualizerComponent` paints eleven tracks with 3px thumbs and nothing else — no on/off, no auto,
  no presets, no band labels, no dB scale.
  **Two routes reach an equalizer and they must agree.** The menu resolves through the catalog
  (`routeWinampModernSurface`), while a skin's own `TOGGLE Eq` button goes through
  `WinampModernMainView.routeComponentToggle`, which checks the *auxiliary containers* before falling
  through to `WindowManager.toggleEqualizer()`. Leaving the container synthesized but unrouted made
  those two disagree: the menu opened the full classic EQ and the skin's button opened the stub. Not
  synthesizing it is what keeps them consistent — both fall past synthesis into the same window.
  Defix and T800 are the measured cases (neither declares a single EQ control); a skin that draws its
  own equalizer is matched as embedded or declared first and never reaches synthesis.
- **What that fall-through opens is a hosted window, not the standalone one** (B55). The equalizer is
  the one *component kind* in the hosted-window registry, and it is there for the reason synthesis
  rejected it: a hosted window mounts the complete `EQView` — bands, preamp, ON/AUTO/PRESETS, the
  curve — inside the skin's own standard frame, where the synthesized `<component guid:eq>` holder
  would have mounted the stub. So the order the equalizer actually resolves in is **embedded →
  declared → hosted window in the skin's frame → NullPlayer's own window**, and only the last of
  those wears the flat palette chrome. Both routes still agree because both end at
  `WindowManager.toggleEqualizer()`, which consults the coordinator, then the materializer, then the
  standalone controller — in that order, from one place.
  `EQView` draws the classic layout in a *hosted* mode: no title bar, no close button and no window
  drag (the frame owns all three), and its `Metrics` spread the ten bands, the preamp and the buttons
  across whatever width the frame gives it, so a client area wider than the 275 the artwork was cut
  for fills rather than letterboxes. Drawing and hit testing read the same `Metrics`, which is the
  only thing keeping a spread slider clickable where it is drawn. The window opens at the player's
  own width on first materialization only — never re-applied, so a window the user has resized stays
  resized.

#### NullPlayer-owned hosted windows are lazy

Spectrum, Cava, Flow, PeppyMeter, Audio Analysis, Waveform, ProjectM — and the fallback equalizer —
use a second, typed window catalog. All but the equalizer are application features rather than Winamp
component GUIDs, so they must never be added to `WinampModernComponentRegistry` or to load-time
component synthesis. The equalizer is the one exception, and only on its *fallback* path: it is still
a component kind, still routed by the surface coordinator first, and reaches this catalog only once
every skin-owned step has declined (B55, above).

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
- The hosted surface is chromeless: the Wasabi standard frame owns close, resize, keyboard, and
  artwork. The same existing feature view draws its shared `.wal`-palette fallback chrome only when
  it remains inside the standalone controller. **It does not own the drag** — see below.
- Window size is per registry entry and then clamped by the selected skin frame's hard resize limits.
  Center-stack sizing is a preference inside those bounds, not a replacement geometry; PeppyMeter
  therefore retains its larger authored height instead of collapsing to the spectrum-family size.
- **A hosted window opens at the player's width, in both directions.** A `.wal` player is whatever
  width the skin drew, and the registry defaults were cut for a 275px classic player, so left alone a
  wide skin opens Cava or the spectrum analyzer as a narrow column beside the player and a narrow one
  (Anaheim and micro are both 240) leaves them jutting out past it. Every hosted window therefore
  opens at the player's width and left edge — the rule the equalizer has followed in every UI mode
  (`WindowManager.winampModernHostedOpeningFrame`, applied by `applyHostedWindowDefaultWidth`). Three
  rules hold it together: it runs on **first materialization only** (a window the user has resized is
  never yanked back), never when a restored frame exists, and the skin frame's own
  `contentMinSize`/`contentMaxSize` clamp the result, so the renderer is never handed a width it
  would bounce back.

- **The width floor is the narrower of the registry minimum and the player itself.** This is what
  makes the paragraph above true rather than merely intended. A hosted window's floor is not really
  the registry `minimumSize`: that number is written into the synthesized frame as `minimum_w`
  (`WasabiSkinInitializer.instantiateHostedWindowAtRuntime`), and from there it becomes *both*
  `window.contentMinSize` and the renderer's own `resize(to:)` clamp. For the spectrum family that
  number is `SkinElements.SpectrumWindow.minSize` — 275, **the same as their default width** — so
  under any skin narrower than 275 the floor sat at the default and the match to a narrower player
  was arithmetically impossible. It looked like a rule that did nothing rather than a floor that
  blocked it. `WinampModernHostedWindowInstantiation.minimumSize` now caps the width floor at the
  skin's own player width, measured live by the materializer in skin pixels: a skin that draws a
  240px player is proof 240 is legible in that skin. Height floors are untouched, and the classic
  `SkinElements` constants are untouched, so Classic and Original keep their 275.
  **When a geometry rule appears to do nothing, check the clamp before the arithmetic.**

#### A skin's chrome can live in a *second* window

Itemskin is the measured case: `PLEdit`, `Video`, `MLibrary` and `AVS_window` are bare boxes holding
one `<component>` each, and the frame the user sees is a separate `dynamic="1"` container
(`cont.clear.pl`, `cont.clear.vd`, …) that the window's own `Wasabi:StandardFrame:*` script keeps laid
exactly over it. Nothing in the hosting model needs to know — both are ordinary containers, and the
skin's script does the pairing. What it needs from the engine is that a window can be moved to another
window's position and that `onMove()` reaches a script at all; both are in
[scripting.md](scripting.md) → *Writing back the position a window just read* (B69).

#### A frame supplies chrome, not a drag surface (B57)

The rule: **a hosted surface passes a press it does not consume to the window drag.** The frame's
title strip is a supplement to that, never a replacement for it.

B55 read "the frame owns the chrome" as "the frame owns the drag" and gave all eight surfaces a
`guard hostedContext == nil else { return }` in `mouseDown`/`mouseDragged`/`mouseUp`. What that
actually left is measurable, and it is small. Standard-frame title strips across the 36 installed
skins: **corneramp_redux 15px, Anexa/Bio-Nid/Rika/T800 18px, cPro-Bento and micro 21px, Core-X5 and
S7Reflex 24px, Nullsoft 2000 SP4 Lite 27px, Defix 42px, Big Bento 45px.** A strip is a *fixed* height,
so it is a smaller share of the window the larger the window gets — on Nullsoft 2000 the hosted
projectM window (550×580) was **6%** draggable, against a body that is a handle everywhere in Classic
and Original. Two skins never reach this path at all (Overdrive_2 and Sony_Walkman have no usable
standard frame, so every hosted window falls back to the standalone one, which drags normally).

`WinampModernHostedWindowDrag` implements it on the app's existing prime-then-move idiom: the press is
primed at `mouseDown` (`windowWillPrimeDragging`) and only becomes a drag once the pointer has
travelled 3pt, which is what keeps a click a click and lets the double-clicks these surfaces carry
still fire. Movement goes through `windowWillMove` so snapping and docking are unchanged, and
`mouseUp` answers whether the press moved the window so a caller can drop the click it would
otherwise have performed on release.

Two things follow for any new hosted surface:

- **The surface gets first refusal.** Sliders, rows and buttons claim their presses before the drag
  is primed; what is left is background, and background moves the window. The equalizer is the case
  that proves it — hosted, its `Metrics` spread the preamp, the ten bands and the buttons across the
  frame's width, and only the margins around them are a handle.
- **A body that is entirely a control has no body drag, and that is correct.** `WaveformView`'s
  hosted `waveformRect` is the whole view, so every press there seeks; its handle is the frame strip,
  exactly as it is that view's own title bar when standalone. Do not invent one.

Not covered by B57, and still open: `WinampModernVisualizationSurfaceView` swallows single clicks the
same way but sits inside the skin's *own* window, so its drag has to route through the parent's skin
hit test rather than a `hostedContext` (B58); the hosted library and video surfaces (B60); and skins
whose own markup leaves the *player* nearly undraggable, which no host-side surface change can reach
(B59).

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

- **An object that leaves the layout resized to nothing, and hears that once.** Hidden subtrees are
  laid out (above), but a *negative* box is dropped along with everything under it, so a pane
  collapsed to zero takes its children out of `resizeTargets` entirely. `dispatchResize` therefore
  compares against the previous target set and dispatches `onResize(x, y, 0, 0)` to whatever has gone,
  which is what Wasabi does — it resizes a window to nothing rather than forgetting about it. Big
  Bento gives the SUI tab area its width back from `player.component.playlist.onResize`; closing the
  side playlist collapses that group's grandparent to 0 wide, so before this the tab area kept a 335px
  hole on every tab (BB30).

Each target hears its **own** parent-relative `(x, y, w, h)`, and only if its own box actually moved.
A UI Size change dispatches nothing: it moves the drawing boundary, not the skin's canvas.

#### A `<layout>` is a window, in four places

Winamp treats a container's layout as the window itself, and a skin says it either way. Each of these
was a separate defect on Big Bento's search popup (BB31), and they only make sense together:

| A script does | Answered by |
|---|---|
| `layout.show()` / `hide()` | its **container's** window (`requestWindow` walks up) |
| `layout.setXmlParam("x"/"y"/"w"/"h")` | the window's frame — `resize()` already did this, one-at-a-time writes now do too |
| `layout.getLeft()` / `getTop()` | the desktop position it was given, not 0 (a layout resolves at its own canvas origin, and skins read these straight back into `resize(getLeft(), getTop(), …)`) |
| `layout.isVisible()` | the **window**, not the graph attribute — the host can close a window (an `autoclose` popup) without the attribute moving |

`autoclose="1"` on a container is a transient popup: it ships no titlebar, no close button and no menu
entry, because being dismissed *is* how it closes. Dismiss it on the next **click elsewhere**, not on
`windowDidResignKey` — an `ontop noactivation` window's key state flickers as it is ordered in, and
closing on resign shuts the popup in the same turn that opened it.

#### The two host-drawn controls: `<edit>` and `<list>`

Winamp fills both with native child windows, so the skin draws the box and nothing else — the content
is the host's, exactly as the playlist panel is.

- **`<edit>`**: the view owns the focused one (click, or the skin's `setFocus()`), types into it, and
  sends `onEnter` / `onAbort` / `onEditUpdate`. Printable keys are **consumed**, or a letter typed
  into a search box also fires a skin accelerator. An edit that declares no `color=` draws in
  `wasabi.list.text`, not white — Winamp's edit text is the list colour, which the skins say in their
  own comments.
- **`<list>`**: rows live on the object (`WasabiGuiList`) so the renderer draws what the script just
  wrote. `deleteAllItems` / `addItem` / `getNumItems` / `getItemLabel(item, column)` /
  `getFirstItemSelected` / `getNextItemSelected(after)` / `scrollToItem`, plus wheel scrolling, click
  to select and `onDoubleClick(item)` — one argument, the row.
- **Row height is the em plus 3px of leading, floored** — *not* the `fontsize` cell, which is a GDI
  height with a smaller em inside it. A skin sizes its window from its own expectation of this
  number, so getting it wrong crops the last row of every result.

#### How large NullPlayer draws its own text: Text Size

The embedded playlist and the embedded Media Library are the **host's** surfaces. A
`<windowholder hold="guid:{45F3F7C1-…}">` is filled by the player, so there is no `fontsize` on it to
read, and in Winamp the playlist font is a *Winamp preference* rather than something the skin states.
The size has to be decided by us, and `WinampModernTextScale` is where.

**One control drives both surfaces**, so they cannot drift apart — `UI → Winamp Modern → Text Size`,
stored **per skin** (`WinampModernSkinState`, section `@nullplayer.text`, key `size`, raw percent with
`0` meaning Auto). The library keeps every internal proportion it has: the setting moves the single
`contentScale` that `itemHeight`, the column header height, `bitmapTextScale` and `contentFont` are
all derived from.

```
auto cell (px) = clamp(canvasHeight / 48, 11, 18)
explicit cell  = 11 * percent / 100      // 100…200%, and an explicit choice is NOT capped at 18
content scale  = cell / 11               // what the library multiplies its own scale by
```

**Auto is keyed on the window's size, and the first attempt keyed it on fonts.** That earlier rule
(`b2980d3a`) took the median `fontsize` declared near the holder, and it cannot separate the two skins
it has to: Big Bento Modern's playlist pane declares 22 and wants the large rows, Defix Hi-END 200's
declares 19/20 and does not. Window size separates them cleanly.

| Skin | Window | Auto cell | |
|---|---|---|---|
| Big Bento Modern (all four) | 1536×878 | 878/48 → **18px** (the cap) | large rows, as intended |
| Defix Hi-END 200 `pledit` | 406×355 | 355/48 → clamps to **11px** | the Wasabi default |
| Defix `SUI` (library) | 800×600 | 600/48 → **12.5px** | mild, coherent with its window |

Two details that are load-bearing:

- **It reads the `canvasSize`, not the holder's frame.** Big Bento's side playlist pane swings between
  202 and 819px as the user collapses or enlarges it; the row size must not move with it. Using the
  canvas also gives each window of a separate-window skin its own correct number.
- **`auto` depends on canvas height, so every canvas change has to re-push the library's scale** —
  `applyCanvasResize` and `activateLayout`, not just the UI Size observer and surface creation.
  Without that a user resize grows the playlist and leaves the library beside it stale.

The divisor 48 keeps anything under a 528px-tall window at the 11px default. The 18px cap belongs to
`auto` alone, which is guessing: judged on screen, a host-drawn *list* has to stay quieter than the
labels around it. A user who picks 200% is not guessing, so their choice beats the cap.

The `<text>`/`<edit>`/`<list>` paths above are untouched by all of this — they read a size the skin
really did declare for its own object.

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

The video surface later needed the two paths kept apart for a different reason (B63): its teardown
hands the picture back to NullPlayer's own window, and doing that on a *tab switch* pops that window
out over the skin. Unmounting now unparks and stays hidden, and a returning holder re-parks the
picture — [components/video.md](components/video.md) → *A holder leaving is a tab switch*.

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
