# Sonos Integration

This document covers Sonos speaker discovery and casting in AdAmp.

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

### Zone vs Group
- **Zone**: Individual Sonos speaker (e.g., "Living Room")
- **Group**: Multiple zones playing in sync (e.g., "Living Room +2")

When casting, we target the **group coordinator** - the speaker that controls playback for the group.

### Discovery Flow
1. SSDP/mDNS finds Sonos devices on network
2. Fetch device description XML from each device (port 1400)
3. Extract room name, UDN, and AVTransport URL
4. After 3 seconds, fetch group topology from any zone
5. Create cast devices based on groups (showing coordinator only)

### Group Topology
Fetched via SOAP request to `/ZoneGroupTopology/Control`:
```xml
<u:GetZoneGroupState xmlns:u="urn:schemas-upnp-org:service:ZoneGroupTopology:1"/>
```

Response contains all groups and their member zones, allowing us to:
- Show grouped speakers as single entry (e.g., "Living Room +2")
- Target the coordinator for playback control

## Casting

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

## Troubleshooting

### Devices Not Found
1. Check UPnP is enabled in Sonos app settings
2. Ensure devices are on same network/VLAN as computer
3. Check firewall allows UDP 1900 (SSDP) and mDNS (5353)
4. Try clicking "Refresh Devices" and wait 10 seconds

### Devices Found But Won't Play
1. Verify AVTransport URL is accessible: `curl http://{ip}:1400/xml/device_description.xml`
2. Check Sonos isn't in "TV" mode (some soundbars)
3. Ensure media URL is accessible from Sonos (not localhost)

### Group Topology Issues
- Groups take 3+ seconds to resolve after initial discovery
- Reopen the Cast Devices menu after waiting
- If groups show incorrectly, click Refresh

## Network Requirements

### Ports
- **UDP 1900**: SSDP discovery
- **UDP 5353**: mDNS discovery
- **TCP 1400**: Sonos HTTP/SOAP control
- **Media port**: Whatever port your media is served on

### Multicast
SSDP requires multicast to work. Some routers/switches block this:
- Enable IGMP snooping
- Allow multicast on WLAN
- Don't isolate wireless clients

## References

- [Sonos UPnP Services (unofficial)](https://github.com/SoCo/SoCo/wiki/Sonos-UPnP-Services-and-Functions)
- [SoCo Python Library](https://github.com/SoCo/SoCo)
- [Sonos Developer Docs](https://docs.sonos.com/)
- [Sonos Connection Security](https://support.sonos.com/en-us/article/adjust-connection-security-settings)
