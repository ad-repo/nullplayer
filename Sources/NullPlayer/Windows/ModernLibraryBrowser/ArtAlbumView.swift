import AppKit

/// An album opened from Flow or Tiles: ‹ Back, the cover with the album's title, detail and facts
/// lines and a Play button, its description (three lines until **More**), then its tracks — over
/// the artist's picture, dimmed, when it was opened from an artist. Click selects a track, double-click or Return plays it, right-click
/// shows its row's menu; right-click on the cover or title shows the album's. Esc goes back.
/// Item 0 is ‹ Back and the rest are the tracks, so the lens drives it like the other art views.
final class ArtAlbumView: NSView, LibraryArtView {
    var onActivate: ((Int) -> Void)?
    var onMenu: ((Int, NSEvent) -> Void)?
    var onApproachingEnd: (() -> Void)?
    var onPlayAlbum: (() -> Void)?
    var onAlbumMenu: ((NSEvent) -> Void)?
    var style: LibraryArtStyle = .fallback { didSet { needsDisplay = true } }

    private(set) var items: [LibraryArtItem] = []
    /// The selected track.
    private(set) var centerIndex = 0

    private var album: LibraryArtItem?
    private var detail = ""
    private var facts = ""
    private var summary: String?
    private var summaryExpanded = false
    private var cover: CGImage?
    private var backdrop: CGImage?
    private var backdropId: String?
    private var scrollOffset: CGFloat = 0

    private let pad: CGFloat = 12
    private let rowHeight: CGFloat = 22

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Data

    func setAlbum(_ album: LibraryArtItem, detail: String, info: LibraryAlbumInfo?, backdrop: LibraryArtItem?) {
        self.detail = detail
        facts = info?.facts.joined(separator: " · ") ?? ""
        setBackdrop(backdrop)
        guard album.id != self.album?.id else { needsDisplay = true; return }
        self.album = album
        summary = info?.summary
        summaryExpanded = false
        if summary == nil, let loadSummary = info?.loadSummary {
            Task { [weak self] in
                let loaded = await loadSummary()
                guard let self, self.album?.id == album.id, let loaded, !loaded.isEmpty else { return }
                self.summary = loaded
                self.needsDisplay = true
            }
        }
        cover = album.loadedArt
        if cover == nil, let source = album.art {
            Task { [weak self] in
                let preview = await LibraryRowThumbnails.shared.previewImage(for: source)
                guard let self, self.album?.id == album.id else { return }
                self.cover = preview
                self.needsDisplay = true
            }
        }
        needsDisplay = true
    }

    /// Full-size art: the screen is far larger than the 400 px preview.
    private func setBackdrop(_ item: LibraryArtItem?) {
        guard item?.id != backdropId else { return }
        backdropId = item?.id
        backdrop = item?.cachedArtwork()?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        if backdrop == nil, let item, let source = item.art {
            Task { [weak self] in
                let image = await source.load()?.cgImage(forProposedRect: nil, context: nil, hints: nil)
                guard let self, self.backdropId == item.id else { return }
                self.backdrop = image
                self.needsDisplay = true
            }
        }
        needsDisplay = true
    }

    func setItems(_ newItems: [LibraryArtItem], preservingCenter: Bool) {
        let previousId = items.indices.contains(centerIndex) ? items[centerIndex].id : nil
        items = newItems
        centerIndex = preservingCenter ? newItems.firstIndex { $0.id == previousId } ?? firstTrack : firstTrack
        if !preservingCenter { scrollOffset = 0 }
        needsDisplay = true
    }

    func setCenterIndex(_ index: Int, animated: Bool) {
        guard items.indices.contains(firstTrack) else { return }
        centerIndex = min(max(index, firstTrack), items.count - 1)
        scrollToSelection()
        needsDisplay = true
    }

    private var firstTrack: Int { items.first?.isBack == true ? 1 : 0 }

    // MARK: Geometry (flipped: y grows down, everything scrolls together)

    private var backRect: CGRect { CGRect(x: pad, y: pad - scrollOffset, width: 70, height: 20) }

