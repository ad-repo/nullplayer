# WMP skin Phase 3 handoff

## Repository state at phase start

```text
pwd:    /Users/ad/Projects/nullplayer-wmp-skin-support
branch: feat/wmp-skin-support
HEAD:   77b4beed12523b094722f82131c5541a855821ba
status: clean except for the user-supplied, untracked skins/ corpus
```

## Phase 2 gate remediation

Phase 3 began only after replacing Phase 2's literal-only geometry limitation with
`WMPInitialLayoutExpression`, a bounded static evaluator for finite arithmetic and deterministic
geometry references. It does not execute JScript, calls, assignments, statements, or script globals.
On the real untracked `9SeriesDefault.wmz`, the recognizable `vPlayer` render now resolves 47 nodes
instead of 15, so the recorded Phase 2 decision is **GO**.

## Delivered

- An explicit `.wmp` `PlayerUIMode` and `.wmp` controller family. WMP is neither Classic nor a
  `ModernSkinFamily`; its capability and menu exposure remain DEBUG-only.
- A dedicated `WMPMainWindowController`, `WMPMainView`, and app-authored
  `WMPUnskinnedMainView`. Missing, deleted, corrupt, or unselected skins remain in WMP mode and never
  instantiate another skin family's main controller.
- `WMPSkinImporter`, owning `Application Support/NullPlayer/WMPSkins`, pre-commit archive
  validation, installed enumeration, same-directory atomic replacement, selection, and reset.
- DEBUG launch support through `-uiMode wmp -wmpSkinPath /absolute/path/skin.wmz`, applied after
  restoration so persisted state cannot override or cancel an explicit test launch.
- Exact WMP mode/skin/view persistence and geometry restore. Older state decodes safely; mismatched
  identities retain only a safely clamped top-left position and never inherit shared UI scale.
- Explicit WMP factory, reload, teardown, frame, and compact-mode branches in `WindowManager`.
  Teardown cancels loading and releases the archive, scene, image store, and callbacks.
- A dedicated Windows Media Player UI menu for loading, selecting, resetting, and locating installed
  `.wmz` skins.
- Cross-family auxiliary-window prevention. In WMP mode, existing Classic, Original, and Winamp
  Modern EQ, playlist, library, and visualization actions are disabled and their controller entry
  points refuse creation. They remain unavailable until Phase 6 provides WMP-owned hosted chrome.

## Native-window appearance contract

The plan and owning skill now state the requirement explicitly: every NullPlayer-owned native
window exposed in WMP mode must be wrapped in chrome derived from the active `.wmz`, including
borders, title/window controls, colors, metrics, resize affordances, and docking treatment. The
implementation must use a WMP-owned hosted-window registry/style snapshot. It must not import,
subclass, or visually fall back to Classic, Original, or Winamp Modern chrome. Missing WMP chrome
uses only a documented app-authored WMP-neutral fallback.

This resolves the observed upside-down/backwards EQ title: that was a Classic fallback window being
shown while WMP was active, not a coordinate error in the WMP loader. The shared Classic renderer
was left unchanged; Phase 3 instead prevents that invalid cross-family fallback.

## State and failure behavior

- Import work and complete archive validation run off the main actor; UI swaps return to main.
- Installation is committed only after successful validation and uses atomic replacement within the
  destination directory. A failed replacement preserves the prior installed skin and selection.
- An invalid remembered selection produces an actionable unskinned WMP surface; it does not switch
  modes or consult another skin engine.
- Release builds reject `.wmp` selection and normalize stale WMP mode state to Classic while the
  experimental capability remains disabled.
- Compact Mode, Compact Window, and shared UI scaling are unavailable in WMP until implemented by
  the WMP family.

## Shared-path audit

Shared `App/` files changed only where an explicit controller-family or persistence branch is
required. Every WMP behavior is gated by `.wmp` or `AppCapabilities.wmpSkinMode`; Classic, Modern,
and Metal retain their prior factory and runtime paths. No file under `Skin/`, `ModernSkin/`,
`WinampModern/`, or existing feature-window implementations changed.

The implementation mirror and canonical planning-worktree copy of
`docs/wmp-skin-integration-plan.md` were both updated with the native-window appearance contract.
`skills/wmp-skin-guide/SKILL.md` owns the corresponding implementation invariant. The original
`/Users/ad/Projects/nullplayer` checkout was not modified.

## Verification

```text
focused WMP Phase 3 suite: 8 passed, 0 failed
complete WMP suite: 45 executed, 2 expected opt-in skips, 0 failed (23.352 s)
9SeriesDefault all-view render: 1 passed, 0 failed
full swift test: 478 passed, 2 expected opt-in skips, 0 failed (31.177 s)
release swift build: passed
git diff --check: passed
vPlayer: 859x468 canvas, 47 resolved / 31 unresolved,
         visible x=250 y=0 346x344, 419,632-byte peak cache, 21.71 ms render
viewTiny: 596x468 canvas, 7 resolved / 2 unresolved,
          visible x=250 y=0 346x266, 858,420-byte cumulative peak cache, 5.01 ms render
```

Real skin archives and render dumps remain untracked; the final dump is under
`/private/tmp/wmp-phase3-final-render/`. The build retained the repository's existing warnings,
including the SQLite privacy resource, deprecated APIs, Swift concurrency diagnostics, and aubio
deployment target mismatch.

## Next work

Phase 4 adds mapping-image hit testing and the narrow playable transport host. It must preserve the
dedicated WMP controller boundary established here. Native auxiliary windows stay disabled until
the WMP-owned hosted chrome work specified in Phase 6 is complete.
