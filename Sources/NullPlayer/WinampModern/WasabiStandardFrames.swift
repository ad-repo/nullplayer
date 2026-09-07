import Foundation

/// The Wasabi standard window frames, and the conventional tag ↔ groupdef pairing real skins rely on.
///
/// A `.wal` window is a frame plus a content group: `<Wasabi:StandardFrame:Status
/// content="pledit.content.group">`. The frame's own `standardframe.maki` instantiates the named
/// group into its client area at runtime, which is why the frame *must* be a real skin-supplied
/// groupdef with that script attached — the identifier-only shells we seed for missing Wasabi bases
/// build nothing and would give a synthesized window a title bar and an empty hole.
///
/// CornerAmp and Winamp Modern declare `xuitag="Wasabi:StandardFrame:Status"` on the groupdef, so the
/// tag resolves normally. **mmd3 declares the same conventional ids with no `xuitag` at all** — in
/// real Winamp the standard library supplies the tag and the skin only overrides the definition — so
/// without the pairing below its playlist window is a frame that instantiates nothing (measured: 5
/// scene nodes, an empty white rectangle).
enum WasabiStandardFrames {

    /// The frame flavours, in the order synthesis prefers them: a status bar is the richest, a static
    /// frame the barest.
    enum Flavour: String, CaseIterable {
        case statusbar
        case nostatusbar
        case `static`

        var groupIdentifier: String {
            switch self {
            case .statusbar: return "wasabi.standardframe.statusbar"
            case .nostatusbar: return "wasabi.standardframe.nostatusbar"
            case .static: return "wasabi.standardframe.static"
            }
        }

        var xuiTag: String {
            switch self {
            case .statusbar: return "Wasabi:StandardFrame:Status"
            case .nostatusbar: return "Wasabi:StandardFrame:NoStatus"
            case .static: return "Wasabi:StandardFrame:Static"
            }
        }
    }

    /// The measured conventional pairs. `modal` is included because skins declare it in the same
    /// block; synthesis never selects it (a modal frame hides its system menu).
    static let conventionalXUITags: [(tag: String, identifier: String)] =
        Flavour.allCases.map { ($0.xuiTag, $0.groupIdentifier) }
        + [("Wasabi:StandardFrame:Modal", "wasabi.standardframe.modal")]
}

extension WasabiStandardFrames {

    /// Where the client area sits inside a frame we drew ourselves.
    ///
    /// Only reached when the skin declares **no** `wasabi.standardframe.*` of its own, so these
    /// numbers never displace a skin's own chrome. Calibrated against `Winamp 3.0 Default`, the one
    /// corpus skin whose every full-size layout is a bare `<Wasabi:StandardFrame:*>`: its player's
    /// `placeholder` sits at `6,5` in the content group and lands at `11,20` in the skin's own
    /// screenshot, which puts the client origin at `5,15`; its resize grip is a 16px sprite at
    /// `254,85`, so the client must be at least 270x101 inside a 275x116 window, which is what the
    /// right and bottom insets below leave.
    static let contentInset = (x: 5.0, y: 15.0, width: -5.0, height: -15.0)

    /// The title strip drawn across the top of such a frame — `contentInset.y`, by construction: the
    /// client area starts where the strip ends.
    static var titleHeight: Double { contentInset.y }

    static func flavour(forTypeName typeName: String) -> Flavour? {
        Flavour.allCases.first { $0.xuiTag.caseInsensitiveCompare(typeName) == .orderedSame }
    }

    static func isStandardFrame(_ object: WasabiObject) -> Bool {
        flavour(forTypeName: object.typeName) != nil
    }

    /// Set on a `<Wasabi:StandardFrame:*>` instance whose groupdef the skin never supplied, so the
    /// renderer knows to paint the chrome Winamp's own frame would have drawn.
    static let hostedAttribute = "nullplayer.standardframe"

    static func isHostedFrame(_ object: WasabiObject) -> Bool {
        isStandardFrame(object) && object.attributes[hostedAttribute] == "1"
    }

    /// The edge drawn around a frame we painted ourselves. One point, inside `contentInset`'s
    /// margin, so it never moves an object the skin placed.
    static let borderWidth = 1.0

