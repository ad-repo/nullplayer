import AppKit

/// How the Library Browser shows its rows: the list, the Cover Flow carousel, or a grid of art
/// tiles. One choice for both browsers, kept across relaunches and tab switches.
enum LibraryViewMode: String, CaseIterable {
    case list, flow, tiles

    private static let defaultsKey = "LibraryBrowserViewMode"

    static var saved: LibraryViewMode {
        get { UserDefaults.standard.string(forKey: defaultsKey).flatMap(LibraryViewMode.init) ?? .list }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }

    /// The mode's button icon, filled in `color` and fitted into `rect`. Drawn on an 8×8 grid so it
    /// stays crisp at whole-number scales, and symmetric top to bottom so a flipped context draws
    /// it the same.
    func drawIcon(in rect: CGRect, color: NSColor, context: CGContext) {
        let unit = min(rect.width, rect.height) / 8
        let origin = CGPoint(x: rect.midX - 4 * unit, y: rect.midY - 4 * unit)
        let cells: [CGRect]
        switch self {
        case .list:  cells = [CGRect(x: 0, y: 0, width: 8, height: 2), CGRect(x: 0, y: 3, width: 8, height: 2),
                              CGRect(x: 0, y: 6, width: 8, height: 2)]
        case .flow:  cells = [CGRect(x: 0, y: 2, width: 1, height: 4), CGRect(x: 2, y: 0, width: 4, height: 8),
                              CGRect(x: 7, y: 2, width: 1, height: 4)]
        case .tiles: cells = [CGRect(x: 0, y: 0, width: 3, height: 3), CGRect(x: 5, y: 0, width: 3, height: 3),
                              CGRect(x: 0, y: 5, width: 3, height: 3), CGRect(x: 5, y: 5, width: 3, height: 3)]
        }
        context.saveGState()
        context.setFillColor(color.cgColor)
        for cell in cells {
            context.fill(CGRect(x: origin.x + cell.minX * unit, y: origin.y + cell.minY * unit,
                                width: cell.width * unit, height: cell.height * unit))
        }
        context.restoreGState()
    }
}

/// One item of the art views (Cover Flow, tiles), built by a browser from a display row.
struct LibraryArtItem {
    let id: String
    let title: String
    let subtitle: String
    /// The browser's in-memory full-size art, if it has it already.
    let cachedArtwork: () -> NSImage?
    /// The art's loader and cache key. Cover Flow runs `load` for full-size art; tiles take the
    /// 400 px preview through `LibraryRowThumbnails`, which shares its loads with the list rows.
    let art: LibraryRowThumbnails.Source?
    var isBack = false
    /// The art's width over its height: 1 for covers, `posterAspect` for movies, shows and seasons.
    var artAspect: CGFloat = 1

    static let posterAspect: CGFloat = 2.0 / 3.0

    static let back = LibraryArtItem(id: "__art_back__", title: "‹ Back", subtitle: "",
                                     cachedArtwork: { nil }, art: nil, isBack: true)

    /// The art if memory holds it now: the 400 px preview, else the browser's full-size copy.
    @MainActor var loadedArt: CGImage? {
        art.flatMap(LibraryRowThumbnails.shared.cachedPreview)
            ?? cachedArtwork()?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}

/// Theming for the art views. Their background is always clear so the Cava backdrop shows
/// through; callers supply text and placeholder colors from their active skin.
struct LibraryArtStyle {
    var titleColor: NSColor
    var subtitleColor: NSColor
    var placeholderFill: NSColor
    var placeholderTextColor: NSColor
    var reflectionStrength: CGFloat = 0.35

