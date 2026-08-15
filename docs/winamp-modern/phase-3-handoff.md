# Winamp Modern (`.wal`) — Phase 3 Handoff

**For:** the agent implementing Phase 4 (Winamp Modern compatibility expansion)

**From:** Phase 3 (CornerAmp_Redux vertical slice — COMPLETE)

**Date:** 2026-08-15

Read first:

- `~/.claude/plans/i-want-to-support-frolicking-rabbit.md` — source-of-truth plan and locked scope
- `docs/winamp-modern/phase-0a-decision-record.md` — provenance and non-negotiable security limits
- `docs/winamp-modern/phase-0b-decision-record.md` — measured target capabilities and cPro topology
- `docs/winamp-modern/phase-2-handoff.md` — archive, VFS, XML, graph, and geometry contracts
- `docs/winamp-modern/phase-3-handoff.md` — this document
- `TASKS.md` — Phase 3 complete; Phase 4 is next

## 1. Phase 3 outcome and boundary

Phase 3 provides the first complete, interactive `.wal` path:

```text
validated .wal
  → retained Wasabi graph
  → bounded image/font resource cache
  → Core Graphics scene rendering + alpha window region
  → AppKit input + alpha-aware object hit testing
  → target-only MAKI parser/interpreter/dispatch
  → bounded NullPlayer playback/metadata/visualization host bridge
  → synchronous script/render/graph teardown
```

A user-supplied CornerAmp_Redux archive now loads in the real Winamp Modern controller, runs its startup
scripts, renders its 246×228 diagonal alpha-shaped layout, and controls NullPlayer transport, seek, and volume.
No CornerAmp or other third-party skin asset is committed.

Phase 3 deliberately implements only the classes, opcodes, methods, and visual states required by the measured
CornerAmp target. Phase 4 owns compatibility breadth: bitmap fonts, gamma/color systems, animated and N-state
resources, ticker/album-art/visualization elements, broader XUI/alias/inheritance behavior, layout/shade/resize,
configuration persistence, and additional MAKI opcodes/APIs. Phase 5 still owns real playlist/EQ/library
component hosting.

## 2. Production UI entry points

### Main controller

`Sources/NullPlayer/Windows/WinampModern/WinampModernMainWindowController.swift`

- Replaces the Phase 1 placeholder with a transparent borderless AppKit window backed by the Phase 2 loader.
- Loads the selected installed archive, creates the host/renderer/script runtime/view, runs `onscriptloaded`, and
  resizes the window to the skin canvas.
- `loadSkin(at:)` is the live skin replacement entry point.
- `prepareForUITeardown()` synchronously tears down the view, scripts, renderer, and loaded graph before a mode
  controller is released.
- In DEBUG builds only, `-winampModernSkinPath <absolute-path>` loads a developer-supplied archive directly.
  This is an acceptance hook, not a production filesystem bypass: the archive still goes through
  `WinampModernSkinLoader` and its VFS.

### Input view

`Sources/NullPlayer/Windows/WinampModern/WinampModernMainView.swift`

- Owns hover, press, release, drag, right-click, and window-drag dispatch.
- Converts AppKit bottom-left event coordinates to Wasabi top-left coordinates exactly once at the view boundary.
- Routes XML actions for play/pause/stop/previous/next/eject, volume/seek sliders, repeat/shuffle, and the existing
  Phase 1 auxiliary-window toggles.
- Dispatches target MAKI mouse and playback lifecycle events through `WinampModernScriptRuntime`.
- Rejects mouse hits outside the rendered alpha window region via `hitTest(_:)`.

### Skin selection

`Sources/NullPlayer/WinampModern/WinampModernSkinImporter.swift` and
`Sources/NullPlayer/App/ContextMenuBuilder.swift`

- The selected installed skin name is stored under `winampModernSkinName`.
- Import selects the imported archive; selecting an installed item reloads the active Winamp Modern controller.
- The importer/installed-skin menu remains DEBUG-only. Do not broaden release UI as part of unrelated Phase 4
  compatibility work.

## 3. Rendering and resource contracts

`Sources/NullPlayer/WinampModern/WasabiRenderer.swift`

### `WasabiResourceCache`

- Reads bitmap and TTF bytes only through `WalVirtualFileSystem`.
- Decodes PNG resources and crops bitmap sprites using top-left Wasabi sprite coordinates.
- Uses a bounded LRU bitmap cache with the locked 256 MB production cap.
- Builds target TTF fonts with Core Text without installing them globally.
- `teardown()` clears decoded images, fonts, access state, and cache cost.

### `WasabiSceneRenderer`

- Selects `container id="Main"` and its `layout id="normal"`; canvas dimensions come from the layout's declared
  width/minimum/default attributes.
