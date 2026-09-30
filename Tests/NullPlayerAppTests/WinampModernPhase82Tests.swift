import XCTest
@testable import NullPlayer

/// Phase 82 (B69) — one window laid over another: Itemskin's frames find their content.
///
/// Reported live as *"the windows, eq, play, library etc are empty panes and the content for the
/// window renders separately as paneless panels separated from their window shells"*, with a
/// screenshot of three empty frames stacked in one column and their contents floating in another.
///
/// Itemskin does not draw a component window's chrome in that window. Each of `PLEdit`, `Video`,
/// `MLibrary` and `AVS_window` is a bare box holding one `<component>`; the frame the user sees is a
/// **second, dynamic container** (`cont.clear.pl`, `cont.clear.vd`, `cont.clear.ml`, …) that the
/// window's `Wasabi:StandardFrame:*` script keeps laid exactly over it, from a 10ms timer and from
/// `onMove`/`onResize`/`onSetVisible`:
///
/// ```
/// chrome.resize(content.getLeft(), content.getTop(), content.getWidth(), content.getHeight())
/// ```
///
/// Both sides of that are `<layout>`s, and a layout answers `getLeft()`/`getTop()` in its own canvas
/// space — 0 — while the `x`/`y` a `resize()` writes are pushed out to the desktop. So the script
/// asked for (0, 0), B61's round-trip guard read that as "the position it already had" and suppressed
/// the move, and every frame stayed wherever the tiler had parked it.
///
/// B61 fixed the **self** round trip (`me.resize(me.getLeft(), …)`). This is the **cross-window** one,
/// and it is fixed the same way — on the write, never on the read. Making a layout report its desktop
/// position is the obvious move and is wrong; multipass lays its side drawers out against that 0.
///
/// Two smaller things had to come with it:
///
/// - **`onMove()` was never dispatched at all.** Without it the frame window could be dragged off its
///   content, and the sync timer snapped it back a frame later. Six corpus skins bind it.
/// - **A pinned move must not be clamped to the visible frame.** The tiler had already put Itemskin's
///   library window's right edge past the screen; the clamp then stopped the *frame* window — the only
///   one of the pair a script moves — 82px short of it, and the pair came apart at the screen edge.
final class WinampModernPhase82Tests: XCTestCase {

    // MARK: - The read is unchanged

    /// The half that must **not** move. A layout is the space every object inside it is laid out in,
    /// and skins do arithmetic across that boundary — multipass positions its side drawers from
    /// `layoutMainNormal.getLeft()`, and adding the window's desktop origin there moved every drawer
    /// and its hover region off the artwork it belongs to.
    func testALayoutStillAnswersItsOwnCanvasOriginAndNotTheDesktops() throws {
        let (runtime, program) = try makeRuntime()
        runtime.containerOriginQuery = { _ in CGPoint(x: 1309, y: 318) }
        let layout = try XCTUnwrap(object(runtime, type: "layout", id: "normal"))
        XCTAssertEqual(try readOrigin(runtime, program, of: layout), CGPoint(x: 0, y: 0))
    }

    /// Its counterpart, for the record: a `<container>` has no layout space of its own, so it does
    /// answer where the host put the window (B61).
    func testAContainerStillAnswersTheHostsDesktopOrigin() throws {
        let (runtime, program) = try makeRuntime()
        runtime.containerOriginQuery = { _ in CGPoint(x: 1309, y: 318) }
        let container = try XCTUnwrap(object(runtime, type: "container", id: "chrome"))
        XCTAssertEqual(try readOrigin(runtime, program, of: container), CGPoint(x: 1309, y: 318))
    }

    // MARK: - The cross-window round trip

    /// The defect, at its smallest. The chrome layout reads the content layout's position — 0, its
    /// canvas origin — and hands it straight back to its own `resize()`. The window it is asking for
    /// is the *content window's*, so that is the point the host is given.
    func testAWindowResizedToAnothersReadPositionLandsOnThatWindow() throws {
        let (runtime, program) = try makeRuntime()
        runtime.containerOriginQuery = { id in
            id.caseInsensitiveCompare("content") == .orderedSame
                ? CGPoint(x: 1309, y: 318) : CGPoint(x: 616, y: 663)
        }
        var moves: [(WasabiObjectID, CGPoint, Bool)] = []
        runtime.containerMoveRequested = { moves.append(($0, $1, $2)) }

        let content = try XCTUnwrap(object(runtime, type: "layout", id: "contentNormal"))
        let chrome = try XCTUnwrap(object(runtime, type: "layout", id: "normal"))
        let read = try readOrigin(runtime, program, of: content)
        XCTAssertEqual(read, CGPoint(x: 0, y: 0), "the read itself is unchanged")
        try resize(runtime, program, chrome, to: CGRect(origin: read, size: CGSize(width: 330, height: 137)))

        XCTAssertEqual(moves.count, 1)
        XCTAssertEqual(moves.first?.1, CGPoint(x: 1309, y: 318),
                       "the frame window goes where the content window actually is")
        XCTAssertTrue(moves.first?.2 ?? false, "and it is a pin, so the host must not clamp it")
    }

