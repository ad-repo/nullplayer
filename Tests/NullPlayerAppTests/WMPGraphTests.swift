import Foundation
import XCTest
@testable import NullPlayer

final class WMPGraphTests: XCTestCase {
    func testGraphIsDeterministicRetainsUnknownNodesAndReportsDuplicateIDs() throws {
        let xml = """
        <THEME><VIEW id="main" width="JScript:view.width-4;">
          <SUBVIEW id="dup"><MYSTERY id="dup" foo="bar"/></SUBVIEW>
        </VIEW></THEME>
        """
        let document = try WMPXMLParser().parse(xml, path: "theme.wms")
        let first = WMPObjectGraph(document: document)
        let second = WMPObjectGraph(document: try WMPXMLParser().parse(xml, path: "theme.wms"))
        XCTAssertEqual(first.dump(), second.dump())
        XCTAssertEqual(first.nodes(id: "DUP").count, 2)
        XCTAssertEqual(first.diagnostics.map(\.code), [.duplicateIdentifier])
        XCTAssertEqual(first.allNodes.last?.kind, .unknown("MYSTERY"))
        XCTAssertTrue(first.allNodes.last?.parent === first.allNodes.dropLast().last)
    }

    func testAttributeClassificationDoesNotExecuteAuthoredCode() {
        XCTAssertEqual(WMPAttributeParser.parse(name: "width", value: "JScript:view.width-1;"),
                       .jScript("view.width-1;"))
        XCTAssertEqual(WMPAttributeParser.parse(name: "down", value: "wmpprop:player.settings.mute"),
                       .binding(kind: .property, path: "player.settings.mute"))
        XCTAssertEqual(WMPAttributeParser.parse(name: "enabled", value: "wmpenabled:player.controls.play"),
                       .binding(kind: .enabled, path: "player.controls.play"))
        XCTAssertEqual(WMPAttributeParser.parse(name: "onClick", value: "JScript:player.controls.play();"),
                       .handler(event: "onClick", source: "player.controls.play();"))
        XCTAssertEqual(WMPAttributeParser.parse(name: "onTop", value: "true"), .literal("true"))
        XCTAssertEqual(WMPAttributeParser.parse(name: "mappingColor", value: "#FA6A6A"),
                       .color(WMPColor(red: 250, green: 106, blue: 106)))
        XCTAssertEqual(WMPAttributeParser.parse(name: "image", value: "art\\button.bmp"),
                       .resource("art\\button.bmp"))
        XCTAssertEqual(WMPAttributeParser.parse(name: "image", value: "res://wmploc.dll/#1"),
                       .unsupported("res://wmploc.dll/#1"))
    }

    @MainActor
    func testLoaderBuildsViewsResourcesScriptsAndWarningsInDocumentOrder() async throws {
        let xml = """
        <THEME scriptFile="scripts/main.js;res://wmploc.dll/RT_TEXT/#132">
          <VIEW id="full"><IMAGE image="local.bmp"/><IMAGE image="missing.bmp"/></VIEW>
          <VIEW id="tiny"><IMAGE image="shared/root.bmp"/></VIEW>
        </THEME>
        """
        let url = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("Wrapper/theme.wms", data: Data(xml.utf8)),
            WMPTestArchiveEntry("Wrapper/local.bmp", data: Data([1])),
            WMPTestArchiveEntry("Wrapper/shared/root.bmp", data: Data([2])),
            WMPTestArchiveEntry("Wrapper/scripts/main.js", data: Data("function onLoad(){}".utf8))
        ])
        let loaded = try await WMPSkinLoader().load(from: url)
        XCTAssertFalse(loaded.wasLoadedOnMainThread)
        XCTAssertEqual(loaded.views.map(\.id), ["full", "tiny"])
        XCTAssertEqual(loaded.resources.map(\.status), [.available, .missing, .available])
        XCTAssertEqual(loaded.scripts.map(\.status), [.available, .unsupported])
        XCTAssertEqual(loaded.diagnostics.map(\.code), [.unsupportedResource, .resourceMissing])
    }

    func testFiftyLoadAndReleaseCyclesProduceTheSameDump() async throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/WMPSkin/widgets.wmz")
        var expected: String?
        for _ in 0..<50 {
            let loaded = try await WMPSkinLoader().load(from: url)
            if let expected { XCTAssertEqual(loaded.deterministicGraphDump, expected) }
            else { expected = loaded.deterministicGraphDump }
            XCTAssertFalse(loaded.wasLoadedOnMainThread)
        }
    }

    func testOptInNineSeriesDefaultCorpus() async throws {
        guard let path = ProcessInfo.processInfo.environment["WMP_TEST_WMZ"], !path.isEmpty else {
            throw XCTSkip("Set WMP_TEST_WMZ to the user-supplied 9SeriesDefault.wmz corpus skin.")
        }
        let loaded = try await WMPSkinLoader().load(from: URL(fileURLWithPath: path))
        XCTAssertEqual(loaded.views.count, 2)
        XCTAssertEqual(loaded.archive.resourcePaths.filter { $0.lowercased().hasSuffix(".bmp") }.count, 115)
        XCTAssertEqual(loaded.scripts.filter { $0.status == .available }.count, 3)
        let tags = Dictionary(uniqueKeysWithValues: loaded.compatibilityReport.tags.map { ($0.name, $0.count) })
        let expectedTags = [
            "subview": 33, "text": 15, "button": 14, "slider": 10,
            "buttonelement": 10, "buttongroup": 6, "volumeslider": 2,
            "seekslider": 2, "balanceslider": 1, "playlist": 1,
            "dropdownplaylist": 1, "video": 1, "wmpvideo": 1, "wmpeffects": 1,
            "equalizersettings": 1, "popup": 1, "player": 2, "network": 2, "view": 2
        ]
        for (tag, count) in expectedTags { XCTAssertEqual(tags[tag], count, tag) }
        // These intentionally mirror the spike's `grep -c`: the corpus has a few lines with more
        // than one expression/binding, so attribute occurrences are a different (also useful) count.
        let lines = loaded.definitionSource.split(whereSeparator: { $0.isNewline })
        let expressionCount = lines.filter { $0.range(of: "jscript:", options: .caseInsensitive) != nil }.count
        let bindingCount = lines.filter { $0.range(of: "wmpprop:", options: .caseInsensitive) != nil }.count
        XCTAssertEqual(expressionCount, 87)
        XCTAssertEqual(bindingCount, 44)
    }
}
