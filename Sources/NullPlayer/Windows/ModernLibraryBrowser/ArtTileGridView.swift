import AppKit

/// A scrolling grid of art tiles, each with its title and subtitle underneath — the Library
/// Browser's Tiles mode. Layer-backed and virtualised: only the rows on screen have layers. Art is
/// the 400 px preview from `LibraryRowThumbnails`, so tiles and list rows share one load and cache.
/// Click selects a tile, double-click or Return activates it, right-click shows its row's menu.
final class ArtTileGridView: NSView, LibraryArtView {
    var onActivate: ((Int) -> Void)?
    var onMenu: ((Int, NSEvent) -> Void)?
    var onApproachingEnd: (() -> Void)?
    var style: LibraryArtStyle = .fallback {
        didSet { removeAllTiles(); needsLayout = true }
    }

    private(set) var items: [LibraryArtItem] = []
    /// The selected tile.
    private(set) var centerIndex = 0

    /// Smallest tile side; tiles grow to share a row's spare width evenly.
    private let minTileSide: CGFloat = 120
    private let gap: CGFloat = 12
    private let labelHeight: CGFloat = 34

    /// Distance scrolled down from the top of the grid.
    private var scrollOffset: CGFloat = 0
    private var tiles: [Int: TileLayer] = [:]
    /// Item ids whose preview is being read back from the cache.
    private var resolving: Set<String> = []
    private var lastApproachingEndItemCount: Int?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true
        NotificationCenter.default.addObserver(self, selector: #selector(artDidLoad),
                                               name: LibraryRowThumbnails.didLoadNotification, object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Data

    func setItems(_ newItems: [LibraryArtItem], preservingCenter: Bool) {
        let previousId = items.indices.contains(centerIndex) ? items[centerIndex].id : nil
        if newItems.isEmpty || newItems.first?.id != items.first?.id { lastApproachingEndItemCount = nil }
        items = newItems
        removeAllTiles()
        if preservingCenter, let previousId, let kept = newItems.firstIndex(where: { $0.id == previousId }) {
            centerIndex = kept
        } else {
            centerIndex = 0
            scrollOffset = 0
        }
        needsLayout = true
    }

    func setCenterIndex(_ index: Int, animated: Bool) {
        guard !items.isEmpty else { return }
        centerIndex = min(max(index, 0), items.count - 1)
        scrollToSelection()
        needsLayout = true
    }

    // MARK: Geometry

    private var columns: Int { max(1, Int((bounds.width - gap) / (minTileSide + gap))) }
    private var tileSide: CGFloat { (bounds.width - gap * CGFloat(columns + 1)) / CGFloat(columns) }
    private var rowHeight: CGFloat { tileSide + labelHeight + gap }
    private var rowCount: Int { (items.count + columns - 1) / columns }
    private var maxScrollOffset: CGFloat { max(0, gap + CGFloat(rowCount) * rowHeight - bounds.height) }

    /// A tile's art square in view coordinates (bottom-left origin).
    private func artRect(for index: Int) -> CGRect {
        let column = index % columns, row = index / columns
        let top = gap + CGFloat(row) * rowHeight - scrollOffset
        return CGRect(x: gap + CGFloat(column) * (tileSide + gap), y: bounds.height - top - tileSide,
                      width: tileSide, height: tileSide)
    }

    private var visibleRows: ClosedRange<Int>? {
        guard rowCount > 0, bounds.height > 0 else { return nil }
        let first = max(0, Int((scrollOffset - gap) / rowHeight))
        let last = min(rowCount - 1, Int((scrollOffset + bounds.height) / rowHeight))
        return first <= last ? first...last : nil
    }

    private var visibleIndices: Range<Int> {
        guard let rows = visibleRows else { return 0..<0 }
        return rows.lowerBound * columns..<min(items.count, (rows.upperBound + 1) * columns)
    }

    private func scrollToSelection() {
        guard bounds.height > 0 else { return }
        let top = gap + CGFloat(centerIndex / columns) * rowHeight
        if top < scrollOffset {
            scrollOffset = top - gap
        } else if top + rowHeight > scrollOffset + bounds.height {
            scrollOffset = top + rowHeight - bounds.height
        }
        scrollOffset = min(max(scrollOffset, 0), maxScrollOffset)
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        scrollOffset = min(max(scrollOffset, 0), maxScrollOffset)
        layoutTiles()
    }

    private func layoutTiles() {
        let visible = visibleIndices
        for (index, tile) in tiles where !visible.contains(index) {
            tile.removeFromSuperlayer()
            tiles[index] = nil
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for index in visible {
            let tile = tiles[index] ?? makeTile(for: index)
            tile.layout(art: artRect(for: index), labelHeight: labelHeight)
            tile.setSelected(index == centerIndex, color: style.titleColor)
        }
        CATransaction.commit()
        loadArt(for: visible)
        requestMoreItemsIfNeeded(lastVisible: visible.upperBound)
    }

    private func makeTile(for index: Int) -> TileLayer {
        let item = items[index]
        let tile = TileLayer(item: item, style: style)
        tile.setImage(item.loadedArt)
        layer?.addSublayer(tile)
        tiles[index] = tile
        return tile
    }

    private func removeAllTiles() {
        tiles.values.forEach { $0.removeFromSuperlayer() }
        tiles.removeAll()
    }

    // MARK: Art

    @objc private func artDidLoad() { loadArt(for: visibleIndices) }

    /// Fill the visible tiles that have no art yet: a loaded preview is read back from the cache,
    /// the rest are queued (then the row of tiles past each edge).
    private func loadArt(for visible: Range<Int>) {
        let cache = LibraryRowThumbnails.shared
        var wanted: [LibraryRowThumbnails.Source] = []
        for index in visible {
            guard let tile = tiles[index], !tile.hasImage, let source = items[index].art else { continue }
            guard cache.thumbnail(for: source) != nil else { wanted.append(source); continue }
            let id = items[index].id
            guard resolving.insert(id).inserted else { continue }
            Task { [weak self] in
                let preview = await cache.previewImage(for: source)
                guard let self else { return }
                self.resolving.remove(id)
                guard let preview, let tile = self.tiles[index], self.items.indices.contains(index),
                      self.items[index].id == id else { return }
                tile.setImage(preview)
            }
        }
        let preload = LibraryRowThumbnails.preloadOrder(around: visible, count: items.count)
            .prefix(columns * 2).compactMap { items[$0].art }
        cache.request(wanted + preload)
    }

    private func requestMoreItemsIfNeeded(lastVisible: Int) {
        guard !items.isEmpty, lastVisible >= items.count - columns * 2,
              lastApproachingEndItemCount != items.count else { return }
        lastApproachingEndItemCount = items.count
        onApproachingEnd?()
    }

    // MARK: Interaction

    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY * rowHeight / 3
        let clamped = min(max(scrollOffset - delta, 0), maxScrollOffset)
        guard clamped != scrollOffset else { return }
        scrollOffset = clamped
        layoutTiles()
    }

    /// The tile (art and label) under a click, selected.
    private func selectTile(at event: NSEvent) -> Int? {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        guard let hit = visibleIndices.first(where: {
            artRect(for: $0).union(artRect(for: $0).offsetBy(dx: 0, dy: -labelHeight)).contains(point)
        }) else { return nil }
        setCenterIndex(hit, animated: false)
        return hit
    }

    override func mouseDown(with event: NSEvent) {
        if let hit = selectTile(at: event), event.clickCount == 2 { onActivate?(hit) }
    }

    override func rightMouseDown(with event: NSEvent) {
        if let hit = selectTile(at: event) { onMenu?(hit, event) }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123: setCenterIndex(centerIndex - 1, animated: false)       // left
        case 124: setCenterIndex(centerIndex + 1, animated: false)       // right
        case 126: setCenterIndex(centerIndex - columns, animated: false) // up
        case 125: setCenterIndex(centerIndex + columns, animated: false) // down
        case 36, 76: if items.indices.contains(centerIndex) { onActivate?(centerIndex) }
        default: super.keyDown(with: event)
        }
    }
}

