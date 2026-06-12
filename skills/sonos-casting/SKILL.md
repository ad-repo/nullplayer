---
name: sonos-casting
description: Sonos UPnP discovery, multi-room casting, coordinator transfer, custom checkbox UI, and protocol quirks. Use when working on Sonos casting, UPnP control, multi-room audio, or group management.
---

# Sonos Integration

This guide covers Sonos speaker discovery, casting, and multi-room grouping in NullPlayer.

## Quick Start

1. Open Sonos from either:
   - Right-click anywhere in NullPlayer → **Output Devices → Sonos**
   - Top menu bar → **Output → Sonos**
2. Check the rooms you want to cast to (checkboxes stay open for multi-select)
3. Click **🟢 Start Casting** to begin playback
4. Click **🔴 Stop Casting** from the Sonos menu to fully end the cast session

## Discovery Methods

NullPlayer uses two methods to discover Sonos devices:

### 1. SSDP (Simple Service Discovery Protocol)
- UDP multicast to `239.255.255.250:1900`
- Search target: `urn:schemas-upnp-org:device:ZonePlayer:1`
- Works on most networks but can be blocked by firewalls/routers

### 2. mDNS/Bonjour (Fallback)
- Service type: `_sonos._tcp.local.`
- Uses Apple's NWBrowser API
- More reliable on networks that block UDP multicast
- Added as fallback due to Sonos app changes in 2024-2025

## Requirements

### UPnP Must Be Enabled
Sonos added a UPnP toggle in their app settings. **Discovery will fail if disabled.**

To enable:
1. Open Sonos app (iOS/Android)
2. Go to **Account → Privacy & Security → Connection Security**
3. Ensure **UPnP** is **ON** (default)

If UPnP is disabled, SSDP discovery won't find devices and SOAP control won't work.

### Connection Security (Firmware 85.0+, July 2025)

Sonos firmware 85.0-66270 added optional security settings:

| Setting | Default | Effect if Changed |
|---------|---------|-------------------|
| Authentication | OFF | Blocks SOAP commands from NullPlayer |
| UPnP | ON | Disables ALL local SOAP control |
| Guest Access | ON | Prevents same-network playback control |

NullPlayer detects 401/403 SOAP errors and shows a specific message directing users to the Connection Security settings.

## Architecture

### Zone vs Group vs Room
- **Zone**: Individual Sonos speaker hardware (e.g., a single Sonos One)
- **Room**: A named location that may contain one or more zones (e.g., "Living Room" with stereo pair)
- **Group**: Multiple rooms playing in sync (e.g., "Living Room + Kitchen")

When casting, NullPlayer targets the **group coordinator** - the speaker that controls playback for the group.

### Discovery Flow
1. SSDP/mDNS finds Sonos devices on network
2. Fetch device description XML from each device (port 1400)
3. Extract room name, UDN (unique device name), and AVTransport URL
4. After 3 seconds, fetch group topology from any zone
5. Create cast devices based on groups (showing coordinator only)

### Group Topology
Fetched via SOAP request to `/ZoneGroupTopology/Control`:
```xml
<u:GetZoneGroupState xmlns:u="urn:schemas-upnp-org:service:ZoneGroupTopology:1"/>
```

Response contains all groups and their member zones.

## User Interface

### Menu Structure

```
Sonos                          ▸
├── ☐ Dining Room                 (checkbox - selectable room)
├── ☐ Living Room                 (checkbox - selectable room)  
├── ☐ Kitchen                     (checkbox - selectable room)
├── ─────────────────
├── 🟢 Start Casting              (when NOT casting)
│   OR
├── 🔴 Stop Casting               (when casting)
└── Refresh
```

### Checkbox Behavior

**When NOT casting:**
| State | Meaning |
|-------|---------|
| ☐ Unchecked | Room is not selected for casting |
| ☑ Checked | Room is selected for future casting |

