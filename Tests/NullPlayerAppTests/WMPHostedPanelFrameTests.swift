import AppKit
import XCTest
@testable import NullPlayer

/// **A ring-less `.wmz` lends no frame, and our windows wear the fallback glass.** W207 nine-sliced
/// a drawer bitmap into a frame for these skins; `anemone`'s carried the drawer's painted close box
/// and keyed-out edges into our windows, and the reporter asked for the glass instead (2026-11-02).
/// The fixtures are `anemone`'s shape: a 328x261 tray with its list at 83,72 155x116.
final class WMPHostedPanelFrameTests: XCTestCase {

    private func skin(_ markup: String, images: [String: Data] = [:]) async throws -> WMPLoadedSkin {
        var entries = [WMPTestArchiveEntry("skin.wms", data: Data(markup.utf8))]
        for (path, data) in images { entries.append(WMPTestArchiveEntry(path, data: data)) }
        return try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive(entries))
    }

    private func block(width: Int, height: Int) throws -> Data {
        try WMPSkinTestSupport.encodedImage(width: width, height: height,
                                            rgba: [UInt8](repeating: 255, count: width * height * 4))
    }

    private static let tray = """
        <SUBVIEW id="tray" left="307" top="0" width="328" height="261"
                 backgroundImage="tray.png" transparencyColor="#00FF00" visible="false">
          <BUTTON id="closeTray" left="247" top="69" image="tray.png"/>
          <ITEMSPLAYLIST id="pl" left="83" top="72" width="155" height="116" visible="false"/>
        </SUBVIEW>
        """

    func testASkinWithOnlyAPanelLendsNothing() async throws {
        let loaded = try await skin("""
        <THEME><VIEW id="myview" width="321" height="268">\(Self.tray)</VIEW></THEME>
        """, images: ["tray.png": try block(width: 328, height: 261)])
        XCTAssertNil(WMPHostedFrameTemplate.derive(from: loaded, playerViewID: "myview"))
    }

    /// The same skin with a ring elsewhere still lends the ring.
    func testARingIsStillLentBesideAPanel() async throws {
        let loaded = try await skin("""
        <THEME>
        <VIEW id="myview" width="321" height="268">\(Self.tray)</VIEW>
        <VIEW id="plView" width="200" height="200" minWidth="200" minHeight="200">
          <SUBVIEW horizontalAlignment="left"    verticalAlignment="top"    backgroundImage="tray.png"/>
          <SUBVIEW horizontalAlignment="right"   verticalAlignment="top"    backgroundImage="tray.png"/>
          <SUBVIEW horizontalAlignment="left"    verticalAlignment="bottom" backgroundImage="tray.png"/>
          <SUBVIEW horizontalAlignment="right"   verticalAlignment="bottom" backgroundImage="tray.png"/>
          <SUBVIEW id="plFrame" horizontalAlignment="stretch" verticalAlignment="stretch"
                   left="10" top="10" width="180" height="180">
            <PLAYLIST id="plList" left="0" top="0" width="180" height="180"/>
          </SUBVIEW>
        </VIEW>
        </THEME>
        """, images: ["tray.png": try block(width: 328, height: 261)])
        let template = WMPHostedFrameTemplate.derive(from: loaded, playerViewID: "myview")
        XCTAssertEqual(template?.viewID, "plView")
        XCTAssertEqual(template?.ringNodeIDs.count, 4)
    }
}
