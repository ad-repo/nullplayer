import XCTest
import AppKit
@testable import NullPlayer

/// Opt-in render harness. Phases 3–8 never watched a target skin paint — every check was structural
/// (graph built, scripts ran), which is exactly why a vertical-flip bug in every bitmap draw could
/// survive 490+ green tests. This renders the real scene to a PNG so the output can be looked at.
///
///     WINAMP_MODERN_ENGINE=/path/ClassicPro_2.01.exe \
///     WINAMP_MODERN_WAL=/path/cPro-Bento.wal \
///     WINAMP_MODERN_RENDER_DUMP=/path/to/dump-dir \
///       swift test --filter WinampModernRenderDumpTests
final class WinampModernRenderDumpTests: XCTestCase {

    func testRendersEachContainerToPNG() throws {
        let env = ProcessInfo.processInfo.environment
        guard let walPath = env["WINAMP_MODERN_WAL"], let dumpPath = env["WINAMP_MODERN_RENDER_DUMP"] else {
            throw XCTSkip("Set WINAMP_MODERN_WAL and WINAMP_MODERN_RENDER_DUMP (and WINAMP_MODERN_ENGINE for cPro).")
        }
        let dumpDirectory = URL(fileURLWithPath: dumpPath, isDirectory: true)
        try FileManager.default.createDirectory(at: dumpDirectory, withIntermediateDirectories: true)

        var store: ClassicProEngineStore?
        if let enginePath = env["WINAMP_MODERN_ENGINE"] {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("WinampModernRenderDump-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
            let engineStore = ClassicProEngineStore(rootDirectory: directory)
            _ = try ClassicProEngineImporter(store: engineStore)
                .importEngine(from: URL(fileURLWithPath: enginePath))
            store = engineStore
        }

        // With no WINAMP_MODERN_ENGINE the already-installed engine store is used, so a cPro skin
        // renders from the engine the app itself imported instead of failing on `load.xml`.
        let loaded = try WinampModernSkinLoader(engineStore: store ?? .shared)
            .load(from: URL(fileURLWithPath: walPath))
        defer { loaded.teardown() }
        let host = RenderHost()
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: host)
        defer { runtime.teardown() }
        try runtime.start()

        if env["WINAMP_MODERN_RENDER_XUI"] != nil {
            func walk(_ objects: [WasabiObject]) {
                for object in objects {
                    if !object.scriptBindings.isEmpty {
                        print("XUI \(object.typeName) id=\(object.xmlID ?? "-") "
                              + "isXUITag=\(loaded.runtime.types.isXUITag(object.typeName)) "
                              + "scripts=\(object.scriptBindings.map { ($0.logicalPath as NSString).lastPathComponent }) "
                              + "onsetxuiparam=\(runtime.hasBinding(for: object, event: "onsetxuiparam")) "
                              + "onscriptloaded=\(runtime.hasBinding(for: object, event: "onscriptloaded"))")
                    }
                    walk(object.children)
                }
            }
            walk(loaded.runtime.graph.roots)
        }
        // The measured-demand list: what the skin's load + `onscriptloaded` pass actually reached for
        // and did not find. Printed here so the harness answers "missing art, bad geometry, or a
        // script that never ran" in one run.
        let report = loaded.compatibilityReport(withRuntime: runtime)
        print("RENDER-DUMP compatibility level=\(report.level)\n\(report.summary)")
        for finding in report.findings.sorted(by: { $0.severity.rawValue < $1.severity.rawValue }) {
            print("FINDING [\(finding.severity)] \(finding.category.rawValue)/\(finding.code) "
                  + "×\(finding.count) \(finding.message) @\(finding.location ?? "-")")
        }

        // The reconciled surface picture: what the skin declared, what was embedded, what NullPlayer
        // synthesized, and what is left to the classic fallback.
        let inventory = loaded.surfaceInventory
        print("RENDER-DUMP arrangement=\(inventory.arrangement) "
              + "embedded=\(inventory.embeddedKinds.map(\.rawValue).sorted()) "
              + "declared=\(inventory.declaredContainers.map { "\($0.key.rawValue)=\($0.value)" }.sorted()) "
              + "synthesized=\(loaded.surfaceSynthesis.synthesizedContainers.map { "\($0.key.rawValue)=\($0.value)" }.sorted()) "
              + "fallback=\(loaded.surfaceSynthesis.unavailable.map(\.key.rawValue).sorted())")

        let containers = WinampModernContainerTopology.windowContainers(graph: loaded.runtime.graph)
        print("RENDER-DUMP containers: \(containers.map { "\($0.id) main=\($0.isMainPlayer)" })")
        XCTAssertFalse(containers.isEmpty, "Skin declares no window containers.")

        // The surface picture must be *consistent* for any skin, measured or not: each surface has
        // exactly one home, an SUI skin is never synthesized into, and nothing is synthesized that
        // the skin already shows. This is the assertion that would catch a duplicate playlist window.
        let hostedIDs = Set(containers.map(\.id))
        let catalog = WinampModernSurfaceCoordinator.makeCatalog(
            loadedSkin: loaded, hostedContainerIDs: hostedIDs,
            embeddedContainerID: containers.first(where: \.isMainPlayer)?.object.stableID)
        for kind in WinampModernSurfaceInventory.managedKinds {
            let embedded = inventory.embeddedKinds.contains(kind)
            let declared = inventory.declaredContainers[kind]
            let synthesized = loaded.surfaceSynthesis.synthesizedContainers[kind]
            if embedded {
                XCTAssertNil(synthesized,
                             "\(kind.rawValue) is embedded; synthesizing a window would duplicate it")
            }
            if let synthesized {
                XCTAssertEqual(inventory.arrangement, .separateWindows,
                               "an SUI skin's surfaces are embedded, not missing")
                XCTAssertNil(declared, "\(kind.rawValue) already has a declared window")
                XCTAssertTrue(hostedIDs.contains(synthesized),
                              "synthesized container '\(synthesized)' never opened")
            }
        }
        print("RENDER-DUMP catalog: \(catalog.summaryLine)")

        // Written beside the PNGs so a dump can be read without the console scrollback.
        let sidecar = [
            "skin: \((walPath as NSString).lastPathComponent)",
            "arrangement: \(inventory.arrangement)",
            "catalog: \(catalog.summaryLine)",
            "containers: \(containers.map(\.id).joined(separator: " "))",
            "",
            report.summary,
        ].joined(separator: "\n")
        try sidecar.write(to: dumpDirectory.appendingPathComponent("surfaces.txt"),
                          atomically: true, encoding: .utf8)

        for info in containers {
            // A fixed clock makes ticker/animation frames reproducible; set
            // WINAMP_MODERN_RENDER_CLOCK to a different value to capture a later frame.
            let clock = Double(env["WINAMP_MODERN_RENDER_CLOCK"] ?? "") ?? 0
            guard let renderer = try? WasabiSceneRenderer(loadedSkin: loaded, host: host,
                                                          containerID: info.id, clock: { clock }) else {
                print("RENDER-DUMP \(info.id): no renderable normal layout")
                continue
            }
            for layoutID in renderer.availableLayoutIDs {
                _ = try? renderer.activateLayout(id: layoutID)
                let size = renderer.canvasSize
                print("RENDER-DUMP \(info.id)/\(layoutID): \(Int(size.width))x\(Int(size.height)), "
                      + "\(renderer.sceneNodes().count) nodes")
                // WINAMP_MODERN_RENDER_PROBE=<container>/<layout> dumps that scene's node list.
                if env["WINAMP_MODERN_RENDER_PROBE"] == "\(info.id)/\(layoutID)" {
                    for node in renderer.sceneNodes() {
                        print("PROBE \(node.object.typeName) id=\(node.object.xmlID ?? "-") "
                              + "frame=\(node.frame) clip=\(node.clip) bitmap=\(node.bitmapID ?? "-") "
                              + "attrs=\(node.object.attributes.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))")
                    }
                }
                let holders = renderer.componentHolders()
                if !holders.isEmpty {
                    print("HOLDERS \(info.id)/\(layoutID): "
                          + holders.map { "\($0.kind.rawValue)@\($0.object.xmlID ?? "-")\($0.frame)" }
                            .joined(separator: " "))
                }
                if env["WINAMP_MODERN_RENDER_BITMAPS"] != nil {
                    var missing: Set<String> = []
                    var resolved = 0
                    for node in renderer.sceneNodes() {
                        for id in [node.bitmapID, node.object.attributes["background"]].compactMap({ $0 }) {
                            if renderer.resources.bitmap(identifier: id) == nil { missing.insert(id) }
                            else { resolved += 1 }
                        }
                    }
                    print("BITMAPS \(info.id)/\(layoutID): resolved=\(resolved) "
                          + "missing=\(missing.sorted().joined(separator: " "))")
                }
                guard size.width >= 1, size.height >= 1,
                      let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                              bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { continue }
                // `drawText` ends in `NSString.draw(in:withAttributes:)`, which renders into the
                // *current NSGraphicsContext* — not the CGContext it was handed. Without this the
                // harness silently drops every TrueType/system-font string while the real app (which
                // always has a current context inside `NSView.draw`) shows them.
                let previous = NSGraphicsContext.current
                NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
                renderer.draw(in: context)
                NSGraphicsContext.current = previous
                guard let image = context.makeImage() else { continue }
                let url = dumpDirectory.appendingPathComponent("\(info.id)-\(layoutID).png")
                let rep = NSBitmapImageRep(cgImage: image)
                try rep.representation(using: .png, properties: [:])?.write(to: url)
                print("RENDER-DUMP wrote \(url.path)")
            }
            renderer.teardown()
        }
    }

    private final class RenderHost: WinampModernHost {
        var playbackState: PlaybackState = .playing
        var currentTime: TimeInterval = 73
        var duration: TimeInterval = 245
        var volume: Double = 0.7
        var shuffleEnabled = false
        var repeatEnabled = false
        var trackTitle = "A Very Long Song Title That Must Scroll Across The Display"
        var trackInfo = "NullPlayer QA"
        var trackDisplayTitle = "Some Artist - A Very Long Song Title That Must Scroll Across The Display"
        var bitrateKbps = 320
        var sampleRateHz = 44_100
        var channelCount = 2
        var spectrumLevels: [Float] = (0..<64).map { Float(($0 % 16)) / 16 }

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
