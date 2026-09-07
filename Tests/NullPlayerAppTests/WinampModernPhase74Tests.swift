import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 74 — B52: a fade stops costing a full re-solve of the object tree.
///
/// The ticket blamed `mutationGeneration`: something moved it nearly every frame, so the renderer's
/// memoized scene and layout walks never survived, and `layout()` came out at ~10% of a core on Big
/// Bento Modern with 345 of its 369 samples inside `append`. Instrumenting it
/// (`WINAMP_MODERN_MUTATION_TRACE=1`, which reports writes **and** re-solves per interval) found two
/// mechanisms, and the counter was the smaller one:
///
/// 1. `tickTargetAnimation` ran at 60 Hz per animating object and called `notifyGraphDidMutate()` on
///    **every** tick — a whole-window relayout and repaint — whether or not the tick's rounded
///    integer write changed anything. Big Bento rotates 17 `Bento:InfoLine` rows through a
///    target-alpha fade that never stops while a track is loaded, so the skin is in that state
///    permanently.
/// 2. `WinampModernMainView.invalidateRectCaches()` dropped the renderer's memoized scene on every
///    notification, times every container window the notification fans out to: **~460 drops a
///    second**, measured. That cache is keyed on the graph's own generation, so a mutation
///    invalidates it *without being told* — and a non-mutation must not.
///
/// Measured after, same skin playing with the scope visible: `layout()` 9.9% -> 1.3% of the main
/// thread, its tree re-solve 9.2% -> 0.9%.
final class WinampModernPhase74Tests: XCTestCase {

    // MARK: - The generation a cosmetic write does not move

    /// `alpha` is the attribute skins animate, and `append` reads it only as the multiplier it hands
    /// down to children — which `sceneNodes()` re-resolves over the cached nodes. So it moves the
    /// graph's own counter (callers that must see *any* change still see it) and not the scene's.
    func testAlphaDoesNotMoveTheSceneGenerationButStillMovesTheMutationCounter() throws {
        let renderer = try makeRenderer(layout: """
        <layout id="normal" w="200" h="200" default_w="200" default_h="200">
          <layer id="art" x="0" y="0" w="20" h="20"/>
        </layout>
        """)
        let graph = renderer.loadedSkin.runtime.graph
        let art = try XCTUnwrap(graph.objects(xmlID: "art").first)

        let mutations = graph.mutationGeneration
        let scene = graph.sceneGeneration
        XCTAssertTrue(art.setAttribute("alpha", value: "128"))
        XCTAssertGreaterThan(graph.mutationGeneration, mutations)
        XCTAssertEqual(graph.sceneGeneration, scene, "a fade must not invalidate the scene walk")
    }

    /// Everything else does move it. `visible` decides whether an object is in the scene at all,
    /// geometry decides where, and an attribute the flag map does not recognise is not assumed to be
    /// harmless — the exclusion list is one attribute long on purpose.
    func testEveryOtherWriteMovesTheSceneGeneration() throws {
        let renderer = try makeRenderer(layout: """
        <layout id="normal" w="200" h="200" default_w="200" default_h="200">
          <layer id="art" x="0" y="0" w="20" h="20"/>
        </layout>
        """)
        let graph = renderer.loadedSkin.runtime.graph
        let art = try XCTUnwrap(graph.objects(xmlID: "art").first)

        for (name, value) in [("visible", "0"), ("x", "5"), ("w", "40"), ("image", "other"),
                              ("text", "hello"), ("targeta", "0"), ("sysregion", "1")] {
            let before = graph.sceneGeneration
            XCTAssertTrue(art.setAttribute(name, value: value))
            XCTAssertGreaterThan(graph.sceneGeneration, before,
                                 "\(name) can change what the scene walk produces")
        }
    }

    // MARK: - What the scene reports while the cache survives

    /// The point of keeping `alpha` out of the key: the *cached* nodes have to answer with the new
    /// alpha anyway. A fade on a parent reaches every descendant, because `inheritedAlpha` is a
    /// product handed down the tree — this is the assertion that makes the exclusion safe rather than
    /// merely cheap.
    func testAFadeOnAParentReachesItsChildrenThroughTheCachedScene() throws {
        let renderer = try makeRenderer(layout: """
        <layout id="normal" w="200" h="200" default_w="200" default_h="200">
          <group id="panel" x="0" y="0" w="100" h="100">
            <layer id="art" x="0" y="0" w="20" h="20"/>
          </group>
        </layout>
        """)
        let graph = renderer.loadedSkin.runtime.graph
        let panel = try XCTUnwrap(graph.objects(xmlID: "panel").first)

        // Warm the cache, then fade the parent without touching the child.
        XCTAssertEqual(inheritedAlpha(of: "art", in: renderer), 1, accuracy: 0.001)
        XCTAssertTrue(panel.setAttribute("alpha", value: "128"))
        XCTAssertEqual(inheritedAlpha(of: "art", in: renderer), 128.0 / 255, accuracy: 0.01,
                       "the child inherits the parent's fade from a cache that was never rebuilt")

        // And back again — a fade that returns to opaque must not leave the child dimmed.
        XCTAssertTrue(panel.setAttribute("alpha", value: "255"))
        XCTAssertEqual(inheritedAlpha(of: "art", in: renderer), 1, accuracy: 0.001)
    }

