import XCTest
import AppKit
@testable import NullPlayer

/// Throwaway probe: how much of a skin's player window answers a press with a window drag.
///
///     WINAMP_MODERN_DRAG_PROBE="$HOME/Library/Application Support/NullPlayer/WinampModernSkins" \
///       swift test --filter WinampModernDragProbe
final class WinampModernDragProbe: XCTestCase {

    @MainActor
    func testDragCoverageAcrossTheCorpus() throws {
        let env = ProcessInfo.processInfo.environment
        guard let root = env["WINAMP_MODERN_DRAG_PROBE"] else { throw XCTSkip("set WINAMP_MODERN_DRAG_PROBE") }
        var wals: [URL] = []
        let rootURL = URL(fileURLWithPath: root)
        if rootURL.pathExtension.lowercased() == "wal" {
            wals = [rootURL]
        } else {
            wals = ((try? FileManager.default.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension.lowercased() == "wal" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
        for wal in wals {
            do { try probe(wal) } catch { print("SKIN \(wal.lastPathComponent) FAILED \(error)") }
        }
    }

    @MainActor
    private func probe(_ wal: URL) throws {
        let loaded = try WinampModernSkinLoader(engineStore: .shared).load(from: wal)
        defer { loaded.teardown() }
        let host = RenderHost()
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: host)
        defer { runtime.teardown() }
        var renderersByContainer: [String: WasabiSceneRenderer] = [:]
        for info in WinampModernContainerTopology.windowContainers(graph: loaded.runtime.graph) {
            guard let renderer = try? WasabiSceneRenderer(loadedSkin: loaded, host: host,
                                                          containerID: info.id, clock: { 0 }) else { continue }
            renderersByContainer[info.id] = renderer
        }
        let all = Array(renderersByContainer.values)
        runtime.resolvedGeometryRequested = { object in
            for renderer in all { if let g = renderer.resolvedGeometry(of: object) { return g } }
            return nil
        }
        try runtime.start()
        let wanted = ProcessInfo.processInfo.environment["WINAMP_MODERN_DRAG_CONTAINERS"]
            .map { Set($0.split(separator: ",").map(String.init)) }
        for (containerID, renderer) in renderersByContainer.sorted(by: { $0.key < $1.key }) {
            if let wanted, !wanted.contains(containerID) { continue }
            let view = WinampModernMainView(renderer: renderer, scripts: runtime, host: host,
                                            componentHost: nil)
            let size = renderer.canvasSize
            guard size.width > 1, size.height > 1 else { continue }
            view.setFrameSize(size)
            var drag = 0, nothing = 0, blocked = 0
            var map: [String] = []
            var blockers: [String: Int] = [:]
            var blockerObjects: [String: WasabiObject] = [:]
            let step: CGFloat = 3
            var y: CGFloat = 0
            while y < size.height {
                var row = ""
                var x: CGFloat = 0
                while x < size.width {
                    let point = CGPoint(x: x, y: y)
                    if let object = renderer.object(at: point) {
                        if view.shouldDragWindow(from: object) { drag += 1; row += "#" }
                        else {
                            blocked += 1
                            let key = "\(object.typeName)#\(object.xmlID ?? "-")"
                            blockers[key, default: 0] += 1
                            blockerObjects[key] = object
                            row += "."
                        }
                    } else { nothing += 1; row += " " }
                    x += step
                }
                map.append(row)
                y += step
            }
            let total = max(1, drag + nothing + blocked)
            // The top 24px is where a person reaches for a titlebar.
            let topRows = map.prefix(8)
            let topCells = max(1, topRows.reduce(0) { $0 + $1.count })
            let topDrag = topRows.reduce(0) { $0 + $1.filter { $0 == "#" }.count }
            let top = blockers.sorted { $0.value > $1.value }.prefix(6)
                .map { "\($0.key)=\($0.value * 100 / total)%" }.joined(separator: " ")
            print(String(format: "DRAG %-34@ %-16@ %3dx%-3d drag=%2d%% none=%2d%% blocked=%2d%% top24=%3d%% | %@",
                         wal.deletingPathExtension().lastPathComponent as NSString,
                         containerID as NSString,
                         Int(size.width), Int(size.height),
                         drag * 100 / total, nothing * 100 / total, blocked * 100 / total,
                         topDrag * 100 / topCells,
                         top as NSString))
            if ProcessInfo.processInfo.environment["WINAMP_MODERN_DRAG_WHY"] != nil {
                for (key, _) in blockers.sorted(by: { $0.value > $1.value }).prefix(8) {
                    guard let object = blockerObjects[key] else { continue }
                    let events = ["onleftbuttondown", "onleftbuttonup", "onleftclick",
                                  "ondoubleclick", "onrightbuttondown"]
                        .filter { runtime.hasBinding(for: object, event: $0) }
                    print("  WHY \(key) move=\(object.attributes["move"] ?? "-") action=\(object.attributes["action"] ?? "-") ghost=\(object.attributes["ghost"] ?? "-") bindings=\(events)")
                }
            }
            if ProcessInfo.processInfo.environment["WINAMP_MODERN_DRAG_MAP"] != nil {
                for row in map { print("  MAP |\(row)|") }
            }
        }
    }

    /// The NullPlayer-owned windows: the skin's standard frame around our own NSView.
    @MainActor
    func testHostedWindowDragCoverage() throws {
        let env = ProcessInfo.processInfo.environment
        guard let root = env["WINAMP_MODERN_DRAG_HOSTED"] else { throw XCTSkip("set WINAMP_MODERN_DRAG_HOSTED") }
        let rootURL = URL(fileURLWithPath: root)
        var wals: [URL] = []
        if rootURL.pathExtension.lowercased() == "wal" { wals = [rootURL] } else {
            wals = ((try? FileManager.default.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension.lowercased() == "wal" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
        for wal in wals {
            do { try probeHosted(wal) } catch { print("HOSTED \(wal.lastPathComponent) FAILED \(error)") }
        }
    }

    @MainActor
    private func probeHosted(_ wal: URL) throws {
        let loaded = try WinampModernSkinLoader(engineStore: .shared).load(from: wal)
        defer { loaded.teardown() }
        let host = RenderHost()
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: host)
        defer { runtime.teardown() }
        try runtime.start()
        guard let instantiate = loaded.runtime.instantiateHostedWindow else {
            print("HOSTED \(wal.lastPathComponent) no instantiator"); return
        }
        for definition in WinampModernHostedWindowRegistry.all {
            guard case .skinFrame(let frame) = loaded.surfaceSynthesis.hostedWindows[definition.id] else {
                print("HOSTED \(wal.deletingPathExtension().lastPathComponent) \(definition.id.rawValue) classic fallback")
                continue
            }
            do {
                let graphRoot = try instantiate(.init(definition: definition, frame: frame))
                let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: host,
                                                       containerID: definition.id.containerIdentifier)
                let view = WinampModernMainView(renderer: renderer, scripts: runtime, host: host,
                                                componentHost: nil, drivesScripts: false)
                let rootsBefore = Set(loaded.runtime.graph.roots.map(\.stableID))
                try runtime.startTrustedHostedWindowScripts(beneath: graphRoot)
                for root in loaded.runtime.graph.roots where !rootsBefore.contains(root.stableID) {
                    print("  NEWROOT \(root.typeName) id=\(root.xmlID ?? "-")")
                }
                func dumpTree(_ object: WasabiObject, depth: Int) {
                    guard depth < 3 else { return }
                    for child in object.children {
                        print("  TREE \(String(repeating: "  ", count: depth))\(child.typeName) "
                              + "id=\(child.xmlID ?? "-")")
                        dumpTree(child, depth: depth + 1)
                    }
                }
                if ProcessInfo.processInfo.environment["WINAMP_MODERN_DRAG_HOSTED_TREE"] != nil {
                    dumpTree(graphRoot, depth: 0)
                }
                var size = renderer.canvasSize
                view.setFrameSize(size)
                view.scriptsDidStart()
                view.needsLayout = true
                view.layoutSubtreeIfNeeded()
                // Our own NSView sits over every host-window holder and eats the press there.
                let surfaceRects = renderer.componentHolders().compactMap { holder -> CGRect? in
                    guard case .hostWindow = holder.surfaceID else { return nil }
                    return holder.frame
                }
                var drag = 0, other = 0
                var map: [String] = []
                let step: CGFloat = 3
                var y: CGFloat = 0
                while y < size.height {
                    var row = ""
                    var x: CGFloat = 0
                    while x < size.width {
                        let point = CGPoint(x: x, y: y)
                        if surfaceRects.contains(where: { $0.contains(point) }) { row += "S"; other += 1 }
                        else if let object = renderer.object(at: point), view.shouldDragWindow(from: object) {
                            drag += 1; row += "#"
                        } else { other += 1; row += "." }
                        x += step
                    }
                    map.append(row)
                    y += step
                }
                let total = max(1, drag + other)
                // The title strip: everything above the topmost hosted surface.
                let firstSurfaceRow = map.firstIndex { $0.contains("S") } ?? map.count
                let strip = map.prefix(firstSurfaceRow)
                let stripCells = max(1, strip.reduce(0) { $0 + $1.count })
                let stripDrag = strip.reduce(0) { $0 + $1.filter { $0 == "#" }.count }
                print(String(format: "HOSTED %-30@ %-14@ %3dx%-3d drag=%2d%% strip=%2dpx strip_drag=%3d%% surfaces=%d",
                             wal.deletingPathExtension().lastPathComponent as NSString,
                             definition.id.rawValue as NSString,
                             Int(size.width), Int(size.height), drag * 100 / total,
                             firstSurfaceRow * 3, stripDrag * 100 / stripCells,
                             surfaceRects.count))
                if ProcessInfo.processInfo.environment["WINAMP_MODERN_DRAG_MAP"] != nil {
                    for row in map { print("  MAP |\(row)|") }
                }
                // A skin whose chrome is a second window (Itemskin) builds it as a new dynamic
                // container while the frame script starts. Composite it over the content window at
                // the frame object's own offset — which is exactly what the glue does live — so the
                // dump is a picture of the finished window rather than of half of it.
                var chrome: (renderer: WasabiSceneRenderer, origin: CGPoint, size: CGSize)?
                if let newRoot = loaded.runtime.graph.roots.first(where: {
                    !rootsBefore.contains($0.stableID)
                        && $0.typeName.caseInsensitiveCompare("container") == .orderedSame
                }) {
                    // The chrome window *is* the content window: Itemskin's `layout.clear.ml`
                    // is 660x274, exactly its `MLibrary` layout, and the script keeps one over
                    // the other. The frame object's own rect inside the layout is not its
                    // placement.
                    // The materializer grows the window to the chrome's own floor; the probe has no
                    // window, so it does the same to the renderer before measuring.
                    if let floor = runtime.hostedChromeFloor(of: graphRoot) {
                        let grown = CGSize(width: max(size.width, floor.width),
                                           height: max(size.height, floor.height))
                        if grown != size {
                            _ = renderer.resize(to: grown)
                            view.setFrameSize(renderer.canvasSize)
                            size = renderer.canvasSize
                        }
                    }
                    if let chromeRenderer = try? WasabiSceneRenderer(
                        loadedSkin: loaded, host: host, containerID: newRoot.xmlID ?? "") {
                        chrome = (chromeRenderer, .zero, size)
                    }
                }
                if let dump = ProcessInfo.processInfo.environment["WINAMP_MODERN_DRAG_HOSTED_PNG"] {
                    let scale = 2
                    // Room for chrome that overhangs the content window on any side, so the dump is
                    // the whole window rather than the part of it our own container covers.
                    let pad = chrome.map {
                        (left: max(0, -$0.origin.x), top: max(0, -$0.origin.y),
                         right: max(0, $0.origin.x + $0.size.width - size.width),
                         bottom: max(0, $0.origin.y + $0.size.height - size.height))
                    } ?? (left: 0, top: 0, right: 0, bottom: 0)
                    let canvas = CGSize(width: size.width + pad.left + pad.right,
                                        height: size.height + pad.top + pad.bottom)
                    let pixels = CGSize(width: canvas.width * CGFloat(scale),
                                        height: canvas.height * CGFloat(scale))
                    if let context = CGContext(data: nil, width: Int(pixels.width),
                                               height: Int(pixels.height), bitsPerComponent: 8,
                                               bytesPerRow: 0,
                                               space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                               bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) {
                        context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
                        // Canvas is bottom-left, skin space top-left: put the content window where
                        // the padding leaves room for it.
                        context.translateBy(x: pad.left, y: pad.bottom)
                        let previous = NSGraphicsContext.current
                        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
                        renderer.draw(in: context)
                        if let chrome {
                            _ = chrome.renderer.resize(to: chrome.size)
                            context.saveGState()
                            context.translateBy(x: chrome.origin.x,
                                                y: -(chrome.origin.y + (chrome.size.height - size.height)))
                            chrome.renderer.draw(in: context)
                            context.restoreGState()
                            chrome.renderer.teardown()
                        }
                        NSGraphicsContext.current = previous
                        if let image = context.makeImage() {
                            let directory = URL(fileURLWithPath: dump, isDirectory: true)
                            try? FileManager.default.createDirectory(at: directory,
                                                                     withIntermediateDirectories: true)
                            let url = directory.appendingPathComponent(
                                "\(wal.deletingPathExtension().lastPathComponent)-\(definition.id.rawValue).png")
                            try? NSBitmapImageRep(cgImage: image)
                                .representation(using: .png, properties: [:])?.write(to: url)
                            print("HOSTED-PNG \(url.path)")
                        }
                    }
                }
            } catch {
                print("HOSTED \(wal.deletingPathExtension().lastPathComponent) \(definition.id.rawValue) FAILED \(error)")
            }
        }
    }

    private final class RenderHost: WinampModernHost {
        var playbackState: PlaybackState = .playing
        var currentTime: TimeInterval = 73
        var duration: TimeInterval = 245
        var volume: Double = 0.7
        var shuffleEnabled = false
        var repeatEnabled = false
        var trackTitle = "A Very Long Song Title That Must Scroll"
        var trackArtist = "Some Artist"
        var trackAlbum = "An Album"
        var trackInfo = "NullPlayer QA"
        var trackDisplayTitle = "Some Artist - A Very Long Song Title"
        var bitrateKbps = 320
        var sampleRateHz = 44_100
        var channelCount = 2
        var spectrumLevels: [Float] = (0..<64).map { Float(($0 % 16)) / 16 }
        var vuLevels: (left: Double, right: Double) = (0.5, 0.5)
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
