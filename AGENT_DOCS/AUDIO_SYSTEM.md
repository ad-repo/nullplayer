# Audio System Architecture

This document describes AdAmp's audio playback system, including local file playback, streaming audio, equalization, and spectrum analysis.

## Overview

AdAmp uses two parallel audio pipelines to handle different content types:

| Content Type | Pipeline | EQ Support | Spectrum |
|-------------|----------|------------|----------|
| Local files (.mp3, .flac, etc.) | AVAudioEngine | Yes | Yes |
| HTTP streaming (Plex) | AudioStreaming library | Yes | Yes |

Both pipelines support full 10-band EQ and real-time spectrum visualization. EQ settings are automatically synchronized between them.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                         AudioEngine                                  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  LOCAL FILES                        STREAMING (Plex/Subsonic)        │
│  ────────────                       ──────────────────────────       │
│                                                                      │
│  ┌──────────────┐                   ┌─────────────────────────────┐ │
│  │ AVAudioFile  │                   │   StreamingAudioPlayer      │ │
│  └──────┬───────┘                   │   (AudioStreaming lib)      │ │
│         │                           │                             │ │
│         ▼                           │  ┌───────────────────────┐  │ │
│  ┌──────────────┐                   │  │ HTTP URL → Decode →   │  │ │
│  │ playerNode   │─────────┐         │  │ PCM buffers           │  │ │
│  │ (primary)    │         │         │  └───────────┬───────────┘  │ │
│  └──────────────┘         │         │              │              │ │
│                           │         │              ▼              │ │
│  ┌──────────────┐         │         │  ┌───────────────────────┐  │ │
│  │crossfadeNode │─────────┼──► mixerNode ─► eqNode ─► limiter   │ │
│  │ (for Sweet   │         │         │  │ AVAudioUnitEQ         │  │ │
│  │  Fades)      │         │         │  └───────────┬───────────┘  │ │
│  └──────────────┘         │         │              │              │ │
│                           │         │              ▼              │ │
│                           │         │  ┌───────────────────────┐  │ │
│                           │         │  │ Spectrum Tap          │  │ │
│                           │         │  │ (frameFiltering)      │  │ │
│                           │         │  └───────────────────────┘  │ │
│                           ▼         └─────────────────────────────┘ │
│                    ┌──────────────┐                                 │
│                    │ mixerNode    │  EQ settings sync ◄──────────►  │
│                    └──────┬───────┘                                 │
│                           │                                         │
│                           ▼                                         │
│                    ┌──────────────┐                                 │
│                    │ eqNode       │                                 │
│                    │ (10-band EQ) │                                 │
│                    └──────┬───────┘                                 │
│                           │                                         │
│                           ▼                                         │
│                    ┌──────────────┐                                 │
│                    │ limiterNode  │                                 │
│                    │ (Anti-clip)  │                                 │
│                    └──────┬───────┘                                 │
│                           │                                         │
│                           ▼                                         │
│                    ┌──────────────┐                                 │
│                    │mainMixerNode │                                 │
│                    └──────┬───────┘                                 │
│                           │                                         │
│                           ▼                                         │
│                    ┌──────────────┐                                 │
│                    │ Output Node  │ ─────► Speakers / Audio Device  │
│                    └──────────────┘                                 │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## Components

### AudioEngine (`AudioEngine.swift`)

The main audio controller that manages:
- Playback state (play, pause, stop, seek)
- Playlist management
- Track loading (routes to appropriate pipeline)
- EQ settings (synced to both pipelines)
- Anti-clipping limiter for EQ protection
- Gapless playback (optional, local files only)
- Volume normalization (optional, local files only)
- Output device selection
- Delegate notifications for UI updates

**Key Properties:**
```swift
private let engine = AVAudioEngine()        // For local files
private let playerNode = AVAudioPlayerNode()
private let crossfadePlayerNode = AVAudioPlayerNode() // For Sweet Fades
private let eqNode = AVAudioUnitEQ(numberOfBands: 10)
private let limiterNode = AVAudioUnitDynamicsProcessor()  // Anti-clipping
private var streamingPlayer: StreamingAudioPlayer?  // For HTTP streaming
private var crossfadeStreamingPlayer: StreamingAudioPlayer? // For Sweet Fades
var gaplessPlaybackEnabled: Bool           // Pre-schedule next track
var volumeNormalizationEnabled: Bool       // Loudness normalization
var sweetFadeEnabled: Bool                 // Crossfade between tracks
var sweetFadeDuration: TimeInterval        // Crossfade length (1-10s)
```

