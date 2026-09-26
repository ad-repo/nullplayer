import XCTest
@testable import NullPlayer

/// **`Classic` — the three things its metadata pane and its missing frame taught the engine.**
///
/// Its value readouts take their size from their labels (`fontsize="jscript:clip_label.fontsize"`),
/// which the runtime never evaluates because `jscript:` runs for geometry only; and it authors no
/// close at all, because WMP drew a title bar around it (2026-09-26).
final class WMPClassicReadoutTests: XCTestCase {
    private func load(_ wms: String, js: String? = nil) async throws -> WMPLoadedSkin {
        var entries = [WMPTestArchiveEntry("skin.wms", data: Data(wms.utf8))]
        if let js { entries.append(WMPTestArchiveEntry("s.js", data: Data(js.utf8))) }
        return try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive(entries))
    }

    private func drawnFontSize(_ id: String, in skin: WMPLoadedSkin) async throws -> CGFloat {
        let identifier = try XCTUnwrap(skin.graph.allNodes.first { $0.xmlID == id }?.stableID)
        let scene = try await WMPSceneBuilder(loadedSkin: skin)
            .build(viewID: "main", overrides: .empty)
        return try XCTUnwrap(scene.commands.compactMap { command -> WMPSceneText? in
            guard command.stableID == identifier, case let .text(text) = command.paint else { return nil }
            return text
        }.first).fontSize
    }

    /// A readout sized from its label draws at the label's size, not at the 12pt default.
    func testAFontSizeReferencingAnotherElementTakesThatElementsNumber() async throws {
        let skin = try await load("""
        <THEME><VIEW id="main" width="285" height="100">
            <TEXT id="clip_label" top="5" width="75" height="15" fontsize="9" value="Clip:"/>
            <TEXT id="clip" top="5" left="85" width="200" height="15"
                  fontsize="jscript:clip_label.fontsize" value="A title"/>
        </VIEW></THEME>
        """)
        let clip = try await drawnFontSize("clip", in: skin)
        XCTAssertEqual(clip, 9)
    }

    /// Only the one-hop `<id>.<same property>` shape is read; anything else keeps the default.
    func testAnyOtherFontSizeExpressionKeepsTheDefault() async throws {
        let skin = try await load("""
        <THEME><VIEW id="main" width="285" height="100">
            <TEXT id="label" top="5" width="75" height="15" fontsize="9" value="Clip:"/>
            <TEXT id="value" top="5" left="85" width="200" height="15"
                  fontsize="jscript:label.fontsize + 4" value="A title"/>
        </VIEW></THEME>
        """)
        let value = try await drawnFontSize("value", in: skin)
        XCTAssertEqual(value, 12)
    }

    func testASkinWithNoCloseIsDetected() {
        XCTAssertFalse(WMPCloseControl.authorsClose(
            definitionSource: #"<VIEW><BUTTON onClick="view.ReturnToMediaCenter();"/></VIEW>"#,
            scriptSources: ["classic.js": "function StopPlaying() { player.close(); }"]),
            "`player.close()` closes the media, not a window")
    }

    func testEveryCorpusSpellingOfACloseCounts() {
        let spellings = [
            #"<BUTTON onClick="view.close();"/>"#,
            #"<BUTTON onClick="vMain.close();"/>"#,
            #"<BUTTON onmousedown="jscript:TubeFrameView.close();"/>"#,
            #"<BUTTON onClick="close();"/>"#,
            #"<BUTTON onClick="theme.closeView('vRos');"/>"#,
            #"<closeButton left="263" top="4" image="close_up.bmp"/>"#,
        ]
        for markup in spellings {
            XCTAssertTrue(WMPCloseControl.authorsClose(definitionSource: markup, scriptSources: [:]),
                          markup)
        }
        XCTAssertTrue(WMPCloseControl.authorsClose(
            definitionSource: "<VIEW/>",
            scriptSources: ["s.js": "function doClose() { view.close(); }"]),
            "a close spelled in the skin's scripts counts")
    }
}
