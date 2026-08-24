# Winamp Modern (`.wal`) — MAKI surface

Part of [compatibility.md](../compatibility.md). Implemented and unimplemented script methods, the event surface, and dispatch behavior.

## MAKI

**Supported opcodes** — stack push/pop/assignment; equality and ordered comparison; conditional and
unconditional branches; host/global method calls; local call/return; move; pre/post
increment/decrement; arithmetic and modulo; bitwise and logical operations; allocation; delete.

**Supported API** — the authoritative list is `signature(for:)` in `WinampModernScriptRuntime.swift`.
By area:

- **Playback host**: playback state, current time, duration, volume, shuffle/repeat, title/info,
  spectrum levels, transport (play/pause/stop/prev/next), seek, file-open
- **GUI mutation**: `setxmlparam`, `resize`, `show`, `hide`, `toggle` (each invalidates the view). An
  image-valued param (`image`, `bitmap`, `background`, the button/slider state images) is a **load**:
  an id the skin never registered — the empty string included — leaves the object wearing the artwork
  it already had, as a failed load does in Winamp. Defix names its background art from a preference it
  never seeds, so taking those writes literally stripped the wood panel off the player and the frame
  off every other window. Phase 25
- **Lookups**: containers, layouts, object descendants, script group, script parameter/token access
- **System**: viewport/application coordinates, runtime/skin identity, integer/string/float
  conversion (`integerToString`, `stringToInteger`, `floatToString`, `stringToFloat`) and the casts
  (`Integer`, `Float`, `String`, `Boolean` — a script mixing a float with an int-typed API needs
  them, which is where a volume handler lives), date helpers, per-skin
  `getPublicInt`/`setPublicInt`
- **`PopupMenu`**: `addCommand(title, id, checked, disabled)`, `addSeparator`, `addSubMenu(child,
  title)`, `checkCommand`, `popAtMouse`, `popAtXY(x, y)` — shown as a real `NSMenu` through
  `popupPresenter`, which the main view installs. `popAtMouse` pops at the mouse; `popAtXY` at the
  given point, in the window-client space `clientToScreenX/Y` answer in (Phase 24). Both block and
  answer the picked id (0 = cancelled)
- **Events dispatched to scripts** — see the table below
- **Timers**: bounded scheduling (see limits)
- **Animated layers**: `getLength`, `gotoFrame`, `getCurFrame`, `setStartFrame`, `setEndFrame`,
  `setSpeed`, `play`/`stop`, `isPlaying` — the play head is a pure function of the time since `play()`
  (`WasabiAnimation`), so the renderer and the script always agree on the current frame
- **`Map`**: `loadMap`, `inRegion`, `getValue`, `getWidth`, `getHeight`, `getARGBValue(x, y, channel)`
  — a bitmap the script samples. `new Map` and `new Timer` are indistinguishable at construction
  (class GUIDs are not in the archive), so a dynamic object becomes a map on its first `loadMap`.
  `loadMap` takes **either a declared bitmap id or a VFS path**; ClassicPro's "is the plugin
  installed?" probe is the path form (`…/engine/image/installed.png`, width 1). The `getARGBValue`
  channel index is **BGRA** — pinned by `player.maki` building `colorbandpeak="r,g,b"` from channels
  2, 1, 0
- **`Region`**: `loadFromMap(map, threshold, reversed)`, `offset(dx, dy)`, and `<object>.setRegion(r)`
  — plus the short `<object>.setRegionFromMap(map, threshold, reversed)`, which skips the intermediate
  object. Clips one control to a shape taken from a map's red channel: **reversed** keeps every pixel
  at or below the threshold (how a skin fills a bar as its value rises), the plain form everything at
  or above. `offset` moves the shape in map pixels, for skins whose map covers a whole window rather
  than the control. Settled by the same first-call rule as `Map`. `setRegion` with anything that is
  not a loaded region clears the clip, and a map that cannot be resolved leaves the control
  **unclipped** rather than clipping it away to nothing. The region does not affect hit testing: T800
  drags its volume by tracking the mouse across the *whole* strip, most of which the region has
  clipped away
- **`XmlDoc`**: `load`, `exists` — **inert**. The callback-driven parser is not implemented, so a
  document always reports that it does not exist and every caller takes its own skip path. Cost: a
  skin's optional `ClassicPro.xml` extras (songticker antialiasing, custom beat-vis names) are ignored
- **Window scaling**: `<layout>.setScale(f)` is answered by **NullPlayer's own UI Size** — the level
  nearest the requested factor — and by nothing else. A `.wal` scene is always laid out on the skin's
  pixel grid, with UI Size applied at the view's drawing and input boundaries, so a second
  layout-local scale would be a rival for the same pixels. `getScale()` therefore still answers **1**
  whatever size the windows are drawn at: the layout's own scale really is 1, and ClassicPro's resize
  arithmetic (which multiplies by it) is in skin pixels. On a receiver that is not a layout the call
  is accepted and inert. Measured demand: Defix's seven configurator buttons (100, 125, 150, 175,
  200, 250, 300 — the ladder gained 175/250/300 for them), Ebonite's `standardframe.m` and boom's
  `prefs.m`; all three call it on a layout. **Not** dispatched: `onScale`, the layout event Wasabi
  raises when a scale changes (Ebonite uses it to keep two layouts in step, which our one global
  scale already does)
