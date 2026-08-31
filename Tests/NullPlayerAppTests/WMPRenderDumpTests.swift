import Foundation
import XCTest
@testable import NullPlayer

final class WMPRenderDumpTests: XCTestCase {
    private let pixels: [UInt8] = [
        255, 0, 0, 255,   0, 255, 0, 255,
        0, 0, 255, 255,   255, 0, 255, 255
    ]

    func testUprightCropColorKeyNestedClipZOrderAndBackingScale() async throws {
        let bmp = try WMPSkinTestSupport.encodedImage(width: 2, height: 2, rgba: pixels, type: .bmp)
        let xml = """
        <THEME><VIEW id="main" width="8" height="6">
          <SUBVIEW id="parent" left="1" top="1" width="5" height="4">
            <IMAGE id="whole" left="1" top="1" width="2" height="2" image="pixel.bmp" transparencyColor="#FF00FF"/>
            <IMAGE id="crop" left="3" top="1" width="1" height="1" image="pixel.bmp"
                   cropLeft="1" cropTop="0" cropWidth="1" cropHeight="1"/>
          </SUBVIEW>
          <SUBVIEW id="back" left="0" top="0" width="1" height="1" zIndex="1" backgroundColor="#0000FF"/>
          <SUBVIEW id="front" left="0" top="0" width="1" height="1" zIndex="2" backgroundColor="#FF0000"/>
        </VIEW></THEME>
        """
        let url = try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("theme.wms", data: Data(xml.utf8)),
            WMPTestArchiveEntry("pixel.bmp", data: bmp)
        ])
        let skin = try await WMPSkinLoader().load(from: url)
        let store = WMPImageStore(provider: skin.archive)
        let scene = try await WMPSceneBuilder(loadedSkin: skin, imageStore: store).build(viewID: "main")
        let one = try await WMPRenderer(imageStore: store).render(scene: scene, backingScale: 1)
        XCTAssertFalse(scene.wasBuiltOnMainThread)
        XCTAssertFalse(one.wasRenderedOnMainThread)
        XCTAssertEqual(WMPSkinTestSupport.rgba(one.image, x: 0, yFromTop: 0), [255, 0, 0, 255])
        XCTAssertEqual(WMPSkinTestSupport.rgba(one.image, x: 2, yFromTop: 2), [255, 0, 0, 255])
        XCTAssertEqual(WMPSkinTestSupport.rgba(one.image, x: 3, yFromTop: 2), [0, 255, 0, 255])
        XCTAssertEqual(WMPSkinTestSupport.rgba(one.image, x: 2, yFromTop: 3), [0, 0, 255, 255])
        XCTAssertEqual(WMPSkinTestSupport.rgba(one.image, x: 3, yFromTop: 3), [0, 0, 0, 0])
        XCTAssertEqual(WMPSkinTestSupport.rgba(one.image, x: 4, yFromTop: 2), [0, 255, 0, 255])

        let two = try await WMPRenderer(imageStore: store).render(scene: scene, backingScale: 2)
        XCTAssertEqual(two.image.width, 16)
        XCTAssertEqual(two.image.height, 12)
        XCTAssertEqual(WMPSkinTestSupport.rgba(two.image, x: 4, yFromTop: 4), [255, 0, 0, 255])
    }

    func testTextCounterTransformKeepsGlyphsUprightInTopFrame() async throws {
        let xml = """
        <THEME><VIEW id="main" width="80" height="40">
          <TEXT id="label" left="2" top="2" width="50" height="16" value="Ab"
                fontType="Arial" fontSize="12" foregroundColor="#FFFFFF"/>
        </VIEW></THEME>
        """
        let url = try WMPSkinTestSupport.makeArchive([WMPTestArchiveEntry("theme.wms", data: Data(xml.utf8))])
        let skin = try await WMPSkinLoader().load(from: url)
        let store = WMPImageStore(provider: skin.archive)
        let scene = try await WMPSceneBuilder(loadedSkin: skin, imageStore: store).build(viewID: "main")
        let result = try await WMPRenderer(imageStore: store).render(scene: scene)
        var topAlpha = 0, bottomAlpha = 0
        for y in 0..<40 {
            for x in 0..<80 {
                let alpha = WMPSkinTestSupport.rgba(result.image, x: x, yFromTop: y)[3]
                if y < 20 { topAlpha += alpha > 0 ? 1 : 0 }
                else { bottomAlpha += alpha > 0 ? 1 : 0 }
            }
        }
        XCTAssertGreaterThan(topAlpha, 0)
        XCTAssertEqual(bottomAlpha, 0)
    }

    func testOptInRenderDumpForUserSuppliedSkin() async throws {
        guard let path = ProcessInfo.processInfo.environment["WMP_TEST_WMZ"], !path.isEmpty else {
            throw XCTSkip("Set WMP_TEST_WMZ to a user-supplied .wmz; local skins/ is never committed.")
        }
        let skin = try await WMPSkinLoader().load(from: URL(fileURLWithPath: path))
        let viewID = skin.views.first(where: { $0.id.caseInsensitiveCompare("vPlayer") == .orderedSame })?.id
            ?? skin.views.first?.id
        let selected = try XCTUnwrap(viewID)
        let store = WMPImageStore(provider: skin.archive)
        let output: URL
        if let configured = ProcessInfo.processInfo.environment["WMP_RENDER_DUMP_DIR"], !configured.isEmpty {
            output = URL(fileURLWithPath: configured, isDirectory: true)
        } else {
            output = try WMPSkinTestSupport.temporaryDirectory()
        }
        var records: [WMPRenderDumpRecord] = []
        for view in skin.views {
            let scene = try await WMPSceneBuilder(loadedSkin: skin, imageStore: store).build(viewID: view.id)
            records.append(try await WMPRenderer(imageStore: store).dump(scene: scene, to: output))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(records).write(to: output.appendingPathComponent("render-report.json"), options: .atomic)
        XCTAssertEqual(records.count, skin.views.count)
        XCTAssertTrue(records.allSatisfy {
            FileManager.default.fileExists(atPath: output.appendingPathComponent($0.pngFilename).path)
        })
        XCTAssertGreaterThan(try XCTUnwrap(records.first { $0.viewID == selected }).resolvedNodeCount, 0)
        print("WMP render dump (untracked): \(output.path)")
    }
}
