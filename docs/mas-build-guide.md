# Mac App Store Build Guide

This guide covers building, signing, and submitting NullPlayer to the Mac App Store.

## Prerequisites

### Apple Developer Account & Certificates

1. **Apple Developer Account** — Active membership ($99/year)
2. **App ID** — `com.nullplayer.app` registered in [App Store Connect](https://appstoreconnect.apple.com/)
3. **Code Signing Certificates** — Two required:
   - **Apple Distribution** (aka "3rd Party Mac Developer Application")
   - **Apple Distribution** (aka "3rd Party Mac Developer Installer")
   
   Both can be created/renewed via [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/certificates/list).

4. **MAS Provisioning Profile** — Create in Certificates, Identifiers & Profiles:
   - Type: **macOS App Store** (not Ad Hoc)
   - App ID: `com.nullplayer.app`
   - Include all team members who may sign builds
   - Download and save to: `~/Library/MobileDevice/Provisioning Profiles/NullPlayer.provisionprofile`

5. **Local Setup** — Import certificates into Keychain:
   ```bash
   # Drag-drop the .cer files into Keychain Access, or:
   open ~/Downloads/distribution_cert.cer
   ```

## Environment Variables

Export these before running `build_mas.sh`:

```bash
# Application signing identity (copy from Keychain Access → Certificates)
export MAS_APP_IDENTITY="3rd Party Mac Developer Application: Your Name (TEAMID)"

# Installer signing identity
export MAS_INSTALLER_IDENTITY="3rd Party Mac Developer Installer: Your Name (TEAMID)"

# Provisioning profile path
export MAS_PROVISION_PROFILE="$HOME/Library/MobileDevice/Provisioning Profiles/NullPlayer.provisionprofile"
```

To find the correct identity strings:
```bash
# List all signing identities
security find-identity -p codesigning -v

# Example output:
#   "3rd Party Mac Developer Application: Your Name (ABCD1234EF)"
#   "3rd Party Mac Developer Installer: Your Name (ABCD1234EF)"
```

## Building

```bash
# Full build (compile + assemble + sign)
./scripts/build_mas.sh

# Use existing release build (skip compilation)
./scripts/build_mas.sh --skip-build
```

Output:
- `dist/NullPlayer.app` — Signed app bundle
- `dist/NullPlayer-X.Y.Z.pkg` — Installer package for submission

## Verification

Always verify before uploading:

```bash
# Check app bundle signature
codesign --verify --deep --strict dist/NullPlayer.app

# Check installer signature
pkgutil --check-signature dist/NullPlayer-X.Y.Z.pkg

# Confirm package payload structure (no CLI scripts included)
pkgutil --payload-files dist/NullPlayer-X.Y.Z.pkg | grep "NullPlayer.app/Contents/MacOS/"
# Should list ONLY the NullPlayer executable under Contents/MacOS
```

## Submission

### Option 1: Transporter App (Recommended)

1. Download [Transporter](https://apps.apple.com/app/transporter/id1450874784) from App Store
2. Launch → Click "+" → Select `dist/NullPlayer-X.Y.Z.pkg`
3. Verify app info matches [App Store Connect](https://appstoreconnect.apple.com/)
4. Click "Deliver"

### Option 2: Command Line

```bash
# Using altool
xcrun altool --upload-app --type macos \
  --file dist/NullPlayer-X.Y.Z.pkg \
  --bundle-id com.nullplayer.app \
  --username "your-email@example.com" \
  --password "@keychain:AC_PASSWORD"
```

`notarytool` is for Developer ID distribution outside the App Store. MAS builds are delivered to App Store Connect with Transporter or `altool`.

## Versioning Rules

**CRITICAL:** App Store requires strict version ordering. CFBundleVersion must be **higher** on every submission.

Before building:
1. Open `Sources/NullPlayer/Resources/Info.plist`
2. Increment `CFBundleVersion` (integer, e.g., `1` → `2`)
3. Update `CFBundleShortVersionString` if desired (e.g., `0.24.0` → `0.25.0`)
4. **Each App Store upload MUST have higher CFBundleVersion than the previous submission**

Example version progression:
```text
First submission:   v0.24.0 / build 1
Second submission:  v0.24.1 / build 2  (or v0.25.0 / build 5, etc.)
Third submission:   v0.25.0 / build 6
```

## Known Limitations (MAS Sandbox)

### Multicast/Bonjour Restriction

The MAS sandbox does **not** allow the `com.apple.security.network.multicast` entitlement. This affects:
- **Generic DLNA devices** — Require UPnP multicast discovery; will not be discovered
- **RAOP/AirPlay** — UPnP/Bonjour discovery is blocked
- **Sonos, Chromecast, AirPlay (Bonjour-based)** — Work via existing `NSBonjourServices` declaration in Info.plist without multicast

Users cannot cast to generic smart TVs or devices without explicit Bonjour support. Recommend in release notes:
> "Mac App Store version supports Sonos, Chromecast, and Bonjour AirPlay devices. Generic DLNA/UPNP devices require the DMG version from GitHub."

### Encryption Declaration

`Sources/NullPlayer/Resources/Info.plist` sets `ITSAppUsesNonExemptEncryption=false` because NullPlayer uses only standard TLS for HTTPS — no custom encryption algorithms.

## Troubleshooting

### "Code object is not signed at all"

Provisioning profile not embedded or certificate not found. Verify:
```bash
codesign -dv dist/NullPlayer.app | grep embedded
# Should show path to embedded.provisionprofile
```

### "Certificate not trusted"

Check identity string matches Keychain exactly:
```bash
security find-identity -p codesigning -v
# Copy the exact string (including team ID)
```

### "Package signature invalid"

Installer identity may not match provisioning profile's team ID. Verify both are from the same Apple Developer account.

### "Build failed at Step 2" (framework check)

Run `./scripts/bootstrap.sh` first to download required frameworks.

## See Also

- `scripts/build_dmg.sh` — Direct download DMG (ad-hoc signed, no sandboxing)
- `docs/development-workflow.md` — Local build & test
- [App Store Connect](https://appstoreconnect.apple.com/) — Submission status, reviews, analytics
