import XCTest
@testable import NullPlayerCore

final class EQConfigurationTests: XCTestCase {
    func testRemapIdentityForClassicLayout() {
        let gains: [Float] = [-3, -1, 0, 1, 2, 3, 4, 2, 1, 0]

        let remapped = EQBandRemapper.remap(gains: gains, from: .classic10, to: .classic10)

        XCTAssertEqual(remapped, gains)
    }

    func testRemapIdentityForModernLayout() {
        let gains = (0..<EQConfiguration.modern21.bandCount).map { Float($0) - 10 }

        let remapped = EQBandRemapper.remap(gains: gains, from: .modern21, to: .modern21)

        XCTAssertEqual(remapped, gains)
    }

    func testFlatRemapStaysFlatAcrossLayouts() {
        let classicFlat = Array(repeating: Float(0), count: EQConfiguration.classic10.bandCount)
        let modern = EQBandRemapper.remap(gains: classicFlat, from: .classic10, to: .modern21)
        XCTAssertTrue(modern.allSatisfy { abs($0) < 0.0001 })

        let remappedBack = EQBandRemapper.remap(gains: modern, from: .modern21, to: .classic10)
        XCTAssertTrue(remappedBack.allSatisfy { abs($0) < 0.0001 })
    }

    func testBassHeavyRemapPreservesLowEndBias() {
        let bassHeavy: [Float] = [8, 6, 4, 2, 0, -1, -1, 0, 0, 0]

        let modern = EQBandRemapper.remap(gains: bassHeavy, from: .classic10, to: .modern21)

        XCTAssertGreaterThan(modern[0], modern[10])
        XCTAssertGreaterThan(modern[3], modern[14])
        XCTAssertGreaterThan(modern[5], modern[20])
    }

    func testTrebleHeavyRemapPreservesHighEndBias() {
        let trebleHeavy: [Float] = [-2, -2, -1, 0, 0, 1, 3, 5, 6, 7]

        let modern = EQBandRemapper.remap(gains: trebleHeavy, from: .classic10, to: .modern21)
        let classic = EQBandRemapper.remap(gains: modern, from: .modern21, to: .classic10)

        XCTAssertGreaterThan(modern[20], modern[8])
        XCTAssertGreaterThan(classic[9], classic[0])
        XCTAssertEqual(classic[9], trebleHeavy[9], accuracy: 0.35)
    }

    func testPersistedLayoutLookupMatchesKnownCounts() {
        XCTAssertEqual(EQConfiguration.persistedLayout(forBandCount: 10), .classic10)
        XCTAssertEqual(EQConfiguration.persistedLayout(forBandCount: 21), .modern21)
        XCTAssertNil(EQConfiguration.persistedLayout(forBandCount: 17))
    }

    func testClassicLayoutMatchesAudioEngineConfiguration() {
        XCTAssertEqual(EQConfiguration.classic10.bandCount, 10)
        XCTAssertEqual(EQConfiguration.classic10.frequencies, [
            60, 170, 310, 600, 1_000, 3_000, 6_000, 12_000, 14_000, 16_000
        ])
        XCTAssertEqual(EQConfiguration.classic10.parametricBandwidth, 1.75)
    }

    func testModernLayoutMatchesAudioEngineConfiguration() {
        XCTAssertEqual(EQConfiguration.modern21.bandCount, 21)
        XCTAssertEqual(EQConfiguration.modern21.frequencies, [
            31.5, 45, 63, 90, 125, 180, 250, 355, 500, 710, 1_000,
            1_400, 2_000, 2_800, 4_000, 5_600, 8_000, 11_200, 14_000,
            16_000, 20_000
        ])
        XCTAssertEqual(EQConfiguration.modern21.parametricBandwidth, 1.0)
    }

    // MARK: - EQBandProgram (fixed 21-band node programming)

    func testPhysicalBandCountIsTwentyOne() {
        XCTAssertEqual(EQBandProgram.physicalBandCount, 21)
        XCTAssertEqual(EQBandProgram.physicalBandCount, EQConfiguration.modern21.bandCount)
    }

