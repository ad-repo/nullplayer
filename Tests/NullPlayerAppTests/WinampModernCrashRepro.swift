import XCTest
import AppKit
@testable import NullPlayer

/// Opt-in harness that drives a *live-ish* session — every standard event dispatched at every object
/// in graph order, with a redraw after each, then a spread of clocks for ticker/animation frames.
/// The dump harness only ever renders a skin's initial state; this one exists to catch a draw that
/// a script mutation makes fatal.
///
/// Written for the 2026-08-16 report of an
/// `-[__NSPlaceholderDictionary initWithObjects:forKeys:count:]: attempt to insert nil object` abort
/// inside `NSString.size(withAttributes:)` in `drawText`, while running cPro-Bento.
/// **It does not reproduce that crash** — not with the current code and not with the font hardening
/// reverted — so the trigger is still something this harness does not do (real host metadata, a
/// theme switch, UI Size, or an event it does not fire). Leave it here for the next attempt.
///
///     WINAMP_MODERN_ENGINE=… WINAMP_MODERN_WAL=… swift test --filter WinampModernCrashRepro
final class WinampModernCrashRepro: XCTestCase {

    func testDriveSkinAndDraw() throws {
        let env = ProcessInfo.processInfo.environment
        guard let walPath = env["WINAMP_MODERN_WAL"] else { throw XCTSkip("set WINAMP_MODERN_WAL") }

        var store: ClassicProEngineStore?
        if let enginePath = env["WINAMP_MODERN_ENGINE"] {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("CrashRepro-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
            let engineStore = ClassicProEngineStore(rootDirectory: directory)
            _ = try ClassicProEngineImporter(store: engineStore)
                .importEngine(from: URL(fileURLWithPath: enginePath))
            store = engineStore
        }

        let loaded = try WinampModernSkinLoader(engineStore: store).load(from: URL(fileURLWithPath: walPath))
        defer { loaded.teardown() }
        let host = ReproHost()
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: host)
        defer { runtime.teardown() }
        try runtime.start()

        var clock: Double = 0
        let renderer = try XCTUnwrap(try? WasabiSceneRenderer(loadedSkin: loaded, host: host,
                                                              containerID: "main", clock: { clock }))
        defer { renderer.teardown() }

        func drawOnce(_ label: String) {
            let size = renderer.canvasSize
            guard size.width >= 1, size.height >= 1,
                  let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                          bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return }
            let previous = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            renderer.draw(in: context)
            NSGraphicsContext.current = previous
        }

        drawOnce("initial")

        // Every event a live session fires at objects, in graph order, redrawing after each so a
        // mutation that makes a text object undrawable shows up attributed to its own event.
        var objects: [WasabiObject] = []
        func collect(_ list: [WasabiObject]) {
            for object in list { objects.append(object); collect(object.children) }
        }
        collect(loaded.runtime.graph.roots)
        print("REPRO driving \(objects.count) objects")

        for event in ["onleftclick", "onrightclick", "onenterarea", "onleavearea", "ontimer",
                      "onsetvisible", "onresize", "onsetposition", "ontoggle", "ontargetreached"] {
            for object in objects {
                let arguments: [MakiValue]
                switch event {
                case "onsetposition": arguments = [.integer(128)]
                case "ontoggle", "onsetvisible": arguments = [.boolean(true)]
                case "onresize": arguments = [.integer(0), .integer(0), .integer(400), .integer(300)]
                default: arguments = []
                }
                _ = try? runtime.dispatch(object: object, event: event, arguments: arguments)
            }
            clock += 1.7
            drawOnce(event)
            print("REPRO survived \(event)")
        }

        // And a spread of clocks, for ticker/animation frames.
        for step in 0..<40 {
            clock = Double(step) * 0.37
            drawOnce("clock \(clock)")
        }
        print("REPRO completed")
    }

    private final class ReproHost: WinampModernHost {
        var playbackState: PlaybackState = .playing
        var currentTime: TimeInterval = 12
        var duration: TimeInterval = 200
        var volume: Double = 0.7
        var shuffleEnabled = false
        var repeatEnabled = false
        var trackTitle = "Title"
        var trackInfo = "Artist"
        var spectrumLevels: [Float] = (0..<64).map { Float($0 % 16) / 16 }

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
