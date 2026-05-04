# Spectrum Analyzer Algorithms

Complete algorithm specifications for all three normalization modes.

## Accurate Mode - Complete Algorithm

**Goal:** Display true signal levels with a flat response for pink noise, suitable for technical analysis.

Important: accurate mode currently differs between local file playback and streaming playback.

**Step 1: FFT Bin Range Calculation**
For each of the 75 logarithmic bands:
```
startFreq = 20 × (20000/20)^(band/75)      // Band's lower frequency edge
endFreq = 20 × (20000/20)^((band+1)/75)    // Band's upper frequency edge
binWidth = sampleRate / fftSize             // Hz per FFT bin (e.g., 44100/2048 = 21.5 Hz)
startBin = max(1, floor(startFreq / binWidth))
endBin = max(startBin, min(fftSize/2 - 1, floor(endFreq / binWidth)))
```

### Local `AudioEngine` Accurate Mode

**Step 2: Peak Aggregation**
Pick the largest magnitude within the band:
```
peakMag = max(magnitude[startBin...endBin])
```

**Step 3: BeSpec Calibration**
Apply Hann correction and energy-preserving FFT scale:
```
bespecFactor = 2.0 / sqrt(fftSize)
calibratedMag = peakMag * bespecFactor
```

**Step 4: Decibel Conversion**
```
dB = 20.0 * log10(max(calibratedMag, 1e-10))
```

**Step 5: Dynamic Range Mapping**
```
ceiling = 0.0 dB
floor = -20.0 dB
normalized = (dB - floor) / (ceiling - floor)
output = clamp(normalized, 0.0, 1.0)
```

Characteristics:
- Peak aggregation gives narrow high-frequency components equal standing with bass
- No bandwidth compensation is applied in local accurate mode
- Display range is 20 dB (`-20...0 dB`)

### Streaming `StreamingAudioPlayer` Accurate Mode

**Step 2: Power Integration (Sum of Squared Magnitudes)**
Sum the squared magnitude of all FFT bins within the band:
```
totalPower = sum(magnitude[bin]^2) for bin in startBin...endBin
binCount = endBin - startBin + 1
```

**Step 3: RMS Magnitude Calculation**
Calculate Root Mean Square (average energy density):
```
avgPower = totalPower / binCount
rmsMag = sqrt(avgPower)
```

**Step 4: Bandwidth Compensation**
Apply scaling to compensate for pink noise's 1/f energy distribution:
```
bandwidthHz = endFreq - startFreq
refBandwidth = 20.0
bandwidthScale = pow(bandwidthHz / refBandwidth, 0.6)
scaledMag = rmsMag * bandwidthScale
```

**Step 5: Decibel Conversion**
Convert linear magnitude to decibels:
```
dB = 20.0 * log10(max(scaledMag, 1e-10))
```

**Step 6: Dynamic Range Mapping**
Map dB range to 0.0-1.0 display range:
```
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
- RMS power integration uses energy across each whole band
- 40 dB dynamic range display (`0...40 dB`)
- Bandwidth compensation aims to flatten pink noise
- Best for: Technical analysis, checking frequency balance, mixing reference

## Adaptive Mode - Complete Algorithm

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

## Dynamic Mode - Complete Algorithm

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

## Algorithm Comparison Summary

| Aspect | Accurate | Adaptive | Dynamic |
|--------|----------|----------|---------|
| **Magnitude source** | Local: peak bin; streaming: RMS of all bins | Single interpolated bin | Single interpolated bin |
| **Bandwidth scaling** | Local: none; streaming: `pow(bw/20, 0.6)` | `sqrt(bw/refBw)` | `sqrt(bw/refBw)` |
| **Frequency weighting** | None | Sub-bass reduction | Sub-bass reduction |
| **Gain control** | Fixed dB mapping | Global adaptive | Per-region adaptive |
| **Peak tracking** | None | Single global peak | 3 regional peaks |
| **Output curve** | Linear (dB-mapped) | Square root | Square root |
| **Preserves balance** | Yes (true levels) | Yes (scaled together) | No (independent) |
| **Pink noise response** | Flat | Flat | Flat per-region |

## State Variables

**Adaptive Mode:**
- `spectrumGlobalPeak: Float` - Tracked global peak level
- `spectrumGlobalReferenceLevel: Float` - Smoothed normalization reference

**Dynamic Mode:**
- `spectrumRegionPeaks: [Float]` - Array of 3 tracked peaks (bass, mid, treble)
- `spectrumRegionReferenceLevels: [Float]` - Array of 3 smoothed references

## Output

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

## Pink Noise Handling

Pink noise has equal energy per octave (not per Hz). Different normalization modes handle this differently:

**All modes apply bandwidth scaling** to compensate for pink noise's 1/f slope:
- Formula: `pow(bandwidthHz / refBandwidth, exponent)` where exponent varies by mode
- This makes pink noise appear relatively flat across all modes
- Accurate mode uses `refBandwidth=20.0` and `exponent=0.6` for slightly steeper high-frequency boost
- Adaptive/Dynamic modes use `refBandwidth=100.0` and `exponent=0.5` (square root)

**Adaptive/Dynamic modes only:**
- Apply additional frequency weighting to reduce sub-bass dominance

## Frequency Weighting (Adaptive/Dynamic modes only)

In **Adaptive** and **Dynamic** modes, an additional frequency weighting curve is applied on top of pink noise compensation to make music look more visually appealing:

| Frequency Range | Weight | Reason |
|-----------------|--------|--------|
| < 40 Hz (sub-bass) | 0.70 | Light reduction - sub-bass energy is usually felt, not seen |
| 40-100 Hz (bass) | 0.85 | Very light reduction - let bass punch through |
| 100-300 Hz (low-mid) | 0.92 | Minimal reduction |
| > 300 Hz | 1.00 | Full level |

This weighting is **not applied** in Accurate mode to preserve true signal levels.
