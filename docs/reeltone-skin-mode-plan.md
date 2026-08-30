# Reeltone Skin Mode Implementation Plan

- Status: Phase 3 implemented; exit verification pending
- Baseline: `origin/main` at `56c198ec44131158c0a500a4c947c5ad281b1644`
- Planning branch: `plan/reeltone-mode`
- Reference skin: `aqua-glass.reeltone` (`formatVersion: 2`)

## Implementation Progress

| Phase | Status | Notes |
|---|---|---|
| Phase 0 | Not recorded on this branch | The plan is present; the remaining Phase 0 artifacts must be audited separately. |
| Phase 1 | In progress | Mode shell is implemented; automated verification and manual live-switch acceptance are tracked against the Phase 1 exit criteria. |
| Phase 2 | Implemented; exit verification pending | Loader/store security tests pass. Aqua Glass acceptance remains pending because the archive is not present in this worktree. |
| Phase 3 | Implemented; exit verification pending | v1 palette adaptation, fallback Original-window styling, import/discovery/selection, live switching, and restart restoration are implemented. `swift test` passes (459 tests, 2026-08-29); manual readability acceptance remains pending. |
| Phase 4+ | Not started | Dynamic surfaces remain out of scope. |

Update this table at each phase boundary. Do not mark a phase complete until its automated checks
and manual exit criteria have both been recorded.

## Worktree Requirement

All planning, implementation, builds, tests, commits, and documentation changes for Reeltone support must be performed from a dedicated Git worktree. The primary checkout at `/Users/ad/Projects/nullplayer` must not be used as the working directory and must not receive Reeltone edits.

The planning worktree was created as follows:

```bash
git worktree add -b plan/reeltone-mode /private/tmp/nullplayer-reeltone-mode origin/main
cd /private/tmp/nullplayer-reeltone-mode
```

Its required starting state is:

```text
worktree: /private/tmp/nullplayer-reeltone-mode
branch:   plan/reeltone-mode
HEAD:     56c198ec44131158c0a500a4c947c5ad281b1644
upstream: origin/main
```

Before beginning an implementation phase, verify the active location and baseline from inside the worktree:

```bash
pwd
git branch --show-current
git rev-parse HEAD
git status --short
```

If a durable implementation worktree replaces the current `/private/tmp` worktree, create it from the same branch or from a new phase branch based on the recorded `origin/main` baseline. Update this section with its path before making changes. Do not copy the plan or implementation into the primary checkout as a substitute for moving or recreating the worktree.

## 1. Objective

Add Reeltone as a distinct NullPlayer skin/UI mode that can load `.reeltone` archives and create its windows from the surfaces and regions declared by the skin.

The mode will reuse NullPlayer's Original component implementations and visual language where the Reeltone package requests a complex hosted component or omits one. It will not be implemented as an Original skin selected inside Original mode, and it will not depend on the Winamp Modern (`.wal`) subsystem.

The first complete milestone must make Aqua Glass usable for normal playback. Later milestones add general panel topology and the full v2 component set without changing Classic or Original behavior.

## 2. Scope

### In scope

- A new persisted `PlayerUIMode.reeltone` mode.
- Reeltone v1 theme support.
- Reeltone v2 shaped main windows, declared panels, art, regions, controls, and animations.
- Dynamic construction of one AppKit window for the main surface and one for each declared panel.
- Reuse of Original playlist, equalizer, library, artwork, and visualization components through explicit embedded-host interfaces.
- Standard Original auxiliary-window fallbacks when a selected skin does not provide a region for a requested component.
- Secure loading, installation, discovery, validation, diagnostics, and switching of `.reeltone` archives.
- Exact-mode state restoration, UI Size behavior, Compact Mode integration, docking, minimization, and Always on Top.
- Unit, integration, UI, accessibility, malformed-package, 1x, and 2x coverage.

### Out of scope