    func testModernProgramFillsAllPhysicalBandsActive() {
        let program = EQBandProgram.program(for: .modern21)
        XCTAssertEqual(program.count, EQBandProgram.physicalBandCount)
        XCTAssertTrue(program.allSatisfy { !$0.bypass })
        XCTAssertEqual(program.map { $0.frequency }, EQConfiguration.modern21.frequencies)
    }

    func testClassicProgramActivatesTenBandsAndBypassesRest() {
        let program = EQBandProgram.program(for: .classic10)
        XCTAssertEqual(program.count, EQBandProgram.physicalBandCount)

        // Bands 0-9 active at classic frequencies.
        for index in 0..<10 {
            XCTAssertFalse(program[index].bypass, "classic band \(index) should be active")
            XCTAssertEqual(program[index].frequency, EQConfiguration.classic10.frequencies[index])
        }
        // Bands 10-20 bypassed.
        for index in 10..<21 {
            XCTAssertTrue(program[index].bypass, "physical band \(index) should be bypassed in classic")
            XCTAssertEqual(program[index].role, .bypassed)
        }
    }

    func testFilterRolesAndBandwidthClassic() {
        let program = EQBandProgram.program(for: .classic10)
        XCTAssertEqual(program[0].role, .lowShelf)
        XCTAssertEqual(program[0].bandwidth, 1.0)        // shelf bands use 1.0
        XCTAssertEqual(program[9].role, .highShelf)
        XCTAssertEqual(program[9].bandwidth, 1.0)
        // Mid bands parametric at the classic bandwidth.
        XCTAssertEqual(program[1].role, .parametric)
        XCTAssertEqual(program[1].bandwidth, 1.75)
        XCTAssertEqual(program[5].bandwidth, 1.75)
    }

    func testFilterRolesAndBandwidthModern() {
        let program = EQBandProgram.program(for: .modern21)
        XCTAssertEqual(program[0].role, .lowShelf)
        XCTAssertEqual(program[20].role, .highShelf)
        XCTAssertEqual(program[1].role, .parametric)
        XCTAssertEqual(program[1].bandwidth, 1.0)        // modern parametric bandwidth
        XCTAssertEqual(program[10].bandwidth, 1.0)
    }

    // MARK: - Canonical gain round-trip (no re-remap)

    /// Mirrors the AudioEngine canonical-gain bookkeeping: each layout keeps its own
    /// exact gains; a round-trip switch restores them bit-identically without re-remapping.
    func testCanonicalGainsSurviveRoundTripWithoutReRemap() {
        var canonical: [String: [Float]] = [:]
        let classicGains: [Float] = [-3, -1, 0, 1, 2, 3, 4, 2, 1, 0]
        canonical[EQConfiguration.classic10.name] = classicGains

        // classic → modern: seed modern from classic (first use).
        let modernSeed = EQBandRemapper.remap(gains: classicGains, from: .classic10, to: .modern21)
        canonical[EQConfiguration.modern21.name] = modernSeed

        // Edit a modern band; classic's canonical array is untouched.
        canonical[EQConfiguration.modern21.name]?[5] = 9

        // modern → classic: classic already seeded, so restore exactly (no re-remap).
        let restoredClassic = canonical[EQConfiguration.classic10.name]
        XCTAssertEqual(restoredClassic, classicGains)

        // modern's edited gains also persist exactly.
        XCTAssertEqual(canonical[EQConfiguration.modern21.name]?[5], 9)
    }

    func testFirstUseSeedingUsesRemapper() {
        let classicGains: [Float] = [8, 6, 4, 2, 0, -1, -1, 0, 0, 0]
        let seeded = EQBandRemapper.remap(gains: classicGains, from: .classic10, to: .modern21)
        XCTAssertEqual(seeded.count, EQConfiguration.modern21.bandCount)
        // Bass bias preserved through the seeding remap.
        XCTAssertGreaterThan(seeded[0], seeded[20])
    }
}
