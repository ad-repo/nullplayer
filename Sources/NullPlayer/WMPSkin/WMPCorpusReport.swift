import CryptoKit
import Foundation

struct WMPCorpusArchiveFacts: Hashable, Codable {
    let entryCount: Int
    let compressedBytes: UInt64
    let uncompressedBytes: UInt64
    let maximumCompressionRatio: Double
    let definitionPath: String
    let textEncoding: WMPTextEncoding
    let viewCount: Int
}

struct WMPCorpusRenderMetrics: Hashable, Codable {
    let viewID: String
    let canvasSize: WMPSize
    let resolvedNodeCount: Int
    let unresolvedNodeCount: Int
    let commandCount: Int
    let hitTargetCount: Int
    let widgetCount: Int
    let firstRenderMilliseconds: Double
    let warmRenderMilliseconds: Double
    let twoXRenderMilliseconds: Double
    let resizeBuildMilliseconds: Double
    let hitTestMicroseconds: Double
    let repaintAreaRatio: Double
    let peakCacheBytes: Int
}

enum WMPCorpusConfidence: String, Hashable, Codable {
    case high
    case medium
    case low
    case rejected
}

struct WMPCorpusSkinReport: Codable {
    let filename: String
    let sha256: String
    let loadMilliseconds: Double
    let warmLoadMilliseconds: Double?
    let archive: WMPCorpusArchiveFacts?
    let compatibility: WMPCompatibilityReport?
    let unknownTags: [WMPInventoryItem]
    let unknownAttributes: [WMPInventoryItem]
    let unknownMembers: [WMPInventoryItem]
    let unknownEvents: [WMPInventoryItem]
    let renderMetrics: [WMPCorpusRenderMetrics]
    let diagnostics: [WMPDiagnostic]
    let confidence: WMPCorpusConfidence
}

struct WMPCorpusReport: Codable {
    let formatVersion: Int
    let generatedAt: Date
    let skinCount: Int
    let acceptedCount: Int
    let rejectedCount: Int
    let skins: [WMPCorpusSkinReport]
}

/// Opt-in analysis for user-supplied skins. The report contains engine facts and measurements only:
/// it never writes archives, artwork, screenshots, or render buffers.
struct WMPCorpusReportHarness: @unchecked Sendable {
    static let formatVersion = 1
    private let loader: WMPSkinLoader

    init(loader: WMPSkinLoader = WMPSkinLoader()) {
        self.loader = loader
    }

    func analyze(urls: [URL]) async -> WMPCorpusReport {
        var reports: [WMPCorpusSkinReport] = []
        for url in urls.sorted(by: { WMPPath.less($0.lastPathComponent, $1.lastPathComponent) }) {
            reports.append(await analyze(url: url))
        }
        return WMPCorpusReport(formatVersion: Self.formatVersion, generatedAt: Date(),
            skinCount: reports.count, acceptedCount: reports.filter { $0.archive != nil }.count,
            rejectedCount: reports.filter { $0.archive == nil }.count, skins: reports)
    }

