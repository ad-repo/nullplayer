import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 52 — gotoTarget animation: speed-0 instant snap, alpha inheritance, and the
/// target-alpha default. Driven by Anaheim Player 01's compact mode, where hover controls use
/// `setTargetSpeed(0)` for instant show and the drawer slides MiniTicker via `gotoTarget`.
final class WinampModernPhase52Tests: XCTestCase {

    // MARK: - speed = 0 snaps immediately

    func testSpeedZeroSnapsToTargetImmediately() throws {
        let (runtime, object) = try makeRuntimeWithObject()
        let ref = reference(object)
        let prog = emptyProgram()
        _ = try runtime.invoke(method: "settargetx", on: ref, arguments: [.integer(100)], program: prog)
        _ = try runtime.invoke(method: "settargety", on: ref, arguments: [.integer(200)], program: prog)
        _ = try runtime.invoke(method: "settargetspeed", on: ref, arguments: [.double(0)], program: prog)
        _ = try runtime.invoke(method: "gototarget", on: ref, arguments: [], program: prog)
        XCTAssertEqual(object.attributes["x"], "100")
        XCTAssertEqual(object.attributes["y"], "200")
        XCTAssertEqual(object.attributes["goingtotarget"], "0", "snap completes immediately")
    }

    func testSpeedZeroSnapsAlphaToTarget() throws {
        let (runtime, object) = try makeRuntimeWithObject()
        let ref = reference(object)
        let prog = emptyProgram()
        _ = try runtime.invoke(method: "setalpha", on: ref, arguments: [.integer(0)], program: prog)
        _ = try runtime.invoke(method: "settargeta", on: ref, arguments: [.integer(255)], program: prog)
        _ = try runtime.invoke(method: "settargetspeed", on: ref, arguments: [.double(0)], program: prog)
        _ = try runtime.invoke(method: "gototarget", on: ref, arguments: [], program: prog)
        XCTAssertEqual(object.attributes["alpha"], "255")
    }

    // MARK: - Unset targetAlpha preserves current alpha

    func testGotoTargetWithoutSettingTargetAlphaPreservesCurrentAlpha() throws {
        let (runtime, object) = try makeRuntimeWithObject()
        let ref = reference(object)
        let prog = emptyProgram()
        _ = try runtime.invoke(method: "setalpha", on: ref, arguments: [.integer(180)], program: prog)
        _ = try runtime.invoke(method: "settargety", on: ref, arguments: [.integer(50)], program: prog)
        _ = try runtime.invoke(method: "settargetspeed", on: ref, arguments: [.double(0)], program: prog)
        _ = try runtime.invoke(method: "gototarget", on: ref, arguments: [], program: prog)
        XCTAssertEqual(object.attributes["alpha"], "180",
                       "alpha must stay at 180 when targeta was never set")
    }

    func testGotoTargetWithoutAlphaOrTargetAlphaDefaultsTo255() throws {
        let (runtime, object) = try makeRuntimeWithObject()
        let ref = reference(object)
        let prog = emptyProgram()
        // Neither alpha nor targeta is set — alpha should stay at the default 255.
        _ = try runtime.invoke(method: "settargety", on: ref, arguments: [.integer(50)], program: prog)
        _ = try runtime.invoke(method: "settargetspeed", on: ref, arguments: [.double(0)], program: prog)
        _ = try runtime.invoke(method: "gototarget", on: ref, arguments: [], program: prog)
        let alpha = object.attributes["alpha"]
        XCTAssertTrue(alpha == nil || alpha == "255",
                      "alpha must stay unset or at 255, not be clobbered to 0")
    }

    // MARK: - Animated path also preserves alpha

    func testAnimatedGotoTargetPreservesAlphaWhenTargetaUnset() throws {
        let (runtime, object) = try makeRuntimeWithObject()
        let ref = reference(object)
        let prog = emptyProgram()
        _ = try runtime.invoke(method: "setalpha", on: ref, arguments: [.integer(200)], program: prog)
        _ = try runtime.invoke(method: "settargety", on: ref, arguments: [.integer(50)], program: prog)
        _ = try runtime.invoke(method: "settargetspeed", on: ref, arguments: [.double(0.7)], program: prog)
        _ = try runtime.invoke(method: "gototarget", on: ref, arguments: [], program: prog)
        // The animation is running (speed > 0), check that isGoingToTarget is true.
        let going = try runtime.invoke(method: "isgoingtotarget", on: ref, arguments: [], program: prog).integerValue
        XCTAssertEqual(going, 1)
        // Wait a short time and let it converge — with speed=0.7 it converges quickly.
        // Instead of waiting, just cancel and check that alpha didn't change to 0.
        _ = try runtime.invoke(method: "canceltarget", on: ref, arguments: [], program: prog)
        let alpha = Int(object.attributes["alpha"] ?? "0") ?? 0
        XCTAssertGreaterThan(alpha, 100,
                             "alpha must remain near 200, not decay toward 0")
    }