**When casting:**
| State | Meaning |
|-------|---------|
| ☐ Unchecked | Room is NOT receiving audio from the app |
| ☑ Checked | Room IS receiving audio from the app |

### Multi-Select Feature

The room checkboxes use `SonosRoomCheckboxView` which **keeps the menu open** when clicked, allowing you to select multiple rooms without the menu closing.

This behavior is intentionally the same in both:
- Context menu Sonos submenu
- Top menu bar `Output > Sonos` submenu

## Casting Workflow

### Starting a Cast

1. **Load music** - Play or load a track from Plex, Subsonic, local files, or internet radio
2. **Open Sonos menu** - Right-click → Output Devices → Sonos
3. **Select rooms** - Check one or more room checkboxes
4. **Start casting** - Click "🟢 Start Casting"

The app will:
- Cast to the first selected room
- Join additional rooms to that group
- Update checkboxes to show which rooms are receiving audio

**Internet Radio Note:** Radio streams are live and don't support seeking. When you cast a radio station, time resets to 0:00.

### Managing Rooms While Casting

While casting is active:
- **Check a room** → Room joins the cast group and starts playing
- **Uncheck a non-coordinator room** → Room leaves the group and stops playing
- **Uncheck the coordinator room (with other rooms still checked)** → Playback transfers to the next remaining room, which becomes the new coordinator. Brief (~1-2s) playback interruption during transfer. Menu closes to refresh state.
- **Uncheck the coordinator room (only room in group)** → Casting stops entirely

**Coordinator transfer implementation**: `CastManager.transferSonosCast()` saves session state, stops the old coordinator, casts to the new coordinator, and re-joins other rooms. Uses `UPnPManager.disconnectSession()` to clear the session without sending Stop (old coordinator is already standalone after leaving). `stopCasting()` ungroups all member rooms **before** stopping the coordinator to prevent stale group topology on subsequent casts. Polling is also stopped at the top of `stopCasting()` before any ungrouping SOAP calls.

### Stopping a Cast

There are two intentional stop paths:

- **Player Stop button / end-of-playlist**: sends `Stop` to Sonos but keeps `upnpManager.activeSession`, selected rooms, group membership, and LocalMediaServer registrations intact. The next compatible track reuses the same Sonos target without re-selecting rooms. This path is `AudioEngine.stop()` or `castTrackDidFinish()` → `CastManager.softStopForActiveDevice()` → `stopPlayback()`.
- **Sonos menu 🔴 Stop Casting**: fully tears down the cast session via `CastManager.stopCasting()`.

Click **🔴 Stop Casting** to fully disconnect:
- Ungroup all member rooms (each becomes standalone)
- Stop playback on the coordinator
- Clear all room selections
- Return to local control (stopped; use the play button to resume)

## Casting Protocol

### AVTransport Control
- Control URL: `http://{ip}:1400/MediaRenderer/AVTransport/Control`
- Service type: `urn:schemas-upnp-org:service:AVTransport:1`

Key actions:
- `SetAVTransportURI` - Set media URL with DIDL-Lite metadata
- `Play` - Start playback
- `Pause` - Pause playback
- `Stop` - Stop playback
- `Seek` - Seek to position (REL_TIME format: HH:MM:SS)
- `GetTransportInfo` - Get transport state
- `GetPositionInfo` - Get current position and duration

### Fire-and-Forget Commands

For Sonos audio casting, playback control commands use a **fire-and-forget** pattern:

| Command | Behavior |
|---------|----------|
| `Pause` | Sends SOAP request, returns immediately |
| `Resume` | Sends SOAP request, returns immediately |
| `Seek` | Sends SOAP request, returns immediately |

**Why fire-and-forget?**
- Sonos SOAP requests can take 5-10 seconds
- Blocking makes the UI unresponsive
- Commands succeed even without waiting for acknowledgment

**Error detection:** Consecutive failures are tracked. After 3 failures, a user-facing error notification is posted.

