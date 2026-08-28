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
                try runtime.startTrustedHostedWindowScripts(beneath: graphRoot)
                let size = renderer.canvasSize
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
