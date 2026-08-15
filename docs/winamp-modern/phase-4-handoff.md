# Winamp Modern (`.wal`) — Phase 4 Handoff

**For:** the agent implementing Phase 5 (playlist, EQ, library, and component hosting)

**From:** Phase 4 (Winamp Modern compatibility expansion — COMPLETE)

**Date:** 2026-08-15

Read first:

- `~/.claude/plans/i-want-to-support-frolicking-rabbit.md` — source-of-truth plan and locked scope
- `docs/winamp-modern/phase-0a-decision-record.md` — provenance and security limits
- `docs/winamp-modern/phase-0b-decision-record.md` — measured target capabilities and component topology
- `docs/winamp-modern/phase-3-handoff.md` — renderer, MAKI, host, and lifecycle contracts inherited by Phase 4
- `TASKS.md` — local task ledger; Phase 4 is complete and Phase 5 is next

## 1. Phase 4 outcome and boundary

The self-contained Winamp Modern target now completes the bounded `.wal` pipeline and MAKI startup without
falling back to Classic or NullPlayer Modern rendering code. Its Main container supports normal and shade
layouts, script-driven layout changes, constrained resizing, cached color-theme changes, and the broader
resource/widget surface observed in the target.

Phase 4 added:

- bitmap-font rendering while preserving VFS-backed TrueType support
- declared colors, gamma groups/sets, bounded themed bitmap caching, and persisted theme selection
- animated layers, toggles, N-state buttons, status, song tickers, album-art host/fallback rendering, and spectrum
  visualization
- resource aliases, inherited/XUI group expansion with `embed_xui`, and `sendparams`/`hideobject`/`showobject`
  meta-commands
- normal/shade layout activation, default/minimum/maximum sizing, runtime geometry changes, transparent window
  behavior, and child clipping
- per-skin namespaced integer/string configuration objects
- class-aware MAKI method signatures, dynamic timer/config objects, additional observed events and standard methods,
  and the Winamp Modern compiled-GUID byte ordering

The target did not introduce a previously unsupported opcode value. Phase 4 therefore extended observed method,
event, object, and class dispatch without inventing unmeasured opcode semantics or weakening VM budgets.

Phase 5 still exclusively owns playlist/EQ/library adapters, component buckets/window holders, multi-container
native window mapping, and routing auxiliary toggles into skin-owned components. No Phase 5 work is included here.

## 2. Resource, color, and font contracts

`Sources/NullPlayer/WinampModern/WasabiSkinInitializer.swift` now distinguishes bitmap-font `file` attributes
that name another declared bitmap from paths that must resolve through the VFS. `WalResourceRegistry` also
supports case-insensitive aliases with bounded traversal; missing targets and cycles fail closed.

`Sources/NullPlayer/WinampModern/WasabiRenderer.swift` adds `WasabiColorThemeCatalog` and extends
`WasabiResourceCache`:

- gamma sets are read from the already bounded expanded XML document
- theme names and gamma groups are case-insensitive
- the active theme is persisted under the loaded skin's private configuration namespace
- theme changes invalidate decoded themed bitmaps and dirty appearance state
- decoded bitmaps remain under the existing 256 MB LRU cost limit
- bitmap gamma work uses Core Image only after the source image has passed archive/image limits
- bitmap fonts resolve their sprite sheet through the resource registry and draw through the existing clipped
  Core Graphics scene

No skin resource is read by an absolute host path. No Winamp artwork, font, or other third-party skin asset was
added to the repository.

## 3. XUI, aliases, and initialization

The initialization order remains resource registration → type registration → object creation → script binding →
initialization → first paint.

Within object creation:

- inherited group defaults are merged before instance attributes
- a resolved group's template children are created before instance children
- `embed_xui` directs instance children into the named descendant slot
- resource declarations and aliases never become retained GUI objects
- meta-commands are retained temporarily and applied after the complete object graph exists
- `sendparams` mutates only named targets beneath its owner or optional group scope
- hide/show meta-commands use the same bounded retained subtree search

