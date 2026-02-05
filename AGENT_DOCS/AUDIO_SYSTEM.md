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
3. **FFT** - 2048-point DFT using Accelerate framework (vDSP) (~46ms at 44.1kHz)
4. **Magnitude calculation** - Convert complex output to magnitudes
5. **Power integration** - Sum power (magnitude²) of FFT bins within each logarithmic band. For bands with few bins, interpolate and scale by bandwidth.
6. **Frequency weighting** - Apply compensation curve in adaptive/dynamic modes (skipped in accurate mode)
7. **Normalization** - Scale based on selected mode (accurate/adaptive/dynamic)
8. **Smoothing** - Fast attack, slow decay for visual appeal

**Note:** Both local and streaming playback use identical 2048-pt FFT processing for consistent visualization across all audio sources.

### Pink Noise Handling

Pink noise has equal energy per octave (not per Hz). Different normalization modes handle this differently:

**All modes apply bandwidth scaling** to compensate for pink noise's 1/f slope:
- Formula: `pow(bandwidthHz / refBandwidth, exponent)` where exponent varies by mode
- This makes pink noise appear relatively flat across all modes
- Accurate mode uses `refBandwidth=20.0` and `exponent=0.6` for slightly steeper high-frequency boost
- Adaptive/Dynamic modes use `refBandwidth=100.0` and `exponent=0.5` (square root)

**Adaptive/Dynamic modes only:**
- Apply additional frequency weighting to reduce sub-bass dominance

### Frequency Weighting (Adaptive/Dynamic modes only)

In **Adaptive** and **Dynamic** modes, an additional frequency weighting curve is applied on top of pink noise compensation to make music look more visually appealing:

| Frequency Range | Weight | Reason |
|-----------------|--------|--------|
| < 40 Hz (sub-bass) | 0.70 | Light reduction - sub-bass energy is usually felt, not seen |
| 40-100 Hz (bass) | 0.85 | Very light reduction - let bass punch through |
| 100-300 Hz (low-mid) | 0.92 | Minimal reduction |
| > 300 Hz | 1.00 | Full level |

This weighting is **not applied** in Accurate mode to preserve true signal levels.

### Normalization Modes

The spectrum analyzer supports three normalization modes (configurable via right-click menu). Each mode processes FFT data differently to achieve different visualization goals.

---

#### Accurate Mode - Complete Algorithm

**Goal:** Display true signal levels with a flat response for pink noise, suitable for technical analysis.

**Step 1: FFT Bin Range Calculation**
For each of the 75 logarithmic bands:
```
startFreq = 20 × (20000/20)^(band/75)      // Band's lower frequency edge
endFreq = 20 × (20000/20)^((band+1)/75)    // Band's upper frequency edge
binWidth = sampleRate / fftSize             // Hz per FFT bin (e.g., 44100/2048 = 21.5 Hz)
startBin = max(1, floor(startFreq / binWidth))
endBin = max(startBin, min(fftSize/2 - 1, floor(endFreq / binWidth)))
```

**Step 2: Power Integration (Sum of Squared Magnitudes)**
Sum the squared magnitude of all FFT bins within the band:
```
totalPower = Σ (magnitude[bin]²)  for bin in startBin...endBin
binCount = endBin - startBin + 1
```

**Step 3: RMS Magnitude Calculation**
Calculate Root Mean Square (average energy density):
```
avgPower = totalPower / binCount
rmsMag = sqrt(avgPower)
```

**Step 4: Bandwidth Compensation (Pink Noise Flattening)**
Apply scaling to compensate for pink noise's 1/f energy distribution:
```
bandwidthHz = endFreq - startFreq
refBandwidth = 20.0                           // Reference bandwidth (Hz)
bandwidthScale = pow(bandwidthHz / refBandwidth, 0.6)
scaledMag = rmsMag × bandwidthScale
```
- The `0.6` exponent provides steeper high-frequency boost than sqrt (0.5)
- `refBandwidth = 20.0` is low, providing more boost to wide high-frequency bands
- Result: Pink noise appears relatively flat across the display

**Step 5: Decibel Conversion**
Convert linear magnitude to decibels:
```
dB = 20.0 × log₁₀(max(scaledMag, 1e-10))
```

