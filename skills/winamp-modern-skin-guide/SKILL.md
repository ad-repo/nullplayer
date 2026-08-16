---
name: winamp-modern-skin-guide
description: Winamp 5.x .wal skin engine — Wasabi XML/XUI renderer, MAKI bytecode VM, VFS mounts, component hosting, and the ClassicPro engine import. Use when working on the WinampModern subsystem, debugging a .wal skin that fails to load or renders wrong, or extending Wasabi/MAKI coverage.
---

# Winamp Modern (`.wal`) Skin Engine

NullPlayer's fourth UI mode (`PlayerUIMode.winampModern`) loads and runs **Winamp 5.x modern skins** —
`.wal` archives containing Wasabi XML/XUI markup and compiled MAKI bytecode. It is a clean-room
implementation: the archive is parsed, the object graph is built, and the scripts are interpreted by
NullPlayer's own code. No Winamp binary, plugin, or asset is bundled.

**Status: experimental.** The runtime loads, scripts, and renders real skins, but see
[compatibility.md](compatibility.md) for the exact supported/unsupported surface before assuming any
behavior works.

## Where things live

All engine code is in `Sources/NullPlayer/WinampModern/`; all UI/controller code is in
`Sources/NullPlayer/Windows/WinampModern/`.

| Concern | File |
|---------|------|
| Archive validation | `WalArchive.swift` |
| Logical filesystem + path variables | `WalVirtualFileSystem.swift` |
| Directory-backed provider (engine) | `WalDirectoryResourceProvider.swift` |
| Lenient XML parse + include expansion | `WalXML.swift` |
| Initialization passes, registries | `WasabiSkinInitializer.swift` |
| Retained object graph | `WasabiObjectGraph.swift` |
| Coordinates / anchors | `WasabiGeometry.swift` |
| `<Wasabi:Frame>` splitter | `WasabiFrame.swift` |
| Fonts + text measurement (shared) | `WasabiTextMetrics.swift` |
| Resource cache + scene renderer | `WasabiRenderer.swift` |
| MAKI parser + interpreter | `MakiBytecode.swift` |
| Script runtime + method dispatch | `WinampModernScriptRuntime.swift` |
| Skin-facing host API | `WinampModernHost.swift` |
| Component model + host protocol | `WinampModernComponents.swift` |
| Container topology | `WinampModernContainerTopology.swift` |
| Surface inventory + synthesis | `WasabiSurfaceInventory.swift`, `WasabiSurfaceSynthesizer.swift`, `WasabiStandardFrames.swift` |
| Colour theme + palette | `WinampModernThemeCoordinator.swift`, `WasabiPalette.swift` |
| EQ action decoding | `WinampModernEQActions.swift` |
| Diagnostics | `WalDiagnostics.swift` |
| Compatibility report | `WinampModernCompatibilityReport.swift` |
| Complete loader | `WinampModernSkinLoader.swift` |
| Import + storage | `WinampModernSkinImporter.swift` |
| ClassicPro engine import | `ClassicProEngine.swift`, `NSISArchive.swift`, `LZMA1Decoder.swift` |
| Window controller / view | `Windows/WinampModern/WinampModernMainWindowController.swift`, `…MainView.swift` |
| `AudioEngine` component bridge | `Windows/WinampModern/WinampModernComponentBridge.swift` |
| Surface routing | `Windows/WinampModern/WinampModernSurfaceCoordinator.swift` |
| Embedded library surface | `Windows/WinampModern/WinampModernLibrarySurfaceView.swift` |

Design records and per-phase handoffs: `docs/winamp-modern/`.

## The pipeline