### Volume Control
Sonos uses **GroupRenderingControl** (not `RenderingControl`) so that volume/mute apply to the whole group, not just the coordinator zone. Non-Sonos DLNA devices still use `RenderingControl`.

| | Sonos | Other DLNA |
|---|---|---|
| Control URL | `/MediaRenderer/GroupRenderingControl/Control` | `/MediaRenderer/RenderingControl/Control` |
| Set volume | `SetGroupVolume` (no Channel arg) | `SetVolume` (Channel=Master) |
| Get volume | `GetGroupVolume` | `GetVolume` |
| Set mute | `SetGroupMute` (no Channel arg) | `SetMute` (Channel=Master) |
| Service type | `urn:schemas-upnp-org:service:GroupRenderingControl:1` | `urn:schemas-upnp-org:service:RenderingControl:1` |

This is handled in `UPnPManager.setVolume(_:)`, `getVolume()`, and `setMute(_:)` by branching on `session.device.type == .sonos`.

### Playback State Monitoring

NullPlayer polls Sonos every 5 seconds during casting:
- `GetTransportInfo` — Returns transport state (PLAYING, PAUSED_PLAYBACK, STOPPED, etc.)
- `GetPositionInfo` — Returns current position and duration

**What polling detects:**
- Sonos stopped externally (paused via Sonos app, speaker went to sleep)
- Track position drift (syncs local timer)
- Device unreachable (SOAP timeout)

**Polling lifecycle:**
- Started (`startSonosPolling`) when Sonos casting begins
- Stopped (`stopSonosPolling`) at the top of `stopCasting()`, before ungrouping rooms
- Also runs post-wake check after Mac sleep

**Position sync:** Each PLAYING poll updates `activeSession.position` and sets `activeSession.playbackStartDate = Date()`. On PAUSED_PLAYBACK, `playbackStartDate` is set to `nil` so the timer freezes. `CastManager.currentTime` interpolates `session.position + elapsed(since: playbackStartDate)` — the same pattern used for Chromecast.

**Poll failure logging:** `pollSonosPlaybackState()` logs explicitly when it returns `nil` due to no session, failed `GetTransportInfo`, or failed `GetPositionInfo`, so silent poll failures are visible in Console.

### Resilience and Recovery

**CoreAudio route churn:**
- Sonos grouping, coordinator transfer, room switching, Wi-Fi changes, Zoom routes, and AirPlay-style output changes can trigger local `AVAudioEngineConfigurationChange` notifications even while cast playback is remote.
- Local `AudioEngine` graph rebuilds must be deferred while `CastManager.activeSession` exists or `AudioEngine.isAnyCastingActive` is true.
- See `skills/audio-system/audio-pipelines.md` — Cast Route-Change Safety.

**Network change detection:**
- LocalMediaServer monitors network changes via NWPathMonitor and refreshes its own bound IP when Wi-Fi changes.
- UPnPManager also monitors network changes. When the active local IP changes, or the network returns after being unavailable, it stops SSDP/mDNS discovery, clears cached Sonos/DLNA device URLs and Sonos topology, then starts discovery on the current interface.
- Active Sonos casts are ended only when the local IP actually changes. A pure reconnect refreshes discovery without tearing down a working speaker session.

**Mac sleep/wake handling:**
- CastManager observes sleep/wake notifications
- On wake: waits 2s for network, refreshes local/UPnP network state, then polls Sonos state if casting and updates UI

**Server health checks:**
- LocalMediaServer pings itself every 30 seconds
- Auto-restarts if the ping fails

**Group topology refresh:**
- During casting, group topology refreshed every 60 seconds
- Detects external group changes

### Group Management

**Join a group** - `SetAVTransportURI` with `x-rincon:{coordinator_uid}`:
```xml
<u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
  <InstanceID>0</InstanceID>
  <CurrentURI>x-rincon:RINCON_xxxx</CurrentURI>
  <CurrentURIMetaData></CurrentURIMetaData>
</u:SetAVTransportURI>
```

