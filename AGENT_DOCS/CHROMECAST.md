# Chromecast Implementation

AdAmp implements Google Cast Protocol v2 for casting audio and video to Chromecast devices.

## Architecture

### Key Files

| File | Purpose |
|------|---------|
| `Casting/CastProtocol.swift` | Protocol implementation, message encoding/decoding, session controller |
| `Casting/ChromecastManager.swift` | Device discovery (mDNS), connection management, public API |
| `Casting/CastManager.swift` | High-level casting coordinator for all device types |
| `scripts/test_chromecast.swift` | Standalone test script for debugging |

### Discovery

Chromecast devices are discovered via mDNS (Bonjour):
- Service type: `_googlecast._tcp`
- Domain: `local.`
- Uses `NWBrowser` for discovery
- Resolves to IP:port (default port 8009)

### Protocol Overview

Google Cast Protocol v2:
1. **TLS Connection** - Port 8009, self-signed certificate (must accept)
2. **Protobuf Framing** - 4-byte big-endian length prefix + protobuf message
3. **Namespaces** - Different message types use different namespace URNs
4. **Session Flow**:
   - CONNECT to `receiver-0`
   - Start heartbeat (PING every 5 seconds)
   - LAUNCH Default Media Receiver (appId: `CC1AD845`)
   - Wait for RECEIVER_STATUS with `transportId`
   - CONNECT to the transportId
   - LOAD media with URL and metadata

### Message Namespaces

| Namespace | Purpose |
|-----------|---------|
| `urn:x-cast:com.google.cast.tp.connection` | Connection management (CONNECT, CLOSE) |
| `urn:x-cast:com.google.cast.tp.heartbeat` | Keep-alive (PING, PONG) |
| `urn:x-cast:com.google.cast.receiver` | App lifecycle (LAUNCH, STOP, GET_STATUS) |
| `urn:x-cast:com.google.cast.media` | Media control (LOAD, PLAY, PAUSE, SEEK, STOP) |

## Implementation Details

### CastSessionController

The `CastSessionController` class manages a single Chromecast session:
- Thread-safe with `NSLock` for state access
- Uses `NWConnection` for TLS socket
- Completion-based async API (bridged to async/await in ChromecastManager)

### Protobuf Encoding

Manual protobuf implementation (no external library):
- Varint encoding for integers
- Length-delimited strings
- Field numbers match official CastMessage proto definition

### Key Implementation Gotcha: Data Slice Indexing

Swift `Data` slices maintain original indices. When processing a receive buffer:

```swift
// WRONG - reads from wrong positions if buffer is a slice:
let byte = buffer[0]
let slice = buffer[4..<total]

// CORRECT - always works:
let byte = buffer[buffer.startIndex]
let startIdx = buffer.startIndex + 4
let endIdx = buffer.startIndex + total
let slice = buffer[startIdx..<endIdx]
```

This caused silent crashes during development until identified with the standalone test script.

## Debugging

### Standalone Test Script

Use `scripts/test_chromecast.swift` to debug protocol issues in isolation:

```bash
swift scripts/test_chromecast.swift
```

The test script:
1. Connects to Chromecast via TLS
2. Sends CONNECT message
3. Sends LAUNCH command
4. Waits for RECEIVER_STATUS with transportId
5. Reports success/failure with debug info

### Common Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| Silent crash on receive | Data slice indexing | Use `startIndex` explicitly |
| Timeout waiting for transportId | Buffer not being processed | Check receive loop continuity |
| TLS connection fails | Certificate rejection | Accept self-signed in verify block |
| No devices found | mDNS not working | Check network, firewall |

### Adding Debug Logging

In `CastProtocol.swift`, add NSLog statements:
```swift
NSLog("CastSessionController: Received %d bytes", data.count)
NSLog("CastSessionController: handleMessage type=%@", type)
```

## Media Loading

### LOAD Message Format

```json
{
  "type": "LOAD",
  "media": {
    "contentId": "http://...",
    "contentType": "video/mp4",
    "streamType": "BUFFERED",
    "metadata": {
      "type": 0,
      "metadataType": 0,
      "title": "Movie Title",
      "subtitle": "Artist/Description"
    }
  },
  "autoplay": true,
  "requestId": 1
}
```

### Plex Content

For Plex content, the stream URL includes the authentication token:
```
http://server:32400/library/parts/12345/.../file.mkv?X-Plex-Token=xxx
```

## Playback Control

After successful LOAD, use the `transportId` for media commands:

| Command | Payload |
|---------|---------|
| PLAY | `{"type":"PLAY","mediaSessionId":1,"requestId":N}` |
| PAUSE | `{"type":"PAUSE","mediaSessionId":1,"requestId":N}` |
| STOP | `{"type":"STOP","mediaSessionId":1,"requestId":N}` |
| SEEK | `{"type":"SEEK","mediaSessionId":1,"currentTime":30.5,"requestId":N}` |

## Volume Control

Volume is controlled via the receiver namespace (not media):

```json
{"type":"SET_VOLUME","volume":{"level":0.5},"requestId":N}
{"type":"SET_VOLUME","volume":{"muted":true},"requestId":N}
```

## References

- [Google Cast SDK Documentation](https://developers.google.com/cast/docs/developers)
- [OpenCastSwift](https://github.com/mhmiles/OpenCastSwift) - Reference implementation
- [node-castv2](https://github.com/thibauts/node-castv2) - Node.js implementation
