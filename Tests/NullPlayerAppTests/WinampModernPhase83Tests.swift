import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 83 — the two defects behind Defix's detached visualizer.
///
/// **B16 — the missing `VISCON` container.** `WinampModernContainerTopology.isHidden` read the *live*
/// `visible` attribute to decide whether a container is an SUI-collapsed stub, and
/// `WinampModernScriptRuntime.setVisible` writes that same key when a script calls `hide()`. Defix
/// closes its own detachable visualizer from `onScriptLoaded` — the ordinary thing to do with one —
/// so from `scripts.start()` onward that 406×360 window was classified as a stub that does not exist.
/// `RENDER-DUMP` takes its container list after `start()`, which is why the window had never been
/// listed, rendered or measured. The declared value is now snapshotted at creation.
///
/// **B70 — a XUI wrapper's commands never reached the control inside it.** A `<groupdef xuitag=…
/// embed_xui=…>` wrapper is a `<group>`: no click behaviour of its own, and the object the pointer
/// lands on is the embedded control. Enkera's whole transport and Defix's two button bars declare
/// their command on the wrapper, so every one of those buttons drew, pressed, glowed — and reached
/// nothing. The range (`low`/`high`) and the value accessors already crossed that seam; the commands
/// are the third thing that has to.
final class WinampModernPhase83Tests: XCTestCase {

    // MARK: - B16: declared visibility, not live visibility

    /// The defect exactly: a container the skin declares as a real window, hidden the way a script
    /// hides it, must still be a window.
    func testScriptHidingAContainerDoesNotRemoveItsWindow() throws {
        let loaded = try makeSkin(xml: Self.twoContainers)
        let before = WinampModernContainerTopology.windowContainers(graph: loaded.runtime.graph)
        XCTAssertTrue(before.contains { $0.id == "detached" },
                      "the skin declares a 406×360 window; it is one before anything runs")

        let container = try XCTUnwrap(loaded.runtime.graph.roots.first { $0.xmlID == "detached" })
        // What `setVisible` writes. Going through the runtime would need a MAKI fixture to call
        // `hide()`; the attribute is the whole mechanism and this is the value it lands on.
        _ = container.setAttribute("visible", value: "0")

        let after = WinampModernContainerTopology.windowContainers(graph: loaded.runtime.graph)
        XCTAssertTrue(after.contains { $0.id == "detached" },
                      "a closed window is still a window — B16")
        XCTAssertEqual(before.map(\.id), after.map(\.id),
                       "closing a window changes nothing about the window *list*")
    }

    /// The other half: the check `isHidden` exists for still works. Nothing in the 36-skin corpus
    /// declares a bare `visible=` on a container, so this case is guarded by test rather than by use.
    func testDeclaredVisibleZeroStillExcludesTheContainer() throws {
        let loaded = try makeSkin(xml: Self.declaredHidden)
        let windows = WinampModernContainerTopology.windowContainers(graph: loaded.runtime.graph)
        XCTAssertFalse(windows.contains { $0.id == "stub" },
                       "a container the *markup* declares invisible is a stub, as before")
        XCTAssertTrue(windows.contains { $0.id == "main" })
    }

    /// The snapshot is taken before any script can run, and only for top-level containers.
    func testDeclaredVisibilityIsStampedOnContainersOnly() throws {
        let loaded = try makeSkin(xml: Self.twoContainers)
        let key = WinampModernContainerTopology.declaredVisibleAttribute
        let container = try XCTUnwrap(loaded.runtime.graph.roots.first { $0.xmlID == "detached" })
        XCTAssertEqual(container.attributes[key], "1",
                       "a container that declares nothing is declared visible")
        let layout = try XCTUnwrap(container.children.first { $0.xmlID == "normal" })
        XCTAssertNil(layout.attributes[key], "the stamp is a container's, not every object's")
    }

    // MARK: - B70: a wrapper's commands are the embedded control's commands

    /// Enkera's transport in miniature: the command on the instance, a bare button inside.
    func testXUIWrapperForwardsItsCommandsToTheEmbeddedControl() throws {
        let loaded = try makeSkin(xml: Self.embeddedCommandButton)
        let wrapper = try XCTUnwrap(findObject(in: loaded, id: "transport.play"))
        let inner = try XCTUnwrap(wrapper.children.first { $0.xmlID == "but" })

        XCTAssertEqual(inner.attributes["action"], "play",
                       "the object the pointer lands on is the one that must carry the command")
        XCTAssertEqual(inner.attributes["param"], "guid:pl")
        XCTAssertEqual(inner.attributes["tooltip"], "Play/Resume")
        XCTAssertEqual(inner.attributes["dblclickaction"], "next")
        XCTAssertEqual(inner.attributes["rightclickaction"], "stop")
    }

