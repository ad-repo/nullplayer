import Foundation

/// Backend-agnostic spectrum and PCM snapshot helper.
/// Accepts interleaved float32 PCM frames and exposes:
/// - 75-bin spectrum data
/// - 512-sample PCM snapshot
public final class PortableAudioAnalysis: @unchecked Sendable {
    public private(set) var spectrumData: [Float]
    public private(set) var pcmData: [Float]

    private let spectrumBinCount: Int
    private let pcmSampleCount: Int
    private let decayFactor: Float
    private let silenceThreshold: Float
    private let minFrequency: Double
    private let maxFrequency: Double

    public init(
        spectrumBinCount: Int = 75,
        pcmSampleCount: Int = 512,
        decayFactor: Float = 0.85,
        silenceThreshold: Float = 0.01,
        minFrequency: Double = 20,
        maxFrequency: Double = 20_000
    ) {
        self.spectrumBinCount = max(1, spectrumBinCount)
        self.pcmSampleCount = max(1, pcmSampleCount)
        self.decayFactor = max(0, min(decayFactor, 1))
        self.silenceThreshold = max(0, silenceThreshold)
        self.minFrequency = minFrequency
        self.maxFrequency = max(maxFrequency, minFrequency)
        self.spectrumData = Array(repeating: 0, count: max(1, spectrumBinCount))
        self.pcmData = Array(repeating: 0, count: max(1, pcmSampleCount))
    }

    public func consume(_ frame: AnalysisFrame?) {
        guard let frame else {
            applyDecayToSpectrum()
            zeroPCM()
            return
        }

        let mono = makeMonoSamples(from: frame)
        updatePCM(with: mono)
        updateSpectrum(with: mono, sampleRate: frame.sampleRate)
    }

    private func makeMonoSamples(from frame: AnalysisFrame) -> [Float] {
        let channels = max(1, frame.channels)
        guard channels > 1 else {
            return frame.samples
        }

        let frameCount = frame.samples.count / channels
        guard frameCount > 0 else { return [] }

        var mono = Array(repeating: Float.zero, count: frameCount)
        let reciprocal = Float(1.0 / Double(channels))

        for frameIndex in 0..<frameCount {
            var sum: Float = 0
            let base = frameIndex * channels
            for channel in 0..<channels {
                sum += frame.samples[base + channel]
            }
            mono[frameIndex] = sum * reciprocal
        }

        return mono
    }

    private func updatePCM(with mono: [Float]) {
        guard !mono.isEmpty else {
            zeroPCM()
            return
        }

        if mono.count >= pcmSampleCount {
            let start = mono.count - pcmSampleCount
            pcmData.replaceSubrange(0..<pcmSampleCount, with: mono[start..<mono.count])
            return
        }

        let missing = pcmSampleCount - mono.count
        if missing > 0 {
            for index in 0..<missing {
                pcmData[index] = 0
            }
        }
        pcmData.replaceSubrange(missing..<pcmSampleCount, with: mono[0..<mono.count])
    }

    private func updateSpectrum(with mono: [Float], sampleRate: Double) {
        guard !mono.isEmpty, sampleRate > 0 else {
            applyDecayToSpectrum()
            return
        }

        let nyquist = sampleRate * 0.5
        guard nyquist > 0 else {
            applyDecayToSpectrum()
            return
        }

        let ratio = spectrumBinCount > 1
            ? pow(maxFrequency / minFrequency, 1.0 / Double(spectrumBinCount - 1))
            : 1.0

        for band in 0..<spectrumBinCount {
            let frequency = min(minFrequency * pow(ratio, Double(band)), nyquist * 0.98)
            let magnitude = goertzelMagnitude(samples: mono, sampleRate: sampleRate, frequency: frequency)
            let normalized = min(1.0, magnitude * 10.0)
            let decayed = spectrumData[band] * decayFactor
            let next = max(normalized, decayed)
            spectrumData[band] = next < silenceThreshold ? 0 : next
        }
    }

    private func applyDecayToSpectrum() {
        for index in spectrumData.indices {
            let decayed = spectrumData[index] * decayFactor
            spectrumData[index] = decayed < silenceThreshold ? 0 : decayed
        }
    }

    private func zeroPCM() {
        for index in pcmData.indices {
            pcmData[index] = 0
        }
    }

    private func goertzelMagnitude(samples: [Float], sampleRate: Double, frequency: Double) -> Float {
        guard !samples.isEmpty, frequency > 0, sampleRate > 0 else { return 0 }

        let omega = 2.0 * Double.pi * frequency / sampleRate
        let coeff = 2.0 * cos(omega)

        var q0 = 0.0
        var q1 = 0.0
        var q2 = 0.0

        for sample in samples {
            q0 = coeff * q1 - q2 + Double(sample)
            q2 = q1
            q1 = q0
        }

        let power = max(0.0, (q1 * q1) + (q2 * q2) - (coeff * q1 * q2))
        let magnitude = sqrt(power) / Double(samples.count)
        return Float(magnitude)
    }
}
