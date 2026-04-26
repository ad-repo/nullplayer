---
name: chromecast-casting
description: Google Cast Protocol v2, message framing, debugging, and test scripts. Use when working on Chromecast casting, debugging Cast protocol issues, or implementing Cast commands.
---

# Chromecast Implementation

NullPlayer implements Google Cast Protocol v2 for casting audio and video to Chromecast devices.

## Key Files

| File | Purpose |
|------|---------|
| `Casting/CastProtocol.swift` | Protocol implementation, message encoding/decoding, session controller |
| `Casting/ChromecastManager.swift` | Device discovery (mDNS), connection management, public API |
| `Casting/CastManager.swift` | High-level casting coordinator for all device types |
| `scripts/test_chromecast.swift` | Standalone test script for debugging |

## Discovery

Chromecast devices are discovered via mDNS (Bonjour):
- Service type: `_googlecast._tcp`
- Domain: `local.`
- Uses `NWBrowser` for discovery
- Resolves to IP:port (default port 8009)

## Protocol Overview

Google Cast Protocol v2:
1. **TLS Connection** — Port 8009, self-signed certificate (must accept)
2. **Protobuf Framing** — 4-byte big-endian length prefix + protobuf message
3. **Namespaces** — Different message types use different namespace URNs
4. **Session Flow**:
   - CONNECT to `receiver-0`
   - Start heartbeat (PING every 5 seconds)
   - LAUNCH Default Media Receiver (appId: `CC1AD845`)
   - Wait for RECEIVER_STATUS with `transportId`
   - CONNECT to the transportId
   - LOAD media with URL and metadata

## Message Namespaces

| Namespace | Purpose |
|-----------|---------|
| `urn:x-cast:com.google.cast.tp.connection` | Connection management (CONNECT, CLOSE) |
| `urn:x-cast:com.google.cast.tp.heartbeat` | Keep-alive (PING, PONG) |
| `urn:x-cast:com.google.cast.receiver` | App lifecycle (LAUNCH, STOP, GET_STATUS) |
| `urn:x-cast:com.google.cast.media` | Media control (LOAD, PLAY, PAUSE, SEEK, STOP) |

## CastSessionController

The `CastSessionController` class manages a single Chromecast session:
- Thread-safe with `NSLock` for state access
- Uses `NWConnection` for TLS socket
- Completion-based async API (bridged to async/await in ChromecastManager)
- Implements `CastSessionControllerDelegate` protocol for status updates

## Position Synchronization

Position tracking uses `CastSession` fields, not AudioEngine-local variables:

- `activeSession.position` — last known position reported by Chromecast
- `activeSession.playbackStartDate` — `Date()` when playback last transitioned to PLAYING; `nil` when paused or buffering
- `CastManager.currentTime` interpolates: `session.position + Date().timeIntervalSince(session.playbackStartDate)`

**Status polling** (`CastSessionController.startStatusPolling()`) polls `GET_STATUS` every second. Each `MEDIA_STATUS` response updates `session.position` and resets `session.playbackStartDate = Date()` when PLAYING, or sets `playbackStartDate = nil` when not playing.

This handles buffering: when `playerState == BUFFERING`, `playbackStartDate` is cleared so the interpolation freezes at `session.position` until PLAYING resumes.

**Both video and audio** casts use the same session-based tracking. The audio branch in `handleChromecastMediaStatusUpdate` mirrors the video branch exactly.

## Stopping Playback and Closing the App

When the user stops casting Chromecast:

1. `ChromecastManager.stop()` sends `STOP` to the **media session** — stops media but leaves the Default Media Receiver app running on the TV.
2. `ChromecastManager.stopApp()` sends `STOP` to **`receiver-0`** (receiver namespace) — closes the Default Media Receiver app entirely, triggering HDMI-CEC to dismiss the cast overlay from the TV screen.
3. A **200ms sleep** between `stop()` and `disconnect()` ensures STOP bytes flush before the socket is cancelled. Without this, `connection.cancel()` races with the outbound STOP bytes and the Chromecast never processes the command, leaving the video paused on screen.

```swift
// In ChromecastManager.stop():
sessionController?.stop()      // STOP to media session
sessionController?.stopApp()   // STOP to receiver-0

// In CastManager.stopCasting():
chromecastManager.stop()
try? await Task.sleep(nanoseconds: 200_000_000)  // 200ms flush delay
chromecastManager.disconnect()
```

## Pre-Load IDLE Guard (`chromecastHasSeenActivePlayback`)

Chromecast sends an initial `IDLE` status immediately after a new media session is created, **before** the `LOAD` command is processed. Without a guard, this IDLE would be interpreted as "media ended" and trigger `stopCasting()`.

