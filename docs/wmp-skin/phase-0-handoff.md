# WMP skin Phase 0 handoff

## Repository state at phase start

```text
pwd:    /Users/ad/Projects/nullplayer-wmp-skin-support
branch: feat/wmp-skin-support
status: clean
HEAD:   a746d8c7e5a8d72f548bb8761b9ecd3c9cea1534
```

## Delivered

- Locked Phase 0 limits and stable `WMP0001`–`WMP0020` diagnostics.
- Metadata-first, read-only ZIP audit with normalized path policy, symlink/collision checks, aggregate
  limits, CRC verification, bounded XML counting, and BMP/script header limits.
- NullPlayer-owned deterministic fixture corpus and generator.
- Bundled JavaScriptCore helper with a length-prefixed bounded protocol, bare JSON-only realm,
  callback/timer caps, address-space/file-descriptor limits, parent deadline, forced termination,
  synchronous reap, and clean replacement.
- DMG/MAS helper assembly and inside-out signing paths plus a packaging verifier.
- Separate GO decisions for Phase 1 and Phase 5 in `phase-0-decision-record.md`.

## Review map

- Contracts/auditor: `Sources/NullPlayer/WMPSkin/WMPPhase0Policy.swift`
- Parent deadline/restart harness: `Sources/NullPlayer/WMPSkin/WMPScriptIsolation.swift`
- Isolated evaluator: `Sources/WMPScriptIsolationHelper/main.swift`
- Corpus: `Tests/NullPlayerAppTests/Fixtures/WMPSkin/`
- Tests: `Tests/NullPlayerAppTests/WMPPhase0Tests.swift`
- Packaging: `Package.swift`, `scripts/lib/assemble_app.sh`, `scripts/build_dmg.sh`,
  `scripts/build_mas.sh`, and `scripts/verify_wmp_phase0_packaging.sh`

## Gates

Run from this worktree:

```bash
./scripts/bootstrap.sh
swift build -c debug
swift test --filter WMPPhase0ArchiveTests
swift test --filter WMPScriptIsolationTests
swift test
git diff --check
```

Agent development uses debug builds. Do not build a DMG unless the user explicitly requests one.
The packaging verifier remains available for a release operator to run against an assembled app.

The MAS assembly path requires the repository's existing `MAS_APP_IDENTITY`,
`MAS_INSTALLER_IDENTITY`, and `MAS_PROVISION_PROFILE` credentials. Its nested-helper signing command
uses the same restricted helper entitlements as the verified DMG assembly.

## Phase 1 boundary

Phase 1 may promote the audit types into the production WMP loader but must not expose a UI mode,
install a skin before the entire archive/graph succeeds, relax a Phase 0 bound, or run any skin script.
Scripted support remains unavailable until the Phase 5 bridge repeats the helper security gate.

## Repository state at phase end

```text
pwd:    /Users/ad/Projects/nullplayer-wmp-skin-support
branch: feat/wmp-skin-support
status: clean after committing this handoff
Phase 0 implementation HEAD: f3bab57a
```

Final build and test verification used debug artifacts. Packaging verification used the already
assembled app and did not trigger another DMG build:

```text
swift build -c debug: passed
WMPPhase0ArchiveTests: 4 passed
WMPScriptIsolationTests: 4 passed
swift test: 440 passed, 0 failed (29.896 s)
git diff --check: passed
helper packaging verifier: passed against the assembled app
codesign --verify --deep --strict: passed against the assembled app
```
