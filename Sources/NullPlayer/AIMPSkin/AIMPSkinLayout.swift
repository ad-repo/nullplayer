import CoreGraphics
import Foundation

/// A frame laid out, before anything is drawn: every shown item placed by AIMP's docking rules
/// (`reference/layout.md` § Items, `AIMPSkinAlignment`), and in each the controls it shows, placed, with
/// what a key shows and what the pointer can do to it. The painter draws the tree
/// (`AIMPSkinPainter.paint`); the frame's click targets, tooltips, named rects and handlers are read
/// from it (`Tree.offers`), and a window's natural size from it alone.
final class AIMPSkinLayout {
    /// An item placed, the controls it shows in drawing order, and the items it holds.
    struct Item {
        let item: AIMPSkinItem
        let rect: CGRect
        var controls: [Control]
        var items: [Item]
    }

    /// A control placed: where `PlaceInfo` puts it, where it draws (a display grown to its text),
    /// how it looks and what it offers the pointer, and the controls placed in it.
    struct Control {
        /// As a script restyled it.
        let control: AIMPSkinControl
        let image: AIMPSkinImage?
        let placed: CGRect
        let rect: CGRect
        /// The item's rect its window cuts it at (W10's cover strip).
        let cut: CGRect?
        var look: Look
        /// Its click targets, topmost last, and its tooltip.
        var targets: [AIMPSkinTarget]
        let hint: String?
        /// A gauge the window eases: its value and how fast it may rise and fall.
        let gauge: (value: Double, up: Double, down: Double)?
        var controls: [Control]
    }

    /// How a control looks this frame, all the painter needs to draw it: its class's settings and
    /// what the frame's state makes of them. The painter switches on it once.
    enum Look {
        /// A key, or a control drawn as one: this frame of its picture, a panel's fill, its caption
        /// (`glyphFirst`: its centred glyph at its left, before the spaces the caption opens with).
        case key(AIMPControlClass.Key, frame: Int, caption: String, glyphFirst: Bool)
        /// Its picture, as it is (a library list with no library to list).
        case picture
        /// One frame of its filmstrip: a gauge's needle, an animator's step, a selector's position,
        /// a state display's state, a digit key held down.
        case frame(Int)
        case digits(value: Double, AIMPControlClass.Digits)
        case time(seconds: Int, AIMPControlClass.Digits)
        /// A slider's or seek bar's value, 0–1, and its thumb.
        case slider(AIMPControlClass.Slider, fraction: Double, thumb: AIMPSkinImage?)
        case rating(Int)
        /// NullPlayer's playlist, the rows the quick search leaves (`shown`), and those in view.
        case playlist(AIMPSkinControl.Playlist, rows: Rows, shown: [Int])
        case libraryTree(AIMPSkinControl.Library, rows: Rows, tree: [AIMPSkinLibrary.Row])
        case libraryTable(AIMPSkinControl.Library, library: AIMPSkinLibrary, rows: Rows, table: [Int], header: CGFloat)
        /// The playlist's scroll bar: its thumb, `length` long, `share` of the way down (nil: all
        /// the rows are in view).
        case scrollBar(thumb: AIMPSkinImage?, length: CGFloat, share: CGFloat?)
        /// A quick search box and the search shown in it, if any.
        case search(String?, font: AIMPSkinFont)
        case tabControl(AIMPSkinControl.Tabs, caption: String)
        case playlistTabs(AIMPSkinControl.Tabs, playing: Bool)
        case playlistBox(font: AIMPSkinFont?, centred: Bool)
        case equalizer(preamp: UInt32?, curve: UInt32?)
        case coverArt(AIMPControlClass.Cover)
        case glass(blur: Double?, tint: AIMPSkinColor?)
        case waveForm(AIMPControlClass.Trace)
        case visualization(AIMPControlClass.Spectrum, cover: Int?)
        case spectrum(AIMPControlClass.Spectrum)
    }

    /// The rows of a list in view: from row `first`, `visible` of them (and the one partly shown
    /// below), `height` tall.
    struct Rows {
        let first: Int
        let visible: Int
        let height: CGFloat

        /// `count` rows `height` tall in `room`, from row `top`, or as near it as lets the last row
        /// show at the bottom.
        init(top: Int, count: Int, height: CGFloat, room: CGFloat) {
            self.height = height
            visible = max(1, Int(room / height))
            first = min(max(0, top), max(0, count - visible))
        }

        /// The rows of `all` in view.
        func inView<Row>(_ all: [Row]) -> ArraySlice<Row> { all.dropFirst(first).prefix(visible + 1) }