Recursive group expansion and inheritance limits from Phase 2 remain unchanged. Alias traversal is capped at 64
links and returns no definition for a cycle.

## 4. Widgets and drawing

The retained renderer now recognizes the measured Phase 4 widgets:

- `AnimatedLayer` selects a bounded frame from its registered bitmap and uses an injected monotonic clock
- `NStatesButton` resolves numbered state resources and reflects the host repeat state where applicable
- `Status` selects play/pause/stop artwork from host playback state
- `Songticker` supports clipped bitmap-font marquee drawing
- `AlbumArt` draws a narrow optional `CGImage` supplied by `WinampModernHost`, otherwise `notfoundimage`
- `Vis` draws capped spectrum bars from the existing visualization host data

`WinampModernMainView` schedules a 30 Hz display timer only when its current scene contains an animated layer or
song ticker. Teardown invalidates that timer before scripts, resource caches, and the graph are released.

The album-art host property has a default `nil` implementation, so existing hosts remain source-compatible and
fallback artwork remains deterministic. Supplying asynchronous artwork from the application is not required for
Phase 5 component hosting and should not broaden the skin's filesystem/network authority.

## 5. Layout, resizing, and window behavior

`WasabiSceneRenderer` owns the active layout and exposes its declared layout IDs. Activating a layout resets the
canvas to `default_w/default_h`, then `w/h`, then its minimum as a final fallback. Interactive resize clamps to
declared minimum/maximum dimensions and invalidates geometry.

`WinampModernScriptRuntime` routes `Container.switchToLayout` through an injected callback.
`WinampModernMainView` applies the resulting canvas size, and `WinampModernMainWindowController` preserves the
window's top-left point while changing its frame. A reentrancy guard prevents AppKit resize notifications from
feeding back into skin-initiated resize operations.

The Winamp Modern window remains transparent and borderless. Only its controller acquired `.resizable` and an
`NSWindowDelegate`; Classic and NullPlayer Modern controller/rendering sources were not changed.

## 6. Configuration and MAKI expansion

`Sources/NullPlayer/WinampModern/WinampModernConfiguration.swift` is the only persistence seam exposed to this
runtime. Storage keys are scoped by a sanitized imported-skin namespace, section, and key. Scripts can read/write
integer private values and string configuration attributes, but cannot address arbitrary defaults keys.

MAKI changes are concentrated in `MakiBytecode.swift` and `WinampModernScriptRuntime.swift`:

- method signatures receive the declaring class GUID so overloaded methods consume the correct stack arguments
- compiled GUIDs are canonicalized by reversing each little-endian 32-bit word
- dynamic references represent bounded timers, configuration items, and configuration attributes
- standard string/time/metadata/viewport/status/theme methods required by the target have explicit signatures
- GUI methods cover parent/layout lookup, text, geometry, alpha, enabled/active state, positions, animation frames,
  targets, and action routing
- timers retain the Phase 3 count and frequency caps
- navigation, arbitrary modal UI, and unapproved named-window behavior remain denied or compatibility-safe
- null receiver diagnostics now include the class GUID and source variable when available

Unsupported valid methods still fail with `.unsupportedScriptCapability`; malformed stack/receiver behavior still
fails with `.invalidScript`. Execution, stack, call-depth, allocation, script-size, and timer limits were not raised.

## 7. Lifecycle and teardown

The Phase 3 teardown order remains authoritative:

1. `WinampModernMainView.teardown()` invalidates tracking and animation timers and clears interaction state.
2. `WinampModernScriptRuntime.teardown()` clears all view/layout/theme callbacks, cancels MAKI timers, tears down
   the interpreter, ends visualization consumption, and drops dynamic/config/menu state.
3. `WasabiSceneRenderer.teardown()` clears bitmap/font/theme-derived caches.
4. `WinampModernLoadedSkin.teardown()` tears down the retained graph.