`CastManager` maintains:
```swift
private var chromecastHasSeenActivePlayback: Bool = false
```

**Lifecycle:**
- Reset to `false` at every cast start — in `cast()` before `chromecastManager.cast()`, in `castNewTrack()` before `chromecastManager.cast()`, and in `stopCasting()`.
- Set to `true` on first `PLAYING` or `BUFFERING` status for both video and audio casts.
- IDLE is only treated as "media ended" when `chromecastHasSeenActivePlayback == true`.
- IDLE with `chromecastHasSeenActivePlayback == false` is logged and ignored (pre-load IDLE).

**Critical**: The reset must happen **before** calling `chromecastManager.cast()`, not after. The Chromecast sends its initial IDLE as soon as the new media session is created (during `LOAD`), which can arrive before any `MainActor.run` block scheduled after the cast call executes.

```swift
// WRONG — reset races with arriving IDLE:
try await chromecastManager.cast(url: url, metadata: metadata)
await MainActor.run { self.chromecastHasSeenActivePlayback = false }

// CORRECT — reset before LOAD is issued:
chromecastHasSeenActivePlayback = false
try await chromecastManager.cast(url: url, metadata: metadata)
```

This applies to both `CastManager.cast()` (full connect+cast path) and `CastManager.castNewTrack()` (reuse-existing-session path).

## `.loaded` CastState

`CastState` has a `.loaded` case meaning "LOAD acknowledged by the receiver, awaiting first status update":

- Chromecast video/audio cast: `activeSession.state = .loaded` immediately after `LOAD` is sent.
- On first `PLAYING` or `BUFFERING` status: `activeSession.state = .casting`.
- IDLE arriving while `chromecastHasSeenActivePlayback == false` → ignored (pre-load IDLE).
- IDLE arriving while `chromecastHasSeenActivePlayback == true` → media ended, triggers `stopCasting()`.
- DLNA/UPnP (no status updates): `activeSession.state = .casting` immediately after LOAD.

UI timers in `CastManager` and `VideoPlayerWindowController` skip updates while `activeSession.state == .loaded` to prevent showing stale time before the receiver has confirmed position.

## Cast Architecture — Single Owner Model

`CastManager.activeSession` is the single authoritative description of the active cast. Every other component reads from `activeSession` and subscribes to `CastManager.sessionDidChangeNotification` for updates.

### `currentCast` Enum

```swift
public enum CurrentCast: Sendable { case none; case audio; case video }
```

`CastManager.currentCast` derives from `activeSession`:
- `.none` — `activeSession == nil`
- `.audio` — `activeSession.metadata?.mediaType == .audio` (or nil)
- `.video` — `activeSession.metadata?.mediaType == .video`

Use `currentCast` — not `isCastingVideo` or any window flag — to branch on what is casting. All `WindowManager`, `ContextMenuBuilder`, and `VideoPlayerWindowController` branches use `CastManager.shared.currentCast`.

### Inflight Task Serialization

`cast()` serializes concurrent calls via a private `inflight: Task<Void, Error>?` chain:

```swift
let task = Task { @MainActor in
    try? await inflight?.value  // wait for any in-flight cast first
    // ... actual cast logic
}
inflight = task
try await task.value
```

### Media Type Teardown

If `cast()` is called while a session is active and the new media type differs (e.g., audio → video), `stopCastingAndAwaitTeardown()` runs before the new `LOAD`. This ensures the prior session is fully stopped and `LocalMediaServer` files are unregistered before the new session starts.

### Window Controller Ownership (`didInitiateCast`)

`VideoPlayerWindowController` has a private `didInitiateCast: Bool` flag, `true` only when the cast was started from the player window's own cast button. `windowWillClose` only stops the cast if `case .video = CastManager.shared.currentCast, didInitiateCast`. This allows closing an unrelated player window without interrupting a library-menu cast.

### Video-to-Audio Cast Transition (Auto-Close Video Player)

When `castNewTrack` or `cast()` successfully starts an audio cast while the video player window is open:

- **`castNewTrack` path**: `isCastingVideo` is still `true` at this point. `WindowManager.closeVideoPlayerForCastTransition()` checks `isCastingVideo` and calls `VideoPlayerWindowController.closeForCastTransition()`.
- **`cast()` path**: `stopCastingAndAwaitTeardown()` already ran, which posts `sessionDidChangeNotification` with `currentCast == .none`, triggering `handleCastSessionChange()` which clears `isCastingVideo`. `WindowManager.closeVideoPlayerForCastTransition()` falls back to checking `window?.isVisible`.

