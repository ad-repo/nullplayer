---
name: wmp-skin-guide
description: Windows Media Player .wmz/.wms skin engine, bounded loading, retained graph, compatibility reporting, rendering, isolated JScript, and WMP-specific app-mode integration.
---

# Windows Media Player skin engine

Read this skill before changing `Sources/NullPlayer/WMPSkin/` or
`Sources/NullPlayer/Windows/WMPSkin/`. The phased contract is in
`docs/wmp-skin-integration-plan.md`; the current security decisions and locked limits are in
`docs/wmp-skin/phase-0-decision-record.md`.

## Isolation boundary

WMP is an independent skin engine. Keep engine/model work in `WMPSkin/`, AppKit work in
`Windows/WMPSkin/`, and tests/fixtures under the WMP test paths. Do not teach Classic, Original, or
Winamp Modern types about WMP markup. Change shared application files only when no WMP-owned seam can
satisfy the requirement; keep that seam minimal, gate it explicitly on the WMP controller family,
and prove all existing modes retain their behavior. Record every shared path and the rejected local
alternatives in the phase handoff.

Implementation runs only from `/Users/ad/Projects/nullplayer-wmp-skin-support` on
`feat/wmp-skin-support`. Run the hard worktree preflight in the plan before writing or building.

Never put WMP input work on the main thread. Archive validation/inflation, decoding, XML/graph/report
construction, image work, expressions, and helper-process communication run on a WMP-owned background
executor. Never use `DispatchQueue.main.sync`. Hand only completed immutable snapshots and typed host
commands to `MainActor`, where the work is limited to AppKit presentation.

WMP owns a dedicated app-authored unskinned player. On a fresh public-release profile with no
persisted mode and before the user has downloaded/imported a skin, launch that WMP view. Missing,
deleted, corrupt, or rejected selections also recover to it while remaining in `.wmp`. Never use an
Original/Classic/Winamp Modern controller, preference, `skin.json`, or artwork as WMP's default or
fallback. Existing users keep their persisted mode.

## Loader contracts

- `WMPPhase0Limits` and stable codes `WMP0001`–`WMP0020` are locked. Production loading must preserve
  their meanings and reject metadata bounds before decompressing payloads.
- Archive paths normalize Windows separators, use Unicode-composed case-insensitive lookup, and
  reject absolute paths, drive prefixes, traversal, symlinks, collisions, excess wrapper depth, and
  CRC failure. The provider is read-only and never extracts to disk.
- A skin contains exactly one unambiguous `.wms` at root or under one wrapper directory. Resources
  resolve relative to the declaring file and then the skin root, never outside the provider.
- Text decoding is strict BOM-aware UTF-8/UTF-16LE/UTF-16BE. Do not shell out to `iconv`, accept
  malformed surrogates, or allow embedded NULs.
- XML retains authored tag/attribute spelling and source locations while bounding depth and node
  count. Unknown elements stay in the graph for compatibility reporting.
- Attribute parsing classifies expressions, bindings, handlers, colors, and resources without
  executing skin code. `res://` and optional missing artwork warn; path escapes and required missing
  scripts fail.
- Graph IDs and registry order are deterministic. Duplicate authored IDs are retained and warned,
  not silently collapsed.

Skin JScript must never run in the app process. Phase 5 uses the killable helper-process architecture
selected by Phase 0 and must repeat its hard-stop/restart security gate before product exposure.

## Static scene and image contracts

- `WMPSceneBuilder` resolves literal geometry plus the bounded static initial-layout grammar in
  `WMPInitialLayoutExpression`: finite numbers, parentheses, arithmetic, and geometry reads from
  deterministic IDs. `wmpprop:` is accepted only as an alias for that same geometry grammar.
  Calls, assignments, statements, script globals, ambiguous/unknown IDs, cycles, and excessive
  dependency depth remain unresolved diagnostics; never route them through in-process JScript or
  invent fallback geometry.
- Scene coordinates remain top-left throughout layout, clipping, dirty bounds, hit metadata, and
  paint commands. Core Graphics conversion happens once in `WMPRenderer`; images and text each use
  an explicit counter-transform so pixels and glyphs remain upright.
- The immutable scene owns no `CGImage` or cache state. `WMPImageStore` performs bounded ImageIO
  metadata/decode off-main, supports BMP/GIF/JPEG/PNG, and uses a byte-bounded LRU keyed by canonical
  resource path plus color key.
- Color keys compare exact un-premultiplied RGB and clear only matching pixels. Preserve the source
  alpha of every non-matching pixel.
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

## Verification

Use the committed original fixtures in `Tests/NullPlayerAppTests/Fixtures/WMPSkin/`. Run focused WMP
tests first, the user-supplied `WMP_TEST_WMZ` corpus check when available, then full `swift test` and
`git diff --check`. Do not commit third-party skins or build a DMG unless the user requests it.