    /// The containment: only commands cross. The wrapper is what draws and what is placed, and a
    /// second copy of its geometry or its artwork on the child would paint and position twice.
    func testForwardingLeavesGeometryAndArtworkOnTheWrapper() throws {
        let loaded = try makeSkin(xml: Self.embeddedCommandButton)
        let wrapper = try XCTUnwrap(findObject(in: loaded, id: "transport.play"))
        let inner = try XCTUnwrap(wrapper.children.first { $0.xmlID == "but" })

        XCTAssertEqual(wrapper.attributes["image"], "cbuttons.play")
        XCTAssertNil(inner.attributes["image"], "artwork stays on the wrapper, which draws it")
        XCTAssertEqual(wrapper.attributes["x"], "309")
        XCTAssertNil(inner.attributes["x"], "the child is fitparent; it must not be placed twice")
    }

    /// A control that states its own command keeps it — the wrapper does not overwrite the inside.
    func testEmbeddedControlKeepsItsOwnCommand() throws {
        let loaded = try makeSkin(xml: Self.embeddedControlWithOwnAction)
        let wrapper = try XCTUnwrap(findObject(in: loaded, id: "transport.play"))
        let inner = try XCTUnwrap(wrapper.children.first { $0.xmlID == "but" })
        XCTAssertEqual(inner.attributes["action"], "stop", "the control's own declaration wins")
    }

    // MARK: - Fixtures

    /// A player plus a second real window, neither declaring `visible=`.
    private static let twoContainers = """
    <WinampAbstractionLayer version="1.35">
      <skininfo><name>Phase83</name></skininfo>
      <container id="main" default_visible="1">
        <layout id="normal" w="406" h="355"/>
      </container>
      <container id="detached" default_visible="0" default_x="0" default_y="0">
        <layout id="normal" default_w="406" default_h="360" minimum_w="406" minimum_h="149"/>
      </container>
    </WinampAbstractionLayer>
    """

    private static let declaredHidden = """
    <WinampAbstractionLayer version="1.35">
      <skininfo><name>Phase83</name></skininfo>
      <container id="main" default_visible="1">
        <layout id="normal" w="406" h="355"/>
      </container>
      <container id="stub" visible="0">
        <layout id="normal" default_w="406" default_h="360"/>
      </container>
    </WinampAbstractionLayer>
    """

    private static let embeddedCommandButton = """
    <WinampAbstractionLayer version="1.35">
      <skininfo><name>Phase83</name></skininfo>
      <groupdef id="custom.cbutton" xuitag="Button:Glow" embed_xui="but">
        <button id="but" fitparent="1"/>
        <layer id="glow" fitparent="1" ghost="1"/>
      </groupdef>
      <container id="main" default_visible="1">
        <layout id="normal" w="406" h="355">
          <Button:Glow id="transport.play" x="309" y="29" w="35" h="52" image="cbuttons.play"
                       action="play" param="guid:pl" tooltip="Play/Resume"
                       dblclickaction="next" rightclickaction="stop"/>
        </layout>
      </container>
    </WinampAbstractionLayer>
    """

    private static let embeddedControlWithOwnAction = """
    <WinampAbstractionLayer version="1.35">
      <skininfo><name>Phase83</name></skininfo>
      <groupdef id="custom.cbutton" xuitag="Button:Glow" embed_xui="but">
        <button id="but" fitparent="1" action="stop"/>
      </groupdef>
      <container id="main" default_visible="1">
        <layout id="normal" w="406" h="355">
          <Button:Glow id="transport.play" x="309" y="29" w="35" h="52" action="play"/>
        </layout>
      </container>
    </WinampAbstractionLayer>
    """

    private func findObject(in loaded: WinampModernLoadedSkin, id: String) -> WasabiObject? {
        func walk(_ object: WasabiObject) -> WasabiObject? {
            if object.xmlID == id { return object }
            for child in object.children {
                if let hit = walk(child) { return hit }
            }
            return nil
        }
        for root in loaded.runtime.graph.roots {
            if let hit = walk(root) { return hit }
        }
        return nil
    }

    private func makeSkin(xml: String) throws -> WinampModernLoadedSkin {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase83Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Phase83-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        let payload = Data(xml.utf8)
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
}
