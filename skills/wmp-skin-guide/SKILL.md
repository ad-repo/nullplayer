---
name: wmp-skin-guide
description: Windows Media Player .wmz/.wms skin engine, bounded loading, retained graph, compatibility reporting, rendering, the persistent JScript runtime and host object model, and WMP-specific app-mode integration.
---

# Windows Media Player skin engine

Read this skill before changing `Sources/NullPlayer/WMPSkin/` or
`Sources/NullPlayer/Windows/WMPSkin/`. The current security decisions and locked limits are in
`phase-0-decision-record.md`.

**The script runtime and everything skin JScript can reach is `reference/object-model.md`.** It is
the canonical reference for the persistent `JSContext`, the three member resolutions
(`ok`/`INERT`/`UNRECOGNISED`), element and expression semantics, and how to add a member without
making the demand tally lie.

**Not every skin in the corpus is work.** `scripts/wmp_corpus_exclusions.txt` is the blacklist both
corpus scripts read, and a skin belongs on it when no work in this engine changes its outcome —
`Darkling` is authored against WMP's Party Mode host and draws its own "designed for Party Mode"
panel without one, exactly as real WMP does. An excluded archive never ranks work; see
`reference/harness.md`.

**Measure before you reason.** `reference/harness.md` is the canonical probe and corpus reference —
every env-var flag, the line grammar, `scripts/wmp_skin_census.sh`, `scripts/wmp_render_sweep.sh`,
`scripts/wmp_markup_census.sh`, and the traps those scripts enforce. No other file restates a command; add a flag there in the same
change that adds it. The ranked backlog it feeds is `WMP_TASKS.md` at the repo root, and a closed
entry moves to `docs/wmp-skin/wmp-backlog-archive.md` in the same change that closes it.

**The `phase-*-handoff.md` files are unverified narrative.** Check every claim in them against the
code before relying on it: phase 7 asserts that WMP "remains explicitly unavailable in release/MAS
products through `AppCapabilities.wmpSkinMode`", and `AppCapabilities.supports` returns `true`
unconditionally unless `EDITION_CUSTOM` is defined, which nothing defines. That is a false claim,
not a self-qualified one. The census likewise found their corpus numbers wrong in both directions —
see `reference/harness.md` § "What the harness measured".

## Isolation boundary

WMP is an independent skin engine. Keep engine/model work in `WMPSkin/`, AppKit work in
`Windows/WMPSkin/`, and tests/fixtures under the WMP test paths. Do not teach Classic, Original, or
Winamp Modern types about WMP markup. Change shared application files only when no WMP-owned seam can
satisfy the requirement; keep that seam minimal, gate it explicitly on the WMP controller family,
and prove all existing modes retain their behavior. Record every shared path and the rejected local
alternatives in the phase handoff.

Never put WMP input work on the main thread. Archive validation/inflation, decoding, XML/graph/report
construction, image work, expressions, and script evaluation run on a WMP-owned background
executor — the script context has its own serial queue, so a skin that loops forever wedges that
queue and nothing else. Never use `DispatchQueue.main.sync`. Hand only completed immutable snapshots and typed host
commands to `MainActor`, where the work is limited to AppKit presentation.

WMP owns a dedicated app-authored unskinned player. On a fresh public-release profile with no
persisted mode and before the user has downloaded/imported a skin, launch that WMP view. Missing,
deleted, corrupt, or rejected selections also recover to it while remaining in `.wmp`. Never use an
Original/Classic/Winamp Modern controller, preference, `skin.json`, or artwork as WMP's default or
fallback. Existing users keep their persisted mode.

## Loader contracts

- `WMPPhase0Limits` and stable codes `WMP0001`–`WMP0020` are locked. Production loading must preserve
  their meanings and reject metadata bounds before decompressing payloads. One amendment exists:
  `WMP0005`'s 200:1 ratio is tested only on entries expanding past `entryCompressionRatioFloorBytes`
  (1 MiB), because a ratio is not the quantity a bomb is dangerous in and flat-colour BMPs are not
  bombs — see Amendment 1 in `phase-0-decision-record.md`. It is not a precedent: **never relax a
  limit to make a skin load.** That one held only because the limit was mis-specified against its
  own threat model, and it was argued about the threat rather than about the skins.
- Archive paths normalize Windows separators, use Unicode-composed case-insensitive lookup, and
  reject absolute paths, drive prefixes, traversal, symlinks, collisions, excess wrapper depth, and
  CRC failure. The provider is read-only and never extracts to disk.
- A skin contains exactly one unambiguous `.wms` at root or under one wrapper directory. Resources
  resolve relative to the declaring file and then the skin root, never outside the provider.
- Text decoding is BOM-aware UTF-8/UTF-16LE/UTF-16BE, then a **positional** BOM-less UTF-16 sniff,
  then a deterministic Windows-1252 fallback for unmarked legacy WMP text. Do not guess other ANSI
  code pages, shell out to `iconv`, accept malformed surrogates, or allow embedded NULs.
- XML is parsed by a hand-rolled lenient parser, **not** `XMLParser` — libxml2 aborts on a duplicate
  attribute before the delegate runs, which rejected 4 of 14 archives. It retains authored
  tag/attribute spelling, **attribute document order**, and source locations while bounding depth and
  node count. Unknown elements stay in the graph for compatibility reporting.