**Step 6: Dynamic Range Mapping**
Map dB range to 0.0-1.0 display range:
```
// Both local and streaming use identical parameters (2048-pt FFT):
ceiling = 40.0 dB    // Maps to 100% (top of display)
floor = 0.0 dB       // Maps to 0% (bottom of display)

normalized = (dB - floor) / (ceiling - floor)
output = clamp(normalized, 0.0, 1.0)
```

**Step 7: Final Smoothing (All Modes)**
Applied on main thread for visual continuity:
```
if newValue > currentValue:
    spectrumData[band] = newValue              // Instant attack
else:
    spectrumData[band] = current × 0.90 + new × 0.10  // 90% decay smoothing
```

**Characteristics:**
- No adaptive gain control - quiet signals appear quiet, loud appear loud
- True representation of frequency content
- 40dB dynamic range display (ceiling - floor)
- Pink noise test signal appears flat
- Best for: Technical analysis, checking frequency balance, mixing reference

---

#### Adaptive Mode - Complete Algorithm

**Goal:** Automatically adjust gain based on overall signal level while preserving relative frequency balance.

**Step 1: Center Frequency Interpolation**
For each of the 75 logarithmic bands, sample a single interpolated FFT bin:
```
startFreq = 20 × (20000/20)^(band/75)
endFreq = 20 × (20000/20)^((band+1)/75)
centerFreq = sqrt(startFreq × endFreq)        // Geometric mean
exactBin = centerFreq / binWidth
lowerBin = floor(exactBin)
upperBin = min(lowerBin + 1, fftSize/2 - 1)
fraction = exactBin - lowerBin
interpMag = magnitude[lowerBin] × (1 - fraction) + magnitude[upperBin] × fraction
```

**Step 2: Pre-computed Bandwidth Scaling**
Apply pre-computed scale factors for pink noise compensation:
```
// Pre-computed at startup for each band:
ratio = (20000/20)^(1/75)                     // ~1.096 frequency ratio per band
refBandwidth = 1000.0 × (ratio - 1.0)         // Reference bandwidth at 1kHz
bandwidth = endFreq - startFreq
bandwidthScale[band] = sqrt(bandwidth / refBandwidth)

// Applied per-frame:
bandMagnitude = interpMag × bandwidthScale[band]
```

**Step 3: Pre-computed Frequency Weighting**
Apply frequency-dependent weighting to reduce sub-bass dominance:
```
// Pre-computed weights by frequency:
freq < 40 Hz:    weight = 0.70   // Sub-bass: 30% reduction
freq < 100 Hz:   weight = 0.85   // Bass: 15% reduction
freq < 300 Hz:   weight = 0.92   // Low-mid: 8% reduction
freq >= 300 Hz:  weight = 1.00   // Full level

newSpectrum[band] = bandMagnitude × frequencyWeight[band]
```

**Step 4: Global Peak Tracking**
Find maximum value across all 75 bands:
```
globalPeak = max(newSpectrum[0..74])
```

**Step 5: Adaptive Peak Update (Slow Rise, Slower Decay)**
Update the tracked peak level with asymmetric smoothing:
```
if globalPeak > spectrumGlobalPeak:
    // Rising: 8% of new value (fast attack)
    spectrumGlobalPeak = spectrumGlobalPeak × 0.92 + globalPeak × 0.08
else:
    // Falling: 0.5% of new value (very slow decay)
    spectrumGlobalPeak = spectrumGlobalPeak × 0.995 + globalPeak × 0.005
```

**Step 6: Reference Level Calculation**
Compute the normalization reference with anti-pulsing smoothing:
```
// Target: weighted average favoring tracked peak over current peak
targetReferenceLevel = max(spectrumGlobalPeak × 0.5, globalPeak × 0.3)

// Smooth reference to prevent jumpy normalization:
spectrumGlobalReferenceLevel = spectrumGlobalReferenceLevel × 0.85 + targetReferenceLevel × 0.15
referenceLevel = max(spectrumGlobalReferenceLevel, 0.001)  // Prevent divide-by-zero
```

**Step 7: Global Normalization with Square Root Curve**
Normalize all bands using the global reference:
```
for band in 0..<75:
    normalized = min(1.0, newSpectrum[band] / referenceLevel)
    newSpectrum[band] = pow(normalized, 0.5)  // Square root for better dynamics
```
- Square root curve expands quiet signals, compresses loud signals
- All bands scale together, preserving relative frequency balance