    static let fallback = LibraryArtStyle(
        titleColor: .white,
        subtitleColor: NSColor.white.withAlphaComponent(0.6),
        placeholderFill: NSColor(white: 0.16, alpha: 1),
        placeholderTextColor: NSColor.white.withAlphaComponent(0.5)
    )
}

/// What the lens asks of an art view. `centerIndex` is the centred cover, or the selected tile
/// or track.
@MainActor
protocol LibraryArtView: NSView {
    var style: LibraryArtStyle { get set }
    var onActivate: ((Int) -> Void)? { get set }
    /// A right-click on an item: the browser shows that row's own context menu.
    var onMenu: ((Int, NSEvent) -> Void)? { get set }
    var onApproachingEnd: (() -> Void)? { get set }
    var centerIndex: Int { get }
    func setItems(_ items: [LibraryArtItem], preservingCenter: Bool)
    func setCenterIndex(_ index: Int, animated: Bool)
}

/// A browser display row as the lens sees it.
protocol LibraryArtRow {
    var id: String { get }
    var indentLevel: Int { get }
    var hasChildren: Bool { get }
    /// Artists, albums, folders, tracks, movies, shows, seasons and episodes.
    var isArtItem: Bool { get }
    var isAlbumItem: Bool { get }
    var isVideoContainer: Bool { get }
}

/// The Flow and Tiles views over a browser's display rows, shared by both browsers. It owns the
/// view mode, the art view standing in for the list, and the tree navigation: a focus stack of the
/// containers drilled into, a synthetic ‹ Back item, and re-centring after a level change. An
/// album opens its own screen (`ArtAlbumView`) listing its tracks. The browser keeps what is its
/// own — its rows, their art, expanding and playing them, and their context menus.
@MainActor
final class LibraryArtLens<Row: LibraryArtRow> {
    struct Host {
        var rows: () -> [Row]
        var isSearch: () -> Bool
        var selectedIndex: () -> Int?
        /// Loading, an error, or a Plex source not linked: the browser draws that state instead.
        var isBlocked: () -> Bool
        var style: () -> LibraryArtStyle
        var item: (Row) -> LibraryArtItem
        var isExpanded: (Row) -> Bool
        var toggleExpand: (Row) -> Void
        var play: (Row) -> Void
        /// Show the row's context menu, as a right-click on it in the list would.
        var menu: (Row, NSEvent) -> Void
        /// The album screen's facts and description for an album row.
        var albumInfo: (Row) -> LibraryAlbumInfo?
        /// Append the next page of a paginated library, if the source has one.
        var loadNextPage: () -> Void
    }

    private let host: Host
    private weak var container: NSView?
    private let flowLabelPlacement: CoverFlowView.LabelPlacement

    private(set) var view: (any LibraryArtView)?
    /// Which view `view` is; an open album shows its own screen whatever the mode.
    private enum ViewKind { case flow, tiles, album }
    private var viewKind: ViewKind?
    var frame: NSRect = .zero { didSet { view?.frame = frame } }

    var mode: LibraryViewMode = .saved {
        didSet {
            guard mode != oldValue else { return }
            LibraryViewMode.saved = mode
            modeDidChange(from: oldValue)
        }
    }

    /// The current level's rows (Back excluded), aligned with the view for activation.
    private var levelRows: [Row] = []
    /// Containers drilled into, outermost first; the root level when empty.
    private(set) var focusStack: [String] = []
    /// After a drill-in, centre the first child once children appear.
    private var centerFirstChild = false
    /// After Back or a mode switch, centre this row once the level is rebuilt.
    private var pendingCenterId: String?
    private var rebuildScheduled = false

    init(container: NSView, flowLabelPlacement: CoverFlowView.LabelPlacement = .bottomBand, host: Host) {
        self.container = container
        self.flowLabelPlacement = flowLabelPlacement
        self.host = host
    }

    /// Search results sit one level below their synthetic category headers.
    private var rootLevel: Int { host.isSearch() ? 1 : 0 }

    /// True when the current list has art rows at its root. Evaluated on every server-bar draw,
    /// so it short-circuits instead of building the level.
    var hasItems: Bool {
        let rootLevel = rootLevel
        return host.rows().contains { $0.indentLevel == rootLevel && $0.isArtItem }
    }

    /// The art view stands in for the list: a mode other than List over a list with art rows.
    var isPresenting: Bool { mode != .list && hasItems }

    // MARK: Browser events