### StreamingAudioPlayer (`StreamingAudioPlayer.swift`)

A wrapper around the [AudioStreaming](https://github.com/dimitris-c/AudioStreaming) library that provides:
- HTTP audio streaming with buffering
- Its own AVAudioUnitEQ for processing
- Spectrum analysis via frame filtering
- State change callbacks

**Why a separate EQ?**  
AVAudioNode instances can only be attached to one AVAudioEngine at a time. Since AudioStreaming uses its own internal engine, we maintain a separate EQ node that stays synchronized with the main engine's EQ.

### Track Switch Race Condition Guard

When switching streaming tracks (e.g., clicking to play a different track), two race conditions can occur:

1. **EOF callback race**: The old track's EOF callback fires even though it was intentionally stopped, which would incorrectly advance the playlist
2. **Stop/play race**: If `stop()` is called before `play(url:)`, the async stop operation can cancel the newly queued track

**Solution**: AudioEngine uses an `isLoadingNewStreamingTrack` flag and avoids explicit `stop()` calls:

```swift
private var isLoadingNewStreamingTrack: Bool = false

private func loadStreamingTrack(_ track: Track) {
    isLoadingNewStreamingTrack = true   // Set before starting new track
    
    // DON'T call stop() before play() - the AudioStreaming library handles this internally.
    // Calling stop() explicitly causes a race condition where the async stop callback
    // fires AFTER play(url:) is called, cancelling the newly queued track.
    
    streamingPlayer?.play(url: track.url)
    
    // Set state immediately so play() doesn't try to reload
    state = .playing
    
    // Clear flag after delay to ensure stale EOF callbacks have passed
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
        self?.isLoadingNewStreamingTrack = false
    }
}

func streamingPlayerDidFinishPlaying() {
    // Ignore EOF callbacks that fire during track switch
    guard !isLoadingNewStreamingTrack else { return }
    trackDidFinish()
}
```

**Key points:**
- Don't call `stop()` before `play(url:)` - the AudioStreaming library handles stopping internally
- Set `state = .playing` immediately after `play(url:)` to prevent the `play()` function from triggering a redundant reload
- The 50ms delay ensures stale EOF callbacks from the old track are ignored

This prevents race conditions where clicking to play track N would result in track N+1 playing or no playback at all.

## Equalizer

### Configuration

Both EQ nodes use identical Winamp-style 10-band configuration:

| Band | Frequency | Filter Type | Bandwidth |
|------|-----------|-------------|-----------|
| 0 | 60 Hz | Low Shelf | 2.0 octaves |
| 1 | 170 Hz | Parametric | 2.0 octaves |
| 2 | 310 Hz | Parametric | 2.0 octaves |
| 3 | 600 Hz | Parametric | 2.0 octaves |
| 4 | 1 kHz | Parametric | 2.0 octaves |
| 5 | 3 kHz | Parametric | 1.5 octaves |
| 6 | 6 kHz | Parametric | 1.5 octaves |
| 7 | 12 kHz | Parametric | 1.5 octaves |
| 8 | 14 kHz | Parametric | 1.5 octaves |
| 9 | 16 kHz | High Shelf | 1.5 octaves |

### Gain Range

- Per-band gain: **-12 dB to +12 dB**
- Preamp (global gain): **-12 dB to +12 dB**

### Default State

The EQ is **disabled (bypassed) by default** to preserve original audio quality. Users must explicitly enable it via the EQ window's ON/OFF button. When disabled, audio passes through unprocessed at full resolution.

### Anti-Clipping Limiter

A transparent limiter (Apple's `AUDynamicsProcessor` Audio Unit) is inserted after the EQ to prevent clipping when boosts are applied:

- **Threshold:** -1 dB (catches peaks just before clipping)
- **Headroom:** 1 dB
- **Attack:** 1ms (fast response)
- **Release:** 50ms (transparent recovery)

The limiter is always active but only engages when peaks approach 0 dB.

### EQ Synchronization

When EQ settings change, both pipelines are updated:

```swift
func setEQBand(_ band: Int, gain: Float) {
    let clampedGain = max(-12, min(12, gain))
    eqNode.bands[band].gain = clampedGain      // Local pipeline
    streamingPlayer?.setEQBand(band, gain: clampedGain)  // Streaming pipeline
}
```

When loading a streaming track, current EQ settings are synced:

```swift
private func syncEQToStreamingPlayer() {
    var bands: [Float] = []
    for i in 0..<10 {
        bands.append(eqNode.bands[i].gain)
    }
    streamingPlayer?.syncEQSettings(bands: bands, preamp: eqNode.globalGain, enabled: !eqNode.bypass)
}
```

## Gapless Playback

When enabled via **Playback Options → Gapless Playback**, the engine pre-schedules the next track for seamless transitions between songs.

### How It Works

**Local Files:**
1. When a track starts playing, the next track in the playlist is loaded and scheduled to play immediately after
2. `AVAudioPlayerNode.scheduleFile()` queues the next file
3. When the current track ends, playback continues seamlessly to the pre-scheduled track
4. The next-next track is then pre-scheduled

**Streaming (Plex/Subsonic):**
1. Uses the AudioStreaming library's `queue(url:)` method to pre-buffer the next streaming track
2. The queued track plays immediately when the current track finishes
3. Only works when both current and next tracks are streaming (can't cross pipelines)

### Constraints

| Scenario | Behavior |
|----------|----------|
| Sweet Fades enabled | Gapless disabled - crossfade handles transitions |
| Casting active | Gapless disabled - playback is remote |
| Mixed sources (local→streaming) | Gapless disabled for that transition |
| Repeat single track mode | Handled separately (gapless not needed) |
| Shuffle mode | Random next track is pre-scheduled |

### Settings Persistence

The gapless setting is saved to UserDefaults and restored on app launch.

## Sweet Fades (Crossfade)

When enabled via **Playback Options → Sweet Fades (Crossfade)**, tracks smoothly blend into each other with overlapping playback and volume fading.

### How It Works

1. When the current track approaches its end (remaining time = fade duration), the next track begins playing at volume 0
2. Both tracks play simultaneously while their volumes are crossfaded:
   - Outgoing track: fades from full volume to 0
   - Incoming track: fades from 0 to full volume
3. Uses an **equal-power fade curve** (sine/cosine) for perceptually smooth transitions
4. When the fade completes, the outgoing track is stopped

### Signal Flow During Crossfade

**Local Files:**
```
playerNode ─────────────────┐
(outgoing, fading out)      │
                            ├─► mixerNode ─► eqNode ─► limiter ─► output
crossfadePlayerNode ────────┘
(incoming, fading in)
```

**Streaming:**
Two independent `StreamingAudioPlayer` instances with their volumes controlled independently.

### Fade Duration

Configurable via **Playback Options → Fade Duration** when Sweet Fades is enabled:
- 1s, 2s, 3s, **5s (default)**, 7s, 10s

### Constraints

| Scenario | Behavior |
|----------|----------|
| Casting active | Crossfade disabled - playback is remote |
| Mixed sources (local→streaming) | Crossfade skipped for that transition |
| Next track shorter than 2x fade | Crossfade skipped (track too short) |
| Repeat single track mode | Crossfade skipped (unusual UX) |
| End of playlist | No crossfade, normal stop |
| User skips/seeks during fade | Crossfade cancelled, normal playback resumes |

### Cancel Conditions

The crossfade is cancelled if the user:
- Seeks to a new position
- Skips to next/previous track
- Selects a different track
- Stops playback

When cancelled, the outgoing track's volume is restored and the incoming track is stopped.

### Interaction with Gapless Playback

Sweet Fades takes precedence over gapless playback:
- When Sweet Fades is enabled, gapless pre-scheduling is disabled
- When Sweet Fades is disabled, gapless resumes (if enabled)

### Settings Persistence

Both `sweetFadeEnabled` and `sweetFadeDuration` are saved to UserDefaults and restored on app launch.

## Volume Normalization

When enabled via **Playback Options → Volume Normalization**, tracks are analyzed and gain-adjusted to achieve consistent perceived loudness.

### Algorithm

1. **Analysis:** Scan up to 30 seconds of audio for peak and RMS levels
2. **Target:** -14 dB (similar to streaming services like Spotify)
3. **Gain calculation:** `target - trackRMS`, clamped to ±12 dB
4. **Headroom protection:** Gain reduced if peaks would exceed -0.5 dB

### Implementation

```swift
// Calculate gain needed to reach target loudness
let gainNeededDB = targetLoudnessDB - rmsDB
let clampedGainDB = max(-12.0, min(12.0, gainNeededDB))

// Prevent clipping
if peakDB + clampedGainDB > -0.5 {
    finalGainDB = clampedGainDB - (peakAfterGain + 0.5)
}

// Apply as linear multiplier to volume
normalizationGain = pow(10.0, finalGainDB / 20.0)
```

### Limitations

- Only applies to **local files** (streaming tracks not analyzed)
- Uses RMS as a loudness estimate (not true LUFS measurement)
- Re-analyzes when track loads (no persistent cache)

## Spectrum Analyzer

Both pipelines feed spectrum data to the UI for visualization.

### Implementation

**Local files:** Uses `AVAudioPlayerNode.installTap()` on the player node.

**Streaming:** Uses AudioStreaming's `frameFiltering` API:
```swift
player.frameFiltering.add(entry: "spectrumAnalyzer") { [weak self] buffer, _ in
    self?.processAudioBuffer(buffer)
}
```

### Processing Pipeline

1. **Sample extraction** - Get float samples from PCM buffer (mono-mix stereo)
2. **Windowing** - Apply Hann window to reduce spectral leakage
3. **FFT** - 512-point DFT using Accelerate framework (vDSP) (~11.6ms at 44.1kHz)
4. **Magnitude calculation** - Convert complex output to magnitudes
5. **Frequency mapping** - Map FFT bins to 75 bands (logarithmic, 20Hz-20kHz)
6. **Normalization** - Normalize to peak and apply power curve (0.4)
7. **Smoothing** - Fast attack, slow decay for visual appeal

**Note:** The FFT size was reduced from 2048 to 512 samples to decrease audio-to-visualization latency from ~46ms to ~11.6ms.

### Output

75 float values (0.0-1.0) representing energy in each frequency band, updated via delegate:
```swift
delegate?.audioEngineDidUpdateSpectrum(spectrumData)
```

## Milkdrop Visualization

AdAmp includes a Milkdrop visualization window powered by projectM (libprojectM-4).

### Low-Latency PCM Delivery

PCM audio data is pushed directly to the visualization using `NotificationCenter`:

```swift
// Posted from audio tap with ~23ms latency
NotificationCenter.default.post(
    name: .audioPCMDataUpdated,
    object: self,
    userInfo: ["pcm": pcmSamples, "sampleRate": sampleRate]
)
```

The visualization subscribes to this notification and receives PCM data directly from the audio tap (on the audio thread) for lowest possible latency. Thread safety is handled by the visualization view's internal `dataLock`.

**Previous approach:** A 60fps Timer polled `AudioEngine.pcmData` from the main thread, adding 16-33ms of additional latency on top of the FFT buffer latency.

**Current approach:** Direct notification from audio tap eliminates polling latency. Total latency is now approximately **15-20ms** (down from **60-80ms**).

**Additional optimizations:**
- The visualization's "idle mode" (calmer beats when audio is paused) only updates when playback state changes via `audioPlaybackStateChanged` notification, rather than checking on every PCM buffer. This eliminates ~40-60 unnecessary main thread dispatches per second.
- PCM buffer reduced from 1024 to 512 samples for faster data transfer
- `OSAllocatedUnfairLock` used instead of `NSLock` for faster thread synchronization

### Idle Mode (Calm Visualization)

When audio is not playing, the visualization automatically enters "idle mode" to provide a calmer visual experience:

- **Beat sensitivity** is reduced from 1.0 (normal) to 0.2 (idle)
- The visualization continues animating but responds less dramatically to any residual audio data
- When music starts playing, beat sensitivity automatically returns to normal

This prevents the visualization from appearing overly active when no music is playing.

### Fullscreen Mode

The Milkdrop window supports fullscreen mode:

- Press **F** to toggle fullscreen
- Press **Escape** to exit fullscreen
- Menu bar and dock auto-hide in fullscreen
- Window chrome is hidden for immersive viewing

Note: The Milkdrop window uses a custom fullscreen implementation (rather than macOS native fullscreen) because it's a borderless window for authentic Winamp styling.

### Keyboard Controls

| Key | Action |
|-----|--------|
| F | Toggle fullscreen |
| Escape | Exit fullscreen |
| → | Next preset |
| ← | Previous preset |
| Shift+→ | Next preset (hard cut) |
| Shift+← | Previous preset (hard cut) |
| R | Random preset |
| Shift+R | Random preset (hard cut) |
| L | Toggle preset lock |

## Output Device Selection

AudioEngine supports routing audio to specific output devices:

```swift
func setOutputDevice(_ deviceID: AudioDeviceID?) -> Bool
```

This uses CoreAudio's `AudioUnitSetProperty` with `kAudioOutputUnitProperty_CurrentDevice` on the engine's output node.

**Note:** Output device selection only affects local file playback. Streaming audio uses the system default output (AudioStreaming limitation).

## File Support

### Local Playback (AVAudioEngine)

Formats supported by AVAudioFile:
- MP3, M4A, AAC, WAV, AIFF, FLAC, ALAC, OGG

### Streaming Playback (AudioStreaming)

- HTTP/HTTPS URLs
- MP3, AAC, Ogg Vorbis streams
- Shoutcast/Icecast with metadata

## Dependencies

| Library | Purpose | Version |
|---------|---------|---------|
| AVFoundation | Local file playback, EQ | System |
| Accelerate | FFT for spectrum analysis | System |
| CoreAudio | Output device management | System |
| [AudioStreaming](https://github.com/dimitris-c/AudioStreaming) | HTTP streaming with AVAudioEngine | 1.4.0+ |

## Platform Requirements

- **macOS 13.0+** (required by AudioStreaming library)

## Plex Play Statistics

When playing Plex content, AdAmp reports playback activity back to the Plex server. This enables:

- **Play count tracking** - Tracks are marked as "played" and count increments
- **Last played date** - Server records when you last listened/watched
- **Now Playing** - Shows what's playing in other Plex clients
- **Continue watching** - Resume playback where you left off (videos)

### PlexPlaybackReporter

The `PlexPlaybackReporter` singleton manages all Plex reporting:

```swift
// Automatic integration - no manual calls needed
// AudioEngine calls the reporter at appropriate playback events:
- trackDidStart()    // When a Plex track begins playing
- trackDidPause()    // When playback is paused
- trackDidResume()   // When playback resumes
- trackDidStop()     // When playback stops or track finishes
- updatePosition()   // Called every 100ms for progress tracking
```

### Timeline Updates

Periodic updates are sent to Plex every **10 seconds** during playback:
- Current playback position
- Playing/paused/stopped state
- Enables "Now Playing" in Plex dashboard

### Scrobbling

A track is marked as "played" (scrobbled) when:
1. Track reaches **90% completion**, OR
2. Track finishes naturally (reaches the end)

**AND** at least **30 seconds** have been played (prevents accidental scrobbles from quick skips).

### API Endpoints

| Endpoint | Purpose |
|----------|---------|
| `/:/timeline` | Report playback state and position |
| `/:/scrobble` | Mark item as played |
| `/:/unscrobble` | Mark item as unplayed |
| `/:/progress` | Update resume position |

### Track Model Integration

Plex items include a `plexRatingKey` property in the Track model:

```swift
struct Track {
    // ... other properties ...
    let plexRatingKey: String?  // nil for local files
}
```

The reporter checks for this key and only reports for Plex content.

### PlexVideoPlaybackReporter

The `PlexVideoPlaybackReporter` singleton manages Plex reporting for **video content** (movies and TV episodes):

```swift
// Automatic integration - VideoPlayerWindowController calls the reporter:
- movieDidStart()      // When a Plex movie begins playing
- episodeDidStart()    // When a Plex episode begins playing
- videoDidPause()      // When video playback is paused
- videoDidResume()     // When video playback resumes
- videoDidStop()       // When video playback stops or finishes
- updatePosition()     // Called during playback for progress tracking
```

**Video Scrobbling Rules:**
- Video is marked as "watched" when reaching **90% completion** or finishing naturally
- Minimum **60 seconds** of playback required (prevents accidental scrobbles)
- Reports `type: "movie"` or `type: "episode"` to distinguish video from audio

**Video Integration:**
- `VideoPlayerWindowController.play(movie:)` - Starts tracking for movies
- `VideoPlayerWindowController.play(episode:)` - Starts tracking for TV episodes
- Non-Plex videos (local files) are not reported

## Plex Radio/Mix

AdAmp supports Plex radio features, allowing you to generate dynamic playlists based on a seed track, album, or artist. This is similar to PlexAmp's "Track Radio", "Artist Radio", and "Album Radio" features.

### Accessing Radio Features

Right-click on any Plex track, album, or artist in the browser to access radio options:

| Item Type | Menu Option | Description |
|-----------|-------------|-------------|
| Track | "Start Track Radio" | Plays sonically similar tracks based on the seed track |
| Album | "Start Album Radio" | Plays tracks from sonically similar albums |
| Artist | "Start Artist Radio" | Plays tracks from sonically similar artists |

### How It Works

The radio feature uses Plex's sonic analysis API to find similar content:

1. **Track Radio**: Uses `track.sonicallySimilar={trackID}` filter with random sorting
2. **Album Radio**: Fetches sonically similar albums, then gets tracks from each
3. **Artist Radio**: Fetches sonically similar artists, then gets tracks from each

### Technical Requirements

Full radio functionality requires:

- **Plex Pass** subscription (for sonic analysis features)
- **Plex Media Server v1.24.0+** (64-bit)
- **Sonic analysis enabled** on the server for the music library

Tracks with sonic analysis have a `musicAnalysisVersion` attribute in their metadata.

### API Endpoints

| Endpoint | Purpose |
|----------|---------|
| `/library/sections/{libraryID}/all?type=10&track.sonicallySimilar={id}` | Fetch sonically similar tracks |
| `/library/sections/{libraryID}/all?type=9&album.sonicallySimilar={id}` | Fetch sonically similar albums |
| `/library/sections/{libraryID}/all?type=8&artist.sonicallySimilar={id}` | Fetch sonically similar artists |

### Radio Playlist Size

By default, radio playlists include up to 100 tracks. The results use `sort=random` for variety.

## Subsonic/Navidrome Streaming

AdAmp supports streaming music from Subsonic-compatible servers (including Navidrome). This uses the same HTTP streaming pipeline as Plex.

### SubsonicManager

The `SubsonicManager` singleton handles:
- Server connection management (multiple servers supported)
- Library content caching (artists, albums, playlists)
- Track conversion to AudioEngine-compatible format
- Credential storage via KeychainHelper

### SubsonicServerClient

Handles all Subsonic REST API communication:
- **Token authentication**: `md5(password + salt)` per request
- **API version**: 1.16.1 (widely compatible)
- **Endpoints**: getArtists, getAlbum, stream, search3, playlists, star/unstar, scrobble

### Scrobbling

The `SubsonicPlaybackReporter` reports playback activity to the Subsonic server:

| Event | Report Type | Description |
|-------|-------------|-------------|
| Track starts | `submission=false` | "Now playing" indicator |
| 50% played OR 4 minutes | `submission=true` | Track marked as played |

Standard scrobbling rules: track is scrobbled when played 50% or 4 minutes, whichever comes first.

### Track Model Integration

Subsonic items include identifiers in the Track model:

```swift
struct Track {
    // ... other properties ...
    let subsonicId: String?       // Song ID for scrobbling (nil for non-Subsonic)
    let subsonicServerId: String? // Which server the track belongs to
}
```

### Stream URLs

Stream URLs include authentication parameters:
```
http://server/rest/stream?id=SONG_ID&u=USERNAME&t=TOKEN&s=SALT&v=1.16.1&c=AdAmp&f=json
```

### API Endpoints

| Endpoint | Purpose |
|----------|---------|
| `ping` | Test server connection |
| `getArtists` | Fetch artist list (indexed A-Z) |
| `getArtist` | Get artist details + albums |
| `getAlbum` | Get album details + tracks |
| `getAlbumList2` | Browse albums (various sorts) |
| `search3` | Full-text search |
| `stream` | Get audio stream for a track |
| `getCoverArt` | Get artwork image |
| `getPlaylists` / `getPlaylist` | Playlist management |
| `star` / `unstar` | Favorite items |
| `getStarred2` | Get all favorites |
| `scrobble` | Report playback |

## Historical Note

Prior to the AudioStreaming integration, Plex streaming used `AVPlayer` which outputs directly to hardware, bypassing `AVAudioEngine`. An attempt was made to bridge this using `MTAudioProcessingTap` and a ring buffer to route audio through the EQ, but this failed due to fundamental timing mismatches between the tap's push model and the engine's pull model.

The AudioStreaming library solves this by handling streaming entirely within `AVAudioEngine`, allowing proper integration with audio processing nodes.
