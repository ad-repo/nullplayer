import AppKit

/// Where a browser's list sits, worked out by its view in one place. Drawing, every hit test and
/// every scroll range read it, so a click lands on the row drawn under it (PR #480: hit tests
/// reserved the header on a different condition than drawing, and every click landed one row up).
struct LibraryBrowserListLayout {
    /// Below the tab bar (and search bar), above the offline banner, the window's full inner
    /// width. Loading, error and art views fill it.
    let area: NSRect
    /// The column header band and the columns it shows, when the list has columns.
    let header: Header?
    /// Where rows are drawn: under the header, left of the scrollbar and alphabet index.
    let rows: NSRect
    /// The alphabet index, beside the rows.
    let alphabet: NSRect
    /// Right of the header, above an alphabet index that starts under it: filled as header.
    let headerGap: NSRect?
    /// The offline-volume banner under `area`, when a local watch folder is offline.
    let banner: NSRect?
    let rowHeight: CGFloat
    /// UI Size: 1 at 100%.
    let scale: CGFloat
    /// The classic view draws in skin coordinates, which run top-down; the modern view in AppKit's,
    /// which run bottom-up.
    let isFlipped: Bool

    struct Header {
        let rect: NSRect
        let columns: [LibraryBrowserColumn]
        /// The group the columns' widths are keyed by; nil for radio's fixed columns.
        let group: LibraryColumnVisibilityGroup?
    }

    /// Split `content` — everything under the tab bar (and search bar) — into the list's parts,
    /// in the view's own coordinates: the banner along the bottom, then the header along the top
    /// of the rows, with the alphabet index and scrollbar down the right. `alphabetBesideHeader`
    /// runs the index the list's full height rather than starting under the header.
    init(content: NSRect, bannerHeight: CGFloat,
         columns: [LibraryBrowserColumn], group: LibraryColumnVisibilityGroup?, headerHeight: CGFloat,
         scrollbarWidth: CGFloat, alphabetWidth: CGFloat, alphabetBesideHeader: Bool,
         rowHeight: CGFloat, scale: CGFloat, isFlipped: Bool) {
        let top: CGRectEdge = isFlipped ? .minYEdge : .maxYEdge
        let bottom: CGRectEdge = isFlipped ? .maxYEdge : .minYEdge
        let (banner, area) = content.divided(atDistance: bannerHeight, from: bottom)
        let headerHeight = columns.isEmpty ? 0 : headerHeight
        let listWidth = area.width - scrollbarWidth - alphabetWidth
        let (headerRect, rows) = NSRect(x: area.minX, y: area.minY, width: listWidth, height: area.height)
            .divided(atDistance: headerHeight, from: top)
        let alphabet = NSRect(x: area.minX + listWidth, y: area.minY, width: alphabetWidth, height: area.height)

        self.area = area
        self.header = columns.isEmpty ? nil : Header(rect: headerRect, columns: columns, group: group)
        self.rows = rows
        self.alphabet = alphabetBesideHeader ? alphabet : alphabet.divided(atDistance: headerHeight, from: top).remainder
        self.headerGap = alphabetBesideHeader || columns.isEmpty ? nil
            : NSRect(x: headerRect.maxX, y: headerRect.minY, width: area.maxX - headerRect.maxX, height: headerRect.height)
        self.banner = bannerHeight > 0 ? banner : nil
        self.rowHeight = rowHeight
        self.scale = scale
        self.isFlipped = isFlipped
    }

    /// How far `y` lies below the top of `rect`.
    func depth(of y: CGFloat, in rect: NSRect) -> CGFloat {
        isFlipped ? y - rect.minY : rect.maxY - y
    }

    /// Row `index`'s rect, with the list scrolled by `scrollOffset`.
    func rowRect(_ index: Int, scrollOffset: CGFloat) -> NSRect {
        band(index, height: rowHeight, in: rows, scrollOffset: scrollOffset)
    }

    /// The `index`th band `height` tall down `rect`, counting from its top.
    func band(_ index: Int, height: CGFloat, in rect: NSRect, scrollOffset: CGFloat = 0) -> NSRect {
        let top = CGFloat(index) * height - scrollOffset
        let y = isFlipped ? rect.minY + top : rect.maxY - top - height
        return NSRect(x: rect.minX, y: y, width: rect.width, height: height)
    }

