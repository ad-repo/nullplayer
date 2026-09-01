import AppKit
import CoreGraphics
import Foundation
import XCTest
@testable import NullPlayer

final class WMPPhase7Tests: XCTestCase {
    private var helperURL: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/debug/WMPScriptIsolationHelper")
    }

    func testCorpusReportEmitsFactsDemandMetricsAndConfidenceWithoutPixels() async throws {
        let xml = """
        <THEME><VIEW id="main" width="80" height="40">
          <TEXT id="label" left="2" top="2" width="50" height="14" value="Ready"/>
          <BUTTON id="play" left="2" top="20" width="20" height="16" onclick="player.controls.play();"/>
        </VIEW></THEME>
        """
        let url = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data(xml.utf8))
        ], filename: "OriginalPhase7.wmz")
        let output = try WMPSkinTestSupport.temporaryDirectory().appendingPathComponent("report.json")
        let report = try await WMPCorpusReportHarness().writeReport(for: [url], to: output)
        XCTAssertEqual(report.formatVersion, 1)
        XCTAssertEqual(report.skinCount, 1)
        XCTAssertEqual(report.acceptedCount, 1)
        let skin = try XCTUnwrap(report.skins.first)
        XCTAssertEqual(skin.sha256.count, 64)
        XCTAssertEqual(skin.archive?.entryCount, 1)
        XCTAssertEqual(skin.renderMetrics.count, 1)
        XCTAssertEqual(skin.renderMetrics.first?.resolvedNodeCount, 3)
        XCTAssertTrue(skin.unknownTags.isEmpty)
        XCTAssertTrue(skin.unknownMembers.isEmpty)
        XCTAssertEqual(skin.confidence, .high)
        let encoded = try Data(contentsOf: output)
        XCTAssertNotNil(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains(url.deletingLastPathComponent().path),
                       "Corpus reports must not disclose local corpus paths")
    }

    func testOptInLocalCorpusProducesTypedReport() async throws {
        let environment = ProcessInfo.processInfo.environment
        let root = environment["WMP_CORPUS_PATH"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("skins", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else {
            throw XCTSkip("Set WMP_CORPUS_PATH to a directory of user-supplied .wmz skins.")
        }
        let urls = try FileManager.default.contentsOfDirectory(at: root,
            includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            .filter { $0.pathExtension.caseInsensitiveCompare("wmz") == .orderedSame }
        guard !urls.isEmpty else { throw XCTSkip("The opt-in WMP corpus contains no .wmz files.") }
        let outputRoot: URL
        if let configured = environment["WMP_CORPUS_REPORT_DIR"] {
            outputRoot = URL(fileURLWithPath: configured, isDirectory: true)
        } else {
            outputRoot = try WMPSkinTestSupport.temporaryDirectory()
        }
        let output = outputRoot.appendingPathComponent("wmp-corpus-report.json")
        let report = try await WMPCorpusReportHarness().writeReport(for: urls, to: output)
        XCTAssertEqual(report.skinCount, urls.count)
        XCTAssertGreaterThan(report.acceptedCount, 0)
        XCTAssertTrue(report.skins.allSatisfy { $0.archive != nil || !$0.diagnostics.isEmpty })
        XCTAssertTrue(report.skins.allSatisfy { $0.sha256.count == 64 })
        print("WMP corpus report (untracked): \(output.path)")
    }

    func testDeterministicFuzzInputsReturnSuccessOrTypedFailure() throws {
        var generator = Phase7Generator(seed: 0x574D_5037)
        let imageProvider = WMPMemoryResourceProvider(["fuzz.png": Data([0x89, 0x50, 0x4E, 0x47])])
        let imageStore = WMPImageStore(provider: imageProvider)
        for iteration in 0..<512 {
            let count = generator.integer(96)
            let bytes = Data((0..<count).map { _ in generator.byte() })

            do {
                _ = try WMPTextDecoder.decode(bytes, path: "fuzz-\(iteration).wms")
            } catch {
                XCTAssertTrue(error is WMPFailure, "Text fuzz returned untyped error: \(error)")
            }

            let raw = String(decoding: bytes, as: UTF8.self)
            do {
                _ = try WMPXMLParser(limits: .init(maximumNestingDepth: 16, maximumNodeCount: 128))
                    .parse("<THEME>\(raw)</THEME>", path: "fuzz.wms")
            } catch {
                XCTAssertTrue(error is WMPFailure, "XML fuzz returned untyped error: \(error)")
            }

            do {
                let normalized = try WMPPath.validateArchivePath(raw)
                XCTAssertFalse(normalized.hasPrefix("/"))
                XCTAssertFalse(normalized.split(separator: "/").contains(".."))
            } catch {
                XCTAssertTrue(error is WMPFailure, "Path fuzz returned untyped error: \(error)")
            }

            _ = WMPAttributeParser.parse(name: iteration.isMultiple(of: 2) ? "color" : "onclick", value: raw)
            let rgb = (0..<48).map { _ in generator.byte() }
            let alpha = (0..<16).map { _ in generator.byte() }
            let mapping = WMPMappingImage(width: 4, height: 4, rgb: rgb, alpha: alpha,
                nodeByColor: [WMPColor(red: rgb[0], green: rgb[1], blue: rgb[2]): 1])
            _ = mapping.node(at: WMPPoint(x: CGFloat(generator.integer(8)),
                                          y: CGFloat(generator.integer(8))),
                             in: WMPRect(x: 0, y: 0, width: 8, height: 8))
        }
        XCTAssertThrowsError(try imageStore.image(for: "fuzz.png")) {
            XCTAssertTrue($0 is WMPFailure, "Image fuzz returned untyped error: \($0)")
        }
    }

    func testArchiveMetadataAndPayloadMutationsNeverReturnUntypedFailure() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/WMPSkin/widgets.wmz")
        let original = try Data(contentsOf: fixture)
        XCTAssertGreaterThan(original.count, 64)
        let directory = try WMPSkinTestSupport.temporaryDirectory()
        let mutationURL = directory.appendingPathComponent("mutation.wmz")
        var generator = Phase7Generator(seed: 0x5A49_5037)
        for _ in 0..<128 {
            var mutation = original
            let offset = generator.integer(mutation.count)
            mutation[offset] ^= UInt8(1 << generator.integer(8))
            try mutation.write(to: mutationURL, options: .atomic)
            do {
                _ = try WMPArchive(url: mutationURL)
            } catch {
                XCTAssertTrue(error is WMPFailure, "Archive mutation returned untyped error: \(error)")
            }
        }
    }

    func testHundredRapidLoadsViewsResizesAndCacheTeardownRemainBounded() async throws {
        let pixels = [UInt8](repeating: 0x7F, count: 16 * 16 * 4)
        let png = try WMPSkinTestSupport.encodedImage(width: 16, height: 16, rgba: pixels)
        let archive = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data("""
            <THEME><VIEW id="full" width="160" height="80" minWidth="100" minHeight="50" maxWidth="320" maxHeight="160">
            <IMAGE id="art" left="0" top="0" width="160" height="80" image="art.png"/>
            <BUTTON id="play" left="4" top="4" width="20" height="20"/></VIEW>
            <VIEW id="tiny" width="80" height="30"><TEXT left="1" top="1" width="60" height="12" value="Tiny"/></VIEW></THEME>
            """.utf8)),
            WMPTestArchiveEntry("art.png", data: png)
        ])
        let descriptorsBefore = openDescriptorCount()
        for iteration in 0..<100 {
            autoreleasepool {
                _ = iteration
            }
            let skin = try await WMPSkinLoader().load(from: archive)
            let store = WMPImageStore(provider: skin.archive,
                limits: .init(maximumDimension: 128, maximumPixels: 16_384,
                              maximumDecodedBytes: 65_536, cacheBytes: 4_096))
            let viewID = iteration.isMultiple(of: 2) ? "full" : "tiny"
            let size = WMPSize(width: CGFloat(100 + iteration * 3), height: CGFloat(50 + iteration))
            let scene = try await WMPSceneBuilder(loadedSkin: skin, imageStore: store)
                .build(viewID: viewID, requestedSize: size)
            if iteration.isMultiple(of: 10) {
                _ = try await WMPRenderer(imageStore: store).render(scene: scene,
                    backingScale: iteration.isMultiple(of: 20) ? 2 : 1)
            }
            XCTAssertLessThanOrEqual(store.metrics.currentCacheBytes, 4_096)
            store.removeAll()
            XCTAssertEqual(store.metrics.currentCacheBytes, 0)
            XCTAssertEqual(store.metrics.currentMappingBytes, 0)
        }
        let descriptorsAfter = openDescriptorCount()
        XCTAssertLessThanOrEqual(descriptorsAfter, descriptorsBefore + 8,
            "Rapid load teardown leaked file descriptors")
    }

    func testBridgeRejectsOversizedInputBeforeLaunchAndLeavesNoProcess() {
        let isolation = WMPScriptIsolation(helperURL: helperURL)
        let result = isolation.evaluate(script: String(repeating: "x",
            count: WMPPhase0Limits.scriptMessageBytes + 1))
        guard case let .failed(diagnostic) = result else { return XCTFail("Oversized input was accepted") }
        XCTAssertEqual(diagnostic.code, .scriptMessageTooLarge)
        XCTAssertEqual(isolation.activeProcessCount, 0)
    }

    func testBridgeStopsReadingOversizedHelperResponse() throws {
        let directory = try WMPSkinTestSupport.temporaryDirectory()
        let helper = directory.appendingPathComponent("oversized-helper")
        try Data("#!/bin/sh\nhead -c 1048582 /dev/zero\nsleep 5\n".utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        let isolation = WMPScriptIsolation(helperURL: helper, timeout: 1, terminationGrace: 0.05)
        let started = Date()
        let result = isolation.evaluate(script: "1")
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.5)
        guard case let .failed(diagnostic) = result else { return XCTFail("Oversized response was accepted") }
        XCTAssertTrue(diagnostic.code == .scriptCrashed || diagnostic.code == .scriptProtocolViolation)
        XCTAssertEqual(isolation.activeProcessCount, 0)
    }

    @MainActor
    func testAccessibilityTreeIsStableUniqueAndReplacedWithScene() throws {
        let first = phase7Scene(viewID: "full", ids: [(1, "play", "button"), (2, "seek", "slider")])
        let second = phase7Scene(viewID: "tiny", ids: [(3, "stop", "button")])
        let context = try XCTUnwrap(CGContext(data: nil, width: 100, height: 50, bitsPerComponent: 8,
            bytesPerRow: 400, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 50),
            styleMask: .borderless, backing: .buffered, defer: false)
        let view = WMPMainView(frame: window.contentView?.bounds ?? .zero)
        window.contentView = view
        view.present(image, scene: first)
        let firstIDs = accessibilityIDs(view)
        XCTAssertEqual(Set(firstIDs), ["wmp.play", "wmp.seek"])
        XCTAssertEqual(firstIDs.count, Set(firstIDs).count)
        view.present(image, scene: second)
        XCTAssertEqual(Set(accessibilityIDs(view)), ["wmp.stop"])
        view.prepareForUITeardown()
        XCTAssertTrue(view.accessibilityChildren()?.isEmpty == true)
    }

    private func phase7Scene(viewID: String, ids: [(Int, String, String)]) -> WMPScene {
        let size = WMPSize(width: 100, height: 50)
        let hits = ids.map { stableID, nodeID, kind in
            WMPHitMetadata(stableID: stableID, nodeID: nodeID, kind: kind,
                frame: .init(x: CGFloat(stableID * 10), y: 5, width: 10, height: 10), clipRect: nil,
                zIndex: 0, documentOrder: stableID, action: kind == "slider" ? .seek : .play,
                sticky: false, enabled: true, mappingImage: nil, mappingTargets: [])
        }
        return WMPScene(viewID: viewID, canvasSize: size,
            resizeLimits: .init(minimum: size, maximum: size), commands: [], hits: hits,
            geometries: [:], unresolved: [], diagnostics: [], dirtyBounds: nil,
            metrics: .init(resolvedNodeCount: hits.count, unresolvedNodeCount: 0, visibleBounds: nil),
            wasBuiltOnMainThread: false)
    }

    @MainActor
    private func accessibilityIDs(_ view: WMPMainView) -> [String] {
        (view.accessibilityChildren() ?? []).compactMap {
            ($0 as? NSAccessibilityElement)?.accessibilityIdentifier()
        }
    }

    private func openDescriptorCount() -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count) ?? 0
    }
}

private struct Phase7Generator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func byte() -> UInt8 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return UInt8(truncatingIfNeeded: state >> 24)
    }
    mutating func integer(_ upperBound: Int) -> Int {
        guard upperBound > 0 else { return 0 }
        return Int(byte()) % upperBound
    }
}