- Executing code from a skin archive.
- MAKI/XML or `.wal` compatibility.
- A dependency on `Sources/NullPlayer/WinampModern/` or any feature-branch-only Winamp Modern type.
- Changes to the behavior or file formats of Classic and Original skins.
- Reeltone authoring tools or publishing-service integration.
- Extensions to the public Reeltone schema unless a real compatibility case requires one and the extension is documented separately.

## 3. Source Format Assumptions

The implementation should track the published Reeltone documentation and schema:

- Format guide: <https://reeltone.iagocavalcante.com/studio/format.html>
- v2 schema: <https://reeltone.iagocavalcante.com/studio/schema-v2.json>

A `.reeltone` file is a ZIP archive with `skin.json` at its root. Version 1 is a fixed deck theme. Version 2 declares a shaped window, optional named panels, artwork, and ordered regions.

The v2 component vocabulary currently includes:

`play`, `pause`, `playPause`, `stop`, `prev`, `next`, `seek`, `volume`, `shuffle`, `repeatMode`, `title`, `elapsed`, `duration`, `artwork`, `trackList`, `visualiser`, `equaliser`, `close`, `minimise`, `togglePanel`, `decoration`, `library`, and `libraryBack`.

The loader must treat this as untrusted declarative input. Unknown additive fields should be retained or ignored with diagnostics when safe; an unsupported major format version must fail clearly.

## 4. Architecture

### 4.0 Blast-radius containment

Reeltone implementation must be isolated to `Reeltone/`, `Windows/Reeltone/`, and
Reeltone-specific tests and documentation whenever possible. Changes to existing shared code are
permitted only when they are unavoidable integration seams for mode selection, lifecycle,
persistence, menus, or shared provider protocols.

Every shared-code change must:

- branch on exact `.reeltone` mode or a narrowly named capability whose existing-mode results are
  unchanged;
- avoid modifying Classic, Original, Original-Metal, or Winamp Modern implementation behavior;
- delegate Reeltone behavior immediately into a Reeltone-owned type instead of growing parallel
  Reeltone logic inside an existing subsystem;
- remain the smallest practical change at that seam and avoid opportunistic refactors;
- include focused regression coverage for the unchanged behavior of existing modes when the seam
  is testable.

If a task can be completed either inside the Reeltone subsystem or by generalizing existing skin
code, prefer the Reeltone-local implementation. Generalization is allowed only when duplication
would prevent correct lifecycle or state behavior, and its necessity must be documented in the
phase review. A later phase must not broaden an earlier shared seam merely for convenience.

```text
.reeltone archive
    -> bounded archive inspection and resource validation
    -> versioned manifest decoder
    -> immutable loaded skin + diagnostics
    -> surface inventory (main + named panels)
    -> Reeltone surface coordinator
    -> surface window controllers and ordered region views
    -> Original component hosts + AudioEngine command/state bridge
```

### 4.1 Mode boundary

Add `PlayerUIMode.reeltone`. Give the mode explicit capability properties instead of deriving behavior from a binary Classic/Modern flag:

- `usesModernEQLayout = true` so Reeltone uses the Original 21-band EQ configuration.
- `usesModernControllers = true` only for Original fallback auxiliary windows; the Reeltone main and declared panel windows use Reeltone controllers.
- `usesReeltoneSurfaces = true` to select the dynamic surface coordinator.

Any shared `App/` path must branch on the exact mode or a narrowly named capability. Reeltone work must not alter Classic or Original behavior as an assumed no-op.
Shared `App/` edits are integration seams only; substantive Reeltone behavior belongs in
Reeltone-owned types under the source layout below.

### 4.2 Engine boundary

Create a separate `ReeltoneSkinEngine`. Do not overload `ModernSkinEngine` with another archive format or lifecycle. The Reeltone engine owns selection, installation, decoding, validation, resource lookup, and skin-change notifications.

The engine should also produce a companion Original-style theme adapter. This adapter supplies colors, fonts, and fallback assets to existing Original auxiliary components without making a Reeltone archive pretend to be an Original skin.

### 4.3 Surface inventory and coordinator

Decode the manifest into an immutable inventory before creating AppKit objects:

- One required `main` surface.
- Zero or more named panel surfaces.
- Authored size, attachment edge, initial visibility, background art, ordered regions, and declared component ownership for every surface.

`ReeltoneSurfaceCoordinator` reconciles this inventory with live windows. It creates, updates, or tears down the exact set of surface controllers on skin load, skin switch, UI reconstruction, and mode exit. `WindowManager` should depend on a small provider protocol rather than storing knowledge of every panel name.

### 4.4 Region rules

- Region coordinates and art use a top-left origin; AppKit uses bottom-left. Conversion occurs once at the surface boundary and is shared by drawing and hit testing.
- Region array order is paint order and hit-test order; the last eligible region under the pointer wins.
- Decorative regions never consume input.
- Elliptical clipping applies consistently to painting and hit testing.
- Multiple read-only or visualization regions are allowed.
- Stateful complex hosts (`trackList`, `equaliser`, `library`) are singletons per mode. A duplicate declaration produces a deterministic diagnostic and fallback behavior rather than duplicate stateful views.
- Resource paths resolve only inside the validated archive root.

### 4.5 Component reuse boundary

Reuse Original functionality through explicit content-only hosts:

| Reeltone component | NullPlayer implementation |
|---|---|
| Transport, shuffle, repeat, seek, volume | Thin bridge to existing `AudioEngine` and `WindowManager` commands/state |
| Title, elapsed, duration | Reeltone text renderer fed by existing playback updates |
| Artwork | Existing artwork state/loading path, clipped by the region shape |
| Visualiser | Reusable visualization/spectrum view with one consumer identity per instance |
| `trackList` | `ModernPlaylistView` in its existing embedded mode, generalized behind a host |
| `equaliser` | Extract or add a content-only embedded mode to the Original EQ view |
| `library`, `libraryBack` | Extract an embedded host from the Original library browser and route navigation through it |
| `togglePanel` | Surface coordinator visibility action targeting a validated panel name |
| `close`, `minimise` | Owning surface window action |

If a skin has no hosted region for Playlist, Equalizer, Library, or Spectrum, existing Window-menu and context-menu actions open the normal Original auxiliary window styled by the companion theme. If the component is hosted, those same actions focus or toggle its owning Reeltone surface instead of creating a duplicate.

### 4.6 Proposed source layout

```text
Sources/NullPlayer/Reeltone/
├── ReeltoneManifest.swift
├── ReeltoneArchive.swift
├── ReeltoneDiagnostics.swift
├── ReeltoneSkinLoader.swift
├── ReeltoneSkinStore.swift
├── ReeltoneSkinEngine.swift
├── ReeltoneThemeAdapter.swift
├── ReeltoneSurfaceInventory.swift
└── ReeltoneSkinState.swift

Sources/NullPlayer/Windows/Reeltone/
├── ReeltoneMainWindowController.swift
├── ReeltoneSurfaceWindowController.swift
├── ReeltoneSurfaceView.swift
├── ReeltoneRegionRenderer.swift
├── ReeltoneComponentBridge.swift
├── ReeltoneComponentHost.swift
└── ReeltoneSurfaceCoordinator.swift

Sources/NullPlayer/App/
└── ReeltoneSurfaceProviding.swift
```

Exact names may change during implementation, but the archive/model layer must remain independent of AppKit, and component adapters must remain separate from manifest decoding.

### 4.7 Storage and identity

- Install user skins under `~/Library/Application Support/NullPlayer/ReeltoneSkins/`.
- Persist a stable manifest ID plus an installation identity. Duplicate manifest IDs must not silently overwrite one another.
- Validate into a staging location before atomically moving a package into the store.
- Scope selected-skin state, surface visibility, panel frames, and UI geometry to the exact `.reeltone` mode and skin identity.
- Clamp restored windows to available screens only when presenting them; do not mutate authored geometry in the decoded model.

## 5. Phased Implementation

Each phase should be a reviewable change with its own tests and exit criteria. A later phase must not compensate for an incomplete earlier gate.

