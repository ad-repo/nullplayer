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
    /// **A `<TEXT>` is a box, and WMP clips to it.** `scrolling` is what a skin turns on when the
    /// value is wider than the box — `WoW` writes `metadata.scrolling = (metadata.textWidth >
    /// metadata.width)` on every metadata change — and `scrollingDelay`/`scrollingAmount` are the
    /// marquee's clock and step. 114 of the 180 corpus archives author `scrolling`.
    let scrolling: Bool
    /// Milliseconds between marquee steps as authored. WMP falls back to 85 ms when a skin supplies
    /// less than its 30 ms minimum, rather than accepting the faster value.
    let scrollDelayMilliseconds: Double
    /// Skin pixels per marquee step. WMP's default is 1.
    let scrollAmount: CGFloat

    var effectiveScrollDelayMilliseconds: Double {
        scrollDelayMilliseconds >= 30 ? scrollDelayMilliseconds : 85
    }
}

enum WMPPaint: Hashable, Codable {
    case fill(WMPColor)
    case image(WMPSceneImage)
    case text(WMPSceneText)
}

enum WMPWidgetKind: String, Hashable, Codable {
    case text, slider, playlist, dropdownPlaylist, popup, editBox, listBox, effects, video
}

extension WMPWidgetKind {
    /// The platform host measures its popup controls at 24 points high.
    var intrinsicHeight: CGFloat? {
        switch self {
        case .dropdownPlaylist, .popup: return 24
        default: return nil
        }
    }
}

/// The container artwork that shapes a hosted surface: which image, which colours it keys out,
/// and where that image sits in scene coordinates.
///
/// **A windowless `<EFFECTS>` is confined by its container's *shape*, not by its bounding box.**
/// The rect has never been the picture: `Plus! Bionic Dot` authors a 169x160 `visMask` whose
/// `main_vis_back.png` keys `#ff00ff` out of everything but a round lens with an arc cut from its
/// lower edge to clear the transport ring. Clipping the visualizer to the rect instead put a hard
/// 169x160 slab of spectrum across the face and over the play controls.
///
/// Cerulean needs none of this and gets none: its `face.bmp` is *opaque artwork drawn over* the
/// visualizer through `commandSplitIndex`, so the surround is hidden by paint rather than by shape,
/// and its `<EFFECTS>` parent declares no keyed background at all.
struct WMPWidgetRegionMask: Hashable, Codable {
    let resourcePath: String
    let keyedOut: [WMPColor]
    /// The masking image's frame in scene coordinates. It is not always the widget's own frame, so
    /// the offset between the two is what aligns the mask over the surface.
    let frame: WMPRect
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
    let videoPresentation: WMPVideoPresentation?
    /// Where this widget sits in `WMPScene.commands`: the index the walk had reached when the node
    /// was visited, which is before its own paint commands and before any of its children. Paint
    /// commands at or after it are the artwork a skin means to draw *over* the widget's content —
    /// which is how a negative `zIndex` on an `<EFFECTS>` puts the visualizer behind a
    /// colour-keyed hole in the parent's `backgroundImage` (Cerulean, Plus! Professional).
    ///
    /// It is an index and not a zIndex threshold on purpose: `WMPSceneBuilder.walk` sorts only
    /// siblings, so `commands` is DFS order and is not globally sorted by zIndex.
    let commandSplitIndex: Int?
    /// The inherited `alphaBlend` of the subtree this widget sits in, 0-1 — the same number
    /// `WMPPaintCommand.alpha` carries, computed by the same walk.
    ///
    /// **A hosted AppKit surface is not exempt from its parent's fade.** `alphaBlend` inherits, so
    /// a `.wmz` hides a pane it has not opened yet by fading the container to zero, and the scene's
    /// paint commands have honoured that since they were filtered at `emit`. The widgets were not:
    /// `Plus! Bionic Dot` declares `<subview id="visMask" … alphaBlend="0"><effects …/></subview>`
    /// and fades the mask to 255 in `toggleVis()`, so its artwork correctly drew nothing while the
    /// `<EFFECTS>` overlay drew a 169x160 visualizer rectangle over the face. Five other archives
    /// author the same idiom — `Plus! Professional`, `Plus! Pulsar`, `Plus! HueShifter`,
    /// `Plus! Plasma Ball` and `Halloween` — and it is the Plus! house style, not one skin.
    ///
    /// Cerulean is untouched by it: its `<effects zIndex="-1">` sits under a colour-keyed hole with
    /// no `alphaBlend` anywhere above it, so this reads 1 and the surface hosts exactly as before.
    let alpha: CGFloat
    /// Set for `.effects` only: the container shape this surface is confined to, when the skin
    /// authored one. See `WMPWidgetRegionMask`.
    let regionMask: WMPWidgetRegionMask?