    func writeReport(for urls: [URL], to outputURL: URL) async throws -> WMPCorpusReport {
        let report = await analyze(urls: urls)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(report)
        try await Task.detached(priority: .utility) {
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: outputURL, options: .atomic)
        }.value
        return report
    }

    private func analyze(url: URL) async -> WMPCorpusSkinReport {
        let digest = (try? await Task.detached(priority: .utility) {
            try Self.hashFile(at: url)
        }.value) ?? "unavailable"
        let started = CFAbsoluteTimeGetCurrent()
        do {
            let skin = try await loader.load(from: url)
            let loadMilliseconds = Self.elapsed(since: started)
            let warmStarted = CFAbsoluteTimeGetCurrent()
            _ = try await loader.load(from: url)
            let warmLoadMilliseconds = Self.elapsed(since: warmStarted)
            let facts = Self.archiveFacts(skin)
            var metrics: [WMPCorpusRenderMetrics] = []
            var reportDiagnostics = skin.diagnostics
            for view in skin.views {
                do {
                    metrics.append(try await Self.measure(viewID: view.id, skin: skin))
                } catch let failure as WMPFailure {
                    reportDiagnostics.append(contentsOf: failure.diagnostics)
                } catch {
                    reportDiagnostics.append(WMPDiagnostic(.renderFailed,
                        "Report measurement failed for view '\(view.id)': \(error.localizedDescription)"))
                }
            }
            let unknownTags = Self.unknown(skin.compatibilityReport.tags, supported: Self.supportedTags)
            let unknownAttributes = Self.unknown(skin.compatibilityReport.attributes,
                                                  supported: Self.supportedAttributes,
                                                  permitsEventPrefix: true)
            let unknownMembers = skin.compatibilityReport.members.filter { !Self.supports(memberPath: $0.name) }
            let unknownEvents = Self.unknown(skin.compatibilityReport.events, supported: Self.supportedEvents)
            let confidence = Self.confidence(unknownTags: unknownTags, unknownAttributes: unknownAttributes,
                unknownMembers: unknownMembers, unknownEvents: unknownEvents,
                diagnostics: reportDiagnostics, metrics: metrics, viewCount: skin.views.count)
            return WMPCorpusSkinReport(filename: url.lastPathComponent, sha256: digest,
                loadMilliseconds: loadMilliseconds, warmLoadMilliseconds: warmLoadMilliseconds,
                archive: facts, compatibility: skin.compatibilityReport,
                unknownTags: unknownTags, unknownAttributes: unknownAttributes,
                unknownMembers: unknownMembers, unknownEvents: unknownEvents,
                renderMetrics: metrics, diagnostics: reportDiagnostics, confidence: confidence)
        } catch let failure as WMPFailure {
            return WMPCorpusSkinReport(filename: url.lastPathComponent, sha256: digest,
                loadMilliseconds: Self.elapsed(since: started), warmLoadMilliseconds: nil,
                archive: nil, compatibility: nil,
                unknownTags: [], unknownAttributes: [], unknownMembers: [], unknownEvents: [],
                renderMetrics: [], diagnostics: failure.diagnostics, confidence: .rejected)
        } catch {
            return WMPCorpusSkinReport(filename: url.lastPathComponent, sha256: digest,
                loadMilliseconds: Self.elapsed(since: started), warmLoadMilliseconds: nil,
                archive: nil, compatibility: nil,
                unknownTags: [], unknownAttributes: [], unknownMembers: [], unknownEvents: [],
                renderMetrics: [], diagnostics: [WMPDiagnostic(.invalidArchive,
                    "Corpus analysis failed: \(error.localizedDescription)")], confidence: .rejected)
        }
    }

    private static func archiveFacts(_ skin: WMPLoadedSkin) -> WMPCorpusArchiveFacts {
        let compressed = skin.archive.entries.reduce(UInt64(0)) { $0 &+ $1.compressedSize }
        let uncompressed = skin.archive.entries.reduce(UInt64(0)) { $0 &+ $1.uncompressedSize }
        let ratio = skin.archive.entries.reduce(0.0) { result, entry in
            guard entry.uncompressedSize > 0 else { return result }
            let value = entry.compressedSize == 0 ? .infinity
                : Double(entry.uncompressedSize) / Double(entry.compressedSize)
            return max(result, value)
        }
        return WMPCorpusArchiveFacts(entryCount: skin.archive.entries.count,
            compressedBytes: compressed, uncompressedBytes: uncompressed,
            maximumCompressionRatio: ratio.isFinite ? ratio : Double(WMPPhase0Limits.entryCompressionRatio),
            definitionPath: skin.definitionPath, textEncoding: skin.textEncoding,
            viewCount: skin.views.count)
    }

    private static func measure(viewID: String, skin: WMPLoadedSkin) async throws -> WMPCorpusRenderMetrics {
        let store = WMPImageStore(provider: skin.archive)
        let builder = WMPSceneBuilder(loadedSkin: skin, imageStore: store)
        let scene = try await builder.build(viewID: viewID)
        let renderer = WMPRenderer(imageStore: store)
        let first = try await renderer.render(scene: scene, backingScale: 1)
        let warm = try await renderer.render(scene: scene, backingScale: 1)
        let twoX = try await renderer.render(scene: scene, backingScale: 2)

        let resizeStarted = CFAbsoluteTimeGetCurrent()
        let proposed = scene.resizeLimits.clamp(WMPSize(width: scene.canvasSize.width + 64,
                                                         height: scene.canvasSize.height + 48))
        _ = try await builder.build(viewID: viewID, requestedSize: proposed)
        let resizeMilliseconds = elapsed(since: resizeStarted)

        let hitStarted = CFAbsoluteTimeGetCurrent()
        let tester = WMPHitTester(hits: scene.hits)
        let samples = 1_000
        for index in 0..<samples {
            let x = scene.canvasSize.width * CGFloat((index * 37) % samples) / CGFloat(samples)
            let y = scene.canvasSize.height * CGFloat((index * 61) % samples) / CGFloat(samples)
            _ = tester.hitTest(WMPPoint(x: x, y: y))
        }
        let hitMicroseconds = elapsed(since: hitStarted) * 1_000 / Double(samples)
        let canvasArea = Double(scene.canvasSize.width * scene.canvasSize.height)
        let dirtyArea = scene.dirtyBounds.map { Double(max(0, $0.width) * max(0, $0.height)) } ?? canvasArea
        return WMPCorpusRenderMetrics(viewID: viewID, canvasSize: scene.canvasSize,
            resolvedNodeCount: scene.metrics.resolvedNodeCount,
            unresolvedNodeCount: scene.metrics.unresolvedNodeCount,
            commandCount: scene.commands.count, hitTargetCount: scene.hits.count,
            widgetCount: scene.widgets.count,
            firstRenderMilliseconds: first.renderMilliseconds,
            warmRenderMilliseconds: warm.renderMilliseconds,
            twoXRenderMilliseconds: twoX.renderMilliseconds,
            resizeBuildMilliseconds: resizeMilliseconds,
            hitTestMicroseconds: hitMicroseconds,
            repaintAreaRatio: canvasArea > 0 ? min(1, dirtyArea / canvasArea) : 0,
            peakCacheBytes: store.metrics.peakCacheBytes)
    }

    private static func elapsed(since start: CFAbsoluteTime) -> Double {
        (CFAbsoluteTimeGetCurrent() - start) * 1_000
    }

    private static func hashFile(at url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func unknown(_ items: [WMPInventoryItem], supported: Set<String>,
                                permitsEventPrefix: Bool = false) -> [WMPInventoryItem] {
        items.filter {
            let name = $0.name.lowercased()
            return !supported.contains(name) && !(permitsEventPrefix && name.hasPrefix("on"))
        }
    }

    private static func supports(memberPath path: String) -> Bool {
        let parts = path.lowercased().split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return false }
        let object: String
        let member: String
        switch parts[0] {
        case "player" where parts.count >= 3:
            switch parts[1] {
            case "controls": object = "controls"; member = parts[2]
            case "settings": object = "settings"; member = parts[2]
            case "currentmedia": object = "media"; member = parts[2]
            case "currentplaylist": object = "playlist"; member = parts[2]
            case "network": object = "network"; member = parts[2]
            default: object = "player"; member = parts[1]
            }
        case "metadata": object = "metadata"; member = parts[1]
        case "theme": object = "theme"; member = parts[1]
        case "view": object = "view"; member = parts[1]
        case "eq": object = "eq"; member = parts[1]
        case "vis": object = "vis"; member = parts[1]
        case "ipl", "ddpl": object = "playlist"; member = parts[1]
        default:
            object = parts[0]; member = parts[1]
            if WMPJScriptCompatibility.supports(object: "element", member: member) { return true }
        }
        return WMPJScriptCompatibility.supports(object: object, member: member)
    }

    private static func confidence(unknownTags: [WMPInventoryItem], unknownAttributes: [WMPInventoryItem],
                                   unknownMembers: [WMPInventoryItem], unknownEvents: [WMPInventoryItem],
                                   diagnostics: [WMPDiagnostic], metrics: [WMPCorpusRenderMetrics],
                                   viewCount: Int) -> WMPCorpusConfidence {
        guard metrics.count == viewCount, !metrics.isEmpty,
              !diagnostics.contains(where: { $0.severity == .error }) else { return .low }
        let unknownDemand = unknownTags.reduce(0) { $0 + $1.count }
            + unknownAttributes.reduce(0) { $0 + $1.count }
            + unknownMembers.reduce(0) { $0 + $1.count }
            + unknownEvents.reduce(0) { $0 + $1.count }
        let unresolved = metrics.reduce(0) { $0 + $1.unresolvedNodeCount }
        if unknownDemand == 0 && unresolved == 0 { return .high }
        if unknownTags.isEmpty && unresolved <= metrics.reduce(0, { $0 + $1.resolvedNodeCount }) / 10 {
            return .medium
        }
        return .low
    }

    private static let supportedTags: Set<String> = [
        "theme", "view", "subview", "text", "image", "button", "buttongroup", "buttonelement",
        "slider", "volumeslider", "seekslider", "balanceslider", "playlist", "dropdownplaylist",
        "playelement", "pausebutton", "stopelement", "prevelement", "nextelement", "rewbutton",
        "rewelement", "ffwdbutton", "ffwdelement", "returnbutton", "shufflebutton",
        "equalizersettings", "popup", "wmpeffects", "video", "wmpvideo", "player", "network", "script"
    ]

    private static let supportedAttributes: Set<String> = [
        "id", "name", "title", "accessiblename", "tooltip", "left", "top", "width", "height",
        "minwidth", "minheight", "maxwidth", "maxheight", "horizontalalignment", "verticalalignment",
        "zindex", "visible", "enabled", "sticky", "value", "position", "min", "max", "minvalue",
        "maxvalue", "image", "background", "backgroundimage", "backgroundcolor", "backgroundtiled",
        "hoverimage", "downimage", "disabledimage", "mappingimage", "mappingcolor", "transparencycolor",
        "cropleft", "croptop", "cropwidth", "cropheight", "backgroundcropleft", "backgroundcroptop",
        "backgroundcropwidth", "backgroundcropheight", "tiled", "fonttype", "fontsize", "fontstyle",
        "foregroundcolor", "color", "justification", "scriptfile"
    ]

    private static let supportedEvents: Set<String> = [
        "onload", "onclose", "ontimer", "onmousedown", "onmouseup", "onclick", "onchange",
        "openstatechange", "playstatechange", "status_onchange", "modechange", "buffering_onchange",
        "reception_onchange", "viewchange"
    ]
}
