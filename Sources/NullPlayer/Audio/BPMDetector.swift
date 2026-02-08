import Foundation
import CAubio

/// Real-time BPM detector powered by aubio's tempo detection.
///
/// Wraps aubio's `aubio_tempo_t` which uses onset detection + beat tracking
/// to produce accurate, stable BPM readings across all genres.
///
/// Thread safety: All `process` calls must happen on the same thread (the audio tap thread).
/// BPM updates are posted to the main thread via notification.
class BPMDetector {
    
    // MARK: - Configuration
    
    /// aubio FFT buffer size (must be power of 2)
    private let bufSize: UInt32 = 1024
    
    /// aubio hop size (samples between analysis frames)
    private let hopSize: UInt32 = 512
    
    /// Minimum confidence to display a BPM value
    private let minConfidence: Float = 0.1
    
    // MARK: - aubio State
    
    /// aubio tempo detection object
    private var tempo: OpaquePointer?
    
    /// aubio input buffer (hopSize samples)
    private var inputBuffer: UnsafeMutablePointer<fvec_t>?
    
    /// aubio output buffer (beat detection result)
    private var outputBuffer: UnsafeMutablePointer<fvec_t>?
    
    /// Accumulator for incoming samples (audio tap delivers 2048 at a time,
    /// aubio wants hopSize chunks)
    private var sampleAccumulator: [Float] = []
    
    /// Current sample rate
    private var sampleRate: UInt32 = 44100
    
    /// Whether aubio has been initialized with the correct sample rate
    private var isInitialized = false
    
    // MARK: - Smoothing State
    
    /// Last displayed BPM
    private var displayedBPM: Int = 0
    
    /// Whether we have a confident reading
    private var hasConfidentReading = false
    
    /// Recent BPM readings for stability filtering
    private var recentReadings: [Float] = []
    private let maxReadings = 10
    
    /// Timing for notification throttling
    private var lastNotificationTime: CFAbsoluteTime = 0
    private let notificationInterval: CFAbsoluteTime = 1.0
    
    // MARK: - Initialization
    
    init() {
        // Defer aubio init until we know the sample rate
    }
    
    deinit {
        destroyAubio()
    }
    
    /// Create or recreate the aubio tempo object for the given sample rate
    private func initAubio(sampleRate: UInt32) {
        destroyAubio()
        
        self.sampleRate = sampleRate
        tempo = new_aubio_tempo("default", bufSize, hopSize, sampleRate)
        inputBuffer = new_fvec(hopSize)
        outputBuffer = new_fvec(2)
        
        // Set silence threshold (ignore very quiet sections)
        if let t = tempo {
            aubio_tempo_set_silence(t, -40.0)
        }
        
        isInitialized = true
    }
    
    /// Clean up aubio resources
    private func destroyAubio() {
        if let t = tempo { del_aubio_tempo(t) }
        if let ib = inputBuffer { del_fvec(ib) }
        if let ob = outputBuffer { del_fvec(ob) }
        tempo = nil
        inputBuffer = nil
        outputBuffer = nil
        isInitialized = false
    }
    
    // MARK: - Public API
    
    /// Process a buffer of mono audio samples. Call from the audio tap thread.
    func process(samples: UnsafePointer<Float>, count: Int, sampleRate: Double) {
        let sr = UInt32(sampleRate)
        
        // Initialize or reinitialize if sample rate changed
        if !isInitialized || sr != self.sampleRate {
            initAubio(sampleRate: sr)
        }
        
        guard let tempo = tempo,
              let inputBuf = inputBuffer,
              let outputBuf = outputBuffer else { return }
        
        // Accumulate incoming samples
        sampleAccumulator.append(contentsOf: UnsafeBufferPointer(start: samples, count: count))
        
        let hop = Int(hopSize)
        let now = CFAbsoluteTimeGetCurrent()
        
        // Process in hopSize chunks
        while sampleAccumulator.count >= hop {
            // Copy samples into aubio's input buffer
            let data = inputBuf.pointee.data!
            for i in 0..<hop {
                data[i] = sampleAccumulator[i]
            }
            sampleAccumulator.removeFirst(hop)
            
            // Run aubio tempo detection
            aubio_tempo_do(tempo, inputBuf, outputBuf)
            
            // Get current BPM estimate
            let bpm = aubio_tempo_get_bpm(tempo)
            let confidence = aubio_tempo_get_confidence(tempo)
            
            if bpm > 0 && confidence >= minConfidence {
                recentReadings.append(bpm)
                if recentReadings.count > maxReadings {
                    recentReadings.removeFirst()
                }
                
                // Use median for stability
                if recentReadings.count >= 3 {
                    let sorted = recentReadings.sorted()
                    let median = sorted[sorted.count / 2]
                    let newBPM = Int(median.rounded())
                    
                    if newBPM > 0 {
                        displayedBPM = newBPM
                        hasConfidentReading = true
                    }
                }
            }
        }
        
        // Post notification (throttled)
        if hasConfidentReading && displayedBPM > 0 && now - lastNotificationTime >= notificationInterval {
            lastNotificationTime = now
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
    
    /// Reset all state (call on track change)
    func reset() {
        destroyAubio()
        sampleAccumulator.removeAll()
        recentReadings.removeAll()
        displayedBPM = 0
        hasConfidentReading = false
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
}