        /// The `offset`th row in view, down from the top of `rect`.
        func line(_ offset: Int, in rect: CGRect) -> CGRect {
            CGRect(x: rect.minX, y: rect.minY + CGFloat(offset) * height, width: rect.width, height: height)
        }
    }

    let flow: AIMPSkinDataflow
    let interaction: AIMPSkinInteraction
    var skin: AIMPSkin { flow.skin }
    /// AIMP 3.0's and AIMP 2's controls belong to the window, not to their item (`controls(of:)`).
    let controlsOutliveItems: Bool
    /// Items this layout hid by their `AutoHide` (`autoHides`).
    private(set) var autoHidden: Set<String> = []
    /// What this frame measured, by item and what was asked: each subtree is measured once however
    /// often docking asks (an item's slot, its `AutoHide` test and a pulled item's height all ask for
    /// its size; a row's clients for what they hold and whether they are hollow). Frame sizes are
    /// kept by depth too, as the measure stops at a depth (`size`).
    private var sizes: [Measured: CGSize] = [:]
    private var hollow: [ObjectIdentifier: Bool] = [:]
    private struct Measured: Hashable {
        let item: ObjectIdentifier
        let measure: Measure
    }

    /// Which size of an item is asked for (`measured`): as this frame shows it, `depth` levels down
    /// the measure (`size`); or the least it takes as the skin was saved, `page` as a tabbed group's
    /// page (`leastSize`).
    enum Measure: Hashable {
        case frame(depth: Int)
        case least(page: Bool)
    }

    init(flow: AIMPSkinDataflow, interaction: AIMPSkinInteraction = .init()) {
        self.flow = flow
        self.interaction = interaction
        controlsOutliveItems = flow.skin.archive.isLegacy
    }

    /// A form, or its item `rootName`, laid out at `size`; nil for a form or item the skin lacks.
    func tree(size: CGSize, item rootName: String? = nil, form formName: String? = nil) -> Tree? {
        guard let form = skin.index.form(formName) else { return nil }
        let root: AIMPSkinItem
        if let rootName {
            guard let item = form.item(named: rootName) else { return nil }
            root = item
        } else {
            root = form
        }
        return Tree(root: withScrollBars(tree(root, in: CGRect(origin: .zero, size: size))), rootIsItem: rootName != nil,
                    autoHidden: autoHidden)
    }

    /// `item` placed at `rect`, its controls, then the items it holds, placed in turn: the order the
    /// painter draws them in.
    func tree(_ item: AIMPSkinItem, in rect: CGRect) -> Item {
        let children = layout(item, in: rect)
        let controls = self.controls(of: item, in: rect)
        return Item(item: item, rect: rect, controls: controls, items: children.map { tree($0.0, in: $0.1) })
    }

    // MARK: Items

    /// The items of `item` that show: a tabbed group's active page, else every shown child. A dock
    /// site shows while it holds its form, docked and shown (Telos's equalizer starts hidden, over
    /// its transport panel); one holding none takes no room (A4 3.2's library site, its library a
    /// window, leaves the split view to the playlist).
    func shownItems(of item: AIMPSkinItem) -> [AIMPSkinItem] {
        AIMPSkinAlignment.participants(heldItems(item), of: item, pages: .active { self.flow.activePage($0) }, index: skin.index) { item in
            guard item.isDockSite else { return flow.isShown(item) }
            guard let form = item.name.flatMap({ skin.index.sites[$0]?.form }) else { return false }
            return flow.isDocked(form) && flow.isVisible(form) && flow.isShown(item)
        }
    }

    /// What `item` holds now: its own items, less any a script moved out, plus any it moved in
    /// (`Parent :=`); a dock site also holds its form while it is docked.
    func heldItems(_ item: AIMPSkinItem) -> [AIMPSkinItem] {
        var held = moved(item.items, holder: item.name) { if case .item(let item) = $0 { item } else { nil } }
        if let name = item.name, let site = skin.index.sites[name], flow.isDocked(site.form), let holder = skin.index.holders[name] {
            held.append(holder)
        }
        return held
    }

    /// The controls an item or control holds now (`own`), as `heldItems`.
    func heldControls(_ element: AIMPSkinElement, own: [AIMPSkinControl]) -> [AIMPSkinControl] {
        moved(own, holder: element.name) { if case .control(let control) = $0 { control } else { nil } }
    }

