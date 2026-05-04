import XCTest
@testable import NullPlayer

final class SpectrumAccurateModeCalculatorTests: XCTestCase {
    private let fftSize = 2048
    private let sampleRate: Float = 44_100

    func testLocalAccurateModeUsesPeakAggregation() throws {
        let band = try bandWithAtLeastFiveBins()
        let range = try XCTUnwrap(SpectrumAccurateModeCalculator.bandRange(
            for: band,
            fftSize: fftSize,
            sampleRate: sampleRate,
            magnitudeCount: fftSize / 2
        ))

        var sparse = [Float](repeating: 0, count: fftSize / 2)
        sparse[range.startBin] = 8

        var dense = sparse
        for bin in (range.startBin + 1)...range.endBin {
            dense[bin] = 4
        }

        let sparseLevel = SpectrumAccurateModeCalculator.localBespecLevel(
            band: band,
            magnitudes: sparse,
            fftSize: fftSize,
            sampleRate: sampleRate
        )
        let denseLevel = SpectrumAccurateModeCalculator.localBespecLevel(
            band: band,
            magnitudes: dense,
            fftSize: fftSize,
            sampleRate: sampleRate
        )

        XCTAssertEqual(sparseLevel, denseLevel, accuracy: 0.0001)
        XCTAssertGreaterThan(sparseLevel, 0)
        XCTAssertLessThan(sparseLevel, 1)
    }

    func testStreamingAccurateModeUsesRMSBandEnergy() throws {
        let band = try bandWithAtLeastFiveBins()
        let range = try XCTUnwrap(SpectrumAccurateModeCalculator.bandRange(
            for: band,
            fftSize: fftSize,
            sampleRate: sampleRate,
            magnitudeCount: fftSize / 2
        ))

        let amplitudes: [Float] = [0.1, 0.25, 0.5, 1, 2, 4, 8]
        let result = amplitudes.compactMap { amplitude -> (Float, Float)? in
            var sparse = [Float](repeating: 0, count: fftSize / 2)
            sparse[range.startBin] = amplitude

            var dense = sparse
            for bin in (range.startBin + 1)...range.endBin {
                dense[bin] = amplitude
            }

            let sparseLevel = SpectrumAccurateModeCalculator.streamingRMSLevel(
                band: band,
                magnitudes: sparse,
                fftSize: fftSize,
                sampleRate: sampleRate
            )
            let denseLevel = SpectrumAccurateModeCalculator.streamingRMSLevel(
                band: band,
                magnitudes: dense,
                fftSize: fftSize,
                sampleRate: sampleRate
            )

            return denseLevel > sparseLevel && denseLevel < 1 ? (sparseLevel, denseLevel) : nil
        }.first

        let levels = try XCTUnwrap(result)
        XCTAssertGreaterThan(levels.1, levels.0)
    }

    func testLocalAndStreamingAccurateModesAreCurrentlyDifferent() throws {
        let band = try bandWithAtLeastFiveBins()
        let range = try XCTUnwrap(SpectrumAccurateModeCalculator.bandRange(
            for: band,
            fftSize: fftSize,
            sampleRate: sampleRate,
            magnitudeCount: fftSize / 2
        ))

        var magnitudes = [Float](repeating: 0, count: fftSize / 2)
        for bin in range.startBin...range.endBin {
            magnitudes[bin] = 8
        }

        let localLevel = SpectrumAccurateModeCalculator.localBespecLevel(
            band: band,
            magnitudes: magnitudes,
            fftSize: fftSize,
            sampleRate: sampleRate
        )
        let streamingLevel = SpectrumAccurateModeCalculator.streamingRMSLevel(
            band: band,
            magnitudes: magnitudes,
            fftSize: fftSize,
            sampleRate: sampleRate
        )

        XCTAssertNotEqual(localLevel, streamingLevel, accuracy: 0.0001)
    }

    private func bandWithAtLeastFiveBins() throws -> Int {
        for band in 0..<SpectrumAccurateModeCalculator.bandCount {
            guard let range = SpectrumAccurateModeCalculator.bandRange(
                for: band,
                fftSize: fftSize,
                sampleRate: sampleRate,
                magnitudeCount: fftSize / 2
            ) else {
                continue
            }

            if range.endBin - range.startBin + 1 >= 5 {
                return band
            }
        }

        throw XCTSkip("No spectrum band covered at least five FFT bins")
    }
}