    /// The header's band at any x, so a right-click above the alphabet index still opens the
    /// column menu.
    func isInHeaderBand(_ point: NSPoint) -> Bool {
        guard let header else { return false }
        return point.y >= header.rect.minY && point.y < header.rect.maxY
    }
}

/// The list half of a library browser view, shared by the classic and modern views: scrolling,
/// the column header, clicks, keys and right-click menus on the rows, and the Flow / Tiles lens
/// standing in for them. The view lays the list out and draws it; points reach here in the
/// layout's coordinates.
@MainActor
final class LibraryBrowserList {
    struct Host {
        let layout: () -> LibraryBrowserListLayout
        let artStyle: () -> LibraryArtStyle
        /// The window's Background submenu, offered atop every menu the list pops up.
        let backdropMenu: () -> NSMenuItem?
    }

    static let alphabetLetters = ["#"] + (65...90).map { String(UnicodeScalar($0)) }

    private unowned let view: NSView
    let model: LibraryBrowserModel
    private let actions: LibraryBrowserActions
    private let art: LibraryBrowserArt
    private let host: Host

    var scrollOffset: CGFloat = 0
    var horizontalScrollOffset: CGFloat = 0
    private let typeAhead = LibraryTypeAhead()
    private var resize: (column: LibraryBrowserColumn.ID, group: LibraryColumnVisibilityGroup,
                         startX: CGFloat, startWidth: CGFloat)?

    /// List, Flow or Tiles, and the Flow / Tiles view standing in for the list.
    private(set) lazy var lens = LibraryArtLens<LibraryBrowserItem>(
        container: view, flowLabelPlacement: flowLabelPlacement, host: .init(
            rows: { [unowned self] in model.displayItems },
            isSearch: { [unowned self] in model.browseMode == .search },
            selectedIndex: { [unowned self] in model.selectedIndices.min() },
            isBlocked: { [unowned self] in model.listState != .rows },
            style: host.artStyle,
            item: { [unowned self] in art.artItem(for: $0) },
            isExpanded: { [unowned self] in model.isExpanded($0) },
            toggleExpand: { [unowned self] in model.toggleExpand($0) },
            play: { [unowned self] in actions.activate($0) },
            menu: { [unowned self] row, event in
                // As a right-click on the row in the list: select it, then its menu.
                if let index = model.displayItems.firstIndex(where: { $0.id == row.id }) { model.selectedIndices = [index] }
                popUp(actions.contextMenu(for: row), with: event)
            },
            albumInfo: { [unowned self] in actions.playable(for: $0).flatMap(LibraryAlbumInfo.init) },
            loadNextPage: { [unowned self] in
                if model.currentSource.isLocal { model.appendNextLocalPage() }
            }
        ))
    private let flowLabelPlacement: CoverFlowView.LabelPlacement

    init(view: NSView, model: LibraryBrowserModel, actions: LibraryBrowserActions, art: LibraryBrowserArt,
         flowLabelPlacement: CoverFlowView.LabelPlacement = .bottomBand, host: Host) {
        self.view = view
        self.model = model
        self.actions = actions
        self.art = art
        self.flowLabelPlacement = flowLabelPlacement
        self.host = host
    }

    func teardown() {
        typeAhead.cancel()
        lens.teardown()
    }

    /// The list's part of a model change; the view handles the rest.
    func modelDidChange(_ change: LibraryBrowserModel.Change) {
        switch change {
        case .rows: lens.rowsDidChange()
        case .listState: lens.updateVisibility()
        case .rowsReplaced: scrollOffset = 0
        case .rebuilt: horizontalScrollOffset = 0
        // With nothing playing, the artwork background shows the browsed library's art.
        case .loaded: art.showBrowsedLibrary()
        case .reveal(let index): ensureVisible(index)
        case .source:
            lens.resetNavigation()
            scrollOffset = 0
        case .columns: clampHorizontalScrollOffset()
        // A new tab opens at its top, and Flow or Tiles at its root.
        case .browseMode:
            lens.resetNavigation()
            scrollOffset = 0
        }
    }

