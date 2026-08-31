---
name: reeltone-skin-guide
description: Reeltone mode boundaries, lifecycle integration, persistence, menus, archive loading, and surface rendering.
---

# Reeltone Skin Guide

Read `docs/reeltone-skin-mode-plan.md` before changing Reeltone support. That plan is the source of
truth for phase scope, exit criteria, security requirements, and implementation progress.

## Containment rule

Keep substantive implementation in `Sources/NullPlayer/Reeltone/` and
`Sources/NullPlayer/Windows/Reeltone/`. Shared `App/` edits are limited to unavoidable, narrowly
gated integration seams. An existing mode must never acquire changed behavior merely because a
Reeltone branch is expected to be a no-op.

At every phase boundary, audit all changed files outside the Reeltone directories and justify each
one against the plan's blast-radius rule. Prefer a Reeltone-owned adapter or provider over adding
Reeltone logic to an existing skin engine.

## Phase 1 shell

- `PlayerUIMode.reeltone` is a distinct persisted mode.
- Reeltone uses the 21-band EQ and Original auxiliary controllers through explicit capabilities.
- `ReeltoneMainWindowController` owns the main window and temporarily hosts Original main content.
- `ReeltoneSkinState` owns the selected-skin identity; it is independent of Original and Metal.
- Reeltone menu construction and actions live in `ReeltoneMenuBuilder`.
- Secure `.reeltone` import is intentionally disabled until Phase 2 validation and installation
  exist. Do not copy or inspect an untrusted archive from the Phase 1 menu shell.
- Live mode switches preserve playback state and the outgoing main window's top-left anchor while
  using the incoming mode's native size.

## Existing-mode boundaries

Do not change Classic, Original, Original-Metal, or Winamp Modern rendering to implement Reeltone.
Reeltone must not depend on `WinampModern/`. If shared behavior must be generalized, document why a
Reeltone-local implementation cannot provide correct lifecycle or state behavior and add regression
coverage for every existing mode affected by the seam.

## Phase 2 archive and store boundary

- `ReeltoneSkinEngine` owns selection and delegates package work to `ReeltoneSkinStore` and
  `ReeltoneSkinLoader`; UI integration must not extract archives directly.
- Inspect ZIP central-directory metadata before creating any archive-controlled path. Reject
  absolute paths (including Windows drive paths), traversal, backslashes, symlinks, canonically or
  case-equivalent duplicates, file/directory collisions, and a non-root `skin.json`.
- The package limits are 1,024 entries, 64 MiB total uncompressed data, and a maximum 1,000:1 ratio
  for each non-empty compressed entry. The first two are hard caps; the ratio is NullPlayer's
  additional archive-bomb defense.
- Resource paths are validated once and represented by `ReeltoneResourceHandle`. Image and font
  objects are created lazily from handles. Installation validation still forces one image decode so
  corrupt art, dimensions over 2048 by 2048, and more than 64 MiB of aggregate RGBA memory fail
  before the package can enter the store.
- Temporary archive loads own a `ReeltoneLoadedSkin` cleanup root. Call `close()` when replacing a
  live load; deinitialization is a fallback. Installed loads never own or remove their store root.
- Installations live at `Application Support/NullPlayer/ReeltoneSkins/<installation UUID>/` with a
  store-owned metadata record. Manifest IDs are metadata, not directory names, so installing the
  same manifest ID twice cannot overwrite an existing skin.
- Validate a complete sibling staging directory before an atomic rename or replacement. Discovery
  revalidates the manifest/resources and returns structured diagnostics for invalid entries rather
  than exposing them as selectable skins.
- Version 1 accepts sprite mode `fill` as documented by the format guide. Its fixed-deck sprites
  are safety-validated but not rendered by the Original-content adapter; emit one structured
  `unsupportedConstruct` warning per declared sprite. Version 2 additionally follows the frozen
  schema vocabulary while ignoring unknown additive object fields; its top-level fixed-deck sprite
  slots receive the same explicit warning because shaped surfaces do not consume them.

## Phase 3 theme boundary

- `ReeltoneThemeAdapter` maps v1 `screen`, `ink`, `inkDim`, `panel`, and `panelText` values into a
  transient programmatic Original skin. It normalizes `#RRGGBBAA` to the RGB channels supported by
  the Original palette and substitutes a readable built-in value for malformed or missing colors.
- Map v1 built-in and packaged fonts into the transient presentation. Validate a packaged font's
  PostScript name before installation; never defer malformed-font failure until first draw.
- `ModernSkinEngine.activateTransientSkin` is the sole shared rendering seam. It must not write
  `modernSkinName` or `metalSkinName`; returning to either Original family reloads that family's
  independently persisted selection.
- The Reeltone runtime activates the adapter before creating its main or fallback auxiliary
  controllers. Playlist, Equalizer, Library, and Spectrum therefore share one coherent palette.
- The menu discovers only store-validated installations. Import and selection go through
  `ReeltoneSkinEngine`; no menu action extracts an archive directly.