**Leave a group** - `BecomeCoordinatorOfStandaloneGroup`:
```xml
<u:BecomeCoordinatorOfStandaloneGroup xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
  <InstanceID>0</InstanceID>
</u:BecomeCoordinatorOfStandaloneGroup>
```

## Implementation Details

### State Management

**CastManager.swift** maintains:
```swift
/// Rooms selected for Sonos casting (UDNs) - used before casting starts
var selectedSonosRooms: Set<String> = []
```

### Custom Checkbox View

**SonosRoomCheckboxView** is an `NSView` subclass that:
- Renders a checkbox with the room name
- Handles clicks without closing the menu
- Updates `selectedSonosRooms` when not casting
- Joins/unjoins rooms when casting is active

```swift
@objc private func checkboxClicked(_ sender: NSButton) {
    if isCastingToSonos {
        // Toggle actual Sonos group membership
        if isNowChecked {
            joinSonosToGroup(...)
        } else {
            unjoinSonos(...)
        }
    } else {
        // Just update local selection state
        if isNowChecked {
            selectedSonosRooms.insert(roomUDN)
        } else {
            selectedSonosRooms.remove(roomUDN)
        }
    }
}
```

### Device Matching

**Challenge**: `sonosRooms` returns room UDNs, but `sonosDevices` only contains group coordinators.

**Solution** in `castToSonosRoom`:
1. Try direct ID match (room is a coordinator)
2. Fall back to matching by room name
3. Use first available device as last resort

### Local File Casting

Local files are supported via an embedded HTTP server (LocalMediaServer):
- **Port**: 8765
- **Seeking**: Supports HTTP Range requests
- **Network binding**: Binds to local network interface (en0/en1), not localhost
- **HEAD requests**: Handles HEAD requests (Sonos may send HEAD before GET)

**Supported content:**
- ✅ Plex streaming (with token in URL)
- ✅ Subsonic/Navidrome streaming (via proxy)
- ✅ Jellyfin streaming (via proxy)
- ✅ Emby streaming (via proxy)
- ✅ Local files (via embedded HTTP server)
- ✅ Internet radio (Shoutcast/Icecast streams)

**Subsonic/Navidrome/Jellyfin/Emby Casting:**
Streams are proxied through LocalMediaServer because:
1. Sonos has issues with URLs containing query parameters
2. The media server may be localhost-bound, unreachable by Sonos

### Artwork Display

NullPlayer sends artwork URLs via DIDL-Lite metadata:

| Source | Artwork URL |
|--------|-------------|
| Plex | `PlexManager.artworkURL(thumb:)` - Plex transcode endpoint |
| Subsonic | `SubsonicManager.coverArtURL(coverArtId:)` - Subsonic getCoverArt |
| Jellyfin | `JellyfinManager.imageURL(itemId:imageTag:size:)` - Jellyfin `/Items/{id}/Images/Primary` |
| Emby | `EmbyManager.imageURL(itemId:imageTag:size:)` - Emby `/Items/{id}/Images/Primary` |
| Local files | LocalMediaServer extracts embedded artwork and serves as JPEG |

See [artwork-debugging-history.md](artwork-debugging-history.md) for historical artwork troubleshooting attempts.

## Sonos Protocol Quirks

**Content-Type matching:** The content type in DIDL-Lite `protocolInfo` must match the actual HTTP Content-Type header. Use `track.contentType` when a backend provides it; otherwise use `CastManager.detectAudioContentType(for:)` to detect from file extension. Extensionless server streams must not fall back to `audio/mpeg` when API metadata says the codec/container is FLAC, WAV, ALAC, etc.

**Content-Length for MP3/OGG:** Sonos closes the connection if Content-Length is missing for MP3 and OGG. Chunked transfer encoding only works for WAV/FLAC.