    // MARK: - An at-target move still takes its duration (B281)

    /// Answered synchronously, the reached event landed inside the `onTargetReached` that re-armed
    /// it and the re-entrancy guard dropped it: Ryoko Asakura's 0.1 s volume poll froze.
    func testAtTargetMoveDefersReachedEventByItsDuration() throws {
        let (runtime, object) = try makeRuntimeWithObject()
        let ref = reference(object)
        let prog = emptyProgram()
        _ = try runtime.invoke(method: "settargeta", on: ref, arguments: [.integer(255)], program: prog)
        _ = try runtime.invoke(method: "settargetspeed", on: ref, arguments: [.double(0.1)], program: prog)
        _ = try runtime.invoke(method: "gototarget", on: ref, arguments: [], program: prog)
        XCTAssertTrue(runtime.timers.contains(id: WinampModernScriptRuntime.TimerNamespace.targetAnimation.id(for: object.stableID)),
                      "the reached event waits on the move's timer, not the caller's dispatch")
    }

    /// A speed-0 snap moves now and answers later: Ryoko Asakura's notifier snaps in `onScriptLoaded`
    /// before creating the timers its `onTargetReached` starts (B293).
    func testSpeedZeroSnapDefersReachedEvent() throws {
        let (runtime, object) = try makeRuntimeWithObject()
        let ref = reference(object)
        let prog = emptyProgram()
        _ = try runtime.invoke(method: "settargetx", on: ref, arguments: [.integer(100)], program: prog)
        _ = try runtime.invoke(method: "settargetspeed", on: ref, arguments: [.double(0)], program: prog)
        _ = try runtime.invoke(method: "gototarget", on: ref, arguments: [], program: prog)
        XCTAssertEqual(object.attributes["x"], "100")
        XCTAssertTrue(runtime.timers.contains(id: WinampModernScriptRuntime.TimerNamespace.targetAnimation.id(for: object.stableID)),
                      "the reached event waits for the next tick, after the caller's handler")
    }

    // MARK: - Alpha inheritance in scene tree

    func testAlphaInheritancePropagatesParentAlphaToChildren() throws {
        let renderer = try makeRenderer(layout: """
        <layout id="normal" w="100" h="100">
          <group id="parent" x="0" y="0" w="100" h="100" alpha="128">
            <layer id="child" x="10" y="10" w="20" h="20"/>
          </group>
        </layout>
        """)
        let nodes = renderer.sceneNodes()
        let child = try XCTUnwrap(nodes.first { $0.object.xmlID == "child" })
        // Parent alpha is 128/255 ≈ 0.502; child inherits it.
        XCTAssertEqual(child.inheritedAlpha, 128.0 / 255.0, accuracy: 0.01)
    }

    func testAlphaInheritanceZeroParentMakesChildrenInvisible() throws {
        let renderer = try makeRenderer(layout: """
        <layout id="normal" w="100" h="100">
          <group id="parent" x="0" y="0" w="100" h="100" alpha="0">
            <layer id="child" x="10" y="10" w="20" h="20"/>
          </group>
        </layout>
        """)
        let nodes = renderer.sceneNodes()
        let child = try XCTUnwrap(nodes.first { $0.object.xmlID == "child" })
        XCTAssertEqual(child.inheritedAlpha, 0, accuracy: 0.001)
    }

    func testAlphaInheritanceMultipliesThroughNestedGroups() throws {
        let renderer = try makeRenderer(layout: """
        <layout id="normal" w="100" h="100">
          <group id="outer" x="0" y="0" w="100" h="100" alpha="128">
            <group id="inner" x="0" y="0" w="100" h="100" alpha="128">
              <layer id="leaf" x="10" y="10" w="20" h="20"/>
            </group>
          </group>
        </layout>
        """)
        let nodes = renderer.sceneNodes()
        let leaf = try XCTUnwrap(nodes.first { $0.object.xmlID == "leaf" })
        // (128/255) * (128/255) ≈ 0.252
        XCTAssertEqual(leaf.inheritedAlpha, (128.0 / 255.0) * (128.0 / 255.0), accuracy: 0.01)
    }

    // MARK: - Helpers

    // MARK: - Intake #14 user round (Steamed up, Ryoko Asakura, pumaSKIN)

    /// A move shorter than one animation tick lands in the call (B472).
    func testASubTickMoveLandsAtOnce() throws {
        let (runtime, object) = try makeRuntimeWithObject()
        let ref = reference(object)
        let prog = emptyProgram()
        _ = try runtime.invoke(method: "settargetx", on: ref, arguments: [.integer(30)], program: prog)
        _ = try runtime.invoke(method: "settargetspeed", on: ref, arguments: [.double(0.01)], program: prog)
        _ = try runtime.invoke(method: "gototarget", on: ref, arguments: [], program: prog)
        XCTAssertEqual(object.attributes["x"], "30")
    }