    /// The `<group>` node for this frame's client area, or `nil` when the frame names no content.
    ///
    /// A standard frame **names its body by group id** rather than nesting it, and in real Winamp the
    /// frame's own `standardframe.maki` does the `newGroup(getParam("content"))`. A skin that ships
    /// that groupdef ships the script with it; a skin that expects Winamp's ships neither, so without
    /// this the named group never enters the graph at all — the same shape as `WasabiTitleBox`.
    static func contentGroupNode(for object: WasabiObject, location: WalSourceLocation) -> WalXMLNode? {
        guard let content = object.attributes["content"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty else { return nil }
        return WalXMLNode(name: "group", attributes: [
            "id": content,
            "x": String(Int(contentInset.x)), "y": String(Int(contentInset.y)),
            "w": String(Int(contentInset.width)), "h": String(Int(contentInset.height)),
            "relatw": "1", "relath": "1",
        ], location: location)
    }
}

extension WasabiStandardFrames {

    /// A frame whose chrome the **skin** drew but whose content-instantiating script it left to
    /// Winamp — the case `contentGroupNode(for:location:)` above is the mirror image of.
    ///
    /// `<groupdef id="wasabi.standardframe.statusbar" inherit_content="scripts">` is a skin saying
    /// "this is my artwork, keep the scripts of the definition I am replacing", and the definition it
    /// replaces is Winamp's own `standardframe.xml` — which ships `standardframe.maki`, and which we
    /// do not have. Such a skin therefore claims the groupdef (so the hosted path above never fires)
    /// and declares no script of its own (so nothing ever runs `newGroup(getParam("content"))`), and
    /// its playlist window comes up as the skin's own chrome around nothing at all: measured on
    /// `TRON___Legacy.wal`, `Pledit/normal` was 18 nodes of border, title and status bar, with
    /// `pledit.content.group` — the component holder that *is* the playlist — never in the graph.
    /// The whole corpus has three of these (TRON Legacy, Sony Walkman, canum); every other skin
    /// either ships the script or leaves the groupdef to us.
    ///
    /// **A declared script is still taken at its word here.** The bytecode test that
    /// `WasabiSurfaceSynthesizer` applies to pick a frame for a window of *ours* is deliberately not
    /// repeated: this path only ever adds a group to a frame where nothing else could have, and
    /// treating a script-bearing frame as scriptless would put a second copy of the content group
    /// under one the skin's own script instantiates.
    static func needsHostedContent(definitionChildren: [WalXMLNode],
                                   group: (String) -> [WalXMLNode]?) -> Bool {
        !declaresScript(in: definitionChildren, group: group, depth: 0, visited: [])
    }

