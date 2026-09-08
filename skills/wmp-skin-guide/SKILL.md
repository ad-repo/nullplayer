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
every env-var flag, the line grammar, `scripts/wmp_skin_census.sh` and `scripts/wmp_render_sweep.sh`,
and the traps those scripts enforce. No other file restates a command; add a flag there in the same
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
- **A zero geometry override is a value, not an absence.** Every skin with a store-thumbnail
  `previewView` collapses it in `onLoad` — `view.width = 0; view.height = 0; view.backgroundImage =
  ""; theme.currentViewID = "controlView"` — and Microsoft's own `auto.js` in `Official_Xbox_XP`
  does it with a comment saying so. Discarding a `0` override as "not positive" left 34 corpus
  skins showing a static splash bitmap where the skin had asked for its player.
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

The ones that cost the most, in WMP terms:

- **A green corpus sweep says nothing about AppKit.** The harness builds scenes and rasterizes them;
  it never calls an `NSView.draw`. It was completely right — correct scene, hit tests, dispatch, and
  a dumped PNG with proper transparency — while the app on screen was a black rectangle.
- **Compare `WMPRenderer`'s own image against a screen capture of the same window rect.** Agreement
  means the defect is in the scene; disagreement means it is in the overlays or compositing. That one
  comparison ended the hunt.
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
  wrong on screen. `WMP_RENDER_PROBE`'s `WIDGET` line is the only instrument that sees them; the
  overlays currently ignore `WMPWidget.clipRect`, which is open as W43.
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

## Phase 6 widget and view contracts

- `WMPScene.widgets` is immutable semantic metadata for accessibility and native surfaces. AppKit
  overlays are created only after a completed scene arrives and are replaced with the scene.
- Playlist snapshots are capped at 4,096 rows. Selection, scrolling, play, removal, and movement use
  typed host actions; scripts receive plain copied item values, never `Track` objects.
- WMP exposes ten EQ gains. `WMPAudioEngineHost` uses `EQBandRemapper` at the boundary when the live
  engine is in its 21-band layout; every write remains clamped to ±12 dB.
- `WMPEFFECTS` hosts the safe WMP bars surface. Its single ref-counted spectrum consumer must be
  registered only while an effects surface exists in the active view and removed on switch/teardown.
- `VIDEO`/`WMPVIDEO` remain an app-authored placeholder. WMP plug-ins, ActiveX, DLLs, and arbitrary
  media surfaces remain denied.
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
