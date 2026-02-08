import Foundation
import Accelerate

/// Real-time BPM detector using onset detection and autocorrelation.
///
/// Processes audio buffers from the audio tap to detect tempo. Uses bass-band
/// energy autocorrelation to find periodicity, with harmonic disambiguation
/// and multi-layer smoothing for stable, non-jumpy output.
///
/// Thread safety: All `process` calls must happen on the same thread (the audio tap thread).
/// BPM updates are posted to the main thread via notification.
class BPMDetector {
    
    // MARK: - Configuration
    
    /// BPM range to consider valid
    private let minBPM: Float = 60
    private let maxBPM: Float = 200
    
    /// How often to run autocorrelation analysis (seconds)
    private let analysisInterval: CFAbsoluteTime = 0.5
    
    /// EMA alpha for final BPM smoothing
    private let bpmSmoothAlpha: Float = 0.2
    
    /// Number of recent BPM estimates for median filtering
    private let medianWindowSize = 7
    
    /// Lock-in: how many consecutive readings must agree before locking
    private let lockInCount = 3
    
    /// Lock-in: how far off (BPM) a reading must be to break lock
    private let lockInTolerance: Float = 5.0
    
    /// Lock-in: how many consecutive out-of-range readings to break lock
    private let lockBreakCount = 6
    
    // MARK: - State
    
    /// Sample rate of the audio being processed
    private var sampleRate: Double = 44100
    
    /// Rolling buffer of bass energy values
    private var energyBuffer: [Float] = []
    
    /// Maximum energy buffer size (~12 seconds at 60Hz)
    private let maxEnergyBufferSize = 720
    
    /// Timestamps for each energy sample (to compute actual sample rate)
    private var energyTimestamps: [CFAbsoluteTime] = []
    
    /// Recent raw BPM estimates for median filtering
    private var recentEstimates: [Float] = []
    
    /// Current smoothed BPM (EMA output)
    private var smoothedBPM: Float = 0
    
    /// Last displayed BPM (what was posted via notification)
    private var displayedBPM: Int = 0
    
    /// Whether we have a confident BPM reading
    private var hasConfidentReading = false
    
    /// Lock-in state
    private var isLockedIn = false
    private var lockInConsecutiveCount = 0
    private var lockBreakConsecutiveCount = 0
    
    /// Timing for analysis throttling
    private var lastAnalysisTime: CFAbsoluteTime = 0
    
    /// Timing for notification throttling (don't spam UI)
    private var lastNotificationTime: CFAbsoluteTime = 0
    private let notificationInterval: CFAbsoluteTime = 1.0
    
    /// Pre-allocated buffers for autocorrelation
    private var autocorrelationBuffer: [Float] = []
    
    /// Small FFT for bass energy extraction
    private var bassFFTSetup: vDSP_DFT_Setup?
    private let bassFFTSize = 512
    private var bassRealIn = [Float](repeating: 0, count: 512)
    private var bassImagIn = [Float](repeating: 0, count: 512)
    private var bassRealOut = [Float](repeating: 0, count: 512)
    private var bassImagOut = [Float](repeating: 0, count: 512)
    private var bassWindow = [Float](repeating: 0, count: 512)
    
    // MARK: - Initialization
    