- **Object validity**: `isInvalid()` is true for a null receiver *and* for an object whose declared
  bitmap never resolved. ClassicPro probes for optional artwork by declaring a hidden layer over it
  and asking that layer whether it is invalid
- **Cursor + EQ**: `getMousePosX`/`getMousePosY` (in **skin pixels**, on the window's canvas — *not*
  the space a mouse event's x/y use, which is the receiver's parent; see
  [reference/scripting.md](../reference/scripting.md) §*Rotary controls*), `getEQ`, `getEqBand`/`setEqBand` and `getEqPreamp`/`setEqPreamp` (MAKI's −127…127 scale ↔ the
  engine's ±12 dB), `atan`. Both setters **announce the change** (`onEqBandChanged` /
  `onEqPreampChanged`, Phase 41) exactly as `setVolume` does
- **`List`**: `addItem`, `enumItem`, `getNumItems`, `removeItem`, `removeAll`, `findItem` (objects
  match by identity, other values by string form); bounded at 4096 items.
  **`BitList`**: `setSize`, `getSize`, `setItem`, `getItem` — same backing store, holding flags
- **`WinampConfig`**: `getGroup(guid)` → `getInt`/`getBool`/`getString`, resolved against the skin's
  own namespaced configuration, never real Winamp settings. Unset reads 0/""/false, which is also the
  right answer for the one item ClassicPro asks about (`"frequencies"` = 0, the classic EQ frequencies
  NullPlayer's `EQConfiguration.classic10` uses). The setters are deliberately absent
- **Children**: `getNumChildren`, `enumChildren(i)`
- **`System.getCurrentTrackRating()`** — always 0 (unrated). NullPlayer's playback `Track` carries no
  user rating (the library's rating is in `MediaLibrary`, which is not on the host adapter), so the
  ClassicPro ratings widget draws no stars rather than aborting its script
- **Runtime instantiation**: `System.newGroup(id)` creates a registered groupdef's subtree under the
  calling script's group, and `<object>.init(parent)` **moves it where the script wants it**. The new
  subtree's own scripts start on that attachment, not on creation — a script's first act is to look
  around from its own group, so starting it before `init` gives it the wrong parent. A group that is
  never `init`'d still starts, once the outermost dispatch unwinds. Phase 24
- **`System.newGroupAsLayout(id)`** — Winamp gives the groupdef its own borderless floating layout,
  owned by the layout its `owner="<container>,<layout>"` attribute names. Ours is an **overlay child of
  that owner layout**, appended last, keeping a `group` type — and the coordinates say that is the
  right answer rather than a compromise: multipass positions the result with
  `resize(layout.getLeft() + 54, layout.getTop() + 217, 164, 78)`, our root layout answers 0 for both
  (window-local), and (54, 217) is exactly where the author's own commented-out `<group x="9" y="62"/>`
  inside drawer.bottom (45, 155) would have put it — confirmed by `RENDER_CLICK_WATCH`. It must **not**
  be typed `layout`: `resize` on a layout is a *window* resize. No `owner=` falls back to the calling
  script's own layout; a caller with no layout above it (a `skin.xml`-level script) answers null.
  Phase 33 — this one method's absence aborted multipass's entire startup
- **`ToggleButton.setActivatedNoCallback(bool)`** — `setActivated` without the `onToggle` it would
  otherwise send. A skin uses it to follow state it is already reacting to; the plain setter there
  re-enters its own notification. Phase 33
- **`GuiObject.getClassName()`** — the object's Wasabi class (`layer`, `button`, `togglebutton`,
  `slider`…). multipass's style switcher walks one list of mixed objects and branches on
  `strUpper(getClassName())` to decide which artwork attributes to swap. Phase 33
- **`Container.close()`** — the `hide()` route: a container is a window, anything else stops in the
  graph. Phase 33
- **`Container.toggle()`** — `show`/`hide` with the direction read back first. Ujola Cat's Color
  Themes and cat buttons carry no `action` at all: `getContainer("colorthemes").toggle()` is the whole
  handler, and a fail-closed refusal took both buttons with it. The direction comes from the **host's
  window state** (`containerVisibilityQuery`), not from the graph's `visible` attribute, which the
  host never writes when a window is opened from the Windows menu or closed from its own titlebar —
  read off the attribute the toggle inverts after the first manual close. `isVisible()` answers from
  the same place for a container; for anything else it **walks up the parent chain** — an object
  inside a hidden group is not visible, matching Winamp's rule (B22, Phase 34 addendum)
- **`GuiObject.isActive()`** — "does my window have the keyboard?", answered by walking up to the
  object's **container** and asking the host whether that window is key. The gate a skin puts in front
  of a key handler: `onKeyDown` reaches every program in the skin whatever window is focused, so
  winampmodern566's playlist asks it (of its content group *and* of that container's `shade` layout —
  both resolve to the same window, which is the only thing that can be focused) before acting on
  `ctrl+w`. With no host to ask — the headless harness — every object reads active, so a probe can
  still drive a handler that gates on it. Unimplemented before Phase 43, and fail-closed dispatch
  meant it aborted the whole handler
