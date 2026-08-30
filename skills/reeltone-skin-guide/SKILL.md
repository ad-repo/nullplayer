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
- Version 1 accepts sprite mode `fill` as documented by the format guide. Version 2 additionally
  follows the frozen schema vocabulary while ignoring unknown additive object fields.

## Phase 3 theme boundary

- `ReeltoneThemeAdapter` maps v1 `screen`, `ink`, `inkDim`, `panel`, and `panelText` values into a
  transient programmatic Original skin. It normalizes `#RRGGBBAA` to the RGB channels supported by
  the Original palette and substitutes a readable built-in value for malformed or missing colors.
- `ModernSkinEngine.activateTransientSkin` is the sole shared rendering seam. It must not write
  `modernSkinName` or `metalSkinName`; returning to either Original family reloads that family's
  independently persisted selection.
- The Reeltone runtime activates the adapter before creating its main or fallback auxiliary
  controllers. Playlist, Equalizer, Library, and Spectrum therefore share one coherent palette.
- The menu discovers only store-validated installations. Import and selection go through
  `ReeltoneSkinEngine`; no menu action extracts an archive directly.
- A missing or invalid preferred installation renders the built-in Reeltone theme and never
  changes either Original-family preference.
