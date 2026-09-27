import Foundation
import XCTest
@testable import NullPlayer

final class WMPPhase0ArchiveTests: XCTestCase {
    private var fixtures: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/WMPSkin", isDirectory: true)
    }

    func testLockedLimitsMatchDecisionRecord() {
        XCTAssertEqual(WMPPhase0Limits.archiveEntries, 4_096)
        XCTAssertEqual(WMPPhase0Limits.entryUncompressedBytes, 32 * 1_024 * 1_024)
        XCTAssertEqual(WMPPhase0Limits.archiveUncompressedBytes, 128 * 1_024 * 1_024)
        XCTAssertEqual(WMPPhase0Limits.entryCompressionRatio, 200)
        XCTAssertEqual(WMPPhase0Limits.entryCompressionRatioFloorBytes, 1 * 1_024 * 1_024)
        XCTAssertEqual(WMPPhase0Limits.wrapperDirectories, 1)
        XCTAssertEqual(WMPPhase0Limits.xmlDepth, 256)
        XCTAssertEqual(WMPPhase0Limits.xmlNodes, 100_000)
        XCTAssertEqual(WMPPhase0Limits.imageDimension, 32_768)
        XCTAssertEqual(WMPPhase0Limits.imagePixels, 32_000_000)
        XCTAssertEqual(WMPPhase0Limits.scriptBytes, 4 * 1_024 * 1_024)
        XCTAssertEqual(WMPPhase0Limits.expressionDependencyDepth, 128)
        XCTAssertEqual(WMPPhase0Limits.expressionPasses, 256)
        XCTAssertEqual(WMPPhase0Limits.activeTimers, 256)
        XCTAssertEqual(WMPPhase0Limits.minimumTimerPeriodMilliseconds, 8)
        XCTAssertEqual(WMPPhase0Limits.preferenceValueBytes, 64 * 1_024)
        XCTAssertEqual(WMPPhase0Limits.scriptMessageBytes, 1 * 1_024 * 1_024)
        XCTAssertEqual(WMPPhase0Limits.scriptInFlightBytes, 16 * 1_024 * 1_024)
    }

    func testOriginalValidArchivesPassWithoutExtraction() throws {
        for name in ["widgets.wmz", "wrapper-directory.wmz", "two-view.wmz"] {
            XCTAssertNoThrow(try WMPPhase0ArchiveAuditor.audit(url: fixtures.appendingPathComponent(name)), name)
        }
    }

    /// The half of the image bounds that is easy to lose: a WMP slider or progress bar is authored
    /// as one horizontal filmstrip of frames, so a legitimate resource is thousands of pixels wide
    /// and a few dozen tall. An axis bound set to a texture size rejects the idiom while protecting
    /// nothing — 15990x20 is 320 Kpx against a 32 Mpx area bound — and it cost `pharaoh`, `Ice` and
    /// `The_Doobie_Brothers` their whole load and `Nautical` its only view (W33). `imagePixels`
    /// stays the memory guard and `oversized-image-axis.wmz` pins the axis bound above.
    func testFilmstripImageIsAdmittedByBothImageBounds() {
        XCTAssertNoThrow(try WMPPhase0ArchiveAuditor.audit(
            url: fixtures.appendingPathComponent("filmstrip-image.wmz")))
        XCTAssertNoThrow(try WMPArchive(url: fixtures.appendingPathComponent("filmstrip-image.wmz")))
    }

    func testEncodingFixturesCarryExpectedBOMs() throws {
        XCTAssertFalse(try Data(contentsOf: fixtures.appendingPathComponent("utf8.wms")).starts(with: [0xFF, 0xFE]))
        XCTAssertTrue(try Data(contentsOf: fixtures.appendingPathComponent("utf16le.wms")).starts(with: [0xFF, 0xFE]))
        XCTAssertTrue(try Data(contentsOf: fixtures.appendingPathComponent("utf16be.wms")).starts(with: [0xFE, 0xFF]))
    }

    func testHostileArchivesHaveStableTypedFailures() {
        let cases: [(String, WMPPhase0DiagnosticCode)] = [
            ("traversal.wmz", .pathTraversal),
            ("absolute-path.wmz", .absolutePath),
            ("drive-path.wmz", .drivePath),
            ("case-collision.wmz", .caseCollision),
            ("symlink.wmz", .symbolicLink),
            ("wrapper-too-deep.wmz", .wrapperDepthExceeded),
            ("excess-entries.wmz", .tooManyEntries),
            ("excess-ratio.wmz", .compressionRatioExceeded),
            ("excess-entry-bytes.wmz", .entryTooLarge),
            ("excess-archive-bytes.wmz", .archiveTooLarge),
            ("deep-xml.wmz", .xmlDepthExceeded),
            ("excess-xml-nodes.wmz", .xmlNodeLimitExceeded),
            ("oversized-image.wmz", .oversizedImage),
            ("oversized-image-axis.wmz", .oversizedImage),
            ("oversized-script.wmz", .oversizedScript),
            ("crc-corrupt.wmz", .crcMismatch),
        ]

        for (name, expectedCode) in cases {
            XCTAssertThrowsError(try WMPPhase0ArchiveAuditor.audit(url: fixtures.appendingPathComponent(name)), name) { error in
                XCTAssertEqual((error as? WMPPhase0Diagnostic)?.code, expectedCode, "wrong diagnostic for \(name): \(error)")
            }
        }
    }

    /// The ratio bound is only asked about entries past `entryCompressionRatioFloorBytes`, because
    /// below it a ratio measures how *boring* an image is rather than how dangerous it is. An
    /// uncompressed flat-colour BMP squashes 240:1 to 850:1 and 13 of the 180 installed archives
    /// were rejected for a blank background — every over-200:1 entry in that whole corpus is a
    /// `.bmp`, the largest expanding to 842,636 bytes against a 32 MiB per-entry bound.
    ///
    /// `small-high-ratio.wmz` is 64 KiB at ~830:1 and must be admitted; `excess-ratio.wmz` is the
    /// same shape at 2 MiB and must still be rejected. Both halves, because a floor that admits
    /// everything is not a floor.
    func testTheRatioBoundAppliesOnlyAboveItsSizeFloor() throws {
        XCTAssertNoThrow(try WMPPhase0ArchiveAuditor.audit(
            url: fixtures.appendingPathComponent("small-high-ratio.wmz")))
        XCTAssertThrowsError(try WMPPhase0ArchiveAuditor.audit(
            url: fixtures.appendingPathComponent("excess-ratio.wmz"))) { error in
            XCTAssertEqual((error as? WMPPhase0Diagnostic)?.code, .compressionRatioExceeded)
        }
    }
}