- `reference/loading.md` is the contract for both: what is tolerated, what stays fatal, and the two
  things (attribute order, CR-only line endings) that look cosmetic and are not.
- Attribute parsing classifies expressions, bindings, handlers, colors, and resources without
  executing skin code. `res://` and optional missing artwork warn; path escapes and required missing
  scripts fail.
- Graph IDs and registry order are deterministic. Duplicate authored IDs are retained and warned,
  not silently collapsed.

Skin JScript runs in one persistent in-process `JSContext` per skin session, on a WMP-owned serial
queue, with the object model as the security boundary — see Amendment 2 in
`phase-0-decision-record.md` for why the helper process was retired and what that costs. An in-app
`WKWebView` remains prohibited.

## Static scene and image contracts

- **A view is sized like any other node: authored literal, then script override, then the natural
  size of its own `backgroundImage`.** WMP skins routinely author `<VIEW backgroundImage="...">` with
  no width or height — the window *is* the bitmap — and demanding a positive literal at the root was
  the largest single cause of a skin that loaded and then drew nothing (89 views across 48 skins).
  The same artwork fallback already applied to every non-root node. **A view with no size and no
  artwork of its own is then sized by the union of the subtree it can place from literals and
  artwork alone** — `iconic` hangs its whole player off one `<SUBVIEW backgroundImage="base.gif">`.
  That union descends into a container whose own size is unknown and ignores `visible`, because a
  skin authors every wrapper hidden and turns one on in `onLoad`. Anything needing script
  contributes nothing, and the builder never invents geometry.
- **A view with nothing to draw is `0x0`, not a rejection, and a literal or scripted zero is an
  authored answer.** A `.wmz` names views that are never windows: 25 corpus skins author a
  `controlView` holding only `<player>` and a hidden `<video>` so an `onLoad` can run with host
  bindings and no window, and `pharaoh` writes the same idea as `<view id="vGhost" width="0"
  height="0">` whose handler redirects. Rejecting them was the last of `WMP0032`. The builder still
  invents nothing — the honest size of empty content is empty — and **`WMPMainWindowController` is
  what refuses to make a window out of it**: initial load walks its candidate list (persisted view,
  then `vPlayer`, then document order) running each view's script and following its `setCurrentView`
  until a view has a canvas, and `switchView` runs a windowless view's script, honours its host
  commands, and stays where it is. `WMPRenderer` still refuses a non-positive canvas; a zero-area
  scene must never reach it.
- **`theme.openView` opens a view; `theme.currentViewID` replaces one; this app has one window, so the difference is a return path rather than a second window.** 57 of 180 archives ask for a panel by name this way. `openView` is its own host command: the controller presents the view and remembers the one it covered, and `closeView` pops back to it instead of ordering the window out — without that, opening a settings panel is the W46 trap with no way home. `openViewRelative` is deliberately still unimplemented (W50): its offset is meaningless with one window, and aliasing it would drop the offset silently. See `reference/object-model.md`.
- **A view arrived at by a switch loads exactly like one arrived at by launch, and a `.wmz` compact mode is built entirely out of that.** `switchView(to:)` raises `load` on the new view, applies the host commands the handler posts — *after* `apply`, which sets the view timer from markup, so the script's `setViewTimerInterval` is the override and not the other way round — and schedules its `timerRequests`. It did none of the three for a long time (W46), and Corona's `viewTiny` is authored `timerInterval="0"` and animates itself into the mini player from `OnTinyLoad` alone: the switch happened, nothing ran, and the compact view drew **the same artwork at the same size as the player**. The only visible symptom was the playlist and equaliser drawers going away, because `viewTiny`'s markup does not have them. Two consequences bind: the initial-load `collapsed` guard applies here too, since a view can now blank itself in an `onLoad` this path finally runs; and `viewchange` is dispatched only when the markup authors a handler, because a transaction's `timerRequests` are what *that* transaction registered and an unconditional binding-only one posts an empty set that cancels what `load` just scheduled.
- **The skin's own JScript is ES3, and `JSContext` is not — `WMPJScriptDialect` is where that is reconciled (W86).** WMP9's `corona_tiny.js` chains its compact-mode animation by appending a timer event to the array its `TimerDispatch` is enumerating with `for-in`. JScript visits the appended index; JavaScriptCore snapshots and does not, so the chained event was dropped on the tick it was registered and the whole WMP9 family could neither collapse its video panel nor get back to `vPlayer`. Corona's 2002 script splices the array instead and is unaffected, which is what made `corona` the control and `9SeriesDefault` the case. The rewrite is bounded, skips strings/comments/regex literals, and leaves a program with no `for-in` byte-identical; **3 of 180 archives use `for-in` at all and one depends on the live semantic**, so the corpus sweep is the proof it changed nothing else. **Before ranking a "the script runs and nothing happens" defect, ask whether the handler depends on an ES3 semantic** — no headless probe here can see that class, and the live `INPUT script-diag` line stays silent because nothing throws. And when you add to this file's scanner: **test a CRLF fixture.** Swift folds `"\r\n"` into one `Character` that is not `"\n"`, and the first version of the rewrite silently did nothing to the entire corpus for that reason while every LF-only unit test passed.
- **A `<property>_onchange` fires in the same transaction as the write that triggered it, and the view's `JScript:` geometry expressions are *not* re-run to achieve the same thing.** A `.wmz` animates by writing geometry once per timer tick, so a pane positioned off a moving one has to move in the same frame; letting it catch up on the next transaction tore the compact view into two visible halves that closed four seconds later (W87). Only what the skin declared is raised — 16 geometry `_onchange` attributes across 6 archives — bounded and once per property per transaction, so two panes positioned off each other cannot loop. **Re-resolving the expression set after the handlers is the tempting general form and it is wrong**: those attributes are an initial layout rather than a live binding, and several read the property they write (`left="JScript:svBottomLeft.width-left"`), so re-running them moved 175 of 545 corpus images and shattered `Back to the Future Trilogy`'s `videoView` and `ALXMorph`'s frame. That is what a sweep is for; it was reverted on the measurement, not on taste.
- **A zero geometry override is a value, not an absence.** Every skin with a store-thumbnail
  `previewView` collapses it in `onLoad` — `view.width = 0; view.height = 0; view.backgroundImage =
  ""; theme.currentViewID = "controlView"` — and Microsoft's own `auto.js` in `Official_Xbox_XP`
  does it with a comment saying so. Discarding a `0` override as "not positive" left 34 corpus
  skins showing a static splash bitmap where the skin had asked for its player.
