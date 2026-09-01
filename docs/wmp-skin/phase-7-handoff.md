# WMP skin Phase 7 handoff

## Repository state at phase start

```text
pwd:    /Users/ad/Projects/nullplayer-wmp-skin-support
branch: feat/wmp-skin-support
HEAD:   ce7a12c3ca407dbf5c3d1e7597ce962e41be0ce6
status: clean except for the user-supplied, untracked skins/ corpus
```

## Delivered

- `WMPCorpusReportHarness`, a reusable WMP-owned analyzer that emits archive hashes/facts, complete
  compatibility demand and unknowns, typed diagnostics, cold/warm load metrics, per-view 1×/2× and
  warm render metrics, resize/hit/repaint/cache measurements, and a confidence grade. It serializes
  no source text, archive payload, pixel buffer, screenshot, or local input path.
- Opt-in corpus routing through `WMP_CORPUS_PATH` and external JSON retention through
  `WMP_CORPUS_REPORT_DIR`. The default local `skins/` directory remains untracked and read-only.
- Deterministic adversarial coverage for 128 archive metadata/payload mutations and 512 rounds of
  text, XML, path, attribute/color, mapping-buffer, and image-decode inputs. Outcomes are success or
  typed WMP failure; no trap or unbounded allocation was observed.
- One hundred rapid load/view/resize/cache-teardown cycles with bounded cache and file-descriptor
  assertions. Existing production tests additionally repeat 100 fresh realms and 100 hostile
  hard-stop/restart cycles, 20 complete four-family controller cycles, timer storms, view switching,
  and synchronous teardown.
- A bounded helper stdout reader. The parent now enforces the 1 MiB response limit while reading,
  rejects oversized script/globals before process launch, caps crash stderr, and exposes only a
  read-only active-process count for teardown evidence.
- Backing-scale-aware WMP presentation. The controller renders at the active window scale and
  rebuilds after backing-property changes; original fixtures continue to verify exact 1× and 2×
  orientation/pixels.
- Stable accessibility-tree replacement tests for custom buttons and sliders, alongside the Phase 6
  native-surface and full/tiny view accessibility coverage.
- A narrow corpus-driven compatibility default: an empty optional image is a `WMP0023` warning and
  cannot reject the surrounding skin. Direct provider escape remains a hard failure.
- Compatibility demand matching is case-insensitive, known semantic transport tags are classified
  correctly, and event scanning no longer reports arbitrary words beginning with `on`.

## Corpus evidence

The opt-in corpus contained 14 user-supplied archives. Four loaded and produced ten measured views;
ten rejected safely with typed diagnostics. No archive, artwork, screenshot, render dump, or report
is tracked.

- Seven rejected with `WMP0025` because authored text is not strict UTF-8/UTF-16LE/UTF-16BE.
- Three rejected with `WMP0027` because the skin repeats an XML attribute, which is not well-formed.
- The empty-optional-image compatibility default admitted one additional corpus skin without
  weakening path or archive limits.
- Remaining accepted-skin demand is reported for custom slider/edit/list controls, legacy effects
  and video settings, playlist variants, appearance attributes, and denied object-model members.

One debug corpus run measured accepted skins as follows. These are observations, not cross-machine
performance budgets:

| Measurement | Observed range |
|---|---:|
| Cold load | 28.73–361.33 ms |
| Warm load | 29.34–361.14 ms |
| First 1× render | 3.17–17.78 ms |
| Warm 1× render | 0.21–2.64 ms |
| 2× render | 0.87–8.10 ms |
| Resize layout | 0.74–6.38 ms |
| Hit test | 1.04–66.94 µs/sample |
| Peak decoded cache | 1,139,764 bytes |

## Security and packaging audit

- Request IDs are authenticated by exact response matching; JSON shape/count limits, finite-number
  validation, 1 MiB frame bounds, 16 MiB session accounting, capability allowlists, process deadline,
  termination/reaping, and fresh-realm recovery remain covered by the Phase 0/5 suites.
- The existing assembled `dist/NullPlayer.app` passes deep code-sign verification and
  `scripts/verify_wmp_phase0_packaging.sh`; its nested helper carries App Sandbox and no network
  entitlement. DMG/MAS assembly scripts sign the nested helper before the enclosing app.
- WMP remains explicitly unavailable in release/MAS products through `AppCapabilities.wmpSkinMode`
  until Phase 8. Therefore the Phase 7 packaging gate takes its allowed unavailable-product branch.
  No new DMG was built, in accordance with the owning skill, and credentialed MAS packaging was not
  attempted. Phase 8 must repeat an in-product helper launch after public capability enablement.

## Release-candidate gate status

Automated implementation gates pass. Public exposure remains blocked on the live/operator matrix:
stream/radio playback, docking and menus, multiple physical displays, minimize/occlusion,
sleep/wake, route change, steady-playback CPU, and credentialed distribution packaging. These require
approved streams, hardware/display state, user interaction, or signing credentials and were not
simulated. Known unsupported behavior is present in compatibility reporting and degrades safely.

## Shared-path audit

No shared/global source path changed. Production edits are under `Sources/NullPlayer/WMPSkin/` and
`Sources/NullPlayer/Windows/WMPSkin/`; tests, compatibility docs, this handoff, and the owning skill
are WMP-owned paths. The backing-scale correction is local to the WMP controller. No Classic,
Original, Original-Metal, Winamp Modern, `AudioEngine`, menu, persistence, or packaging source was
changed.

The planning worktree remains unchanged. The `/Users/ad/Projects/nullplayer` checkout retains its
pre-existing unrelated state. The untracked implementation `skins/` directory remains untouched.

## Verification

```text
focused Phase 7 suite: 8 passed, 0 failed
focused compatibility/bridge/Phase 7 suite: 20 passed, 1 expected opt-in skip, 0 failed
complete swift test with WMP_TEST_WMZ=skins/9SeriesDefault.wmz:
  517 passed, 1 expected stream skip, 0 failed (40.900 s post-commit verification)
100 hostile helper hard-stop/restart cycles: passed
100 production fresh-realm cycles: passed
100 rapid load/view/resize/cache cycles: passed
14-skin local corpus report: 4 accepted, 10 typed rejections
packaged helper signature/sandbox/no-network verification: passed
git diff --check: passed
```

Pre-existing SQLite privacy-resource, deprecated OpenGL, aubio deployment-target, and local shader
warnings remain.

## Repository state before phase commit

```text
pwd:    /Users/ad/Projects/nullplayer-wmp-skin-support
branch: feat/wmp-skin-support
HEAD:   ce7a12c3ca407dbf5c3d1e7597ce962e41be0ce6
status: Phase 7 WMP-owned changes plus the user-supplied, untracked skins/ corpus
```