**HEAD requests:** Sonos sends HTTP HEAD before GET to check file size. LocalMediaServer handles both methods.

**Radio streams:** MP3 radio streams use `x-rincon-mp3radio://` URI scheme for better Sonos buffering.

**Error 701:** "Transition Not Available" - occurs when the speaker is busy. NullPlayer waits for transport ready state before retrying. **It also fires when the speaker connects but can't decode the stream** (never leaves `STOPPED`), so all retries exhaust — see the FlyingFox chunked gotcha below for the YouTube → Sonos live path.

**FlyingFox never frames chunked responses (live-stream gotcha):** FlyingFox auto-adds `Transfer-Encoding: chunked` to any response body with no `count`, but `HTTPConnection.sendResponse` writes the body bytes **un-framed** (raw `socket.write`, no chunk-size lines). The result is a malformed response that no compliant HTTP/1.1 client — Sonos included — can read, so the YouTube → Sonos cast connected but never played (UPnP 701, transport stuck `STOPPED`). Fix: the `/live/*` GET and HEAD handlers pass a sentinel `Content-Length` (`liveStreamAdvertisedLength`, 1 TiB) so FlyingFox takes its Content-Length branch and streams the raw bytes verbatim, plus `Connection: close` to mark true end-of-stream. The count only sets the header; iteration still ends when the ffmpeg producer EOFs. Never reintroduce `Transfer-Encoding: chunked` on these endpoints. (Normal internet radio is unaffected — Sonos connects directly to the remote SHOUTcast server, bypassing LocalMediaServer.)

**Redirect limitation:** Sonos doesn't follow HTTP 30x redirects with relative URLs - only absolute URLs work.

**Supported formats:** MP3 (320kbps), AAC/HE-AAC (320kbps), FLAC (24-bit, 48kHz), WAV (16-bit), OGG Vorbis (320kbps).

**Not supported for Sonos casting:** ALAC, AIFF/AIF, WavPack (`wv`), Monkey's Audio (`ape`).

## Format Compatibility and Auto-Skip

### Two-Tier Compatibility Check

`CastManager.isSonosCompatible(_:allowUnknownSampleRate:)` has two modes:

- **Strict (default)**: nil sample rate on a lossless track → incompatible. Used as the _final_ verdict in `castCurrentTrack` and `castNewTrack` after the sample rate has been fetched.
- **Permissive** (`allowUnknownSampleRate: true`): nil sample rate → pass through. Used in _scan/positioning_ functions that advance the playlist index before casting begins.