    /// The same trip in the other direction, which is what `onMove` runs: dragging the frame pulls
    /// the content window along behind it.
    func testTheContentWindowFollowsTheFrameTheSameWay() throws {
        let (runtime, program) = try makeRuntime()
        runtime.containerOriginQuery = { id in
            id.caseInsensitiveCompare("content") == .orderedSame
                ? CGPoint(x: 1309, y: 318) : CGPoint(x: 1159, y: 418)
        }
        var moved: CGPoint?
        runtime.containerMoveRequested = { _, point, _ in moved = point }

        let chrome = try XCTUnwrap(object(runtime, type: "layout", id: "normal"))
        let content = try XCTUnwrap(object(runtime, type: "layout", id: "contentNormal"))
        let read = try readOrigin(runtime, program, of: chrome)
        try resize(runtime, program, content, to: CGRect(origin: read, size: CGSize(width: 330, height: 137)))

        XCTAssertEqual(moved, CGPoint(x: 1159, y: 418))
    }

    /// **B61 must still hold.** A window handing back its *own* position is resizing itself in place,
    /// and moving it to a layout's 0 is what threw Big Bento's player into the corner of the monitor.
    /// The two idioms are one keystroke apart and only the receiver tells them apart.
    func testWritingBackAWindowsOwnPositionIsStillNotAMove() throws {
        let (runtime, program) = try makeRuntime()
        runtime.containerOriginQuery = { _ in CGPoint(x: 1309, y: 318) }
        var moved = false
        runtime.containerMoveRequested = { _, _, _ in moved = true }

        let chrome = try XCTUnwrap(object(runtime, type: "layout", id: "normal"))
        let read = try readOrigin(runtime, program, of: chrome)
        try resize(runtime, program, chrome, to: CGRect(origin: read, size: CGSize(width: 330, height: 137)))

        XCTAssertFalse(moved, "resize(getLeft(), getTop(), w, h) on itself leaves the window alone")
    }

    /// **BB31 must still hold.** Only the round trip is recognised, never the value: Big Bento's
    /// search-results popup places itself at a point it *measured* with `clientToScreenX/Y`, and that
    /// is an ordinary, clamped move whatever the number happens to be.
    func testAPositionTheScriptDidNotReadIsStillAnOrdinaryMove() throws {
        let (runtime, program) = try makeRuntime()
        runtime.containerOriginQuery = { _ in CGPoint(x: 1309, y: 318) }
        var moves: [(WasabiObjectID, CGPoint, Bool)] = []
        runtime.containerMoveRequested = { moves.append(($0, $1, $2)) }

        let chrome = try XCTUnwrap(object(runtime, type: "layout", id: "normal"))
        try resize(runtime, program, chrome, to: CGRect(x: 40, y: 90, width: 330, height: 137))

        XCTAssertEqual(moves.first?.1, CGPoint(x: 40, y: 90))
        XCTAssertFalse(moves.first?.2 ?? true, "an authored position is placed, so it is clamped")
    }

    /// The record is spent by the write that uses it. Each of these resizes is preceded by its own
    /// pair of reads, so a stale one must not be able to pin a later write that only happens to name
    /// the same coordinates.
    func testThePinnedPositionIsConsumedByTheWriteThatUsesIt() throws {
        let (runtime, program) = try makeRuntime()
        runtime.containerOriginQuery = { id in
            id.caseInsensitiveCompare("content") == .orderedSame
                ? CGPoint(x: 1309, y: 318) : CGPoint(x: 616, y: 663)
        }
        var moves: [(WasabiObjectID, CGPoint, Bool)] = []
        runtime.containerMoveRequested = { moves.append(($0, $1, $2)) }

        let content = try XCTUnwrap(object(runtime, type: "layout", id: "contentNormal"))
        let chrome = try XCTUnwrap(object(runtime, type: "layout", id: "normal"))
        _ = try readOrigin(runtime, program, of: content)
        try resize(runtime, program, chrome, to: CGRect(x: 0, y: 0, width: 330, height: 137))
        try resize(runtime, program, chrome, to: CGRect(x: 0, y: 0, width: 400, height: 200))

        XCTAssertEqual(moves.count, 1, "the second write has no fresh read behind it")
        XCTAssertEqual(moves.first?.1, CGPoint(x: 1309, y: 318))
    }