- **`System.isAppActive()`** — answered honestly (`NSApp.isActive`; `true` with no application, i.e.
  the harness), unlike its `isMinimized`/`isKeyDown` neighbours. Skins *gate work* on it: multipass's
  drawer Focus Mode returns early from its 100 ms timer while the app is inactive, so a hardcoded
  `false` would have stopped the drawers permanently. Phase 33
- **`System.strUpper(s)`** — beside `strLower`. Phase 33
- **Paint order**: `bringToFront` / `bringToBack` — sibling order within the parent. Phase 24
- **Per-skin string config**: `getPrivateString` / `setPrivateString`, beside the integer pair.
  Phase 24 — `CproTabs.m` stores its tab order here
- **Resolved geometry**: `getLeft`/`getTop`/`getWidth`/`getHeight` and `getGuiX/Y/W/H` answer where the
  object actually **landed**, in its parent's coordinates, supplied by the window that renders its
  container. The declared attribute is only the fallback for an object the active scene cannot place.
  Reading the markup instead is wrong for any relative geometry: cPro's tab strip is `w="-4"
  relatw="1"`, and `getWidth()` = −4 made its script squeeze every tab to its minimum. Phase 24
- **Window-manager notifications**: `beforeRedock()`, `redock()`, `snapAdjust(x, y, w, h)` — deliberate
  no-ops (NullPlayer places `.wal` windows itself and has no docking model for them), but they must
  *exist*: a missing method aborts the whole handler, and this trio is what stopped the stock Winamp
  Modern skin's CONFIG button from ever opening its equalizer drawer. Their arities were read out of the
  bytecode with `WINAMP_MODERN_RENDER_DISASM`, not guessed — a wrong argument count desynchronises the
  interpreter's stack. Phase 24
- **`debugString(message, level)`** — a skin's own trace output, dropped. Phase 24
- **`clientToScreenX/Y` and `screenToClientX/Y`** — relative to the receiver's **parent** client area,
  which is the space `getLeft()`/`getTop()` already answer in. Every measured call site is the idiom
  `b.clientToScreenX(b.getLeft())` — receiver and coordinate the same object — which only makes sense
  under that reading: taking it as the receiver's *own* box double-counts, and taking it as pure
  identity loses the parent chain (that is what put ClassicPro's tab menu at the window's left edge
  instead of under its tab). "Screen" is the window's client space: a `.wal` window is borderless and
  positioned by us, so the window origin is a constant that cancels in the round trip every caller
  makes, and `popAtXY` places its menu in the same window the point came from. The stock skin's
  titlebar exercises the other shape — `layout.clientToScreenX(…)` out, titlebar **group**
  `screenToClientX(…)` back, then `− group.getLeft()` — and both objects hang off the layout, so it
  returns the input and the correction lands. Phase 24
- **`popAtXY(x, y)`** — a script-built menu at a computed point, in the same coordinates the
  conversions above answer in. ClassicPro's tab-strip right-click menu and its drawer's "goto" menu.
  Phase 24
- **`System.getExtension(path)`** — the extension of a filename, without the dot, from the last path
  component (Windows separators included). Defix reads it off the playing item for its format readout.
  Phase 25
- **`System.getPath(path)` / `System.removePath(path)`** — the directory half and the leaf half of a
  path, the way `getExtension` is the tail. Pure string work on a string the host already handed out
  (Windows separators included); neither opens anything or reaches the filesystem. B38
- **`System.getDecoderName(item)`** — Winamp names the *input plugin* decoding the item; the honest
  equivalent here is the codec NullPlayer is decoding, from the track's own extension
  (`WinampModernHost.decoderName`), with "HTTP Stream" for a stream that has none. Skins print it as a
  *Decoder* readout. B38
- **`System.getPlayItemMetaDataString("filename")`** — the playing item's location
  (`WinampModernHost.trackPath`). Display only: nothing in the seam opens a path a script hands back,
  and the file-info panels immediately split it with `getPath`/`getExtension`. B38
- **`System.getIdealVideoWidth()` / `getIdealVideoHeight()`** — **0**, for the same reason
  `hasVideoSupport` is false, and also what Winamp answers for an audio track. B38
- **`System.hasVideoSupport()`** — **false**. A `.wal` video holder gets the neutral backing every
  unhosted component kind gets, so a skin that asks is told the truth and lays itself out without a
  video tab. Phase 25
- **`System.newDynamicContainer(id)`** — answered with the **already-instantiated** container of that
  id rather than a fresh instance. Every declared container exists from load, and a script's next move
  is always to reach into the one it asked for
  (`newDynamicContainer("browserpro").getLayout(…).findObject(…)`). A skin that wants two copies of one
  window gets one. Phase 25
- **`<object>.setFontSize(px)`** — writes the same pixel height the XML attribute carries. Phase 25
- **Layer FX** (`fx_setEnabled/Wrap/Rect/BgFx/Clear/Realtime/Localized/Bilinear/AlphaMode/Speed`,
  `fx_setGridSize(w, h)`, `fx_update`, `fx_restart`, and the `fx_get*` readbacks) — **implemented**,
  Phase 28. A skin's rotating parts are not sprite strips: an analog VU needle or a spinning cassette
  reel is one still image warped through the skin's own callbacks, so before this they were silently
  **frozen** (nothing failed, and the compatibility report stayed clean while most of a skin's meters
  stood still).

  How it works here: the layer is covered by a grid of `fx_setGridSize` **cells**; the skin's callback
  is evaluated once per grid **vertex** per frame into a source-coordinate mesh, and every destination
  pixel takes its source from the bilinear interpolation of the four vertices around it. A rotation is
  affine in x/y, so even a 1×1 grid (Defix's cassette reels) reproduces one exactly.
  `WasabiLayerFX.swift` owns the model and the resampler; `WinampModernScriptRuntime.layerFXMesh`
  evaluates; `WasabiSceneRenderer.layerFXProvider` draws.

  **`fx_onGetPixelR` answers with the source *angle* and `fx_onGetPixelD` with the source *distance*
  (R for rotation, D for distance)** — the opposite of how the parameter names in `std.mi` read.
  Measured from Defix's needle and cassette scripts, which return `argument0 + rotation` where the
  rotation is degrees ÷ 57.295 (= 180/π); a radius answer would slide a needle along its own length
  instead of sweeping it. Coordinates are normalized 0…1, top-left origin, centre (0.5, 0.5), angle
  growing clockwise.

  Not implemented, and not yet asked for by anything measured: `fx_onGetPixelA` (per-vertex alpha),
  `fx_setBgFx(1)` (warping the backdrop rather than the layer's own image), and `fx_setSpeed` as a
  host-driven animation clock — the skins in the corpus drive their own timers and call `fx_update()`.

  A warp is a CPU resample on the paint path, so it is bounded: vertices per layer and warped surface
  size both have ceilings, and the mesh is cached until `fx_update()` unless `fx_setRealtime(1)`. The
  warped raster is cached with the mesh that produced it, so a repaint the skin did not ask for (a
  neighbouring object moving, AppKit widening a partial invalidation) does not re-run the pixel loop
  for a warp that has not moved a vertex. Phase 29.

  **The mesh is evaluated off the paint path.** Running the skin's callbacks per vertex through the
  interpreter is main-thread work — MAKI is single-threaded and the graph is not thread-safe — but it
  does not have to happen *inside* `NSView.draw`. The window's 30 Hz clock calls
  `refreshLayerFXMeshes()` first and invalidates second, so the frame AppKit is composing is never
  the one waiting for the VM. Phase 29.
- **MAKI's math library** — `sqrt`, `pow`, `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `atan2`,
  `log`, `log10`, `exp`, `abs`, all `System` methods. Phase 28. Domain errors answer 0 rather than a
  NaN that would travel into a coordinate. Missing `sqrt` alone kept Defix's needles frozen *after*
  Layer FX worked: its `onTimer` aborted on the first call, every tick, and the abort is invisible
  unless you look at `WINAMP_MODERN_RENDER_SCRIPTS=1`'s `failed=` column
