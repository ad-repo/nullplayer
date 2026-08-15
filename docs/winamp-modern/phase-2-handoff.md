# Winamp Modern (`.wal`) — Phase 2 Handoff

**For:** the agent implementing Phase 3 (CornerAmp_Redux vertical slice)
**From:** Phase 2 (production archive, XML/XUI core, retained graph — COMPLETE)
**Date:** 2026-08-15

Read first:

- `~/.claude/plans/i-want-to-support-frolicking-rabbit.md` — source-of-truth plan and locked scope
- `docs/winamp-modern/phase-0a-decision-record.md` — provenance and non-negotiable security limits
- `docs/winamp-modern/phase-0b-decision-record.md` — measured target capabilities and cPro topology
- `docs/winamp-modern/phase-2-handoff.md` — this document
- `TASKS.md` — Phase 2 complete; Phase 3 is next

## 1. Phase 2 outcome and boundary

Phase 2 now provides a headless production pipeline:

```text
.wal file
  → bounded WalArchive
  → fixed-mount, case-insensitive VFS
  → lenient bounded XML + include expansion
  → resource and groupdef/XUI registries
  → deterministic retained Wasabi object graph
  → script bindings + first-paint invalidation
```

It deliberately does **not** render, decode MAKI instructions, dispatch input, or bind playback APIs.
The Winamp Modern main window therefore remains the Phase 1 placeholder. Phase 3 owns the first complete
rendering/input/MAKI/host-API slice.

“First paint” in Phase 2 means initialization finished and graph nodes are dirty for their first consumer.
`WasabiSkinRuntime.markFirstPaintComplete()` clears that initial invalidation only after a future renderer
has actually painted.

## 2. Production entry points

### Complete loader

`Sources/NullPlayer/WinampModern/WinampModernSkinLoader.swift`

- `WinampModernSkinLoader.load(from:additionalMounts:)` is the main headless entry point.
- It validates the `.wal`, mounts it at `/Skins/<sanitized-name>/`, expands `skin.xml`, initializes all
  Phase 2 registries/passes, and returns `WinampModernLoadedSkin`.
- `WinampModernAdditionalMount` is the seam for `/System/` defaults and the Phase 6
  `/Plugins/classicPro/engine/` provider.
- `WinampModernLoadedSkin.teardown()` tears down the retained graph.

### Import and storage

`Sources/NullPlayer/WinampModern/WinampModernSkinImporter.swift`

- Validated archives are kept intact under
  `~/Library/Application Support/NullPlayer/WinampModernSkins/`.
- Validation completes before an existing installed file is atomically replaced.
- `WinampModernContainerIngesting` is the single container-format seam. Phase 2 supplies
  `WalContainerIngestor`; Phase 6 should add the internal NSIS `.exe` ingestor here without changing the
  picker/store contract.
- The `.wal` picker and installed-skin listing are under the existing DEBUG-only Winamp Modern submenu in
  `ContextMenuBuilder`. Keep the family out of release menus until Phase 3 renders a usable target.

## 3. Archive and VFS contracts

### `WalArchive`

`Sources/NullPlayer/WinampModern/WalArchive.swift`

- ZIPFoundation-backed, read-only, on-demand inflation.
- Supports `skin.xml` at archive root or under exactly one wrapper directory.
- Rejects traversal/absolute/drive paths, symlinks, split/deep roots, case-colliding resources, corrupt ZIPs,
  more than 4,096 entries, entries over 32 MB, archives over 128 MB uncompressed, and per-entry ratios over
  200:1.
- CRC verification remains enabled. Archive reads are serialized because ZIPFoundation's shared archive
  cursor is not concurrent-read safe.
- `WalResourceProvider` is the neutral read-only provider protocol. Do not bypass it with host filesystem URLs.

### `WalVirtualFileSystem`

`Sources/NullPlayer/WinampModern/WalVirtualFileSystem.swift`

- Fixed logical mounts only; no host filesystem lookup.
- Case-insensitive canonical lookup with original spelling retained for diagnostics/snapshots.
- Normalizes Windows separators, `.` and `..`; escaping `/` is a hard error.
- Supports `@WINAMPPATH@`, `@SKINPATH@`, `@COLORTHEMESPATH@`, `@DEFAULTSKINPATH@`, and explicitly added
  variables.
- Supports a `*` wildcard only in the final include path component and returns deterministic sorted results.
- The cPro cross-mount shape works as intended:
  `@COLORTHEMESPATH@/../../Plugins/classicPro/engine/load.xml`.

## 4. XML, registries, and initialization

### XML/include layer

`Sources/NullPlayer/WinampModern/WalXML.swift`

- `WalLenientXMLParser` accepts multiple roots and raw ampersands seen in Wasabi fragments while still
  requiring balanced tags.
- Every node retains `WalSourceLocation` (`logical-path:line:column`).
- `WalXMLDocumentLoader` expands `<include>` and `<elementinclude>`, including final-component globs.
- Limits: XML depth 256, include depth 32, and 100,000 expanded nodes. Include cycles and missing targets
  fail with source-aware `WalFailure` diagnostics.

### Initialization passes

`Sources/NullPlayer/WinampModern/WasabiSkinInitializer.swift`

The pass trace is intentionally explicit and tested:

1. resource registration
2. groupdef/XUI registration and inheritance validation
3. object creation
4. script binding
5. initialization
6. first-paint preparation

