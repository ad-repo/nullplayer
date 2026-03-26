# CI Unit Tests — Blocked Issue

## Status

Unit tests and the `NullPlayerTests` test target were removed in commit `bfcac17` because they could not compile on CI.

## The Problem

The `NullPlayer` SPM target depends on `SQLite.swift` (pinned to 0.15.4 via `Package.resolved`). On CI (GitHub Actions `macos-14` runner, Xcode 16.2), the `NullPlayer` target fails to compile with:

```
error: missing argument label 'value:' in call
```

on every `Expression<T>("column_name")` call in the SQLite store files:

- `Data/Models/MediaLibraryStore.swift`
- `Data/Models/LocalRadioHistory.swift`
- `Radio/RadioStationFoldersStore.swift`
- `Radio/RadioStationRatingsStore.swift`
- `Visualization/ProjectMPresetRatingsStore.swift`
- `Emby/EmbyRadioHistory.swift`
- `Jellyfin/JellyfinRadioHistory.swift`
- `Plex/PlexRadioHistory.swift`
- `Subsonic/SubsonicRadioHistory.swift`

The same code compiles and runs fine locally (macOS 26 / newer Xcode). This is a CI-environment-specific issue.

Since `NullPlayerTests` depended on the `NullPlayer` target, the build error meant **zero** tests could run — there were no individual passing tests to preserve.

## What Was Tried

1. Pinning SQLite.swift to `0.15.x` via `.upToNextMinor(from: "0.15.4")` in `Package.swift`
2. Bumping the SPM cache key in CI to bust a potentially stale cache
3. Committing `Package.resolved` to lock the exact version (0.15.4)

None resolved the CI compile error.

## Likely Root Cause

SQLite.swift 0.15.4 compiles differently under Xcode 16.2 on macOS 14 vs newer local toolchains. The `Expression<T>(_ identifier: String)` initializer (column reference) may not be visible to the compiler in that environment, causing it to fall through to `Expression<T>(value: T)` and report the label mismatch.

Possible explanations:
- A Swift language mode difference between local and CI toolchains
- A module visibility or overload resolution difference in Swift 6.0.x (Xcode 16.x ships Swift 6)
- SQLite.swift 0.15.4 has a latent incompatibility with Swift 6 even when the package itself is compiled in Swift 5 mode

## Options to Fix

1. **Upgrade SQLite.swift to 0.16+** and update all `Expression<T>("col")` calls to the new API — the 0.16+ API change is exactly the `value:` label that CI is already demanding, so this may be the right path.

2. **Split the test target** — create a `NullPlayerCoreTests` target that depends only on `NullPlayerCore` (no SQLite), move tests that don't touch SQLite stores there, and run those in CI.

3. **Investigate the Swift toolchain difference** — compare Swift versions between local and CI, and check whether SQLite.swift 0.15.4 compiles cleanly under `swift-6.0.x` in strict mode.

## Test Files

The deleted test files are in git history at commit `9162fc2` (the commit before `bfcac17`) and can be restored with:

```bash
git checkout 9162fc2 -- Tests/NullPlayerTests
```
