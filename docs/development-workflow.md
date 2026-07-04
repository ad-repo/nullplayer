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

### DMG (Direct Download)

```bash
./scripts/build_dmg.sh           # Full release build + DMG
./scripts/build_dmg.sh --skip-build  # Use existing release build
```

Output:
- `dist/NullPlayer.app` — Application bundle
- `dist/NullPlayer-X.Y.Z.dmg` — Immutable, versioned DMG for archives, checksums, and Homebrew
- `dist/NullPlayer.dmg` — Stable-name copy for human-facing download links

The script builds a release binary, creates the app bundle, copies VLCKit.framework and libprojectM-4.dylib, fixes rpaths, creates the versioned DMG, and copies it to the stable `NullPlayer.dmg` filename. The final summary prints the versioned DMG's SHA256 — copy this value into the Homebrew cask on each release.

### Mac App Store

```bash
./scripts/build_mas.sh           # Full release build + signed installer package
./scripts/build_mas.sh --skip-build  # Use existing release build
```

Output:
- `dist/NullPlayer.app` — Signed application bundle
- `dist/NullPlayer-X.Y.Z.pkg` — Installer package for App Store submission

Requires environment variables (`MAS_APP_IDENTITY`, `MAS_INSTALLER_IDENTITY`, `MAS_PROVISION_PROFILE`). See `docs/mas-build-guide.md` for detailed setup and submission instructions.

## Release Flow

NullPlayer releases use the plain `X.Y.Z` tag format, matching `CFBundleShortVersionString` exactly. Do not prefix release tags with `v`.

### GitHub Release

The preferred release helper builds the DMG, creates or updates the GitHub release, and uploads both the immutable versioned asset and the stable human-friendly asset:

1. Bump `CFBundleShortVersionString` (and `CFBundleVersion` if needed) in `Sources/NullPlayer/Resources/Info.plist`.
2. Update `CHANGELOG.md` with a matching `## X.Y.Z` section.
3. Run:
   ```bash
   ./scripts/create_release.sh
   ```

The helper uses `.github/release_template.md`, extracts the matching changelog section, and publishes these assets:

- `NullPlayer-X.Y.Z.dmg` — use for Homebrew and archived release references
- `NullPlayer.dmg` — use for download pages and `releases/latest/download/NullPlayer.dmg`

Useful helper options:

```bash
./scripts/create_release.sh --dry-run     # Build notes and assets, but do not call GitHub
./scripts/create_release.sh --skip-build  # Reuse an existing dist/NullPlayer-X.Y.Z.dmg
./scripts/create_release.sh --draft       # Create/update the release as a draft
./scripts/create_release.sh --prerelease  # Mark the release as a prerelease
./scripts/create_release.sh --replace-versioned  # Re-upload the versioned DMG on an existing release
```

When updating an existing release, the helper always refreshes `NullPlayer.dmg` but leaves `NullPlayer-X.Y.Z.dmg` unchanged unless `--replace-versioned` is passed. This protects Homebrew users because the cask checksum is tied to the versioned asset.

### Homebrew Cask

NullPlayer is distributed via a personal tap at `ad-repo/homebrew-nullplayer` (`Casks/nullplayer.rb`). After the GitHub release:

1. Note the SHA256 printed by `./scripts/build_dmg.sh` for `dist/NullPlayer-X.Y.Z.dmg`.
2. In the `ad-repo/homebrew-nullplayer` repo, update `Casks/nullplayer.rb`:
   - Bump `version "X.Y.Z"`.
   - Replace `sha256 "..."` with the value from step 1.
   - Keep the cask URL pointed at the versioned DMG, not `NullPlayer.dmg`.
   - Commit and push.
3. Verify locally:
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
