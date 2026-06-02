# Mac App Store Distribution Scope

NullPlayer is submitted to the Mac App Store (MAS) with full feature parity to the direct-download DMG build, **with the exception of CLI mode and CLI installer scripts.** This document defines what features are included in the MAS build, what is excluded, and the Apple review considerations for retained sensitive functionality like local-network casting and media-server authentication.

## Scope Decision

**MAS feature set = DMG feature set MINUS headless CLI mode.** Rationale:
- The in-bundle `--cli` flag invokes a `.accessory` activation policy (no Dock icon, no menu bar) — not a primary app experience suitable for App Store distribution.
- The three CLI installer scripts (`scripts/nullplayer`, `scripts/install_cli_launcher.sh`, `scripts/Install NullPlayer CLI.command`, copied to DMG at `scripts/build_dmg.sh:305-312`) write to `/usr/local/bin`, which is prohibited under App Sandbox. They are bundled only in the direct-download DMG.
- All other features — including casting, media-server integration, visualizations, and local playback — remain in MAS.

## Feature Matrix

| Feature | DMG | MAS | Sandbox Impact | Evidence |
|---------|-----|-----|-----------------|----------|
| **Playback** | ✓ | ✓ | — | Local + streaming |
| Audio formats (MP3, FLAC, AAC, WAV, AIFF, ALAC, OGG) | ✓ | ✓ | — | `Info.plist` line 60–69 |
| Video formats (MKV, MP4, MOV, AVI, WebM, HEVC) | ✓ | ✓ | Requires file access | `Windows/VideoPlayer/VideoPlayerWindowController.swift` (KSPlayer/FFmpeg libraries) |
| **Casting** | ✓ | ✓ | High | See Review Notes |
| Chromecast | ✓ | ✓ | Local network + HTTP | `Casting/ChromecastManager.swift` |
| Sonos (multi-room) | ✓ | ✓ | Local network + HTTP | `Casting/CastManager.swift` |
| UPnP/DLNA | ✓ | ✓ | Local network + HTTP | `Casting/UPnPManager.swift` |
| AirPlay | ✓ | ✓ | Local network | `Casting/CastDevice.swift` |
| Embedded HTTP server for local/proxied streams | ✓ | ✓ | Network server (port 8765) | `Casting/LocalMediaServer.swift:204, 31` |
| **Media Servers** | ✓ | ✓ | Keychain auth | See Review Notes |
| Plex (PIN auth) | ✓ | ✓ | — | `Plex/PlexManager.swift` |
| Jellyfin | ✓ | ✓ | — | `Jellyfin/JellyfinManager.swift` |
| Emby | ✓ | ✓ | — | `Emby/EmbyManager.swift` |
| Navidrome/Subsonic | ✓ | ✓ | — | `Subsonic/SubsonicManager.swift` |
| **Local Library** | ✓ | ✓ | Requires file access | `Data/Models/MediaLibrary.swift` |
| SQLite library scan | ✓ | ✓ | Directory traversal | `Utilities/LocalFileDiscovery.swift` |
| **Visualizations** | ✓ | ✓ | GPU (Metal) | See Review Notes (GPL-3.0 risk) |
| ProjectM/MilkDrop (100 presets + user downloads) | ✓ | ✓ | — | `Visualization/ProjectMWrapper.swift` |
| Spectrum analyzer (Metal, 84-bar) | ✓ | ✓ | — | `Visualization/SpectrumAnalyzerView.swift` |
| Geiss, Tripex, Met Museum, Album Art effects | ✓ | ✓ | — | `Visualization/Geiss*`, `Tripex*`, `MetMuseum/` |
| **Skins** | ✓ | ✓ | — | — |
| Classic `.wsz` skins + modern JSON skins | ✓ | ✓ | — | `Skin/`, `ModernSkin/` |
| **Audio Processing** | ✓ | ✓ | — | — |
| 10/21-band parametric EQ | ✓ | ✓ | — | `Windows/ModernEQ/`, `Audio/EQ.swift` |
| Reference tuning (432/440/custom Hz) | ✓ | ✓ | — | — |
| Gapless, crossfade, replay gain | ✓ | ✓ | — | `Audio/AudioEngine.swift` |
| **Internet Radio** | ✓ | ✓ | HTTP streams + Keychain | `Radio/RadioManager.swift` |
| Shoutcast/Icecast (streaming stations) | ✓ | ✓ | — | — |
| **OS Integration** | ✓ | ✓ | — | — |
| Now Playing, Control Center, Touch Bar, AirPods | ✓ | ✓ | — | `App/NowPlayingManager.swift` |
| Discord Music Presence | ✓ | ✓ | — | `App/NowPlayingManager.swift` (via `MPNowPlayingInfoCenter`) |
| Sleep timer | ✓ | ✓ | — | `App/SleepTimerManager.swift` |
| **UI Modes** | ✓ | ✓ | — | — |
| Classic main window + playlist + EQ | ✓ | ✓ | — | `Windows/MainWindow/` |
| Modern UI (alternate renderer) | ✓ | ✓ | — | `Windows/ModernMainWindow/` |
| **CLI Mode** | ✓ | **✗** | Sandbox + `/usr/local/bin` | See Exclusions |
| Headless `--cli` flag playback | ✓ | **✗** | — | `App/main.swift:9-14`, `CLI/CLIMode.swift` |
| CLI installer scripts | ✓ | **✗** | `/usr/local/bin` write | `scripts/build_dmg.sh:305-312` |

