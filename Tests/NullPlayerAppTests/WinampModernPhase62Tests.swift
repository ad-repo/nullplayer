import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 62 — B44 / B44a: skin-scoped persistence of the state the **engine** owns.
///
/// A skin's own preferences already survive on their own (`setPrivateInt`, `cfgattrib`). What did not
/// was anything living in the object graph, which is rebuilt from the markup on every load and then
/// re-stamped by the skin's own scripts. Big Bento Modern is the case that found it — drag its
/// player/playlist divider wide, quit, and it is narrow again, which is why the header analyzers
/// (B43) went undiscovered for the whole B35–BB22 run.
///
/// The rule every entry obeys, and what these tests exist to pin down: **a state the *user* set is a
/// preference and survives; a state the skin's script set is the author's default and does not.**
/// Bento genuinely ships "narrow player, wide playlist" via a script calling `setPosition(434)`, and a
/// skin whose splitter the user has never touched must open exactly as its author wrote it.
final class WinampModernPhase62Tests: XCTestCase {

    /// cPro-Bento's own splitter, to the attribute: a vertical divider measured from the right edge,
    /// 200px in, bounded at 158 and at "always leave 224px for the other pane".
    private static let splitter = """
    <groupdef id="pane.left"><text id="left.label" text="L" x="0" y="0" w="10" h="10"/></groupdef>
    <groupdef id="pane.right"><text id="right.label" text="R" x="0" y="0" w="10" h="10"/></groupdef>
    <layout id="normal" w="500" h="300" default_w="500" default_h="300" minimum_w="200" minimum_h="100">
      <Wasabi:Frame id="split" x="0" y="0" w="0" h="0" relatw="1" relath="1"
                    left="pane.left" right="pane.right" orientation="vertical"
                    from="right" width="200" minwidth="158" maxwidth="-224"/>
    </layout>
    """

    // MARK: - The store

    /// `0` is a legal stored position — ClassicPro closes its side view with `setPosition(0)` and a
    /// user may well leave it closed — so "never dragged" cannot be spelled as zero. It is a separate
    /// sentinel, and this is the assertion that keeps the two apart.
    func testZeroIsAStoredPositionAndNotTheAbsenceOfOne() throws {
        let configuration = try makeConfiguration()
        XCTAssertNil(WinampModernSkinState.framePosition(container: "main", frame: "split",
                                                         in: configuration))
        WinampModernSkinState.setFramePosition(0, container: "main", frame: "split", in: configuration)
        XCTAssertEqual(WinampModernSkinState.framePosition(container: "main", frame: "split",
                                                           in: configuration), 0)
    }

    /// The key is the two names that survive a reload. `stableID` is a per-load counter and would
    /// address a different object on the next launch; the container is in the key because a skin may
    /// carry the same frame id in two of its windows.
    func testTheKeyIsScopedToTheContainerAndTheFrameID() throws {
        let configuration = try makeConfiguration()
        WinampModernSkinState.setFramePosition(300, container: "main", frame: "split", in: configuration)

        XCTAssertEqual(WinampModernSkinState.framePosition(container: "main", frame: "split",
                                                           in: configuration), 300)
        XCTAssertNil(WinampModernSkinState.framePosition(container: "playlist", frame: "split",
                                                         in: configuration))
        XCTAssertNil(WinampModernSkinState.framePosition(container: "main", frame: "split2",
                                                         in: configuration))
    }

    /// Two skins are two namespaces, which is what `WinampModernConfiguration` already gives every
    /// `setPrivateInt`. A divider dragged in Bento must not move one in ClassicPro.
    func testTwoSkinsDoNotShareADividerPosition() throws {
        let suiteName = "WinampModernPhase62Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let bento = WinampModernConfiguration(namespace: "Big Bento Modern", defaults: defaults)
        let cpro = WinampModernConfiguration(namespace: "cPro-Bento", defaults: defaults)

        WinampModernSkinState.setFramePosition(434, container: "main", frame: "split", in: bento)
        XCTAssertEqual(WinampModernSkinState.framePosition(container: "main", frame: "split",
                                                           in: bento), 434)
        XCTAssertNil(WinampModernSkinState.framePosition(container: "main", frame: "split", in: cpro))
    }