- **`onSetVisible` when a window is shown** — Phase 28. A `.wal` skin starts and stops its animation
  from this handler (Defix's cassette reels switch their Layer FX on there; its speaker cabinets start
  their `getVisBand` timer there), and showing a native window with `orderFront` never touches the
  Wasabi graph. Every visible object in the container's subtree is told, once per actual change
  (`notifyContainerVisibility(containerID:visible:)`)
- **`System.getPlaylistLength()`** — the number of tracks in the queue, answered from the same
  snapshot `PE_Info` is built from so a skin showing both cannot disagree with itself. Phase 30
- **`onTextChanged(newtext)` on host-bound text** — raised when the content of a `display=`-bound
  text, a songticker, or the playlist status line **changes**, including the first time it becomes
  non-empty. Literals never raise it. This is the only signal some skins take that a host readout is
  worth re-reading: Defix writes its playlist `Items:`/`Time:` from a subroutine whose sole caller is
  this handler. Polled from the window controller's host-state hooks plus a 1 Hz beat. Phase 30
- **`<browser>.navigateUrl(url)`** — navigates only the addressed embedded browser through the host's
  scheme policy. A call on a non-browser GUI object is quietly inert. `System.navigateUrl` remains
  denied and cannot launch an application or choose a browser object.
- **`System.getVisBand(channel, band)`** — one spectrum band as a vis byte (0…255), the unit
  `getLeftVUMeter`/`getRightVUMeter` already answer in and the one meter artwork is cut for. `std.mi`
  documents the band range as **0…75**, so a request is resampled into whatever band count the host's
  analyser produces (75 today) rather than indexed straight into it. The source is the one spectrum
  tap every other visualization window consumes (`AudioEngine` → `updateSpectrum` →
  `host.spectrumLevels`); it is **mono**, so both channels answer the same value — a stereo split
  would mean a second FFT for skins alone. Phase 27. **On a decibel scale since Phase 30**: the tap's
  linear magnitude scaled by 255 put ordinary music at the very bottom of the range (measured on
  Defix: mean 4, max 39 out of 255, its 25-frame cone on frame 0 for 96.5% of a track), so the
  magnitude is mapped through `20·log10` over a 60 dB window. Same material after: mean 139, max 232
