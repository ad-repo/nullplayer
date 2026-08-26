import Foundation

/// `<Wasabi:Frame>` — Wasabi's splitter. It is the object cPro-Bento's whole body hangs off:
///
/// ```xml
/// <Wasabi:Frame id="centro.mainframe" left="centro.components" right="centro.playlist1"
///               orientation="vertical" from="right" width="200" minwidth="158" maxwidth="-224"/>
/// ```
///
/// A frame is not a container the skin fills — it **instantiates the two groups it names** and lays
/// them out either side of a divider sitting `position` pixels from the `from` edge. Treating it as
/// an ordinary identifier-only group (as the Wasabi standard-library shells are) leaves the library
/// tree, the playlist and the tabs out of the graph entirely.
///
/// Layout is expressed by writing the panes' own geometry attributes, so the existing
/// `WasabiGeometrySpec` pipeline resolves them like any other object and a later parent resize needs
/// no frame-specific code — only a change of `position` re-runs this.
enum WasabiFrame {
    /// Half the divider's thickness, in skin pixels. The panes stop this far short of the boundary
    /// on each side, leaving the grab strip between them.
    static let dividerHalfThickness = 4.0

    static func isFrame(typeName: String) -> Bool {
        let lower = typeName.lowercased()
        return lower == "wasabi:frame" || lower == "frame"
    }

    static func isFrame(_ object: WasabiObject) -> Bool { isFrame(typeName: object.typeName) }

    /// The two group identifiers this frame instantiates, in `from`-edge-first document order
    /// (`left`/`right` for a vertical divider, `top`/`bottom` for a horizontal one). Empty when the
    /// frame names neither pair, which real skins do use as a plain group.
    static func paneIdentifiers(of object: WasabiObject) -> [String] {
        ["left", "top", "right", "bottom"].compactMap { direction in
            guard let value = object.attributes[direction]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { return nil }
            return value
        }
    }

    /// `true` when the divider is vertical (a `left`/`right` split), `false` for `top`/`bottom`.
    static func isVerticalDivider(_ object: WasabiObject) -> Bool {
        object.attributes["left"] != nil || object.attributes["right"] != nil
    }

    /// Divider offset from the `from` edge, in skin pixels. Seeded from `width`/`height` (Wasabi uses
    /// whichever names the split axis) and thereafter owned by `position`, which `setPosition` writes.
    static func position(of object: WasabiObject) -> Double {
        if let stored = object.attributes["position"], let value = Double(stored) { return max(0, value) }
        let seed = isVerticalDivider(object) ? object.attributes["width"] : object.attributes["height"]
        return max(0, seed.flatMap(Double.init) ?? 0)
    }

    /// Move the divider. Returns whether anything changed, so callers can skip the redraw/notify.
    @discardableResult
    static func setPosition(_ position: Double, on object: WasabiObject) -> Bool {
        let clamped = String(Int(max(0, position.isFinite ? position : 0)))
        guard object.attributes["position"] != clamped else { return false }
        _ = object.setAttribute("position", value: clamped)
        applyLayout(to: object)
        return true
    }

    /// Write the two panes' geometry from the current divider position. A pane that would be
    /// negative-sized (the skin closing the split with `setPosition(0)`) collapses to zero rather
    /// than flipping — a signed rect would otherwise render mirrored across the boundary.
    static func applyLayout(to object: WasabiObject) {
        let identifiers = paneIdentifiers(of: object)
        guard identifiers.count == 2 else { return }
        let panes = identifiers.map { identifier in
            object.children.first { $0.xmlID?.caseInsensitiveCompare(identifier) == .orderedSame }
        }
        guard let first = panes[0], let second = panes[1] else { return }

        let vertical = isVerticalDivider(object)
        let offset = position(of: object)
        let inner = max(0, offset - dividerHalfThickness)   // pane on the `from` side
        let outer = -(offset + dividerHalfThickness)        // pane on the far side, parent-relative

        // Cross-axis: both panes always span the parent completely.
        for pane in [first, second] {
            if vertical {
                _ = pane.setAttribute("y", value: "0")
                _ = pane.setAttribute("h", value: "0")
                _ = pane.setAttribute("relath", value: "1")
            } else {
                _ = pane.setAttribute("x", value: "0")
                _ = pane.setAttribute("w", value: "0")
                _ = pane.setAttribute("relatw", value: "1")
            }
            // A groupdef may carry `fitparent="1"`; honouring it here would make both panes fill the
            // frame and stack on top of each other.
            _ = pane.setAttribute("fitparent", value: nil)
        }

        let (originKey, extentKey, relativeOriginKey, relativeExtentKey) = vertical
            ? ("x", "w", "relatx", "relatw")
            : ("y", "h", "relaty", "relath")

        func place(_ pane: WasabiObject, offset origin: Double, relativeOrigin: Bool,
                   extent: Double, relativeExtent: Bool) {
            _ = pane.setAttribute(originKey, value: String(Int(origin)))
            _ = pane.setAttribute(relativeOriginKey, value: relativeOrigin ? "1" : "0")
            _ = pane.setAttribute(extentKey, value: String(Int(extent)))
            _ = pane.setAttribute(relativeExtentKey, value: relativeExtent ? "1" : "0")
        }

        switch fromEdge(of: object) {
        case .start:
            // The first pane is measured from the near edge; the second takes what is left.
            place(first, offset: 0, relativeOrigin: false, extent: inner, relativeExtent: false)
            place(second, offset: offset + dividerHalfThickness, relativeOrigin: false,
                  extent: outer, relativeExtent: true)
        case .end:
            place(first, offset: 0, relativeOrigin: false, extent: outer, relativeExtent: true)
            place(second, offset: -inner, relativeOrigin: true, extent: inner, relativeExtent: false)
        }
    }