## Excluded from MAS (Direct-Download Only)

### CLI Mode
- **What:** Invocation via `nullplayer --cli` flag; sets app to `.accessory` activation policy (no Dock icon, no menu bar).
- **Where:** Checked at runtime in `Sources/NullPlayer/App/main.swift:9-14`; implementation in `Sources/NullPlayer/CLI/CLIMode.swift`.
- **Why excluded:** Headless mode without Dock integration is not a primary app experience suitable for App Store review.

### CLI Installer Scripts
- **What:** Three shell scripts bundled in DMG only (`scripts/nullplayer`, `scripts/install_cli_launcher.sh`, `scripts/Install NullPlayer CLI.command`).
- **Where:** Copied to DMG staging at `scripts/build_dmg.sh:305-312`.
- **Why excluded:** App Sandbox prohibits writing to `/usr/local/bin`. The MAS packaging must not execute this portion of `build_dmg.sh`.

## App Store Metadata Mapping

Every claim in the App Store listing must map to an Included feature in the matrix above:

| Metadata Claim | Included Feature | Matrix Row |
|---|---|---|
| "Play local audio files" | Playback + audio formats | Playback |
| "Support for MP3, FLAC, AAC, WAV, AIFF, ALAC, OGG" | Audio formats | Playback |
| "Cast to Chromecast, Sonos, and AirPlay" | Casting (Chromecast, Sonos, AirPlay) | Casting |
| "Stream from Plex, Jellyfin, Emby, Navidrome/Subsonic" | Media Servers | Media Servers |
| "Parametric EQ and reference tuning" | EQ + reference tuning | Audio Processing |
| "Visualizations (ProjectM, Geiss, Tripex, spectrum)" | Visualizations | Visualizations |
| "Internet radio (Shoutcast/Icecast)" | Internet Radio | Internet Radio |
| "Discord Music Presence, Control Center, Now Playing" | OS Integration | OS Integration |
| "Classic and modern UI modes" | UI Modes | UI Modes |

## Apple Review Notes

### Local HTTP Server for Casting (Port 8765)

NullPlayer bundles an embedded HTTP server (`Casting/LocalMediaServer.swift`) that:
- Binds to `0.0.0.0:8765` to serve local audio files to UPnP, Chromecast, Sonos, and DLNA cast devices.
- Is **not accessible from the internet** — restricted to the local network via Bonjour service discovery and device-specific URLs.
- Serves two types of content:
  1. **Local files** (registered via token): Users select files locally; the server returns HTTP URLs for cast devices to fetch directly. Supports HTTP Range requests for seeking.
  2. **Proxied remote streams**: Media servers (Jellyfin, Emby, Subsonic) return stream URLs without file extensions. The server proxies these streams under a token so Sonos (which requires recognizable MIME types) can play them. The app still owns the server credential and stream lifecycle.
- **Why necessary:** Cast protocols (UPnP/DLNA, Chromecast) require HTTP-accessible media URLs. A local-network server is the only way to expose local files to cast devices on the LAN.
- **User control:** Users explicitly select cast targets and files; no automatic broadcast or always-on listening.

**Entitlements required:** `com.apple.security.app-sandbox`, `com.apple.security.network.server`, `com.apple.security.network.client`, `com.apple.security.network.local-outbound`.

### Local Network Discovery and Bonjour

The app uses `NSLocalNetworkUsageDescription` (`Info.plist:27-28`) and registers three Bonjour service types (`_googlecast._tcp`, `_airplay._tcp`, `_raop._tcp`) to discover cast devices on the local network. This is required for cast device enumeration and only happens after the user grants local network permission.

**User impact:** One system privacy prompt on first casting attempt. No background scanning.

### Media Server Credentials in Keychain

The app stores media server credentials (Plex auth token, Jellyfin/Emby auth + server URL, Subsonic password) in the system Keychain under service `com.nullplayer.app` (`Utilities/KeychainHelper.swift:26`). Keys include `plex_auth_token`, `subsonic_servers`, `jellyfin_servers`, `emby_servers`.

**Security:** Credentials are encrypted by the OS and only accessible to the NullPlayer app bundle. Users explicitly enter credentials; no automatic discovery or injection.

**User impact:** Standard Keychain unlock prompt on first access after login or when the Keychain is locked. No background credential sync.

### Arbitrary Loads for Media (NSAllowsArbitraryLoadsForMedia)

