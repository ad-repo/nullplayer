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
    /// Every colour this node keys out of its artwork, in authored order: `transparencyColor`
    /// then `clippingColor`. A subview commonly declares both, with different colours.
    let colorKeys: [WMPColor]
    /// The key to use **only if the decoded sprite carries no alpha channel of its own**, set when
    /// the node declares no key at all. WMP's implicit transparency colour; see `WMPColorKey`.
    let implicitColorKey: WMPColor?
    let tiled: Bool
    let interpolation: WMPImageInterpolation
    let mappingMask: WMPSceneMappingMask?
    /// The archive path of a `clippingImage` shaping this draw, and the colours keyed out of it.
    /// The mask itself lives in the image store — the immutable scene owns no `CGImage`.
    let clippingMaskPath: String?
    let clippingMaskKeys: [WMPColor]

    init(resourcePath: String, sourceRect: WMPRect?, colorKeys: [WMPColor], tiled: Bool,
         interpolation: WMPImageInterpolation, mappingMask: WMPSceneMappingMask?,
         clippingMaskPath: String? = nil, clippingMaskKeys: [WMPColor] = [],
         implicitColorKey: WMPColor? = nil) {
        self.resourcePath = resourcePath
        self.sourceRect = sourceRect
        self.colorKeys = colorKeys
        self.implicitColorKey = implicitColorKey
        self.tiled = tiled
        self.interpolation = interpolation
        self.mappingMask = mappingMask
        self.clippingMaskPath = clippingMaskPath
        self.clippingMaskKeys = clippingMaskKeys
    }
}

struct WMPSceneMappingMask: Hashable, Codable {
    let mapping: WMPMappingImage
    let nodeIDs: [Int]
}

struct WMPSceneText: Hashable, Codable {
    let value: String
    let fontName: String
    let fontSize: CGFloat
    let bold: Bool
    let italic: Bool
    let underline: Bool
    /// `fontSmoothing="false"` is authored by 96 of 178 corpus skins, almost always on the small
    /// pixel readouts where antialiasing turns a crisp 6px digit into grey mush.
    let smoothed: Bool
    let color: WMPColor
    let alignment: WMPTextAlignment
}

enum WMPPaint: Hashable, Codable {
    case fill(WMPColor)
    case image(WMPSceneImage)
    case text(WMPSceneText)
}

enum WMPWidgetKind: String, Hashable, Codable {
    case text, slider, playlist, dropdownPlaylist, popup, editBox, listBox, effects, video
}

struct WMPWidget: Hashable, Codable {
    let stableID: Int
    let nodeID: String?
    let kind: WMPWidgetKind
    let frame: WMPRect
    let clipRect: WMPRect?
    let label: String
    let toolTip: String?
    let minimumValue: Double?
    let maximumValue: Double?
    /// Set for `.slider` widgets only: what the scene drew, and the geometry needed to turn a
    /// pointer position back into a value. Without the direction a vertical equaliser bar is
    /// dragged along its width, which is one pixel of travel per 28 dB.
    let value: Double?
    let direction: WMPSliderDirection?
    let borderSize: CGFloat
    let thumbSize: WMPSize?
    /// The `wmpprop:` path this control's `value` is bound to, lower-cased. A skin that declares
    /// one has said where its slider writes; see `WMPTransportAction.boundAction`.
    let valueBindingPath: String?

    init(stableID: Int, nodeID: String?, kind: WMPWidgetKind, frame: WMPRect, clipRect: WMPRect?,
         label: String, toolTip: String?, minimumValue: Double? = nil, maximumValue: Double? = nil,
         value: Double? = nil, direction: WMPSliderDirection? = nil, borderSize: CGFloat = 0,
         thumbSize: WMPSize? = nil, valueBindingPath: String? = nil) {
        self.stableID = stableID
        self.nodeID = nodeID
        self.kind = kind
        self.frame = frame
        self.clipRect = clipRect
        self.label = label
        self.toolTip = toolTip
        self.minimumValue = minimumValue
        self.maximumValue = maximumValue
        self.value = value
        self.direction = direction
        self.borderSize = borderSize
        self.thumbSize = thumbSize
        self.valueBindingPath = valueBindingPath
    }
}

struct WMPPaintCommand: Hashable, Codable {
    let stableID: Int
    let nodeID: String?
    let frame: WMPRect
    let clipRect: WMPRect?
    let zIndex: Int
    let documentOrder: Int
    let paint: WMPPaint
    /// WMP's `alphaBlend`, 0-255 normalized to 0-1 and inherited down the subtree. 38 corpus skins
    /// author it and 717 of those uses are `alphaBlend="0"` — an element the skin means to be
    /// invisible until a script fades it in. Drawing those opaque paints a slab over the artwork.
    let alpha: CGFloat

    init(stableID: Int, nodeID: String?, frame: WMPRect, clipRect: WMPRect?, zIndex: Int,
         documentOrder: Int, paint: WMPPaint, alpha: CGFloat = 1) {
        self.stableID = stableID
        self.nodeID = nodeID
        self.frame = frame
        self.clipRect = clipRect
        self.zIndex = zIndex
        self.documentOrder = documentOrder
        self.paint = paint
        self.alpha = alpha
    }
}

