# Internet Radio

NullPlayer supports Shoutcast and Icecast internet radio streaming with automatic reconnection and live metadata display.

## Architecture

```
Sources/NullPlayer/
├── Radio/
│   └── RadioManager.swift        # Singleton managing radio state
├── Data/Models/
│   └── RadioStation.swift        # Station data model
└── Windows/Radio/
    └── AddRadioStationSheet.swift # Add/edit station UI
```

## Key Components

### RadioManager

Singleton (`RadioManager.shared`) that manages:
- Station list (persisted to UserDefaults)
- Current playing station
- Connection state (disconnected/connecting/connected/reconnecting/failed)
- ICY stream metadata (current song title)
- Auto-reconnect logic

**Key Properties:**
```swift
var stations: [RadioStation]           // All saved stations
var currentStation: RadioStation?      // Currently playing (nil if not radio)
var currentStreamTitle: String?        // ICY metadata "Artist - Song"
var connectionState: ConnectionState   // Current connection state
var isActive: Bool                      // True if radio is playing
var statusText: String?                 // Display text for marquee
```

**Notifications:**
- `stationsDidChangeNotification` - Station list modified
- `streamMetadataDidChangeNotification` - ICY metadata received
- `connectionStateDidChangeNotification` - Connection state changed

### RadioStation Model

```swift
struct RadioStation: Identifiable, Codable {
    let id: UUID
    var name: String
    var url: URL
    var genre: String?
    var iconURL: URL?
    
    func toTrack() -> Track  // Convert to playable Track
}
```

### Connection States

```swift
enum ConnectionState {
    case disconnected           // Not playing radio
    case connecting             // Initial connection attempt
    case connected              // Successfully streaming
    case reconnecting(attempt)  // Auto-reconnect in progress
    case failed(message)        // Connection failed
}
```

## Audio Engine Integration

RadioManager integrates with AudioEngine through delegate callbacks:

| Callback | Purpose |
|----------|---------|
| `streamDidConnect()` | Called when stream starts playing |
| `streamDidDisconnect(error:)` | Called on stream end/error, triggers reconnect |
| `streamDidReceiveMetadata(_:)` | Receives ICY metadata for display |

**Critical: State Preservation**

When `loadTracks()` is called with radio content:
1. Detect radio content by comparing `track.url` with `currentStation.url`
2. Use `stopLocalOnly()` instead of `stop()` to preserve RadioManager state
3. Calling `stop()` would trigger `RadioManager.stop()`, clearing state

```swift
// In loadTracks()
let isRadioContent: Bool
if RadioManager.shared.isActive {
    isRadioContent = validTracks.first.map { track in
        RadioManager.shared.currentStation?.url == track.url
    } ?? false
    // ...
}

// Use stopLocalOnly() for radio, stop() for other content
if isRadioContent {
    stopLocalOnly()  // Preserves RadioManager state
} else {
    stop()  // Calls RadioManager.stop() for non-radio
}
```

## Playlist URL Resolution

Radio stations often use playlist URLs (`.pls`, `.m3u`, `.m3u8`) that must be resolved to actual stream URLs:

```swift
func startPlayback(station: RadioStation) {
    let ext = station.url.pathExtension.lowercased()
    if ext == "pls" || ext == "m3u" || ext == "m3u8" {
        resolvePlaylistURL(station.url) { resolvedURL in
            // IMPORTANT: Check casting state fresh here, not before async call
            if !CastManager.shared.isCasting {
                WindowManager.shared.audioEngine.play()
            }
        }
    }
}
```

**Gotcha:** The `resolvePlaylistURL` call can take up to 10 seconds. Always check `CastManager.shared.isCasting` fresh inside the callback, not captured before the async call.

## Auto-Reconnect

When a stream disconnects unexpectedly:

1. RadioManager receives `streamDidDisconnect(error:)` from AudioEngine
2. If `manualStopRequested` is false and `autoReconnectEnabled` is true:
   - Increment `reconnectAttempts`
   - Set state to `.reconnecting(attempt: n)`
   - Schedule reconnect with exponential backoff (2s, 4s, 8s, 16s, 32s)
3. After `maxReconnectAttempts` (5), set state to `.failed`

**Manual stop does NOT trigger reconnect:**
- User pressing Stop → `manualStopRequested = true`
- Loading non-radio content → `RadioManager.stop()` called
- Switching stations → `currentStation` changes, resets attempts

## ICY Metadata

Shoutcast/Icecast streams include in-band metadata with current song info:

1. `StreamingAudioPlayer` receives metadata from AudioStreaming library
2. Forwards via `streamingPlayerDidReceiveMetadata(_:)` delegate method
3. AudioEngine checks `RadioManager.shared.isActive` and forwards to RadioManager
4. RadioManager updates `currentStreamTitle` and posts notification
5. MainWindowView observes notification and updates marquee display

**Metadata keys:**
- `StreamTitle` - Usually "Artist - Song" format
- `StreamUrl` - Stream URL (sometimes)
- `icy-name` - Station name
- `icy-genre` - Station genre

## Casting Radio to Sonos

Internet radio can be cast to Sonos speakers:

1. Sonos receives the stream URL directly (no proxy needed)
2. Time resets to 0:00 (live stream, no seeking)
3. Local playback stops when casting starts

**Flow:**
1. User starts radio playback locally
2. Opens Sonos menu, selects rooms
3. Clicks "Start Casting"
4. `CastManager.castToSonos()` sends stream URL to Sonos
5. Local playback stops via `stopLocalForCasting()`

## UI Integration

### Library Browser

Radio stations appear in the Library Browser when "Internet Radio" source is selected:
- Station list with name, genre, stream URL
- Double-click to play
- Right-click context menu (Play, Edit, Delete)
- "+ADD" button for adding stations

### Main Window Marquee

The marquee displays (in priority order):
1. Error message (if any)
2. Video title (if video playing)
3. Radio status/stream title (if radio active)
4. Track title

```swift
func getMarqueeDisplayText() -> String {
    if let error = errorMessage { return error }
    if WindowManager.shared.isVideoActivePlayback { return videoTitle }
    if RadioManager.shared.isActive { return RadioManager.shared.statusText }
    return currentTrack?.displayTitle ?? "NullPlayer"
}
```

## Station Persistence

Stations are stored in UserDefaults as JSON:

```swift
private let stationsKey = "RadioStations"

func saveStations() {
    let data = try? JSONEncoder().encode(stations)
    UserDefaults.standard.set(data, forKey: stationsKey)
}

func loadStations() {
    guard let data = UserDefaults.standard.data(forKey: stationsKey),
          let saved = try? JSONDecoder().decode([RadioStation].self, from: data) else {
        stations = defaultStations()
        return
    }
    stations = saved
}
```

## Default Stations

New installations include sample SomaFM stations:
- Groove Salad
- Drone Zone
- DEF CON Radio

## Testing Radio

Manual QA checklist:
- [ ] Add station with direct stream URL
- [ ] Add station with .pls/.m3u URL (resolves to stream)
- [ ] Play station, verify ICY metadata displays
- [ ] Stop playback, verify no auto-reconnect
- [ ] Disconnect network, verify auto-reconnect attempts
- [ ] Cast to Sonos, verify stream plays on speaker
- [ ] Switch from radio to Plex/local, verify clean transition
- [ ] Switch from Plex/local to radio, verify state preserved
