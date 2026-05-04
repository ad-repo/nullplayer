import Foundation

enum SpectrumAccurateModeCalculator {
    static let bandCount = 75
    static let minFrequency: Float = 20
    static let maxFrequency: Float = 20_000

    struct BandRange: Equatable {
        let startFrequency: Float
        let endFrequency: Float
        let startBin: Int
        let endBin: Int
    }

    static func bandRange(
        for band: Int,
        fftSize: Int,
        sampleRate: Float,
        magnitudeCount: Int
    ) -> BandRange? {
        guard band >= 0,
              band < bandCount,
              fftSize > 0,
              sampleRate > 0,
              magnitudeCount > 1 else {
            return nil
        }

        let startFrequency = minFrequency * pow(maxFrequency / minFrequency, Float(band) / Float(bandCount))
        let endFrequency = minFrequency * pow(maxFrequency / minFrequency, Float(band + 1) / Float(bandCount))
        let binWidth = sampleRate / Float(fftSize)
        let maxBin = min(fftSize / 2 - 1, magnitudeCount - 1)
        let startBin = min(maxBin, max(1, Int(startFrequency / binWidth)))
        let endBin = max(startBin, min(maxBin, Int(endFrequency / binWidth)))

        return BandRange(
            startFrequency: startFrequency,
            endFrequency: endFrequency,
            startBin: startBin,
            endBin: endBin
        )
    }

    static func localBespecLevel(
        band: Int,
        magnitudes: [Float],
        fftSize: Int,
        sampleRate: Float
    ) -> Float {
        guard let range = bandRange(
            for: band,
            fftSize: fftSize,
            sampleRate: sampleRate,
            magnitudeCount: magnitudes.count
        ) else {
            return 0
        }

        var peakMagnitude: Float = 0
        for bin in range.startBin...range.endBin {
            if magnitudes[bin] > peakMagnitude {
                peakMagnitude = magnitudes[bin]
            }
        }

        let bespecFactor: Float = 2.0 / sqrt(Float(fftSize))
        let calibratedMagnitude = peakMagnitude * bespecFactor
        let dB = 20.0 * log10(max(calibratedMagnitude, 1e-10))
        let ceiling: Float = 0.0
        let floor: Float = -20.0
        return clamped((dB - floor) / (ceiling - floor))
    }

    static func streamingRMSLevel(
        band: Int,
        magnitudes: [Float],
        fftSize: Int,
        sampleRate: Float
    ) -> Float {
        guard let range = bandRange(
            for: band,
            fftSize: fftSize,
            sampleRate: sampleRate,
            magnitudeCount: magnitudes.count
        ) else {
            return 0
        }

        var totalPower: Float = 0
        for bin in range.startBin...range.endBin {
            totalPower += magnitudes[bin] * magnitudes[bin]
        }

        let binCount = Float(range.endBin - range.startBin + 1)
        let averagePower = totalPower / max(binCount, 1)
        let rmsMagnitude = sqrt(averagePower)
        let bandwidth = range.endFrequency - range.startFrequency
        let bandwidthScale = pow(bandwidth / 20.0, 0.6)
        let scaledMagnitude = rmsMagnitude * bandwidthScale
        let dB = 20.0 * log10(max(scaledMagnitude, 1e-10))
        let ceiling: Float = 40.0
        let floor: Float = 0.0
        return clamped((dB - floor) / (ceiling - floor))
    }

    private static func clamped(_ value: Float) -> Float {
        max(0, min(1, value))
    }
}
