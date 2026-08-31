import CoreGraphics
import UniformTypeIdentifiers
import XCTest
@testable import NullPlayer

final class WMPImageStoreTests: XCTestCase {
    private let pixels: [UInt8] = [
        255, 0, 0, 255,   0, 255, 0, 255,
        0, 0, 255, 255,   255, 0, 255, 255
    ]

    func testDecodesRequiredFormatsAndEnforcesDimensionLimit() throws {
        let types: [(String, UTType)] = [("a.bmp", .bmp), ("b.gif", .gif),
                                         ("c.jpg", .jpeg), ("d.png", .png)]
        var resources: [String: Data] = [:]
        for (path, type) in types { resources[path] = try WMPSkinTestSupport.encodedImage(width: 2, height: 2, rgba: pixels, type: type) }
        let store = WMPImageStore(provider: WMPMemoryResourceProvider(resources))
        for (path, _) in types { XCTAssertEqual(try store.image(for: path).size, WMPSize(width: 2, height: 2)) }
        XCTAssertEqual(store.metrics.decodedImageCount, 4)

        let limited = WMPImageStore(provider: WMPMemoryResourceProvider(["d.png": resources["d.png"]!]),
            limits: WMPImageStoreLimits(maximumDimension: 1, maximumPixels: 1,
                                       maximumDecodedBytes: 4, cacheBytes: 4))
        XCTAssertEqual(WMPSkinTestSupport.failureCode { try limited.image(for: "d.png") }, .oversizedImage)
    }

    func testLRUEvictsWithinByteBudget() throws {
        let data = try WMPSkinTestSupport.encodedImage(width: 2, height: 2, rgba: pixels)
        let provider = WMPMemoryResourceProvider(["a.png": data, "b.png": data])
        let store = WMPImageStore(provider: provider,
            limits: WMPImageStoreLimits(maximumDimension: 10, maximumPixels: 100,
                                       maximumDecodedBytes: 400, cacheBytes: 16))
        _ = try store.image(for: "a.png")
        _ = try store.image(for: "b.png")
        XCTAssertEqual(store.metrics.currentCacheBytes, 16)
        XCTAssertEqual(store.metrics.cachedImageCount, 1)
        XCTAssertEqual(store.metrics.evictionCount, 1)
    }

    func testColorKeyMasksExactRGBAndRetainsOtherAlpha() throws {
        let rgba: [UInt8] = [255, 0, 255, 255, 50, 100, 150, 128]
        let data = try WMPSkinTestSupport.encodedImage(width: 2, height: 1, rgba: rgba)
        let store = WMPImageStore(provider: WMPMemoryResourceProvider(["key.png": data]))
        let image = try store.image(for: "key.png", colorKey: WMPColor(red: 255, green: 0, blue: 255)).image
        XCTAssertEqual(WMPSkinTestSupport.rgba(image, x: 0, yFromTop: 0), [0, 0, 0, 0])
        let retained = WMPSkinTestSupport.rgba(image, x: 1, yFromTop: 0)
        XCTAssertEqual(retained[3], 128)
        assertComponent(retained[0], equals: 50, accuracy: 1)
        assertComponent(retained[1], equals: 100, accuracy: 1)
        assertComponent(retained[2], equals: 150, accuracy: 1)
    }

    private func assertComponent(_ lhs: UInt8, equals rhs: UInt8, accuracy: UInt8,
                                 file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThanOrEqual(abs(Int(lhs) - Int(rhs)), Int(accuracy), file: file, line: line)
    }
}