    /// Two fades deep: the product, not the nearest ancestor's value.
    func testInheritedAlphaIsTheProductOfEveryAncestorsFade() throws {
        let renderer = try makeRenderer(layout: """
        <layout id="normal" w="200" h="200" default_w="200" default_h="200">
          <group id="outer" x="0" y="0" w="100" h="100">
            <group id="inner" x="0" y="0" w="50" h="50">
              <layer id="art" x="0" y="0" w="20" h="20"/>
            </group>
          </group>
        </layout>
        """)
        let graph = renderer.loadedSkin.runtime.graph
        _ = renderer.sceneNodes()
        try XCTUnwrap(graph.objects(xmlID: "outer").first).setAttribute("alpha", value: "128")
        try XCTUnwrap(graph.objects(xmlID: "inner").first).setAttribute("alpha", value: "128")

        let expected = (128.0 / 255) * (128.0 / 255)
        XCTAssertEqual(inheritedAlpha(of: "art", in: renderer), CGFloat(expected), accuracy: 0.01)
    }

    // MARK: - The box a targeted repaint has to cover

    /// A child is not obliged to stay inside its parent — only a **sized group** clips, and a `layer`
    /// never does — and `alpha` is inherited, so repainting a faded object's own rect alone leaves
    /// whatever hangs outside it half-faded on screen. `paintedBounds` is the union of the subtree.
    func testPaintedBoundsCoversAChildDrawnOutsideItsParent() throws {
        let renderer = try makeRenderer(layout: """
        <layout id="normal" w="200" h="200" default_w="200" default_h="200">
          <layer id="panel" x="0" y="0" w="20" h="20">
            <layer id="overhang" x="0" y="0" w="80" h="80"/>
          </layer>
        </layout>
        """)
        let graph = renderer.loadedSkin.runtime.graph
        let panel = try XCTUnwrap(graph.objects(xmlID: "panel").first)

        let own = try XCTUnwrap(renderer.frame(of: panel))
        let painted = try XCTUnwrap(renderer.paintedBounds(of: panel))
        XCTAssertTrue(painted.contains(own))
        XCTAssertGreaterThan(painted.width, own.width,
                             "the child drawn past the parent's edge is part of what the fade repaints")
    }

    /// The other half of the same rule: a **sized group** is a window in Wasabi and does clip, so its
    /// painted box is its own — repainting more than that would be repainting pixels it cannot reach.
    func testPaintedBoundsStopsAtASizedGroupsClip() throws {
        let renderer = try makeRenderer(layout: """
        <layout id="normal" w="200" h="200" default_w="200" default_h="200">
          <group id="panel" x="0" y="0" w="20" h="20">
            <layer id="overhang" x="0" y="0" w="80" h="80"/>
          </group>
        </layout>
        """)
        let panel = try XCTUnwrap(renderer.loadedSkin.runtime.graph.objects(xmlID: "panel").first)
        XCTAssertEqual(renderer.paintedBounds(of: panel), renderer.frame(of: panel))
    }

    /// A leaf answers its own box, not nil — the object-targeted repaint path falls back to the whole
    /// window when this returns nothing, and doing that for every fade would undo the fix.
    func testPaintedBoundsOfALeafIsItsOwnBox() throws {
        let renderer = try makeRenderer(layout: """
        <layout id="normal" w="200" h="200" default_w="200" default_h="200">
          <layer id="art" x="10" y="10" w="20" h="20"/>
        </layout>
        """)
        let art = try XCTUnwrap(renderer.loadedSkin.runtime.graph.objects(xmlID: "art").first)
        XCTAssertEqual(renderer.paintedBounds(of: art), renderer.frame(of: art))
    }

    // MARK: - Helpers

    private func inheritedAlpha(of id: String, in renderer: WasabiSceneRenderer) -> CGFloat {
        renderer.sceneNodes().first { $0.object.xmlID == id }?.inheritedAlpha ?? .nan
    }

    private func makeRenderer(layout: String) throws -> WasabiSceneRenderer {
        let renderer = try WasabiSceneRenderer(loadedSkin: makeSkin(layout: layout), host: TestHost())
        addTeardownBlock { renderer.teardown() }
        return renderer
    }

    private func makeSkin(layout: String) throws -> WinampModernLoadedSkin {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase74Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Phase74-\(UUID().uuidString).wal")
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