- **A node draws the artwork a script last gave it, not the one its markup declares.** Images were
  the one property class the script-override path skipped, and `Alienware Invader` — whose whole
  player is behind a 568-frame intro of `mainBack.backgroundImage = "png24/intro_anim_f<N>.png"` —
  drew nothing at all because of it (W75). An override is an authored path string and resolves under
  the same provider rules as markup; one the skin does not contain warns and leaves the authored
  artwork in place; `""` clears the property the way an absent attribute does. The rules and the
  traps are in `reference/object-model.md` § *What a property read answers, and who wins*.
- `WMPSceneBuilder` resolves literal geometry plus the bounded static initial-layout grammar in
  `WMPInitialLayoutExpression`: finite numbers, parentheses, arithmetic, and geometry reads from
  deterministic IDs. `wmpprop:` is accepted only as an alias for that same geometry grammar.
  Calls, assignments, statements, script globals, ambiguous/unknown IDs, cycles, and excessive
  dependency depth stay unresolved *for the scene builder*, which never executes skin code and never
  invents fallback geometry. The general path is the live context in `WMPScriptRuntime`, whose
  resolved values arrive as scene overrides; the static grammar remains the fast, script-free
  evaluator the builder uses before any transaction has run.
- Scene coordinates remain top-left throughout layout, clipping, dirty bounds, hit metadata, and
  paint commands. Core Graphics conversion happens once in `WMPRenderer`; images and text each use
  an explicit counter-transform so pixels and glyphs remain upright.
- The immutable scene owns no `CGImage` or cache state. `WMPImageStore` performs bounded ImageIO
  metadata/decode off-main, supports BMP/GIF/JPEG/PNG, and uses a byte-bounded LRU keyed by canonical
  resource path plus color key.
- **ImageIO is stricter about BMP than Windows is, so a `.bmp` it refuses falls back to
  `WMPBitmapDecoder`** — never to a failure the user sees as a blank skin. Nine of the corpus's
  3,687 bitmaps are rejected by ImageIO alone: eight set `biClrImportant` while `biClrUsed` is zero
  (Windows reads the palette size from `biClrUsed` and treats the other as advisory), and one is a
  BI_RLE8 stream that walks clean and is refused anyway. The fallback runs *only* after ImageIO has
  failed, under the same dimension/pixel/byte bounds, applied before it allocates — an oversized
  bitmap still fails `WMP0034`. Do not "fix" such a file by patching its header, and do not relax a
  limit to admit one.
- **A mapping mask is authored top-left, and the render CTM is y-flipped, so clipping through one
  needs the same counter-flip `drawImage` applies.** `WMPRenderer.clip(to:mask:context:)` owns that;
  it undoes the CTM by hand rather than with `restoreGState`, which would discard the clip too. A
  mask fixture split left/right cannot see this class of bug — split it top/bottom.
- **A node keys out every colour it declares, not one.** `transparencyColor` and `clippingColor` are
  both keys — the second is the colour WMP cuts out of a subview's own artwork to shape it — and a
  subview routinely carries both with *different* values (`Alpine7618_v09` keys `#FF00FF` and
  `#FF0033`). 103 of the 180 archives author clipping attributes, so an engine honouring one key per
  image paints the other as a flat slab over most of the window. `WMPSceneImage.colorKeys` is
  therefore a list, in authored order, and the image-store cache key contains all of it. Color keys
  compare exact un-premultiplied RGB and clear only matching pixels. Preserve the source alpha of
  every non-matching pixel.