    // MARK: - Which frames are addressable

    /// A `<Wasabi:Frame>` that names neither pane pair is an ordinary group, which real skins do use
    /// it as; it has no divider and nothing to remember. A frame with no `id` cannot be addressed
    /// across launches at all and is skipped rather than given a positional key that a markup edit
    /// would silently reassign to a different splitter.
    func testOnlyIdentifiedTwoPaneSplittersArePersistable() throws {
        let renderer = try makeRenderer(layout: """
        <groupdef id="pane.left"><text id="l" text="L" x="0" y="0" w="10" h="10"/></groupdef>
        <groupdef id="pane.right"><text id="r" text="R" x="0" y="0" w="10" h="10"/></groupdef>
        <layout id="normal" w="500" h="300" default_w="500" default_h="300">
          <Wasabi:Frame id="split" x="0" y="0" w="0" h="0" relatw="1" relath="1"
                        left="pane.left" right="pane.right" from="left" width="200"/>
          <Wasabi:Frame id="plain.group" x="0" y="0" w="10" h="10"/>
          <Wasabi:Frame x="0" y="0" w="0" h="0" relatw="1" relath="1"
                        left="pane.left" right="pane.right" from="left" width="100"/>
        </layout>
        """)
        XCTAssertEqual(renderer.persistableFrames().map(\.id), ["split"])
    }

