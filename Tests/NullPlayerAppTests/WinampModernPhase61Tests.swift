import XCTest
@testable import NullPlayer

/// Phase 61 — B43: `fliph` / `flipv`, which the engine ignored entirely.
///
/// Neither attribute appeared anywhere in `Sources/` before this. Found live on Big Bento Modern,
/// whose header analyzer group is a **butterfly**: `main.vis` (`fliph="1"`) and `main.vis2` sit side
/// by side at 144px each so the two meet low-frequency-to-low-frequency in the middle, with
/// `main.vis.mirror` / `main.vis.mirror2` (`flipv="1" alpha="110"`) as a dimmed 10px reflection under
/// each. Ignored, that drew two identical copies with a seam and two reflections that were not
/// reflected.
///
/// The draw itself needs a window and real audio, so what is asserted here is the arithmetic and the
/// attribute reading. The defining property of a flip is that it is an **involution about the
/// object's own frame**: applied twice it is the identity, and the object still covers exactly the
/// rect it declares. That is what keeps a mirrored object inside its box.
final class WinampModernPhase61Tests: XCTestCase {

    private let graph = WasabiObjectGraph()

    private func vis(_ attributes: [String: String]) -> WasabiObject {
        var merged = attributes
        merged["id"] = merged["id"] ?? "vis"
        return graph.makeObject(typeName: "vis", attributes: merged,
                                source: WalSourceLocation(path: "/test.xml"))
    }

    private func transform(_ attributes: [String: String],
                           frame: CGRect) -> CGAffineTransform? {
        WasabiSceneRenderer.flipTransform(of: vis(attributes), frame: frame)
    }

    // MARK: - No flip declared

    /// The overwhelmingly common case, and the one that must stay free: no transform at all, so the
    /// draw path is untouched for every object in the corpus that declares neither flag.
    func testAnObjectWithNoFlipAsksForNoTransform() {
        XCTAssertNil(transform([:], frame: CGRect(x: 10, y: 20, width: 100, height: 40)))
    }

    /// `fliph="0"` is a real declaration, not an absent one — Styx writes it explicitly on two of its
    /// four boxes to say "this one is the unmirrored half of the pair".
    func testAnExplicitZeroAsksForNoTransform() {
        XCTAssertNil(transform(["fliph": "0", "flipv": "0"],
                               frame: CGRect(x: 0, y: 0, width: 100, height: 40)))
    }

    // MARK: - The mirror is about the object's own frame

    /// A horizontal flip exchanges the frame's left and right edges and leaves `y` alone. The frame
    /// used here is deliberately **not** at the origin: an implementation that mirrors about the
    /// canvas rather than the object passes at `x=0` and fails everywhere else, which is exactly how
    /// Big Bento's box at `x=436` would have been drawn off its own panel.
    func testHorizontalFlipExchangesTheFrameSideEdges() {
        let frame = CGRect(x: 436, y: 3, width: 288, height: 30)
        let transform = try! XCTUnwrap(self.transform(["fliph": "1"], frame: frame))

        XCTAssertEqual(CGPoint(x: frame.minX, y: frame.minY).applying(transform),
                       CGPoint(x: frame.maxX, y: frame.minY))
        XCTAssertEqual(CGPoint(x: frame.maxX, y: frame.maxY).applying(transform),
                       CGPoint(x: frame.minX, y: frame.maxY))
        // The centre is the fixed point of a mirror.
        XCTAssertEqual(CGPoint(x: frame.midX, y: frame.midY).applying(transform),
                       CGPoint(x: frame.midX, y: frame.midY))
    }

    /// A vertical flip is the same statement on the other axis — the reflection strips under Bento's
    /// analyzers, which are `flipv="1"` and 10px tall.
    func testVerticalFlipExchangesTheFrameTopAndBottomEdges() {
        let frame = CGRect(x: 436, y: 33, width: 144, height: 10)
        let transform = try! XCTUnwrap(self.transform(["flipv": "1"], frame: frame))

        XCTAssertEqual(CGPoint(x: frame.minX, y: frame.minY).applying(transform),
                       CGPoint(x: frame.minX, y: frame.maxY))
        XCTAssertEqual(CGPoint(x: frame.maxX, y: frame.maxY).applying(transform),
                       CGPoint(x: frame.maxX, y: frame.minY))
    }

    /// Both at once is the diagonal — Styx's `vis1`, the corner of its 2×2 quad.
    func testBothFlipsRotateTheFrameThroughItsCentre() {
        let frame = CGRect(x: 0, y: 50, width: 100, height: 40)
        let transform = try! XCTUnwrap(self.transform(["fliph": "1", "flipv": "1"], frame: frame))

        XCTAssertEqual(CGPoint(x: frame.minX, y: frame.minY).applying(transform),
                       CGPoint(x: frame.maxX, y: frame.maxY))
        XCTAssertEqual(CGPoint(x: frame.maxX, y: frame.minY).applying(transform),
                       CGPoint(x: frame.minX, y: frame.maxY))
    }

