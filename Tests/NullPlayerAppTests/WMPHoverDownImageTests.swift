import XCTest
@testable import NullPlayer

/// W132: `hoverDownImage` is the face of a control latched down with the pointer on it. It was
/// never drawn — the attribute was not classified as a resource, so no lookup could find it — and
/// the state machine had no way to tell a latched hover from a press.
final class WMPHoverDownImageTests: XCTestCase {
    private func load(wms: String, resources: [String: Data]) async throws -> WMPLoadedSkin {
        var entries = [WMPTestArchiveEntry("skin.wms", data: Data(wms.utf8))]
        for (name, data) in resources.sorted(by: { $0.key < $1.key }) {
            entries.append(WMPTestArchiveEntry(name, data: data))
        }
        return try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive(entries))
    }

    private func stableID(_ skin: WMPLoadedSkin, _ id: String) throws -> Int {
        try XCTUnwrap(skin.graph.allNodes.first { $0.xmlID == id }?.stableID)
    }

    private func sheet(_ width: Int, _ height: Int) throws -> Data {
        try WMPSkinTestSupport.encodedImage(width: width, height: height,
            rgba: (0..<(width * height)).flatMap { _ in [UInt8(0), 0, 0, 255] })
    }

    private func drawnImages(_ scene: WMPScene) -> [WMPSceneImage] {
        scene.commands.compactMap { command in
            guard case let .image(image) = command.paint else { return nil }
            return image
        }
    }

    private func drawn(_ scene: WMPScene, _ file: String) -> Bool {
        drawnImages(scene).contains { ($0.resourcePath as NSString).lastPathComponent == file }
    }

    func testTheAttributeIsAResource() {
        XCTAssertTrue(WMPAttributeParser.isResourceAttribute("hoverDownImage"))
    }

    /// Latched on and hovered takes `hoverDownImage`; latched on with the pointer elsewhere, and a
    /// press, keep `downImage`. `Windows XP` authors `hoverDownImage` as its *hover* sheet, so a
    /// press drawn through it would never look pressed.
    func testALatchedButtonTakesHoverDownOnlyWhileHoveredAndNotPressed() async throws {
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="20" height="20">
            <BUTTON id="toggle" image="up.png" hoverImage="hover.png" downImage="down.png"
                    hoverDownImage="hoverdown.png" sticky="true" onClick="a();"/>
        </VIEW></THEME>
        """, resources: ["up.png": try sheet(4, 4), "hover.png": try sheet(4, 4),
                         "down.png": try sheet(4, 4), "hoverdown.png": try sheet(4, 4)])
        let builder = WMPSceneBuilder(loadedSkin: skin, imageStore: WMPImageStore(provider: skin.archive))
        let id = try stableID(skin, "toggle")
        let target = WMPHitTarget(stableID: id, nodeID: "toggle", kind: "button", frame: .zero,
                                  action: nil, sticky: true, enabled: true)

        var state = WMPInteractionState()
        _ = state.move(over: target)
        _ = state.press(target)
        let pressed = try await builder.build(viewID: "main", interactionState: state)
        XCTAssertTrue(drawn(pressed, "down.png"), "a press draws downImage")
        XCTAssertFalse(drawn(pressed, "hoverdown.png"))

        _ = state.release(over: target)
        XCTAssertTrue(state.isHoverDown(id), "released over itself, the toggle is latched and hovered")
        let latchedHover = try await builder.build(viewID: "main", interactionState: state)
        XCTAssertTrue(drawn(latchedHover, "hoverdown.png"))
        XCTAssertFalse(drawn(latchedHover, "down.png"))

        _ = state.move(over: nil)
        let latchedAway = try await builder.build(viewID: "main", interactionState: state)
        XCTAssertTrue(drawn(latchedAway, "down.png"))
        XCTAssertFalse(drawn(latchedAway, "hoverdown.png"))
    }

    /// In a group the down sheet is still drawn for every latched child, and `hoverDownImage` is
    /// laid over it cut to the one child under the pointer.
    func testAGroupLaysHoverDownOverTheHoveredLatchedChildOnly() async throws {
        let map = try WMPSkinTestSupport.encodedImage(width: 2, height: 1,
            rgba: [255, 0, 0, 255, 0, 0, 255, 255])
        let skin = try await load(wms: """
        <THEME><VIEW id="main" width="20" height="20">
            <BUTTONGROUP id="group" mappingImage="map.png" image="up.png" downImage="down.png"
                         hoverDownImage="hoverdown.png">
                <BUTTONELEMENT id="shuffle" mappingColor="#FF0000" sticky="true" onClick="a();"/>
                <BUTTONELEMENT id="repeat" mappingColor="#0000FF" sticky="true" onClick="b();"/>
            </BUTTONGROUP>
        </VIEW></THEME>
        """, resources: ["map.png": map, "up.png": try sheet(2, 1), "down.png": try sheet(2, 1),
                         "hoverdown.png": try sheet(2, 1)])
        let builder = WMPSceneBuilder(loadedSkin: skin, imageStore: WMPImageStore(provider: skin.archive))
        let groupID = try stableID(skin, "group")
        let shuffle = try stableID(skin, "shuffle")
        let repeatID = try stableID(skin, "repeat")
        let resting = try await builder.build(viewID: "main")
        let group = try XCTUnwrap(resting.hits.first { $0.stableID == groupID })
        let shuffleTarget = try XCTUnwrap(group.mappingTargets.first { $0.stableID == shuffle })

        var state = WMPInteractionState()
        _ = state.setStickyDown(true, node: shuffle)
        _ = state.setStickyDown(true, node: repeatID)
        _ = state.move(over: shuffleTarget)
        let scene = try await builder.build(viewID: "main", interactionState: state)

        let down = drawnImages(scene).filter { ($0.resourcePath as NSString).lastPathComponent == "down.png" }
        XCTAssertEqual(Set(down.first?.mappingMask?.nodeIDs ?? []), [shuffle, repeatID],
                       "both latched children keep the down sheet")
        let hoverDown = drawnImages(scene).filter { ($0.resourcePath as NSString).lastPathComponent == "hoverdown.png" }
        XCTAssertEqual(hoverDown.count, 1)
        XCTAssertEqual(hoverDown.first?.mappingMask?.nodeIDs, [shuffle],
                       "cut to the child under the pointer")
    }
}