**Step 8: Final Smoothing (Same as Accurate)**
```
if newValue > currentValue:
    spectrumData[band] = newValue
else:
    spectrumData[band] = current × 0.90 + new × 0.10
```

**Characteristics:**
- Single global gain control - all frequencies scale together
- Automatic level adjustment over time
- Preserves relative frequency balance (bass-heavy content stays bass-heavy)
- Square root compression provides visual dynamics
- Best for: General listening, music that varies in loudness

---

#### Dynamic Mode - Complete Algorithm

**Goal:** Maximize visual activity by normalizing each frequency region independently.

**Steps 1-3: Same as Adaptive Mode**
- Center frequency interpolation
- Bandwidth scaling
- Frequency weighting

**Step 4: Region Definition**
Split the 75 bands into three independent regions:
```
Bass region:   bands 0-24   (~20 Hz to ~300 Hz)
Mid region:    bands 25-49  (~300 Hz to ~3.4 kHz)
Treble region: bands 50-74  (~3.4 kHz to ~20 kHz)
```

**Step 5: Per-Region Peak Tracking**
For each of the 3 regions:
```
regionPeak = max(newSpectrum[start..end])  // Find peak in this region

if regionPeak > spectrumRegionPeaks[regionIndex]:
    // Rising: 8% blend (fast attack)
    spectrumRegionPeaks[regionIndex] = old × 0.92 + regionPeak × 0.08
else:
    // Falling: 0.5% blend (slow decay)
    spectrumRegionPeaks[regionIndex] = old × 0.995 + regionPeak × 0.005
```

**Step 6: Per-Region Reference Level**
Calculate independent reference for each region:
```
targetReferenceLevel = max(spectrumRegionPeaks[regionIndex] × 0.5, regionPeak × 0.3)
spectrumRegionReferenceLevels[regionIndex] = old × 0.85 + target × 0.15
referenceLevel = max(spectrumRegionReferenceLevels[regionIndex], 0.001)
```

**Step 7: Per-Region Normalization**
Normalize each region independently:
```
for band in regionStart..<regionEnd:
    normalized = min(1.0, newSpectrum[band] / referenceLevel)
    newSpectrum[band] = pow(normalized, 0.5)  // Square root curve
```

**Step 8: Final Smoothing (Same as other modes)**
```
if newValue > currentValue:
    spectrumData[band] = newValue
else:
    spectrumData[band] = current × 0.90 + new × 0.10
```

**Characteristics:**
- Three independent gain controls (bass, mid, treble)
- Each region fills its display area regardless of actual energy
- Does NOT preserve relative frequency balance
- Maximum visual activity for all content
- Best for: Visual appeal, live performances, content with sparse frequency content

---

### Algorithm Comparison Summary

| Aspect | Accurate | Adaptive | Dynamic |
|--------|----------|----------|---------|
| **Magnitude source** | RMS of all bins in band | Single interpolated bin | Single interpolated bin |
| **Bandwidth scaling** | `pow(bw/20, 0.6)` | `sqrt(bw/refBw)` | `sqrt(bw/refBw)` |
| **Frequency weighting** | None | Sub-bass reduction | Sub-bass reduction |
| **Gain control** | Fixed dB mapping | Global adaptive | Per-region adaptive |
| **Peak tracking** | None | Single global peak | 3 regional peaks |
| **Output curve** | Linear (dB-mapped) | Square root | Square root |
| **Preserves balance** | Yes (true levels) | Yes (scaled together) | No (independent) |
| **Pink noise response** | Flat | Flat | Flat per-region |

### State Variables

**Adaptive Mode:**
- `spectrumGlobalPeak: Float` - Tracked global peak level
- `spectrumGlobalReferenceLevel: Float` - Smoothed normalization reference

**Dynamic Mode:**
- `spectrumRegionPeaks: [Float]` - Array of 3 tracked peaks (bass, mid, treble)
- `spectrumRegionReferenceLevels: [Float]` - Array of 3 smoothed references

### Output

75 float values (0.0-1.0) representing energy in each frequency band, updated via delegate:
```swift
delegate?.audioEngineDidUpdateSpectrum(spectrumData)
```

Also posted via NotificationCenter for low-latency updates:
```swift
NotificationCenter.default.post(
    name: .audioSpectrumDataUpdated,
    object: self,
    userInfo: ["spectrum": spectrumData]
)
```