    /// The display rows changed. Coalesced to one rebuild: browsers mutate their rows many times
    /// per reload, and a rebuild per mutation beachballs.
    func rowsDidChange() {
        guard mode != .list, !rebuildScheduled else { return }
        rebuildScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.rebuildScheduled = false
            self.rebuild()
        }
    }

    /// A tab or source change: back to the root level, in the same mode.
    func resetNavigation() {
        focusStack.removeAll()
        centerFirstChild = false
        pendingCenterId = nil
        rowsDidChange()
    }

    /// The skin or its palette changed: recolour the art view, which takes its colours when made.
    func restyle() {
        view?.style = host.style()
    }

    func updateVisibility() {
        view?.isHidden = !isPresenting || host.isBlocked()
    }

    func teardown() {
        view?.removeFromSuperview()
        view = nil
        viewKind = nil
        levelRows = []
    }

    // MARK: Mode

    private func modeDidChange(from oldMode: LibraryViewMode) {
        if oldMode == .list {
            seedFocusFromSelection()
        } else if let view, levelRows.indices.contains(view.centerIndex - backOffset) {
            // Flow ↔ Tiles keeps the level and the item the old view was on.
            pendingCenterId = levelRows[view.centerIndex - backOffset].id
        }
        teardown()
        if mode == .list {
            focusStack.removeAll()
            centerFirstChild = false
            pendingCenterId = nil
        } else {
            rebuild()
        }
        container?.window?.makeFirstResponder(isPresenting ? view : container)
    }

    /// Switching on with a container already expanded and selected in the list (an artist showing
    /// its albums) opens inside that container rather than back at the root.
    private func seedFocusFromSelection() {
        focusStack.removeAll()
        centerFirstChild = false
        pendingCenterId = nil
        let rows = host.rows()
        guard let idx = host.selectedIndex(), rows.indices.contains(idx) else { return }
        let selected = rows[idx]
        guard selected.indentLevel >= rootLevel, selected.isArtItem else { return }

        let ancestors = ancestorIds(ofIndex: idx, in: rows)
        if selected.hasChildren, host.isExpanded(selected) {
            focusStack = ancestors + [selected.id]
            centerFirstChild = true
        } else {
            focusStack = ancestors
            pendingCenterId = selected.id
        }
    }

    /// The art container ids from the root down to the row's parent; empty at the root, or when an
    /// ancestor is not an art row.
    private func ancestorIds(ofIndex idx: Int, in rows: [Row]) -> [String] {
        var chain: [String] = []
        var neededLevel = rows[idx].indentLevel - 1
        var i = idx - 1
        while i >= 0, neededLevel >= rootLevel {
            if rows[i].indentLevel == neededLevel {
                guard rows[i].isArtItem else { return [] }
                chain.insert(rows[i].id, at: 0)
                neededLevel -= 1
            }
            i -= 1
        }
        return chain
    }

    // MARK: Level

    private var backOffset: Int { focusStack.isEmpty ? 0 : 1 }

    /// The art rows at the root, or the direct children of the container drilled into.
    private func currentLevelRows(in rows: [Row]) -> [Row] {
        guard let parentId = focusStack.last else {
            let rootLevel = rootLevel
            return rows.filter { $0.indentLevel == rootLevel && $0.isArtItem }
        }
        guard let parentIdx = rows.firstIndex(where: { $0.id == parentId }) else { return [] }
        let parentLevel = rows[parentIdx].indentLevel
        return rows[(parentIdx + 1)...]
            .prefix { $0.indentLevel > parentLevel }
            .filter { $0.indentLevel == parentLevel + 1 && $0.isArtItem }
    }

    /// The album drilled into, if the focus is one.
    private func openAlbum(in rows: [Row]) -> Row? {
        guard let id = focusStack.last else { return nil }
        return rows.first { $0.id == id && $0.isAlbumItem }
    }

