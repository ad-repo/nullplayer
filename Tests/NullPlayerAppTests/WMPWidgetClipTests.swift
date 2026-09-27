import CoreGraphics
import XCTest
@testable import NullPlayer

/// Where a hosted `NSView` goes when the markup asks for more room than its container has (W74).
///
/// The scene has always confined a widget's *painting* to the container it was declared in —
/// `WMPSceneBuilder` records that box as the widget's `clipRect` and every command intersects with
/// it. The `NSView` the widget is hosted in was placed from the raw authored frame instead, so an
/// overlay drew wherever the markup reached and the scene beneath it was simply covered.
///
/// `Revert.wmz` is the ground truth and the only archive in the corpus where it shows: its
/// `ctrlPlaylist` is `height="jscript:view.height-top-3"` with `top=0` inside a group at `top=14`,
/// which resolves 257 tall in a 260-tall view against a container box of 242. The overlay's extra
/// fifteen points covered the bottom of `pl_b.bmp`, and the playlist window lost the silver bevel
/// that closes its frame — reported on screen, and ranked by `WMP_RENDER_APPKIT` as the only
/// `outside=` in the corpus besides its own second release.
///
/// The arithmetic is frame ∩ clip ∩ bounds, which is what `WMPVideoSurface.update` has always done
/// for the picture. These tests pin it for the rest of the widgets.
final class WMPWidgetClipTests: XCTestCase {

    private func scene(canvas: WMPSize, widgets: [WMPWidget]) -> WMPScene {
        WMPScene(viewID: "full", canvasSize: canvas,
                 resizeLimits: .init(minimum: canvas, maximum: canvas),
                 commands: [], hits: [], widgets: widgets, geometries: [:], unresolved: [],
                 diagnostics: [], dirtyBounds: nil,
                 metrics: .init(resolvedNodeCount: widgets.count, unresolvedNodeCount: 0,
                                visibleBounds: nil),
                 wasBuiltOnMainThread: false)
    }

    private func widget(_ frame: WMPRect, clip: WMPRect?) -> WMPWidget {
        WMPWidget(stableID: 1, nodeID: "ctrlPlaylist", kind: .playlist, frame: frame, clipRect: clip,
                  label: "Playlist", toolTip: nil, minimumValue: nil, maximumValue: nil)
    }

    @MainActor
    private func hostedFrame(canvas: WMPSize, viewSize: NSSize,
                             frame: WMPRect, clip: WMPRect?) throws -> NSRect {
        let width = Int(canvas.width), height = Int(canvas.height)
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
                                              bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let view = WMPMainView(frame: NSRect(origin: .zero, size: viewSize))
        view.present(try XCTUnwrap(context.makeImage()),
                     scene: scene(canvas: canvas, widgets: [widget(frame, clip: clip)]))
        view.layoutSubtreeIfNeeded()
        let hosted = try XCTUnwrap(view.subviews.compactMap { $0 as? WMPPlaylistSurfaceView }.first,
                                   "the playlist widget is hosted")
        return hosted.frame
    }

    /// `Revert`'s own numbers, at 1:1. The view stops at the container's 242, not the markup's 257.
    @MainActor
    func testOverlayStopsAtTheContainerItWasDeclaredIn() throws {
        let frame = try hostedFrame(canvas: .init(width: 256, height: 260),
                                    viewSize: NSSize(width: 256, height: 260),
                                    frame: .init(x: 3, y: 14, width: 250, height: 257),
                                    clip: .init(x: 3, y: 14, width: 250, height: 242))
        XCTAssertEqual(frame, NSRect(x: 3, y: 14, width: 250, height: 242))
        // The four points the defect was measured in: the overlay must not reach the view's floor,
        // which is where `pl_b.bmp` draws the bevel.
        XCTAssertEqual(frame.maxY, 256)
    }

    /// A widget with no `clipRect` is unconfined and keeps the frame it was authored at — the
    /// common case, and the one the 543 already-clean hosted views in the corpus are.
    @MainActor
    func testUnclippedWidgetKeepsItsAuthoredFrame() throws {
        let frame = try hostedFrame(canvas: .init(width: 200, height: 100),
                                    viewSize: NSSize(width: 200, height: 100),
                                    frame: .init(x: 10, y: 20, width: 100, height: 50),
                                    clip: nil)
        XCTAssertEqual(frame, NSRect(x: 10, y: 20, width: 100, height: 50))
    }

    /// A clip wider than the frame confines nothing: the intersection is the frame itself. This is
    /// most of the corpus — a control well inside its container — and is why the fix moved two
    /// views and not five hundred.
    @MainActor
    func testClipLargerThanTheFrameChangesNothing() throws {
        let frame = try hostedFrame(canvas: .init(width: 200, height: 100),
                                    viewSize: NSSize(width: 200, height: 100),
                                    frame: .init(x: 40, y: 30, width: 20, height: 20),
                                    clip: .init(x: 0, y: 0, width: 200, height: 100))
        XCTAssertEqual(frame, NSRect(x: 40, y: 30, width: 20, height: 20))
    }

    /// The scene scales to the window, so the clip has to scale with it. At 2:1 `Revert`'s
    /// container box is 484 tall, not 242.
    @MainActor
    func testClipScalesWithTheView() throws {
        let frame = try hostedFrame(canvas: .init(width: 256, height: 260),
                                    viewSize: NSSize(width: 512, height: 520),
                                    frame: .init(x: 3, y: 14, width: 250, height: 257),
                                    clip: .init(x: 3, y: 14, width: 250, height: 242))
        XCTAssertEqual(frame, NSRect(x: 6, y: 28, width: 500, height: 484))
    }

    /// The third term. A container that itself hangs off the canvas cannot license an overlay
    /// outside the window, so the placed frame is bounded by the view as well — the same
    /// `.intersection(bounds)` `WMPVideoSurface` applies to the picture.
    @MainActor
    func testOverlayIsAlsoBoundedByTheView() throws {
        let frame = try hostedFrame(canvas: .init(width: 200, height: 100),
                                    viewSize: NSSize(width: 200, height: 100),
                                    frame: .init(x: 150, y: 50, width: 100, height: 100),
                                    clip: .init(x: 150, y: 50, width: 100, height: 100))
        XCTAssertEqual(frame, NSRect(x: 150, y: 50, width: 50, height: 50))
    }

    /// A clip that misses the frame entirely leaves nothing to host, and an empty rect is the
    /// honest answer — `NSRect.intersection` returns `.null` there, whose origin is not a place.
    @MainActor
    func testDisjointClipCollapsesTheOverlay() throws {
        let frame = try hostedFrame(canvas: .init(width: 200, height: 100),
                                    viewSize: NSSize(width: 200, height: 100),
                                    frame: .init(x: 0, y: 0, width: 20, height: 20),
                                    clip: .init(x: 100, y: 60, width: 20, height: 20))
        XCTAssertTrue(frame.isEmpty, "a widget clipped away is hosted at no size: \(frame)")
        XCTAssertFalse(frame.origin.x.isInfinite || frame.origin.y.isInfinite,
                       "the collapsed frame is a real rect, not CGRect.null")
    }
}