    /// `own` less any a script moved out of `holder`, plus any it moved in, by name.
    private func moved<Element: AIMPSkinElement>(_ own: [Element], holder name: String?,
                                                 as kind: (AIMPSkinIndex.Element) -> Element?) -> [Element] {
        let moved = flow.state.script.parents
        guard let name, !moved.isEmpty else { return own }
        let kept = own.filter { child in child.name.flatMap { moved[$0] }.map { $0 == name } ?? true }
        return kept + moved.filter { $0.value == name && skin.index.parentOf[$0.key] != name }.keys.sorted()
            .compactMap { skin.index.byName[$0].flatMap(kind) }
    }

    /// Where `item`'s shown items go in `rect`: docked edges first, by level; items with no
    /// `Alignment` down from the top; clients sharing what is left; each inset by its margins.
    func layout(_ item: AIMPSkinItem, in rect: CGRect) -> [(AIMPSkinItem, CGRect)] {
        var items = shownItems(of: item)
        // A tab page with no size of its own fills its group, whatever its alignment: pages are
        // alternatives, not a stack (Kantaris-Teyp's deck pages say none, and stood 49 px tall in a
        // 250-px group). One with a picture keeps its size (Nakamichi BX's slider scales).
        if item.isTabbedGroup, items.count == 1, let page = items.first, !hasOwnSize(page) {
            return [(page, page.layout.inset(rect))]
        }
        // Clients share along the row unless the item says `ldVertical`: AIMP's default, so a
        // caption's icon, title and keys need no direction.
        let horizontal = item.layout.isRow
        items = items.filter { item in
            guard autoHides(item, in: rect, row: horizontal) else { return true }
            if let name = item.name { autoHidden.insert(name) }
            return false
        }
        var free = rect
        var placed: [Int: CGRect] = [:]
        // An item's `AlignmentMargins` sit outside it: its slot is its size plus them (Sony TC-MR2's
        // cassette docks left with 85 px before it and 509 after), and it is inset from the slot below.
        func slot(_ item: AIMPSkinItem) -> (CGFloat, CGFloat) {
            let slot = item.layout.slot(size(item))
            return (slot.width, slot.height)
        }
        let order = AIMPSkinAlignment.levelOrder(items.map(\.layout))
        for i in order {
            let (w, h) = slot(items[i])
            switch items[i].layout.dock {
            case .top?:
                placed[i] = CGRect(x: free.minX, y: free.minY, width: free.width, height: h)
                free = CGRect(x: free.minX, y: free.minY + h, width: free.width, height: free.height - h)
            case .bottom?:
                placed[i] = CGRect(x: free.minX, y: free.maxY - h, width: free.width, height: h)
                free.size.height -= h
            case .left?:
                placed[i] = CGRect(x: free.minX, y: free.minY, width: w, height: free.height)
                free = CGRect(x: free.minX + w, y: free.minY, width: free.width - w, height: free.height)
            case .right?:
                placed[i] = CGRect(x: free.maxX - w, y: free.minY, width: w, height: free.height)
                free.size.width -= w
            default:
                break
            }
        }
        // Where negative margins pull an item back over the run (TEAC CD-RW890's NEXT key: 20 px tall
        // with -20 above, beside PREV, 20 tall with -84 above), its slot is 0 or less: it sits at its
        // margins and the run moves on by the slot.
        // Items with no `Alignment` run down from the top in `AlignmentLevel` order whatever the
        // parent's `LayoutDirection` (Soot's 50-px caption bar over its three transport keys, laid
        // side by side); one with no height of its own takes what remains.
        var pulled: [Int: CGRect] = [:]
        for i in order where placed[i] == nil && items[i].layout.dock == nil {
            let item = items[i]
            let (_, h) = slot(item)
            let ih = size(item).height
            if let m = item.layout.margins, h <= 0 && ih > 0 {
                pulled[i] = CGRect(x: free.minX + CGFloat(m.left), y: free.minY + CGFloat(m.top), width: free.width - CGFloat(m.left + m.right), height: ih)
                free = CGRect(x: free.minX, y: free.minY + h, width: free.width, height: free.height - h)
                continue
            }
            if h > 0 {
                placed[i] = CGRect(x: free.minX, y: free.minY, width: free.width, height: h)
                free = CGRect(x: free.minX, y: free.minY + h, width: free.width, height: free.height - h)
            }
        }
        var clients = items.indices.filter { placed[$0] == nil && pulled[$0] == nil && items[$0].layout.dock == .client }
        // A client with nothing to show takes no share of the row beside one that has (RealPlayer
        // 11's empty `EqualizerFrame` held 300 px of its info strip open on the desktop).
        if clients.count > 1, clients.contains(where: { !isHollow(items[$0]) }) {
            for i in clients where isHollow(items[i]) {
                placed[i] = horizontal ? CGRect(x: free.minX, y: free.minY, width: 0, height: free.height)
                    : CGRect(x: free.minX, y: free.minY, width: free.width, height: 0)
            }
            clients.removeAll { placed[$0] != nil }
        }
        if clients.count > 1 {
            // Each at least what it holds needs (LX-tix's cover beside its 200-px info panel).
            let least = clients.map { leastSize(items[$0]) }
            let shares = AIMPSkinAlignment.share(free, among: clients.map { items[$0].layout }, vertical: !horizontal,
                                            minimums: least.map { horizontal ? $0.width : $0.height })
            for (i, rect) in zip(clients, shares) { placed[i] = rect }
        }
        return items.enumerated().map { i, item in
            (item, pulled[i] ?? item.layout.inset(placed[i] ?? free))
        }
    }