`Info.plist:46-47` sets `NSAllowsArbitraryLoadsForMedia` to allow plain-HTTP media streams from:
- Internet radio stations (Shoutcast/Icecast over HTTP).
- Media servers that serve streams over HTTP (not HTTPS).
- The embedded local HTTP server (`http://192.168.x.x:8765`).

**Justification:** Media servers (Jellyfin, Emby, Navidrome) in home/lab setups often use self-signed certs or plain HTTP. Users own these servers and consciously connect to them. Restricting to HTTPS would break legitimate use cases.

### GPL-3.0 Components (Flagged Risk)

The app bundles GPL-3.0-licensed video/analysis libraries:
- **KSPlayer** (SPM library; used in `Windows/VideoPlayer/VideoPlayerWindowController.swift`): Video playback via FFmpeg.
- **FFmpegKit** and **FFmpeg**: Video decoding (LGPL-2.1 + GPL-3.0 parts).
- **aubio**: Audio spectrum analysis via FFmpeg pipeline.

GPL-3.0 licenses are known to be in tension with App Store distribution terms (Apple requires source code availability for derivative works; MAS terms do not permit external source redistribution). **This is a known compatibility risk.** If Apple rejects the submission, the following remediation options exist (in priority order):

1. **Remove video playback** (MKV/MP4/WebM via KSPlayer/FFmpeg), keeping audio-only formats.
2. **Replace FFmpeg with native macOS codecs** (AudioToolbox, VideoToolbox, VTDecoderSession).
3. **Remove spectrum analysis** (aubio) and retain static visualizations.

**Current stance:** Proceed with submission as-is. Only split/remove stacks if Apple explicitly rejects. Reference `docs/third-party-notices.md` and issue #240 (third-party notices audit) for the full component license list.

## Follow-up / Compliance Work

The following MAS-specific blockers remain before release:

1. **App Sandbox entitlements** — Create `Sources/NullPlayer/NullPlayer.entitlements` with:
   - `com.apple.security.app-sandbox` = true
   - `com.apple.security.files.user-selected.read-only` (for local library scan)
   - `com.apple.security.network.client` (for media server queries + internet radio)
   - `com.apple.security.network.server` (for casting HTTP server)
   - `com.apple.security.network.local-outbound` (for Bonjour discovery)
   - Corresponding `SecurityScopedBookmark` implementation for persistent file access if needed.

2. **Privacy Manifest** (`PrivacyInfo.xcprivacy`) — Document all API usage:
   - `NSLocalNetworkUsageReason`: "Discover and cast to local devices"
   - `NSBonjourUsageReason`: "Discover Chromecast, AirPlay, and DLNA devices"
   - `NSFileAppsWithLocalNetworkUsageReason`: Keychain and Bonjour access (if required)
   - AudioToolbox, AVFoundation, MediaPlayer usage for playback and Now Playing integration.

3. **Code Signing and Notarization** — Sign with Apple Developer certificate (not ad-hoc). The current DMG uses ad-hoc signing (`scripts/build_dmg.sh:269-287`); MAS requires:
   - Provisioning profile (`com.nullplayer.app` MAS profile from App Store Connect).
   - `xcodebuild` with `-signingIdentity` and `-allowProvisioningUpdates`.
   - Automatic notarization via Xcode or `xcrun altool` (required for distribution).

4. **MAS Build Script** — Create a separate MAS build that:
   - Runs the standard SPM build with MAS entitlements.
   - Invokes `scripts/validate_notices.sh` for third-party notice compliance (see `docs/third-party-notices.md`).
   - **Does NOT** execute the CLI installer copy step (`scripts/build_dmg.sh:305-312`).
   - Uploads to App Store Connect via `xcrun altool` or the new App Store Connect API.

5. **GPL-3.0 Risk Assessment** — Monitor Apple's response to KSPlayer/FFmpeg/aubio. If rejected, prioritize video stack removal or native codec replacement. Track in a follow-up issue.

Related issue: **#240** (third-party notices audit and validation) provides the foundational component licensing audit. The MAS entitlements and privacy manifest (items 1–2 above) depend on #240 being merged.

## Testing Checklist (Before Submission)

- [ ] Local file playback (all audio formats) on MAS build.
- [ ] Streaming playback from Plex, Jellyfin, Emby, Navidrome/Subsonic.
- [ ] Cast to Chromecast, Sonos, AirPlay, DLNA devices on local network.
- [ ] Verify Keychain credential storage and retrieval in sandboxed context.
- [ ] Visualizations render correctly (Metal, spectrum analyzer, ProjectM).
- [ ] EQ and reference tuning apply correctly.
- [ ] `--cli` flag is not available in MAS build (or fails gracefully with informative error).
- [ ] MAS build does not write to `/usr/local/bin` or any non-sandboxed directory.
- [ ] Privacy prompt for local network access appears and can be toggled in System Settings.
- [ ] App does not crash when user denies local network permission (cast features degrade gracefully).
- [ ] `docs/third-party-notices.md` and `ThirdPartyNotices.txt` bundled and readable in app.
