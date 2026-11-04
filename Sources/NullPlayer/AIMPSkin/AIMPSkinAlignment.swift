import CoreGraphics
import Foundation

/// How AIMP docks an item's children by their `Alignment` (`reference/layout.md` § Items), as pure
/// functions of the item tree: which children take part, the room they add up to, the order each
/// edge takes them in, and how clients share what is left. `AIMPSkinLayout` lays a frame out and
/// measures an item's least size by them, the renderer a form's natural size, and AIMP 3.0's
/// translator its items; each says only how it sizes a child and which of a tabbed group's pages count.
/// (Dock *sites*, items that hold a whole form, are `AIMPSkinDockSites`.)
enum AIMPSkinAlignment {
    /// Whether an item shows before anything has run: saved shown, or a tabbed group's page, which
    /// shows while it is the active one whatever it was saved as.
    static func startsShown(_ element: AIMPSkinElement, in index: AIMPSkinIndex) -> Bool {
        element.savedShown || element.name.map { index.tabOf[$0] != nil } == true
    }

    /// Which of a tabbed group's pages take part.
    enum Pages {
        /// Every shown one, as alternatives: the group is as big as its biggest page.
        case every
        /// Every shown one, else its first: a group none of whose pages counts still measures one.
        case everyElseFirst
        /// The one at the place among its tabs (`AIMPSkinIndex.tabOf`) a group, by name, shows; a
        /// group with no name shows every shown page.
        case active((String) -> Int)
    }

    /// The children of `node`, from `items`, that take part: those `isShown` passes, of a tabbed
    /// group only the `pages` asked for.
    static func participants(_ items: [AIMPSkinItem], of item: AIMPSkinItem, pages: Pages, index: AIMPSkinIndex,
                             isShown: (AIMPSkinItem) -> Bool) -> [AIMPSkinItem] {
        let shown = items.filter(isShown)
        guard item.isTabbedGroup else { return shown }
        switch pages {
        case .every: return shown
        case .everyElseFirst: return shown.isEmpty ? Array(items.prefix(1)) : shown
        case .active(let page):
            guard let group = item.name else { return shown }
            let active = page(group)
            return shown.filter { $0.name.flatMap { index.tabOf[$0]?.index } == active }
        }
    }

    /// How several clients fill their item: side by side along its row (down it), or each the whole
    /// of it, as a tabbed group's pages (and AIMP 3.0's clients) do.
    enum Clients {
        case share(row: Bool)
        case overlap
    }

    /// The room `children` take docked in one item: top and bottom bars, and items with no
    /// `Alignment`, stack; left and right panels sit in a row beside the clients.
    static func aggregate(_ children: [(dock: AIMPSkinDock?, size: CGSize)], clients: Clients) -> CGSize {
        var stacked = CGSize.zero, sides = CGSize.zero, client = CGSize.zero
        let sharing = children.filter { $0.dock == .client }.count > 1
        for (dock, s) in children {
            switch dock {
            case .left?, .right?:
                sides = CGSize(width: sides.width + s.width, height: max(sides.height, s.height))
            case .client?:
                switch clients {
                case .share(row: true) where sharing: client = CGSize(width: client.width + s.width, height: max(client.height, s.height))
                case .share(row: false) where sharing: client = CGSize(width: max(client.width, s.width), height: client.height + s.height)
                default: client = CGSize(width: max(client.width, s.width), height: max(client.height, s.height))
                }
            default:
                stacked = CGSize(width: max(stacked.width, s.width), height: stacked.height + s.height)
            }
        }
        return CGSize(width: max(stacked.width, sides.width + client.width), height: stacked.height + max(sides.height, client.height))
    }