All callbacks use weak captures. Phase 5 component views must fit into this same synchronous ownership boundary;
no component or adapter may survive its container/runtime teardown.

## 8. Verification completed

Headless automated verification:

- `swift test` → **464 tests passed**, 3 opt-in fixture tests skipped when environment variables were absent
- user-supplied Winamp Modern fixture:

  ```sh
  WINAMP_MODERN_WAL=/path/to/WinampModern566.wal swift test \
    --filter WinampModernPhase4Tests/testLocalWinampModernCompatibilityWhenFixtureIsSupplied
  ```

  → startup scripts pass; normal is 354×280; script dispatch switches to shade at 354×25 and back; resize clamps;
  an alternate cached gamma theme activates and the original theme is restored
- user-supplied CornerAmp fixture:

  ```sh
  WINAMP_MODERN_CORNERAMP_WAL=/path/to/CornerAmp_Redux.wal swift test \
    --filter WinampModernPhase3Tests
  ```

  → **5 tests passed**, including first paint, input, MAKI budgets, timer bounds, and complete teardown
- original synthetic Phase 4 tests cover bitmap fonts, existing TTF paths, colors/gamma, theme invalidation,
  animation, N-state/status/ticker/album-art/vis drawing, alias resolution/cycles, XUI embedding, meta-command
  mutations, layout limits, and configuration namespace isolation
- `git diff --check` passes

The DEBUG live four-mode switching harness was intentionally **not rerun** in Phase 4. Cycling that harness was
observed to distort the user's active Classic and NullPlayer Modern windows. Verification stayed headless and
Winamp-Modern-specific after that report. A future manual lifecycle run must be coordinated so it does not alter an
active user session; the omission does not authorize changes to Classic/Modern geometry as part of Phase 5.

## 9. Attribution and fixtures

Webamp Modern at pinned commit `5f56a5369c3e2346f4f6e045f214856ef9abaad4` remained a behavioral reference.
The existing MIT attribution is recorded in `scripts/third_party_components.tsv` and
`Sources/NullPlayer/Resources/ThirdPartyLicenses/WebampModern_LICENSE.txt`. No Webamp source or third-party skin
asset was copied into the repository.

The real Winamp Modern and CornerAmp archives used for acceptance are local, user-supplied, and untracked. All
committed test fixture data is generated synthetically at test time.

## 10. Phase 5 starting sequence

Stay within Phase 5 in the source plan:

1. Use the Phase 0B topology inventory to map separate Wasabi containers and embedded component holders.
2. Freeze the component host ownership/teardown seam before adding playlist, EQ, or library adapters.
3. Implement component buckets/window holders without allowing skin GUIDs to escape the typed host registry.
4. Add playlist behavior, then the classic 10-band EQ adapter, then the library surface required by the measured
   targets.
5. Route PL/EQ/library toggles to skin containers/components rather than assuming a native auxiliary window.
6. Retain original synthetic tests and opt-in user-supplied target acceptance for each component topology.

Do not begin the ClassicPro importer (Phase 6), general compatibility hardening (Phase 7), or release work
(Phase 8) while implementing Phase 5.

## 11. Known Phase 5 considerations

- The renderer still chooses the Main container for its single native player view; Phase 5 owns additional
  container-to-window/component mapping.
- Playlist, EQ, and library toggles still use the Phase 1 classic auxiliary-window policy until Phase 5 replaces it.
- `newgroup` remains a compatibility-safe null result; instantiate groups only if a measured Phase 5 component
  path requires it and preserve object-count/inheritance limits.
- Album-art rendering has a typed image seam, but the production host currently returns `nil`; fallback images are
  supported. Do not turn album-art lookup into skin-controlled I/O.
- Theme color math is compatibility-focused and cached, not a claim of pixel-identical behavior for every Wasabi
  gamma edge case. Broader corpus/profiling work belongs to Phase 7.
- The release menu remains gated. Phase 5 component work does not authorize release exposure or version changes.
