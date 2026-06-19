---
name: audio-system
description: Audio engine architecture, local/streaming pipelines, EQ, spectrum analysis, and playback flow. Use when working on audio playback, streaming, equalization, spectrum visualization, BPM detection, or ProjectM integration.
---

# Audio System Architecture

This guide describes NullPlayer's audio playback system, including local file playback, streaming audio, equalization, spectrum analysis, and waveform generation.

## Overview

NullPlayer uses two parallel audio pipelines to handle different content types:

| Content Type | Pipeline | EQ Support | Spectrum | Waveform |
|-------------|----------|------------|----------|----------|
| Local files (.mp3, .flac, etc.) | AVAudioEngine | Yes | Yes | Cached 4096-bucket snapshot |
| HTTP streaming (Plex/Subsonic/Jellyfin/Emby/radio) | AudioStreaming library | Yes | Yes | Live stream accumulator from 576-sample PCM chunks |

Both pipelines support the active EQ layout for the current UI mode and real-time spectrum visualization. Classic mode uses the legacy 10-band layout; modern mode uses a 21-band layout. EQ settings are automatically synchronized between them. Adaptive/dynamic spectrum modes share the same broad algorithm across local and streaming playback; accurate mode currently differs by pipeline (local uses BeSpec-style peak aggregation, streaming uses RMS power integration). The waveform window reuses the same playback sources: local files use cached snapshots, while streams start with live accumulation and may promote to a cached seekable snapshot when prerendering is available.

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
│  │crossfadeNode │─────────┼──► mixerNode ─► eqNode ────────────┐ │ │
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
│                    │ (mode EQ)    │                                 │
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

## Components Quick Reference

### AudioEngine (`Audio/AudioEngine.swift`)

Main audio controller managing:
- Playback state (play, pause, stop, seek)
- Playlist management
- Shuffle cycle management for non-repeating playback order
- Track loading (routes to appropriate pipeline)
- EQ settings (synced to both pipelines)
- Gapless playback (optional; local files and same-pipeline streaming)
- Volume normalization (optional, local files only)
- Sweet Fades crossfade (both pipelines)
- Reference Tuning pitch shift (both pipelines via a shared `PitchTuningController`; disabled while casting)
- Playback Speed tempo control (`0.25×...4.0×`; local files and HTTP streams; disabled while casting)
- Output device selection
- Delegate notifications for UI updates
- Separate consumer gating for FFT/spectrum work vs live waveform chunk generation

**Key Properties:**
```swift
private let engine = AVAudioEngine()
private let playerNode = AVAudioPlayerNode()
private let crossfadePlayerNode = AVAudioPlayerNode()
private let activeEQConfiguration: EQConfiguration
private let eqNode: AVAudioUnitEQ
private var streamingPlayer: StreamingAudioPlayer?
private var crossfadeStreamingPlayer: StreamingAudioPlayer?
var gaplessPlaybackEnabled: Bool
var volumeNormalizationEnabled: Bool
var sweetFadeEnabled: Bool
var sweetFadeDuration: TimeInterval
```

Shuffle-specific behavior in `AudioEngine`:
- Shuffle playback uses a persistent cycle order instead of choosing a fresh random index for each advance.
- A shuffled cycle visits each playlist index once before stopping or reshuffling for repeat.
- Explicit track selection while shuffle is enabled re-anchors the cycle on that selected track.
- Queue replacement, `playNow`, and empty-queue insertion all start playback from the shuffled `currentIndex`, not from index `0`.

### StreamingAudioPlayer (`Audio/StreamingAudioPlayer.swift`)