At the end of every phase, review the diff for blast radius: identify every modified file outside
the Reeltone subsystem, justify why that integration edit is unavoidable, and remove or relocate
any Reeltone behavior that can live in a Reeltone-owned file.

### Phase 0 — Baseline, decisions, and fixtures

Implementation steps:

1. From a dedicated worktree, create the implementation branch from the recorded `origin/main` commit, or refresh the baseline and update this document before coding. Never implement this subsystem from the primary checkout.
2. Record an architecture decision for the distinct Reeltone mode, separate engine, dynamic surface coordinator, and Original component-host boundary.
3. Create small, self-authored v1 and v2 fixtures covering one resource of each relevant type. Add malformed fixtures generated by tests rather than storing dangerous archives.
4. Decide and document the pixel-to-point rule. The default should be one authored pixel to one point at 100% UI Size, with AppKit backing scale handling Retina pixels.
5. Record Aqua Glass provenance and CC0 metadata before committing the archive. Until then, use the local file as a manual acceptance fixture and keep automated fixtures self-authored.
6. Create `skills/reeltone-skin-guide/SKILL.md` as the owning technical guide. New Reeltone subsystem details belong there, not in `AGENTS.md`.

Exit criteria:

- Architecture and scaling decisions are explicit.
- Fixtures can be used without network access.
- The implementation branch has no Winamp Modern dependency.

### Phase 1 — Mode shell and lifecycle seam

Implementation steps:

1. Add `PlayerUIMode.reeltone`, persistence/migration handling, menu selection, launch restoration, and exact-mode comparisons.
2. Replace binary mode decisions touched by this work with narrowly scoped capability checks.
3. Extend `WindowManager.reloadUI(to:)` to rebuild Reeltone mode without interrupting playback, casting, playlist, current track, or seek position.
4. Add a placeholder `ReeltoneMainWindowController` that hosts the standard Original main content until v2 surface rendering arrives.
5. Apply the Original 21-band EQ layout on mode entry.
6. Rebuild menus and context menus with a Reeltone skin selector/import entry visible only in this mode or when selecting a Reeltone skin.
7. Ensure main-window mode switching preserves the outgoing top-left position while using the incoming mode's own size.

Exit criteria:

- Classic, Original, Metal, and Reeltone can be switched live in both directions.
- Playback continues through every switch.
- Reeltone has independent persisted identity and geometry.
- Existing mode tests remain unchanged and pass.

### Phase 2 — Secure archive loader and skin store

Implementation steps:

1. Implement versioned v1/v2 manifest models with useful coding-path diagnostics.
2. Inspect ZIP metadata before extraction and reject absolute paths, traversal, symlinks, duplicate logical paths, and unexpected root layouts.
3. Enforce the published limits: 64 MiB uncompressed package size, images no larger than 2048 by 2048, and no more than 64 MiB of decoded image memory.
4. Add compressed-entry count and compression-ratio limits to prevent archive bombs even when the final uncompressed budget is nominal.
5. Decode images and register fonts lazily through validated resource handles. Respect explicit resource paths and PostScript names.
6. Validate required resources and component references before installation.
7. Implement atomic install, replacement, removal, discovery, preferred-skin selection, and structured diagnostics.
8. Keep extracted transient data in a per-load temporary directory with deterministic cleanup.

Exit criteria:

- Valid v1, valid v2, and Aqua Glass load into immutable models.
- Malformed JSON, unsupported versions, missing resources, corrupt images, path attacks, symlinks, duplicate paths, and budget violations fail safely.
- No archive-controlled path can escape its temporary or installed root.

### Phase 3 — Version 1 theme support

Implementation steps:

1. Map v1 screen, ink, panel, and panel-text values into `ReeltoneThemeAdapter`.
2. Render the placeholder Reeltone main using standard Original content with the adapted palette.
3. Style standard Original fallback Playlist, Equalizer, Library, and Spectrum windows through the same adapter.
4. Add import, discovery, selection, live skin switching, and restart restoration.
5. Ensure invalid preferred skins fall back to a bundled/default Reeltone theme without changing the user's Original preference.

Exit criteria:

- A v1 skin is usable as a distinct Reeltone mode.
- Every fallback auxiliary window has coherent colors and readable text.
- Selecting or failing to load a Reeltone skin cannot alter the selected Original skin.

### Phase 4 — Version 2 surface model and static rendering

Implementation steps:

1. Build the normalized surface inventory for the main surface and declared panels.
2. Implement borderless, nonopaque, shaped Reeltone windows with authored sizes.
3. Render surface background art and ordered decoration, text, and artwork regions.
4. Share top-left coordinate conversion between draw, layout, accessibility, and hit testing.
5. Support rectangular and elliptical clipping.
6. Implement generic window dragging from unclaimed regions while preserving component input.
7. Apply UI Size through a live scale multiplier; do not cache the global multiplier in view constants.
8. Verify exact output and interaction at 1x and 2x backing scales.

Exit criteria:

- Aqua Glass renders at the intended 960 by 384 authored size at 100%.
- Static regions align visually and hit-test at the same coordinates.
- Switching UI Size does not leave stale layer-backed content or distorted restored frames.

### Phase 5 — Aqua Glass functional vertical slice

Implementation steps:

1. Implement normal, hover, pressed, playing, playing-hover, and playing-pressed art-state selection.
2. Wire play, pause, stop, previous/rewind, next/forward, close, and minimise.
3. Implement seek sliders, volume sliders, and volume knobs with clamped value mapping.
4. Wire shuffle and repeat mode to existing state and notifications.
5. Render title, elapsed, duration, and elliptical artwork from live playback state.
6. Support multiple visualizer regions without consumer-registration collisions.
7. Implement frame animations and `drivenBy` behavior for playback, always, and never.
8. Invalidate only regions affected by state or animation changes.

Exit criteria:

- Aqua Glass can open media, control playback, seek, change volume, toggle shuffle/repeat, display metadata/artwork, and show both declared visualizers.
- Duplicate previous/next controls behave consistently.
- Animations stop when their surface is hidden or torn down.

This phase is the first user-testable compatibility milestone.

### Phase 6 — Declared panels and window topology

Implementation steps:

1. Create one `ReeltoneSurfaceWindowController` per declared panel.
2. Apply left, right, top, and bottom attachment rules relative to the owning surface.
3. Implement `togglePanel` with validated panel targets.
4. Track authored initial visibility separately from user-restored visibility.
5. Move, minimize, restore, hide, and apply Always on Top coherently across the surface set.
6. Add declared surfaces to the Window menu using stable skin-provided names or safe generated labels.
7. Persist panel visibility and floating position per exact skin identity.
8. Reconcile the live surface set safely when switching between skins with different panels.

Exit criteria:

- Multi-panel fixtures create the expected windows and attachments.
- Panel state restores only for the same Reeltone skin.
- Skin switching leaves no orphan windows, observers, timers, or audio consumers.

### Phase 7 — Hosted Original components

Implementation steps:

1. Define a generic component-host contract for sizing, focus, teardown, skin/theme updates, and visibility.
2. Host `ModernPlaylistView` through its embedded path and remove any remaining standalone-window assumptions.
3. Extract an embedded/content-only Original EQ surface while preserving the same 21-band model and commands as the fallback window.
4. Extract an embedded/content-only Original library browser surface, including `libraryBack` navigation.
5. Host reusable artwork and visualization views directly where their lifecycle permits it.
6. Route Playlist, Equalizer, Library, and Spectrum menu actions to the hosted owner when present; otherwise create the standard Original fallback window.
7. Define deterministic handling for duplicate singleton component declarations and report it in diagnostics.
8. Ensure custom-drawn hosted controls expose accessibility elements, labels, values, actions, focus, and keyboard operation.

Exit criteria:

- Fixtures can host Playlist, EQ, Library, and Visualization inside declared regions.
- No singleton component exists both hosted and standalone.
- Removing or hiding a host does not lose playlist, EQ, or library model state.
- Original standalone views behave exactly as before outside Reeltone mode.

### Phase 8 — Restoration, docking, Compact Mode, and teardown