- **`System.getLeftVUMeter()` / `getRightVUMeter()`** — program level per channel as a vis byte
  (0…255), measured by `WinampModernLevelMeter` as **linear peak amplitude, unsmoothed**, off the
  main thread. **Not the spectrum**, and not a perceptual value: the skin owns the curve and the
  ballistics. Defix maps the byte through `73.813 · x^¼ − 100`, clamps at 0, and applies its own
  attack and decay before it turns a needle, so the host's only job is to hand over the same
  excursion Winamp does. Phase 27.5 → 28 → 29, and each step was a different way of getting the
  *scale* wrong:
  - Reading a peak band out of the bar-display tap (before 27.5) was wrong twice over — that tap is
    mono, so both needles moved together, and its bands are already normalised so bars fill their
    window, so ×255 sat at the ceiling and **every needle in every skin pinned**.
  - Routing it through `PeppyMeterLevelModel` (27.5) wore PeppyMeter's calibration: dBFS over a
    −42 dB floor with VU ballistics, i.e. the same signal compressed and smoothed twice before the
    skin's own curve saw it. The two surfaces want different measurements of one tap, so the `.wal`
    meter now owns its own (Phase 28).
  - **RMS** (28) is an energy average, and Winamp's byte is an excursion. Music that peaks at full
    scale measures 0.05–0.15 RMS; against Defix's own artwork that is the bottom sixth of the sweep
    (0.1 → 34%, 0.3 → 60%, measured with `WINAMP_MODERN_RENDER_VU`), and a mean-square over a whole
    buffer averages away exactly the transients a VU is watched for. **Peak** (29) puts loud material
    at 0.5–1.0, which is the swing the artwork is cut for.
  - **Peak over a whole tap buffer** (29) is nearly a *constant* on dense music — the buffer is
    50–100 ms and something in it is always loud — so the needle then sat high and still. Winamp
    measures a 576-sample vis block (~13 ms at 44.1 kHz), and that is where the dynamics are. Each
    arriving buffer is split into blocks of that length and **played out one at a time as real time
    passes** (29.5), so a skin polling every 17 ms sees successive blocks rather than the same number
    five times over. It costs one buffer of latency, which is what a VU looks like anyway. The
    cadence is taken from the interval between arrivals, because the buffer carries no duration of
    its own and the decimated and streaming paths post different lengths.
  - **Nothing ever said "silence"** (29.5). The tap simply stops posting when playback stops, pauses,
    ends, or moves to a cast device, so the last value stuck and the needles hung wherever the music
    left them. Running off the end of the played-out blocks *is* the silence signal: the last block
    is held for 150 ms to ride out jitter between buffers, and after that the meter reads 0.

  `WINAMP_MODERN_VU_LOG=1` prints the buffer's peak and RMS, the block spread within it, and the byte
  the skin receives — the difference between the last two entries above is visible as `peak` (one
  number for the buffer) against `blockRange` (the spread across it).

  The tap is the shared stereo PCM notification, received with `queue: nil` and measured on the
  posting thread; the main thread only reads the played-out block. Registering with `queue: .main`
  delivers *synchronously* and blocks the real-time audio tap — see `PeppyMeterLevelModel`.