- Consumes the retained graph directly; AppKit/Core Graphics types are not inserted into graph objects.
- Resolves retained top-left geometry and applies one Y flip at the Core Graphics drawing boundary.
- Renders layout backgrounds, layers and sprite regions, TTF text, button/toggle/status states, and horizontal or
  vertical slider thumbs.
- Supports parent clipping when `clipchildren` is enabled.
- Text display bindings currently cover elapsed time, song name, and song info. Status/toggle images reflect host
  playback, repeat, and shuffle state.
- Scene order is retained graph order. Hit testing walks it in reverse and rejects clipped, hidden, ghosted, or
  transparent bitmap pixels. `containsVisiblePixel(at:)` is the window-region test.
- `draw(in:)` calls `markFirstPaintComplete()` only after a real render.

Keep the renderer cache bounded and VFS-only in Phase 4. Add new element renderers and resource kinds without
moving platform rendering state into `WasabiObjectGraph`.

## 4. MAKI bytecode and execution contracts

`Sources/NullPlayer/WinampModern/MakiBytecode.swift`

### Parser and value model

- `MakiBytecodeParser` reads the FG compiled-script format into classes, methods, typed variables/constants,
  bindings, and decoded instructions.
- Table counts are bounded to 100,000 entries and all indexes/offsets are checked before use.
- `MakiValue` covers null, Boolean, integer, float, double, string, and reference objects. Reference identity is
  explicit through `MakiObjectReference`.
- Parser failures use `.invalidScript`; unimplemented valid behavior uses `.unsupportedScriptCapability`.

### Target interpreter

The Phase 3 opcode surface covers the CornerAmp paths: stack push/pop/assignment, equality and ordered
comparisons, conditional/unconditional branches, host/global method calls, local calls/return, move,
pre/post increment/decrement, arithmetic/modulo, bit/logical operations, allocation, and delete.

Production execution limits are intentionally fixed and enforced per event:

- 5,000,000 instructions
- call depth 256
- 64 MB event allocation accounting
- 1,000,000 stack values

Budget failures use `.scriptBudgetExceeded`. Unsupported opcodes fail closed instead of becoming silent no-ops.
`MakiInterpreter.teardown()` drops its dispatcher and prevents subsequent execution.

Phase 4 should add opcodes only from an observed compatibility need and should extend synthetic budget/error
coverage with each addition. Do not weaken these caps.

## 5. Script runtime and target dispatch

`Sources/NullPlayer/WinampModern/WinampModernScriptRuntime.swift`

- Parses every Phase 2 script binding during initialization and preserves owner ID and script parameter.
- `start()` begins visualization consumption and dispatches `onscriptloaded`.
- `dispatchSystem(event:)` and `dispatch(object:event:)` resolve compiled binding variables and execute matching
  event handlers.
- GUI references use stable retained graph IDs, so script mutations remain attached to the production graph.
- Target mutations currently include `setxmlparam`, `resize`, `show`, and `hide`; each invalidates the view through
  `graphDidMutate`.
- Target lookups include containers, layouts, object descendants, script group, and script parameter/token access.
- Host reads/writes cover volume, seek, duration, left/right visualization levels, time, viewport/application
  coordinates, runtime/skin identity, and integer/string conversion.
- Private integer storage is namespaced by skin under `winampModern.private.<skin>...`.
- Popup menus use an inert command model and an injected presenter. Skin `messagebox` calls are denied rather than
  allowing arbitrary modal host UI. `newgroup` remains a safe null result until broader group instantiation is
  deliberately implemented.
- Unsupported methods fail with a source-aware `.unsupportedScriptCapability` diagnostic.

This dispatcher is not a general Wasabi API. Phase 4 should extend `signature(for:)` and the relevant system,
GUI, or object dispatch path together so stack argument counts and return kinds remain explicit.

## 6. Safe host and timer contracts

`Sources/NullPlayer/WinampModern/WinampModernHost.swift`

- `WinampModernHost` is the narrow skin-facing API: playback state/time/duration, volume, shuffle/repeat,
  title/info, spectrum levels, transport, seek, file-open, and visualization-consumer lifecycle.
- `WinampModernAudioEngineHost` adapts that interface to `AudioEngine`; scripts never receive the engine itself.
- Volume is clamped to 0...1 and visualization consumer registration is reference-safe and idempotent per host.
- `MakiTimerService` allows at most 256 active timers, clamps periods to at least 8 ms and at most 120 Hz, replaces
  an existing timer by ID, and invalidates every timer during teardown.

Keep new Phase 4 host capabilities narrow, typed, and explicitly justified by a measured skin. Do not expose host
filesystem, networking, process launch, arbitrary selectors, or unrestricted modal UI.

## 7. Real-skin resource compatibility fixes

`Sources/NullPlayer/WinampModern/WasabiSkinInitializer.swift`