    /// `layoutNodes()`, not `sceneNodes()`: Wasabi lays a hidden object out anyway, and a splitter
    /// inside a closed drawer still has a position the user set. Restoring only what is painted would
    /// lose it for any skin whose drawer happened to be shut at quit.
    func testAHiddenSplitterIsStillPersistable() throws {
        let renderer = try makeRenderer(layout: Self.splitter.replacingOccurrences(
            of: #"<Wasabi:Frame id="split""#, with: #"<Wasabi:Frame id="split" visible="0""#))
        XCTAssertTrue(renderer.frameDividers().isEmpty, "nothing to grab while it is hidden")
        XCTAssertEqual(renderer.persistableFrames().map(\.id), ["split"])
    }

    // MARK: - Save and restore

    /// The round trip, through the two calls the window layer actually makes: a drag, then the store,
    /// then a fresh renderer over the same skin reseeded from the markup.
    func testADraggedDividerComesBackWhereTheUserLeftIt() throws {
        let loaded = try makeSkin(layout: Self.splitter)
        let first = try makeRenderer(loadedSkin: loaded)
        let divider = try XCTUnwrap(first.frameDivider(at: CGPoint(x: 300, y: 150)))
        first.dragFrameDivider(divider, to: CGPoint(x: 260, y: 150))
        XCTAssertEqual(WasabiFrame.position(of: divider), 240)
        first.persistFramePosition(of: divider)

        // A second renderer over the same graph is not a relaunch, so reseed the frame the way a
        // reload does before asking for it back.
        WasabiFrame.setPosition(200, on: divider)
        XCTAssertEqual(WasabiFrame.position(of: divider), 200, "the markup's own seed")

        let second = try makeRenderer(loadedSkin: loaded)
        XCTAssertTrue(second.restorePersistedFramePositions())
        XCTAssertEqual(WasabiFrame.position(of: divider), 240)
    }

    /// **The rule that keeps this from overriding the author.** Bento's `setPosition(434)` is the
    /// skin's genuine default, not a defect and not a preference; a splitter the user has never
    /// dragged must open exactly where the skin put it.
    func testASplitterTheUserNeverDraggedIsLeftEntirelyToTheSkin() throws {
        let renderer = try makeRenderer(layout: Self.splitter)
        let divider = try XCTUnwrap(renderer.frameDivider(at: CGPoint(x: 300, y: 150)))
        // The skin's own script, run at load.
        WasabiFrame.setPosition(180, on: divider)

        XCTAssertFalse(renderer.restorePersistedFramePositions(), "nothing stored, nothing to move")
        XCTAssertEqual(WasabiFrame.position(of: divider), 180)
    }

    /// Restoring is idempotent and re-reads the store, which is what makes the late re-assert safe:
    /// the second pass exists to beat a skin whose `setPosition` comes from a timer, and it must not
    /// pull back a divider the user dragged in the meantime.
    func testTheLateReassertReReadsTheStoreRatherThanReplayingIt() throws {
        let renderer = try makeRenderer(layout: Self.splitter)
        let divider = try XCTUnwrap(renderer.frameDivider(at: CGPoint(x: 300, y: 150)))
        renderer.persistFramePosition(of: divider)                       // the opening 200
        // Restoring what is already there leaves the divider alone. (The return value can still be
        // true on the very first pass: `setPosition` compares against the `position` *attribute*,
        // which a frame still on its `width=` seed has not got yet, so it writes one. That costs one
        // resize dispatch and nothing else.)
        renderer.restorePersistedFramePositions()
        XCTAssertEqual(WasabiFrame.position(of: divider), 200)

        // The user drags inside the first second…
        renderer.dragFrameDivider(divider, to: CGPoint(x: 260, y: 150))
        renderer.persistFramePosition(of: divider)
        // …and the skin's timer fires after them.
        WasabiFrame.setPosition(200, on: divider)

        XCTAssertTrue(renderer.restorePersistedFramePositions())
        XCTAssertEqual(WasabiFrame.position(of: divider), 240, "the drag, not the opening position")
    }

    /// A stored offset is re-clamped against the box **as it is now**. `maxwidth="-224"` is measured
    /// from the far edge, so a position that was legal in a wide window is out of bounds in a narrow
    /// one — and an unclamped restore would put the divider past the end of its own axis.
    func testAStoredPositionIsReclampedAgainstTheCurrentBox() throws {
        let loaded = try makeSkin(layout: Self.splitter)
        let wide = try makeRenderer(loadedSkin: loaded)
        let divider = try XCTUnwrap(wide.frameDivider(at: CGPoint(x: 300, y: 150)))
        wide.dragFrameDivider(divider, to: CGPoint(x: 0, y: 150))
        XCTAssertEqual(WasabiFrame.position(of: divider), 276, "capped by `maxwidth=-224` at 500px")
        wide.persistFramePosition(of: divider)

        let narrow = try makeRenderer(loadedSkin: loaded)
        _ = narrow.resize(to: CGSize(width: 300, height: 300))
        XCTAssertTrue(narrow.restorePersistedFramePositions())
        // Not 276. At 300px the two bounds cross — `maxwidth="-224"` leaves only 76 while
        // `minwidth="158"` demands 158 — and `clampedPosition` resolves that the way it always has,
        // with the minimum winning. The assertion here is that the *stored* offset is re-clamped at
        // all; which bound it lands on is the frame's own existing arithmetic.
        XCTAssertEqual(WasabiFrame.position(of: divider), 158)
    }

    /// A horizontal splitter is stored and restored on its own axis — ClassicPro's `centro.plframe`,
    /// which spells its bounds `minwidth`/`maxwidth` in either orientation.
    func testAHorizontalSplitterRoundTripsOnItsOwnAxis() throws {
        let renderer = try makeRenderer(layout: """
        <groupdef id="pane.top"><text id="t" text="T" x="0" y="0" w="10" h="10"/></groupdef>
        <groupdef id="pane.bottom"><text id="b" text="B" x="0" y="0" w="10" h="10"/></groupdef>
        <layout id="normal" w="400" h="200" default_w="400" default_h="200">
          <Wasabi:Frame id="plsplit" x="0" y="0" w="0" h="0" relatw="1" relath="1"
                        top="pane.top" bottom="pane.bottom" orientation="h"
                        from="top" height="60" minwidth="20" maxwidth="-50"/>
        </layout>
        """)
        let divider = try XCTUnwrap(renderer.frameDividers().first)
        renderer.dragFrameDivider(divider.object, to: CGPoint(x: 200, y: 120))
        renderer.persistFramePosition(of: divider.object)

        WasabiFrame.setPosition(60, on: divider.object)
        XCTAssertTrue(renderer.restorePersistedFramePositions())
        XCTAssertEqual(WasabiFrame.position(of: divider.object), 120)
    }

    // MARK: - Which layout a container is on (B44a)

    /// A container with two layouts, the second of them a shade — the shape every skin that draws a
    /// titlebar shade button has.
    private static let shadeable = """
    <layout id="normal" w="300" h="200" default_w="300" default_h="200">
      <text id="title" text="N" x="0" y="0" w="10" h="10"/>
    </layout>
    <layout id="shade" w="300" h="20" default_w="300" default_h="20">
      <text id="title.shade" text="S" x="0" y="0" w="10" h="10"/>
    </layout>
    """

    /// The round trip: the user shades the window, and a fresh load comes back shaded.
    func testAContainerComesBackOnTheLayoutTheUserSwitchedItTo() throws {
        let loaded = try makeSkin(layout: Self.shadeable)
        let first = try makeRenderer(loadedSkin: loaded)
        XCTAssertEqual(first.activeLayoutID, "normal")
        _ = try first.activateLayout(id: "shade")
        first.persistActiveLayout()

        let second = try makeRenderer(loadedSkin: loaded)
        XCTAssertEqual(second.activeLayoutID, "normal", "a fresh load opens on the skin's own layout")
        XCTAssertEqual(second.rememberedLayoutID, "shade")
    }

    /// The same rule as the splitter, on the other piece of state: a container the user has never
    /// switched has nothing remembered, so the skin decides which layout opens.
    func testAContainerTheUserNeverSwitchedRemembersNothing() throws {
        let renderer = try makeRenderer(layout: Self.shadeable)
        XCTAssertNil(renderer.rememberedLayoutID)
    }

    /// Already on it is nothing to do — this is what keeps the restore from resizing a window at
    /// launch for no reason.
    func testTheLayoutAlreadyActiveIsNotOfferedForRestore() throws {
        let renderer = try makeRenderer(layout: Self.shadeable)
        renderer.persistActiveLayout()
        XCTAssertNil(renderer.rememberedLayoutID, "`normal` is already up")
    }

    /// An updated skin may rename or drop a layout. The stored name is checked against the
    /// container's own children, so a stale one is ignored rather than throwing on activation.
    func testALayoutTheSkinNoLongerDeclaresIsIgnored() throws {
        let loaded = try makeSkin(layout: Self.shadeable)
        let renderer = try makeRenderer(loadedSkin: loaded)
        WinampModernSkinState.setLayout("winshade", container: "main", in: loaded.configuration)
        XCTAssertNil(renderer.rememberedLayoutID)
    }

    /// Layouts are keyed per container, so shading the player does not shade the playlist window.
    func testTheLayoutIsScopedToItsContainer() throws {
        let configuration = try makeConfiguration()
        WinampModernSkinState.setLayout("shade", container: "main", in: configuration)
        XCTAssertEqual(WinampModernSkinState.layout(container: "main", in: configuration), "shade")
        XCTAssertNil(WinampModernSkinState.layout(container: "pledit", in: configuration))
    }

    // MARK: - A splitter outside the opening layout (B44a)

    /// The gap B44's first slice left. `persistableFrames()` only ever sees the **active** layout, and
    /// the restore ran once at `scriptsDidStart`, so a divider dragged in a layout the user switched
    /// to later was stored and then never put back. Activating a layout now restores its own
    /// splitters.
    func testASplitterInAnotherLayoutIsRestoredWhenThatLayoutIsActivated() throws {
        let loaded = try makeSkin(layout: """
        <groupdef id="pane.left"><text id="l" text="L" x="0" y="0" w="10" h="10"/></groupdef>
        <groupdef id="pane.right"><text id="r" text="R" x="0" y="0" w="10" h="10"/></groupdef>
        <layout id="normal" w="300" h="200" default_w="300" default_h="200">
          <text id="title" text="N" x="0" y="0" w="10" h="10"/>
        </layout>
        <layout id="wide" w="500" h="300" default_w="500" default_h="300">
          <Wasabi:Frame id="wide.split" x="0" y="0" w="0" h="0" relatw="1" relath="1"
                        left="pane.left" right="pane.right" from="left" width="200"/>
        </layout>
        """)
        let renderer = try makeRenderer(loadedSkin: loaded)
        // Nothing to see from the opening layout — which is exactly why this was missed.
        XCTAssertTrue(renderer.persistableFrames().isEmpty)

        _ = try renderer.activateLayout(id: "wide")
        let divider = try XCTUnwrap(renderer.persistableFrames().first)
        renderer.dragFrameDivider(divider.object, to: CGPoint(x: 260, y: 150))
        XCTAssertEqual(WasabiFrame.position(of: divider.object), 260)
        renderer.persistFramePosition(of: divider.object)

        // A reload reseeds it, and switching back to `wide` is the only thing that can restore it.
        WasabiFrame.setPosition(200, on: divider.object)
        let reloaded = try makeRenderer(loadedSkin: loaded)
        XCTAssertFalse(reloaded.restorePersistedFramePositions(), "not in the opening layout")
        _ = try reloaded.activateLayout(id: "wide")
        XCTAssertTrue(reloaded.restorePersistedFramePositions())
        XCTAssertEqual(WasabiFrame.position(of: divider.object), 260)
    }

    // MARK: - Fixtures

    private func makeConfiguration() throws -> WinampModernConfiguration {
        let suiteName = "WinampModernPhase62Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return WinampModernConfiguration(namespace: "fixture", defaults: defaults)
    }

    private func makeRenderer(layout: String) throws -> WasabiSceneRenderer {
        try makeRenderer(loadedSkin: makeSkin(layout: layout))
    }

    private func makeRenderer(loadedSkin: WinampModernLoadedSkin) throws -> WasabiSceneRenderer {
        let renderer = try WasabiSceneRenderer(loadedSkin: loadedSkin, host: TestHost())
        addTeardownBlock { renderer.teardown() }
        return renderer
    }

    private func makeSkin(layout: String) throws -> WinampModernLoadedSkin {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase62Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        // A unique archive name gives each fixture its own configuration namespace, which matters
        // more here than anywhere else: this suite writes to that namespace.
        let url = directory.appendingPathComponent("Phase62-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        let payload = Data("""
        <WasabiXML>
          <container id="main">
            \(layout)
          </container>
        </WasabiXML>
        """.utf8)
        try archive.addEntry(with: "skin.xml", type: .file, uncompressedSize: Int64(payload.count),
                             compressionMethod: .none) { position, size in
            let start = Int(position)
            guard start < payload.count else { return Data() }
            return payload.subdata(in: start..<min(payload.count, start + size))
        }
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: url)
        addTeardownBlock { loaded.teardown() }
        return loaded
    }

    private final class TestHost: WinampModernHost {
        var playbackState: PlaybackState = .stopped
        var currentTime: TimeInterval = 0
        var duration: TimeInterval = 0
        var volume: Double = 0.5
        var shuffleEnabled = false
        var repeatEnabled = false
        var trackTitle = ""
        var trackInfo = ""
        var spectrumLevels: [Float] = []

        func play() {}
        func pause() {}
        func stop() {}
        func previous() {}
        func next() {}
        func seek(to seconds: TimeInterval) {}
        func openFiles() {}
        func beginVisualizationConsumption() {}
        func endVisualizationConsumption() {}
    }
}