    /// A plain object is not a window: its `x`/`y` are read back out of the scene like everything
    /// else, so it can neither record a position nor borrow one.
    func testAnObjectInsideALayoutNeitherRecordsNorBorrowsAPosition() throws {
        let (runtime, program) = try makeRuntime()
        runtime.containerOriginQuery = { _ in CGPoint(x: 1309, y: 318) }
        var moved = false
        runtime.containerMoveRequested = { _, _, _ in moved = true }

        let text = try XCTUnwrap(object(runtime, type: "text", id: "title"))
        _ = try readOrigin(runtime, program, of: text)
        try resize(runtime, program, text, to: CGRect(x: 0, y: 0, width: 10, height: 10))

        XCTAssertFalse(moved)
    }

    // MARK: - B156: a window that is not on screen lends no position

    /// Itemskin's frame script answers its content window's `onSetVisible(1)` with `syncContent()`
    /// before it shows the frame. The frame has never been placed — a new dynamic container sits at
    /// the screen's bottom-left — and pinning the content there put the Spectrum Analyzer 74pt below
    /// the screen, over the slot the tiler had just given it. The size half still applies.
    func testAWindowReadWhileOffScreenDoesNotMoveTheWindowWrittenTo() throws {
        let (runtime, program) = try makeRuntime()
        runtime.containerOriginQuery = { id in
            id.caseInsensitiveCompare("content") == .orderedSame
                ? CGPoint(x: 1309, y: 318) : CGPoint(x: 0, y: 1032)
        }
        runtime.containerVisibilityQuery = { id in id.caseInsensitiveCompare("content") == .orderedSame }
        var moved = false
        runtime.containerMoveRequested = { _, _, _ in moved = true }
        var sizes: [CGSize] = []
        runtime.layoutResizeRequested = { sizes.append($1) }

        let chrome = try XCTUnwrap(object(runtime, type: "layout", id: "normal"))
        let content = try XCTUnwrap(object(runtime, type: "layout", id: "contentNormal"))
        let read = try readOrigin(runtime, program, of: chrome)
        try resize(runtime, program, content, to: CGRect(origin: read, size: CGSize(width: 383, height: 211)))

        XCTAssertFalse(moved, "the hidden frame's origin is not a place to put the content")
        XCTAssertEqual(sizes.last, CGSize(width: 383, height: 211))
    }

    /// The other direction is unchanged once the window read *is* on screen: the frame is shown and
    /// its timer puts it on the content, which is how the pair settles.
    func testAWindowReadWhileOnScreenStillPinsTheWindowWrittenTo() throws {
        let (runtime, program) = try makeRuntime()
        runtime.containerOriginQuery = { id in
            id.caseInsensitiveCompare("content") == .orderedSame
                ? CGPoint(x: 1309, y: 318) : CGPoint(x: 0, y: 1032)
        }
        runtime.containerVisibilityQuery = { id in id.caseInsensitiveCompare("content") == .orderedSame }
        var moves: [(WasabiObjectID, CGPoint, Bool)] = []
        runtime.containerMoveRequested = { moves.append(($0, $1, $2)) }

        let content = try XCTUnwrap(object(runtime, type: "layout", id: "contentNormal"))
        let chrome = try XCTUnwrap(object(runtime, type: "layout", id: "normal"))
        let read = try readOrigin(runtime, program, of: content)
        try resize(runtime, program, chrome, to: CGRect(origin: read, size: CGSize(width: 383, height: 211)))

        XCTAssertEqual(moves.first?.1, CGPoint(x: 1309, y: 318))
        XCTAssertTrue(moves.first?.2 ?? false)
    }

    // MARK: - B160: the position lands before the size

