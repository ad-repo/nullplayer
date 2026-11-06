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

Local playback completion must use `scheduleFile(_:at:completionCallbackType:completionHandler:)` with `.dataPlayedBack`. Do not use the deprecated three-parameter form; its completion handler fires before audio finishes playing.

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
| Next track is a video or an unresolved placeholder | Not pre-scheduled; the end-of-track advance routes it (`canHandOff`) |
| Repeat single track mode | Handled separately (gapless not needed) |
| Shuffle mode | The next item from the active non-repeating shuffle cycle is pre-scheduled |

### Settings Persistence

The gapless setting is saved to UserDefaults and restored on app launch.

## Sweet Fades (Crossfade)

When enabled via **Playback ▸ Sweet Fades (Crossfade) ▸ Enabled**, tracks smoothly blend into each other with overlapping playback and volume fading. The submenu is always shown; Fade Duration and Fade Out Only grey out while Enabled is off.

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
- **Player state:** `crossfadePlayerIsActive` tracks which `AVAudioPlayerNode` is primary. It is toggled in `completeCrossfade()`, which also leaves the outgoing node at volume 0. `seek()` and the cue-neighbour reload in `loadLocalTrack()` always schedule on `playerNode`, so they hand playback back through `makePlayerNodePrimary()`, which stops `crossfadePlayerNode` **and restores `playerNode` to unity**. Without the volume restore, every seek after an odd number of completed fades played silently with the clock running (M72).
- **Files:** the incoming file goes in `crossfadeAudioFile` for the whole fade; `audioFile` stays the outgoing track's until `completeCrossfade()` swaps it, so a cancel keeps playing the file `currentTrack` and the clock describe.
- **Cancel:** `cancelCrossfade()` increments `playbackGeneration` to immediately invalidate both outgoing and incoming completion handlers. It stops the incoming node and leaves `crossfadePlayerIsActive` alone: the outgoing node keeps playing and stays primary.
- **Pause:** `pauseLocalOnly()` cancels a fade in flight. It pauses only the primary player, so without the cancel the incoming track kept playing and its timer completed the fade while paused.

### Fade Duration

Configurable via **Playback ▸ Sweet Fades ▸ Fade Duration** when Sweet Fades is enabled:
- 1s, 2s, 3s, **5s (default)**, 7s, 10s

### Fade Out Only

**Sweet Fades ▸ Fade Out Only** (`sweetFadeOutOnly`, UserDefaults) replaces the overlap with a plain
fade-out (M70): the track fades over its last Fade Duration seconds, and the normal end-of-track
advance starts the next one at full volume from 0:00. No second player runs and `startCrossfade()`
is never called. Asked for because a two-sided crossfade fades the next track's intro in, so a song
that opens on a kick loses it; an overlap with the next track at full volume was tried first and
sounded jarring against the still-fading track.

The fade is stateless: `refreshEndFade(at:)` sets `OutputFades.endFade` from
`OutputFades.endFadeCurve(remaining:over:)` — unity until the last Fade Duration seconds, then the
crossfade's equal-power `cos` curve down to 0 at the end. The clock tick (0.1 s, `startTimeUpdates`)
calls it, and so does `seek(to:)`, because the tick does not run while paused and a paused seek
would otherwise resume on the old position's gain. Starting the clock calls it too: a restart of
the same track (repeat one, Play after Stop) would otherwise play its first 0.1 s on the end's
near-silent gain. The `currentTrack` setter calls
`OutputFades.trackDidChange()` on a different track, so the next one never starts on the last
tick's gain. It is an output-stage gain, stacked with the pause/resume fade (*Fade on
Pause/Resume*, below).

The engine asks `crossfadesTracks` or `fadesOutTrackEnds` for the mode, never the two settings
inline. Gapless still asks `sweetFadeEnabled`, so it stays off in Fade Out Only too: under gapless
the next track's audio would start before the `currentTrack` change that clears the end fade.

