import Foundation
import Accelerate

/// Real-time BPM detector using onset detection and autocorrelation.
///
/// Processes audio buffers from the audio tap to detect tempo. Uses bass-band
/// energy onset detection with autocorrelation to find periodicity, plus
/// multi-layer smoothing (median filter + EMA + lock-in) for stable output.
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
    private let lockBreakCount = 3
    
    // MARK: - State
    
    /// Sample rate of the audio being processed
    private var sampleRate: Double = 44100
    
    /// Rolling buffer of bass energy values (raw, not thresholded)
    /// Each entry corresponds to one audio frame (~60Hz)
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
    
    /// Frame counter for debug logging
    private var frameCount = 0
    
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
        
        // Store raw energy (no thresholding - autocorrelation works on the full signal)
        energyBuffer.append(bassEnergy)
        energyTimestamps.append(now)
        
        // Keep buffer bounded
        if energyBuffer.count > maxEnergyBufferSize {
            let excess = energyBuffer.count - maxEnergyBufferSize
            energyBuffer.removeFirst(excess)
            energyTimestamps.removeFirst(excess)
        }
        
        frameCount += 1
        
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
        frameCount = 0
        
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
        // Zero-pad if needed
        if processCount < bassFFTSize {
            for i in processCount..<bassFFTSize {
                bassRealIn[i] = 0
            }
        }
        // Clear imaginary input
        memset(&bassImagIn, 0, bassFFTSize * MemoryLayout<Float>.size)
        
        // Forward FFT
        vDSP_DFT_Execute(setup, bassRealIn, bassImagIn, &bassRealOut, &bassImagOut)
        
        // Sum energy in bass range: 20-200 Hz
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
        
        // Normalize by number of bins
        let binCount = Float(maxBin - minBin + 1)
        return energy / binCount
    }
    
    // MARK: - Autocorrelation Analysis
    
    /// Run autocorrelation on the energy buffer and update BPM estimate.
    /// Uses the raw energy signal directly - autocorrelation finds periodicity
    /// without needing explicit onset detection.
    private func analyzeAndUpdate(timestamp: CFAbsoluteTime) {
        let n = energyBuffer.count
        guard n >= 150 else { return }
        
        // Compute actual onset rate from timestamps
        let timeSpan = energyTimestamps[n - 1] - energyTimestamps[0]
        guard timeSpan > 0 else { return }
        let onsetRate = Float(n - 1) / Float(timeSpan)
        
        // BPM range → lag range in energy samples
        // lag = onsetRate * 60 / bpm
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
        
        // Use the most recent portion
        let analysisLength = n
        
        for lagIdx in 0..<lagCount {
            let lag = minLag + lagIdx
            let compareLength = analysisLength - lag
            guard compareLength > 0 else {
                autocorrelationBuffer[lagIdx] = 0
                continue
            }
            
            // Normalized autocorrelation: subtract mean, dot product
            var sum: Float = 0
            for i in 0..<compareLength {
                let a = energyBuffer[i] - meanEnergy
                let b = energyBuffer[i + lag] - meanEnergy
                sum += a * b
            }
            autocorrelationBuffer[lagIdx] = sum / Float(compareLength)
        }
        
        // Find the dominant peak in the autocorrelation
        guard let peakIdx = findDominantPeak(in: autocorrelationBuffer, count: lagCount) else {
            return
        }
        
        let bestLag = Float(minLag + peakIdx)
        guard bestLag > 0 else { return }
        
        // Convert lag to BPM
        var rawBPM = onsetRate * 60.0 / bestLag
        
        // Octave correction: bring into range
        while rawBPM < minBPM && rawBPM > 0 { rawBPM *= 2 }
        while rawBPM > maxBPM { rawBPM /= 2 }
        
        guard rawBPM >= minBPM && rawBPM <= maxBPM else { return }
        
        // Add to recent estimates for median filtering
        recentEstimates.append(rawBPM)
        if recentEstimates.count > medianWindowSize {
            recentEstimates.removeFirst(recentEstimates.count - medianWindowSize)
        }
        
        // Need enough estimates for median
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
                    isLockedIn = false
                    lockInConsecutiveCount = 0
                    lockBreakConsecutiveCount = 0
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
        
        // Post notification (throttled)
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
    
    /// Find the dominant peak in the autocorrelation buffer.
    private func findDominantPeak(in buffer: [Float], count: Int) -> Int? {
        guard count > 2 else { return nil }
        
        // Find all local maxima
        var peaks: [(index: Int, value: Float)] = []
        for i in 1..<(count - 1) {
            if buffer[i] > buffer[i - 1] && buffer[i] > buffer[i + 1] && buffer[i] > 0 {
                peaks.append((index: i, value: buffer[i]))
            }
        }
        
        guard !peaks.isEmpty else {
            // No local maxima found - just find the global max
            var maxVal: Float = 0
            var maxIdx: vDSP_Length = 0
            vDSP_maxvi(buffer, 1, &maxVal, &maxIdx, vDSP_Length(count))
            return maxVal > 0 ? Int(maxIdx) : nil
        }
        
        // Sort by value descending
        peaks.sort { $0.value > $1.value }
        
        // Return the highest peak
        return peaks[0].index
    }
}