Wrapper around [AudioStreaming](https://github.com/dimitris-c/AudioStreaming) library:
- HTTP audio streaming with buffering
- Its own AVAudioUnitEQ (stays synchronized)
- Spectrum analysis via frame filtering
- Optional 576-sample waveform chunk generation for live waveform consumers
- State change callbacks

**Why separate EQ?** AVAudioNode instances can only be attached to one AVAudioEngine. Since AudioStreaming uses its own internal engine, we maintain a separate EQ node that stays synchronized with the main engine's EQ.

### Track Switch Race Condition Guard

When switching streaming tracks, avoid race conditions with an `isLoadingNewStreamingTrack` flag:

```swift
private var isLoadingNewStreamingTrack: Bool = false

private func loadStreamingTrack(_ track: Track) {
    isLoadingNewStreamingTrack = true
    
    // DON'T call stop() before play() - AudioStreaming handles this internally
    streamingPlayer?.play(url: track.url)
    state = .playing
    
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
        self?.isLoadingNewStreamingTrack = false
    }
}

func streamingPlayerDidFinishPlaying() {
    guard !isLoadingNewStreamingTrack else { return }
    trackDidFinish()
}
```

### NAS Responsiveness for Local Track Switches

See `skills/local-library/SKILL.md` — NAS Responsiveness section.

## Equalizer

### Configuration

Classic mode uses the legacy 10-band configuration; modern mode uses a 21-band configuration derived from `EQConfiguration.modern21`. Both pipelines build their `AVAudioUnitEQ` from the same active layout at launch.

### Classic 10-Band Configuration

| Band | Frequency | Filter Type | Bandwidth |
|------|-----------|-------------|-----------|
| 0 | 60 Hz | Low Shelf | 1.0 octave |
| 1 | 170 Hz | Parametric | 1.75 octaves |
| 2 | 310 Hz | Parametric | 1.75 octaves |
| 3 | 600 Hz | Parametric | 1.75 octaves |
| 4 | 1 kHz | Parametric | 1.75 octaves |
| 5 | 3 kHz | Parametric | 1.75 octaves |
| 6 | 6 kHz | Parametric | 1.75 octaves |
| 7 | 12 kHz | Parametric | 1.75 octaves |
| 8 | 14 kHz | Parametric | 1.75 octaves |
| 9 | 16 kHz | High Shelf | 1.0 octave |

### Modern 21-Band Configuration

Frequencies: `31.5, 45, 63, 90, 125, 180, 250, 355, 500, 710, 1000, 1400, 2000, 2800, 4000, 5600, 8000, 11200, 14000, 16000, 20000`

- First band: `lowShelf`
- Last band: `highShelf`
- Middle bands: `parametric`
- Parametric bandwidth: `1.0` octave

- Per-band gain: **-12 dB to +12 dB**
- Preamp (global gain): **-12 dB to +12 dB**
- **Disabled by default** to preserve original audio quality
- Saved EQ arrays are remapped between 10-band and 21-band layouts when restoring across classic/modern mode switches

### Modern EQ UI Controls

| Control | Behavior |
|---------|----------|
| ON toggle | Enable/disable EQ |
| AUTO toggle | Apply genre-based preset for current track; auto-enables EQ if off |
| FLAT ROCK POP ELEC HIP JAZZ CLSC buttons | Apply preset and highlight active button; auto-enables EQ if off; clicking active button deactivates (applies flat, no highlight) |
| Drag a fader | Adjust that EQ band; clears active preset highlight |
| Double-click a fader | Reset that band only to 0 dB (not all bands) |
| Integrated `PRE` control | Adjust global preamp from `-12...+12 dB`; double-click resets to `0 dB` |

Modern EQ specifics:
- 21 compact faders across the full slider strip
- Integrated glowing `PRE` control in the graph/header strip instead of a dedicated left preamp slider
- All 21 frequency labels are shown in-window using compact formatting (`1K`, `1.4K`, `2K`, etc.)
- Graph background uses per-band mini tracks so it visually echoes the fader lanes instead of a single connected fill

### EQ Synchronization

When EQ settings change, both pipelines are updated:

```swift
func setEQBand(_ band: Int, gain: Float) {
    let clampedGain = max(-12, min(12, gain))
    eqNode.bands[band].gain = clampedGain      // Local pipeline
    streamingPlayer?.setEQBand(band, gain: clampedGain)  // Streaming pipeline
}
```

## Reference Tuning and Playback Speed

Reference Tuning shifts playback pitch by a precise cents offset to retune content from one reference frequency to another (e.g. A=440 → A=432). It is implemented as a shared `PitchTuningController` (`Audio/PitchTuningController.swift`) that owns the local `AVAudioUnitTimePitch` node and creates one configured streaming pitch node per AudioStreaming player. This keeps the primary and Sweet Fades crossfade streaming graphs independent while driving all nodes from the same state.

Playback Speed is also owned by `PitchTuningController`, but it is a tempo/time-stretch control, not a pitch shift. The supported user range is `0.25×...4.0×`; `1.0×` is normal speed. Pitch is preserved while tempo changes.

### Graph placement

Local graph: `playerNode + crossfadePlayerNode → mixerNode → localPitchNode → eqNode → mainMixerNode`. Placing the pitch node **after** the mixer means a single node handles both the primary and crossfade players, and the spectrum tap on `mixerNode` keeps capturing pre-pitch (source) frequencies — the analyzer shows the source content's spectrum, not the shifted output. This is a deliberate trade-off; moving the tap onto `localPitchNode` would invert it.

Streaming graph: each `StreamingAudioPlayer` receives its own node from `PitchTuningController.makeStreamingPitchNode()` and attaches it via `AudioStreaming.AudioPlayer.attach(node:)` after the EQ node. These streaming pitch nodes only carry Reference Tuning cents: they always keep `node.rate = 1.0`. Streaming tempo is applied through AudioStreaming's own private `rateNode` via `StreamingAudioPlayer.rate` / `AudioPlayer.rate`. This avoids double-applying rate when Reference Tuning and Playback Speed are used together.

When `AudioEngine.setPlaybackSpeed(_:)` changes the rate, it updates the controller, persists the preference, applies the rate to the active primary streaming player, and applies it to the crossfade streaming player if one exists. Newly-created streaming players must immediately inherit `tuningController.rate`.

### Math and clamp

Cents offset = `1200 · log2(target / source)` (e.g. 440 → 432 ≈ −31.766 cents). `AVAudioUnitTimePitch.pitch` is in cents, ±2400. The controller clamps `appliedCents` to that range; the Custom… dialog validates input at entry time and rejects out-of-range frequencies rather than silently clamping.

Playback Speed clamps via `PitchTuningController.minRate` / `maxRate` (`0.25...4.0`). Local file time display is wall-clock based, so local `currentTime` must multiply elapsed wall time by `playbackSpeed`; streaming time comes from AudioStreaming's own player progress.

### Persistence and overrides

UserDefaults keys (mirrors EQ/volume normalization pattern):

- `referenceTuningEnabled: Bool`
- `referenceTuningSourceHz: Double` (default 440)
- `referenceTuningTargetHz: Double` (default 432)
- `playbackSpeedRate: Float` (default 1.0; `UserDefaults.float(forKey:) == 0` means missing/default)

CLI flags (`--tuning`, `--tuning-source`, `--tuning-offset-cents`) provide session-only overrides — they do not write back to UserDefaults, matching `--volume` and `--eq`.

### Casting

Casting paths (Sonos / Chromecast / DLNA) hand the remote renderer a stream URL with no local AVFoundation graph to insert into, so Reference Tuning and Playback Speed are intentionally unavailable while casting. Their menus grey out with a "Not available while casting" tooltip; `engine.isAnyCastingActive` is the gate. The persisted speed remains stored and resumes for local/HTTP playback after casting ends.

## Spectrum Analyzer

Both pipelines feed spectrum data to the UI for visualization.

### Processing Pipeline

1. **Sample extraction** - Get float samples from PCM buffer (mono-mix stereo)
2. **Windowing** - Apply Hann window to reduce spectral leakage
3. **FFT** - 2048-point DFT using Accelerate framework
4. **Magnitude calculation** - Convert complex output to magnitudes
5. **Band aggregation** - Accurate mode is pipeline-specific; adaptive/dynamic modes interpolate at band center frequencies
6. **Frequency weighting** - Apply compensation curve (adaptive/dynamic modes)
7. **Normalization** - Scale based on selected mode
8. **Smoothing** - Fast attack, slow decay for visual appeal

### Normalization Modes

| Mode | Gain Control | Preserves Balance | Best For |
|------|--------------|-------------------|----------|
| **Accurate** | Fixed dB mapping | Yes (true levels) | Technical analysis |
| **Adaptive** | Global adaptive | Yes (scaled together) | General listening |
| **Dynamic** | Per-region (bass/mid/treble) | No (independent) | Visual appeal |

### Shared Processing And Accurate-Mode Difference

Both local and streaming use a **2048-point FFT** and 75 logarithmic output bands:
- FFT size: 2048 samples
- Bin width: ~21.5 Hz at 44.1kHz
- Latency: ~46ms

Accurate mode is not identical across pipelines:
- **Local `AudioEngine`:** BeSpec-style peak aggregation per band, calibrated by `2 / sqrt(fftSize)`, mapped from `-20...0 dB`.
- **Streaming `StreamingAudioPlayer`:** RMS power integration per band with bandwidth compensation, mapped from `0...40 dB`.

Adaptive and dynamic modes use the same algorithm shape in both pipelines: center-bin interpolation, bandwidth scaling, frequency weighting, adaptive normalization, and fast-attack/slow-decay smoothing.

### Volume-Independent Visualizations

Spectrum analyzer and ProjectM show audio levels independently of user volume:

**Local:** Tap on `mixerNode` before volume control (mainMixerNode.outputVolume)

**Streaming:** AudioStreaming's `frameFiltering` captures after volume, so `processAudioBuffer()` compensates by dividing samples by current volume (capped at 20x).

## Waveform Window Pipeline

The waveform window shares the audio engine but intentionally does not share the same demand gate as FFT/spectrum analysis.

### Local Files

- `WaveformCacheService` opens the active file with `AVAudioFile`
- Decodes PCM in chunks and stores max absolute amplitude into 4096 buckets
- Persists snapshots under `~/Library/Application Support/NullPlayer/WaveformCache/`
- Cache key is based on canonical path + file size + modification date

### Streams

- Live path:
  - `AudioEngine` and `StreamingAudioPlayer` emit `.audioWaveform576DataUpdated`
  - `BaseWaveformView` listens only for non-file audio tracks
  - `StreamingWaveformAccumulator` builds progressive seekable waveforms for timed streams, and rolling non-seekable waveforms for live/radio streams
- Prerender path (service-backed tracks with stable identity + known duration):
  - `WaveformCacheService` can prerender remote waveforms and persist them as seekable snapshots
  - Service cache key: `WaveformCacheService.serviceCacheKey(serviceIdentity:duration:bitrate:sampleRate:)`
  - Live placeholders or unknown-duration streams skip prerender and stay on live accumulation
  - Generation tries `AVAssetReader` first, then falls back to URL download + local decode
  - Once a seekable service prerender is ready, `BaseWaveformView` freezes on that snapshot and ignores subsequent live 576-sample chunks for the same track

### Consumer Gating

Do not assume spectrum demand implies waveform demand.

- `AudioEngine.spectrumConsumers` controls FFT/spectrum work
- `AudioEngine.waveformConsumers` controls 576-sample waveform chunk generation
- `AudioEngine.stereoConsumers` controls separate L/R downsampled PCM (`.audioStereoPCMDataUpdated`)
- `AudioEngine.magnitudesConsumers` controls raw linear FFT magnitudes (`.audioFFTMagnitudesUpdated`)
- The waveform window registers a waveform consumer only while visible on a non-file audio track
- `SpectrumAnalyzerView` registers a waveform consumer only while `qualityMode == .visClassicExact` and the analyzer is actively rendering
- The Audio Analysis window registers per-pane consumers (see audio-analysis-window skill); a closed window deregisters all of them

This split matters for CPU usage: hidden waveform windows and inactive `vis_classic` views should not keep paying the live waveform callback cost.

### Stereo PCM and FFT-magnitudes paths (Audio Analysis)

Two analysis-only paths exist alongside the mono PCM/spectrum/waveform feeds, each gated by its own
consumer set so it costs nothing when unused:

- **`.audioStereoPCMDataUpdated`** — `["left": [Float](512), "right": [Float](512), "sampleRate": Double]`.
  Separate downsampled L/R buffers (mono streams are duplicated into both). Gated by `stereoNeeded`.
- **`.audioFFTMagnitudesUpdated`** — `["magnitudes": [Float](fftSize/2 linear), "sampleRate": Double, "fftSize": Int]`.
  Raw **linear** FFT magnitudes (not dB, not the 75-band normalized spectrum). Posted inside the
  `spectrumNeeded` FFT block, additionally gated by `magnitudesNeeded`. Consumers of this path must also
  hold a spectrum consumer so the FFT actually runs.

**Both paths are wired in `AudioEngine` (local) and `StreamingAudioPlayer` (streaming) and emit the
identical payload shape.** A consumer listening to only one path silently misses the other engine — the
`stereoNeeded`/`magnitudesNeeded` mirror flags bridge engine → streaming the same way `spectrumNeeded` does.

## BPM Detection

Real-time BPM detection using **aubio** library (`libaubio.5.dylib`):

1. Mono-mixed PCM samples fed in 512-sample hops
2. aubio's `aubio_tempo_t` performs onset detection + beat tracking
3. Median filter over last 10 readings for stability
4. Posts `.bpmUpdated` notification (throttled to 1/second)
5. Displays only when confidence >= 0.05

**Integration:**
- Both `AudioEngine` and `StreamingAudioPlayer` own a `BPMDetector`
- Fed from same buffer as spectrum analysis (before windowing)
- Display reset on track change

**Key Files:**
- `Audio/BPMDetector.swift`
- `Audio/AudioEngine.swift`
- `Audio/StreamingAudioPlayer.swift`

## ProjectM Visualization

### Low-Latency PCM Delivery

PCM data is pushed directly via `NotificationCenter`:

```swift
NotificationCenter.default.post(
    name: .audioPCMDataUpdated,
    object: self,
    userInfo: ["pcm": pcmSamples, "sampleRate": sampleRate]
)
```

Eliminates polling latency - total latency now **15-20ms** (down from 60-80ms).

### Idle Mode

When audio isn't playing:
- Beat sensitivity reduced from 1.0 to 0.2
- Visualization continues but responds less dramatically
- Auto-returns to normal when music starts

### Fullscreen & Controls

- Press **F** to toggle fullscreen
- Press **Escape** to exit
- Arrow keys: Next/Previous preset
- **R**: Random preset
- **L**: Toggle preset lock

## File Support

### Local Playback (AVAudioEngine)
MP3, M4A, AAC, WAV, AIFF, FLAC, ALAC, OGG

Route-change graph rebuilds must catch Objective-C exceptions from `AVAudioEngine.connect(_:to:format:)` via the `ObjCExceptionCatcher` bridge. If reconnect raises `AVAudioEngineGraph::UpdateGraphAfterReconfig`, defer the rebuild and retry through the existing cast/route-stabilization path instead of relying on Swift `do/catch`.

### Streaming Playback (AudioStreaming)
HTTP/HTTPS URLs with MP3, AAC, Ogg Vorbis

**M4A Limitation:** Only "fast-start" optimized M4A files supported. Non-optimized M4A (moov atom at end) will fail. Fix with: `ffmpeg -i input.m4a -movflags +faststart output.m4a`

## Playback Reporters

### Plex
- Timeline updates every 10 seconds
- Scrobble at 90% or end (min 30 seconds)
- Supports both audio (`PlexPlaybackReporter`) and video (`PlexVideoPlaybackReporter`)

### Subsonic/Navidrome
- "Now playing" on track start
- Scrobble at 50% or 4 minutes, whichever comes first

### Jellyfin
- Session API for "now playing"
- Progress updates with ticks (1 tick = 10,000 ns)
- Same scrobbling rules as Subsonic
- Supports both audio (`JellyfinPlaybackReporter`) and video (`JellyfinVideoPlaybackReporter`)

### Emby
- Session API for "now playing" (same structure as Jellyfin)
- Progress updates with ticks (1 tick = 10,000 ns)
- Scrobble at 50% or 4 minutes, whichever comes first
- Supports both audio (`EmbyPlaybackReporter`) and video (`EmbyVideoPlaybackReporter`)

## Dependencies

| Library | Purpose | Version |
|---------|---------|---------|
| AVFoundation | Local file playback, EQ | System |
| Accelerate | FFT for spectrum analysis | System |
| CoreAudio | Output device management | System |
| [AudioStreaming](https://github.com/dimitris-c/AudioStreaming) | HTTP streaming | 1.4.0+ |
| [aubio](https://aubio.org) | BPM/tempo detection | 0.4.9+ |

## Additional Documentation

For detailed information, see:
- [audio-pipelines.md](audio-pipelines.md) - Gapless playback, Sweet Fades, volume normalization
- [playback-flows.md](playback-flows.md) - Plex Radio/Mix, Subsonic streaming, output device selection
- [spectrum-algorithms.md](spectrum-algorithms.md) - Complete spectrum analysis algorithms for all three modes

## Key Files

| Area | Files |
|------|-------|
| Core | `Audio/AudioEngine.swift`, `Audio/StreamingAudioPlayer.swift` |
| EQ | EQ node configuration in AudioEngine, StreamingAudioPlayer |
| Spectrum | `Audio/AudioEngine.swift` (FFT processing) |
| BPM | `Audio/BPMDetector.swift` |
| Output devices | `Audio/AudioOutputManager.swift` |
| Track URL resolution | `Audio/StreamingTrackResolver.swift` |
| File validation | `Audio/AudioFileValidator.swift` |
| ProjectM | `Visualization/ProjectMWrapper.swift`, `Windows/ProjectM/` |
| Reporters | `Plex/PlexPlaybackReporter.swift`, `Plex/PlexVideoPlaybackReporter.swift`, `Subsonic/SubsonicPlaybackReporter.swift`, `Jellyfin/JellyfinPlaybackReporter.swift`, `Jellyfin/JellyfinVideoPlaybackReporter.swift`, `Emby/EmbyPlaybackReporter.swift`, `Emby/EmbyVideoPlaybackReporter.swift` |
