import CoreGraphics
import Foundation

/// A `control` of a form, read once as the skin loads (`AIMPSkinIndex`): its class with what that
/// class alone reads (`AIMPControlClass`), its bindings by the pin they feed, where it sits, how its
/// picture and text draw, and what pressing it does. The layout, the dataflow and the scripts read
/// these rather than the node's properties; a control a script restyled
/// (`AIMPSkinState.Script.propertySets`) is read again with the script's values over its own
/// (`restyled`). `reference/layout.md` § Controls has the rules.
final class AIMPSkinControl: AIMPSkinElement, Sendable {
    /// Which control it is, for the skin's life (a restyled control keeps it): the window keys what
    /// the pointer is over and holds, and the gauges it eases, by it, not by name: a name may be
    /// missing or shared, and two controls with one name lit and released as one.
    struct ID: Hashable, Sendable {
        let value: Int
    }

    let id: ID
    let node: AIMPNode
    let name: String?
    /// The name a script restyles it by: its name, else its `link` (`<control link="Playlist">`).
    let styleKey: String?
    let kind: AIMPControlClass
    let bindings: AIMPSkinBindings
    let gates: [AIMPSkinLink]
    let savedShown: Bool
    /// `PlaceInfo`; a control without one does not show.
    let placement: AIMPPlacement.Info?
    /// The controls it holds, placed in its rect (Cassette-3D's `Panel` of animators).
    let controls: [AIMPSkinControl]

    // MARK: Picture

    /// Its `Skin`: the picture, a filmstrip of frames.
    let picture: String?
    /// The frame that is its mask (`MaskFrame`, on its `Skin` or on the resource that names; `-1`
    /// is none: Red Bias 2.0's visualization, which clipped to its logo).
    let maskFrame: Int?
    /// `BlendingModeOpacity` below 255, and `BlendingMode` as Core Graphics draws it.
    let opacity: Double?
    let blend: CGBlendMode?
    /// Mirrored (Akai GX-R60's right reel: the left's strip, flipped and run backwards).
    let flipX: Bool
    let flipY: Bool

    /// What its caption or display shows, and in what font.
    let text: Text
    let input: Input

    /// `controls`: the controls it holds, read (`AIMPSkinIndex` numbers them all).
    init(_ node: AIMPNode, id: ID, index: AIMPSkinIndex, controls: [AIMPSkinControl]) {
        let props = node.properties
        self.id = id
        self.node = node
        name = node["name"]
        styleKey = node["name"].flatMap { $0.isEmpty ? nil : $0 } ?? node["link"]
        bindings = AIMPSkinBindings(node, names: index.names)
        kind = AIMPControlClass(node, bindings: bindings, resources: index.resources)
        gates = bindings.all("Visibility")
        savedShown = AIMPSkinItem.Layout(node).savedShown
        placement = props["PlaceInfo"].map(AIMPPlacement.Info.init)
        self.controls = controls

        picture = props["Skin"]?.reference
        maskFrame = (props["Skin"]?["MaskFrame"].flatMap { Int($0) }
            ?? picture.flatMap { index.resources[$0]?["Resource"]?["MaskFrame"] }.flatMap { Int($0) })
            .flatMap { $0 >= 0 ? $0 : nil }
        opacity = Double(props["BlendingModeOpacity"]?.reference ?? "").flatMap { $0 < 255 ? $0 : nil }
        blend = Self.blendMode(props["BlendingMode"]?.reference)
        flipX = props["FlipHorizontally"]?.reference == "True"
        flipY = props["FlipVertically"]?.reference == "True"
        text = Text(node, bindings: bindings, index: index)
        input = Input(node, bindings: bindings, index: index)
    }

    /// This control with properties a script set over its own (`AIMPNode.overriding`), read again;
    /// the controls it holds stay as they are.
    func restyled(_ sets: [String: String], index: AIMPSkinIndex) -> AIMPSkinControl {
        AIMPSkinControl(node.overriding(sets), id: id, index: index, controls: controls)
    }

    /// An animator's settings; nil for any other control.
    var animator: AIMPControlClass.Animator? {
        if case .animator(let animator) = kind { animator } else { nil }
    }

    /// AIMP's `BlendingMode` as Core Graphics draws it; nil for `bmNormal` and anything unknown.
    static func blendMode(_ name: String?) -> CGBlendMode? {
        switch name {
        case "bmScreen": return .screen
        case "bmDifference": return .difference
        case "bmMultiply": return .multiply
        case "bmAdd", "bmAdditive", "bmAddition": return .plusLighter
        case "bmLighten": return .lighten
        case "bmDarken": return .darken
        case "bmOverlay": return .overlay
        case "bmExclusion": return .exclusion
        case "bmSoftLight": return .softLight
        case "bmHardLight": return .hardLight
        default: return nil
        }
    }
}

extension AIMPPlacement {
    /// A control's `PlaceInfo`: `anchors` and `margins` (left, top, right, bottom) and a `Size`.
    struct Info: Sendable {
        let anchors: [Int]
        let margins: [Int]
        /// Nil when it is not two numbers: the control then has no room.
        let size: CGSize?

        init(_ property: AIMPNode) {
            anchors = AIMPNode.numbers(property["anchors"] ?? "1,1,0,0")
            margins = AIMPNode.numbers(property["margins"] ?? "0,0,0,0")
            let sizes = AIMPNode.numbers(property["Size"] ?? "0,0")
            size = sizes.count == 2 ? CGSize(width: sizes[0], height: sizes[1]) : nil
        }

        /// Where it sits in `parent`, with the margins a script `moved` (0 left … 3 bottom).
        func rect(in parent: CGRect, moved: [Int: Double]? = nil) -> CGRect {
            var margins = margins
            for (side, value) in moved ?? [:] where margins.indices.contains(side) { margins[side] = Int(value.rounded()) }
            guard let size else { return .zero }
            return AIMPPlacement.rect(anchors: anchors, margins: margins, size: size, in: parent) ?? .zero
        }
    }
}