    // MARK: - Columns

    /// The header's columns and the group their widths are keyed by. Flow / Tiles draw none.
    func headerColumns() -> (columns: [LibraryBrowserColumn], group: LibraryColumnVisibilityGroup?) {
        let group = model.currentColumnGroup()
        return (lens.isPresenting ? [] : model.headerColumns(for: group), group)
    }

    /// The columns a row draws and the group their widths are keyed by (nil = a plain title line).
    /// Artist, album and track rows all draw the list's one header, Finder-style; radio and
    /// YouTube rows draw their own fixed columns.
    func rowColumns(for item: LibraryBrowserItem, header: LibraryBrowserListLayout.Header?)
        -> (columns: [LibraryBrowserColumn], group: LibraryColumnVisibilityGroup?)? {
        switch model.columnGroup(for: item) {
        case .youtube?: return (LibraryBrowserColumn.youtubeColumns, .youtube)
        case _?: return header.map { ($0.columns, $0.group) }
        case nil: return model.isInternetRadioItem(item) ? (LibraryBrowserColumn.internetRadioColumns, nil) : nil
        }
    }

    /// Each column's horizontal span across `rect`, scrolled sideways.
    func columnSpans(_ columns: [LibraryBrowserColumn], group: LibraryColumnVisibilityGroup?,
                     in rect: NSRect) -> [(column: LibraryBrowserColumn, minX: CGFloat, width: CGFloat)] {
        var x = rect.minX + 4 - horizontalScrollOffset
        return zip(columns, model.widths(of: columns, group: group, available: rect.width)).map { column, width in
            defer { x += width }
            return (column, x, width)
        }
    }

    func clampHorizontalScrollOffset() {
        horizontalScrollOffset = max(0, min(horizontalScrollOffset, maxHorizontalScrollOffset(host.layout())))
    }

    private func maxHorizontalScrollOffset(_ layout: LibraryBrowserListLayout) -> CGFloat {
        guard let header = layout.header else { return 0 }
        return max(0, model.totalWidth(of: header.columns, group: header.group, available: header.rect.width) - header.rect.width)
    }

    /// The column whose edge is under `point`: any column's trailing edge but the last, and
    /// Title's leading edge, which resizes the column before it.
    private func resizableColumn(at point: NSPoint, _ layout: LibraryBrowserListLayout) -> LibraryBrowserColumn.ID? {
        guard !model.hasInternetRadioColumns, let header = layout.header, header.columns.count > 1,
              layout.isInHeaderBand(point) else { return nil }
        let margin = 4 * layout.scale
        let spans = columnSpans(header.columns, group: header.group, in: header.rect)
        for (index, span) in spans.enumerated() {
            if index < spans.count - 1, abs(point.x - (span.minX + span.width)) < margin { return span.column.id }
            if index > 0, span.column.id == .title, abs(point.x - span.minX) < margin { return spans[index - 1].column.id }
        }
        return nil
    }

    private func headerColumn(at point: NSPoint, _ layout: LibraryBrowserListLayout) -> LibraryBrowserColumn.ID? {
        guard let header = layout.header, layout.isInHeaderBand(point) else { return nil }
        return columnSpans(header.columns, group: header.group, in: header.rect)
            .first { point.x >= $0.minX && point.x < $0.minX + $0.width }?.column.id
    }

    /// The star under `point` in an Internet Radio station's Rating cell.
    private func ratingStar(at point: NSPoint, row index: Int, _ layout: LibraryBrowserListLayout) -> Int? {
        let item = model.displayItems[index]
        guard model.hasInternetRadioColumns, case .radioStation = item.type,
              let row = rowColumns(for: item, header: layout.header),
              let cell = columnSpans(row.columns, group: row.group, in: layout.rows).first(where: { $0.column.id == .rating }),
              point.x >= cell.minX, point.x < cell.minX + cell.width else { return nil }
        let inner = max(1, cell.width - 8)
        let x = min(max(point.x, cell.minX + 4), cell.minX + cell.width - 4)
        return min(5, max(1, Int((x - cell.minX - 4) / inner * 5) + 1))
    }