    /// The host is asked in two calls, and the size is the one that dispatches `onResize` — so the
    /// pin has to be the first of them, and each goes out once. The rule and the Itemskin defect
    /// behind it are in `reference/scripting.md` → *The pin lands before the size*.
    func testAWindowPutOnAnothersPositionIsMovedBeforeItIsSized() throws {
        let (runtime, program) = try makeRuntime()
        runtime.containerOriginQuery = { id in
            id.caseInsensitiveCompare("content") == .orderedSame
                ? CGPoint(x: 1309, y: 318) : CGPoint(x: 1159, y: 418)
        }
        var requests: [String] = []
        runtime.containerMoveRequested = { _, point, pinned in
            requests.append("move \(Int(point.x)),\(Int(point.y)) pinned=\(pinned)")
        }
        runtime.layoutResizeRequested = { _, size in
            requests.append("size \(Int(size.width))x\(Int(size.height))")
        }

        let chrome = try XCTUnwrap(object(runtime, type: "layout", id: "normal"))
        let content = try XCTUnwrap(object(runtime, type: "layout", id: "contentNormal"))
        let read = try readOrigin(runtime, program, of: chrome)
        try resize(runtime, program, content, to: CGRect(origin: read, size: CGSize(width: 330, height: 197)))

        XCTAssertEqual(requests, ["move 1159,418 pinned=true", "size 330x197"])
    }

    // MARK: - onMove

    /// `onMove()` is addressed at the window objects only — a move changes nothing inside the scene,
    /// so unlike `onResize` there is nothing for the rest of the graph to hear. With no script bound
    /// to it the dispatch is inert, which is what keeps it free for the 30 corpus skins that declare
    /// no handler.
    ///
    /// The *bound* half has no headless route — a binding is compiled MAKI addressed at a variable a
    /// script assigns at runtime, and there is no assembler here — so it is verified live; see the
    /// Itemskin row in `manual-qa-checklist.md`.
    func testAWindowMoveDispatchIsInertWhenNoScriptBindsIt() throws {
        let (runtime, _) = try makeRuntime()
        let container = try XCTUnwrap(object(runtime, type: "container", id: "chrome"))
        let layout = try XCTUnwrap(object(runtime, type: "layout", id: "normal"))
        XCTAssertEqual(runtime.dispatchWindowMove(container: container, layout: layout), 0)
        XCTAssertEqual(runtime.dispatchWindowMove(container: container, layout: container), 0,
                       "a container that is its own layout is addressed once, not twice")
    }

    // MARK: - Helpers

    private func readOrigin(_ runtime: WinampModernScriptRuntime, _ program: MakiProgram,
                            of object: WasabiObject) throws -> CGPoint {
        let target = MakiObjectReference(.gui(object.stableID))
        let x = try runtime.invoke(method: "getLeft", on: target, arguments: [], program: program)
        let y = try runtime.invoke(method: "getTop", on: target, arguments: [], program: program)
        return CGPoint(x: Double(x.integerValue), y: Double(y.integerValue))
    }

    private func resize(_ runtime: WinampModernScriptRuntime, _ program: MakiProgram,
                        _ object: WasabiObject, to rect: CGRect) throws {
        _ = try runtime.invoke(
            method: "resize", on: MakiObjectReference(.gui(object.stableID)),
            arguments: [.integer(Int32(rect.minX)), .integer(Int32(rect.minY)),
                        .integer(Int32(rect.width)), .integer(Int32(rect.height))],
            program: program)
    }

    private func object(_ runtime: WinampModernScriptRuntime, type: String, id: String) -> WasabiObject? {
        func walk(_ objects: [WasabiObject]) -> WasabiObject? {
            for object in objects {
                if object.typeName.caseInsensitiveCompare(type) == .orderedSame,
                   object.xmlID?.caseInsensitiveCompare(id) == .orderedSame { return object }
                if let match = walk(object.children) { return match }
            }
            return nil
        }
        return walk(runtime.loadedSkin.runtime.graph.roots)
    }

    /// Itemskin's shape, at its smallest: one window holding the component and a second holding the
    /// frame drawn over it.
    private func makeRuntime() throws -> (WinampModernScriptRuntime, MakiProgram) {
        let loaded = try makeWinampModernSkin(xml: """
        <WasabiXML>
          <container id="chrome">
            <layout id="normal" w="330" h="137">
              <text id="title" x="0" y="0" w="200" fontsize="20" text="Song"/>
            </layout>
          </container>
          <container id="content">
            <layout id="contentNormal" w="330" h="137"/>
          </container>
        </WasabiXML>
        """)
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: WinampModernStubHost())
        addTeardownBlock { runtime.teardown() }
        return (runtime, Self.syntheticProgram)
    }

    private static let syntheticProgram = MakiProgram(
        version: 0x0403, classes: [], methods: [], variables: [], bindings: [], instructions: [],
        source: WalSourceLocation(path: "/Skins/Synthetic/t.maki"), ownerID: nil, parameter: nil)
}