### Unified Spectrum Processing

Both local and streaming playback use **identical FFT processing** for consistent visualization:

| Parameter | All Sources |
|-----------|-------------|
| FFT size | 2048 |
| Bin width | ~21.5 Hz |
| Latency | ~46ms |
| dB ceiling | 40 |
| dB floor | 0 |

**Benefits of unified implementation:**
- Consistent visualization when switching between local files, Plex, Navidrome, and radio
- Good frequency resolution across the entire spectrum (including sub-bass)
- No visual artifacts when changing audio sources

**Source switching:**
- When switching from local to streaming, the local spectrum tap on `mixerNode` is removed
- When switching from streaming to local, the streaming player is stopped and its spectrum cleared
- A `ResetSpectrumState` notification triggers the `SpectrumAnalyzerView` to clear all visualization state
- This ensures clean transitions with no residual data from the previous source

### Volume-Independent Visualizations

Spectrum analyzer and MilkDrop visualizations display audio levels independently of the user's volume setting. This ensures visualizations show consistent audio levels whether volume is at 10% or 100%.

**Local Playback Implementation:**
- Audio tap installed on `mixerNode` at bus 0 (captures combined audio from both player nodes)
- Both `playerNode` and `crossfadePlayerNode` stay at 1.0 (unity gain)
- Output volume controlled via `engine.mainMixerNode.outputVolume`
- The tap captures unity-gain audio regardless of volume setting
- During crossfade, player volumes ramp between 0 and 1.0 for relative mixing
- Tap on mixerNode ensures visualization works during crossfade and after player swap

**Streaming Playback Implementation:**
- AudioStreaming's `frameFiltering` captures audio after volume is applied
- `processAudioBuffer()` compensates by dividing samples by current volume
- Compensation capped at 20x (volume 5%) to avoid amplifying noise at very low volumes

**Signal Flow (Local):**
```
playerNode (unity) ──────┐
                         ├──► mixerNode ──► eqNode ──► limiterNode ──► mainMixerNode ──► output
crossfadePlayer (unity) ─┘        │                                        (volume here)
                                  │
                                  └── tap captures COMBINED audio (volume-independent)
```

### Standalone Spectrum Analyzer Window

A dedicated spectrum analyzer window is available (Visualizations menu → Spectrum Analyzer) with:

- **Metal-based rendering** - GPU-accelerated visualization via CVDisplayLink
  - Uses runtime shader compilation for SPM compatibility (`device.makeLibrary(source:)`)
  - Separate pipeline states for each quality mode
  - Display-native refresh rate support (up to 120Hz on ProMotion displays)
- **84 bars** (vs 19 in main window) - Higher resolution frequency display
- **Quality modes:**
  - **Winamp** - Smooth gradient colors from skin's `viscolor.txt` with 3D cylindrical bar shading
  - **Enhanced** - Rainbow LED matrix (16 rows) with floating peaks and per-cell fade trails
  - **Ultra** - Maximum visual quality with advanced effects (see below)
- **Decay modes** controlling bar responsiveness:
  - **Instant** - No smoothing, immediate response
  - **Snappy** - 25% retention, fast and punchy (default)
  - **Balanced** - 40% retention, good middle ground
  - **Smooth** - 55% retention, original Winamp feel

The window respects the current skin's visualization colors and docks with other Winamp-style windows.

#### Ultra Quality Mode

Ultra mode provides the smoothest and most visually impressive spectrum visualization:

- **24 LED rows** (vs 16 in Enhanced) for higher vertical resolution
- **Triple buffering** for smoother frame pacing and fewer dropped frames
- **Frequency-based colors** - bass frequencies appear red/orange, treble appears blue/purple
- **Physics-based peaks** - peaks fall with gravity acceleration and bounce when hitting rising bars
- **Reflection effect** - mirror reflection below the bars with fade gradient
- **Bloom/glow effect** - lit cells emit soft glow within their boundaries
- **Anti-aliased cells** - smooth cell edges instead of hard corners

**Performance:** Ultra mode uses more GPU resources but remains efficient:
- Triple buffering (semaphore=3) adds ~16ms latency but eliminates frame drops
- 24 rows is 50% more vertices than Enhanced but negligible for modern GPUs
- Reflection uses the same brightness data, just mirrored and faded