    /// **The property that keeps a flipped object in its box.** Applying the mirror twice returns
    /// every point to itself, so a flip can never translate the content out of the frame — it only
    /// turns it around inside one. Asserted on the hardest case (both axes, an off-origin frame).
    func testAFlipIsAnInvolution() {
        let frame = CGRect(x: 436, y: 3, width: 288, height: 60)
        let transform = try! XCTUnwrap(self.transform(["fliph": "1", "flipv": "1"], frame: frame))
        let twice = transform.concatenating(transform)

        for corner in [CGPoint(x: frame.minX, y: frame.minY),
                       CGPoint(x: frame.maxX, y: frame.minY),
                       CGPoint(x: frame.minX, y: frame.maxY),
                       CGPoint(x: frame.maxX, y: frame.maxY)] {
            let round = corner.applying(twice)
            XCTAssertEqual(round.x, corner.x, accuracy: 0.0001)
            XCTAssertEqual(round.y, corner.y, accuracy: 0.0001)
        }
    }

    /// A flipped object still covers exactly the rect it declares, so nothing about hit testing,
    /// clipping or layout changes when a skin turns one around.
    func testAFlippedObjectStillCoversItsOwnFrame() {
        let frame = CGRect(x: 436, y: 3, width: 288, height: 60)
        let transform = try! XCTUnwrap(self.transform(["fliph": "1", "flipv": "1"], frame: frame))
        XCTAssertEqual(frame.applying(transform), frame)
    }

    // MARK: - How "1" is read

    /// The flags go through the same reader as `relat*`, so they are `atoi(value) != 0` and not
    /// `== 1` (B42). A second, subtly different reading of "true" in the renderer is exactly the bug
    /// that cost a session on the album art.
    func testTheFlagIsReadWithTheAtoiRuleNotEqualsOne() {
        let frame = CGRect(x: 0, y: 0, width: 10, height: 10)
        XCTAssertNotNil(transform(["fliph": "2"], frame: frame))
        XCTAssertNotNil(transform(["fliph": "-1"], frame: frame))
        XCTAssertNotNil(transform(["fliph": "true"], frame: frame))
        XCTAssertNotNil(transform(["fliph": "yes"], frame: frame))
        // `atoi` answers 0 for a non-numeric string, which is the reading corneramp_redux and
        // Shield_Amp depend on for their literal `relatw="%"`.
        XCTAssertNil(transform(["fliph": "%"], frame: frame))
        XCTAssertNil(transform(["fliph": ""], frame: frame))
    }

    /// A skin may declare the *same* object twice in one box, the second copy flipped — that is the
    /// classic Winamp mirrored scope, and `Nullsoft.Winamp.2000.SP4.Lite`'s `video.xml` does exactly
    /// it with two `<vis id="shade.vis">`. The pair must not resolve to the same transform, or the
    /// two coincide and the reflection is invisible.
    func testTwoDeclarationsInOneBoxDoNotCollapse() {
        let frame = CGRect(x: 196, y: 89, width: 73, height: 21)
        XCTAssertNotEqual(transform([:], frame: frame) ?? .identity,
                          transform(["flipv": "1"], frame: frame) ?? .identity)
    }

    /// The shared reader itself, since B43 is the first caller outside the geometry initializer and
    /// its behaviour is now load-bearing in two places.
    func testTheSharedFlagReader() {
        XCTAssertFalse(WasabiGeometrySpec.flag(nil))
        XCTAssertFalse(WasabiGeometrySpec.flag("0"))
        XCTAssertFalse(WasabiGeometrySpec.flag("%"))
        XCTAssertTrue(WasabiGeometrySpec.flag("1"))
        XCTAssertTrue(WasabiGeometrySpec.flag("5"))
        // `atoi`'s leading-integer rule, which `Int(_:)` would answer nil for.
        XCTAssertTrue(WasabiGeometrySpec.flag("1px"))
        XCTAssertTrue(WasabiGeometrySpec.flag(" 1 "))
    }

    // MARK: - The corpus

    /// Styx's drawer is the strongest case of the corpus's 16 declarations (all on `<vis>`): a 2×2
    /// quad of 100×40 analyzers covering all four combinations, which should render as a
    /// kaleidoscope. Every box must resolve to a *different* transform — the defect was that all four
    /// drew identically.
    func testStyxQuadResolvesToFourDistinctTransforms() {
        let boxes: [(String, [String: String], CGRect)] = [
            ("vis1", ["fliph": "1", "flipv": "1"], CGRect(x: 0, y: 50, width: 100, height: 40)),
            ("vis2", ["fliph": "0", "flipv": "1"], CGRect(x: 100, y: 50, width: 100, height: 40)),
            ("vis3", ["fliph": "1", "flipv": "0"], CGRect(x: 0, y: 104, width: 100, height: 40)),
            ("vis4", ["fliph": "0", "flipv": "0"], CGRect(x: 100, y: 104, width: 100, height: 40)),
        ]
        let resolved = boxes.map { name, attributes, frame in
            (name, transform(attributes, frame: frame) ?? .identity)
        }
        XCTAssertEqual(resolved.last?.1, .identity, "vis4 declares neither flag")
        for (outer, (nameA, a)) in resolved.enumerated() {
            for (nameB, b) in resolved[(outer + 1)...] {
                XCTAssertNotEqual(a, b, "\(nameA) and \(nameB) must not draw identically")
            }
        }
    }
}