    func rebuild() {
        guard mode != .list else { return }
        let rows = host.rows()
        let album = openAlbum(in: rows)
        let view = installedView(album == nil ? (mode == .flow ? .flow : .tiles) : .album)
        let level = currentLevelRows(in: rows)
        levelRows = level
        if let album, let albumView = view as? ArtAlbumView {
            // The container it was opened from: its artist, the header's name and the backdrop.
            let opener = focusStack.dropLast().last.flatMap { id in rows.first { $0.id == id } }
            albumView.setAlbum(host.item(album), opener: opener.map(host.item), info: host.albumInfo(album))
        }

        let items = (focusStack.isEmpty ? [] : [LibraryArtItem.back]) + level.map(host.item)
        // A level change owns its centring; only a refresh of the same level keeps the old centre.
        view.setItems(items, preservingCenter: !centerFirstChild && pendingCenterId == nil)
        if centerFirstChild, !level.isEmpty {
            centerFirstChild = false
            view.setCenterIndex(backOffset, animated: false)
        } else if let id = pendingCenterId, let idx = level.firstIndex(where: { $0.id == id }) {
            pendingCenterId = nil
            view.setCenterIndex(idx + backOffset, animated: false)
        }
        updateVisibility()
    }

    private func installedView(_ kind: ViewKind) -> any LibraryArtView {
        if let view, viewKind == kind { return view }
        view?.removeFromSuperview()
        let view: any LibraryArtView
        switch kind {
        case .flow:
            let flow = CoverFlowView()
            flow.labelPlacement = flowLabelPlacement
            view = flow
        case .tiles:
            view = ArtTileGridView()
        case .album:
            let albumView = ArtAlbumView()
            albumView.onPlayAlbum = { [weak self] in self?.withOpenAlbum { self?.host.play($0) } }
            albumView.onAlbumMenu = { [weak self] event in self?.withOpenAlbum { self?.host.menu($0, event) } }
            view = albumView
        }
        view.style = host.style()
        view.onActivate = { [weak self] index in self?.activate(at: index) }
        view.onMenu = { [weak self] index, event in
            guard let self, let row = self.row(at: index) else { return }
            self.host.menu(row, event)
        }
        view.onApproachingEnd = { [weak self] in
            guard let self, self.focusStack.isEmpty else { return }
            self.host.loadNextPage()
        }
        view.frame = frame
        container?.addSubview(view)
        let movesFocus = container?.window?.firstResponder === self.view
        self.view = view
        viewKind = kind
        if movesFocus { container?.window?.makeFirstResponder(view) }
        return view
    }

    private func withOpenAlbum(_ body: (Row) -> Void) {
        openAlbum(in: host.rows()).map(body)
    }

    // MARK: Navigation

    /// Centre the first row of the level shown that `matches`; false when none does. The alphabet
    /// index beside Flow and Tiles jumps this way.
    @discardableResult
    func center(onFirst matches: (Row) -> Bool) -> Bool {
        guard let view, let index = levelRows.firstIndex(where: matches) else { return false }
        view.setCenterIndex(index + backOffset, animated: true)
        return true
    }

    /// The row behind a view index; nil for ‹ Back.
    private func row(at index: Int) -> Row? {
        let realIndex = index - backOffset
        return levelRows.indices.contains(realIndex) ? levelRows[realIndex] : nil
    }

    /// Back pops a level; leaves play; containers drill into their children — an album into its
    /// own screen. Search results open albums and video containers only.
    func activate(at index: Int) {
        if !focusStack.isEmpty, index == 0 {
            navigateBack()
            return
        }
        guard let row = row(at: index) else { return }
        if row.hasChildren, !host.isSearch() || row.isAlbumItem || row.isVideoContainer {
            drillIn(row)
        } else {
            host.play(row)
        }
    }

    private func drillIn(_ row: Row) {
        // Children may load asynchronously; the retained flag re-centres once they arrive.
        if !host.isExpanded(row) { host.toggleExpand(row) }
        focusStack.append(row.id)
        centerFirstChild = true
        pendingCenterId = nil
        rebuild()
    }

    private func navigateBack() {
        guard let popped = focusStack.popLast() else { return }
        centerFirstChild = false
        pendingCenterId = popped
        rebuild()
    }
}