- **A node that declares no key at all still gets one: magenta, whatever alpha the sprite carries.**
  WMP's implicit transparency colour (W78, W78a). The corpus is authored against it — 4,979 of its
  6,076 `transparencyColor` declarations (82%, 142 skins) are `#ff00ff`, `Halo 2` keys three
  siblings by hand and leaves `m_trans_no.png` to the default, and `Main_Street` authors one key in
  the whole file. The scene builder decides (`WMPSceneImage.implicitColorKey`, set only when the
  node declares nothing) and the image store applies it. **The sprite's own alpha channel does not
  veto it, and W78 shipped believing it did.** The reasoning was that a PNG or GIF which authored
  transparency has already said what is see-through; the corpus says the alpha channel is an export
  format instead. `scripts/wmp_implicit_key.py --alpha only` measures the complement — 76 references
  across 21 skins and 62 sprites — and **11 of those nodes carry two states of the same button, one
  exported without an alpha channel and one with, holding pixel-for-pixel identical magenta**
  (`Half-Life_2` `m_pause_no.png`/`m_pause_hov.gif`, both 1,394; `Harry_Potter…`
  `bottomgroup_no.png`/`bottomgroup_hover.gif`, both 5,866). Under the veto the normal state keyed
  and the hover state did not, so the button turned magenta under the pointer. **Never pass the
  implicit key on a mapping image, position map or clipping mask**: they are read for their colours,
  and keying one deletes a `#FF00FF` mapping colour from its own map. Measure the class with
  `scripts/wmp_implicit_key.py` before touching the rule; the default removed 315,157 magenta pixels
  across 87 corpus views, and dropping the alpha veto took the corpus residual from 7,253 px across
  15 views to 878 across 2, changing 13 PNGs and nothing else.
- The opt-in render dump writes one untracked PNG per view plus a JSON report. Corpus paths and
  output directories are local inputs/artifacts and must never be staged.

## Phase 3 app integration contracts

- WMP maps to its own `PlayerUIControllerFamily.wmp`; it is neither Classic nor a
  `ModernSkinFamily`. Keep capability and menu exposure DEBUG-only until the public-exposure phase.
- `WMPSkinImporter` owns `Application Support/NullPlayer/WMPSkins`, complete pre-commit validation,
  same-directory atomic replacement, installed enumeration, and the `wmpSkinName` / view selection
  keys. A failed replacement must leave both the installed archive and selection usable.
- `WMPMainWindowController` must first present `WMPUnskinnedMainView`, then swap in only a completed
  static WMP scene. Missing/corrupt selections stay in WMP with an actionable diagnostic. Main-window
  fallback must never instantiate or consult Classic, Original, or Winamp Modern skin machinery.
- Persist WMP skin/view identity separately. Restore WMP geometry only when the exact mode, skin,
  and view match; preserve top-left position safely and do not apply shared UI scaling.
- Teardown is synchronous and idempotent: cancel WMP tasks, clear callbacks and images, then release
  scene, archive, and image-store ownership before the controller is discarded.
- NullPlayer-owned native windows exposed in WMP mode must be hosted in WMP-owned chrome derived
  from the active `.wmz`: borders, colors, title/window controls, metrics, resize affordances, and
  docking treatment. Never fall back to another skin family's controller or chrome. Until a window
  has a WMP host, hide or disable it; missing skin chrome uses only an app-authored WMP-neutral
  fallback.

## Debugging a live defect

Read **`skills/live-ui-testing`** before diagnosing anything that only reproduces on screen, and the
process section it points at — `winamp-modern-skin-guide/reference/harness.md`
§ *Debugging a live defect* — which is the reference implementation of that workflow. The 2026-09-07
session that produced the fixes below spent hours rediscovering five rules already written there.

**The reproduction loop itself is `reference/harness.md` § *Driving the app*** — select the skin,
launch the debug build with `WMP_TRACE_INPUT=1`, ask `WMP_RENDER_PROBE` where the control is and
click that frame with a `CGEvent`, then read the trace and capture the window. Three of the four
defects in the compact-mode report were app-path defects a render sweep can never see, and each took
one launch once the loop existed. The same section carries the two things that decided those fixes:
how to reduce a skin's own script to a standalone `JSContext` repro, and why a fix that closes the
report while moving images elsewhere in the corpus is the wrong fix.

The ones that cost the most, in WMP terms:

- **Number the transactions before theorising about one.** Two rounds of inference off the raw
  `INPUT` trace named the wrong cancellation check for W88 and produced a fix that was a no-op; one
  temporary `txn <n>` pair named the right one in a single launch. `reference/harness.md`
  § *Driving the app*.
- **A green corpus sweep used to say nothing about AppKit; now it says one thing.**
  `WMP_RENDER_APPKIT=1` runs the real `NSView.draw` of the view and every overlay over it and diffs
  it against a second pass with the overlays hidden. **Start a live report here**: if the view diffs
  to zero, the defect is not the overlays and not compositing, and the scene is where to look. It
  cleared `ALXMorph/mainView` in one run. What it still does not reach is the window's shape and
  shadow (the window server), hover, a timer and live playback — W73.
- **Compare `WMPRenderer`'s own image against a screen capture of the same window rect.** Agreement
  means the defect is in the scene; disagreement means it is in the overlays or compositing. That one
  comparison ended the hunt, and `WMP_RENDER_APPKIT` is that comparison made automatic and
  corpus-wide. **Do not do it by hand against a raw screen capture unless you have to**: the two
  images go through different colour spaces, and reading that difference as a defect is what
  reported 6.8% of the *control* skin as broken.
- **A probe scoped differently from the engine reports the difference as a defect.** Both geometry
  evaluators are scoped to one `VIEW`; the `EXPR` probe walked the whole graph, so every other view's
  expressions were printed under this view's name and refused by an evaluator that could not answer
  them. That read as *82% of the corpus's expressions never reach the live evaluator* — 34,314 rows
  — and cost a whole handoff, whose worked case turned out to be a `plView` node quoted under
  `mainView`. Scoped the way the engine is, the corpus reads **7,569 / 7,569**. Before believing a
  probe about a population, check it is asking the same question the engine answers;
  `reference/harness.md` § *After the cascade* has the numbers and the check that holds it.