Always-incompatible formats (regardless of sample rate): `alac`, `aiff`, `aif`, `wv` (WavPack), `ape` (Monkey's Audio).
Lossless formats requiring the sample-rate check: `flac`, `wav` — rejected above 48 kHz.

Format classification uses the URL extension first, then normalized `Track.contentType` when the URL is extensionless. MIME types are normalized case-insensitively and parameters are ignored, so `Audio/X-FLAC; charset=binary` is treated as FLAC. This matters for Plex, Subsonic/Navidrome, Jellyfin, and Emby stream URLs that may not end in `.flac` or `.wav`.

### Scan Functions Use Permissive Mode

Functions that advance the playlist index use `allowUnknownSampleRate: true` because they run _before_ the sample rate is known:

| Function | Location | Mode |
|----------|----------|------|
| `advanceToFirstSonosCompatibleTrack()` | `AudioEngine.swift` | permissive |
| Skip loops in `castTrackDidFinish()` — sequential, shuffle, shuffle+repeat | `AudioEngine.swift` | permissive |

### Cast Functions Are the Final Authority

`castCurrentTrack` and `castNewTrack` in `CastManager.swift` fetch the actual sample rate from the Plex API for lossless tracks with nil SR, then call strict `isSonosCompatible`. The fetch decision must use the same URL-extension-or-content-type classification as `isSonosCompatible`; Plex stream URLs are often extensionless, so `Track.contentType` must identify FLAC/WAV for the fetch to happen. If a track fails there, `advanceToFirstSonosCompatibleTrack()` is called again to find the next candidate.

For non-Plex backends, preserve both `Track.contentType` and sample rate from server metadata. If an extensionless FLAC/WAV track reaches strict mode without sample rate, it is rejected conservatively rather than sent to Sonos.

### Design Principle

> Scan functions only reject _definitively_ incompatible formats (ALAC, AIFF, WavPack, Monkey's Audio, known >48 kHz SR). They pass nil-SR lossless tracks through so the cast function can fetch and decide. Never use strict mode in a skip/scan loop — it causes Plex FLAC tracks with nil SR to be skipped silently without a fetch attempt.

## Troubleshooting

### Devices Not Found
1. Check UPnP is enabled in Sonos app settings
2. Ensure devices are on same network/VLAN
3. Check firewall allows UDP 1900 (SSDP) and mDNS (5353)
4. Click "Refresh" and wait 10 seconds

### Devices Found But Won't Play
1. Verify AVTransport URL is accessible: `curl http://{ip}:1400/xml/device_description.xml`
2. Check Sonos isn't in "TV" mode (some soundbars)
3. Ensure media URL is accessible from Sonos (not localhost)

### Authentication Errors (401/403)
If you see "Sonos rejected the command":
1. Open Sonos app → Settings → Account → Privacy & Security → Connection Security
2. Ensure **UPnP** is **ON**
3. Ensure **Authentication** is **OFF**
4. These settings were added in Sonos firmware 85.0 (July 2025)

### Local Files Won't Cast
1. Check your Mac has a local network IP address (not just 127.0.0.1)
2. Ensure firewall allows incoming connections on port 8765
3. Verify Sonos speakers are on same network
4. Check Console.app for "LocalMediaServer" log messages

### Seek Bar Stuck at 0 / Position Not Updating
- Root cause: `activeSession.position` and `activeSession.playbackStartDate` not set at cast start.
- At Sonos cast start, `activeSession.position = startPosition` and `activeSession.playbackStartDate = Date()` must both be set immediately (Sonos has no status updates to set them later).
- Each PLAYING poll must update both fields. Check `CastManager: Sonos poll — state=PLAYING` logs.

### Player Stop Keeps Session Alive
- This is expected for Sonos when using the player Stop button: `handleStopForActiveDevice()` calls `softStopForActiveDevice()`, which stops Sonos playback but leaves the session active.
- Use the Sonos menu **🔴 Stop Casting** action when a full disconnect is required.
- Chromecast and non-Sonos DLNA should still route through `stopCasting()` from `softStopForActiveDevice()`.

### Casting Stops Unexpectedly
1. Check if Sonos speaker went to sleep (idle timeout)
2. Check if someone paused via Sonos app (NullPlayer detects this)
3. Check if Mac went to sleep (NullPlayer recovers on wake)
4. Check Console.app for "Sonos reported STOPPED" or "consecutive command failures"

## YouTube → Sonos (paste-URL middleman)

Plays a YouTube (or other yt-dlp-supported) video **locally, muted**, while its audio is
streamed to Sonos — so the audio comes out of your speakers and the video stays watchable and
in sync on the Mac. NullPlayer owns the local video clock, so it can correct A/V lag.

### How it works
1. `YouTubeStreamResolver` runs `yt-dlp -j <url>` and selects a video-only stream (≤1080p
   h264/mp4) and the highest-bitrate audio-only stream, capturing per-stream HTTP headers and
   the media `duration`.
2. **Audio → Sonos.** `YouTubeToSonosCoordinator` chooses one of two paths:
   - **AAC (the common case — itag 140): proxy the real m4a file**, exactly like Navidrome/local
     files. `LocalMediaServer.registerStreamURL(audioURL, contentType: "audio/mp4",
     requestHeaders: audioHeaders)` serves it via `/stream/*` with real `Content-Length` + Range
     passthrough; the yt-dlp headers (esp. `User-Agent`) are forwarded upstream because
     googlevideo URLs are UA/IP-validated. It is cast as a **normal durationed track**
     (`CastManager.cast(to:url:metadata:)`, `musicTrack` / `http-get:audio/mp4`) — **not** the
     radio scheme. This is the reliable path; everything else was a dead end (see history below).
   - **Non-AAC fallback (e.g. opus/webm): live ffmpeg transcode.** `setupLiveAudioStream` spawns
     `ffmpeg` to transcode to ADTS/AAC served at `/live/<token>` (producer-backed; `Connection:
     close` + sentinel `Content-Length`, never chunked — FlyingFox gotcha below) and cast via
     `castLiveAudioStream` (`x-rincon-mp3radio://`). **Less reliable** — Sonos accepts `Play` and
     fetches but often won't sustain the radio stream. Most videos offer AAC, so this rarely runs.
3. The video plays muted via `WindowManager.showLocalMutedVideo` (bypasses video-cast routing).
4. **The muted video must not pause the cast.** Starting any video calls
   `WindowManager.videoPlaybackDidStart()`, which pauses the audio engine — but here the engine
   *is* driving the Sonos cast. It's guarded with `YouTubeToSonosCoordinator.shared.isActive` so
   it does **not** pause during a YT→Sonos session. (Symptom when broken: Sonos `Play` succeeds,
   stream is fetched, then a `Pausing` SOAP fires ~30 ms later and Sonos sits `STOPPED`.)
5. `SonosVideoSyncController` syncs the local video to the Sonos clock, but **only once Sonos has
   truly started playing** (`CastManager.isSonosPlaybackConfirmed`, backed by
   `sonosHasSeenActivePlayback`). Before that it leaves the video alone — otherwise it chases the
   optimistic, ever-advancing startup position and seek-freezes the video. Once playing it does
   one initial alignment seek and then stops background sync. It must not continuously chase Sonos
   drift: Sonos position is coarse and seeking a network-streamed YouTube video re-buffers it, so
   repeated drift correction causes loading spinners every few seconds. The **A/V sync offset**
   popover is the primary fine calibration (persisted to `UserDefaults` key
   `youtubeSonosAVOffset`). Moving the slider only changes the stored offset and label; the
   explicit **Resync** button applies the offset with a single deliberate video seek.

### Enabling the feature (requires yt-dlp + ffmpeg)
The feature is gated on a runtime presence check (`HelperBinaries`). The menu item
**Output → Streaming → Sonos → Open Video URL → Sonos…** only appears when both binaries are found. Resolution
order per binary:
1. **Env override** — `NULLPLAYER_YTDLP_PATH` / `NULLPLAYER_FFMPEG_PATH` (absolute paths).
2. **Bundled** in the app (`Contents/MacOS`, then `Contents/Resources`) — the DMG distribution.
3. **System install** on `PATH` plus `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`.

So the simplest way to turn it on (dev or direct-download) is:

```bash
brew install yt-dlp ffmpeg
```

then relaunch NullPlayer. The sandboxed **Mac App Store build cannot use it** (no bundled
binaries, and the sandbox blocks executing system binaries), so the menu stays hidden there —
this is intentional. For the DMG distribution, binaries are provisioned opt-in via
`NULLPLAYER_BUNDLE_YT_TOOLS=1 ./scripts/bootstrap.sh` (with real checksums) and bundled by
`build_dmg.sh`; they must be listed in `scripts/third_party_components.tsv` or
`validate_notices.sh` fails.

### Usage
1. **Output → Streaming → Sonos** — check one or more rooms in the Sonos room list.
2. **Open Video URL → Sonos…** — the dialog has a wide URL field, auto-filled from the clipboard
   if it looks like a YouTube link.
3. Audio starts on the checked rooms; the first checked room becomes the coordinator and the rest
   join its group. The video opens muted.
4. Open the **A/V Sync Offset** popover and drag the slider until the displayed offset looks
   right; it persists across sessions. Dragging does **not** seek the video.
5. Click **Resync** to apply the current offset with one deliberate video seek. Avoid repeated
   Resync clicks because each seek can force the remote YouTube stream to buffer.
6. **Output → Streaming → Sonos → Stop YouTube → Sonos** tears everything down (unregisters the proxy *or* live
   stream, kills ffmpeg with SIGTERM→SIGKILL if it was used, stops the cast, restores video volume).

### v1 limitations
- **Coarse sync only.** Sonos position is whole-second granular plus a ~1–3 s startup buffer;
  the offset control closes the residual. Not frame-accurate.
- **Opus-only videos are unreliable.** The non-AAC fallback (live ffmpeg → `x-rincon-mp3radio://`)
  often won't sustain on Sonos. Videos that offer AAC (almost all) use the solid proxy path.
- **No automatic drift correction.** After the startup alignment, NullPlayer leaves the local video
  at 1.0x. Automatic rate trimming and repeated drift seeks were removed because they make remote
  YouTube video stall. Use the offset control + Resync for manual correction.
- **No combined pause/seek/scrub.** Pausing the local video leaves Sonos playing. Whole-timeline
  scrubbing isn't wired — use Stop and reopen.
- **Extraction fragility.** yt-dlp breaks when YouTube changes; a bundled copy needs app
  updates (a Homebrew copy can be `brew upgrade`d independently).

### Key files
`Video/HelperBinaries.swift`, `Video/YouTubeStreamResolver.swift` (resolves streams + headers +
`duration`), `Video/YouTubeToSonosCoordinator.swift` (AAC-proxy vs live-ffmpeg branch),
`Video/SonosVideoSyncController.swift` (confirmed-playback gate, one-shot startup alignment,
manual Resync);
`Casting/LocalMediaServer.swift` (`registerStreamURL` with `requestHeaders` passthrough →
`/stream/*`; `registerLiveStream` → `/live/*` fallback);
`Casting/CastManager.swift` (`cast(to:url:metadata:)` normal-track path, `castLiveAudioStream`
fallback, `currentCastPosition`, `isSonosPlaybackConfirmed`, `sonosCastDevice(forRoomUDN:)`);
`App/WindowManager.swift` (`videoPlaybackDidStart` cast-pause guard).

## Network Requirements

### Ports
- **UDP 1900**: SSDP discovery
- **UDP 5353**: mDNS discovery
- **TCP 1400**: Sonos HTTP/SOAP control
- **TCP 8765**: Local media server (for casting local files)
- **Media port**: Whatever port your media is served on (Plex default: 32400)

### Multicast
SSDP requires multicast. Some routers/switches block this:
- Enable IGMP snooping
- Allow multicast on WLAN
- Don't isolate wireless clients

## Key Source Files

| File | Purpose |
|------|---------|
| `Casting/CastManager.swift` | Central coordinator, `selectedSonosRooms` state, polling timer, sleep/wake handling |
| `Casting/UPnPManager.swift` | SSDP/mDNS discovery, SOAP control, group topology, `pollSonosPlaybackState()` |
| `App/ContextMenuBuilder.swift` | Menu UI, `SonosRoomCheckboxView`, casting actions |
| `Casting/LocalMediaServer.swift` | Embedded HTTP server, HEAD handlers, health checks, network monitoring |

## References

- [Sonos UPnP Services (unofficial)](https://github.com/SoCo/SoCo/wiki/Sonos-UPnP-Services-and-Functions)
- [SoCo Python Library](https://github.com/SoCo/SoCo)
- [Sonos Developer Docs](https://docs.sonos.com/)
- [Sonos Connection Security](https://support.sonos.com/en-us/article/adjust-connection-security-settings)