```
.wal file
  └─ WalArchive              validate + bound (ZIP, read-only, on-demand inflate)
      └─ WalVirtualFileSystem  mount at /Skins/<name>/, resolve @VARS@, case-insensitive
          └─ WalXMLDocumentLoader  parse skin.xml, expand <include>/<elementinclude> + globs
              ├─ WinampModernSurfaceInventory   what the skin declares (pre-graph, bounded walk)
              └─ WasabiSurfaceSynthesizer       append windows for missing surfaces
                  └─ WasabiSkinInitializer  6 ordered passes → registries + retained graph
                      ├─ WasabiSceneRenderer   graph → Core Graphics
                      ├─ WinampModernScriptRuntime  MAKI programs bound to graph objects
                      └─ WinampModernHost      the only door to AudioEngine
```

Synthesis sits **before** initialization on purpose: synthetic XML must go through the same
registration, inheritance validation, object creation, and script binding as the skin's own. After
`scripts.start()`, `WinampModernSurfaceCoordinator` reconciles the catalog against the containers that
actually opened.

`WinampModernSkinLoader.load(from:additionalMounts:)` is the headless entry point for the whole
left column and returns a `WinampModernLoadedSkin`. Every test and the window controller go through
it — there is no second path.

### Security model

The skin is **untrusted input**. Three rules hold everywhere and must not be relaxed:

1. **No host filesystem access.** Resources are read only through `WalResourceProvider` /
   `WalVirtualFileSystem`. Never hand a skin an `NSURL` into the real filesystem.