    /// `getObject` searches inside the receiver: a group asked for the id it shares with its child
    /// answers the child (B474).
    func testGetObjectAnswersTheChildNotTheGroup() throws {
        let (runtime, loaded) = try makeRuntime(xml: roundXML)
        let group = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "br").first { $0.tag.is(.group) })
        let found = try runtime.invoke(method: "getobject", on: reference(group),
                                       arguments: [.string("br")], program: emptyProgram())
        let text = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "br").first { !$0.tag.is(.group) })
        XCTAssertEqual(guiID(of: found), text.stableID)
    }

    /// `findObject` is the window-wide lookup, and the window includes its own layout.
    func testFindObjectAnswersItsOwnLayout() throws {
        let (runtime, loaded) = try makeRuntime(xml: roundXML)
        let layout = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "normal").first)
        let found = try runtime.invoke(method: "findobject", on: reference(layout),
                                       arguments: [.string("normal")], program: emptyProgram())
        XCTAssertEqual(guiID(of: found), layout.stableID)
    }

    /// `play()` on a layer still playing keeps its clock (pumaSKIN's beat puma).
    func testPlayKeepsAPlayingLayersClock() throws {
        let (runtime, loaded) = try makeRuntime(xml: roundXML)
        let layer = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "puma").first)
        _ = try runtime.invoke(method: "play", on: reference(layer), arguments: [], program: emptyProgram())
        let started = layer.attributes["animstart"]
        Thread.sleep(forTimeInterval: 0.01)
        _ = try runtime.invoke(method: "play", on: reference(layer), arguments: [], program: emptyProgram())
        XCTAssertEqual(layer.attributes["animstart"], started)
    }

    /// A bitmap font never takes the id of the bitmap it is cut from (B474).
    func testABitmapFontKeepsTheSameIdBitmap() throws {
        let loaded = try load(xml: roundXML)
        let resources = loaded.runtime.resources
        XCTAssertEqual(resources.resolvedDefinition(identifier: "numfont12")?.kind, "bitmap")
        XCTAssertEqual(resources.resolvedFontDefinition(identifier: "numfont12")?.kind, "bitmapfont")
    }

    private let roundXML = """
    <WasabiXML>
      <elements>
        <bitmap id="numfont12" file="numfont12.png"/>
        <bitmapfont id="numfont12" file="numfont12" charwidth="10" charheight="13"/>
      </elements>
      <container id="main">
        <layout id="normal" w="200" h="200">
          <group id="br" x="0" y="0" w="100" h="40">
            <text id="br" x="0" y="0" w="80" h="20" default="1024"/>
          </group>
          <animatedlayer id="puma" x="0" y="50" w="40" h="40" frames="8" speed="1000" autoplay="0"/>
        </layout>
      </container>
    </WasabiXML>
    """

    private func guiID(of value: MakiValue) -> WasabiObjectID? {
        guard case .object(let reference) = value, case .gui(let id) = reference.kind else { return nil }
        return id
    }

    private func makeRuntime(xml: String) throws -> (WinampModernScriptRuntime, WinampModernLoadedSkin) {
        let loaded = try load(xml: xml)
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: Host())
        addTeardownBlock { runtime.teardown() }
        return (runtime, loaded)
    }

    private func makeRuntimeWithObject() throws -> (WinampModernScriptRuntime, WasabiObject) {
        let loaded = try load(xml: """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="200" h="200">
              <group id="holder" x="0" y="0" w="100" h="100">
                <layer id="movable" x="0" y="100" w="40" h="40"/>
              </group>
            </layout>
          </container>
        </WasabiXML>
        """)
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: Host())
        addTeardownBlock { runtime.teardown() }
        let object = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "movable").first)
        return (runtime, object)
    }

    private func makeRenderer(layout: String) throws -> WasabiSceneRenderer {
        let loaded = try load(xml: """
        <WasabiXML>
          <container id="main">
            \(layout)
          </container>
        </WasabiXML>
        """)
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: Host(), clock: { 0 })
        addTeardownBlock { renderer.teardown() }
        return renderer
    }

    private func load(xml: String) throws -> WinampModernLoadedSkin {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase52Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Phase52-\(UUID().uuidString).wal")
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

    private func reference(_ object: WasabiObject) -> MakiObjectReference {
        MakiObjectReference(.gui(object.stableID))
    }

    private func emptyProgram() -> MakiProgram {
        MakiProgram(version: 0x0403, classes: [], methods: [], variables: [], bindings: [],
                    instructions: [], source: WalSourceLocation(path: "/Skins/Synthetic/test.maki"),
                    ownerID: nil, parameter: nil)
    }

    private final class Host: WinampModernHost {
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
