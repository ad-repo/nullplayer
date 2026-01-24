# Sonos Integration

This document covers Sonos speaker discovery, casting, and multi-room grouping in AdAmp.

## Quick Start

1. Right-click anywhere in AdAmp → **Output Devices → Sonos**
2. Check the rooms you want to cast to (checkboxes stay open for multi-select)
3. Click **🟢 Start Casting** to begin playback
4. Click **🔴 Stop Casting** to end the session

## Discovery Methods

AdAmp uses two methods to discover Sonos devices:

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

If UPnP is disabled:
- SSDP discovery won't find devices
- mDNS discovery may still work but SOAP control won't
- The macOS/Windows Sonos app also won't work

## Architecture

### Zone vs Group vs Room
- **Zone**: Individual Sonos speaker hardware (e.g., a single Sonos One)
- **Room**: A named location that may contain one or more zones (e.g., "Living Room" with stereo pair)
- **Group**: Multiple rooms playing in sync (e.g., "Living Room + Kitchen")

When casting, AdAmp targets the **group coordinator** - the speaker that controls playback for the group.

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

---

## User Interface

### Accessing the Sonos Menu
1. Right-click anywhere in AdAmp
2. Go to **Output Devices → Sonos**

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

The checkbox meaning depends on whether you're currently casting:

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

The room checkboxes use a custom view that **keeps the menu open** when clicked. This allows you to:
- Select multiple rooms without the menu closing
- Quickly configure your cast targets
- Click "Start Casting" when ready

### Visual Indicators

| Indicator | Meaning |
|-----------|---------|
| 🟢 Start Casting | Green circle - ready to begin casting |
| 🔴 Stop Casting | Red circle - casting is active, click to stop |

---

## Casting Workflow

### Starting a Cast

1. **Load music** - Play or load a track from Plex, Subsonic, or local files
2. **Open Sonos menu** - Right-click → Output Devices → Sonos
3. **Select rooms** - Check one or more room checkboxes
4. **Start casting** - Click "🟢 Start Casting"

The app will:
- Cast to the first selected room
- Join additional rooms to that group
- Update checkboxes to show which rooms are receiving audio

### Managing Rooms While Casting

While casting is active:
- **Check a room** → Room joins the cast group and starts playing
- **Uncheck a room** → Room leaves the group and stops playing

### Stopping a Cast

Click **🔴 Stop Casting** to:
- Stop playback on all Sonos rooms
- Clear all room selections
- Return to local playback (if audio was playing)

### Error Handling

| Error | Cause | Solution |
|-------|-------|----------|
| "No Music" | No track loaded | Load/play a track first |
| "No Room Selected" | No rooms checked | Select at least one room |
| "No Device Found" | Discovery incomplete | Click Refresh, wait 10 seconds |

---

## Implementation Details

### State Management

**CastManager.swift** maintains:
```swift
/// Rooms selected for Sonos casting (UDNs) - used before casting starts
var selectedSonosRooms: Set<String> = []
```

This set stores room UDNs that the user has checked but hasn't started casting to yet.

### Checkbox State Logic

**ContextMenuBuilder.swift** determines checkbox state:

```swift
if isCastingToSonos {
    // WHILE CASTING: checked = receiving audio from cast session
    // Check if this room is the cast target or in the cast group
    isChecked = (room.id == castTargetUDN) ||
                (room.groupCoordinatorUDN == castTargetUDN) ||
                (room is coordinator and target is in its group)
} else {
    // NOT CASTING: checked = room is selected for future cast
    isChecked = castManager.selectedSonosRooms.contains(room.id)
}
```

### Custom Checkbox View

**SonosRoomCheckboxView** is an `NSView` subclass that:
- Renders a checkbox with the room name
- Handles clicks without closing the menu
- Updates `selectedSonosRooms` when not casting
- Joins/unjoins rooms when casting is active

```swift
class SonosRoomCheckboxView: NSView {
    private let checkbox: NSButton
    private let info: SonosRoomToggle
    
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
}
```

### Device Matching

**Challenge**: `sonosRooms` returns room UDNs, but `sonosDevices` only contains group coordinators.

**Solution** in `castToSonosRoom`:
1. Try direct ID match (room is a coordinator)
2. Fall back to matching by room name
3. Use first available device as last resort

```swift
// Find device that matches selected room
for udn in selectedUDNs {
    // Direct match
    if let device = devices.first(where: { $0.id == udn }) { ... }
    // Name match
    if let room = rooms.first(where: { $0.id == udn }),
       let device = devices.first(where: { $0.name.hasPrefix(room.name) }) { ... }
}
```

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

---

## Casting Protocol