    // MARK: - Hit testing

    /// The row under `point`.
    func rowIndex(at point: NSPoint) -> Int? {
        let layout = host.layout()
        guard !model.browseMode.isHistoryMode, layout.rows.contains(point) else { return nil }
        let index = Int((layout.depth(of: point.y, in: layout.rows) + scrollOffset) / layout.rowHeight)
        return model.displayItems.indices.contains(index) ? index : nil
    }

    func cursor(at point: NSPoint) -> NSCursor {
        let layout = host.layout()
        if resizableColumn(at: point, layout) != nil { return .resizeLeftRight }
        if !model.browseMode.isHistoryMode, layout.alphabet.contains(point) { return .pointingHand }
        return .arrow
    }

    // MARK: - Mouse

    /// A click on the column header, alphabet index or rows. Returns false when `point` is on none.
    func mouseDown(at point: NSPoint, event: NSEvent) -> Bool {
        guard !model.browseMode.isHistoryMode else { return false }
        let layout = host.layout()
        if let columnId = resizableColumn(at: point, layout), let header = layout.header, let group = header.group {
            let columns = header.columns
            let widths = model.widths(of: columns, group: group, available: header.rect.width)
            // Freeze Title's width so it does not flex while another column resizes.
            if model.storedColumnWidth(for: .title, group: group) == nil,
               let title = columns.firstIndex(where: { $0.id == .title }) {
                model.setColumnWidth(widths[title], for: .title, group: group)
            }
            let startWidth = columns.firstIndex { $0.id == columnId }.map { widths[$0] } ?? 0
            resize = (columnId, group, point.x, startWidth)
            NSCursor.resizeLeftRight.push()
            return true
        }
        if let columnId = headerColumn(at: point, layout) {
            model.sortByColumn(columnId)
            view.needsDisplay = true
            return true
        }
        if layout.alphabet.contains(point) {
            let letterHeight = layout.alphabet.height / CGFloat(Self.alphabetLetters.count)
            let index = Int(layout.depth(of: point.y, in: layout.alphabet) / letterHeight)
            if letterHeight > 0, Self.alphabetLetters.indices.contains(index) {
                scrollToLetter(Self.alphabetLetters[index])
            }
            return true
        }
        guard let index = rowIndex(at: point) else { return false }
        clickRow(index, at: point, event: event, layout)
        return true
    }

    /// Dragging a column edge. Returns false when no column is resizing.
    func mouseDragged(at point: NSPoint) -> Bool {
        guard let resize else { return false }
        let minWidth = LibraryBrowserColumn.findColumn(id: resize.column)?.minWidth ?? 30
        model.setColumnWidth(max(minWidth, resize.startWidth + point.x - resize.startX), for: resize.column, group: resize.group)
        view.needsDisplay = true
        return true
    }

    func mouseUp() {
        guard resize != nil else { return }
        resize = nil
        NSCursor.pop()
    }

    private func clickRow(_ index: Int, at point: NSPoint, event: NSEvent, _ layout: LibraryBrowserListLayout) {
        let item = model.displayItems[index]
        let inExpandZone = point.x < layout.rows.minX + CGFloat(item.indentLevel) * 16 + 20
        defer { view.needsDisplay = true }

        if case .radioFolder(let folder) = item.type {
            if folder.hasChildren && (inExpandZone || event.clickCount == 2) {
                model.toggleExpand(item)
            } else {
                model.selectedIndices = [model.displayItems.firstIndex { $0.id == folder.id } ?? index]
            }
            return
        }

        if let star = ratingStar(at: point, row: index, layout), case .radioStation(let station) = item.type {
            RadioManager.shared.setRating(RadioManager.shared.rating(for: station) == star ? 0 : star, for: station)
            model.selectedIndices = [index]
            return
        }

        if item.hasChildren {
            if item.type.isAlbumItem {
                // An album expands on the click and is selected too.
                if event.clickCount == 1 { model.toggleExpand(item) }
            } else if inExpandZone {
                model.toggleExpand(item)
                return
            }
        }

        if event.modifierFlags.contains(.shift) {
            let anchor = model.selectedIndices.max() ?? index
            model.selectedIndices.formUnion(min(anchor, index)...max(anchor, index))
            art.showSelection()
        } else if event.modifierFlags.contains(.command) {
            if model.selectedIndices.remove(index) == nil { model.selectedIndices.insert(index) }
            art.showSelection()
        } else {
            model.selectedIndices = [index]
            // A single click selects; rows play on double-click. A station found by search plays
            // on the click.
            if model.browseMode == .search, case .radioStation(let station) = item.type, event.clickCount == 1 {
                RadioManager.shared.play(station: station)
            } else {
                art.showSelection()
            }
        }

        if event.clickCount == 2 { actions.activate(item) }
    }

