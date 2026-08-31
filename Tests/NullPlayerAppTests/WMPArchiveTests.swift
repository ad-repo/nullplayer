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
        limits = .production; limits.maximumCompressionRatio = 2
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
    }

    private func code(_ paths: [String]) -> WMPDiagnosticCode? {
        let entries = paths.enumerated().map { index, path in
            WMPTestArchiveEntry(path, data: index == 0 ? Data("<THEME/>".utf8) : Data([1]))
        }
        guard let url = try? WMPSkinTestSupport.makeArchive(entries) else { return nil }
        return WMPSkinTestSupport.failureCode { try WMPArchive(url: url) }
    }
}