Measured 2026-11-03 on a Plex stream at 2 s: the gain left unity at 1.92 s remaining and the player
reported the track finished 1.90 s of wall clock later; the next track started 7 ms after that.

### Constraints

| Scenario | Behavior |
|----------|----------|
| Casting active | Crossfade disabled - playback is remote |
| Mixed sources (local→streaming) | Crossfade skipped for that transition |
| Next track is a video or an unresolved placeholder | Crossfade skipped; the end-of-track advance routes it (`canHandOff`) |
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

When cancelled, the outgoing track's volume is restored, the incoming track is stopped, `crossfadePlayerIsActive` is left as it was (the outgoing node stays primary), and `playbackGeneration` is incremented. Pausing also cancels a fade (see *Completion Handler Lifecycle*).

### Interaction with Gapless Playback

Sweet Fades takes precedence over gapless playback:
- When Sweet Fades is enabled, gapless pre-scheduling is disabled
- When Sweet Fades is disabled, gapless resumes (if enabled)

### Settings Persistence

`sweetFadeEnabled`, `sweetFadeDuration`, `sweetFadeOutOnly` and `pauseFadeEnabled` are saved to UserDefaults and restored on app launch.

## Fade on Pause/Resume

**Playback ▸ Fade on Pause/Resume** (`pauseFadeEnabled`, UserDefaults, on by default) ramps a user
pause and its resume over `TransportFade.duration` (0.3 s; 80 ms only removed the click and was not
heard as a fade) instead of cutting mid-waveform (M71). `TransportFade` owns the ramp, and
`OutputFades` (both in `Audio/OutputFades.swift`) stacks it with Fade Out Only's end fade. The
engine applies `OutputFades.gain` on the output stage, after the visualization taps, so the meters
do not dip: `mainMixerNode.outputVolume` for local playback (inside `applyNormalizationGain`) and
`StreamingAudioPlayer.fadeGain` (the stream's unity `balanceNode`) for streams, both written by
`applyOutputFades()`.

- **`state` changes at once.** `pause()` calls `pauseLocalOnly(fadeOut: true)`, which saves the
  position and sets `.paused` immediately — about twenty callers (Now Playing, the CLI, sleep) read
  it straight after — and pauses the player nodes only when the ramp ends.
- **The local clock is manual,** so the fade's tail is added to the saved position; otherwise each
  faded pause would put the clock 0.3 s further behind the audio.
- **A resume replaces the ramp,** so a pause still fading never lands, and `play()` ramps up from
  wherever the gain is (`fadeInResume`, shared by the local and streaming branches). Only a resume
  from `.paused` starts from silence; a start from `.stopped` plays at full level. A seek, stop or
  track change bumps `playbackGeneration`, and the deferred pause is dropped; a change to a
  different track also resets the gain, so the new track does not dip with the old pause.
- **A faded pause stays at gain 0** until the resume ramps it up; `resetLocalCrossfadeStateForDirectPlayback()`
  (Stop, every track load, a load error) resets it to 1, since a streaming load starts its player
  directly, with no ramp. Restoring it when the ramp ended played the players' tail at full level —
  their pause lands a render cycle or more later, a stream's later still — as a spike (#699).
- `pauseLocalOnly()` without `fadeOut` (casting takeover) pauses at once.
- Next, Previous and Stop do not fade: that would hold the command back, which complicates rapid
  clicks and casting.

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

`AVAudioEngine.connect(_:to:format:)` can raise an Objective-C `NSException` from `AVAudioEngineGraph::UpdateGraphAfterReconfig` during route churn. Swift `do/catch` does not catch this. All route-change graph reconnect work must go through the `ObjCExceptionCatcher` bridge (`NPObjCExceptionCatch`) and treat a caught exception as a failed rebuild:

- Log the exception reason.
- Set `audioGraphRebuildDeferredForCast = true`.
- Move local playback to a non-playing state if nodes were already stopped/disconnected.
- Schedule the normal deferred rebuild retry path instead of allowing the process to abort.

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