`closeForCastTransition()` closes the video player **without** calling `CastManager.stopCasting()`. It sets `isClosing = true` before calling `close()` so `windowWillClose` skips its cleanup block entirely.

### Video Cast Routing

Video playback routes to casting only when casting is already active:

- `WindowManager` video entry points call `routeToVideoCastIfNeeded(...)` before creating/loading the local player.
- If `case .video = CastManager.shared.currentCast`, the next video is cast to the active session's device.
- If no video cast is active, videos load into the local player even when `preferredVideoCastDeviceID` is set.

### Mixed-Type Playlists (`castNewTrack`)

`castNewTrack(track:)` dispatches by `track.mediaType`:
- Video tracks → `castVideoURL(...)` (requires an active video-capable cast session)
- Audio tracks → existing audio cast path

Do not assume all playlist tracks are audio. Video items can appear in audio playlists.

### Audio Is Separate

Audio casting remains explicit: if audio is not already casting, playback stays local until the user picks a cast device. `preferredVideoCastDeviceID` is never used for audio.

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

## Playback Control

After successful LOAD, use the `transportId` for media commands:

| Command | Payload |
|---------|---------|
| PLAY | `{"type":"PLAY","mediaSessionId":1,"requestId":N}` |
| PAUSE | `{"type":"PAUSE","mediaSessionId":1,"requestId":N}` |
| STOP | `{"type":"STOP","mediaSessionId":1,"requestId":N}` |
| SEEK | `{"type":"SEEK","mediaSessionId":1,"currentTime":30.5,"requestId":N}` |
| GET_STATUS | `{"type":"GET_STATUS","requestId":N}` |

To close the Default Media Receiver app (dismiss from TV screen), send STOP to `receiver-0` on the receiver namespace:
```json
{"type":"STOP","requestId":N}  // to: "receiver-0", namespace: urn:x-cast:com.google.cast.receiver
```

### MEDIA_STATUS Response

```json
{
  "type": "MEDIA_STATUS",
  "status": [{
    "mediaSessionId": 1,
    "currentTime": 42.5,
    "playerState": "PLAYING",
    "media": { "duration": 180.0 }
  }],
  "requestId": N
}
```

## Volume Control

```json
{"type":"SET_VOLUME","volume":{"level":0.5},"requestId":N}
{"type":"SET_VOLUME","volume":{"muted":true},"requestId":N}
```

## Key Implementation Gotcha: Data Slice Indexing

Swift `Data` slices maintain original indices. When processing a receive buffer:

```swift
// WRONG:
let byte = buffer[0]
let slice = buffer[4..<total]

// CORRECT:
let byte = buffer[buffer.startIndex]
let startIdx = buffer.startIndex + 4
let endIdx = buffer.startIndex + total
let slice = buffer[startIdx..<endIdx]
```

## Protocol Debugging

### Standalone Test Script

```bash
swift scripts/test_chromecast.swift
```

### Common Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| Silent crash on receive | Data slice indexing | Use `startIndex` explicitly |
| TLS connection fails | Certificate rejection | Accept self-signed in verify block |
| No devices found | mDNS not working | Check network, firewall |
| Second cast fails with immediate IDLE teardown | `chromecastHasSeenActivePlayback` not reset | Reset flag **before** calling `chromecastManager.cast()`, also in `stopCasting()` |
| Audio cast play controls do nothing | Session still in `.loaded` state | Use `currentCast == .audio` not `isCasting` to detect audio |
| Seek bar progresses while paused | `playbackStartDate` not cleared on pause | Set `playbackStartDate = nil` when not PLAYING |
| Stop leaves video paused on TV | STOP delivered to media but app still running | Call `stopApp()` after `stop()`; add 200ms delay before `disconnect()` |
| Stop command not delivered | Socket closed before bytes flush | Sleep 200ms between `stop()` and `disconnect()` |
| `clearVideoTrackInfo()` not called | `wasVideoCast` captured after `activeSession` set to nil | Capture `wasVideoCast = currentCast == .video` **before** disconnect |
| Video player stays open after switching to audio cast | Not calling `closeForCastTransition()` | Call `WindowManager.closeVideoPlayerForCastTransition()` after audio cast succeeds |
| Timer drifts during buffering | Not pausing interpolation on BUFFERING | Set `playbackStartDate = nil` on BUFFERING; resume on PLAYING |
| Controls stop working | CLOSE message received | Check `castSessionDidClose()` delegate callback |

## References

- [Google Cast SDK Documentation](https://developers.google.com/cast/docs/developers)
- [OpenCastSwift](https://github.com/mhmiles/OpenCastSwift) - Reference implementation
- [node-castv2](https://github.com/thibauts/node-castv2) - Node.js implementation