    // MARK: - Menus

    /// A right-click: the column menu on the header, the row's menu on a row (selecting it), else
    /// the empty-space menu. Returns false when there is no menu to show.
    func rightMouseDown(at point: NSPoint, event: NSEvent) -> Bool {
        let layout = host.layout()
        let menu: NSMenu?
        if model.browseMode.isHistoryMode {
            menu = nil
        } else if layout.isInHeaderBand(point) {
            menu = actions.columnMenu()
        } else if let index = rowIndex(at: point) {
            if !model.selectedIndices.contains(index) {
                model.selectedIndices = [index]
                view.needsDisplay = true
            }
            menu = actions.contextMenu(for: model.displayItems[index])
        } else {
            menu = actions.emptySpaceMenu()
        }
        return popUp(menu, with: event)
    }

    /// Pop `menu` up at the click, with the window's Background submenu on top.
    @discardableResult
    private func popUp(_ menu: NSMenu?, with event: NSEvent) -> Bool {
        let menu = menu ?? NSMenu()
        if let backdrop = host.backdropMenu() {
            if !menu.items.isEmpty { menu.insertItem(.separator(), at: 0) }
            menu.insertItem(backdrop, at: 0)
        }
        guard !menu.items.isEmpty else { return false }
        NSMenu.popUpContextMenu(menu, with: event, for: view)
        return true
    }

    // MARK: - Scrolling

    /// A scroll-wheel event: the rows, or the columns sideways with Shift or a mostly sideways
    /// swipe. Returns whether the list moved.
    func scrollWheel(_ event: NSEvent) -> Bool {
        guard !model.browseMode.isHistoryMode else { return false }
        let layout = host.layout()
        let vertical = event.hasPreciseScrollingDeltas && event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.deltaY * 3
        let horizontal = event.hasPreciseScrollingDeltas && event.scrollingDeltaX != 0 ? event.scrollingDeltaX : event.deltaX * 3
        let shift = event.modifierFlags.contains(.shift)
        var moved = false

        let maxHorizontal = maxHorizontalScrollOffset(layout)
        if maxHorizontal > 0, shift || abs(horizontal) > abs(vertical) {
            horizontalScrollOffset = max(0, min(maxHorizontal, horizontalScrollOffset - (shift ? vertical : horizontal)))
            moved = true
        }
        let maxVertical = CGFloat(model.displayItems.count) * layout.rowHeight - layout.rows.height
        if maxVertical > 0, vertical != 0, !shift {
            scrollOffset = max(0, min(maxVertical, scrollOffset - vertical))
            moved = true
        }

        // Near the end of a paged local tab, load the next page.
        if model.currentSource.isLocal,
           scrollOffset + layout.rows.height + layout.rowHeight * 10 >= CGFloat(model.displayItems.count) * layout.rowHeight {
            model.appendNextLocalPage()
        }
        return moved
    }

    /// How far down the rows are scrolled, 0 to 1, for a scrollbar.
    var scrollPosition: CGFloat {
        let layout = host.layout()
        let range = CGFloat(model.displayItems.count) * layout.rowHeight - layout.rows.height
        return range > 0 ? min(1, max(0, scrollOffset / range)) : 0
    }

