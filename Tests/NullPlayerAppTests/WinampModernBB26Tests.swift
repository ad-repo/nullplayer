import XCTest
import ZIPFoundation
@testable import NullPlayer

/// BB26 — a button a *script* activates never drew its `activeimage`.
///
/// `resolvedBitmapID` decided a button was active from three sources: a hard-coded `shuffle`/`repeat`
/// `xmlID`, an `EQ_TOGGLE`/`EQ_AUTO` action, and a `cfgattrib` binding through `configStateProvider`.
/// All three are *external* state. The button's own `activated` attribute — what
/// `setActivated`/`setActivatedNoCallback` write from MAKI, and what `toggleActivation` writes on a
/// click — was not in that `||` at all, though `setActivated`'s own doc said it was.
///
/// Reported live 2026-08-31 as *"the file-info rating row draws five dots, not stars"*. The dots are
/// not the defect: Big Bento's `window/rating.png` is a four-cell strip — filled star, grey star,
/// **dot**, red X — and `infocomp.rating.empty` *is* the dot, so an unrated row is correct. The row
/// fills in because `fileinfo.maki` calls `setActivated` on `rate.1…5`, which is the case that could
/// not draw. The rating itself round-tripped the whole way to the server the entire time (verified
/// live on Plex: `Rated item 656141 with rating 8`), which is why this reads as a storage bug and is
/// not one.
///
/// Reach is not one row: 754 of the corpus's 1618 `activeimage` declarations, across 39 of 53 skins,
/// are named by none of the three external sources. Nothing changed at rest, though — no skin in the
/// corpus declares `activated="1"` in its markup, so the artwork only moves once something writes it.
///
/// This is the button half of the rule B66 established for check boxes in `WasabiFormWidgets.isOn`:
/// *a binding can turn a control on; its absence must not turn one off.*
final class WinampModernBB26Tests: XCTestCase {

    // MARK: - The defect

    /// The rating row, reduced to its shape: a plain `<button>` with an `activeimage`, no binding,
    /// no known id, no action — activated only by a script.
    func testAScriptActivatedButtonDrawsItsActiveImage() throws {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="200" h="200">
              <button id="rate.1" x="0" y="0" w="27" h="20"
                      image="rating.empty" activeImage="rating.star"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { renderer.teardown() }
        let button = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "rate.1").first)

        func bitmap() -> String? {
            renderer.sceneNodes().first { $0.object.xmlID == "rate.1" }?.bitmapID
        }
        XCTAssertEqual(bitmap(), "rating.empty", "unrated is the dot, and that part was never wrong")

        _ = button.setAttribute("activated", value: "1")
        XCTAssertEqual(bitmap(), "rating.star",
                       "the button's own activation is the fourth source of an active image")

        _ = button.setAttribute("activated", value: "0")
        XCTAssertEqual(bitmap(), "rating.empty", "and clearing it puts the dot back")
    }

    /// The same gap on the type it was most surprising for: a `togglebutton` flipped by an ordinary
    /// click. `toggleActivation` writes `activated`, dispatches `onToggle` and `onActivate`, and
    /// returns true — every observable except the one the user looks at.
    func testAClickToggledButtonLightsUp() throws {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="200" h="200">
              <togglebutton id="lamp" x="0" y="0" w="20" h="20"
                            image="lamp.off" activeImage="lamp.on"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { renderer.teardown() }
        let lamp = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "lamp").first)

        func bitmap() -> String? {
            renderer.sceneNodes().first { $0.object.xmlID == "lamp" }?.bitmapID
        }
        XCTAssertEqual(bitmap(), "lamp.off")

        let scripts = try WinampModernScriptRuntime(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { scripts.teardown() }

        XCTAssertTrue(scripts.toggleActivation(of: lamp))
        XCTAssertEqual(bitmap(), "lamp.on", "one click, one lit lamp")

        XCTAssertTrue(scripts.toggleActivation(of: lamp))
        XCTAssertEqual(bitmap(), "lamp.off", "and a second click puts it out")
    }

    // MARK: - What must not change

    /// The rest state is the whole regression surface, and it is empty: a button nothing has
    /// activated draws `image`, exactly as before. No corpus skin declares `activated="1"` in its
    /// markup, so this fix moves no skin's launch appearance.
    func testAnUntouchedButtonIsUnchanged() throws {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="200" h="200">
              <button id="plain" x="0" y="0" w="20" h="20"
                      image="plain.off" activeImage="plain.on"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { renderer.teardown() }

        XCTAssertEqual(renderer.sceneNodes().first { $0.object.xmlID == "plain" }?.bitmapID,
                       "plain.off")
    }

    /// A pressed or hovered button still answers with its `downimage`/`hoverimage`: those are checked
    /// *before* the active branch, and an activated button must not swallow the press feedback.
    func testPressAndHoverStillOutrankActivation() throws {
        let loaded = try makeSkin(xml: """
        <WasabiXML>
          <container id="main">
            <layout id="normal" w="200" h="200">
              <button id="rate.2" x="0" y="0" w="27" h="20" image="rating.empty"
                      activeImage="rating.star" downImage="rating.down" hoverImage="rating.hover"/>
            </layout>
          </container>
        </WasabiXML>
        """)
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: TestHost())
        addTeardownBlock { renderer.teardown() }
        let button = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "rate.2").first)
        _ = button.setAttribute("activated", value: "1")

        XCTAssertEqual(renderer.bitmapIDForTesting(button, pressed: true, hovered: false),
                       "rating.down")
        XCTAssertEqual(renderer.bitmapIDForTesting(button, pressed: false, hovered: true),
                       "rating.hover")
        XCTAssertEqual(renderer.bitmapIDForTesting(button, pressed: false, hovered: false),
                       "rating.star")
    }

    // MARK: -

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

    private func makeSkin(xml: String) throws -> WinampModernLoadedSkin {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernBB26Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("BB26-\(UUID().uuidString).wal")
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