// MARK: - TileLayer

/// One tile: the art square (or the Back label on a placeholder), with title and subtitle below.
private final class TileLayer: CALayer {
    private let art = CALayer()
    private let title = CATextLayer()
    private let subtitle = CATextLayer()
    private var backLabel: CATextLayer?
    private(set) var hasImage = false

    init(item: LibraryArtItem, style: LibraryArtStyle) {
        super.init()
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        art.contentsGravity = .resizeAspectFill
        art.masksToBounds = true
        art.cornerRadius = 3
        art.backgroundColor = style.placeholderFill.cgColor
        addSublayer(art)
        for (text, layer, size, weight, color) in [
            (item.isBack ? "" : item.title, title, CGFloat(12), NSFont.Weight.semibold, style.titleColor),
            (item.subtitle, subtitle, CGFloat(10), NSFont.Weight.regular, style.subtitleColor),
        ] {
            layer.string = text
            layer.font = NSFont.systemFont(ofSize: size, weight: weight)
            layer.fontSize = size
            layer.foregroundColor = color.cgColor
            layer.truncationMode = .end
            layer.contentsScale = scale
            addSublayer(layer)
        }
        if item.isBack {
            let label = CATextLayer()
            label.string = item.title
            label.fontSize = 22
            label.alignmentMode = .center
            label.foregroundColor = style.titleColor.cgColor
            label.contentsScale = scale
            art.addSublayer(label)
            backLabel = label
        }
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func layout(art rect: CGRect, labelHeight: CGFloat) {
        art.frame = rect
        title.frame = CGRect(x: rect.minX, y: rect.minY - 18, width: rect.width, height: 16)
        subtitle.frame = CGRect(x: rect.minX, y: rect.minY - labelHeight, width: rect.width, height: 14)
        backLabel?.frame = CGRect(x: 0, y: rect.height / 2 - 14, width: rect.width, height: 28)
    }

    func setImage(_ image: CGImage?) {
        guard let image else { return }
        art.contents = image
        art.backgroundColor = nil
        hasImage = true
    }

    func setSelected(_ selected: Bool, color: NSColor) {
        art.borderWidth = selected ? 2 : 0
        art.borderColor = color.cgColor
    }
}
