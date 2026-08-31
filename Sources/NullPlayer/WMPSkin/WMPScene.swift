import CoreGraphics
import Foundation

enum WMPImageInterpolation: String, Codable {
    case none, low, medium, high
}

enum WMPTextAlignment: String, Codable {
    case left, center, right
}

struct WMPSceneImage: Hashable, Codable {
    let resourcePath: String
    let sourceRect: WMPRect?
    let colorKey: WMPColor?
    let tiled: Bool
    let interpolation: WMPImageInterpolation
}

struct WMPSceneText: Hashable, Codable {
    let value: String
    let fontName: String
    let fontSize: CGFloat
    let bold: Bool
    let color: WMPColor
    let alignment: WMPTextAlignment
}

enum WMPPaint: Hashable, Codable {
    case fill(WMPColor)
    case image(WMPSceneImage)
    case text(WMPSceneText)
}

struct WMPPaintCommand: Hashable, Codable {
    let stableID: Int
    let nodeID: String?
    let frame: WMPRect
    let clipRect: WMPRect?
    let zIndex: Int
    let documentOrder: Int
    let paint: WMPPaint
}

struct WMPHitMetadata: Hashable, Codable {
    let stableID: Int
    let nodeID: String?
    let kind: String
    let frame: WMPRect
    let clipRect: WMPRect?
    let zIndex: Int
}

struct WMPUnresolvedGeometry: Hashable, Codable {
    let stableID: Int
    let nodeID: String?
    let attribute: String
    let authoredValue: String
}

struct WMPSceneMetrics: Hashable, Codable {
    let resolvedNodeCount: Int
    let unresolvedNodeCount: Int
    let visibleBounds: WMPRect?
}

/// An immutable result of one layout transaction. Rendering and later hit testing consume the same
/// frames instead of independently reinterpreting the retained graph.
struct WMPScene: Hashable, Codable {
    let viewID: String
    let canvasSize: WMPSize
    let resizeLimits: WMPResizeLimits
    let commands: [WMPPaintCommand]
    let hits: [WMPHitMetadata]
    let geometries: [Int: WMPResolvedGeometry]
    let unresolved: [WMPUnresolvedGeometry]
    let diagnostics: [WMPDiagnostic]
    let dirtyBounds: WMPRect?
    let metrics: WMPSceneMetrics
    let wasBuiltOnMainThread: Bool

    var deterministicDump: String {
        var lines = ["view=\(viewID) size=\(WMPNumber.format(canvasSize.width))x\(WMPNumber.format(canvasSize.height)) resolved=\(metrics.resolvedNodeCount) unresolved=\(metrics.unresolvedNodeCount)"]
        lines += commands.map { command in
            let paint: String
            switch command.paint {
            case let .fill(color): paint = "fill:\(color)"
            case let .image(image): paint = "image:\(image.resourcePath)"
            case let .text(text): paint = "text:\(text.value)"
            }
            return "\(command.stableID) z=\(command.zIndex) order=\(command.documentOrder) frame=\(command.frame) \(paint)"
        }
        lines += unresolved.map { "unresolved \($0.stableID) \($0.attribute)=\($0.authoredValue)" }
        return lines.joined(separator: "\n")
    }
}