- **`<AlbumArt>.isLoading()`** — whether the current track's cover is still being fetched, from
  `NowPlayingManager`'s real in-flight state; false for a track that already has its cover, for a
  cached miss, with nothing playing, and for any receiver that is not an `<AlbumArt>`. Skins poll it
  from a timer (Defix's playlist window aborted its `ontimer` on the miss every single tick), so a
  stub answering "yes" would be a spinner that never stops. Phase 27
- **ClassicPro shell**: `exploreFile`, `openFile`, `findFiles` (policy below)

**Events dispatched to scripts.** Occurrence counts are call sites across the ClassicPro engine's
`.m` sources, which is the largest measured script corpus.

| Event | Dispatched | From / why not |
|---|---|---|
| `onScriptLoaded` | yes | at `start()`, and per subtree when a runtime group is attached. Object-owned scripts first, then the XUI params, then a skin-level `<scripts>` block — which sits at the end of `skin.xml` and may assume the rest of the skin is configured (Defix's lays out its whole SUI tab strip from the tab labels' `getAutoWidth()`) |
| `onScriptUnloading` | yes (Phase 24) | first thing in `teardown()`, while timers and the graph are still alive |
| `onSetXuiParam` | yes | after `onScriptLoaded`, to the owning XUI instance's own programs only |
| `onResize` | yes (Phase 24) | a canvas change, a layout activation, a divider drag, **and whenever a script's own mutation moves something** (it settles once as the outermost event unwinds); plus one seeding pass after `start()`. Only objects whose own box moved, each with its own parent-relative `(x, y, w, h)`. **Not** from a UI Size change, which moves only the drawing boundary |
| `onPlay` / `onStop` / `onPause` / `onResume` | yes (pause/resume Phase 24) | an explicit transition table: stopped→playing sends `onPlay`, paused→playing `onResume`, playing→paused `onPause`. Never both `onPlay` and `onResume` for one resume |
| `onTitleChange` | yes (Phase 24) | per track, not per redraw — scripts reset per-track state from it |
| `onSetVisible` | yes (Phase 24) | from `show`/`hide`, on the object whose visibility actually changed |
| `onLeftButtonDblClk` | yes (Phase 24) | `mouseDown` with `clickCount == 2` |
| mouse down/up/click/move, `onEnterArea`/`onLeaveArea`, `onRightButtonUp` | yes | with the click's x/y |
| `onVolumeChanged` | yes | `setVolume`, and any change made outside the skin |
| `onPostedPosition`, `onSetPosition`, `onTargetReached`, `onAction`, `onEqFreqChanged`, `onGetCancelComponent` | yes | — |
| `onToggle` | yes | from `setActivated` **and, since Phase 33, from a user click**: a togglebutton flips its own `activated` and then notifies, as in Wasabi. Until then the only sender was a script talking to itself, so a togglebutton a person clicked was inert however completely the skin implemented it — multipass's bottom drawer opens from this event and from nothing else. `setActivatedNoCallback` is the deliberate silent write. A `cfgattrib`-bound control is excluded: the stored preference *is* its state, and it has `onDataChanged` as its route |
| `onActivate(activated)` | yes (B32) | the **indicator's** event, not `onToggle`'s twin: raised whenever a button's activation changes, whoever changed it. Sent from `toggleActivation`, `setActivated` (never `setActivatedNoCallback`), a `cfgattrib` write — and, unlike `onToggle`, a bound control is **not** excluded, because for it the stored preference *is* the activation. A `cfgattrib` write reaches every object bound to that attribute, since a skin declares the same switch once per layout. It had no sender at all before, so no skin could show a toggle's state: mmd3 gives Crossfade/Shuffle/Repeat identical `image` and `activeImage` and does the whole indication with six `ghost="1"` layers at `activated * 255`. 8 of 30 skins declare a handler. A change made **outside** the skin (NullPlayer's Playback menu, a restored session) arrives through `refreshBridgedConfigState()` on `.audioPlaybackOptionsChanged` — an indicator is written once and never polled |
| `onKeyDown(key)` | yes (Phase 43) | a **System** event carrying Winamp's own accelerator **string** — `"alt+g"`, `"ctrl+w"`, `"esc"` — not a virtual keycode, and **lowercase**: two of the three handlers compare without normalising first. Reaches every program whatever window is focused, as in Winamp, which is why a skin that means one window gates on `isActive()`. macOS modifiers map literally (Control→`ctrl`, Option→`alt`, Shift→`shift`, in that order); **Command is not folded onto `ctrl`**, so a ⌘ event is no accelerator at all and the app's menu equivalents keep working. A handler that reaches MAKI's `complete;` consumes the key; anything else falls back to the responder chain. Three of the 17 skins bind one: multipass and winampmodern566 toggle their EQ drawer on `alt+g`, winampmodern566 also shades its playlist on `ctrl+w` and its album-art window on `alt+a`, Defix closes its playlist search line on `esc`. Rika and T800 ship Winamp's stock `playlisteditor.maki`, whose `onKeyDown(Int vkcode)` is the **edit control's** — a GUI receiver and an integer, a different event — and neither loads that program. Drive it with `WINAMP_MODERN_RENDER_KEY` (harness) or `WINAMP_MODERN_DEBUG_KEY` (the app) |
| `onEqBandChanged(band, value)` / `onEqPreampChanged(value)` | yes (Phase 41) | whoever moved the equalizer: the skin's own slider, `System.setEqBand`/`setEqPreamp`, a preset, `EQ_AUTO`, the menu bar, the classic equalizer window, a restored session. One funnel (`refreshEqualizerState()`), dispatching only what changed, driven from every playback-state hook and a 1 Hz safety poll; the first observation announces, so a readout written only from this handler learns its opening value. `band` is 0-based (the XML `param=` is 1-based); `value` is MAKI's −127…127, the scale `getEqBand` answers in — Rika slices a region map at `128 - value`. Every `EQ_BAND`/`EQ_PREAMP` slider's position is synced **before** the events go out, because multipass's eleven `ledfillbar` bars ignore both arguments and re-read their `parentslider` |
| `onDock` / `onUndock` (3 / 3) | **no** | no docked-state model for `.wal` windows |
| `onShowLayout` / `onHideLayout` (2 / 2) | **no** | shade↔normal transitions |
| `onMouseWheelUp` / `Down` (2 / 2) | **no** | the wheel is consumed by the embedded playlist |
| `onCreateLayout`, `onNotify`, `onOpenUrl` (1–2 each) | **no** | minor. `onTextChanged` *is* dispatched — see the bullet above this table |

**Script events callable as methods.** A script may invoke one of its own handlers directly to reuse
it (`slidercb.onSetPosition(slidercb.getPosition())`). Only events with a known arity are callable —
see `dispatchableEventArity` — because the stack cannot be unwound without one. This works for
**system** events too (`System.onEqFreqChanged(freqmode)` in ClassicPro's `eq.m`).

**Arithmetic.** `+`, `−`, `*` keep an Int result an Int; **`/` is always real division**, and the
narrowing happens on the **store** into a declared variable (opcodes 48 and 3), which is where MAKI's
own type system puts it. This is not a detail: every skin writes percentages as `value / 255 * 100`
over two Ints — multipass's seek readout and its `seekTo(length * (pos / 255))`, ClassicPro's
`integerToString(newvol / 255 * 100) + "%"` — and read as integer division *every one of them is
zero*. The symptoms were a seek bar that always sought to 0:00 and a cPro-Bento that reported
`Volume: 0%` at every level. Phase 33.

**Robustness rules** (each earned from a real skin, and each keeping one skin defect from taking down
a whole script):

- A method call on a **null object** is a no-op returning null, as in Winamp — not an abort. MMD3
  checks menu commands from a function that also runs before the menu exists.
- A **member** on a null object reads as its declared type's default and writes nowhere, for the same
  reason. ClassicPro's tab strip opens every click with `closeTab(lastActiveT)`, and on the first click
  `lastActiveT` is NULL while `closeTab` reads `.ID` off it — throwing there meant no tab could ever be
  activated. A member on a non-null non-object still fails closed: the compiler cannot emit one, so it
  means the stack is not what the instruction thinks it is. Phase 24
- `sendAction(action, param, x, y, p1, p2)` is delivered to the addressed object as
  `onAction(…, source)` **as well as** to the host's action handler. It is the channel the standard
  library's own `sendMessage`/`onMessage` pair rides on, so without it every internal script-to-script
  message in a skin was silently dropped. Phase 24
- `setPosition` fires `onSetPosition` **only on a change**. Skins pair two sliders that write each
  other's position from that handler. A **user drag** goes through the same rule (Phase 37): the view
  writes the dragged slider's 0…255 `value=` and dispatches `onSetPosition` with it, so a skin whose
  only feedback is that handler — multipass prints "Balance: Left +40%" on its song ticker from it —
  works under the mouse and not only under a script.
- Event dispatch is **re-entrancy guarded** per (object, event): the interpreter's own call-depth
  budget cannot see native recursion through dispatch, and an unguarded pair overflowed the stack.

**Not supported**

- Any method not in `signature(for:)` — fails closed with `.unsupportedScriptCapability` and is
  recorded in the compatibility report's `unsupportedMethods` bucket
- Unsupported opcodes fail closed; they never become silent no-ops
- **Region set operations** — `Region.add`, `sub`, `stretch`, `copy`, `loadFromBitmap` and the
  `getBoundingBox*` readers. No measured skin calls them; a region is built from one map and used.
  `WindowHolder.setRegionFromMap` and `MouseRedir.setRegion` share the region model but not the
  window-shaping half: a region on a container does not reshape the window

**Never guess an arity.** The bytecode does not encode a call's argument count, so a wrong `signature`
desynchronises the interpreter's stack — silently, and long after the call. `WINAMP_MODERN_RENDER_DISASM`
reads it out instead: the compiler emits the receiver, then one push per argument, then the call, so the
*net* stack effect between receiver and call is the count (mind the binary operators — opcode 64 is `+`,
which pops two and pushes one). That is how `beforeRedock()` and `snapAdjust(x, y, w, h)` were settled.

**Failure granularity.** A method miss aborts *that script event only*; the remaining scripts still
run and the skin loads degraded, with every failure collected into the compatibility report. It
cannot degrade any finer than the event: the bytecode does not encode a call's argument count, so
without a signature the interpreter cannot unwind the stack and must abandon the event rather than
guess. This is why each needed method has to be implemented rather than stubbed.

**Measured demand — cPro-Bento startup.** As of 2026-08-17 (Phase 24): **none.** The target reports
zero error-severity findings and zero unsupported methods at startup, at compatibility level
`degraded`.

**Measured demand — cPro-Bento once its scripts are actually driven** (Phase 24, after `onResize`,
`onTitleChange`, `onPlay` and a tab click). Counts are call sites in the ClassicPro main-window script
set; the whole engine's totals are larger. **Recorded, not implemented** — each would need a host seam
of its own and none is behind a reported symptom. `popAtXY` and `clientToScreen*` were on this list and
came off it in Phase 24; the tab strip's right-click menu (`Show Status Bar` / `Auto Close Tab`) now
opens under its tab, measured with `RENDER_CLICK`, which prints the point the menu is placed at:

| Method | Sites | What it costs |
|---|---|---|
| `parser_addCallback` / `parser_start` / `parser_destroy` | 5 / 4 / 4 | `XmlDoc` callback parsing — the optional `classicpro.xml` extras |
| `enqueueFile` | 5 | the skin adding files to the queue |
| ~~`getTextWidth`~~ | 4 | implemented in B38 — a script measuring a string itself rather than through `getAutoWidth` |
| `playTrack` / `clear` | 3 / 3 | script-driven playlist control |
| `getItemLabel` / `getAttributeName` | 3 / 3 | Guilist accessors — the skin's own list widgets draw empty |
| `getItemFocused` / `setSubItem` | 2 / 2 | the same |
| `getMonitorWidth` / `getMonitorHeight` | 2 / 2 | monitor bounds for placement |
| `getComponentName` | 2 | naming a hosted component |
| ~~`getDecoderName`~~ / `deleteByPos` | 1 / 1 | `getDecoderName` implemented in B38; `deleteByPos` minor |

Across the whole engine (every container, not just the main window) the list also carries the
`Winamp:Browser` events, `setClipboardText` (8) and `shutdown` (1). The `fx_*` family was on this list
until Phase 28 implemented it.

Phase 12 emptied the queue a second time, after `Wasabi:Frame` let the SUI's own scripts run for the
first time: `additem`, `getnumchildren`, `getgroup`, `getcurrenttrackrating`, `oneqfreqchanged` (a
system event called as a method), then `setsize` — plus a *parse* failure, which is worse than a
method miss because it fails the whole skin: opcode 104's immediate is a type offset plus an
"is object" flag, so an object-typed `Member` is `0x0100 | classIndex`, not a value kind.

Getting there took three waves, because each fix let a script run further and reach the next miss —
so re-measure after every change rather than working from a static list (193 methods are *referenced*
across the engine but never reached at startup):

1. `getargbvalue`, `getwidth`/`getheight` (on `Map`), `getitembyguid`, `getposition`, `getscale`,
   `isinvalid`, `setredraw`, `setregionfrommap`, `getdateyear`
2. `delete` (opcode 97) underflowing the value stack — see the note below — then `load`/`exists`
   (`XmlDoc`), `getfilesize`, `getlanguageid`
3. `switchskin`, `getpublicstring`/`setpublicstring`, `getcurcfgval`, `onaction` as a method

> **`delete` is an expression.** The compiler emits `push; delete; pop`, so the delete opcode must
> leave its operand for that discard pop. Consuming it underflowed the stack and killed every script
> that deletes anything — which stayed invisible for eight phases because those scripts aborted
> earlier on a missing method.

**Measured demand — Winamp Modern startup.** Three methods as of Phase 12 (`getgroup` and
`getnumchildren` were implemented for cPro), none of which block the window from rendering:
`clienttoscreenx` (×10), `snapadjust`, `debugstring`.

> A method listed in `signature(for:)` but stubbed in dispatch does **not** appear in either list — it
> looks implemented. `newgroup` hid there and cost the entire Winamp Modern window body. Omit the
> signature instead of stubbing.
- `messagebox` — denied (no arbitrary modal host UI)
- `System.navigateUrl` / `System.navigateUrlBrowser` — sandboxed no-ops; the object-scoped browser
  form is implemented separately
- `newgroup` — **implemented**: expands a registered groupdef as a child of the calling script's group, and starts the scripts the new subtree declares (bounded by the load-time object budget and `maximumRuntimePrograms`)
- Popup menus use an inert command model with an injected presenter
- `getPublicInt`/`setPublicInt` are per-skin namespaced, not truly app-global
