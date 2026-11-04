import CoreGraphics
import Foundation

/// What items and controls share as the layout shows or hides them: a name scripts and bindings
/// find them by, their `Visibility` bindings, and whether the editor saved them shown.
protocol AIMPSkinElement: AnyObject {
    /// The node's `name`, as the skin wrote it (it may be empty).
    var name: String? { get }
    /// `Visibility` bindings: the element hides while any reads 0.
    var gates: [AIMPSkinLink] { get }
    /// Not saved hidden (`Visible`/`InitialVisible` False), or with `AutoHide`, which shows it
    /// whenever it fits whatever the editor saved (Soot's all-in-one trigger, saved hidden, shows
    /// once the window is 550 px wide).
    var savedShown: Bool { get }
}

/// A layout `item` of a form (or the form's root `layout`), read once as the skin loads
/// (`AIMPSkinIndex`): how it docks in its parent, its picture and colour, and the items and controls
/// it holds as the skin wrote them (a script may move some elsewhere: `AIMPSkinLayout.heldItems`).
final class AIMPSkinItem: AIMPSkinElement, Sendable {
    let node: AIMPNode
    let name: String?
    let gates: [AIMPSkinLink]
    let savedShown: Bool
    /// An `item`, not the form's root.
    let isItem: Bool
    let isTabbedGroup: Bool
    /// A `LayoutDockSite`, which holds a form of the skin's (`AIMPSkinDockSites`).
    let isDockSite: Bool
    let layout: Layout
    /// The `Texture` its picture fills it with, and the `Color` under it.
    let texture: String?
    let color: AIMPSkinColor?
    /// Whether it names a colour at all (an item showing nothing has none: `AIMPSkinLayout.isHollow`).
    let declaresColor: Bool
    let items: [AIMPSkinItem]
    let controls: [AIMPSkinControl]

    init(_ node: AIMPNode, compile: (AIMPNode) -> AIMPSkinControl, names: AIMPSkinIndex.Names) {
        let props = node.properties
        self.node = node
        name = node["name"]
        layout = Layout(node)
        gates = AIMPSkinBindings(node, names: names).all("Visibility")
        savedShown = layout.savedShown
        isItem = node.tag == "item"
        isTabbedGroup = layout.isTabbedGroup
        isDockSite = node["class"] == "LayoutDockSite"
        texture = props["Texture"]?.reference
        color = AIMPSkinColor(props["Color"])
        declaresColor = !(props["Color"]?.reference ?? "").isEmpty
        items = (node.child("items")?.children("item") ?? []).map { AIMPSkinItem($0, compile: compile, names: names) }
        controls = (node.child("controls")?.children("control") ?? []).map(compile)
    }

    /// How an item docks in its parent (`reference/layout.md` § Items), as `AIMPSkinAlignment` reads it.
    /// AIMP 3.0's translator measures the items it makes by it too (`AIMPSkinLegacy`).
    struct Layout: Sendable {
        let isTabbedGroup: Bool
        /// `Alignment`, read once; nil where the item has none: it runs down from the top.
        let dock: AIMPSkinDock?
        /// `AlignmentLevel`: lower docks first, against its edge.
        let level: Int
        /// `AlignmentMargins` (l, t, r, b), which sit outside the item.
        let margins: AIMPSkinImage.Margins?
        /// `Size`, `SizeMinimal` and `SizeMaximal`, read once; nil unless two numbers are given.
        let size: CGSize?
        let sizeMinimal: CGSize?
        let sizeMaximal: CGSize?
        let autoHide: Bool
        /// `AutoHideParentSizeThreshold`, when one is given above 0.
        let autoHideThreshold: Double?
        /// `AutoSize` is not False: a docked item's size follows what it holds.
        let autoSize: Bool
        /// Its clients share it along its row: AIMP's default; `ldVertical` shares it down.
        let isRow: Bool
        /// Not saved hidden (`Visible` or `InitialVisible` False), or `AutoHide` (`AIMPSkinElement.savedShown`).
        let savedShown: Bool

        init(_ node: AIMPNode) {
            let props = node.properties
            isTabbedGroup = node["class"] == "LayoutTabbedGroup"
            dock = props["Alignment"].map { AIMPSkinDock($0.reference) }
            level = Int(props["AlignmentLevel"]?.reference ?? "") ?? 0
            margins = AIMPSkinImage.Margins(props["AlignmentMargins"]?.reference)
            size = Self.size(props["Size"]?.reference)
            sizeMinimal = Self.size(props["SizeMinimal"]?.reference)
            sizeMaximal = Self.size(props["SizeMaximal"]?.reference)
            autoHide = props["AutoHide"]?.reference == "True"
            autoHideThreshold = Double(props["AutoHideParentSizeThreshold"]?.reference ?? "").flatMap { $0 > 0 ? $0 : nil }
            autoSize = props["AutoSize"]?.reference != "False"
            isRow = props["LayoutDirection"]?.reference != "ldVertical"
            savedShown = (props["Visible"]?.reference != "False" && props["InitialVisible"]?.reference != "False") || autoHide
        }

