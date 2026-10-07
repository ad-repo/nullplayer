import AppKit
import XCTest
@testable import NullPlayer

@MainActor
final class LibraryRowThumbnailsTests: XCTestCase {
    private func image(width: Int, height: Int) -> NSImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.systemRed.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return NSImage(cgImage: context.makeImage()!, size: NSSize(width: width, height: height))
    }

    // MARK: - Preload order

    func testPreloadOrderAlternatesNearestFirst() {
        let order = LibraryRowThumbnails.preloadOrder(around: 100..<110, count: 1000)
        XCTAssertEqual(Array(order.prefix(4)), [110, 99, 111, 98])
        // Two screens (2 x 10 rows) each side.
        XCTAssertEqual(order.count, 40)
        XCTAssertEqual(Set(order).count, order.count)
    }

    func testPreloadOrderStaysInsideTheList() {
        XCTAssertEqual(LibraryRowThumbnails.preloadOrder(around: 0..<5, count: 8), [5, 6, 7])
        XCTAssertEqual(LibraryRowThumbnails.preloadOrder(around: 0..<0, count: 0), [])
    }

    func testPreloadSpanGrowsWithTheVisibleRows() {
        // 30 visible rows preload 60 either side.
        let order = LibraryRowThumbnails.preloadOrder(around: 100..<130, count: 1000)
        XCTAssertEqual(order.min(), 40)
        XCTAssertEqual(order.max(), 189)
    }

    // MARK: - Renditions

    func testRenditionsCropTheThumbnailAndKeepThePreviewShape() throws {
        let renditions = try XCTUnwrap(LibraryRowThumbnails.Renditions(from: image(width: 1000, height: 500)))
        XCTAssertEqual(renditions.thumbnail.width, 64)
        XCTAssertEqual(renditions.thumbnail.height, 64)
        XCTAssertEqual(renditions.preview.width, 400)
        XCTAssertEqual(renditions.preview.height, 200)
    }

    func testRenditionsNeverUpscale() throws {
        let renditions = try XCTUnwrap(LibraryRowThumbnails.Renditions(from: image(width: 30, height: 120)))
        XCTAssertEqual(renditions.thumbnail.width, 30)
        XCTAssertEqual(renditions.preview.width, 30)
        XCTAssertEqual(renditions.preview.height, 120)
    }

    // MARK: - Disk cache

    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("RowThumbnails-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func setModificationDate(_ date: Date) throws {
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }
    }

    func testDiskCacheRoundTripsBothRenditions() throws {
        let cache = RowThumbnailDiskCache(directory: directory)
        let renditions = try XCTUnwrap(LibraryRowThumbnails.Renditions(from: image(width: 600, height: 300)))
        XCTAssertNil(cache.read("plex:1"))

        cache.write(renditions, key: "plex:1")

        let read = try XCTUnwrap(cache.read("plex:1"))
        XCTAssertEqual(read.thumbnail.width, 64)
        XCTAssertEqual(read.preview.width, 400)
        XCTAssertEqual(read.preview.height, 200)
        XCTAssertEqual(cache.readPreview("plex:1")?.width, 400)
        XCTAssertNil(cache.read("plex:2"))
    }

    func testDiskCacheTreatsOldEntriesAsMisses() throws {
        let cache = RowThumbnailDiskCache(directory: directory)
        cache.write(try XCTUnwrap(LibraryRowThumbnails.Renditions(from: image(width: 100, height: 100))), key: "local:/a.mp3")
        try setModificationDate(Date().addingTimeInterval(-cache.maxAge - 60))

        XCTAssertNil(cache.read("local:/a.mp3"))
        XCTAssertNil(cache.readPreview("local:/a.mp3"))
    }

    func testDiskCacheNeedsBothFiles() throws {
        let cache = RowThumbnailDiskCache(directory: directory)
        cache.write(try XCTUnwrap(LibraryRowThumbnails.Renditions(from: image(width: 100, height: 100))), key: "emby:1")
        let previews = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jpg" }
        for preview in previews { try FileManager.default.removeItem(at: preview) }

        XCTAssertNil(cache.read("emby:1"))
    }

    func testPruneDeletesOldestEntriesUntilUnderTarget() throws {
        var cache = RowThumbnailDiskCache(directory: directory)
        let renditions = try XCTUnwrap(LibraryRowThumbnails.Renditions(from: image(width: 400, height: 400)))
        cache.write(renditions, key: "old")
        try setModificationDate(Date().addingTimeInterval(-3600))
        cache.write(renditions, key: "new")

        let sizes = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
            .map { try $0.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0 }
        let total = sizes.reduce(0, +)
        cache.maxBytes = total - 1
        cache.pruneTargetBytes = total / 2 + 1
        cache.prune()

        XCTAssertNil(cache.read("old"))
        XCTAssertNotNil(cache.read("new"))
    }
}