2. **Everything is bounded.** Archive entries, uncompressed bytes, compression ratio, XML depth, node
   count, include depth, image dimensions, font size, script size, instruction count, call depth,
   allocation, stack values, active timers. See [compatibility.md](compatibility.md#limits) for values.
3. **Failures are typed, never traps.** Malformed input produces a `WalFailure` carrying
   `WalDiagnostic`s with a `WalSourceLocation` (`logical-path:line:column`). A Swift trap or a hang on
   skin input is a bug — the fuzz tests in `WinampModernPhase7Tests` exist to catch exactly that.

Scripts cannot navigate URLs, launch executables, open modal UI, reach arbitrary paths, or touch the
network. `messagebox` is denied; `navigateurl` is a no-op.

### VFS mounts

Fixed logical mounts only — the skin never sees a real path:

| Logical path | Backed by |
|--------------|-----------|
| `/Skins/<sanitized-name>/` | the `.wal` archive |
| `/Plugins/classicPro/engine/` | the imported ClassicPro engine, when installed |
| `/System/` | code-supplied defaults via `WinampModernAdditionalMount` |

Path variables: `@WINAMPPATH@`, `@SKINPATH@`, `@COLORTHEMESPATH@`, `@DEFAULTSKINPATH@`. Windows
separators, `.`, and `..` are normalized; a path escaping `/` is a hard error. A `*` wildcard is
allowed **only** in the final include component and returns sorted, deterministic results.

Cross-mount climbs work, which is how cPro-Bento reaches its engine:
`@COLORTHEMESPATH@\..\..\Plugins\classicPro\engine\load.xml`.

### Initialization passes

`WasabiSkinInitializer` runs six explicit, tested passes, in this order:

1. resource registration
2. groupdef/XUI registration + inheritance validation
3. object creation
4. script binding
5. initialization
6. first-paint preparation

Group semantics worth knowing:

- `inherit_group` **is** the inheritance edge (depth limit 64, cycle-detected).
- `embed_xui` is retained as metadata and is **not** an inheritance edge.
- `xuitag` registers a custom XML tag name for group instantiation.
- A later duplicate definition **replaces** an earlier one and emits a warning — this is deliberate;
  it is how skins override engine defaults.
- `registerWasabiStandardLibrary` seeds the curated `wasabi.*` base groups that ship inside Winamp
  rather than in the archive. Skin/engine definitions register first and always win. A base outside
  the curated set warns and is dropped rather than failing the load.

### Retained graph and coordinates

`WasabiObjectGraph` owns every node (including detached ones). IDs are monotonic and deterministic
for a deterministic expanded document, which makes `snapshot()` the golden-test surface. XML `id`
values are attributes and are **not** unique, so `objects(xmlID:)` returns an array.

Geometry stays in **Wasabi top-left coordinates** throughout the graph. The signed-anchor rule is
encoded in `WasabiGeometry`:

- `x=-60 relatx=1` → `parent.width - 60`
- `w=-120 relatw=1` → `parent.width - 120`
- same for Y/height; missing dimensions use the intrinsic size

> **Gotcha:** the Y flip to AppKit's bottom-left happens exactly **once**, at the Core Graphics
> drawing boundary in `WasabiSceneRenderer` (and once at the event boundary in `WinampModernMainView`).
> Never store flipped coordinates back into the graph, and never insert AppKit types into graph objects.

`fitparent="1"` fills the parent regardless of `x/y/w/h`. Winamp Modern and ClassicPro use it
constantly for their SUI/content groups; without it those groups resolve to a 0×0 rect at the origin
and every descendant collapses into the top-left corner.

#### The two y-origin conventions (source of a whole class of bugs)

Three different APIs are involved and only one of them is bottom-left:

| Operation | Origin | Rule |
|---|---|---|
| Wasabi `y=` in XML, graph frames | top-left | native, never converted |
| `CGImage.cropping(to:)` | **top-left** | indexes raw pixel rows — pass the Wasabi `y` **unchanged** |
| `CGContext.draw(image:in:)` | bottom-left | places the image's *bottom* row at `rect.minY` |

Because `draw(in:)` runs under the renderer's flipped CTM, `rect.minY` is the visual *top*, so every
bitmap must be re-flipped about its own rect or it renders vertically mirrored in place. That is what
`drawImage(_:in:context:)` exists for — **use it for every image draw**, never `context.draw` directly.
`drawFlippedText` does the same job for text.

Converting a Wasabi `y` to a bottom-left origin before `cropping(to:)` mirrors the source rect about
the sheet's centreline, so every sprite is cut from the wrong row of the atlas. Sprite-sheet crops in
`drawBitmapText` and `drawAnimated` index rows directly for the same reason.

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
- Dragging the divider is not implemented, so `minwidth`/`maxwidth` are not enforced yet.

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

#### Layer fill modes

- **Default (no `tile`)**: the bitmap **stretches** to the layer's rect. Resizable window chrome
  depends on this — `wasabi.frame.top` is a 10×18 sprite stretched across the whole titlebar, and the
  menubar/titlebar streaks are 5–10px sprites stretched to hundreds of pixels. Drawing them at
  natural size paints one sprite and leaves the rest of the bar blank.
- **`tile`/`tilex`/`tiley`**: repeat the bitmap instead. Bento-style frames tile their
  top/bottom/left/right/center strips. Tiles are blitted 1:1 with interpolation off, or the resampled
  edges leave a visible seam grid.

### MAKI

`MakiBytecodeParser` reads the `FG` compiled-script format (classes, methods, typed
variables/constants, bindings, instructions); `MakiInterpreter` executes it. The opcode surface is
**demand-driven** — opcodes were added because a measured target skin needed them, and unsupported
opcodes **fail closed** rather than becoming silent no-ops.

A missing method aborts only the script event that hit it — the rest of the skin's scripts still run
and the failure is collected into the compatibility report. It cannot be finer-grained than that:
call sites carry no argument count, so without a signature the stack cannot be unwound.

> **Gotcha:** `MakiInterpreter.dispatcher` is `weak` (the runtime owns the dispatcher). If you
> construct an interpreter in a test with a temporary dispatcher, it deallocates immediately and
> `execute` silently returns at its `guard let dispatcher` without running an instruction — the test
> then passes for the wrong reason. Bind the dispatcher to a local first.

Extending the API: add to `signature(for:)` **and** the matching system/GUI/object dispatch path
together, so argument counts and return kinds stay explicit. Add a regression test with each method.
Use the measured-demand signal rather than porting reference stubs blindly — see
[Debugging](#debugging-a-skin) below.

> **Gotcha:** a method with a `signature(for:)` entry but a stubbed dispatch case is **invisible to
> the compatibility report** — it looks implemented and returns a plausible value. `newgroup`
> returned `.null` this way, and the report showed zero script findings while the entire Winamp
> Modern window body was missing. If you cannot implement a method, leave it out of `signature(for:)`
> so the demand tally records it.

> **Gotcha:** the blocking list is a **queue, not a set**. Each method you add lets its script run
> further and reach the next thing it needs, so the report after a fix names methods the report
> before it could not have known about. cPro-Bento took three full rounds (9 methods → 4 → 0).
> Re-measure after every change; never work down a static list.

**Opcodes are exercised at the same rate as methods** — that is, barely, until a script gets far
enough to use one. `delete` (opcode 97) consumed its operand for eight phases before anything reached
it. `delete obj` is an **expression**: the compiler emits `push; delete; pop`, so the opcode must
leave the value for the statement's own discard pop. When you first unblock a batch of scripts,
expect the *next* failure to be an interpreter bug rather than a missing method.

**A parse failure is worse than a runtime one** — it kills the whole skin, not one event. Opcode 104
(dynamic `Member` access) carries an immediate shaped like a variable record's first two bytes: a
type offset, then an "is object" flag. `Member GuiObject Tab.left;` therefore compiles to
`0x0100 | classIndex` (265 in ClassicPro's `CproTabs.maki`), which read as a plain value kind is an
"unknown value type" and fails the parse. Object members carry their class GUID through to the
member's storage.

#### Script-built UI: `onSetXuiParam` and `System.newGroup`

Winamp Modern's window frames are **hollow XML**. `Wasabi:MainFrame:NoStatus` ships only titlebar and
menubar chrome; the entire client area comes from its `content=` param at runtime:

1. The object is created from the groupdef, and its script (`standardframe.maki`) is bound to it.
2. `onScriptLoaded` fires (a **System** event) and the script caches `getScriptGroup()`.
3. Each XML attribute is delivered as `onSetXuiParam(name, value)`.
4. The handler for `content` calls `System.newGroup(id)`, which expands that groupdef as a child of
   the calling script's own group; the script then positions it with `setXmlParam`.

Two ordering rules make or break this:

- `onSetXuiParam` is a **System** event, not a GUI-object event, and each XUI instance has its own
  program instance. Dispatch it only to programs whose `ownerID` is that object, or one frame's
  `content` reaches all of them.
- It must run **after** `onScriptLoaded`. The handler binds to the script-group variable that
  `getScriptGroup()` populates during `onScriptLoaded`; dispatched earlier, no binding matches and
  every param is silently dropped.

`WasabiSkinRuntime.instantiateGroup` performs the expansion (set by `WasabiSkinInitializer`, so
runtime growth shares the load-time VFS, limits, and object budget). Scripts declared inside the new
subtree are parsed and started via `startScripts(addedBeneath:)`, bounded by `maximumRuntimePrograms`.

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

#### Rotary controls: `Map`

A `Map` is a bitmap the script samples rather than draws: `getValue(x, y)` returns the pixel value at
a point (MMD3's `map.png` is a 44×44 grayscale sweep of the knob's angle) and `inRegion(x, y)` says
whether the point is on the control. `new Map` and `new Timer` produce the same kind of dynamic
object — class GUIDs are not in the archive — so an object becomes a map on its first `loadMap`.
Knob scripts mix `getMousePosX()` with the x/y of a mouse event in one expression, so the cursor
position is reported in **skin pixels**, not screen points; UI Size never enters the script's world.

A `Map` is also a general **image-inspection** object, not only a knob lookup: `getWidth`/`getHeight`
size things from artwork, and `getARGBValue(x, y, channel)` reads whole pixels — ClassicPro derives
its visualization colour bands this way (`colorbandpeak="r,g,b"` from channels **2, 1, 0**, i.e. the
index is BGRA). And `loadMap` takes **either a resource id or a VFS path**; ClassicPro's "is the
plugin installed?" probe is the path form (a 1×1 `installed.png`, checked with `getWidth() != 1`).
Supporting only ids made cPro-Bento conclude the engine was missing and try to switch skins.

#### Asking a skin what it actually shipped

Engines are written to run against skins that omit optional pieces, and they ask two questions:

- **`isInvalid()`** — is this object real? True for a null receiver *and* for an object whose declared
  bitmap never resolved. ClassicPro probes for optional artwork by declaring a hidden layer over it
  (`<layer id="read.bg.left" image="player.left.alt" visible="0"/>`) and asking that layer. Answering
  "valid" for a skin that ships no `mainframe_lr.png` sent `player.maki` on to swap the window frame
  over to bitmaps that do not exist — visible as holes punched through the window's edges.
- **`getCurCfgVal()`** — the value of the config attribute the object is bound to via
  `cfgattrib="{GUID};Name"`. The GUID is the section key, the same addressing `getItemByGuid` uses.

#### Track metadata the skins actually read

Skins do not call dedicated bitrate/sample-rate APIs. `songinfo.maki` lowercases
`System.getSongInfoText()` and pulls values out around the literals `kbps`, `khz`, and the channel
words. The units must be **attached to the number** (`320kbps`, `44khz`) — a space between them and
the fields stay empty. `WinampModernHost.songInfoText` builds this; `trackDisplayTitle` supplies the
`"Artist - Title"` a song ticker shows (`trackTitle` alone drops the artist).

A `songticker` carries no `text`/`default` attribute — its content **is** the current track, and it
scrolls by default. `ticker="bounce"` slides to the end and back; any other enabled value scrolls
continuously and is drawn twice with a gap so it never blanks between cycles. Both the TrueType and
bitmap-font paths share `tickerMotion(for:overflow:textWidth:)`.

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

#### Where a surface lives

`WinampModernSurfaceCoordinator` is the single answer, for menus, skin buttons, and restore alike:
**embedded → declared container → synthesized container → classic fallback**. `WindowManager`'s
`show*`/`toggle*`/`is*Visible` consult it before their classic paths; the fallback has its own entry
point (`showClassicSurfaceForWinampModern`) because re-entering the public toggles would route back
into the coordinator.

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
  `content=` group. The empty built-in `wasabi.*` shells never qualify — they would produce a titled
  empty box.
- mmd3 declares `wasabi.standardframe.*` with **no `xuitag`** (real Winamp's standard library supplies
  it). `WasabiTypeRegistry.registerXUITagAlias` fills an *unclaimed* tag pointing at an *existing*
  groupdef, before the shells are seeded, so a skin's own `xuitag=` always wins.
- **Winamp defines no equalizer component GUID.** An equalizer is recognized by its controls
  (`EQ_BAND`/`EQ_PREAMP`/`<eqvis>`) and a synthesized one uses `guid:eq`. `EQ_TOGGLE`/`EQ_AUTO` do not
  count as evidence — a button that opens the EQ is not an EQ.

#### Container-scoped layout callbacks

One skin, one runtime, several windows: `layoutSwitchRequested`/`layoutResizeRequested` carry the
container's `WasabiObjectID` (derived from the receiver), and the window controller routes each to the
view that owns that container. Without the id, a playlist script resizing itself resized the player.
The controller installs both **before `scripts.start()`** — a skin that resizes from `onScriptLoaded`
does it during `start()`.

#### Colours and hosted AppKit content

`WinampModernThemeCoordinator` owns the one `WasabiColorThemeCatalog` per loaded skin; renderers and
views subscribe by identity token and drop their themed bitmaps on a switch. `WasabiPalette` gives
NullPlayer-drawn content (playlist rows, EQ sliders) colours from the skin's own resources, resolved
through the renderer's *own* resolver so gamma matches.

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

## ClassicPro engine

cPro-Bento does not contain its own engine — it depends on the **ClassicPro** plugin, which ships in a
separate Windows installer. NullPlayer bundles nothing and asks for no permission; the user supplies
the installer and it is extracted **internally**, with no external tools, temp files, or code
execution:

- `LZMA1Decoder` — from-scratch incremental raw LZMA1 range decoder
- `NSISArchive` — NSIS-2 solid-LZMA reader; replays only `SetOutPath`/`ExtractFile` to reconstruct the
  file tree. Other layouts (non-solid, zlib/bzip2, NSIS-3, non-NSIS) get an actionable diagnostic.
- `ClassicProEngineImporter` accepts `.exe`, `.zip` (including a nested installer), or an extracted
  folder; validates structure (requires the `one` family) and SHA-256 hashes the content
- `ClassicProEngineStore` keeps one private copy and exposes a read-only mounted provider

The engine's entire native (`ClassicPro.w5s`) surface is three filesystem-shell methods, none on the
render path. They are adapted under a strict policy: `exploreFile` reveals an existing file in Finder,
`openFile` opens an existing file with the default app (no URLs, no `~`, no executables), and
`findFiles` is a bounded no-op returning −1 so callers early-return.

`WinampVersionCheck` is satisfied by reporting a build number past the `2405` gate, so `load.xml`
*branches* through its "please update Winamp" path rather than being hard-blocked. The skin's own
`warning.maki` runs a **second, independent** check — a `Map` load of the engine's 1×1
`image/installed.png` — and `switchSkin`es away if it fails; that is why `loadMap` must accept a path.
`switchSkin` itself is accepted and inert: choosing a skin is the host's decision, not a script's.

**The engine ships its MAKI `.m` source next to the bytecode.** Read the script that owns the broken
feature instead of inferring semantics — `getARGBValue`'s BGRA channel order, `getDateYear`'s
years-since-1900 scale, and the `isInvalid` probe idiom were all pinned that way rather than guessed.

## Debugging a skin

**Start with the compatibility report.** `WinampModernLoadedSkin.compatibilityReport` (and
`compatibilityReport(withRuntime:)`) aggregates load diagnostics plus the runtime's unsupported-method
tally into de-duplicated categories (`archive`, `resources`, `groups`, `scripts`,
`unsupportedMethods`, `other`) with a coarse level (`.full` / `.degraded` / `.unsupported`). In DEBUG
builds the main window controller logs it after `scripts.start()` whenever the level is not `.full`.
The `unsupportedMethods` bucket is the **measured-demand list** for what to implement next.

**Then look at the pixels.** Structural assertions (graph built, scripts ran, node counts) cannot see
a rendering bug: a vertical-flip and a wrong crop origin survived 490+ green tests because nothing
ever rendered a frame. `WinampModernRenderDumpTests` renders every container/layout of a real skin to
PNG and reports the scene:

```sh
WINAMP_MODERN_WAL=/path/Skin.wal \
WINAMP_MODERN_RENDER_DUMP=/tmp/render \
  swift test --filter WinampModernRenderDumpTests
```

Optional env switches, all off by default:

| Variable | Effect |
|---|---|
| `WINAMP_MODERN_ENGINE` | import + mount the ClassicPro engine first (cPro skins) |
| `WINAMP_MODERN_RENDER_PROBE=<container>/<layout>` | dump every scene node: type, id, frame, clip, bitmap, attributes |
| `WINAMP_MODERN_RENDER_BITMAPS=1` | count resolved bitmaps and list any that fail to load |
| `WINAMP_MODERN_RENDER_XUI=1` | list objects with scripts and whether their events bind |
| `WINAMP_MODERN_RENDER_CLOCK=<seconds>` | pin the animation/ticker clock; render two values to prove motion |

Use the probe to answer "is it missing art, bad geometry, or a script that never ran" before changing
renderer code — `BITMAPS … missing=` distinguishes an unresolved resource from one that draws wrongly.

> **Gotcha:** the harness must install an `NSGraphicsContext` around `renderer.draw`. `drawText` ends
> in `NSString.draw(in:withAttributes:)`, which renders into the *current* `NSGraphicsContext`, not
> the `CGContext` it was handed. Without it every TrueType/system-font string is silently dropped from
> the dump while the real app (always inside `NSView.draw`) shows them — the harness lies to you.

**The dump only ever renders a skin's *initial* state.** A defect a script mutation introduces later
(a font swapped at runtime, an object shown after a click) is invisible to it. `WinampModernCrashRepro`
is the opt-in harness for that case: it fires every standard event at every object in graph order,
redrawing after each, then sweeps the clock. It was written for a live-run crash it still does not
reproduce — extend it rather than starting over.

> **Anything a skin controls can reach CoreText, and a nil there kills the process.**
> `NSString.size(withAttributes:)` aborts with `attempt to insert nil object` if any attribute value
> is null — inside `NSView.draw`, so it is an app crash, not a bad frame. AppKit/CoreText
> constructors are imported as non-optional but can still return null, and **only an `Optional`
> binding sees it** (`let font: NSFont? = …`). `WasabiResources.font` therefore returns `NSFont?`,
> point sizes are clamped to a finite 1…256, and a skin TrueType with no PostScript name is rejected.
> Apply the same discipline to any new skin-derived value handed to a system API.

`WinampModernRenderPixelTests` is the synthetic guard for all of the above: a banded atlas whose crop
origin, upright orientation, tiling, and `fitparent` sizing are asserted per pixel. When you touch
`WasabiSceneRenderer`, verify a fix *fails* without the change before trusting it.

Load a developer archive directly (DEBUG builds):

```sh
./.build/debug/NullPlayer -uiMode winampModern -winampModernSkinPath /abs/path/Skin.wal
```

This still goes through `WinampModernSkinLoader` and its VFS — it is an acceptance hook, not a
filesystem bypass.

Run the engine tests:

```sh
swift test --filter WinampModern              # all synthetic coverage, headless
swift test --filter WinampModernPhase7Tests   # fuzz / stress / limits
```

Opt-in tests against user-supplied skins (nothing third-party is committed, so these skip unless the
env var is set):

```sh
WINAMP_MODERN_WAL=/path/CornerAmp_Redux.wal swift test --filter WinampModernPhase3Tests
WINAMP_MODERN_WAL=/path/WinampModern.wal     swift test --filter WinampModernPhase4Tests
WINAMP_MODERN_ENGINE=/path/ClassicPro_2.01.exe \
  WINAMP_MODERN_WAL=/path/cPro__Bento.wal    swift test --filter WinampModernPhase6Tests
```

Each phase expects a specific fixture — Phase 4 asserts Winamp Modern's 354×280 geometry, so
cPro-Bento is the wrong fixture for it.

## Rules for extending this subsystem

- Do not weaken a limit or a sandbox rule to make a skin load. Degrade gracefully with a warning
  diagnostic instead — a missing optional bitmap or an unknown `wasabi.*` base should warn, not fail.
- Do not add host capabilities beyond what a measured skin needs, and keep them narrow and typed.
- Do not put platform rendering state into `WasabiObjectGraph`.
- Do not broaden the release UI surface as a side effect of unrelated compatibility work.
- Preserve `WalDiagnostic`s; do not replace them with renderer-specific string errors.
- Add fixtures, never third-party assets. Every committed test fixture is synthetic and self-authored.

## Related

- [compatibility.md](compatibility.md) — supported/unsupported Wasabi + MAKI surface, limits, engine policy
- [manual-qa-checklist.md](manual-qa-checklist.md) — the GUI verification pass
- `docs/winamp-modern/` — decision records and per-phase handoffs
- `docs/legal/winamp_modern_provenance.md` — clean-room provenance record
- `skills/modern-skin-guide` — NullPlayer's *own* modern skin system, which is unrelated to this one