Implementation steps:

1. Add the surface coordinator's dynamic controllers to the mode-dependent lifecycle snapshot rather than extending a fixed controller list for every panel.
2. Define synchronous teardown order: stop animation/render loops, unregister audio consumers, cancel tasks, remove observers, detach child windows, close controllers, and clear geometry caches.
3. Restore Reeltone main and panel frames only when the saved mode and skin identity match exactly.
4. Extend snapping/docking inventory to dynamic surfaces without changing existing Classic or Original adjacency behavior.
5. Preserve authored attachments until the user explicitly detaches a panel.
6. Reuse the existing Original compact browser/player surface for Compact Mode and Compact Window, themed through the Reeltone adapter; the Reeltone schema has no compact-surface declaration.
7. Preserve Reeltone regular-window state across Compact Mode entry, live mode switching while compact, and exit.
8. Verify teardown/rebuild repeatedly with the debug recreation path.

Exit criteria:

- Repeated mode switches and skin switches produce a stable controller/window/audio-consumer count.
- Compact Mode, Compact Window, docking, UI Size, minimization, and Always on Top work with zero orphaned Reeltone surfaces.
- A geometry snapshot from any other mode or Reeltone skin is never applied as an exact match.

### Phase 9 — Hardening, performance, and accessibility

Implementation steps:

1. Cache decoded resources by validated identity and account for their decoded-memory cost.
2. Coalesce playback and animation invalidation; do not redraw static surface art at audio callback frequency.
3. Start visualization consumers and timers only while their owning surface is visible, on-screen, and not miniaturized.
4. Add alpha-aware shaped-window hit testing where the manifest art requires it, with a documented threshold.
5. Add keyboard traversal and accessibility proxies for custom-drawn controls and text.
6. Exercise Unicode metadata and font fallback.
7. Add structured compatibility diagnostics that identify skin, surface, region index, component, resource, and severity.
8. Verify loading and switching under memory pressure and repeated malformed-package attempts.

Exit criteria:

- Idle or hidden Reeltone surfaces do not run display-rate work.
- VoiceOver can discover and operate every interactive region.
- Malformed skins cannot crash the app or leave partially installed state.
- Aqua Glass and synthetic fixtures meet the agreed rendering and interaction budget.

### Phase 10 — Full schema compatibility and release

Implementation steps:

1. Close remaining gaps for every published v2 component, control style, clip shape, art state, animation mode, and panel attachment.
2. Produce a compatibility report for Aqua Glass and the maintained fixture matrix.
3. Add user documentation for installing, selecting, switching, diagnosing, and removing Reeltone skins.
4. Document the supported schema version and intentional deviations in `skills/reeltone-skin-guide/SKILL.md`.
5. Run the complete automated and manual release matrix.
6. Remove any experimental feature gate only after the release criteria pass.

Exit criteria:

- Every published v1/v2 construct is either supported or produces an explicit, documented diagnostic.
- No known regression exists in Classic, Original, Metal, playback, casting, or app-state restoration.
- Reeltone mode is discoverable, reversible, and supportable from the application UI.

## 6. Test Strategy

### Unit tests

- Versioned manifest decoding and forward-compatible unknown fields.
- Archive path normalization, root discovery, symlink rejection, duplicate paths, and all resource budgets.
- Resource lookup and lazy image/font registration.
- Top-left to AppKit coordinate conversion at every UI Size.
- Rectangle/ellipse hit testing, z-order, control value mapping, animation frame selection, and panel attachment geometry.
- Mode capability policy, exact-mode persistence, skin-identity scoping, and migration.
- Hosted-versus-fallback component routing and duplicate singleton policy.
- Surface inventory reconciliation and teardown accounting.

### Integration tests

- Load, install, select, switch, remove, and restore v1/v2 skins.
- Switch Classic -> Reeltone -> Original -> Reeltone during active playback.
- Switch between two Reeltone skins with different main sizes and panel sets.
- Exercise compact entry/exit and UI Size changes with hosted and fallback components visible.
- Verify that old controllers cannot unregister newly created visualization consumers.