        /// Whether its size follows what it holds; measuring the `least` a form takes, a client's
        /// still counts, its size being its parent's (Unsquareable's six cover sizes, one shown at a
        /// time, say `AutoSize` False).
        func sizesToContent(least: Bool = false) -> Bool { autoSize || (least && dock == .client) }

        /// `size` grown by its `AlignmentMargins`: the slot it takes.
        func slot(_ size: CGSize) -> CGSize {
            guard let m = margins else { return size }
            return CGSize(width: size.width + CGFloat(m.left + m.right), height: size.height + CGFloat(m.top + m.bottom))
        }

        /// `rect` inset by its `AlignmentMargins`.
        func inset(_ rect: CGRect) -> CGRect { margins?.inset(rect) ?? rect }

        /// `size` no smaller than its `SizeMinimal`, side by side.
        func floored(_ size: CGSize) -> CGSize {
            guard let minimal = sizeMinimal else { return size }
            return CGSize(width: max(size.width, minimal.width), height: max(size.height, minimal.height))
        }

        /// Along `vertical` or across, one of its sizes when it is given and above 0.
        static func extent(_ size: CGSize?, vertical: Bool) -> CGFloat? {
            guard let size else { return nil }
            let extent = vertical ? size.height : size.width
            return extent > 0 ? extent : nil
        }

        /// "w,h": two numbers, else nil.
        private static func size(_ text: String?) -> CGSize? {
            let numbers = AIMPNode.numbers(text)
            return numbers.count == 2 ? CGSize(width: numbers[0], height: numbers[1]) : nil
        }
    }
}

/// An item's `Alignment`: the edge it docks to, or the room the docked ones leave (`laClient`). Any
/// other value (`laNone`) docks it nowhere: it lies over the room left, where an item with no
/// `Alignment` at all runs down from the top.
enum AIMPSkinDock: Hashable, Sendable {
    case top, bottom, left, right, client, none

    init(_ value: String?) {
        switch value {
        case "laTop": self = .top
        case "laBottom": self = .bottom
        case "laLeft": self = .left
        case "laRight": self = .right
        case "laClient": self = .client
        default: self = .none
        }
    }

    /// A side panel's: docked across its parent.
    var isSide: Bool { self == .left || self == .right }
}

extension AIMPSkinImage.Margins {
    /// Four numbers, left, top, right, bottom (`AlignmentMargins` "0,4,0,4"); nil for anything else.
    init?(_ text: String?) {
        let m = AIMPNode.numbers(text)
        guard m.count == 4 else { return nil }
        self.init(left: m[0], top: m[1], right: m[2], bottom: m[3])
    }
}

/// A colour property, read one way wherever a skin gives one: an ARGB number of its own, as its
/// `value` (LX-tix's `-16777216`, black) or a nested `Value` (Unsquareable's items, the list styles),
/// else the resource its `ID` names, which a script may repoint (`AIMPSkin.color(_:links:)`).
/// `.acs3` writes Delphi colours instead (`delphi`), and AIMP 3.0's and AIMP 2's forms are ARGB by
/// the time they are read (`AIMPSkinLegacy`).
enum AIMPSkinColor: Sendable, Equatable {
    case argb(UInt32)
    case resource(String)

    init?(_ property: AIMPNode?) {
        guard let property else { return nil }
        if let argb = Self.number(property) {
            self = .argb(UInt32(truncatingIfNeeded: argb))
        } else if let name = property.reference {
            self = .resource(name)
        } else {
            return nil
        }
    }

    /// The property's own ARGB, nil for none or a clear one: what a list's rows and an equalizer
    /// display's lines are drawn in, where a clear colour draws nothing.
    static func visible(_ property: AIMPNode?) -> UInt32? {
        guard case .argb(let argb)? = AIMPSkinColor(property), argb >> 24 != 0 else { return nil }
        return argb
    }

    /// `.acs3`'s colour, a Delphi number as the property's `value` (`ColorContent`, the playlist's
    /// `ItemHighlightColorPlaying`), as ARGB.
    static func delphi(_ property: AIMPNode?) -> UInt32? {
        property?["value"].flatMap { Int64($0) }.map(argb(delphi:))
    }

    /// The number a property holds: its `value`, else a nested `Value`'s.
    private static func number(_ property: AIMPNode) -> Int64? {
        (property["value"] ?? property.named["Value"]?["value"]).flatMap { Int64($0) }
    }
}

extension AIMPSkinItem {
    /// The first item called `name` in this one, itself included, depth first.
    func item(named name: String) -> AIMPSkinItem? {
        if isItem, self.name == name { return self }
        return items.lazy.compactMap { $0.item(named: name) }.first
    }
}