    func ensureVisible(_ index: Int) {
        let layout = host.layout()
        let top = CGFloat(index) * layout.rowHeight
        if top < scrollOffset {
            scrollOffset = top
        } else if top + layout.rowHeight > scrollOffset + layout.rows.height {
            scrollOffset = top + layout.rowHeight - layout.rows.height
        }
    }

    /// The alphabet index: Flow / Tiles centre the letter, a paged local tab loads its page, any
    /// other list scrolls to and selects its first row.
    private func scrollToLetter(_ letter: String) {
        if lens.jump(to: { $0.sortLetter == letter }) { return }
        if let moved = model.showLocalPage(atLetter: letter) {
            if moved { scrollOffset = 0 }
            return
        }
        guard let index = model.displayItems.firstIndex(where: { $0.sortLetter == letter }) else { return }
        let layout = host.layout()
        let maxScroll = max(0, CGFloat(model.displayItems.count) * layout.rowHeight - layout.rows.height)
        scrollOffset = min(maxScroll, CGFloat(index) * layout.rowHeight)
        model.selectedIndices = [index]
        view.needsDisplay = true
    }

    // MARK: - Keys

    /// A key over the list. Returns false for a key it does not take, or on the Data tab.
    func keyDown(_ event: NSEvent) -> Bool {
        guard !model.browseMode.isHistoryMode else { return false }
        let items = model.displayItems
        let selected = model.selectedIndices.first.flatMap { items.indices.contains($0) ? $0 : nil }

        switch event.keyCode {
        case 36: // Enter: run a search typed since the last one, else play or open the selected row
            if model.hasUnsubmittedSearch {
                model.submitSearch()
            } else if event.modifierFlags.contains(.shift) {
                actions.runOnSelection(.playNext)
            } else if event.modifierFlags.contains(.option) {
                actions.runOnSelection(.addToQueue)
            } else if let selected {
                actions.activate(items[selected])
            }
        case 124: // Right: expand, or step into an expanded row's first child
            guard let selected, items[selected].hasChildren else { break }
            if model.isExpanded(items[selected]) {
                select(selected + 1)
            } else {
                model.toggleExpand(items[selected])
            }
        case 123: // Left: collapse, or step out to the parent row
            guard let selected else { break }
            let item = items[selected]
            if model.isExpanded(item) {
                model.toggleExpand(item)
            } else if item.indentLevel > 0,
                      let parent = items[..<selected].lastIndex(where: { candidate in
                          if case .header = candidate.type { return false }
                          return candidate.indentLevel == item.indentLevel - 1
                      }) {
                select(parent)
            }
        case 48: // Tab / Shift-Tab: the next or previous tab (Folders shares the Plists slot)
            let tabs = LibraryBrowseMode.tabs
            guard let current = tabs.firstIndex(of: model.activeTabSlot) else { break }
            let step = event.modifierFlags.contains(.shift) ? tabs.count - 1 : 1
            model.selectTab(tabs[(current + step) % tabs.count], doubleClick: false)
        case 49 where model.browseMode != .search: // Space: play / pause
            MainWindowKeys.togglePlayPause()
        case 125: // Down
            if let last = model.selectedIndices.max() { select(last + 1) }
        case 126: // Up
            if let first = model.selectedIndices.min() { select(first - 1) }
        default:
            guard let characters = event.characters, !characters.isEmpty else { return false }
            if model.browseMode == .search {
                editSearch(keyCode: event.keyCode, characters: characters)
            } else if let index = typeAhead.handle(keyCode: event.keyCode, characters: characters, in: items) {
                select(index)
            }
        }
        view.needsDisplay = true
        return true
    }

    /// The search field takes typing and Delete; Enter runs the search.
    private func editSearch(keyCode: UInt16, characters: String) {
        if keyCode == 51 {
            if !model.searchQuery.isEmpty { model.searchQuery.removeLast() }
        } else if characters.rangeOfCharacter(from: .alphanumerics) != nil ||
                    characters.rangeOfCharacter(from: .whitespaces) != nil {
            model.searchQuery += characters
        }
    }

    private func select(_ index: Int) {
        guard model.displayItems.indices.contains(index) else { return }
        model.selectedIndices = [index]
        ensureVisible(index)
        art.showSelection()
    }
}
