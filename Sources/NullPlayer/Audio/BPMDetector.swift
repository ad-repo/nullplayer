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
    /// Fixed-size circular buffer for recent BPM readings
    private var recentReadings: [Float] = Array(repeating: 0, count: 10)
    private var readingIndex = 0
    private var readingCount = 0
    private var sortBuffer: [Float] = Array(repeating: 0, count: 10)
    private var lastNotificationTime: CFAbsoluteTime = 0
    private let notificationInterval: CFAbsoluteTime = 1.0
    
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
        readingIndex = 0
        readingCount = 0
        displayedBPM = 0
        hasConfidentReading = false
        lastNotificationTime = 0
    }
    
    // MARK: - Public API
    
    /// Process a whole tap buffer, mixed to mono and scaled by `gain`. Called from the audio
    /// tap thread ONLY. aubio treats its input as one continuous signal, so every buffer must
    /// arrive whole and none skipped: a slice of each (the FFT's 2048 of a 4410-frame buffer,
    /// throttled) squeezed time and broke the tempo. `postBeats` posts `.audioBeatsUpdated`,
    /// only wanted while a beat consumer exists.
    func process(channels: UnsafePointer<UnsafeMutablePointer<Float>>, channelCount: Int,
                 frameCount: Int, sampleRate: Double, gain: Float = 1, postBeats: Bool) {
        guard channelCount > 0 else { return }
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
              let outputData = outputBuf.pointee.data else { return }
        
        // Write samples to ring buffer
        let ringSize = ringBuffer.count
        let toWrite = min(frameCount, ringSize - ringCount)
        let scale = gain / Float(channelCount)
        for i in 0..<toWrite {
            var sum: Float = 0
            for c in 0..<channelCount { sum += channels[c][i] }
            ringBuffer[ringWritePos] = sum * scale
            ringWritePos = (ringWritePos + 1) % ringSize
        }
        ringCount += toWrite
        
        let hop = Int(hopSize)
        let now = CFAbsoluteTimeGetCurrent()
        var beats: [Bool] = []

        while ringCount >= hop {
            for i in 0..<hop {
                inputData[i] = ringBuffer[ringReadPos]
                ringReadPos = (ringReadPos + 1) % ringSize
            }
            ringCount -= hop
            
            aubio_tempo_do(tempoObj, inputBuf, outputBuf)
            if postBeats { beats.append(outputData[0] != 0) }  // aubio: non-zero on a beat in this hop
            
            let bpm = aubio_tempo_get_bpm(tempoObj)
            let confidence = aubio_tempo_get_confidence(tempoObj)

            if bpm > 0 && confidence >= minConfidence {
                recentReadings[readingIndex % maxBPMReadings] = bpm
                readingIndex += 1
                readingCount = min(readingCount + 1, maxBPMReadings)

                if readingCount >= 3 {
                    sortBuffer[0..<readingCount] = recentReadings[0..<readingCount]
                    sortBuffer[0..<readingCount].sort()
                    let median = sortBuffer[readingCount / 2]
                    let newBPM = Int(median.rounded())
                    if newBPM > 0 {
                        displayedBPM = newBPM
                        hasConfidentReading = true
                    }
                }
            }
        }
        
        if !beats.isEmpty {
            NotificationCenter.default.post(
                name: .audioBeatsUpdated, object: nil,
                userInfo: ["beats": beats, "hopMs": Double(hop) * 1000 / sampleRate])
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
