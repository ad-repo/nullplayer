import CoreGraphics
import XCTest
@testable import NullPlayer

/// Phase 77 — B47: `.wal` bitmap filtering follows UI Size × backing scale.
final class WinampModernPhase77Tests: XCTestCase {

    func testRetinaTwoXUsesNearestForNativeSizeArtwork() throws {
        let context = try makeContext(scale: 2)
        XCTAssertEqual(WasabiBitmapInterpolationPolicy.quality(
            sourcePixelSize: CGSize(width: 79, height: 15),
            destination: CGRect(x: 96, y: 12, width: 79, height: 15),
            in: context), .none)
    }

    func testIntegerUIScaleWinsEvenWhenTheSkinStretchesTheBitmap() throws {
        let context = try makeContext(scale: 2)
        XCTAssertEqual(WasabiBitmapInterpolationPolicy.quality(
            sourcePixelSize: CGSize(width: 79, height: 15),
            destination: CGRect(x: 96, y: 12, width: 83, height: 17),
            in: context), .none)
    }

    func testFractionalDeviceScaleStaysSmooth() throws {
        let context = try makeContext(scale: 2.5)
        XCTAssertEqual(WasabiBitmapInterpolationPolicy.quality(
            sourcePixelSize: CGSize(width: 79, height: 15),
            destination: CGRect(x: 96, y: 12, width: 79, height: 15),
            in: context), .high)
    }

    func testActualDownscaleStaysSmoothAtAnIntegerUIScale() throws {
        let context = try makeContext(scale: 2)
        XCTAssertEqual(WasabiBitmapInterpolationPolicy.quality(
            sourcePixelSize: CGSize(width: 100, height: 100),
            destination: CGRect(x: 0, y: 0, width: 40, height: 40),
            in: context), .high)
    }

    func testFlippedSkinContextKeepsTheSameIntegerScale() throws {
        let context = try makeContext(scale: 3)
        context.translateBy(x: 0, y: 100)
        context.scaleBy(x: 1, y: -1)
        XCTAssertEqual(WasabiBitmapInterpolationPolicy.quality(
            sourcePixelSize: CGSize(width: 20, height: 10),
            destination: CGRect(x: 4, y: 5, width: 20, height: 10),
            in: context), .none)
    }

    func testPrescaleUsesTheSameIntegerAndFractionalRule() {
        XCTAssertEqual(WasabiBitmapInterpolationPolicy.quality(
            sourceWidth: 20, sourceHeight: 10,
            destinationWidth: 40, destinationHeight: 20), .none)
        XCTAssertEqual(WasabiBitmapInterpolationPolicy.quality(
            sourceWidth: 20, sourceHeight: 10,
            destinationWidth: 50, destinationHeight: 25), .high)
        XCTAssertEqual(WasabiBitmapInterpolationPolicy.quality(
            sourceWidth: 20, sourceHeight: 10,
            destinationWidth: 10, destinationHeight: 5), .high)
    }

    private func makeContext(scale: CGFloat) throws -> CGContext {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 512, height: 512, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: scale, y: scale)
        return context
    }
}
