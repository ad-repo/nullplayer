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
}
