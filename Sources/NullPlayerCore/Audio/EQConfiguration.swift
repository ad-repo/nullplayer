import Foundation

public struct EQConfiguration: Equatable, Sendable {
    public let name: String
    public let frequencies: [Float]
    public let displayLabels: [String]
    public let parametricBandwidth: Float

    public init(
        name: String,
        frequencies: [Float],
        displayLabels: [String],
        parametricBandwidth: Float
    ) {
        self.name = name
        self.frequencies = frequencies
        self.displayLabels = displayLabels
        self.parametricBandwidth = parametricBandwidth
    }

    public var bandCount: Int {
        frequencies.count
    }

    public func gainValues(remapping gains: [Float], from source: EQConfiguration) -> [Float] {
        EQBandRemapper.remap(gains: gains, from: source, to: self)
    }

    public static func forModernUI(_ isModernUI: Bool) -> EQConfiguration {
        isModernUI ? .modern21 : .classic10
    }

    public static func persistedLayout(forBandCount count: Int) -> EQConfiguration? {
        switch count {
        case classic10.bandCount:
            return .classic10
        case modern21.bandCount:
            return .modern21
        default:
            return nil
        }
    }

    public static let classic10 = EQConfiguration(
        name: "classic10",
        frequencies: [60, 170, 310, 600, 1000, 3000, 6000, 12000, 14000, 16000],
        displayLabels: ["60", "170", "310", "600", "1K", "3K", "6K", "12K", "14K", "16K"],
        parametricBandwidth: 1.75
    )

    public static let modern21 = EQConfiguration(
        name: "modern21",
        frequencies: [31.5, 45, 63, 90, 125, 180, 250, 355, 500, 710, 1000, 1400, 2000, 2800, 4000, 5600, 8000, 11200, 14000, 16000, 20000],
        displayLabels: ["31", "45", "63", "90", "125", "180", "250", "355", "500", "710", "1K", "1.4K", "2K", "2.8K", "4K", "5.6K", "8K", "11.2K", "14K", "16K", "20K"],
        parametricBandwidth: 1.0
    )
}

public enum EQBandRemapper {
    public static func remap(gains: [Float], from source: EQConfiguration, to target: EQConfiguration) -> [Float] {
        guard !target.frequencies.isEmpty else { return [] }
        guard !gains.isEmpty else { return Array(repeating: 0, count: target.bandCount) }
        guard gains.count == source.bandCount else {
            return resized(gains, to: target.bandCount)
        }

        if source == target {
            return gains
        }

        let sourceLogs = source.frequencies.map { log10(Double($0)) }

        return target.frequencies.map { frequency in
            let targetLog = log10(Double(frequency))

            if targetLog <= sourceLogs[0] {
                return gains[0]
            }

            if targetLog >= sourceLogs[sourceLogs.count - 1] {
                return gains[gains.count - 1]
            }

            for index in 1..<sourceLogs.count {
                let lowerLog = sourceLogs[index - 1]
                let upperLog = sourceLogs[index]

                guard targetLog <= upperLog else { continue }

                let range = upperLog - lowerLog
                if range == 0 {
                    return gains[index]
                }

                let factor = Float((targetLog - lowerLog) / range)
                return gains[index - 1] + (gains[index] - gains[index - 1]) * factor
            }

            return gains[gains.count - 1]
        }
    }

    private static func resized(_ gains: [Float], to count: Int) -> [Float] {
        guard count > 0 else { return [] }
        guard !gains.isEmpty else { return Array(repeating: 0, count: count) }
        if gains.count == count { return gains }
        if gains.count == 1 { return Array(repeating: gains[0], count: count) }

        return (0..<count).map { index in
            let position = Float(index) * Float(gains.count - 1) / Float(max(1, count - 1))
            let lower = Int(position.rounded(.down))
            let upper = min(gains.count - 1, lower + 1)
            let fraction = position - Float(lower)
            return gains[lower] + (gains[upper] - gains[lower]) * fraction
        }
    }
}
