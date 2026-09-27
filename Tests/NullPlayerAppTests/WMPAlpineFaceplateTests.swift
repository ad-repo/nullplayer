import CoreGraphics
import Foundation
import XCTest
@testable import NullPlayer

/// `Alpine7618_v09`'s faceplate: a 412-tall view whose top ~260 rows draw nothing while its drawers
/// are shut, and an LCD whose volume readout is a 28 px box.
@MainActor
final class WMPAlpineFaceplateTests: XCTestCase {

    /// The transparent top the window may hang above the screen is read off the composite's alpha.
    func testTheFirstOpaqueRowIsCountedFromTheAuthoredTop() throws {
        let width = 8, height = 10
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for row in 6..<height {
            for column in 0..<width { pixels[(row * width + column) * 4 + 3] = 255 }
        }
        let image = try XCTUnwrap(pixels.withUnsafeMutableBytes { raw -> CGImage? in
            CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        })
        XCTAssertEqual(WMPAlphaPlane(image)?.firstOpaqueRow, 6)
    }

    func testAPlaneThatDrawsNothingHasNoOpaqueRow() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8,
            bytesPerRow: 16, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        XCTAssertNil(WMPAlphaPlane(try XCTUnwrap(context.makeImage()))?.firstOpaqueRow)
    }

    /// WMP's volume is an integer. `0.2 * 100` is `20.000000000000004`, which drew as "20.0000…"
    /// clipped in the LCD's box.
    func testTheVolumeBindingIsAWholeNumber() async throws {
        let skin = try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data("""
            <THEME><VIEW id="main" width="200" height="100">
                <TEXT id="vol" left="10" top="10" width="28" height="12"
                      value="wmpprop:player.settings.volume"/>
            </VIEW></THEME>
            """.utf8))]))
        let id = try XCTUnwrap(skin.graph.allNodes.first { $0.xmlID == "vol" }?.stableID)
        var snapshot = WMPHostSnapshot()
        snapshot.volume = 0.2
        var registry = WMPObservablePropertyRegistry(graph: skin.graph)
        XCTAssertEqual(registry.changes(for: snapshot)
            .first { $0.address == .init(stableID: id, property: "value") }?.value, .number(20))
    }

    func testTheScriptReadsAWholeVolumeAndBalance() {
        let model = WMPObjectModel()
        model.snapshot.volume = 0.2
        model.snapshot.balance = -0.07
        guard case .value(let volume) = model.get("player.settings", "volume"),
              case .value(let balance) = model.get("player.settings", "balance") else {
            return XCTFail("settings.volume and settings.balance must resolve")
        }
        XCTAssertEqual(volume, .number(20))
        XCTAssertEqual(balance, .number(-7))
    }
}
