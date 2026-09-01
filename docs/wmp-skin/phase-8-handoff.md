# WMP skin Phase 8 handoff

## Repository state at phase start

```text
worktree: /Users/ad/Projects/nullplayer-wmp-skin-support
branch:   feat/wmp-skin-support
HEAD:     7cea7d998aa7ee4eb6a1183993840e6923026561
status:   clean except for the user-supplied, untracked skins/ corpus
```

## Delivered

- Public WMP mode in full debug and release editions, while preserving the custom-edition
  capability seam.
- Fresh profiles default to the dedicated unskinned WMP player without persisting a mode. Existing
  four-mode selections and the legacy modern-mode Boolean remain authoritative upgrade inputs.
- Public import, installed-skin selection/removal, authored-view selection, unskinned recovery, and
  bounded compatibility-report export. Removing an installed archive never removes its source file.
- The packaged `-uiMode wmp -wmpSkinPath /absolute/skin.wmz` diagnostic launch hook.
- Public user/support, compatibility, release-note, README, Mac App Store scope, skill, and routing
  documentation.
- Deterministic Windows-1252 fallback for unmarked legacy WMP text, without locale/code-page
  guessing; UTF BOM validation, malformed UTF-16 rejection, and embedded-NUL rejection remain.
- Real-skin repairs found during Corona verification: IDs resolve within the active authored view;
  sliders without explicit dimensions derive their hit geometry from authored track artwork;
  `wmpenabled:` updates its authored property (including `visible`); and mapped button groups mask
  hover/down artwork to the active mapping region rather than changing every button.

## Public/default and upgrade evidence

- A clean full-edition defaults domain resolves to `.wmp`, creates `WMPMainWindowController`, and
  presents `WMPUnskinnedMainView` without reading Original/Classic preferences.
- Explicit `.classic`, `.modern`, `.metal`, and `.wmp` values round-trip unchanged.
- Both legacy `modernUIEnabled` values retain their previous meanings when the current mode key is
  absent.
- Missing, deleted, corrupt, or rejected selected skins remain in WMP mode and recover to the
  app-authored unskinned player.

## Real-skin findings

The user-supplied `skins/` directory is local input and remains untracked. A live debug launch of
`corona.wmz` confirmed that the full three-slice top chrome renders after view-local ID scoping and
that stopped state exposes the Play artwork after preserving `visible` bindings. The earlier live
playback attempt accidentally addressed a separately registered NullPlayer instance; it is not
counted as evidence. Seek dispatch remains covered by the real local-file audio host path and the
Corona-compatible implicit slider hit geometry, but should receive another single-instance live UI
pass before a release tag.

## Verification

```text
focused WMP suite: 91 executed, 5 expected opt-in skips, 0 failed
full swift test before the subsequent Corona repairs: 523 executed, 5 expected skips, 0 failed
Corona render dump after view-local ID repair: full title chrome present
swift build: passed after the runtime repairs
git diff --check: passed
```

The release application and helper previously built and signed successfully, producing
`dist/NullPlayer-0.29.8.dmg`; the Phase 0 packaging verifier and strict code-sign verification
passed. A release-mode test bundle still cannot compile because unrelated test-only helper APIs are
guarded by `#if DEBUG`; the production release app and isolation helper themselves compile and link.

## Shared-path audit

- `AppCapabilities`: public full-edition exposure must use the shared edition capability seam; a
  WMP-local alternative cannot make the mode available to application menus/factories.
- `PlayerUIMode` and `AppStateManager`: fresh default, upgrade precedence, and diagnostic override
  are global mode-selection concerns; they are explicitly gated to the WMP value.
- `AppDelegate` and `ContextMenuBuilder`: packaged diagnostics and public mode/skin actions require
  application-level routing; skin parsing, storage, reporting, and rendering remain WMP-owned.
- Global README, changelog, App Store scope, AGENTS routing, and user-guide skill changes document
  the newly public mode. No Classic, Original, or Winamp Modern renderer was changed.

## Provenance and exclusions

No third-party skin archive, artwork, screenshot, source text, render dump, or corpus report is
tracked. No implementation code or artwork was copied from the local corpus, so no new third-party
notice is required. The build refreshed and validated the existing generated notices.

Physical multi-display, sleep/wake, approved streaming/radio playback, and distribution-credential
Mac App Store signing remain release-candidate manual checks.
