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
4. Click **🔴 Stop Casting** to end the session

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

### Stopping a Cast

Click **🔴 Stop Casting** to:
- Ungroup all member rooms (each becomes standalone)
- Stop playback on the coordinator
- Clear all room selections
- Return to local playback (if audio was playing)

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
- Control URL: `http://{ip}:1400/MediaRenderer/RenderingControl/Control`
- `SetVolume` - Set volume (0-100)
- `GetVolume` - Get current volume
- `SetMute` / `GetMute` - Mute control

### Playback State Monitoring

NullPlayer polls Sonos every 5 seconds during casting:
- `GetTransportInfo` - Returns transport state (PLAYING, PAUSED_PLAYBACK, STOPPED, etc.)
- `GetPositionInfo` - Returns current position and duration

**What polling detects:**
- Sonos stopped externally (paused via Sonos app, speaker went to sleep)
- Track position drift (syncs local timer)
- Device unreachable (SOAP timeout)

**Polling lifecycle:**
- Started when Sonos casting begins
- Stopped when casting ends
- Also runs post-wake check after Mac sleep

### Resilience and Recovery

**Network change detection:**
- LocalMediaServer monitors network changes via NWPathMonitor
- IP address refreshed automatically when Wi-Fi changes

**Mac sleep/wake handling:**
- CastManager observes sleep/wake notifications
- On wake: waits 2s for network, polls Sonos state, updates UI

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
- ✅ Local files (via embedded HTTP server)
- ✅ Internet radio (Shoutcast/Icecast streams)

**Subsonic/Navidrome Casting:**
Streams are proxied through LocalMediaServer because:
1. Sonos has issues with URLs containing query parameters
2. Navidrome may be localhost-bound, unreachable by Sonos

### Artwork Display

NullPlayer sends artwork URLs via DIDL-Lite metadata:

| Source | Artwork URL |
|--------|-------------|
| Plex | `PlexManager.artworkURL(thumb:)` - Plex transcode endpoint |
| Subsonic | `SubsonicManager.coverArtURL(coverArtId:)` - Subsonic getCoverArt |
| Local files | LocalMediaServer extracts embedded artwork and serves as JPEG |

See [artwork-debugging-history.md](artwork-debugging-history.md) for historical artwork troubleshooting attempts.

## Sonos Protocol Quirks

**Content-Type matching:** The content type in DIDL-Lite `protocolInfo` must match the actual HTTP Content-Type header. Use `CastManager.detectAudioContentType(for:)` to detect from file extension.

**Content-Length for MP3/OGG:** Sonos closes the connection if Content-Length is missing for MP3 and OGG. Chunked transfer encoding only works for WAV/FLAC.

**HEAD requests:** Sonos sends HTTP HEAD before GET to check file size. LocalMediaServer handles both methods.

**Radio streams:** MP3 radio streams use `x-rincon-mp3radio://` URI scheme for better Sonos buffering.

**Error 701:** "Transition Not Available" - occurs when the speaker is busy. NullPlayer waits for transport ready state before retrying.

**Redirect limitation:** Sonos doesn't follow HTTP 30x redirects with relative URLs - only absolute URLs work.

**Supported formats:** MP3 (320kbps), AAC/HE-AAC (320kbps), FLAC (24-bit, 48kHz), ALAC (24-bit), WAV/AIFF (16-bit), OGG Vorbis (320kbps).

## Format Compatibility and Auto-Skip

### Two-Tier Compatibility Check

`CastManager.isSonosCompatible(_:allowUnknownSampleRate:)` has two modes:

- **Strict (default)**: nil sample rate on a lossless track → incompatible. Used as the _final_ verdict in `castCurrentTrack` and `castNewTrack` after the sample rate has been fetched.
- **Permissive** (`allowUnknownSampleRate: true`): nil sample rate → pass through. Used in _scan/positioning_ functions that advance the playlist index before casting begins.

Always-incompatible formats (regardless of sample rate): `alac`, `aiff`, `aif`.
Lossless formats requiring the sample-rate check: `flac`, `wav` — rejected above 48 kHz.

### Scan Functions Use Permissive Mode

Functions that advance the playlist index use `allowUnknownSampleRate: true` because they run _before_ the sample rate is known:

| Function | Location | Mode |
|----------|----------|------|
| `advanceToFirstSonosCompatibleTrack()` | `AudioEngine.swift` | permissive |
| Skip loops in `castTrackDidFinish()` — sequential, shuffle, shuffle+repeat | `AudioEngine.swift` | permissive |

### Cast Functions Are the Final Authority

`castCurrentTrack` and `castNewTrack` in `CastManager.swift` fetch the actual sample rate from the Plex API for lossless tracks with nil SR, then call strict `isSonosCompatible`. If a track fails there, `advanceToFirstSonosCompatibleTrack()` is called again to find the next candidate.

### Design Principle

> Scan functions only reject _definitively_ incompatible formats (ALAC, AIFF, known >48 kHz SR). They pass nil-SR lossless tracks through so the cast function can fetch and decide. Never use strict mode in a skip/scan loop — it causes Plex FLAC tracks with nil SR to be skipped silently without a fetch attempt.

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

### Casting Stops Unexpectedly
1. Check if Sonos speaker went to sleep (idle timeout)
2. Check if someone paused via Sonos app (NullPlayer detects this)
3. Check if Mac went to sleep (NullPlayer recovers on wake)
4. Check Console.app for "Sonos reported STOPPED" or "consecutive command failures"

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