- XML include paths remain relative to the including XML document.
- Bitmap/font/script file attributes first resolve relative to their declaring XML and then fall back to
  `@SKINPATH@`, matching real Wasabi archives such as CornerAmp while remaining inside the VFS.
- A code-only empty built-in `wasabi.panel` group is registered because CornerAmp inherits that standard type.
  No system skin asset is bundled or imported.

Phase 4 should place additional code-only standard definitions or user-provided `/System/` resources behind the
existing registry/mount seams. Do not add undocumented broad defaults merely to suppress missing-resource errors.

## 8. Lifecycle and teardown order

The controller/view teardown path is synchronous and idempotent:

1. `WinampModernMainView.teardown()` clears interaction state/callbacks and tears down scripts and renderer.
2. `WinampModernScriptRuntime.teardown()` removes graph/popup callbacks, invalidates timers, tears down the
   interpreter, ends visualization consumption, and releases programs/menu state.
3. `WasabiSceneRenderer.teardown()` clears decoded resource caches.
4. `WinampModernLoadedSkin.teardown()` releases the retained graph and VFS-owned runtime state.

Keep this order when Phase 4 introduces animations, ticker clocks, or additional visualization consumers. Every
new asynchronous producer must stop before its graph/resources are released.

## 9. Verification completed

- Full suite outside the filesystem sandbox (required for macOS audio components): **461 tests passed**, with the
  two opt-in local-archive checks skipped when their environment variable is absent.
- With a user-supplied archive:

  ```sh
  WINAMP_MODERN_CORNERAMP_WAL=/path/to/CornerAmp_Redux.wal swift test \
    --filter WinampModernPhase3Tests
  ```

  → **5 Phase 3 tests passed**.
- Phase 3 coverage in `Tests/NullPlayerAppTests/WinampModernPhase3Tests.swift` verifies:
  - target bytecode parsing and measured method inventory
  - startup scripts and graph mutations
  - 246×228 scene construction, alpha coverage, object hit testing, and button→host input
  - runaway-instruction budget rejection
  - timer frequency/count caps
  - timer/interpreter/visualization/graph teardown
- Live direct-load acceptance used:

  ```sh
  ./.build/debug/NullPlayer -rememberStateEnabled 0 -uiMode winampModern \
    -winampModernSkinPath /path/to/CornerAmp_Redux.wal
  ```

  The archive rendered with its expected diagonal alpha region and scripted first-paint state.
- The four-mode lifecycle harness completed 15 switches with
  `WINAMP-MODERN-ACCEPTANCE: PASS` and a clean exit.
- `./scripts/validate_notices.sh Sources/NullPlayer/Resources dist/NullPlayer.app/Contents/Frameworks` passed.
- `git diff --check` passed.

All committed fixtures are original synthetic data. The real target archive remains user-supplied and untracked.

## 10. Attribution

The MAKI format/opcode behavior used Webamp Modern as a behavioral reference at commit
`5f56a5369c3e2346f4f6e045f214856ef9abaad4`. Its MIT license is included at
`Sources/NullPlayer/Resources/ThirdPartyLicenses/WebampModern_LICENSE.txt`, and the generated aggregate notices
and `scripts/third_party_components.tsv` include the corresponding manifest entry. No Webamp source code or skin
asset is bundled.

## 11. Phase 4 starting sequence

Stay within the single Phase 4 checklist item in the source plan:

1. Build a user-supplied, provenance-safe compatibility corpus and record the first concrete failure.
2. Add only the resource/element/XUI/MAKI behavior needed to advance that failure.
3. Preserve VFS-only resource access, bounded decoded caches, source-aware diagnostics, and execution budgets.
4. Add an original synthetic regression for every newly supported capability and malformed counterpart.
5. Re-run CornerAmp first-paint/input coverage and the 15-switch lifecycle loop after each compatibility slice.

Do not begin component hosting (Phase 5), ClassicPro engine importing (Phase 6), general hardening (Phase 7), or
release documentation/version work (Phase 8) while completing Phase 4.

## 12. Known Phase 4 considerations

- Bitmap fonts, gamma sets, animated/N-state/ticker/album-art/dedicated visualization elements, broader layout
  modes, and generalized XUI behavior are not implemented yet.
- Only CornerAmp-observed MAKI opcodes and method signatures are supported; valid unimplemented behavior fails
  closed with a diagnostic.
- `newgroup` is intentionally inert, and configuration support is limited to target private integers plus host
  repeat/shuffle state.
- The renderer currently owns one Main/normal canvas in one `NSWindow`; multi-layout/shade/resize/window mapping
  belongs to later planned work.
- Playlist, EQ, library, and component bucket toggles still reuse Phase 1 classic auxiliary controllers until
  Phase 5 provides real Wasabi component hosting.
- The release menu remains gated even though the target vertical slice renders; changing release exposure should
  be an explicit plan/release decision, not incidental compatibility work.
