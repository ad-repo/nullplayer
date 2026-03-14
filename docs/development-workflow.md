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

The script builds a release binary, creates the app bundle, copies VLCKit.framework and libprojectM-4.dylib, fixes rpaths, and creates a DMG.

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
