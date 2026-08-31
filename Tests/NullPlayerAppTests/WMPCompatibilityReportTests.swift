import Foundation
import XCTest
@testable import NullPlayer

final class WMPCompatibilityReportTests: XCTestCase {
    func testReportInventoriesTagsAttributesResourcesScriptsMembersAndEventsDeterministically() async throws {
        let xml = """
        <THEME scriptFile="main.js;res://wmploc.dll/#1">
          <VIEW id="main" width="JScript:view.width-player.controls.currentPosition;">
            <BUTTON image="button.bmp" onclick="JScript:player.controls.play();"/>
            <TEXT value="wmpprop:player.controls.currentPositionString"/>
          </VIEW>
        </THEME>
        """
        let url = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("theme.wms", data: Data(xml.utf8)),
            WMPTestArchiveEntry("main.js", data: Data("function onLoad(){}".utf8)),
            WMPTestArchiveEntry("button.bmp", data: Data([1]))
        ])
        let report = try await WMPSkinLoader().load(from: url).compatibilityReport
        XCTAssertEqual(report.tags, [
            WMPInventoryItem(name: "button", count: 1),
            WMPInventoryItem(name: "text", count: 1),
            WMPInventoryItem(name: "theme", count: 1),
            WMPInventoryItem(name: "view", count: 1)
        ])
        XCTAssertEqual(report.events, [
            WMPInventoryItem(name: "onclick", count: 1),
            WMPInventoryItem(name: "onload", count: 1)
        ])
        XCTAssertEqual(report.resources.map(\.resolvedPath), ["button.bmp"])
        XCTAssertEqual(report.scripts.map(\.status), [.available, .unsupported])
        XCTAssertEqual(report.members, [
            WMPInventoryItem(name: "player.controls.currentposition", count: 1),
            WMPInventoryItem(name: "player.controls.currentpositionstring", count: 1),
            WMPInventoryItem(name: "player.controls.play", count: 1),
            WMPInventoryItem(name: "view.width", count: 1)
        ])

        let encoded = try JSONEncoder().encode(report)
        XCTAssertEqual(try JSONDecoder().decode(WMPCompatibilityReport.self, from: encoded), report)
    }
}