    /// The grab strip between the two panes, in the same space as `frame` (the splitter's own
    /// resolved rect). `nil` when the object is not actually a splitter, or when the divider has been
    /// pushed off the end of the axis — ClassicPro closes its side view with `setPosition(0)`, and a
    /// closed split offers nothing to grab.
    static func dividerRect(of object: WasabiObject, in frame: CGRect) -> CGRect? {
        guard paneIdentifiers(of: object).count == 2 else { return nil }
        let vertical = isVerticalDivider(object)
        let extent = vertical ? frame.width : frame.height
        let thickness = dividerHalfThickness * 2
        guard extent > thickness else { return nil }
        let offset = position(of: object)
        let distance = fromEdge(of: object) == .start ? offset : extent - offset
        let start = distance - dividerHalfThickness
        guard start >= 0, start + thickness <= extent else { return nil }
        return vertical
            ? CGRect(x: frame.minX + start, y: frame.minY, width: thickness, height: frame.height)
            : CGRect(x: frame.minX, y: frame.minY + start, width: frame.width, height: thickness)
    }

    /// The divider offset a drag to `point` asks for, clamped to the frame's own limits.
    static func position(draggedTo point: CGPoint, in frame: CGRect, object: WasabiObject) -> Double {
        let vertical = isVerticalDivider(object)
        let extent = Double(vertical ? frame.width : frame.height)
        let along = Double(vertical ? point.x - frame.minX : point.y - frame.minY)
        let raw = fromEdge(of: object) == .start ? along : extent - along
        return clampedPosition(raw, extent: extent, object: object)
    }

    /// `minwidth`/`maxwidth` (which skins write for *both* orientations — ClassicPro's horizontal
    /// `centro.plframe` uses them) bound the offset, and 0…extent bounds those in turn.
    ///
    /// The **axis's own name wins** when a skin declares both. Big Bento Modern's `playlist.dualwnd`
    /// splits the side playlist from its album art horizontally and carries `minheight="100"` next to
    /// a leftover `minwidth="313"`; taking the first name found made 313 the floor for a *height*, so
    /// the cover pane snapped to a third of the window on the first drag and could not go back.
    static func clampedPosition(_ raw: Double, extent: Double, object: WasabiObject) -> Double {
        let vertical = isVerticalDivider(object)
        let minimums = vertical ? ["minwidth", "minheight"] : ["minheight", "minwidth"]
        let maximums = vertical ? ["maxwidth", "maxheight"] : ["maxheight", "maxwidth"]
        let low = max(0, min(limit(object, keys: minimums, extent: extent) ?? 0, extent))
        let high = max(low, min(limit(object, keys: maximums, extent: extent) ?? extent, extent))
        return max(low, min(high, raw.isFinite ? raw : low))
    }

    /// A negative limit is measured from the far edge: ClassicPro's `maxwidth="-224"` means "always
    /// leave 224 pixels for the other pane", so the bound grows with the window rather than pinning
    /// the divider to an absolute column.
    private static func limit(_ object: WasabiObject, keys: [String], extent: Double) -> Double? {
        for key in keys {
            guard let raw = object.attributes[key], let value = Double(raw) else { continue }
            return value < 0 ? max(0, extent + value) : value
        }
        return nil
    }

    private enum Edge { case start, end }

    /// `from` names the edge the divider is measured from: `left`/`top` (near) or `right`/`bottom`
    /// (far). Skins write it in full and abbreviated (`l`, `r`, `t`, `b`), so match the first letter.
    private static func fromEdge(of object: WasabiObject) -> Edge {
        switch object.attributes["from"]?.lowercased().first {
        case "r", "b": return .end
        default: return .start
        }
    }
}
