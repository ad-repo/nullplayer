import Foundation
import CAubio

/// Real-time BPM detector powered by aubio's tempo detection.
///
/// Uses aubio's `aubio_tempo_t` for beat detection and BPM estimation.
/// Thread-safe: `reset()` sets a flag consumed by `process()` on the audio
/// thread so all aubio C library access stays on a single thread.
class BPMDetector {
    
    // MARK: - Configuration
    
    private let bufSize: UInt32 = 1024
    private let hopSize: UInt32 = 512
    private let minConfidence: Float = 0.05
    private let maxBPMReadings = 10
    
    // MARK: - aubio State (audio thread only)
    
    private var tempo: OpaquePointer?
    private var inputBuffer: UnsafeMutablePointer<fvec_t>?
    private var outputBuffer: UnsafeMutablePointer<fvec_t>?
    private var sampleRate: UInt32 = 44100
    private var isInitialized = false
    
    // MARK: - Thread-safe reset
    
    private var needsReset = false
    
    // MARK: - Ring Buffer (audio thread only)
    
    private var ringBuffer = [Float](repeating: 0, count: 8192)
    private var ringWritePos = 0
    private var ringReadPos = 0
    private var ringCount = 0
    
    // MARK: - Display State
    
    private var displayedBPM: Int = 0
    private var hasConfidentReading = false
    private var recentReadings: [Float] = []
    private var lastNotificationTime: CFAbsoluteTime = 0
    private let notificationInterval: CFAbsoluteTime = 1.0
    
    // MARK: - Initialization
    
    init() {
        recentReadings.reserveCapacity(maxBPMReadings + 2)
    }
    
    deinit { destroyAubio() }
    
    private func initAubio(sampleRate: UInt32) {
        destroyAubio()
        self.sampleRate = sampleRate
        tempo = new_aubio_tempo("default", bufSize, hopSize, sampleRate)
        inputBuffer = new_fvec(hopSize)
        outputBuffer = new_fvec(2)
        
        if let t = tempo {
            aubio_tempo_set_silence(t, -40.0)
        }
        
        isInitialized = true
    }
    
    private func destroyAubio() {
        if let t = tempo { del_aubio_tempo(t) }
        if let ib = inputBuffer { del_fvec(ib) }
        if let ob = outputBuffer { del_fvec(ob) }
        tempo = nil
        inputBuffer = nil
        outputBuffer = nil
        isInitialized = false
    }
    
    private func clearState() {
        ringWritePos = 0
        ringReadPos = 0
        ringCount = 0
        recentReadings.removeAll(keepingCapacity: true)
        displayedBPM = 0
        hasConfidentReading = false
        lastNotificationTime = 0
    }
    
    // MARK: - Public API
    
    /// Process audio samples. Called from the audio tap thread ONLY.
    func process(samples: UnsafePointer<Float>, count: Int, sampleRate: Double) {
        if needsReset {
            needsReset = false
            destroyAubio()
            clearState()
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .bpmUpdated, object: nil,
                    userInfo: ["bpm": 0])
            }
        }
        
        let sr = UInt32(sampleRate)
        if !isInitialized || sr != self.sampleRate {
            initAubio(sampleRate: sr)
            clearState()
        }
        
        guard let tempoObj = tempo,
              let inputBuf = inputBuffer,
              let outputBuf = outputBuffer,
              let inputData = inputBuf.pointee.data,
              let _ = outputBuf.pointee.data else { return }
        
        // Write samples to ring buffer
        let ringSize = ringBuffer.count
        let toWrite = min(count, ringSize - ringCount)
        for i in 0..<toWrite {
            ringBuffer[ringWritePos] = samples[i]
            ringWritePos = (ringWritePos + 1) % ringSize
        }
        ringCount += toWrite
        
        let hop = Int(hopSize)
        let now = CFAbsoluteTimeGetCurrent()
        
        while ringCount >= hop {
            for i in 0..<hop {
                inputData[i] = ringBuffer[ringReadPos]
                ringReadPos = (ringReadPos + 1) % ringSize
            }
            ringCount -= hop
            
            aubio_tempo_do(tempoObj, inputBuf, outputBuf)
            
            let bpm = aubio_tempo_get_bpm(tempoObj)
            let confidence = aubio_tempo_get_confidence(tempoObj)
            
            if bpm > 0 && confidence >= minConfidence {
                recentReadings.append(bpm)
                if recentReadings.count > maxBPMReadings {
                    recentReadings.removeFirst()
                }
                
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
        
        if hasConfidentReading && displayedBPM > 0 && now - lastNotificationTime >= notificationInterval {
            lastNotificationTime = now
            let bpm = displayedBPM
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .bpmUpdated, object: nil,
                    userInfo: ["bpm": bpm])
            }
        }
    }
    
    /// Request reset. Safe to call from ANY thread.
    func reset() {
        needsReset = true
    }
}