### UI and accessibility tests

- Expose stable accessibility identifiers for generated surfaces and regions.
- Invoke all Aqua Glass controls and assert playback/state changes.
- Open/focus hosted and fallback Playlist, EQ, Library, and Spectrum surfaces.
- Validate keyboard traversal, actions, values, and VoiceOver labels.
- Capture targeted 1x and 2x screenshots for geometry and clipping regressions.

### Manual matrix

- v1, minimal v2, Aqua Glass, multi-panel, hosted-components, and malformed fixtures.
- 1x and 2x displays; all supported UI Size values; multiple monitors; screen removal/reconnection.
- Local files, media-server playback, radio, video, casting, seek, pause/resume, and track changes.
- Docked and detached panels, minimization, Always on Top, Compact Mode, and Compact Window.
- Live mode switch, live skin switch, quit/relaunch restore, and reset-state behavior.

Minimum automated command at each phase gate:

```bash
swift test
```

UI phases also require a debug build/run and targeted manual verification using the repository workflow.

## 7. Pull Request and Rollout Strategy

- Use one focused pull request per phase or split a phase further when it touches both model and UI extraction work.
- Keep the mode unavailable in release UI behind a narrowly scoped experimental capability through Phase 4.
- Enable manual Aqua Glass testing after Phase 5.
- Do not combine Original EQ/library extraction with unrelated Original visual changes.
- Require before/after evidence for any shared `WindowManager`, persistence, docking, or Compact Mode change.
- Merge tests and owning-skill documentation with the code that introduces each contract.

Suggested milestones:

1. **Mode foundation:** Phases 0-3.
2. **Aqua Glass usable:** Phases 4-5.
3. **Dynamic topology and hosted components:** Phases 6-8.
4. **Release compatibility:** Phases 9-10.

## 8. Principal Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Original component views assume a standalone window | Introduce explicit embedded hosts; do not branch on fragile superview/window inspection |
| Dynamic windows escape fixed lifecycle lists | Give one coordinator ownership and expose its complete controller/window inventory |
| Shared mode code changes Classic or Original | Gate on exact mode/capabilities and keep regression tests for existing modes |
| Authored pixels, points, and Retina backing pixels are conflated | Normalize authored coordinates once and test 1x/2x plus every UI Size transition |
| ZIP/resource attacks or excessive image memory | Inspect before extraction, normalize paths, impose package/entry/image budgets, decode lazily |
| Duplicate stateful component regions produce split state | Enforce singleton ownership with deterministic diagnostics and fallback routing |
| Old visualization views remove new registrations during teardown | Use unique/ref-counted consumer identities and synchronous teardown gates |
| Skin switch restores incompatible panel geometry | Scope restoration to exact mode plus stable installation/skin identity |
| Fonts silently resolve the wrong face | Validate paths and register by explicit PostScript name with a visible fallback diagnostic |
| Large surface animations consume excessive CPU | Cache static layers, invalidate dynamic regions only, and pause hidden surfaces |

## 9. Definition of Done

Reeltone support is complete when:

- Reeltone is a distinct, persisted, live-switchable skin mode based on `origin/main` architecture.
- Aqua Glass is fully usable and visually aligned at 100% UI Size on 1x and 2x displays.
- v1 themes and published v2 surfaces, panels, regions, states, controls, and animations are supported or explicitly diagnosed.
- Main and panel windows are created from the skin manifest.
- Original Playlist, EQ, Library, artwork, and visualization functionality can be hosted in regions, with standard Original auxiliary fallbacks when absent.
- Mode/skin switching, restoration, UI Size, docking, Compact Mode, and teardown are deterministic and leak-free.
- Untrusted archives are bounded and cannot escape their resource root.
- Custom-drawn interactions are keyboard accessible and usable with VoiceOver.
- `swift test` passes and the manual matrix shows no Classic, Original, Metal, playback, casting, or persistence regressions.
- The owning Reeltone skill and user-facing documentation accurately describe the shipped behavior.