- **Expressions are not what starves a view.** `starved.tsv` did not move by one row when the above
  was corrected, and `Cablemusic/mainview` — 63 unresolved nodes — declares no geometry expressions
  at all. A high `unresolved` ratio also does not mean a blank window: two of the three worst-ranked
  views render substantially. See W68 and W75.
- **A ratio, not a count, ranks a starved view.** `unresolved > 0` is true of most views in the
  corpus, including corona's. `starved.tsv` from the census is the ranking; a raw count ranked
  nothing and hid ALXMorph for three phases.
- **Confirm the skin *and the view* before diagnosing.** `wmpSkinViewID` is persisted on every
  present, and Corona's compact view renders almost identically to its player.
- **"The wrong button responds" is two questions, and the harness answers one of them for free.**
  Scan the control with `WMP_RENDER_CLICK` and decode its mapping image independently: if every hit
  *and* every miss lands where the map's colour bands are, hit testing is exonerated and the defect
  is in what gets painted (W47 was a mirrored mask clip). Doing that first turned a vague live report
  into a one-line fix.

## Presenting a skin in a window

Learned by driving the real app on 2026-09-07, after a headless sweep said everything was fine. Each
of these was invisible to the harness and visible in the first minute of live QA.

- **A skinned WMP window carries no macOS shadow.** It is genuinely shaped — Corona is transparent
  across the 250 px its playlist slides into and the 124 px its equaliser drops into — and AppKit
  caches a borderless window's shadow from whatever content it last saw. On a shape that changes with
  every drawer and every repaint that goes stale, and a stale shadow over a transparent region reads
  as a dark box the size of the window. `invalidateShadow()` on each present fixed it, then on each
  frame change fixed it again, then playback's continuous repaints brought it back a third time. So
  `hasShadow` is **off** while a skin is shown and on for the opaque app-authored player. There is no
  drop shadow in Windows Media Player to lose.
- **A script transaction repaints in full.** The dirty region cannot be derived from what a handler
  *wrote*: it writes `svEqualizer.top` and a whole subtree moves that it never mentioned, and a
  `SUBVIEW` carries no hit metadata at all, so the narrowed bounds collapse to roughly the button
  that was clicked. Partial repaints belong to hover and slider drags, where only artwork state
  changes — and there the dirty rect must union the **old and the new** frame of every node whose
  geometry moved. Unioning only the old one erases correctly and paints only the overlap; unioning
  neither never erases, and a closed drawer stays on screen forever.
- **A new scene needs a layout pass.** The AppKit overlays are positioned in `layout()`, which AppKit
  will not run just because a scene arrived, so an equaliser the skin slid away keeps its old frame.
- **The overlays are not in the dumped PNG.** The renderer draws the scene; playlist, equaliser,
  popup, effects and video are `NSView`s hosted over it, and `WMPVideoPlaceholderView` and
  `WMPEffectsSurfaceView` both paint an opaque background. A skin can dump a perfect frame and look
  wrong on screen. `WMP_RENDER_PROBE`'s `WIDGET` line reports where the scene put them, and
  **`WMP_RENDER_APPKIT` is what actually runs their `draw(_:)`** — it hosts the scene in a real
  `WMPMainView`, `cacheDisplay`s it twice (once with the overlays hidden), and reports what the
  AppKit layer added. `outside=` is the number that ranks: an overlay inside its own widget frame is
  the hosting working. Corpus-wide that is **two views in one skin** (W74), which is the whole of
  this class in the default state. The overlays still ignore `WMPWidget.clipRect`, which is what
  W74 is.
- **An overlay fills `bounds`, never `dirtyRect`.** AppKit is free to hand a view a dirty rect
  larger than itself, and it does: the 320x240 `WMPEffectsSurfaceView` was called with
  `{{-269, -26}, {596, 468}}` — the whole window in its own coordinates — and a layer-backed view
  does not clip that (`masksToBounds` is false). `dirtyRect.fill()` therefore painted the spectrum
  pane's translucent wash over the entire skin, reported as "a giant black box over the player".
  Both `WMPEffectsSurfaceView` and `WMPPlaylistSurfaceView` had it. It only appears once the overlay
  exists, and the overlay only exists after a skin reload with a track playing, which is why it read
  as "switching skins causes it".
- **The selected view is persisted on every present, and Corona's route into its compact view is an
  unnamed button inside the equaliser drawer.** Land in `viewTiny` and it is restored on every
  launch; it also renders almost identically to `vPlayer`, so there is no visual signal that it
  happened. Confirm skin *and* view before diagnosing anything in this engine.

- **`.wmz` mode must offer a route to a track.** The auxiliary NullPlayer windows stay hidden here
  until they have WMP-owned chrome, so the skin's own Open button — `theme.openDialog('FILE_OPEN')` —
  is the only one. Before it was implemented the only way to start playback was to leave WMP mode and
  come back, which is not a mode.

## Phase 4 input and transport contracts

- `WMPMappingImage` stores canonical, un-premultiplied RGB plus alpha in authored top-left row
  order. Alpha-zero and unregistered colors never hit. Sample by scaling the original unclipped
  control frame into mapping pixels; apply inherited clipping as a separate hit-test gate.