    /// An item's declared size; a side it leaves at 0 takes its texture's (AIMP sizes such an item to
    /// its picture: Technicss docks a 0×0 `Deck` whose texture is the whole player), else its shown
    /// children's docked (Nakamichi BX docks a pictureless `Deck` around its 306-px face). Measured
    /// once a frame (`sizes`).
    func size(_ item: AIMPSkinItem, depth: Int = 0) -> CGSize { measured(item, .frame(depth: depth)) }

    /// What an item's `SizeMinimal`s add up to as AIMP docks them (`AIMPSkinAlignment.content`), each
    /// with its `AlignmentMargins`; a tabbed group's saved-shown pages are alternatives. An item that
    /// declares none and holds none counts its picture when it is a tabbed group's page and the
    /// picture a real one (`AIMPSkinPolicy.pictureSide`: RealPlayer 11's 210-px cover page): a page is
    /// sized by what it shows. It reads the skin as written, not the frame's state: a row's clients
    /// take at least this (LX-tix's cover beside its info panel), and a window opens no smaller.
    func leastSize(_ item: AIMPSkinItem, page: Bool = false) -> CGSize { measured(item, .least(page: page)) }

    /// `item`'s size as `measure` asks, measured once a frame.
    private func measured(_ item: AIMPSkinItem, _ measure: Measure) -> CGSize {
        let key = Measured(item: ObjectIdentifier(item), measure: measure)
        if let size = sizes[key] { return size }
        let size = self.measure(item, measure)
        sizes[key] = size
        return size
    }

    /// The one sizing rule both measures follow, each with its own children and pictures: what the
    /// item holds docked (`AIMPSkinAlignment.content`: every child in its slot, as `layout` places it),
    /// no smaller than its `SizeMinimal`.
    private func measure(_ item: AIMPSkinItem, _ measure: Measure) -> CGSize {
        let layout = item.layout
        switch measure {
        case .least(let page):
            let holds = layout.sizesToContent(least: true)
            let children = AIMPSkinAlignment.participants(item.items, of: item, pages: .everyElseFirst, index: skin.index) { holds && $0.savedShown }
            let tabbed = item.isTabbedGroup
            let size = layout.floored(AIMPSkinAlignment.content(item, children: children) { measured($0, .least(page: tabbed)) })
            if page, layout.sizeMinimal == nil, size == .zero, item.isItem, let picture = skin.image(item.texture), AIMPSkinPolicy.isPicture(picture) {
                return picture.frameSize
            }
            return size
        case .frame(let depth):
            var size = layout.floored(layout.size ?? .zero)
            if size.width == 0 || size.height == 0, let picture = flow.image(item.texture), picture.hasPixels {
                if size.width == 0 { size.width = picture.frameSize.width }
                if size.height == 0 { size.height = picture.frameSize.height }
            }
            // `SizeMinimal` is only a minimum: the item grows to hold its children, their margins included
            // (RealPlayer 11's 60-px `Conta` holds a 210-px cover 17 px down, above the equalizer).
            let grows = layout.size == nil && layout.sizeMinimal != nil
            // `AutoSize` `False` keeps a size the item has; one with none at all still holds its children
            // (Unsquareable's cover column, 0 px wide, let its 192-px cover lie under the title). Eight
            // levels down the measure stops: a script may have moved an item into its own child.
            guard size.width == 0 || size.height == 0 || grows, depth < 8, layout.sizesToContent() || size == .zero else { return size }
            // Children as `layout` places them (FLAT DARK's 48-px top: a 24-px caption over a 24-px
            // menu), every shown page of a tabbed group as an alternative.
            let shown = AIMPSkinAlignment.participants(heldItems(item), of: item, pages: .every, index: skin.index, isShown: flow.isShown)
            let content = AIMPSkinAlignment.content(item, children: shown) { measured($0, .frame(depth: depth + 1)) }
            if size.width == 0 { size.width = content.width } else if grows { size.width = max(size.width, content.width) }
            if size.height == 0 { size.height = content.height } else if grows { size.height = max(size.height, content.height) }
            return size
        }
    }