### AVTransport Control
Sonos uses UPnP AVTransport service for playback:
- Control URL: `http://{ip}:1400/MediaRenderer/AVTransport/Control`
- Service type: `urn:schemas-upnp-org:service:AVTransport:1`

Key actions:
- `SetAVTransportURI` - Set media URL with DIDL-Lite metadata
- `Play` - Start playback
- `Pause` - Pause playback
- `Stop` - Stop playback
- `Seek` - Seek to position (REL_TIME format: HH:MM:SS)

### Volume Control
Via RenderingControl service:
- Control URL: `http://{ip}:1400/MediaRenderer/RenderingControl/Control`
- `SetVolume` - Set volume (0-100)
- `GetVolume` - Get current volume
- `SetMute` / `GetMute` - Mute control

---

## Limitations

### Bonded Speakers
Bonded speakers are handled automatically:
- **Stereo pairs** (two speakers as L/R) act as one room
- **Surround systems** (soundbar + sub + rears) act as one room
- You group/ungroup the entire room, not individual bonded speakers

### Menu Refresh Behavior
During device refresh, the menu preserves existing zone and group data to avoid UI flicker. The `resetDiscoveryState()` function keeps `sonosZones` and `lastFetchedGroups` intact while only resetting the discovery flags.

### Local File Casting

Local files are supported via an embedded HTTP server (LocalMediaServer):

- **Automatic startup**: Server starts automatically when casting local files
- **Port**: Files are served on port 8765
- **Seeking**: Supports HTTP Range requests for seeking
- **Network binding**: Server binds to local network interface (en0/en1), not localhost

**Supported content:**
- ✅ Plex streaming (with token in URL)
- ✅ Subsonic/Navidrome streaming
- ✅ Local files (via embedded HTTP server)

**Requirements for local file casting:**
- Mac must be on the same network as Sonos speakers
- Firewall must allow incoming connections on port 8765
- Local network interface (en0 or en1) must have an IP address

---

## Troubleshooting

### Devices Not Found
1. Check UPnP is enabled in Sonos app settings
2. Ensure devices are on same network/VLAN as computer
3. Check firewall allows UDP 1900 (SSDP) and mDNS (5353)
4. Click "Refresh" and wait 10 seconds

### Devices Found But Won't Play
1. Verify AVTransport URL is accessible: `curl http://{ip}:1400/xml/device_description.xml`
2. Check Sonos isn't in "TV" mode (some soundbars)
3. Ensure media URL is accessible from Sonos (not localhost)

### Group Topology Issues
- Groups take 3+ seconds to resolve after initial discovery
- Reopen the Sonos menu after waiting
- If groups show incorrectly, click Refresh

### Grouping Not Working
If you can't change room groups:
1. **UPnP must be enabled** in Sonos app settings
2. Ensure rooms are discovered (wait for discovery to complete)
3. Try clicking "Refresh" and wait 10 seconds
4. Check Sonos app to verify groups actually changed
5. **SOAP error 500/1023**: This usually means you're trying to ungroup a bonded speaker

### Checkbox Changes Don't Persist
This is expected behavior:
- When NOT casting: selections are stored locally in memory
- When casting STOPS: selections are cleared
- Refresh always shows the actual Sonos state

### Local Files Won't Cast
If local files fail to cast:
1. Check that your Mac has a local network IP address (not just 127.0.0.1)
2. Ensure firewall allows incoming connections on port 8765
3. Verify Sonos speakers are on the same network as your Mac
4. Check Console.app for "LocalMediaServer" log messages

---

## Network Requirements

### Ports
- **UDP 1900**: SSDP discovery
- **UDP 5353**: mDNS discovery
- **TCP 1400**: Sonos HTTP/SOAP control
- **TCP 8765**: Local media server (for casting local files)
- **Media port**: Whatever port your media is served on (Plex default: 32400)

### Multicast
SSDP requires multicast to work. Some routers/switches block this:
- Enable IGMP snooping
- Allow multicast on WLAN
- Don't isolate wireless clients

---

## Key Source Files

| File | Purpose |
|------|---------|
| `CastManager.swift` | Central casting coordinator, `selectedSonosRooms` state |
| `UPnPManager.swift` | SSDP/mDNS discovery, SOAP control, group topology |
| `ContextMenuBuilder.swift` | Menu UI, `SonosRoomCheckboxView`, casting actions |
| `LocalMediaServer.swift` | Embedded HTTP server for local file casting |

---

## References

- [Sonos UPnP Services (unofficial)](https://github.com/SoCo/SoCo/wiki/Sonos-UPnP-Services-and-Functions)
- [SoCo Python Library](https://github.com/SoCo/SoCo)
- [Sonos Developer Docs](https://docs.sonos.com/)
- [Sonos Connection Security](https://support.sonos.com/en-us/article/adjust-connection-security-settings)
