import XCTest
@testable import NullPlayerPlayback

final class PortableAudioAnalysisTests: XCTestCase {
    func testSpectrumOutputUses75Bins() {
        let analysis = PortableAudioAnalysis()
        let frame = makeStereoSineFrame(sampleRate: 44_100, frequency: 440, frameCount: 2048)

        analysis.consume(frame)

        XCTAssertEqual(analysis.spectrumData.count, 75)
        XCTAssertGreaterThan(analysis.spectrumData.max() ?? 0, 0)
    }

    func testPCMOutputUses512Samples() {
        let analysis = PortableAudioAnalysis()
        let frame = makeStereoSineFrame(sampleRate: 44_100, frequency: 220, frameCount: 2048)

        analysis.consume(frame)

        XCTAssertEqual(analysis.pcmData.count, 512)
        XCTAssertGreaterThan(analysis.pcmData.map(abs).max() ?? 0, 0)
    }

    func testSilenceDecayAndZeroThreshold() {
        let analysis = PortableAudioAnalysis(decayFactor: 0.85, silenceThreshold: 0.01)
        let frame = makeStereoSineFrame(sampleRate: 44_100, frequency: 1_000, frameCount: 1024)

        analysis.consume(frame)
        let initialPeak = analysis.spectrumData.max() ?? 0
        XCTAssertGreaterThan(initialPeak, 0.05)

        // Apply enough silent frames to cross the 0.01 zero threshold.
        for _ in 0..<32 {
            analysis.consume(nil)
        }

        XCTAssertEqual(analysis.spectrumData.max() ?? 0, 0, accuracy: 0.0001)
    }

    func testNilAndEmptyInputHandling() {
        let analysis = PortableAudioAnalysis()
        analysis.consume(nil)

        XCTAssertEqual(analysis.pcmData.count, 512)
        XCTAssertEqual(analysis.spectrumData.count, 75)

        let emptyFrame = AnalysisFrame(samples: [], channels: 2, sampleRate: 44_100, monotonicTime: 0)
        analysis.consume(emptyFrame)

        XCTAssertEqual(analysis.pcmData.max() ?? 0, 0, accuracy: 0.0001)
    }

    private func makeStereoSineFrame(sampleRate: Double, frequency: Double, frameCount: Int) -> AnalysisFrame {
        var interleaved: [Float] = []
        interleaved.reserveCapacity(frameCount * 2)

        for index in 0..<frameCount {
            let t = Double(index) / sampleRate
            let sample = Float(sin(2 * Double.pi * frequency * t))
            interleaved.append(sample)
            interleaved.append(sample)
        }

        return AnalysisFrame(
            samples: interleaved,
            channels: 2,
            sampleRate: sampleRate,
            monotonicTime: 0
        )
    }
}