**Key files:**
- `Visualization/SpectrumAnalyzerView.swift` - Metal-based spectrum view component
- `Visualization/SpectrumShaders.metal` - GPU shaders (Winamp bar, LED matrix, Ultra modes)
- `Windows/Spectrum/SpectrumWindowController.swift` - Window controller
- `Windows/Spectrum/SpectrumView.swift` - Container view with skin chrome

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

### Configuration Change Handling

When the output device changes (either programmatically or via system events like plugging in headphones), AVAudioEngine fires an `AVAudioEngineConfigurationChange` notification. AudioEngine observes this and:

1. Reconnects all nodes with the new output format (sample rate may differ between devices)
2. Re-schedules audio from the current position
3. Resumes playback automatically

This ensures seamless transitions between devices with different sample rates (e.g., 44.1kHz vs 48kHz).

### Device Preference Persistence

The selected output device UID is saved to UserDefaults and restored on app launch. If the saved device is no longer available, the system default is used.

**Note:** Output device selection only affects local file playback. Streaming audio uses the system default output (AudioStreaming limitation).

## File Support

### Local Playback (AVAudioEngine)

Formats supported by AVAudioFile:
- MP3, M4A, AAC, WAV, AIFF, FLAC, ALAC, OGG

### Streaming Playback (AudioStreaming)

- HTTP/HTTPS URLs
- MP3, AAC, Ogg Vorbis streams
- Shoutcast/Icecast with metadata

**M4A Limitation:** Only "fast-start" optimized M4A files are supported for HTTP streaming. Non-optimized M4A files (where the `moov` atom is at the end of the file) will fail with a `streamParseBytesFailure` error. This is a limitation of Apple's AudioFileStream Services. When this error occurs, AdAmp automatically advances to the next track.

To fix problematic M4A files, re-encode with `ffmpeg -i input.m4a -movflags +faststart output.m4a`.

## Dependencies

| Library | Purpose | Version |
|---------|---------|---------|
| AVFoundation | Local file playback, EQ | System |
| Accelerate | FFT for spectrum analysis | System |
| CoreAudio | Output device management | System |
| [AudioStreaming](https://github.com/dimitris-c/AudioStreaming) | HTTP streaming with AVAudioEngine | 1.4.0+ |

## Platform Requirements

- **macOS 14.0+** (required by Swift 6.0 toolchain)

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
http://server/rest/stream?id=SONG_ID&u=USERNAME&t=TOKEN&s=SALT&v=1.16.1&c=AdAmp
```

**Note:** The `f=json` parameter is intentionally omitted from stream URLs. It should only be used for REST API calls that return JSON - stream endpoints return binary audio data.

### Casting to Sonos

When casting Subsonic content to Sonos speakers, streams are proxied through LocalMediaServer:

1. Sonos has issues with URLs containing query parameters (authentication tokens)
2. Navidrome may be bound to localhost, unreachable by Sonos speakers
3. The proxy provides a clean URL: `http://{mac-ip}:8765/stream/{token}`
4. LocalMediaServer fetches from Navidrome and streams to Sonos (no transcoding)

See [SONOS.md](SONOS.md) for full casting documentation.

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

## Now Playing Integration

AdAmp reports playback information to macOS via `MPNowPlayingInfoCenter`, enabling:
- Discord Music Presence (https://github.com/ungive/discord-music-presence)
- macOS Control Center media controls
- Touch Bar controls
- Bluetooth headphone controls (AirPods, etc.)

The integration is managed by `NowPlayingManager` in `Sources/AdAmp/App/NowPlayingManager.swift`.

### Reported Metadata
- Title, Artist, Album
- Duration and elapsed time
- Album artwork (loaded asynchronously)
- Playback state (playing/paused/stopped)

### Remote Commands Supported
- Play, Pause, Toggle Play/Pause
- Next Track, Previous Track
- Seek to position (scrubbing)

## Historical Note

Prior to the AudioStreaming integration, Plex streaming used `AVPlayer` which outputs directly to hardware, bypassing `AVAudioEngine`. An attempt was made to bridge this using `MTAudioProcessingTap` and a ring buffer to route audio through the EQ, but this failed due to fundamental timing mismatches between the tap's push model and the engine's pull model.

The AudioStreaming library solves this by handling streaming entirely within `AVAudioEngine`, allowing proper integration with audio processing nodes.
