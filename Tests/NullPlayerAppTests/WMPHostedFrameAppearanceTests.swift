import AppKit
import CoreGraphics
import XCTest
@testable import NullPlayer

/// **A borrowed window frame wears the colour the skin's script chose, not the one its markup
/// opens with (W145).**
///
/// `xsn_sports` stacks all eight colours of its frame in `plView` and reveals one from its `onLoad`
/// by writing `alphaBlend` on the stacked copies, keyed on the `htcpID` preference. A frame built
/// from markup alone wore the first colour forever — reported as *"the nullplayer window does not
/// follow the color theme selected in xsn"*. The fixture here is that shape at its smallest: a red
/// ring, and a blue top-left copy authored `alphaBlend="0"` that the donor's `onLoad` shows when a
/// preference says so.
@MainActor
final class WMPHostedFrameAppearanceTests: XCTestCase {

    private static func sheet(_ rgba: [UInt8]) throws -> Data {
        try WMPSkinTestSupport.encodedImage(width: 24, height: 24,
                                            rgba: [UInt8]((0..<(24 * 24)).flatMap { _ in rgba }))
    }

    private static let markup = """
        <THEME><VIEW id="plView" width="200" height="200" minWidth="200" minHeight="200"
                     onLoad="if (theme.loadPreference('colour') == '2') { alt.alphaBlend = 255; }
                             theme.savePreference('plViewer', 'true');">
          <SUBVIEW id="client" left="10" top="10" width="180" height="180"
                   horizontalAlignment="stretch" verticalAlignment="stretch">
            <PLAYLIST id="list" left="0" top="0" width="180" height="180"/>
          </SUBVIEW>
          <SUBVIEW horizontalAlignment="left" verticalAlignment="top" backgroundImage="red.png"/>
          <SUBVIEW left="176" horizontalAlignment="right" verticalAlignment="top"
                   backgroundImage="red.png"/>
          <SUBVIEW top="176" horizontalAlignment="left" verticalAlignment="bottom"
                   backgroundImage="red.png"/>
          <SUBVIEW left="176" top="176" horizontalAlignment="right" verticalAlignment="bottom"
                   backgroundImage="red.png"/>
          <SUBVIEW id="alt" horizontalAlignment="left" verticalAlignment="top"
                   backgroundImage="blue.png" alphaBlend="0"/>
        </VIEW></THEME>
        """

    private func skin() async throws -> WMPLoadedSkin {
        let entries = [WMPTestArchiveEntry("skin.wms", data: Data(Self.markup.utf8)),
                       WMPTestArchiveEntry("red.png", data: try Self.sheet([255, 0, 0, 255])),
                       WMPTestArchiveEntry("blue.png", data: try Self.sheet([0, 0, 255, 255]))]
        return try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive(entries))
    }

    /// The top-left corner's colour in the frame the provider would lend for these preferences.
    private func corner(preferences: [String: String]) async throws -> (red: CGFloat, blue: CGFloat) {
        let loaded = try await skin()
        let provider = WMPHostedFrameProvider()
        await provider.refreshScriptedAppearance(skin: loaded, playerViewID: nil,
                                                 preferences: preferences,
                                                 snapshot: WMPHostSnapshot())
        provider.configure(skin: loaded, playerViewID: nil)
        let template = try XCTUnwrap(provider.template)
        let store = WMPImageStore(provider: loaded.archive)
        let drawn = try await template.artwork(
            builder: WMPSceneBuilder(loadedSkin: loaded, imageStore: store),
            renderer: WMPRenderer(imageStore: store),
            size: CGSize(width: 200, height: 200), backingScale: 1)
        let image = try XCTUnwrap(drawn).image
        let colour = try XCTUnwrap(NSBitmapImageRep(cgImage: image).colorAt(x: 4, y: 4)?
            .usingColorSpace(.deviceRGB))
        return (colour.redComponent, colour.blueComponent)
    }

    func testTheDonorsOnLoadChoosesTheFramesColour() async throws {
        let chosen = try await corner(preferences: ["colour": "2"])
        XCTAssertGreaterThan(chosen.blue, 0.8, "the variant the script revealed is drawn")
        XCTAssertLessThan(chosen.red, 0.2)
    }

    /// A skin whose `onLoad` leaves the frame alone lends exactly what its markup draws.
    func testWithoutAScriptChoiceTheMarkupColourStands() async throws {
        let opening = try await corner(preferences: ["colour": "1"])
        XCTAssertGreaterThan(opening.red, 0.8)
        XCTAssertLessThan(opening.blue, 0.2)
    }

    /// The off-screen run works on a copy: `loadPlPrefs()`-style writes must never reach the
    /// skin's real preferences, where `plViewer` decides whether a toggle opens or closes a panel.
    func testTheOffScreenRunNeverWritesTheSkinsPreferences() throws {
        let store = WMPPreferenceStore(copying: ["colour": "2"])
        store.apply([WMPJScriptPreferenceMutation(key: "plViewer", value: "true")])
        XCTAssertEqual(store.values(), ["colour": "2", "plViewer": "true"])
        XCTAssertNil(UserDefaults.standard.object(forKey: "wmp.preferences.volatile"))
    }

    /// Colour, never layout: a script's geometry is the window it was sized for, and a subtree the
    /// frame subtracts as the skin's own stays subtracted.
    func testAppearanceKeepsOnlyColourOnFrameNodes() async throws {
        let loaded = try await skin()
        var template = try XCTUnwrap(WMPHostedFrameTemplate.derive(from: loaded, playerViewID: nil))
        template.excludedNodeIDs = [99]
        var overrides = WMPSceneOverrides.empty
        overrides.properties[.init(stableID: 7, property: "alphablend")] = .number(255)
        overrides.properties[.init(stableID: 7, property: "backgroundimage")] = .string("b.png")
        overrides.properties[.init(stableID: 7, property: "left")] = .number(40)
        overrides.properties[.init(stableID: 99, property: "alphablend")] = .number(255)
        XCTAssertEqual(Set(template.appearing(overrides).appearance.keys),
                       [.init(stableID: 7, property: "alphablend"),
                        .init(stableID: 7, property: "backgroundimage")])
    }

    /// **`visible` follows the script on ring pieces, and nowhere else.** `WALL-E`'s white theme is
    /// `onLoad` revealing a second frame set authored `visible="false"`; without it the borrowed
    /// frame wore only the underlay, with a seam in its top edge and no right rail. A script showing
    /// the skin's own content is not the frame's business.
    func testAppearanceKeepsVisibilityOnRingPiecesOnly() async throws {
        let loaded = try await skin()
        let template = try XCTUnwrap(WMPHostedFrameTemplate.derive(from: loaded, playerViewID: nil))
        let ring = try XCTUnwrap(template.ringNodeIDs.first)
        let other = (template.ringNodeIDs.max() ?? 0) + 1_000
        var overrides = WMPSceneOverrides.empty
        overrides.properties[.init(stableID: ring, property: "visible")] = .bool(true)
        overrides.properties[.init(stableID: other, property: "visible")] = .bool(true)
        XCTAssertEqual(Set(template.appearing(overrides).appearance.keys),
                       [.init(stableID: ring, property: "visible")])
    }
}