    /// Whether an item shows nothing: no size, picture or colour of its own, no controls, and only
    /// items like it inside.
    func isHollow(_ item: AIMPSkinItem) -> Bool {
        if let known = hollow[ObjectIdentifier(item)] { return known }
        let isHollow = !hasOwnSize(item) && !item.declaresColor && heldControls(item, own: item.controls).isEmpty
            && heldItems(item).allSatisfy(self.isHollow)
        hollow[ObjectIdentifier(item)] = isHollow
        return isHollow
    }

    /// Whether an item declares a size or shows a picture with one.
    func hasOwnSize(_ item: AIMPSkinItem) -> Bool {
        let declared = [item.layout.size, item.layout.sizeMinimal].compactMap { $0 }
        return declared.contains { $0.width > 0 || $0.height > 0 } || flow.image(item.texture)?.hasPixels == true
    }

    /// Whether `AutoHide` hides `item` in a parent `rect`: the parent is smaller than its
    /// `AutoHideParentSizeThreshold` along the item's axis (across for a side panel, or for a client
    /// of a `row`; down for a bar), or, with none given, too small for the item itself.
    func autoHides(_ item: AIMPSkinItem, in rect: CGRect, row: Bool) -> Bool {
        guard item.layout.autoHide else { return false }
        let dock = item.layout.dock
        let across = dock?.isSide == true || (dock == .client && row)
        let room = across ? rect.width : rect.height
        if let threshold = item.layout.autoHideThreshold { return Double(room) < threshold }
        let size = size(item)
        return (across ? size.width : size.height) > room
    }
}

extension AIMPSkinLayout {
    /// A form (or one item of it) laid out at `bounds`: the tree, whether its root is an item drawn
    /// with its own picture rather than the form itself, and what `AutoHide` hid.
    struct Tree {
        let root: Item
        let rootIsItem: Bool
        let autoHidden: Set<String>

        /// What a frame drawn from the tree offers the pointer and the window, read in the order the
        /// painter draws the controls: an item's rect, then its controls (each's targets, rect, hint
        /// and handlers, then those nested in it), then its items.
        var offers: Offers {
            var offers = Offers()
            offers.read(root, isItem: rootIsItem)
            return offers
        }
    }

    struct Offers {
        /// Topmost last, as drawn.
        var targets: [AIMPSkinTarget] = []
        var hints: [(rect: CGRect, text: String)] = []
        var namedRects: [String: CGRect] = [:]
        var mouseHandlers: [AIMPSkinFrame.MouseHandlers] = []
        var gauges: [AIMPSkinControl.ID: (value: Double, up: Double, down: Double)] = [:]
        var searchFont: AIMPSkinFont?

        fileprivate mutating func read(_ placed: Item, isItem: Bool) {
            if isItem, let name = placed.item.name { namedRects[name] = placed.rect }
            placed.controls.forEach { read($0) }
            placed.items.forEach { read($0, isItem: true) }
        }

        private mutating func read(_ placed: Control) {
            let control = placed.control, input = control.input
            targets += placed.targets
            if let gauge = placed.gauge { gauges[control.id] = gauge }
            if case .search(_, let font) = placed.look { searchFont = font }
            if let name = control.name {
                namedRects[name] = placed.rect
                // What a right-click does goes on the control's last target (`ContextMenu`).
                if let click = input.rightClick, let index = targets.lastIndex(where: { $0.control == control.id }) {
                    targets[index].rightClick = click
                }
            }
            if let hint = placed.hint, !hint.isEmpty { hints.append((placed.rect, hint)) }
            if let name = control.name, input.onMouseEnter != nil || input.onMouseMove != nil || input.onMouseLeave != nil {
                mouseHandlers.append(.init(name: name, rect: placed.rect, enter: input.onMouseEnter, move: input.onMouseMove,
                                           leave: input.onMouseLeave))
            }
            placed.controls.forEach { read($0) }
        }
    }
}

extension AIMPSkinFrame {
    /// `image`, drawn from `layout`, and what it offers.
    init(image: CGImage, layout: AIMPSkinLayout.Tree) {
        let offers = layout.offers
        self.init(image: image, targets: offers.targets, alpha: AIMPAlphaMask(image), hints: offers.hints, namedRects: offers.namedRects,
                  mouseHandlers: offers.mouseHandlers, gauges: offers.gauges, searchFont: offers.searchFont,
                  autoHidden: layout.autoHidden)
    }
}