    private var coverRect: CGRect {
        let side = min(160, max(80, (bounds.width - 2 * pad) * 0.35))
        return CGRect(x: pad, y: backRect.maxY + 8, width: side, height: side)
    }

    private var textX: CGFloat { coverRect.maxX + 14 }
    private var titleRect: CGRect {
        CGRect(x: textX, y: coverRect.minY + 4, width: max(0, bounds.width - textX - pad), height: 22)
    }
    private var detailRect: CGRect { titleRect.offsetBy(dx: 0, dy: 26) }
    private var factsRect: CGRect { CGRect(x: textX, y: detailRect.maxY + 2, width: titleRect.width, height: 16) }
    private var playRect: CGRect { CGRect(x: textX, y: factsRect.maxY + 12, width: 84, height: 26) }

    private let summaryFont = NSFont.systemFont(ofSize: 12)
    private let collapsedSummaryLines: CGFloat = 3

    /// The description's full height at the view's width, and its collapsed height.
    private func summaryHeights(_ summary: String) -> (full: CGFloat, collapsed: CGFloat) {
        let full = (summary as NSString).boundingRect(
            with: CGSize(width: bounds.width - 2 * pad, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin], attributes: [.font: summaryFont]).height.rounded(.up)
        let lineHeight = NSLayoutManager().defaultLineHeight(for: summaryFont).rounded(.up)
        return (full, min(full, lineHeight * collapsedSummaryLines))
    }

    /// Under the cover; nil without a description.
    private var summaryRect: CGRect? {
        guard let summary else { return nil }
        let heights = summaryHeights(summary)
        return CGRect(x: pad, y: coverRect.maxY + 12, width: bounds.width - 2 * pad,
                      height: summaryExpanded ? heights.full : heights.collapsed)
    }

    /// More / Less, under the description; nil when it fits in three lines.
    private var moreRect: CGRect? {
        guard let summary, let summaryRect, summaryHeights(summary).full > summaryHeights(summary).collapsed else { return nil }
        return CGRect(x: pad, y: summaryRect.maxY + 2, width: 50, height: 16)
    }

    private func trackRect(_ index: Int) -> CGRect {
        let top = (moreRect ?? summaryRect ?? coverRect).maxY + 14
        return CGRect(x: pad, y: top + CGFloat(index - firstTrack) * rowHeight,
                      width: bounds.width - 2 * pad, height: rowHeight)
    }

    private var maxScrollOffset: CGFloat {
        let contentBottom = trackRect(items.count).minY + scrollOffset + pad
        return max(0, contentBottom - bounds.height)
    }

    private func scrollToSelection() {
        let row = trackRect(centerIndex)
        if row.minY < 0 {
            scrollOffset += row.minY
        } else if row.maxY > bounds.height {
            scrollOffset += row.maxY - bounds.height
        }
        scrollOffset = min(max(scrollOffset, 0), maxScrollOffset)
    }