- Mapping-image child bounds are only rejection/dirty metadata. Irregular regions may have empty
  corners inside their bounding box, so activation always samples an exact pixel. Cache mapping
  buffers through `WMPImageStore` with a byte bound and a key containing canonical path plus the
  color-to-node assignment.
- `WMPHitTester` walks reverse z/document order. Mapped unknown/transparent pixels fall through to
  lower controls; disabled controls do not intercept input. Window dragging is reached only after
  interactive hit testing returns no target.
- Mouse capture belongs to the pressed node until release or cancellation. Activation requires an
  inside release on that same node. Seek/volume/balance continue tracking while captured; scan
  commands always stop on release, cancellation, or teardown.
- Normal, hover, down/sticky, and disabled artwork selection is resolved off-main by rebuilding an
  immutable scene. AppKit invalidates only the union of changed control frames while retaining the
  full last rendered image.
- `WMPHost` is a main-actor, typed command/snapshot boundary. `WMPAudioEngineHost` clamps all numeric
  values and exposes metadata, time strings, playlist position, command-enabled state, shuffle,
  repeat, mute, volume, and balance without exposing `AudioEngine` to skin code. JScript remains
  disabled; Phase 4 recognizes semantic transport elements and only a small exact allowlist of
  literal transport statements.
- Both the skinned and app-authored unskinned WMP players use this same host. Custom-drawn controls
  publish accessibility children with stable `wmp.*` identifiers.

## Script, expression, and binding contracts

- `WMPScriptRuntime` is the only production route for skin JScript: one persistent `JSContext` per
  skin session, one transaction at a time, expressions then handlers. `reference/object-model.md`
  is the contract for what it exposes; do not add a member without reading its rules.
- A skin's programs evaluate once per session, **after** the view's elements are installed as
  globals and the host objects are bound, because skins run top-level code that touches both.
- Fail closed per handler, never per session: an unrecognised member aborts that one handler and is
  tallied as measured demand. There is no session-wide script kill switch — a skin puts its whole
  startup in one handler, and a kill switch makes that invisible rather than visible.
- **An inert member that answers a constant is still a phantom.** `mediacenter` was the largest
  cause of a dead handler in the corpus — 159 `ReferenceError`s across 110 of 179 archives (W37) —
  and every one of its nine members is honestly `inert()`: there is no video surface, one effect
  with no type and no presets, no high-contrast mode. But skins *round-trip* these, writing
  `mediacenter.effectPreset` in one view and reading it back in another, so an inert member stores
  session state and answers what was written. A constant looks identical from every instrument and
  is wrong. See `reference/object-model.md` § `mediacenter`.
- **Closing the biggest row raises the ones behind it, and the capture must show both.** W37 took
  the runtime error class 252 → 127 while distinct causes went *up*, 41 → 55: handlers that died on
  their first missing member now reach their second. Never read one row falling as progress without
  re-measuring the whole table in the same capture, and never read lost pixels as a regression
  before finding the statement that hid them — a script that finally runs is a script that finally
  hides panes. `reference/harness.md` § *After W37*.
- **A host command is the script's output, not the drawing's, and it is applied when the
  transaction returns rather than after the scene is presented (W88).** The build and the render are
  the slow half of a transaction, so a view timer that fires during them cancels the task — right
  for the drawing, because a newer transaction is already building a newer scene, and it used to
  discard the commands with it. `Alienware Invader` is what that cost: its 568-frame intro ends on
  the heaviest tick in the skin — `toggleShutter()` swaps `mainBack` to `main_back.png`, turns
  `mainBackGroup1` on and posts `view.timerInterval = 0` — and building that one frame decodes the
  whole player's artwork, overrunning the 50 ms period. The reveal was never presented and the `0`
  never applied, so the timer kept firing with the skin's own `introStatus` now true and the very
  next tick took the *other* branch of `toggleShutter()`, closing the shutter it had just opened.
  Reported live as "it opens to reveal the controls and then closes and stops responding".
  **A transaction that has returned from `transact` has already committed its writes to the runtime,
  so anything downstream of it is not optional.** A command that switches views owns everything
  after it, so this transaction's scene is abandoned rather than drawn over the new view's.
- Authored handlers are selected **per view**. A `.wmz` declares every view in one file, so an
  unscoped scan runs another view's `onLoad` against elements that do not exist in this one.
- Expression reads form a per-view dependency graph. Resolve in stable topological order and commit
  one immutable scene. Missing/ambiguous IDs, cross-view reads, cycles, non-finite values, negative
  sizes, and depth/pass overflow never partially update the visible scene.
- Resizes evaluate from proposed view dimensions off-main. AppKit keeps drawing the last scene until
  the resolved replacement is complete; never synchronously rendezvous with script work.
- `WMPObservablePropertyRegistry` owns both `wmpprop:` and `wmpenabled:`. Coalesce host snapshots,
  retain committed values across batches, and tag origins so script echoes cannot create feedback.
- Host timers enforce the Phase 0 count and period limits. Preferences are bounded and namespaced by
  the SHA-256 of skin archive contents; reset only the active skin namespace.
- Dispatch authored handlers in document order. Host changes use open, play, status, mode,
  buffering, then reception order; input uses mouse-down, mouse-up, click/change semantics from the
  Phase 4 capture model.
