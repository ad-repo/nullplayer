# Audio Pipelines - Detailed Implementation

This document covers the detailed implementation of gapless playback, Sweet Fades (crossfade), volume normalization, and the waveform side path that sits alongside playback.

## Gapless Playback

When enabled via **Playback Options → Gapless Playback**, the engine pre-schedules the next track for seamless transitions between songs.

### How It Works

**Local Files:**
1. When a track starts playing, the next track in the playlist is loaded and scheduled to play immediately after
2. `AVAudioPlayerNode.scheduleFile()` queues the next file
3. When the current track ends, playback continues seamlessly to the pre-scheduled track
4. The next-next track is then pre-scheduled

**Streaming (Plex/Subsonic/Jellyfin/Emby):**
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
| Shuffle mode | The next item from the active non-repeating shuffle cycle is pre-scheduled |

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
                            ├─► mixerNode ─► eqNode ─► mainMixerNode ─► output
crossfadePlayerNode ────────┘
(incoming, fading in)
```

**Streaming:**
Two independent `StreamingAudioPlayer` instances with their volumes controlled independently.

### Completion Handler Lifecycle

The crossfade must carefully manage `playbackGeneration` and delegate callbacks to prevent the outgoing track's completion from interfering:

- **Local files:** `startLocalCrossfade()` increments `playbackGeneration` to invalidate the outgoing `playerNode`'s `.dataPlayedBack` handler (registered in `loadLocalTrack`). The incoming player's `scheduleFile` uses `.dataPlayedBack` with the new generation, so track-end detection works correctly after crossfade completes.
- **Streaming:** `streamingPlayerDidFinishPlaying()` and `streamingPlayerDidChangeState()` check `isCrossfading` to ignore stale callbacks from the outgoing player. `completeStreamingCrossfade()` nils the outgoing player's delegate before stopping it to prevent synchronous callbacks.
- **Safety net:** `trackDidFinish()` has a `guard !isCrossfading` at the top to catch any stray completion callbacks.
- **Player state:** `crossfadePlayerIsActive` tracks which `AVAudioPlayerNode` is primary. It is toggled in `completeCrossfade()` and reset to `false` in `loadLocalTrack()`, `seek()`, `stopLocalOnly()`, and `cancelCrossfade()` to prevent desync with functions that always operate on `playerNode`.
- **Cancel:** `cancelCrossfade()` increments `playbackGeneration` to immediately invalidate both outgoing and incoming completion handlers.

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

When shuffle is enabled, both gapless and Sweet Fades use the same persisted shuffle cycle that natural EOF playback uses. They should not invent a separate random next-track decision.

### Cancel Conditions

The crossfade is cancelled if the user:
- Seeks to a new position
- Skips to next/previous track
- Selects a different track
- Stops playback

When cancelled, the outgoing track's volume is restored, the incoming track is stopped, `crossfadePlayerIsActive` is reset to `false`, and `playbackGeneration` is incremented.

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

## Output Device Selection

AudioEngine supports routing audio to specific output devices:

```swift
func setOutputDevice(_ deviceID: AudioDeviceID?) -> Bool
```

This uses CoreAudio's `AudioUnitSetProperty` with `kAudioOutputUnitProperty_CurrentDevice` on the engine's output node.

### Configuration Change Handling

When the output device changes (either programmatically or via system events like plugging in headphones), AVAudioEngine fires an `AVAudioEngineConfigurationChange` notification. AudioEngine observes this and:

1. Reconnects all nodes with the new output format (sample rate may differ between devices)
2. Re-schedules audio from the current position
3. Resumes playback automatically

This ensures seamless transitions between devices with different sample rates (e.g., 44.1kHz vs 48kHz).

### Cast Route-Change Safety

Cast sessions can trigger local CoreAudio configuration changes even when playback is controlled by Chromecast, Sonos, DLNA, AirPlay-style routes, Zoom, or Wi-Fi-backed outputs. Do not rebuild the local `AVAudioEngine` graph while cast routing is still active or while a cast session is still loaded.

`AudioEngine.handleAudioConfigChange(_:)` must defer graph rebuilds when either condition indicates cast activity:

- `CastManager.shared.activeSession != nil`
- `AudioEngine.isAnyCastingActive == true`

When a rebuild is deferred:

- Set `audioGraphRebuildDeferredForCast` and avoid calling `rebuildAudioGraph()`.
- Local play/load entry points must call `rebuildAudioGraphIfDeferredAfterCast()` before starting or scheduling playback.
- If the rebuild is still blocked, queue the pending user intent instead of dropping it. Replay that intent after the deferred rebuild succeeds.
- If a rebuild cannot restart playback after nodes were stopped/disconnected, move the engine to a non-playing state, stop time updates, and keep the rebuild deferred for retry.
- Local files loaded in `.stopped` state still need to be re-scheduled after rebuild, but must not auto-play.

This prevents `AVAudioEngineGraph::UpdateGraphAfterReconfig` exceptions during cast/room/output churn and keeps the next local playback action intact once routing stabilizes.

### Device Preference Persistence

The selected output device UID is saved to UserDefaults and restored on app launch. If the saved device is no longer available, the system default is used.

**Note:** Output device selection only affects local file playback. Streaming audio uses the system default output (AudioStreaming limitation).

## Waveform Side Path

The waveform window is not just a UI concern. It has a dedicated side path in the audio system with separate cost controls.

### Local File Waveforms

- Generated on demand by `WaveformCacheService`
- Read with `AVAudioFile` in chunked PCM passes
- Reduced to 4096 max-amplitude buckets
- Cached to `~/Library/Application Support/NullPlayer/WaveformCache/`

This keeps waveform generation off the hot playback path after the first decode.

### Streaming Waveforms

Streams do not remote-decode into a cache file. Instead:

1. `AudioEngine` / `StreamingAudioPlayer` publish 576-sample stereo waveform chunks via `.audioWaveform576DataUpdated`
2. `BaseWaveformView` consumes those chunks only for non-file audio tracks
3. `StreamingWaveformAccumulator` builds either:
   - a progressive full-track waveform when the stream has a known duration
   - a rolling live window when the stream has no reliable duration

### CPU Gating

Waveform generation is gated independently from FFT/spectrum analysis:

- `spectrumConsumers` controls spectrum/visualizer work
- `waveformConsumers` controls live waveform chunk generation

This is deliberate. A user may want:
- spectrum or ProjectM without a waveform window
- a waveform window without a visible spectrum window
- `vis_classic` exact mode, which needs waveform chunks even if generic FFT spectrum work is otherwise idle

If you touch the stream PCM callback path, preserve this separation.

## Historical Note

Prior to the AudioStreaming integration, Plex streaming used `AVPlayer` which outputs directly to hardware, bypassing `AVAudioEngine`. An attempt was made to bridge this using `MTAudioProcessingTap` and a ring buffer to route audio through the EQ, but this failed due to fundamental timing mismatches between the tap's push model and the engine's pull model.

The AudioStreaming library solves this by handling streaming entirely within `AVAudioEngine`, allowing proper integration with audio processing nodes.
