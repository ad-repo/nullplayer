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
│  LOCAL FILES                        STREAMING (Plex)                 │
│  ────────────                       ──────────────────               │
│                                                                      │
│  ┌──────────────┐                   ┌─────────────────────────────┐ │
│  │ AVAudioFile  │                   │   StreamingAudioPlayer      │ │
│  └──────┬───────┘                   │   (AudioStreaming lib)      │ │
│         │                           │                             │ │
│         ▼                           │  ┌───────────────────────┐  │ │
│  ┌──────────────┐                   │  │ HTTP URL → Decode →   │  │ │
│  │ playerNode   │                   │  │ PCM buffers           │  │ │
│  │ (AVAudio     │                   │  └───────────┬───────────┘  │ │
│  │  PlayerNode) │                   │              │              │ │
│  └──────┬───────┘                   │              ▼              │ │
│         │                           │  ┌───────────────────────┐  │ │
│         ▼                           │  │ eqNode (10-band)      │  │ │
│  ┌──────────────┐                   │  │ AVAudioUnitEQ         │  │ │
│  │ eqNode       │                   │  └───────────┬───────────┘  │ │
│  │ (10-band EQ) │                   │              │              │ │
│  └──────┬───────┘                   │              ▼              │ │
│         │                           │  ┌───────────────────────┐  │ │
│         ▼                           │  │ Spectrum Tap          │  │ │
│  ┌──────────────┐                   │  │ (frameFiltering)      │  │ │
│  │ limiterNode  │                   │  └───────────────────────┘  │ │
│  │ (Anti-clip)  │                   └─────────────────────────────┘ │
│  └──────┬───────┘                                                   │
│         │                           EQ settings sync ◄──────────►   │
│         ▼                                                           │
│  ┌──────────────┐                                                   │
│  │mainMixerNode │                                                   │
│  └──────┬───────┘                                                   │
│         │                                                           │
│         ▼                                                           │
│  ┌──────────────┐                                                   │
│  │ Output Node  │ ─────► Speakers / Selected Audio Device           │
│  └──────────────┘                                                   │
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
private let eqNode = AVAudioUnitEQ(numberOfBands: 10)
private let limiterNode = AVAudioUnitDynamicsProcessor()  // Anti-clipping
private var streamingPlayer: StreamingAudioPlayer?  // For HTTP streaming
var gaplessPlaybackEnabled: Bool           // Pre-schedule next track
var volumeNormalizationEnabled: Bool       // Loudness normalization
```

### StreamingAudioPlayer (`StreamingAudioPlayer.swift`)

A wrapper around the [AudioStreaming](https://github.com/dimitris-c/AudioStreaming) library that provides:
- HTTP audio streaming with buffering
- Its own AVAudioUnitEQ for processing
- Spectrum analysis via frame filtering
- State change callbacks

**Why a separate EQ?**  
AVAudioNode instances can only be attached to one AVAudioEngine at a time. Since AudioStreaming uses its own internal engine, we maintain a separate EQ node that stays synchronized with the main engine's EQ.

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

1. When a track starts playing, the next track in the playlist is loaded and scheduled to play immediately after
2. `AVAudioPlayerNode.scheduleFile()` queues the next file
3. When the current track ends, playback continues seamlessly to the pre-scheduled track
4. The next-next track is then pre-scheduled

### Limitations

- Only works for **local files** (not HTTP streaming)
- Not compatible with **repeat single track** mode (handled separately)
- Shuffle mode picks a random next track to pre-schedule

### Settings Persistence

The gapless setting is saved to UserDefaults and restored on app launch.

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

## Historical Note

Prior to the AudioStreaming integration, Plex streaming used `AVPlayer` which outputs directly to hardware, bypassing `AVAudioEngine`. An attempt was made to bridge this using `MTAudioProcessingTap` and a ring buffer to route audio through the EQ, but this failed due to fundamental timing mismatches between the tap's push model and the engine's pull model.

The AudioStreaming library solves this by handling streaming entirely within `AVAudioEngine`, allowing proper integration with audio processing nodes.
