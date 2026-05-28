# Development Workflow

## Running the App

```bash
./scripts/bootstrap.sh      # Download frameworks (first time only)
./scripts/kill_build_run.sh # Kill, build (release), and launch
```

The `kill_build_run.sh` script:
1. Kills any running NullPlayer instances (`pkill -9 -x NullPlayer`)
2. Builds in release mode (`swift build -c release`)
3. Launches in background (`.build/arm64-apple-macosx/release/NullPlayer &`)

Release mode is intentional — it matches the DMG distribution binary and catches optimization-related issues early. The script exits immediately after launch; the app continues independently.

```bash
pgrep -l NullPlayer  # Check if app is running
```

## Monitoring Logs (Cursor IDE)

When running the build script via the Shell tool with `is_background: true`, logs are captured to a terminal file:

```text
/Users/ad/.cursor/projects/Users-ad-Projects-adamp/terminals/<shell_id>.txt
```

**To find and monitor:**

```bash
# List recent terminal files
ls -lt /Users/ad/.cursor/projects/Users-ad-Projects-adamp/terminals/*.txt | head -5

# Monitor logs continuously
tail -f /Users/ad/.cursor/projects/Users-ad-Projects-adamp/terminals/<id>.txt

# Search for specific activity
grep -i "cast\|error\|fail" /Users/ad/.cursor/projects/Users-ad-Projects-adamp/terminals/<id>.txt
```

The terminal file shows `exit_code: 0` after the build script completes, but new logs from the running app continue to appear below that marker.

## Distribution

```bash
./scripts/build_dmg.sh           # Full release build + DMG
./scripts/build_dmg.sh --skip-build  # Use existing release build
```

Output:
- `dist/NullPlayer.app` — Application bundle
- `dist/NullPlayer-X.Y.dmg` — Distributable DMG with Applications symlink

The script builds a release binary, creates the app bundle, copies VLCKit.framework and libprojectM-4.dylib, fixes rpaths, and creates a DMG. The final summary prints the DMG's SHA256 — copy this value into the Homebrew cask on each release.

## Release flow (Homebrew cask)

NullPlayer is distributed via a personal tap at `ad-repo/homebrew-nullplayer` (`Casks/nullplayer.rb`). For each release:

1. Bump `CFBundleShortVersionString` (and `CFBundleVersion` if needed) in `Sources/NullPlayer/Resources/Info.plist`.
2. Run `./scripts/build_dmg.sh`. Note the printed `SHA256`.
3. Publish the DMG:
   ```bash
   gh release create vX.Y.Z dist/NullPlayer-X.Y.Z.dmg
   ```
4. In the `ad-repo/homebrew-nullplayer` repo, update `Casks/nullplayer.rb`:
   - Bump `version "X.Y.Z"`.
   - Replace `sha256 "..."` with the value from step 2.
   - Commit and push.
5. Verify locally:
   ```bash
   brew update
   brew install --cask ad-repo/nullplayer/nullplayer
   brew livecheck --cask ad-repo/nullplayer/nullplayer
   ```

The cask runs `xattr -cr` in `postflight` to clear the quarantine bit, because the DMG is currently ad-hoc signed only. Once Developer ID notarization is added to `build_dmg.sh`, that block can be removed.

## Versioning

**Single source of truth:** `Sources/NullPlayer/Resources/Info.plist`

1. Edit `Info.plist`:
   - `CFBundleShortVersionString` — Marketing version (e.g., `1.1`)
   - `CFBundleVersion` — Build number (e.g., `3`)
2. Run `./scripts/build_dmg.sh`

In code: `BundleHelper.appVersion`, `BundleHelper.buildNumber`, `BundleHelper.fullVersion`

## Debugging Protocol Integrations

For complex protocol issues (Chromecast, UPnP, etc.), create standalone Swift test scripts to isolate from the full app:

```bash
swift scripts/test_chromecast.swift
```

Benefits: faster iteration, isolated environment, easier debug output. See `skills/chromecast-casting/SKILL.md` for Chromecast-specific debugging.