- **Hover is two events and a gate.** Crossing from one control to another raises `onMouseOut` on
  the node left *before* `onMouseOver` on the node reached — a skin that fades a readout in on entry
  never fades it back out otherwise — and nothing is raised while the pointer stays inside the same
  node. Unlike every other dispatch site, a hover edge runs a transaction **only where the markup
  authored a handler for it** (`WMPMainWindowController.hoverEvents`): the pointer crosses a whole
  row of buttons on the way to the one it wants, and a transaction rebuilds and re-renders the
  entire scene. Hover *artwork* is unaffected by any of this — it never went through script.
  Measure it with `WMP_RENDER_HOVER`; `onmousemove`, `ondblclick`, `onfocus` and `onblur` are the
  same shape and still unraised.

## Drawing the skin's own controls

- **The skin draws its controls; an AppKit overlay is only for what the scene genuinely cannot
  paint.** What is left hosted is `PLAYLIST`, `DROPDOWNPLAYLIST`, `EFFECTS` and `POPUP`. `VIDEO`
  is not: its placeholder filled every `<VIDEO>` frame with opaque black over the artwork of 166 of
  177 archives, and an audio player has nothing to put there instead. Adding an overlay back needs
  the same argument — name what the renderer cannot draw.
- **A slider is a track plus a thumb the scene places**, and `WMPSliderMetrics` owns that geometry
  alone so each of its rules is testable: `borderSize` is dead track at *both* ends (171 skins),
  a **vertical** slider's maximum is at the **top** (1,312 of 1,968 `direction` attributes are
  vertical — every equaliser band is one), and the same metrics read the pointer back so a drag runs
  along the axis the skin authored. `foregroundImage` is the filled part of the track, cropped
  rather than scaled, and `useForegroundProgress="true"` (46 skins) redirects that fill to
  `foregroundProgress` — a buffer bar behind a thumb showing position, which are different numbers.
- **A `.wmz` says where a slider writes by binding its value, not by choosing a tag.** 163 skins
  author a plain `<SLIDER value="wmpprop:player.settings.volume">` rather than `<VOLUMESLIDER>`, so
  `WMPTransportAction.boundAction` maps the declared `wmpprop:` path to the action. Adding a bindable
  host property means adding it to `WMPObservablePropertyRegistry` *and* deciding whether writing it
  back is an action — one without the other is a control that moves and does nothing.
- **`EQUALIZERSETTINGS` is a settings object, not a control.** 163 skins author it and none give it
  geometry; the skin's own ten bound sliders *are* the equaliser. It is `isNonLayout`, like
  `<player>` and `<network>`.
- **`alphaBlend` is 0-255, inherits down the subtree, and 717 of its 778 corpus uses are `"0"`** —
  an element the skin hides and fades in later. A zero-alpha node still lays out, so its geometry
  stays readable, but it must not reach the command list at all: leaving it there put invisible
  artwork inside `visibleBounds` and every dirty rect derived from it. Honouring it changed what
  several skins draw, because the engine had been painting the topmost of eight stacked shells
  rather than the one authored visible — and it makes `alphaBlendTo` (W38) load-bearing, since a
  skin that fades its own panels in now shows less until that lands.
- **`passthrough="true"` (82 skins) is drawn and never hit.** A decorative overlay registered as a
  hit target swallows the controls beneath it.
- **`TEXT` reads `fontFace`, not `fontType`** — 109 skins against 21 — and `fontStyle` is a *set*
  (`"UNDERLINE, bold"` is authored), not one word. `fontSmoothing="false"` (95 skins) is a readout
  drawn as pixels; antialiasing it turns a 6 px digit into grey mush.
- **A `CUSTOMSLIDER` is the size of its `positionImage`, and its `image` is a filmstrip.** This was
  read out of the art rather than assumed, and `WMPPositionMap` carries the evidence:
  `ALXMorph/seek_map.png` is 86x10 whose columns step 0, 2, 5 … 252 — a **greyscale ramp whose
  luminance is the fraction** — against a `seek.png` of 86x600, sixty frames stacked vertically;
  its `volume_map.png` is a 72x38 arc against a 2232x38 strip of thirty-one frames laid out
  horizontally. So the strip's axis comes from whichever one is a whole multiple of the map, the
  value picks the frame, and a drag reads its value out of the map — which is the whole point of the
  element: its track need not be a straight line. Sizing one from `image` makes it 2,232 px wide.
- **`clippingImage` shapes an element, and it is what makes a shaped window shaped.** 25 skins
  author a non-empty one and every one of them declares a `clippingColor` beside it, which is what
  the mask keys out. Before it, `TDK`, `elvis`, `Secura`, `portals` and the six `US *` service skins
  all drew a black or grey rectangle behind their round artwork.
- **A mask buffer's row zero is the authored top row.** A `CGImage` drawn into a bitmap context
  arrives that way round — `WMPMappingImage` says so in as many words — so "correcting for
  CoreGraphics" by reversing the rows mirrors the mask and clips the half it should keep. That is
  W47 arriving by a second route, and only a **top/bottom** fixture can see it: a left/right one is
  identical under a vertical flip, and so is a horizontal position ramp.