Resource file references and script files are resolved through the VFS during initialization. Image metadata
is validated without decoding a render surface (maximum 8,192×8,192 and 32 Mpx); font sizes are capped at
512 points; bound MAKI files are capped at 4 MB.

Important group/XUI details:

- `inherit_group` is the group inheritance edge, with a depth limit of 64 and cycle detection.
- `xuitag` registers custom XML tag names for group instantiation.
- `embed_xui` is retained as definition metadata but is **not** an inheritance edge.
- Later duplicate resource/group/XUI definitions deterministically replace earlier definitions and emit a
  warning diagnostic. This preserves skin override behavior.
- Group templates are expanded during object creation; recursive template instantiation is rejected.

## 5. Retained graph and geometry

### Object graph

`Sources/NullPlayer/WinampModern/WasabiObjectGraph.swift`

- `WasabiObjectID` is monotonic and deterministic for a deterministic expanded document. XML `id` values are
  attributes and are not assumed unique; `objects(xmlID:)` therefore returns an array.
- The graph owns all nodes, including temporarily detached nodes. Parent/child changes preserve ownership,
  reject cycles, and dirty structure/geometry/content/appearance/script state as appropriate.
- Invalidations are coalesced by stable object ID and consumed in stable-ID order.
- `snapshot()` is deterministic and is the golden-test surface.
- `teardown()` marks every object torn down, removes parent/child/script bindings, clears invalidations, and
  releases graph ownership—even for detached objects.

### Coordinates

`Sources/NullPlayer/WinampModern/WasabiGeometry.swift`

The signed Wasabi rule is encoded directly:

- `x=-60 relatx=1` → `parent.width - 60`
- `w=-120 relatw=1` → `parent.width - 120`
- same rule for Y/height
- missing width/height use the supplied intrinsic size
- negative non-relative dimensions stay signed; `.standardized` is available for later clipping/hit testing

Coordinates remain top-left Wasabi coordinates. Phase 3 should convert once at the Core Graphics boundary; do
not mutate retained geometry into AppKit's bottom-left convention.

## 6. Diagnostics

`Sources/NullPlayer/WinampModern/WalDiagnostics.swift`

- `WalDiagnosticCode` is stable for tests/UI reporting.
- `WalFailure` carries one or more diagnostics and produces an actionable localized description.
- Physical host paths are not exposed by VFS/XML diagnostics.

Phase 3 should preserve these diagnostics instead of replacing them with renderer-specific string errors.

## 7. Verification completed

- `swift test` — **456 tests passed**, including **16 Phase 2 tests**.
- `Tests/NullPlayerAppTests/WinampModernPhase2Tests.swift` covers:
  - valid root/wrapper archives and case-insensitive reads
  - traversal, symlinks, case collisions, corrupt ZIPs, and every archive size/ratio cap
  - fixed mounts, variables, cross-mount resolution, globs, VFS escape rejection
  - include expansion, missing targets, cycles, XML/include/node depth limits, source locations
  - resource/group/XUI passes, inheritance cycles, image/font/script limits
  - deterministic end-to-end graph snapshots
  - mutations, dirty invalidation, stable IDs, ownership, and teardown
  - coordinate/anchor behavior
  - validate-before-replace import/storage behavior
- Existing lifecycle harness:
  `./.build/debug/NullPlayer -rememberStateEnabled 0 -uiMode classic -winampModernAcceptanceLoop 1`
  → **PASS**, 15 switches, controllers matched, clean exit.
- `git diff --check` passed.

All committed test fixtures are original synthetic data. CornerAmp_Redux, Winamp Modern, cPro-Bento, and the
ClassicPro engine remain user-supplied and untracked per the Phase 0A provenance decision.

## 8. Phase 3 starting sequence

Stay within the Phase 3 checklist in the source plan:

1. Obtain a user-supplied CornerAmp_Redux `.wal`; do not commit it.
2. Load it through `WinampModernSkinLoader` and pin its deterministic graph snapshot/diagnostics locally.
3. Add a renderer that consumes `WasabiObjectGraph` without putting AppKit/Core Graphics types into the graph.
4. Implement only the layer/bitmap/text/button/slider/clipping/window-region surface measured for CornerAmp.
5. Add alpha/region-aware hit testing using `WasabiGeometrySpec` plus the one top-left→bottom-left boundary
   transform documented in `skills/ui-guide`.
6. Add the target-only MAKI parser/value/interpreter/dispatch and explicit host adapters required by the skin.
7. Make script/timer/render/audio teardown part of live mode switching and prove deallocation.

Do not begin Winamp Modern breadth (Phase 4), component hosting (Phase 5), or ClassicPro importing (Phase 6)
while completing the CornerAmp vertical slice.

## 9. Known Phase 3 considerations

- The release menu remains intentionally gated; the DEBUG importer installs but does not select/render skins.
- No real third-party fixture is committed, so Phase 3 must use a developer-supplied archive for target bring-up.
- The retained graph has no renderer cache policy yet. Keep image decoding/cache limits within the Phase 0A
  256 MB LRU cap when Phase 3 introduces decoded surfaces.
- Script bindings currently validate and retain logical paths only. They do not parse bytecode or run lifecycle
  events.
- Phase 1's classic auxiliary-window reuse policy remains unchanged until Phase 5.