    /// The room `children` take docked in `item`, each `sizeOf` big: a tabbed group's pages are
    /// alternatives, any other item's clients share it along its `LayoutDirection`.
    static func aggregate(_ item: AIMPSkinItem, children: [AIMPSkinItem], sizeOf: (AIMPSkinItem) -> CGSize) -> CGSize {
        let tabbed = item.isTabbedGroup
        return aggregate(children.map { (tabbed ? .client : $0.layout.dock, sizeOf($0)) },
                         clients: tabbed ? .overlap : .share(row: item.layout.isRow))
    }

    /// What `item` holds: `children` docked in it, each in its slot (`sizeOf` it, its
    /// `AlignmentMargins` around), as `AIMPSkinLayout.layout` places them. The one measure of an
    /// item's content, whichever size is asked (`AIMPSkinLayout.Measure`).
    static func content(_ item: AIMPSkinItem, children: [AIMPSkinItem], sizeOf: (AIMPSkinItem) -> CGSize) -> CGSize {
        aggregate(item, children: children) { $0.layout.slot(sizeOf($0)) }
    }

    /// The order AIMP docks `items` in: each `Alignment`'s items by `AlignmentLevel`, level 0 first,
    /// so against its edge (Denon Classic Style's amplifier under its equalizer under its deck; a
    /// playlist's tool bar under its captions); which alignment goes first stays in document order.
    static func levelOrder(_ items: [AIMPSkinItem.Layout]) -> [Int] {
        let docks = items.map(\.dock)
        let levels = items.map(\.level)
        var queues = Dictionary(grouping: items.indices, by: { docks[$0] })
            .mapValues { $0.sorted { (levels[$0], $0) < (levels[$1], $1) }[...] }
        return items.indices.map { queues[docks[$0]]!.popFirst()! }
    }

    /// Several `laClient` items share `rect`, side by side (one above another when `vertical`), in
    /// `AlignmentLevel` order. Each takes its `Size`, else the larger of its `SizeMinimal` and
    /// `minimums` (what it holds needs) along the axis, with its `AlignmentMargins`; those whose
    /// `SizeMaximal` lets them grow split what is left evenly, a capped one's surplus going to the
    /// rest (Office 2016's ribbon groups, Play Music AIO's header areas). The slots, in `items` order.
    static func share(_ rect: CGRect, among items: [AIMPSkinItem.Layout], vertical: Bool, minimums: [CGFloat]? = nil) -> [CGRect] {
        func extent(_ size: CGSize?) -> CGFloat? { AIMPSkinItem.Layout.extent(size, vertical: vertical) }
        func margins(_ item: AIMPSkinItem.Layout) -> CGFloat {
            item.margins.map { CGFloat(vertical ? $0.top + $0.bottom : $0.left + $0.right) } ?? 0
        }
        var lengths = items.indices.map { i in
            max(extent(items[i].size) ?? extent(items[i].sizeMinimal) ?? 0, minimums?[i] ?? 0) + margins(items[i])
        }
        let caps = items.map { item in extent(item.size).map { $0 + margins(item) } ?? extent(item.sizeMaximal).map { $0 + margins(item) } }
        func grows(_ i: Int) -> Bool { caps[i].map { cap in lengths[i] < cap } ?? true }
        var growing = items.indices.filter(grows)
        var left = (vertical ? rect.height : rect.width) - lengths.reduce(0, +)
        while left > 0.5, !growing.isEmpty {
            let each = left / CGFloat(growing.count)
            left = 0
            for i in growing {
                let grown = min(lengths[i] + each, caps[i] ?? .infinity)
                left += lengths[i] + each - grown
                lengths[i] = grown
            }
            growing = growing.filter(grows)
        }
        let levels = items.map(\.level)
        let order = items.indices.sorted { (levels[$0], $0) < (levels[$1], $1) }
        var slots = [CGRect](repeating: .zero, count: items.count)
        var start = vertical ? rect.minY : rect.minX
        for i in order {
            slots[i] = vertical ? CGRect(x: rect.minX, y: start, width: rect.width, height: lengths[i])
                : CGRect(x: start, y: rect.minY, width: lengths[i], height: rect.height)
            start += lengths[i]
        }
        return slots
    }
}