- **`cursor` names a shape, not a file, in 2,246 of its 2,319 non-empty uses.** Classifying them all
  as artwork made every named cursor a *missing bitmap* (`BITMAPS … missing=hand sizenwse` across
  145 skins) and hid the name from the builder, which reads literals. `WMPAttributeParser` decides
  from the value; the ~70 `.cur`/`.ani` files stay resources and resolve to no cursor (W67).
- **Animation lives in the renderer, not the scene.** `WMPRenderer.render(clock:)` picks the frame,
  so a 10 fps GIF costs a re-render rather than a rebuild — a rebuild runs the skin's script
  transaction, which must not happen ten times a second. 90 of the 180 archives carry a multi-frame
  GIF (2,166 files). `animationCadence(for:)` gives the repaint loop its period *and* the union of
  only the animated frames, because repainting a whole window for one blinking LED is the difference
  between a skin that animates and one that burns a core. **A render dump is a still, so without
  `WMP_RENDER_CLOCK` an animation is unfalsifiable** — frame zero looks exactly like an engine that
  never animates.
- **A `<POPUP>` is an equaliser preset menu and its items come from the skin's own script.** All four
  corpus popups call `appendItem` in an `onLoad` and apply the choice through
  `eq.currentPreset`; `WMPScriptOutput.listItems` carries them out of the transaction, because the
  markup names none of them. The four hardcoded entries that used to be shown were in no skin.
- **An `<EDITBOX>`'s `value` is a string.** Nine of the corpus's ten are `plSearchEdit`, a playlist
  search field whose `onKeyUp` reads it straight back, so it needs its own text path
  (`setWidgetText`) rather than the numeric `setWidgetValue`.

## Phase 6 widget and view contracts

- `WMPScene.widgets` is immutable semantic metadata for accessibility and native surfaces. AppKit
  overlays are created only after a completed scene arrives and are replaced with the scene.
- Playlist snapshots are capped at 4,096 rows. Selection, scrolling, play, removal, and movement use
  typed host actions; scripts receive plain copied item values, never `Track` objects.
- WMP exposes ten EQ gains. `WMPAudioEngineHost` uses `EQBandRemapper` at the boundary when the live
  engine is in its 21-band layout; every write remains clamped to ±12 dB.
- `WMPEFFECTS` hosts the safe WMP bars surface. Its single ref-counted spectrum consumer must be
  registered only while an effects surface exists in the active view and removed on switch/teardown.
- `VIDEO`/`WMPVIDEO` draw nothing — the placeholder that painted them opaque black over the skin's
  own artwork is gone (W9). WMP plug-ins, ActiveX, DLLs, and arbitrary media surfaces remain denied.
- A view switch cancels capture and outgoing timers, stops continuous commands, clears view-local
  overrides, resolves off-main, preserves safe top-left, applies per-skin/view size, atomically swaps
  scene/native/accessibility state, then dispatches the view event.
- Auxiliary NullPlayer windows stay hidden in WMP mode until they have WMP-owned chrome. Never expose
  them through another skin family's provider or artwork.

## Verification

Use the committed original fixtures in `Tests/NullPlayerAppTests/Fixtures/WMPSkin/`. Run focused WMP
tests first, the user-supplied `WMP_TEST_WMZ` corpus check when available, then full `swift test` and
`git diff --check`. Do not commit third-party skins or build a DMG unless the user requests it.

## Phase 8 public exposure contracts

- The full edition supports `.wmp` in debug and release builds. A custom edition still decides
  through `EditionPolicy`; do not bypass that capability seam.
- `PlayerUIMode.stored(in:)` defaults to `.wmp` only when neither the current mode key nor the legacy
  `modernUIEnabled` key exists. Every persisted four-mode choice and both legacy Boolean values are
  upgrade inputs and remain authoritative.
- Keep `-uiMode wmp -wmpSkinPath /absolute/skin.wmz` available in packaged builds as a diagnostic
  launch hook. It imports through the production bounded importer and grants no direct file access to
  skin script.
- Public UI owns import, installed-skin selection, selected-skin removal, authored view selection,
  unskinned recovery, and bounded JSON compatibility-report export. Archive removal never deletes
  the user's original downloaded file.
- User support instructions live in `docs/wmp-skin/user-guide.md`; the exact implemented object-model
  contract stays in `docs/wmp-skin/compatibility.md`.

## Phase 7 hardening contracts

- `WMPCorpusReportHarness` is the reusable corpus seam. It emits archive hashes/facts, compatibility
  demand and unknowns, diagnostics, cold/warm load plus render/layout/hit metrics, and confidence.
  It must never serialize local input paths, source text, archive payloads, pixels, or screenshots.
- Keep reports outside the repository. `WMP_CORPUS_PATH` selects an external corpus directory and
  `WMP_CORPUS_REPORT_DIR` selects an external report directory for the opt-in Phase 7 test.
- Fuzz/mutation outcomes are success or `WMPFailure`; exercise archive metadata/payloads, strict
  text, XML, attributes/colors, mapping images, image decode, and bridge bounds.
- Render at the window's current backing scale and rebuild when backing properties change. Keep 1×
  and 2× correctness in original-fixture tests; never add real-skin goldens.
- Corpus-driven compatibility defaults must remain narrow. Empty optional images warn; text outside
  UTF-8/UTF-16/Windows-1252 and malformed duplicate-attribute XML remain typed rejections unless the
  security contract and compatibility rationale are deliberately amended.