    /// `<EFFECTS windowed="true">`: the visualization is a **windowed** control, and in WMP a
    /// windowed control is a real child window that the skin's own painting cannot draw over.
    /// `windowed="false"` (106 skins) and an absent attribute (46, Cerulean among them) are
    /// windowless — composited into the artwork at the node's place in the paint order, which is
    /// what `commandSplitIndex` exists for. 17 corpus skins declare `true`.
    let isWindowedEffects: Bool

    init(stableID: Int, nodeID: String?, kind: WMPWidgetKind, frame: WMPRect, clipRect: WMPRect?,
         label: String, toolTip: String?, minimumValue: Double? = nil, maximumValue: Double? = nil,
         value: Double? = nil, direction: WMPSliderDirection? = nil, borderSize: CGFloat = 0,
         thumbSize: WMPSize? = nil, valueBindingPath: String? = nil,
         videoPresentation: WMPVideoPresentation? = nil, alpha: CGFloat = 1,
         regionMask: WMPWidgetRegionMask? = nil,
         commandSplitIndex: Int? = nil, isWindowedEffects: Bool = false) {
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
        self.videoPresentation = videoPresentation
        self.alpha = alpha
        self.regionMask = regionMask
        self.commandSplitIndex = commandSplitIndex
        self.isWindowedEffects = isWindowedEffects
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

    /// Where `commands` splits into what is drawn *below* the effects surface and what is drawn
    /// over it. Nil when the scene hosts no `<EFFECTS>`, in which case the whole list is one layer
    /// and the rendered output is exactly what it has always been.
    ///
    /// A scene with several effects widgets takes the earliest, so every surface sits under the
    /// same overlay — the artwork between two of them is authored to cover both.
    ///
    var effectsCommandSplitIndex: Int? {
        widgets.filter { $0.kind == .effects }.compactMap(\.commandSplitIndex).min()
    }

    /// The rects a **windowed** visualization occupies, in which the skin's own overlay artwork is
    /// not drawn at all.
    ///
    /// `windowed="true"` makes the surface a real child window in WMP, and nothing the skin paints
    /// can be layered over a windowed control — which is exactly why 106 corpus skins say
    /// `windowed="false"` and only 17 say `true`. The split index alone does not express that: it
    /// hosts the surface *between* two rasters, so artwork declared after the effects node still
    /// lands on top. `xsn_sports` is built on the occlusion: its video and visualisation drawers
    /// retract to a resting position 26px inside the bottom of the effects rect
    /// (`top="jscript:view.height-123"` against a rect ending at `view.height-97`), and the
    /// windowed surface is what hides the retracted drawer. Drawing it anyway put the drawer's own
    /// background — `vis_drawer_1.png` pictures a button and a slider row — across the bottom of
    /// the visualization while the drawer was shut (W144).
    ///
    /// Clearing the rect rather than dropping the overlay is what keeps the rest of the drawer
    /// right: the part of it below the effects rect is the tab and its cover, and that must still
    /// draw. It is also why this is not "make the surface opaque" — a stopped player draws no
    /// visualization at all, and what belongs in the hole then is whatever the skin painted
    /// *before* the effects node (`visMask`'s own black), not a black rectangle of ours.
    ///
    /// Windowless is untouched and stays the common case: Cerulean's `<effects zIndex="-1">` under
    /// a colour-keyed hole in `face.bmp` is the shape the split index was built for.
    var windowedEffectsRects: [WMPRect] {
        widgets.filter { $0.kind == .effects && $0.isWindowedEffects }.compactMap { widget in
            guard let clip = widget.clipRect else { return widget.frame }
            return widget.frame.intersection(clip)
        }
    }

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