/// **A press changes the artwork the release is tested against (W306).** A control's hit area is
/// the sprite it is drawing, and the press swaps that sprite: `xsn_sports`' drawer tab is a 19x13
/// hover sprite over a 13x7 arrow, so a press on the margin released over nothing and the drawer
/// "sometimes" opened.
final class WMPReleaseOverPressedControlTests: XCTestCase {

    @MainActor
    func testAReleaseInsideThePressedControlClicksItAfterItsSpriteShrank() throws {
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 100, height: 50),
                              styleMask: [.borderless], backing: .buffered, defer: true)
        let view = WMPMainView(frame: NSRect(x: 0, y: 0, width: 100, height: 50))
        window.contentView = view
        let frame = WMPRect(x: 10, y: 10, width: 20, height: 10)
        func scene(_ coverage: WMPHitCoverage?) -> WMPScene {
            var hit = WMPHitMetadata(stableID: 4, nodeID: "tab", kind: "button", frame: frame,
                clipRect: nil, zIndex: 1, documentOrder: 1, action: nil, sticky: true,
                enabled: true, mappingImage: nil, mappingTargets: [])
            hit.coverage = coverage
            return WMPScene(viewID: "main", canvasSize: WMPSize(width: 100, height: 50),
                resizeLimits: WMPResizeLimits(minimum: WMPSize(width: 100, height: 50), maximum: nil),
                commands: [], hits: [hit], geometries: [:], unresolved: [], diagnostics: [],
                dirtyBounds: nil,
                metrics: WMPSceneMetrics(resolvedNodeCount: 1, unresolvedNodeCount: 0,
                                         visibleBounds: nil), wasBuiltOnMainThread: false)
        }
        let image = CGContext(data: nil, width: 100, height: 50, bitsPerComponent: 8,
            bytesPerRow: 400, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        var events: [String] = []
        view.onScriptEvent = { name, _, _ in events.append(name) }
        view.present(image, scene: scene(nil))

        // The press lands on the margin — scene x 11, y 11 — while the whole rect is the sprite.
        let margin = NSPoint(x: 11, y: 50 - 11)
        func event(_ type: NSEvent.EventType) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: margin, modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                clickCount: 1, pressure: 1))
        }
        view.mouseDown(with: try event(.leftMouseDown))
        // Pressed, the control draws only its middle: a 4x4 mask with the outer ring keyed out.
        let arrow = WMPHitCoverage(width: 4, height: 4, opaque: [0, 0, 0, 0,
                                                                  0, 1, 1, 0,
                                                                  0, 1, 1, 0,
                                                                  0, 0, 0, 0])
        view.present(image, scene: scene(arrow))
        view.mouseUp(with: try event(.leftMouseUp))
        XCTAssertTrue(events.contains("click"), "released inside the pressed control: \(events)")
    }
}
