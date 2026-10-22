import CoreGraphics
import XCTest
@testable import NullPlayer

/// The `.wal` window's frame scheduling: a queued partial frame lands as a whole one would, the
/// outline follows the shape, and a new canvas presents in order ahead of a frame still in flight.
final class WinampModernFramesTests: XCTestCase {
    private let space = CGColorSpace(name: CGColorSpace.sRGB)!
    private let red = CGColor(red: 1, green: 0, blue: 0, alpha: 1)
    private let blue = CGColor(red: 0, green: 0, blue: 1, alpha: 1)

    private var shapes: [(CGRect, CGColor)] = []
    private var presented: [WinampModernCanvas.Frame] = []

    private func geometry(_ width: Int = 40, _ height: Int = 30) -> WinampModernFrames.Geometry {
        .init(pixelWidth: width, pixelHeight: height, scale: 1, colorSpace: space)
    }

    /// Frames whose scene is `shapes` as they stand when the frame is recorded.
    private func frames(_ geometry: WinampModernFrames.Geometry? = nil) -> WinampModernFrames {
        let frames = WinampModernFrames(
            record: { [unowned self] geometry, rects in
                WinampModernCanvas.Job(pixelWidth: geometry.pixelWidth, pixelHeight: geometry.pixelHeight,
                                       colorSpace: space, scale: 1, rects: rects, scene: scene(geometry),
                                       chrome: nil, promotesAlpha: false)
            },
            present: { [unowned self] frame, _ in presented.append(frame) })
        frames.target = .canvas(geometry ?? self.geometry())
        frames.isOnScreen = true
        return frames
    }

    private func scene(_ geometry: WinampModernFrames.Geometry) -> WasabiDrawList {
        let list = WasabiDrawList(ctm: .identity, clip: geometry.pixelBounds)
        for (rect, color) in shapes {
            list.setFillColor(color)
            list.fill(rect)
        }
        return list
    }

    /// Run the main queue until `count` frames have been presented.
    private func waitForPresented(_ count: Int) {
        let deadline = Date().addingTimeInterval(2)
        while presented.count < count, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
        XCTAssertEqual(presented.count, count)
    }

    private func bytes(_ image: CGImage) -> [UInt8] {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = context.data!.assumingMemoryBound(to: UInt8.self)
        return Array(UnsafeBufferPointer(start: data, count: image.width * image.height * 4))
    }

    func testAQueuedPartialFrameMatchesAWholeOne() throws {
        shapes = [(CGRect(x: 0, y: 0, width: 40, height: 30), red)]
        let frames = frames()
        frames.request(CGRect(x: 0, y: 0, width: 40, height: 30))
        frames.pumpNewCanvas()
        XCTAssertEqual(presented.count, 1, "a new canvas presents on the spot")

        shapes.append((CGRect(x: 10, y: 10, width: 8, height: 6), blue))
        frames.request(CGRect(x: 8, y: 8, width: 12, height: 10))
        waitForPresented(2)

        let whole = try XCTUnwrap(WinampModernCanvas().render(WinampModernCanvas.Job(
            pixelWidth: 40, pixelHeight: 30, colorSpace: space, scale: 1, rects: [geometry().pixelBounds],
            scene: scene(geometry()), chrome: nil, promotesAlpha: false)))
        XCTAssertEqual(bytes(try XCTUnwrap(presented.last).picture), bytes(whole.picture))
    }

    func testTheOutlineFollowsTheShape() throws {
        shapes = [(CGRect(x: 5, y: 5, width: 20, height: 10), red)]
        let frames = frames()
        frames.request(CGRect(x: 0, y: 0, width: 40, height: 30))
        frames.pumpNewCanvas()
        let first = try XCTUnwrap(frames.outline)

        // A recolour inside the same shape: a readout tick.
        shapes = [(CGRect(x: 5, y: 5, width: 20, height: 10), blue)]
        frames.request(CGRect(x: 5, y: 5, width: 20, height: 10))
        waitForPresented(2)
        XCTAssertNil(presented[1].outline)
        XCTAssertTrue(frames.outline === first)

        shapes = [(CGRect(x: 5, y: 5, width: 30, height: 10), red)]
        frames.request(CGRect(x: 25, y: 5, width: 10, height: 10))
        waitForPresented(3)
        XCTAssertNotNil(presented[2].outline)
        XCTAssertFalse(frames.outline === first)
    }

    /// A resize while a frame renders: the new size presents at once, and the older frame landing
    /// after it is dropped rather than shown over it.
    func testANewCanvasPresentsAheadOfTheFrameInFlight() throws {
        shapes = [(CGRect(x: 0, y: 0, width: 40, height: 30), red)]
        let frames = frames()
        frames.request(CGRect(x: 0, y: 0, width: 40, height: 30))
        frames.pumpNewCanvas()
        // The partial frame's pump is queued on main; the resize queues behind it, so it runs with
        // that frame sent to render and ahead of its landing, which is queued only once it renders.
        frames.request(CGRect(x: 0, y: 0, width: 10, height: 10))
        var resizedCount: Int?
        DispatchQueue.main.async {
            frames.target = .canvas(self.geometry(50, 30))
            frames.request(CGRect(x: 0, y: 0, width: 50, height: 30))
            frames.pumpNewCanvas()
            resizedCount = self.presented.count
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        XCTAssertEqual(resizedCount, 2, "the new size presents on the spot")
        XCTAssertNotNil(presented[1].outline, "a new canvas reports its outline")
        XCTAssertEqual(presented.map(\.picture.width), [40, 50])
    }
}
