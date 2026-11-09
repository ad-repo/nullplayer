import XCTest
@testable import NullPlayer

/// B390 — Würlitzer's `avs` window: two backdrop layouts in one container, flipped by hiding one and
/// showing the other, and stacked under the player rather than over it.
final class WinampModernB390Tests: XCTestCase {
    private func makeRuntime() throws -> WinampModernScriptRuntime {
        let loaded = try makeWinampModernSkin(xml: """
        <WasabiXML>
          <container id="avs" default_visible="1">
            <layout id="fond" w="100" h="100"/>
            <layout id="underlayer" w="100" h="100"/>
          </container>
          <container id="searchresults">
            <layout id="normal" w="100" h="100"/>
          </container>
        </WasabiXML>
        """)
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: WinampModernStubHost())
        addTeardownBlock { runtime.teardown() }
        return runtime
    }

    private func layout(_ runtime: WinampModernScriptRuntime, _ id: String) throws -> WasabiObject {
        func walk(_ objects: [WasabiObject]) -> WasabiObject? {
            for object in objects {
                if object.tag.is(.layout), object.xmlID == id { return object }
                if let match = walk(object.children) { return match }
            }
            return nil
        }
        return try XCTUnwrap(walk(runtime.loadedSkin.runtime.graph.roots))
    }

    func testHidingTheLayoutTheWindowIsNotInLeavesTheWindowOpen() throws {
        let runtime = try makeRuntime()
        var requests: [(String, Bool)] = []
        runtime.hooks.containerVisibilityRequested = { requests.append(($0, $1)) }

        runtime.requestWindow(for: try layout(runtime, "underlayer"), visible: false)

        XCTAssertTrue(requests.isEmpty, "the window shows `fond`; there is no `underlayer` window to hide")
    }

    func testShowingTheOtherLayoutSwitchesTheWindowToIt() throws {
        let runtime = try makeRuntime()
        var requests: [(String, Bool)] = []
        var switches: [String] = []
        runtime.hooks.containerVisibilityRequested = { requests.append(($0, $1)) }
        runtime.hooks.layoutSwitchRequested = { _, id in switches.append(id); return true }
        let underlayer = try layout(runtime, "underlayer")

        runtime.requestWindow(for: underlayer, visible: true)

        XCTAssertEqual(switches, ["underlayer"])
        let container = try XCTUnwrap(underlayer.parent)
        XCTAssertEqual(runtime.activeLayoutByContainer[container.stableID], underlayer.stableID)
        XCTAssertEqual(requests.map(\.0), ["avs"])
        XCTAssertEqual(requests.map(\.1), [true])
        // Now `fond` is the one the window has left, and its hide leaves the window open.
        runtime.requestWindow(for: try layout(runtime, "fond"), visible: false)
        XCTAssertEqual(requests.count, 1)
    }

    func testHidingTheLayoutTheWindowIsInStillClosesIt() throws {
        let runtime = try makeRuntime()
        var requests: [(String, Bool)] = []
        runtime.hooks.containerVisibilityRequested = { requests.append(($0, $1)) }

        runtime.requestWindow(for: try layout(runtime, "fond"), visible: false)

        XCTAssertEqual(requests.map(\.0), ["avs"])
        XCTAssertEqual(requests.map(\.1), [false])
    }

    /// BB31: a container's only layout is its window, shown or hidden as the container is.
    func testALayoutOfASingleLayoutContainerStillShowsItsWindow() throws {
        let runtime = try makeRuntime()
        var requests: [(String, Bool)] = []
        runtime.hooks.containerVisibilityRequested = { requests.append(($0, $1)) }

        runtime.requestWindow(for: try layout(runtime, "normal"), visible: true)

        XCTAssertEqual(requests.map(\.0), ["searchresults"])
        XCTAssertEqual(requests.map(\.1), [true])
    }

    // MARK: - Backdrop or frame

    /// A 10x10 plane over a 10x10 window at the origin; `opaque` says which pixels are drawn.
    private func plane(at origin: CGPoint = .zero, opaque: (Int, Int) -> Bool) -> WinampModernGlueBackdrop.Plane {
        var alpha = [UInt8](repeating: 0, count: 100)
        for row in 0..<10 { for column in 0..<10 where opaque(column, row) { alpha[row * 10 + column] = 255 } }
        return .init(width: 10, height: 10, alpha: alpha, frame: CGRect(origin: origin, size: CGSize(width: 10, height: 10)))
    }

    func testALeaderWithHolesOverAnOpaqueFollowerIsLeftTransparent() {
        let leader = plane { column, _ in column % 2 == 0 }      // a grille: every other column open
        let follower = plane { _, _ in true }
        let share = WinampModernGlueBackdrop.transparentShare(leader: leader, follower: follower)
        XCTAssertEqual(try XCTUnwrap(share), 0.5, accuracy: 0.1)
        XCTAssertTrue(WinampModernGlueBackdrop.isBackdrop(transparentShare: share))
    }

    func testAFrameWhoseClientIsOpaqueUnderItsBorderIsNotABackdrop() {
        let leader = plane { _, _ in true }
        let follower = plane { column, row in column < 2 || row < 2 }  // a border
        let share = WinampModernGlueBackdrop.transparentShare(leader: leader, follower: follower)
        XCTAssertEqual(try XCTUnwrap(share), 0, accuracy: 0.001)
        XCTAssertFalse(WinampModernGlueBackdrop.isBackdrop(transparentShare: share))
    }

    func testPixelsOutsideTheLeaderWindowAreNotJudged() {
        let leader = plane { _, _ in true }
        let follower = plane(at: CGPoint(x: 100, y: 100)) { _, _ in true }
        XCTAssertNil(WinampModernGlueBackdrop.transparentShare(leader: leader, follower: follower))
    }
}
