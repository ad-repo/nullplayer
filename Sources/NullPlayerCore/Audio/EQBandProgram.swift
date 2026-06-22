import Foundation

/// The filter role a physical EQ band plays within a layout.
public enum EQBandRole: String, Sendable, Equatable {
    case lowShelf
    case highShelf
    case parametric
    /// An unused physical band in layouts smaller than `EQBandProgram.physicalBandCount`.
    case bypassed
}

/// One physical band's complete program: frequency, filter role, bandwidth, and bypass.
///
/// This is a pure value type so layout programming can be unit-tested without
/// importing AVFoundation. App code maps each `EQBandSetting` onto an
/// `AVAudioUnitEQ` band.
public struct EQBandSetting: Sendable, Equatable {
    public let frequency: Float
    public let role: EQBandRole
    public let bandwidth: Float
    public let bypass: Bool

    public init(frequency: Float, role: EQBandRole, bandwidth: Float, bypass: Bool) {
        self.frequency = frequency
        self.role = role
        self.bandwidth = bandwidth
        self.bypass = bypass
    }
}

/// Describes how to program a single fixed-size `AVAudioUnitEQ` for any supported
/// layout, so one node can host either the classic 10-band or modern 21-band EQ
/// without being rebuilt.
///
/// The node is always created with `physicalBandCount` bands. A layout's active
/// bands occupy indices `0..<config.bandCount`; remaining physical bands are
/// programmed as bypassed placeholders.
public enum EQBandProgram {
    /// The fixed number of physical bands the shared EQ node is built with.
    /// Must be >= the largest supported layout's band count (modern21 = 21).
    public static let physicalBandCount = EQConfiguration.modern21.bandCount

    /// Per-physical-band program for `config`, padded to `physicalBandCount`.
    public static func program(for config: EQConfiguration) -> [EQBandSetting] {
        precondition(
            config.bandCount <= physicalBandCount,
            "EQ layout \(config.name) has \(config.bandCount) bands, exceeding physical band count \(physicalBandCount)"
        )

        var settings: [EQBandSetting] = []
        settings.reserveCapacity(physicalBandCount)

        let lastIndex = config.bandCount - 1
        for (index, frequency) in config.frequencies.enumerated() {
            let role: EQBandRole
            if index == 0 {
                role = .lowShelf
            } else if index == lastIndex {
                role = .highShelf
            } else {
                role = .parametric
            }
            let bandwidth: Float = role == .parametric ? config.parametricBandwidth : 1.0
            settings.append(EQBandSetting(frequency: frequency, role: role, bandwidth: bandwidth, bypass: false))
        }

        // Pad unused physical bands as bypassed placeholders.
        while settings.count < physicalBandCount {
            settings.append(EQBandSetting(frequency: 1000, role: .bypassed, bandwidth: 1.0, bypass: true))
        }

        return settings
    }
}