/// The pointer shape a control asks for. The corpus is overwhelmingly *named* — `hand` alone is
/// 1,942 of 2,319 non-empty `cursor` attributes — so the named set is the whole of the feature for
/// practical purposes, and the ~70 `.cur`/`.ani` file references are a documented remainder
/// (Windows cursor formats, which no macOS decoder reads).
enum WMPCursor: String, Hashable, Codable {
    case system, hand, sizeAll, sizeWE, sizeNS, sizeNWSE, sizeNESW

    init?(authored: String) {
        switch authored.lowercased() {
        case "system", "default", "arrow": self = .system
        case "hand": self = .hand
        case "sizeall": self = .sizeAll
        case "sizewe": self = .sizeWE
        case "sizens": self = .sizeNS
        case "sizenwse": self = .sizeNWSE
        case "sizenesw": self = .sizeNESW
        default: return nil
        }
    }
}

struct WMPHitMetadata: Hashable, Codable {
    let stableID: Int
    let nodeID: String?
    let kind: String
    let frame: WMPRect
    let clipRect: WMPRect?
    let zIndex: Int
    let documentOrder: Int
    let action: WMPTransportAction?
    let sticky: Bool
    let enabled: Bool
    let mappingImage: WMPMappingImage?
    let mappingTargets: [WMPHitTarget]
    let cursor: WMPCursor?
    /// `tabStop="false"` is authored 544 times against `"true"`'s 170: a skin marks most of its
    /// controls *out* of the keyboard ring and leaves a handful in. Absent is in, as in WMP.
    let tabStop: Bool
    /// A `CUSTOMSLIDER`'s greyscale position map, when it has one. It answers both halves of the
    /// control — the value under the pointer, and which filmstrip frame to draw.
    let positionMap: WMPPositionMap?
    /// The tip the pointer resting on this control should show, already resolved for its state:
    /// `downToolTip` while it is down, `upToolTip` otherwise, and plain `toolTip` behind both.
    /// Authored by nearly the whole corpus — `upToolTip` alone is 4,789 uses across 176 of 179
    /// archives — and shown by nothing until 2026-09-08.
    let toolTip: String?

    init(stableID: Int, nodeID: String?, kind: String, frame: WMPRect, clipRect: WMPRect?,
         zIndex: Int, documentOrder: Int, action: WMPTransportAction?, sticky: Bool, enabled: Bool,
         mappingImage: WMPMappingImage?, mappingTargets: [WMPHitTarget],
         cursor: WMPCursor? = nil, tabStop: Bool = true, positionMap: WMPPositionMap? = nil,
         toolTip: String? = nil) {
        self.stableID = stableID; self.nodeID = nodeID; self.kind = kind; self.frame = frame
        self.clipRect = clipRect; self.zIndex = zIndex; self.documentOrder = documentOrder
        self.action = action; self.sticky = sticky; self.enabled = enabled
        self.mappingImage = mappingImage; self.mappingTargets = mappingTargets
        self.cursor = cursor; self.tabStop = tabStop; self.positionMap = positionMap
        self.toolTip = toolTip
    }
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
    /// The view's authored `resizable`/`resizAble`. A `.wmz` window is borderless, so AppKit
    /// supplies no resize edge of its own and the affordance has to be drawn from this: 477 of the
    /// corpus's 596 views state it, and it is what says whether the window has draggable edges at
    /// all. Absent means false, as in WMP — never invent a resize handle the skin did not ask for.
    let isResizable: Bool
    let commands: [WMPPaintCommand]
    let hits: [WMPHitMetadata]
    let widgets: [WMPWidget]
    let geometries: [Int: WMPResolvedGeometry]
    let unresolved: [WMPUnresolvedGeometry]
    let diagnostics: [WMPDiagnostic]
    let dirtyBounds: WMPRect?
    let metrics: WMPSceneMetrics
    let wasBuiltOnMainThread: Bool

    init(viewID: String, canvasSize: WMPSize, resizeLimits: WMPResizeLimits,
         isResizable: Bool = false,
         commands: [WMPPaintCommand], hits: [WMPHitMetadata], widgets: [WMPWidget] = [],
         geometries: [Int: WMPResolvedGeometry], unresolved: [WMPUnresolvedGeometry],
         diagnostics: [WMPDiagnostic], dirtyBounds: WMPRect?, metrics: WMPSceneMetrics,
         wasBuiltOnMainThread: Bool) {
        self.viewID = viewID; self.canvasSize = canvasSize; self.resizeLimits = resizeLimits
        self.isResizable = isResizable
        self.commands = commands; self.hits = hits; self.widgets = widgets
        self.geometries = geometries; self.unresolved = unresolved; self.diagnostics = diagnostics
        self.dirtyBounds = dirtyBounds; self.metrics = metrics
        self.wasBuiltOnMainThread = wasBuiltOnMainThread
    }

    /// The layout the skin is drawn at, in the coordinates its script reads: parent-relative
    /// origin and resolved size, keyed by stable id. Handed to the script runtime so
    /// `element.height` answers the height the element actually has — including one that came from
    /// its background artwork or from an alignment stretch — rather than only what markup authored.
    var scriptGeometry: [Int: WMPRect] { geometries.mapValues(\.localFrame) }

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