- A missing or invalid preferred installation clears only the stale Reeltone identity, renders
  the built-in Reeltone theme, and never changes either Original-family preference.

## Phases 4–7 surface and hosting boundary

- `ReeltoneDefaults.shared` is the only production defaults domain for Reeltone-owned state. It
  uses the `com.nullplayer.app.reeltone` suite and migrates only legacy Reeltone selection/surface
  keys out of app-standard defaults. Inject it into embedded and Reeltone fallback Original views;
  never let those views read or write another skin family's presentation preferences. AudioEngine,
  playlist, and library content remain shared application models, not skin defaults.
- The v1 Original-content fallback also receives the Reeltone domain. Its Cava and vis_classic
  mini-visualizer modes are intentionally filtered out because those engines still own app-domain
  preference graphs; allowing them here would violate the isolation boundary.
- `ReeltoneSurfaceInventory` is the normalized source of truth for the main surface, sorted panel
  surfaces, authored top-left geometry, and deterministic singleton ownership. Draw, layout,
  accessibility, and hit testing must continue to use its shared coordinate conversion.
- `ReeltoneSurfaceCoordinator` owns all manifest-declared panel controllers. Persist visibility,
  detached state, and floating frames by exact installation identity; suppress persistence during
  topology teardown and temporary main-window hide/minimize operations.
- Reeltone surface windows are borderless, nonopaque, fixed to authored dimensions times the live
  UI scale, and draggable only through unclaimed regions. Rectangular and elliptical clipping
  apply equally to painted and hosted content.
- `ReeltoneComponentBridging` is the narrow transport/state seam. Region updates should invalidate
  only affected rectangles, and animation timers must run only while their surface and driver are
  active.
- `ReeltoneComponentHosting` owns embedded lifecycle, focus, theme refresh, visibility, and
  teardown. Playlist, EQ, and Library use content-only modes; those modes must retain unchanged
  defaults for every standalone Original window.
- Playlist, Equalizer, Library, and Spectrum menu actions route to the declared hosted owner first
  and otherwise retain the Original standalone fallback. When a skin begins hosting a singleton,
  retire any stale standalone controller before exposing the new host.
- Shared `App/` changes for these phases are limited to the `ReeltoneSurfaceProviding` seam,
  exact-mode menu routing, Window-menu panel entries, UI scaling, Always on Top, and dynamic window
  enumeration. Do not allow these branches to affect Classic, Original, Original-Metal, or Winamp
  Modern behavior.

## Phases 8–10 lifecycle and release boundary

- Dynamic panel layout is part of the provider-owned mode lifecycle snapshot. Restore it only
  when the exact installation identity matches; quit-session main geometry also requires that
  identity match and is clamped to available screens only when presented.
- Teardown is synchronous: stop animation and hosted rendering, unregister consumers, cancel
  artwork work, order out and close panels, then release the coordinator before closing main.
- Authored panel attachments remain exact during main-window moves; recompute their authored frame
  instead of applying a second docking delta. A user drag away from that frame records detachment.
- `ReeltoneLoadedSkin` owns the shared decoded-image cache and accounts its bytes against the same
  64 MiB limit validated at installation. Surface views must not create per-window image caches.
- Animation and visualization work runs only while the owning surface is effectively visible;
  spectrum invalidation is coalesced to the main run loop.
- Shaped-window hit testing samples the active chassis image in normalized top-left coordinates.
  Pixels with alpha below `3/255` pass through unless a declared region covers the point; sampling
  reuses the shared decoded image and must not retain a second full-size alpha mask.
- Diagnostics for surface compatibility include severity plus skin, surface, region, component,
  coding path, and resource fields where applicable.
- Reeltone intentionally does **not** support Compact Mode or Compact Window. Hide their menu
  entries, reject programmatic entry, and exit an existing compact presentation before switching
  into `.reeltone`. A Compact Mode -> Reeltone switch must restore `.regular` activation and
  mode-independent app panels without briefly restoring the outgoing mode's player windows.
- The shipped compatibility matrix and intentional deviations live in
  `docs/reeltone-compatibility.md`. Keep it synchronized with schema support.

### Reeltone integration verification

Run the real local-playback and compact-transition sequence in a disposable fixed home:

```bash
mkdir -p /private/tmp/reeltone-live-switch-home
env CFFIXED_USER_HOME=/private/tmp/reeltone-live-switch-home \
  NULLPLAYER_RUN_REELTONE_LIVE_SWITCH_TEST=1 \
  swift test --filter ReeltoneModeSwitchIntegrationTests
```

This opt-in test uses a generated PCM WAV and the production `AudioEngine`/`WindowManager`. It
keeps Spectrum and ProjectM open and verifies their aggregate audio-consumer registration count is
unchanged across bidirectional Classic, Original, Original-Metal, and Reeltone switches. It also
verifies track, playlist, seek, play state, and cast-state continuity; both compact entry paths;
regular activation; compact-controller disposal; and restoration of a mode-independent panel.