    private func trackIndex(at point: CGPoint) -> Int? {
        (firstTrack..<items.count).first { trackRect($0).contains(point) }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        if let backdrop {
            // Fixed behind the scrolling content, dimmed so the text stays readable.
            drawUpright(backdrop, in: aspectFill(CGSize(width: backdrop.width, height: backdrop.height), into: bounds),
                        context: context, alpha: 0.14)
        }
        text("‹ Back", in: backRect, size: 13, weight: .medium, color: style.titleColor)

        let coverRect = coverRect
        context.saveGState()
        context.addPath(CGPath(roundedRect: coverRect, cornerWidth: 3, cornerHeight: 3, transform: nil))
        context.clip()
        if let cover {
            drawUpright(cover, in: aspectFill(CGSize(width: cover.width, height: cover.height), into: coverRect),
                        context: context)
        } else {
            context.setFillColor(style.placeholderFill.cgColor)
            context.fill(coverRect)
        }
        context.restoreGState()

        text(album?.title ?? "", in: titleRect, size: 17, weight: .semibold, color: style.titleColor)
        text(detail, in: detailRect, size: 12, weight: .regular, color: style.subtitleColor)
        text(facts, in: factsRect, size: 12, weight: .regular, color: style.subtitleColor)
        if let summary, let summaryRect {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byWordWrapping
            (summary as NSString).draw(with: summaryRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                       attributes: [.font: summaryFont, .foregroundColor: style.subtitleColor,
                                                    .paragraphStyle: paragraph])
        }
        if let moreRect {
            text(summaryExpanded ? "Less" : "More", in: moreRect, size: 12, weight: .semibold, color: style.titleColor)
        }
        let play = NSBezierPath(roundedRect: playRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        style.titleColor.setStroke()
        play.stroke()
        text("▶ Play", in: playRect.insetBy(dx: 0, dy: 5), size: 12, weight: .semibold, color: style.titleColor,
             alignment: .center)

        for index in firstTrack..<items.count {
            let row = trackRect(index)
            guard row.maxY >= dirtyRect.minY, row.minY <= dirtyRect.maxY else { continue }
            if index == centerIndex {
                style.titleColor.withAlphaComponent(0.18).setFill()
                NSBezierPath(roundedRect: row, xRadius: 3, yRadius: 3).fill()
            }
            let textRow = row.insetBy(dx: 0, dy: 3)
            text("\(index - firstTrack + 1)", in: CGRect(x: row.minX, y: textRow.minY, width: 24, height: textRow.height),
                 size: 12, weight: .regular, color: style.subtitleColor, alignment: .right)
            text(items[index].subtitle, in: CGRect(x: row.maxX - 56, y: textRow.minY, width: 50, height: textRow.height),
                 size: 12, weight: .regular, color: style.subtitleColor, alignment: .right)
            text(items[index].title, in: CGRect(x: row.minX + 34, y: textRow.minY, width: max(0, row.width - 96),
                                                height: textRow.height),
                 size: 13, weight: .regular, color: style.titleColor)
        }
    }

    private func text(_ string: String, in rect: CGRect, size: CGFloat, weight: NSFont.Weight, color: NSColor,
                      alignment: NSTextAlignment = .left) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.alignment = alignment
        (string as NSString).draw(in: rect, withAttributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: paragraph,
        ])
    }

    /// The context is flipped; draw the image the right way up.
    private func drawUpright(_ image: CGImage, in rect: CGRect, context: CGContext, alpha: CGFloat = 1) {
        context.saveGState()
        context.setAlpha(alpha)
        context.translateBy(x: 0, y: rect.minY * 2 + rect.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: rect)
        context.restoreGState()
    }

    private func aspectFill(_ size: CGSize, into rect: CGRect) -> CGRect {
        let scale = max(rect.width / size.width, rect.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: rect.midX - fitted.width / 2, y: rect.midY - fitted.height / 2,
                      width: fitted.width, height: fitted.height)
    }

    // MARK: Interaction

    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY * rowHeight * 3
        scrollOffset = min(max(scrollOffset - delta, 0), maxScrollOffset)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        if backRect.contains(point), items.first?.isBack == true {
            onActivate?(0)
        } else if playRect.contains(point) {
            onPlayAlbum?()
        } else if let moreRect, moreRect.contains(point) {
            summaryExpanded.toggle()
            scrollOffset = min(scrollOffset, maxScrollOffset)
            needsDisplay = true
        } else if let hit = trackIndex(at: point) {
            setCenterIndex(hit, animated: false)
            if event.clickCount == 2 { onActivate?(hit) }
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if coverRect.contains(point) || titleRect.union(detailRect).contains(point) {
            onAlbumMenu?(event)
        } else if let hit = trackIndex(at: point) {
            setCenterIndex(hit, animated: false)
            onMenu?(hit, event)
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126: setCenterIndex(centerIndex - 1, animated: false) // up
        case 125: setCenterIndex(centerIndex + 1, animated: false) // down
        case 36, 76: if items.indices.contains(centerIndex), centerIndex >= firstTrack { onActivate?(centerIndex) }
        case 53: if items.first?.isBack == true { onActivate?(0) } // esc
        default: super.keyDown(with: event)
        }
    }
}
