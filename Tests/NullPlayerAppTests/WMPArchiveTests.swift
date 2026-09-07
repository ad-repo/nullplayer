import Foundation
import XCTest
import ZIPFoundation
@testable import NullPlayer

final class WMPArchiveTests: XCTestCase {
    func testAcceptsRootAndOneWrapperWithCaseInsensitiveReadOnlyLookup() throws {
        let rootURL = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("Skin.WMS", data: Data("<THEME/>".utf8)),
            WMPTestArchiveEntry("Images/BG.BMP", data: Data([1, 2, 3]))
        ])
        let root = try WMPArchive(url: rootURL)
        XCTAssertNil(root.rootPrefix)
        XCTAssertEqual(root.skinDefinitionPath, "Skin.WMS")
        XCTAssertEqual(try root.data(for: "images\\bg.bmp"), Data([1, 2, 3]))

        let wrappedURL = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("Wrapper/theme.wms", data: Data("<THEME/>".utf8)),
            WMPTestArchiveEntry("Wrapper/art/a.bmp", data: Data([4]))
        ])
        let wrapped = try WMPArchive(url: wrappedURL)
        XCTAssertEqual(wrapped.rootPrefix, "Wrapper")
        XCTAssertEqual(wrapped.resourcePaths, ["art/a.bmp", "theme.wms"])
    }

    /// Four of the 180 corpus archives overwrite the signature of the local file header at offset 0
    /// with `01 00 01 00`, which ends ZIPFoundation's iteration before its first entry: the loader
    /// then saw an archive with no entries at all and reported `WMP0021` "no .wms at the root" for
    /// a skin whose `.wms` is at the root. No third-party archive is committed, so the shape is
    /// rebuilt here — a real ZIP with that one signature scribbled over.
    func testLoadsAnArchiveWhoseFirstLocalHeaderSignatureIsOverwritten() throws {
        let url = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("art/bg.bmp", data: Data([1, 2, 3, 4, 5])),
            WMPTestArchiveEntry("theme.wms", data: Data("<THEME/>".utf8))
        ])
        var bytes = try Data(contentsOf: url)
        XCTAssertEqual(Array(bytes.prefix(4)), [0x50, 0x4B, 0x03, 0x04], "fixture is not a plain ZIP")
        bytes.replaceSubrange(bytes.startIndex ..< (bytes.startIndex + 4), with: [0x01, 0x00, 0x01, 0x00])
        let damaged = url.deletingLastPathComponent().appendingPathComponent("damaged.wmz")
        try bytes.write(to: damaged)

        let archive = try WMPArchive(url: damaged)
        XCTAssertEqual(archive.skinDefinitionPath, "theme.wms")
        XCTAssertEqual(archive.resourcePaths, ["art/bg.bmp", "theme.wms"])
        // The repaired entry is the one that was damaged; its bytes must still inflate and pass CRC.
        XCTAssertEqual(try archive.data(for: "art/bg.bmp"), Data([1, 2, 3, 4, 5]))
    }

    /// The repair rewrites a signature only where the header already agrees with the central
    /// directory record pointing at it, so a file that merely fails to be a ZIP stays a failure.
    func testDoesNotInventEntriesInAFileThatIsNotAZIP() throws {
        let directory = try WMPSkinTestSupport.temporaryDirectory()
        let junk = directory.appendingPathComponent("junk.wmz")
        try Data(repeating: 0x01, count: 8_192).write(to: junk)
        XCTAssertEqual(WMPSkinTestSupport.failureCode { try WMPArchive(url: junk) }, .invalidArchive)
    }

    func testRejectsUnsafePathsSymlinksCaseCollisionsAndBadRootShapes() throws {
        XCTAssertEqual(code(["theme.wms", "../escape"]), .pathTraversal)
        XCTAssertEqual(code(["theme.wms", "/absolute"]), .absolutePath)
        XCTAssertEqual(code(["theme.wms", "C:\\drive"]), .drivePath)

        let symlink = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("theme.wms", data: Data("<THEME/>".utf8)),
            WMPTestArchiveEntry("link", data: Data("target".utf8), type: .symlink)
        ])
        XCTAssertEqual(WMPSkinTestSupport.failureCode { try WMPArchive(url: symlink) }, .symbolicLink)

        let collision = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("theme.wms", data: Data("<THEME/>".utf8)),
            WMPTestArchiveEntry("Art/A.bmp", data: Data([1])),
            WMPTestArchiveEntry("art/a.BMP", data: Data([2]))
        ])
        XCTAssertEqual(WMPSkinTestSupport.failureCode { try WMPArchive(url: collision) }, .caseCollision)

        XCTAssertEqual(code(["a.wms", "b.wms"]), .ambiguousSkinDefinition)
        XCTAssertEqual(code(["one/two/theme.wms"]), .wrapperDepthExceeded)
        XCTAssertEqual(code(["Wrapper/theme.wms", "outside.bmp"]), .wrapperDepthExceeded)
        XCTAssertEqual(code(["readme.txt"]), .invalidRoot)
    }

    func testPhaseZeroCorpusRetainsEveryLockedArchiveFailureCode() async throws {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/WMPSkin", isDirectory: true)
        let archiveCases: [(String, WMPDiagnosticCode)] = [
            ("traversal.wmz", .pathTraversal), ("absolute-path.wmz", .absolutePath),
            ("drive-path.wmz", .drivePath), ("case-collision.wmz", .caseCollision),
            ("symlink.wmz", .symbolicLink), ("wrapper-too-deep.wmz", .wrapperDepthExceeded),
            ("excess-entries.wmz", .entryLimitExceeded),
            ("excess-ratio.wmz", .compressionRatioExceeded),
            ("excess-entry-bytes.wmz", .entryTooLarge),
            ("excess-archive-bytes.wmz", .totalSizeExceeded),
            ("oversized-image.wmz", .oversizedImage),
            ("oversized-script.wmz", .oversizedScript), ("crc-corrupt.wmz", .crcMismatch)
        ]
        for (name, expected) in archiveCases {
            let actual = WMPSkinTestSupport.failureCode {
                try WMPArchive(url: fixtures.appendingPathComponent(name))
            }
            XCTAssertEqual(actual, expected, name)
            XCTAssertEqual(actual?.rawValue,
                WMPPhase0DiagnosticCode.allCases.first { $0.rawValue == expected.rawValue }?.rawValue,
                "Phase 1 changed the stable Phase 0 code for \(name)")
        }
        let depthCode = await WMPSkinTestSupport.failureCode {
            try await WMPSkinLoader().load(from: fixtures.appendingPathComponent("deep-xml.wmz"))
        }
        XCTAssertEqual(depthCode, .xmlDepthExceeded)
        let nodeCode = await WMPSkinTestSupport.failureCode {
            try await WMPSkinLoader().load(from: fixtures.appendingPathComponent("excess-xml-nodes.wmz"))
        }
        XCTAssertEqual(nodeCode, .expandedNodeLimitExceeded)
    }

    func testRejectsEveryDeclaredArchiveLimit() throws {
        let countURL = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("theme.wms", data: Data("<THEME/>".utf8)),
            WMPTestArchiveEntry("a"), WMPTestArchiveEntry("b")
        ])
        var limits = WMPArchiveLimits.production
        limits.maximumEntryCount = 2
        XCTAssertEqual(WMPSkinTestSupport.failureCode { try WMPArchive(url: countURL, limits: limits) },
                       .entryLimitExceeded)

        let sizedURL = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("theme.wms", data: Data(repeating: 1, count: 16))
        ])
        limits = .production; limits.maximumEntrySize = 8
        XCTAssertEqual(WMPSkinTestSupport.failureCode { try WMPArchive(url: sizedURL, limits: limits) },
                       .entryTooLarge)
        limits = .production; limits.maximumTotalSize = 8
        XCTAssertEqual(WMPSkinTestSupport.failureCode { try WMPArchive(url: sizedURL, limits: limits) },
                       .totalSizeExceeded)

        let compressedURL = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("theme.wms", data: Data(repeating: 0, count: 8_192), compression: .deflate)
        ])
        // Production limits never ask an 8 KiB entry about its ratio: below
        // `entryCompressionRatioFloorBytes` a ratio measures how boring an image is, not how
        // dangerous, and that rejected 13 of the 180 installed archives for a blank background.
        XCTAssertNoThrow(try WMPArchive(url: compressedURL, limits: .production))
        limits = .production; limits.maximumCompressionRatio = 2; limits.compressionRatioFloor = 0
        XCTAssertEqual(WMPSkinTestSupport.failureCode { try WMPArchive(url: compressedURL, limits: limits) },
                       .compressionRatioExceeded)
    }

    func testProviderResolutionUsesDeclaringDirectoryThenRootAndCannotEscape() throws {
        let provider = WMPMemoryResourceProvider([
            "views/main.wms": Data(), "views/local.bmp": Data(), "shared/root.bmp": Data()
        ])
        XCTAssertEqual(try provider.resolve("local.bmp", relativeTo: "views/main.wms"), "views/local.bmp")
        XCTAssertEqual(try provider.resolve("shared/root.bmp", relativeTo: "views/main.wms"), "shared/root.bmp")
        XCTAssertEqual(WMPSkinTestSupport.failureCode {
            try provider.resolve("../../escape", relativeTo: "views/main.wms") as Any
        }, .resourceEscapesProvider)
        // An empty attribute names no entry: nothing to resolve, and nothing to reject. Throwing
        // here is what killed 39 views across 36 corpus skins (W7).
        XCTAssertNil(try provider.resolve("", relativeTo: "views/main.wms"))
        XCTAssertNil(try provider.resolve("   ", relativeTo: "views/main.wms"))
        XCTAssertEqual(WMPSkinTestSupport.failureCode {
            try provider.resolve("C:/windows/win.ini", relativeTo: "views/main.wms") as Any
        }, .resourceEscapesProvider)
    }

    private func code(_ paths: [String]) -> WMPDiagnosticCode? {
        let entries = paths.enumerated().map { index, path in
            WMPTestArchiveEntry(path, data: index == 0 ? Data("<THEME/>".utf8) : Data([1]))
        }
        guard let url = try? WMPSkinTestSupport.makeArchive(entries) else { return nil }
        return WMPSkinTestSupport.failureCode { try WMPArchive(url: url) }
    }
}