    /// Where a frame names its client group: `content="…"` on a XUI instance (TRON Legacy), or
    /// Wasabi's `notify="content,…"` on a plain `<group>` reference to the same groupdef (Sony
    /// Walkman, Lobe) — the two spellings of one parameter, and the script that reads them is the
    /// same script in both cases.
    static func contentGroupIdentifier(of attributes: [String: String]) -> String? {
        if let content = attributes["content"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !content.isEmpty {
            return content
        }
        guard let notify = attributes["notify"] else { return nil }
        let parts = notify.split(separator: ",", maxSplits: 1)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count == 2,
              parts[0].caseInsensitiveCompare("content") == .orderedSame,
              !parts[1].isEmpty else { return nil }
        return parts[1]
    }

    /// Whether a groupdef id names one of Wasabi's standard window frames. The prefix rather than the
    /// three canonical ids, so a skin's `wasabi.standardframe.mine` is covered too.
    static func isStandardFrameIdentifier(_ identifier: String) -> Bool {
        identifier.lowercased().hasPrefix("wasabi.standardframe.")
    }

    /// The border a skin's own frame chrome draws, per side, in skin pixels.
    struct Border: Equatable {
        var left = 0.0
        var top = 0.0
        var right = 0.0
        var bottom = 0.0

        var isEmpty: Bool { self == Border() }
    }

    /// Measure that border from the `resize=` **strips** the frame declares.
    ///
    /// Only the four single-edge values — `left`, `right`, `top`, `bottom` — are read, never a
    /// corner: a corner sprite is as wide as the artwork's rounding rather than as thick as the
    /// border it joins (TRON's `component.top.left` is 24x19 against a 5px side), so counting it
    /// would inset the client by the corner's width on every side. The strips are the parts that
    /// *stretch*, so their thickness is exactly the hole the artwork leaves — and the numbers it
    /// yields land where the authors of comparable skins wrote theirs by hand: TRON measures
    /// `5,15,-10,-34` against corneramp_redux's authored `5,15,-10,-36` for the same Winamp frame.
    ///
    /// A strip usually states no `w`/`h` at all and takes it from its bitmap, so the sizes come from
    /// the resource registry; a bitmap that declares neither contributes nothing rather than zero.
    static func measuredBorder(in children: [WalXMLNode],
                               group: (String) -> [WalXMLNode]?,
                               bitmapSize: (String) -> CGSize?) -> Border {
        var border = Border()
        measure(children, into: &border, offset: .zero, margin: .zero,
                group: group, bitmapSize: bitmapSize, depth: 0, visited: [])
        return border
    }

    /// The client area of such a frame, as the `<group>` the frame's missing script would have made.
    static func measuredContentGroupNode(identifier: String, border: Border,
                                         location: WalSourceLocation) -> WalXMLNode {
        WalXMLNode(name: "group", attributes: [
            "id": identifier,
            "x": String(Int(border.left)), "y": String(Int(border.top)),
            "w": String(Int(-(border.left + border.right))),
            "h": String(Int(-(border.top + border.bottom))),
            "relatw": "1", "relath": "1",
        ], location: location)
    }

    // MARK: - Measurement

    private static let maximumFrameDepth = 16

    private static func declaresScript(in children: [WalXMLNode], group: (String) -> [WalXMLNode]?,
                                       depth: Int, visited: Set<String>) -> Bool {
        guard depth <= maximumFrameDepth else { return true }
        for node in children {
            if node.name.caseInsensitiveCompare("script") == .orderedSame { return true }
            if declaresScript(in: node.children, group: group, depth: depth + 1,
                              visited: visited) { return true }
            guard let nested = referencedGroup(node, group: group, visited: visited) else { continue }
            if declaresScript(in: nested.children, group: group, depth: depth + 1,
                              visited: nested.visited) { return true }
        }
        return false
    }

    /// The groupdef a `<group id="…">` child pulls in, with the id added to the cycle guard. A group
    /// already on the path answers nil, so a skin that nests a frame inside itself terminates.
    private static func referencedGroup(_ node: WalXMLNode, group: (String) -> [WalXMLNode]?,
                                        visited: Set<String>)
        -> (children: [WalXMLNode], visited: Set<String>)? {
        guard node.name.caseInsensitiveCompare("group") == .orderedSame,
              let identifier = node.attribute("id")?.lowercased(), !identifier.isEmpty,
              !visited.contains(identifier), let children = group(identifier) else { return nil }
        return (children, visited.union([identifier]))
    }

    private static func measure(_ children: [WalXMLNode], into border: inout Border,
                                offset: CGPoint, margin: CGPoint,
                                group: (String) -> [WalXMLNode]?,
                                bitmapSize: (String) -> CGSize?,
                                depth: Int, visited: Set<String>) {
        guard depth <= maximumFrameDepth else { return }
        for node in children {
            func number(_ name: String) -> Double? { node.attribute(name).flatMap(Double.init) }
            func isRelative(_ name: String) -> Bool { node.attribute(name) == "1" }
            let x = number("x") ?? 0
            let y = number("y") ?? 0
            // A nested group carries its own origin and, when it is anchored to the far edge with a
            // negative size, the gap it leaves there — TRON's `wasabi.frame.layout` is `h="-23"`
            // over the status band, so a strip measured inside it is 23px short of the window.
            let childOffset = CGPoint(x: offset.x + (isRelative("relatx") ? 0 : max(0, x)),
                                      y: offset.y + (isRelative("relaty") ? 0 : max(0, y)))
            let childMargin = CGPoint(
                x: margin.x + (isRelative("relatw") ? max(0, -(number("w") ?? 0)) : 0),
                y: margin.y + (isRelative("relath") ? max(0, -(number("h") ?? 0)) : 0))

            if let edges = WasabiResizeEdges(attribute: node.attribute("resize")) {
                let image = node.attribute("image").flatMap(bitmapSize)
                let width = number("w") ?? image.map { Double($0.width) }
                let height = number("h") ?? image.map { Double($0.height) }
                switch edges {
                case .left where !isRelative("relatx"):
                    if let width { border.left = max(border.left, offset.x + x + width) }
                case .right where isRelative("relatx"):
                    border.right = max(border.right, margin.x - x)
                case .top where !isRelative("relaty"):
                    if let height { border.top = max(border.top, offset.y + y + height) }
                case .bottom where isRelative("relaty"):
                    border.bottom = max(border.bottom, margin.y - y)
                default: break
                }
            }

            measure(node.children, into: &border, offset: childOffset, margin: childMargin,
                    group: group, bitmapSize: bitmapSize, depth: depth + 1, visited: visited)
            if let nested = referencedGroup(node, group: group, visited: visited) {
                measure(nested.children, into: &border, offset: childOffset, margin: childMargin,
                        group: group, bitmapSize: bitmapSize, depth: depth + 1,
                        visited: nested.visited)
            }
        }
    }
}