    init() {
        bassFFTSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(bassFFTSize), .FORWARD)
        vDSP_hann_window(&bassWindow, vDSP_Length(bassFFTSize), Int32(vDSP_HANN_NORM))
    }
    
    deinit {
        bassFFTSetup = nil
    }
    
    // MARK: - Public API
    
    /// Process a buffer of mono audio samples. Call from the audio tap thread.
    func process(samples: UnsafePointer<Float>, count: Int, sampleRate: Double) {
        self.sampleRate = sampleRate
        let now = CFAbsoluteTimeGetCurrent()
        
        // Extract bass energy using low-frequency FFT bins
        let bassEnergy = computeBassEnergy(samples: samples, count: count)
        
        // Store raw energy
        energyBuffer.append(bassEnergy)
        energyTimestamps.append(now)
        
        // Keep buffer bounded
        if energyBuffer.count > maxEnergyBufferSize {
            let excess = energyBuffer.count - maxEnergyBufferSize
            energyBuffer.removeFirst(excess)
            energyTimestamps.removeFirst(excess)
        }
        
        // Run autocorrelation analysis at intervals
        // Need at least ~3 seconds of data for meaningful analysis
        if now - lastAnalysisTime >= analysisInterval && energyBuffer.count >= 150 {
            lastAnalysisTime = now
            analyzeAndUpdate(timestamp: now)
        }
    }
    
    /// Reset all state (call on track change)
    func reset() {
        energyBuffer.removeAll()
        energyTimestamps.removeAll()
        recentEstimates.removeAll()
        smoothedBPM = 0
        displayedBPM = 0
        hasConfidentReading = false
        isLockedIn = false
        lockInConsecutiveCount = 0
        lockBreakConsecutiveCount = 0
        lastAnalysisTime = 0
        lastNotificationTime = 0
        
        // Post reset (clear display)
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .bpmUpdated,
                object: nil,
                userInfo: ["bpm": 0]
            )
        }
    }
    
    // MARK: - Bass Energy Extraction
    
    /// Compute energy in the bass frequency range (20-200 Hz) using FFT
    private func computeBassEnergy(samples: UnsafePointer<Float>, count: Int) -> Float {
        guard let setup = bassFFTSetup else { return 0 }
        
        let processCount = min(count, bassFFTSize)
        
        // Copy samples and apply window
        for i in 0..<processCount {
            bassRealIn[i] = samples[i] * bassWindow[i]
        }
        if processCount < bassFFTSize {
            for i in processCount..<bassFFTSize {
                bassRealIn[i] = 0
            }
        }
        memset(&bassImagIn, 0, bassFFTSize * MemoryLayout<Float>.size)
        
        vDSP_DFT_Execute(setup, bassRealIn, bassImagIn, &bassRealOut, &bassImagOut)
        
        let freqResolution = Float(sampleRate) / Float(bassFFTSize)
        let halfSize = bassFFTSize / 2
        let minBin = max(1, Int(20.0 / freqResolution))
        let maxBin = min(halfSize - 1, Int(200.0 / freqResolution))
        
        guard minBin <= maxBin else { return 0 }
        
        var energy: Float = 0
        for i in minBin...maxBin {
            let re = bassRealOut[i]
            let im = bassImagOut[i]
            energy += re * re + im * im
        }
        
        let binCount = Float(maxBin - minBin + 1)
        return energy / binCount
    }
    
    // MARK: - Autocorrelation Analysis
    
    /// Run autocorrelation on the energy buffer and update BPM estimate.
    private func analyzeAndUpdate(timestamp: CFAbsoluteTime) {
        let n = energyBuffer.count
        guard n >= 150 else { return }
        
        // Compute actual onset rate from timestamps
        let timeSpan = energyTimestamps[n - 1] - energyTimestamps[0]
        guard timeSpan > 0 else { return }
        let onsetRate = Float(n - 1) / Float(timeSpan)
        
        // BPM range → lag range
        let minLag = max(2, Int(onsetRate * 60.0 / maxBPM))
        let maxLag = min(n / 2, Int(onsetRate * 60.0 / minBPM))
        
        guard minLag < maxLag else { return }
        
        // Compute mean energy for normalization
        var meanEnergy: Float = 0
        vDSP_meanv(energyBuffer, 1, &meanEnergy, vDSP_Length(n))
        guard meanEnergy > 0 else { return }
        
        // Compute autocorrelation for the lag range
        let lagCount = maxLag - minLag + 1
        if autocorrelationBuffer.count < lagCount {
            autocorrelationBuffer = [Float](repeating: 0, count: lagCount)
        }
        
        for lagIdx in 0..<lagCount {
            let lag = minLag + lagIdx
            let compareLength = n - lag
            guard compareLength > 0 else {
                autocorrelationBuffer[lagIdx] = 0
                continue
            }
            
            var sum: Float = 0
            for i in 0..<compareLength {
                let a = energyBuffer[i] - meanEnergy
                let b = energyBuffer[i + lag] - meanEnergy
                sum += a * b
            }
            autocorrelationBuffer[lagIdx] = sum / Float(compareLength)
        }
        
        // Find the best BPM, preferring the fundamental period over harmonics
        guard let bestBPM = findBestBPM(onsetRate: onsetRate, minLag: minLag, lagCount: lagCount) else {
            return
        }
        
        // Normalize to the same octave as the current lock-in value (if any)
        // This prevents double/half-time oscillation from corrupting the median filter
        var normalizedBPM = bestBPM
        if displayedBPM > 0 && hasConfidentReading {
            let displayed = Float(displayedBPM)
            // If the new estimate is close to 2x or 0.5x the displayed, snap it
            if abs(normalizedBPM - displayed * 2) < displayed * 0.15 {
                normalizedBPM /= 2
            } else if abs(normalizedBPM - displayed / 2) < displayed * 0.15 {
                normalizedBPM *= 2
            }
            // Ensure still in range after snap
            if normalizedBPM < minBPM || normalizedBPM > maxBPM {
                normalizedBPM = bestBPM  // revert
            }
        }
        
        // Add to recent estimates for median filtering
        recentEstimates.append(normalizedBPM)
        if recentEstimates.count > medianWindowSize {
            recentEstimates.removeFirst(recentEstimates.count - medianWindowSize)
        }
        
        guard recentEstimates.count >= 3 else { return }
        
        // Median filter
        let sorted = recentEstimates.sorted()
        let medianBPM = sorted[sorted.count / 2]
        
        // Apply EMA smoothing
        if smoothedBPM == 0 {
            smoothedBPM = medianBPM
        } else {
            smoothedBPM = smoothedBPM * (1 - bpmSmoothAlpha) + medianBPM * bpmSmoothAlpha
        }
        
        let roundedBPM = Int(smoothedBPM.rounded())
        
        // Lock-in logic
        if isLockedIn {
            if abs(Float(roundedBPM) - Float(displayedBPM)) <= lockInTolerance {
                lockBreakConsecutiveCount = 0
            } else {
                lockBreakConsecutiveCount += 1
                if lockBreakConsecutiveCount >= lockBreakCount {
                    // Break lock - also clear old estimates to avoid mixing octaves
                    isLockedIn = false
                    lockInConsecutiveCount = 0
                    lockBreakConsecutiveCount = 0
                    recentEstimates.removeAll()
                    smoothedBPM = Float(roundedBPM)
                    displayedBPM = roundedBPM
                    hasConfidentReading = true
                }
            }
        } else {
            if displayedBPM == 0 || abs(Float(roundedBPM) - Float(displayedBPM)) <= lockInTolerance {
                lockInConsecutiveCount += 1
                displayedBPM = roundedBPM
                hasConfidentReading = true
                
                if lockInConsecutiveCount >= lockInCount {
                    isLockedIn = true
                }
            } else {
                lockInConsecutiveCount = 1
                displayedBPM = roundedBPM
            }
        }
        
        // Post notification (throttled) - always post the current displayed value
        // once we have confidence, to keep the UI label visible
        guard hasConfidentReading && displayedBPM > 0 else { return }
        if timestamp - lastNotificationTime >= notificationInterval {
            lastNotificationTime = timestamp
            let bpm = displayedBPM
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .bpmUpdated,
                    object: nil,
                    userInfo: ["bpm": bpm]
                )
            }
        }
    }
    
    /// Find the best BPM from autocorrelation, preferring the fundamental period.
    ///
    /// The autocorrelation of a periodic signal has peaks at the fundamental period
    /// AND at integer subdivisions (harmonics). A peak at lag=N (fundamental) will
    /// also produce peaks at lag=N/2 (double-time), lag=N/3 (triple-time), etc.
    /// We want the fundamental (largest lag = slowest BPM within range).
    private func findBestBPM(onsetRate: Float, minLag: Int, lagCount: Int) -> Float? {
        guard lagCount > 2 else { return nil }
        
        // Find all local maxima with their BPM values
        struct Peak {
            let lagIdx: Int
            let lag: Int
            let value: Float
            let bpm: Float
        }
        
        var peaks: [Peak] = []
        for i in 1..<(lagCount - 1) {
            if autocorrelationBuffer[i] > autocorrelationBuffer[i - 1] &&
               autocorrelationBuffer[i] > autocorrelationBuffer[i + 1] &&
               autocorrelationBuffer[i] > 0 {
                let lag = minLag + i
                var bpm = onsetRate * 60.0 / Float(lag)
                // Octave-correct into range
                while bpm < minBPM && bpm > 0 { bpm *= 2 }
                while bpm > maxBPM { bpm /= 2 }
                if bpm >= minBPM && bpm <= maxBPM {
                    peaks.append(Peak(lagIdx: i, lag: lag, value: autocorrelationBuffer[i], bpm: bpm))
                }
            }
        }
        
        // Fallback: global max if no local maxima
        if peaks.isEmpty {
            var maxVal: Float = 0
            var maxIdx: vDSP_Length = 0
            vDSP_maxvi(autocorrelationBuffer, 1, &maxVal, &maxIdx, vDSP_Length(lagCount))
            guard maxVal > 0 else { return nil }
            let lag = minLag + Int(maxIdx)
            var bpm = onsetRate * 60.0 / Float(lag)
            while bpm < minBPM && bpm > 0 { bpm *= 2 }
            while bpm > maxBPM { bpm /= 2 }
            return (bpm >= minBPM && bpm <= maxBPM) ? bpm : nil
        }
        
        // Sort by value descending
        peaks.sort { $0.value > $1.value }
        
        let strongestPeak = peaks[0]
        
        // Check if the strongest peak has a harmonic relationship with a
        // longer-lag peak (lower BPM = fundamental). If a peak exists at
        // ~2x the lag with reasonable strength, prefer it (it's the fundamental).
        for candidate in peaks {
            // Skip the strongest itself
            if candidate.lagIdx == strongestPeak.lagIdx { continue }
            
            // Is this candidate at roughly 2x the lag of the strongest? (fundamental)
            let lagRatio = Float(candidate.lag) / Float(strongestPeak.lag)
            if lagRatio > 1.8 && lagRatio < 2.2 {
                // This is the fundamental period (half the BPM)
                // Accept it if it has at least 40% of the strongest peak's energy
                if candidate.value >= strongestPeak.value * 0.4 {
                    return candidate.bpm
                }
            }
        }
        
        // No harmonic disambiguation needed - use the strongest peak
        // But if the current lock-in exists, check if the strongest peak's BPM
        // is double the locked value - if so, use half (fundamental)
        if displayedBPM > 0 && hasConfidentReading {
            let ratio = strongestPeak.bpm / Float(displayedBPM)
            if ratio > 1.8 && ratio < 2.2 {
                // Strongest peak is at double-time of the locked value
                // Look for any peak near the locked BPM
                for candidate in peaks {
                    let candidateRatio = candidate.bpm / Float(displayedBPM)
                    if candidateRatio > 0.9 && candidateRatio < 1.1 && candidate.value > strongestPeak.value * 0.3 {
                        return candidate.bpm
                    }
                }
            }
        }
        
        return strongestPeak.bpm
    }
}
