import AppKit

/// Draws a library browser's list — the column header, the rows and the alphabet index — for both
/// views. Each view fills a `Style` with its skin's fonts and colours; what is drawn where is decided
/// here once.
///
/// In a flipped layout (the classic view's skin coordinates) text, thumbnails and spinners are drawn
/// in a frame turned upright about their own band, so every y here is worked out as if y ran up.
@MainActor
struct LibraryBrowserListPainter {
    struct Style {
        let titleFont: NSFont
        /// A row's info, and every cell but the title.
        let detailFont: NSFont
        let disclosureFont: NSFont
        let title: NSColor
        let selectedTitle: NSColor
        /// Every cell but the title.
        let cell: NSColor
        let selectedCell: NSColor
        /// A plain row's info.
        let info: NSColor
        let selectedInfo: NSColor
        let disclosure: NSColor
        let filledStar: NSColor
        let emptyStar: NSColor
        let selectedRowFill: NSColor
        /// Behind every unselected row, when set.
        let rowFill: NSColor?
        /// Under the rows, before the art drawn behind them, when set.
        let listFill: NSColor?
        let thumbnailPlaceholder: NSColor
        let spinner: NSColor
        /// Rows land on whole points, so text does not shimmer on a non-Retina display.
        let snapsRowsToPoints: Bool
        /// Text keeps full alpha under the window's content opacity (the modern view's skins).
        let textIgnoresContentAlpha: Bool

        let headerFill: NSColor
        let headerFont: NSFont
        let sortIndicatorFont: NSFont
        let headerTitle: NSColor
        let sortedHeaderTitle: NSColor
        let headerSeparator: NSColor
        let headerBottomLine: NSColor

        let alphabetFill: NSColor
        let letterWithRows: NSColor
        let letterWithoutRows: NSColor
    }

    let context: CGContext
    let layout: LibraryBrowserListLayout
    let style: Style
    let model: LibraryBrowserModel
    let list: LibraryBrowserList
    let art: LibraryBrowserArt
    let youtubeVideos: YouTubeVideoActions
    /// Whether a row's title draws after `∿` (`LibraryBrowserActions.isEQMarked`).
    let isEQMarked: (LibraryBrowserItem) -> Bool
    let thumbnails: LibraryRowThumbnailTracker
    /// The spinners' step, advanced by the coordinator while one turns.
    let spinnerStep: Int

    // MARK: - List

    /// The header, the rows under it, then the alphabet index. The rows must not be empty: an empty
    /// list shows each view's own message instead.
    func drawList() {
        if let header = layout.header {
            drawHeader(header)
            if let gap = layout.headerGap {
                style.headerFill.setFill()
                context.fill(gap)
            }
        }

        let rows = layout.rows
        context.saveGState()
        context.clip(to: rows)
        if let listFill = style.listFill {
            listFill.setFill()
            context.fill(rows)
        }
        art.drawBackground(in: context, rect: rows, flipped: layout.isFlipped)
        thumbnails.beginPass(placeholder: style.thumbnailPlaceholder)

        let items = model.displayItems
        let scrollOffset = list.scrollOffset
        let visibleStart = max(0, Int(scrollOffset / layout.rowHeight))
        let visibleEnd = min(items.count, visibleStart + Int(rows.height / layout.rowHeight) + 2)
        if visibleStart < visibleEnd {
            let drawnOffset = style.snapsRowsToPoints ? scrollOffset.rounded() : scrollOffset
            for index in visibleStart..<visibleEnd {
                let rect = layout.rowRect(index, scrollOffset: drawnOffset)
                guard rect.maxY >= rows.minY, rect.minY <= rows.maxY else { continue }
                drawRow(items[index], in: rect, isSelected: model.selectedIndices.contains(index))
            }
            thumbnails.endPass(visible: visibleStart..<visibleEnd, count: items.count) {
                art.rowThumbnailSource(for: items[$0])
            }
        }
        context.restoreGState()

        drawAlphabet()
    }

    // MARK: - Rows

    private func drawRow(_ item: LibraryBrowserItem, in rect: NSRect, isSelected: Bool) {
        // A track or episode whose file is on an offline volume draws dimmed.
        let isOffline = model.isOffline(item)
        if isOffline { context.saveGState(); context.setAlpha(0.35) }
        defer { if isOffline { context.restoreGState() } }

        if isSelected {
            style.selectedRowFill.setFill()
            context.fill(rect)
        } else if let rowFill = style.rowFill {
            rowFill.setFill()
            context.fill(rect)
        }

        let indent = CGFloat(item.indentLevel) * 16
        upright(about: rect.midY) {
            if let row = list.rowColumns(for: item, header: layout.header) {
                drawCells(item, columns: row.columns, group: row.group, in: rect, indent: indent, isSelected: isSelected)
            } else {
                drawPlainRow(item, in: rect, indent: indent, isSelected: isSelected)
            }
        }
    }

    /// A title line: the disclosure triangle (or a channel's spinner), the thumbnail, the title, and
    /// the info at the right — centred on the Radio tab.
    private func drawPlainRow(_ item: LibraryBrowserItem, in rect: NSRect, indent: CGFloat, isSelected: Bool) {
        let textX = rect.minX + indent + 4
        var titleInset: CGFloat = 0
        if case .youtubeChannel(let channel) = item.type, YouTubeChannelUploads.shared.isFetching(channel.id) {
            titleInset = drawRowSpinner(at: textX, in: rect)
        } else if item.hasChildren {
            let attrs: [NSAttributedString.Key: Any] = [.font: style.disclosureFont, .foregroundColor: style.disclosure]
            draw(model.isExpanded(item) ? "▼" : "▶", at: NSPoint(x: textX - 12, y: rect.midY - 5), attrs)
        }
        if let thumbnail = art.rowThumbnailSource(for: item) {
            titleInset += thumbnails.draw(thumbnail, in: context, at: textX + titleInset, rowRect: rect,
                                          side: layout.rowHeight - 2)
        }

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: style.titleFont, .foregroundColor: isSelected ? style.selectedTitle : style.title,
        ]
        draw(shownTitle(item), in: NSRect(x: textX + titleInset, y: rect.minY + 2,
                                          width: rect.width - indent - 60 - titleInset, height: layout.rowHeight - 4),
             titleAttrs)

        guard let info = item.info else { return }
        let infoAttrs: [NSAttributedString.Key: Any] = [
            .font: style.detailFont, .foregroundColor: isSelected ? style.selectedInfo : style.info,
        ]
        let size = info.size(withAttributes: infoAttrs)
        let x = model.browseMode == .radio ? rect.midX - size.width / 2 : rect.maxX - size.width - 4
        draw(info, at: NSPoint(x: x, y: rect.midY - size.height / 2), infoAttrs)
    }

    /// A row's cells under the list's columns. A downloading video's title leads with a spinner, and
    /// a row without an Art column leads its title with the round thumbnail.
    private func drawCells(_ item: LibraryBrowserItem, columns: [LibraryBrowserColumn], group: LibraryColumnVisibilityGroup?,
                           in rect: NSRect, indent: CGFloat, isSelected: Bool) {
        let hasArtColumn = columns.contains { $0.id == .thumbnail }
        let cells = LibraryColumnVisibility.cellFrames(
            widths: model.widths(of: columns, group: group, available: rect.width),
            titleIndex: columns.firstIndex { $0.id == .title }, indent: indent,
            spansLeadingCells: model.columnGroup(for: item) != group)
        for (column, cell) in zip(columns, cells) {
            let x = rect.minX + cell.start - list.horizontalScrollOffset, width = cell.width
            if column.id == .thumbnail {
                if let thumbnail = art.rowThumbnailSource(for: item) {
                    thumbnails.draw(thumbnail, in: context, at: x + 4, rowRect: rect, side: min(width - 8, rect.height - 2))
                }
                continue
            }

            let isTitle = column.id == .title
            let value = isTitle ? shownTitle(item) : item.columnValue(for: column)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: isTitle ? style.titleFont : style.detailFont,
                .foregroundColor: isTitle ? (isSelected ? style.selectedTitle : style.title)
                                          : (isSelected ? style.selectedCell : style.cell),
            ]

            var titleInset: CGFloat = 0
            if isTitle, case .youtubeVideo(let video) = item.type, youtubeVideos.isFetching(video.videoId) {
                titleInset = drawRowSpinner(at: x + 4, in: rect)
            }
            if isTitle, !hasArtColumn, let thumbnail = art.rowThumbnailSource(for: item) {
                titleInset += thumbnails.draw(thumbnail, in: context, at: x + 4 + titleInset, rowRect: rect,
                                              side: rect.height - 2)
            }

            let size = value.size(withAttributes: attrs)
            let textX = isCentered(column.id) ? x + (width - size.width) / 2 : x + 4 + titleInset
            let textRect = NSRect(x: textX, y: rect.minY + (rect.height - size.height) / 2,
                                  width: width - 8 - titleInset, height: size.height)
            if column.id == .rating, !isSelected, value.contains("★") || value.contains("☆") {
                let stars = NSMutableAttributedString(string: value, attributes: attrs)
                for (i, ch) in value.enumerated() {
                    stars.addAttribute(.foregroundColor, value: ch == "★" ? style.filledStar : style.emptyStar,
                                       range: NSRange(location: i, length: 1))
                }
                withTextAlpha { stars.draw(with: textRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine]) }
            } else {
                withTextAlpha {
                    value.draw(with: textRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
                }
            }
        }
    }

    /// The title as drawn, after `∿` when the row plays with an EQ profile, as a queue row's is.
    private func shownTitle(_ item: LibraryBrowserItem) -> String {
        EQProfileResolver.queueTitle(item.shownTitle, marked: isEQMarked(item))
    }

    /// A small spinner at the leading edge of a row's title; returns how far the title moves right.
    private func drawRowSpinner(at x: CGFloat, in rect: NSRect) -> CGFloat {
        let radius = min(rect.height * 0.3, 6)
        Self.drawSpinner(in: context, center: CGPoint(x: x + radius, y: rect.midY), innerRadius: radius * 0.45,
                         outerRadius: radius, lineWidth: 1.5, color: style.spinner, step: spinnerStep)
        return radius * 2 + 4
    }

    /// The Radio tab centres its Genre column, and Internet Radio its star ratings.
    private func isCentered(_ column: LibraryBrowserColumn.ID) -> Bool {
        (model.browseMode == .radio && column == .genre) || (column == .rating && model.hasInternetRadioColumns)
    }

    // MARK: - Header

    private func drawHeader(_ header: LibraryBrowserListLayout.Header) {
        let rect = header.rect
        context.saveGState()
        context.clip(to: rect)
        style.headerFill.setFill()
        context.fill(rect)

        upright(about: rect.midY) {
            let spans = list.columnSpans(header.columns, group: header.group, in: rect)
            for (index, (column, x, width)) in spans.enumerated() {
                let isSortColumn = model.activeColumnSortId == column.id
                let color = isSortColumn ? style.sortedHeaderTitle : style.headerTitle
                let attrs: [NSAttributedString.Key: Any] = [.font: style.headerFont, .foregroundColor: color]
                let size = column.title.size(withAttributes: attrs)
                let textY = rect.minY + (rect.height - size.height) / 2
                let textX = isCentered(column.id) ? x + (width - size.width) / 2 : x + 4
                draw(column.title, at: NSPoint(x: textX, y: textY), attrs)

                if isSortColumn {
                    draw(model.activeColumnSortAscending ? "▲" : "▼", at: NSPoint(x: textX + size.width + 3, y: textY + 1),
                         [.font: style.sortIndicatorFont, .foregroundColor: style.sortedHeaderTitle])
                }
                if index < spans.count - 1 {
                    strokeLine(from: CGPoint(x: x + width - 1, y: rect.minY + 3), to: CGPoint(x: x + width - 1, y: rect.maxY - 3),
                               color: style.headerSeparator)
                }
            }
            strokeLine(from: CGPoint(x: rect.minX, y: rect.minY), to: CGPoint(x: rect.maxX, y: rect.minY),
                       color: style.headerBottomLine)
        }
        context.restoreGState()
    }

    // MARK: - Alphabet index

    /// "#" to "Z" down the index; letters with rows stand out.
    func drawAlphabet() {
        let rect = layout.alphabet
        style.alphabetFill.setFill()
        context.fill(rect)

        let letters = LibraryBrowserList.alphabetLetters
        let letterHeight = rect.height / CGFloat(letters.count)
        let font = NSFont.boldSystemFont(ofSize: min(9 * layout.scale, letterHeight * 0.8))
        let lettersWithRows = model.lettersWithRows
        for (index, letter) in letters.enumerated() {
            let band = layout.band(index, height: letterHeight, in: rect)
            let color = lettersWithRows.contains(letter) ? style.letterWithRows : style.letterWithoutRows
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let size = letter.size(withAttributes: attrs)
            upright(about: band.midY) {
                draw(letter, at: NSPoint(x: band.midX - size.width / 2, y: band.midY - size.height / 2), attrs)
            }
        }
    }

    // MARK: - Spinner

    /// An eight-spoke spinner at `step`, its spokes fading in from clear to `maxAlpha`.
    static func drawSpinner(in context: CGContext, center: CGPoint, innerRadius: CGFloat, outerRadius: CGFloat,
                            lineWidth: CGFloat, color: NSColor, maxAlpha: CGFloat = 1, step: Int) {
        let spokes = 8
        let angleStep = CGFloat.pi * 2 / CGFloat(spokes)
        context.saveGState()
        context.setLineWidth(lineWidth)
        for i in 0..<spokes {
            let angle = CGFloat(i + step) * angleStep - CGFloat.pi / 2
            color.withAlphaComponent(CGFloat(i + 1) / CGFloat(spokes) * maxAlpha).setStroke()
            context.move(to: CGPoint(x: center.x + cos(angle) * innerRadius, y: center.y + sin(angle) * innerRadius))
            context.addLine(to: CGPoint(x: center.x + cos(angle) * outerRadius, y: center.y + sin(angle) * outerRadius))
            context.strokePath()
        }
        context.restoreGState()
    }

    // MARK: - Primitives

    /// Run `body` with y running up about `y`; in an unflipped layout it already does.
    private func upright(about y: CGFloat, _ body: () -> Void) {
        guard layout.isFlipped else { body(); return }
        context.saveGState()
        context.translateBy(x: 0, y: y)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: -y)
        body()
        context.restoreGState()
    }

    private func withTextAlpha(_ body: () -> Void) {
        guard style.textIgnoresContentAlpha else { body(); return }
        context.saveGState()
        context.setAlpha(1)
        body()
        context.restoreGState()
    }

    private func draw(_ text: String, at point: NSPoint, _ attrs: [NSAttributedString.Key: Any]) {
        withTextAlpha { text.draw(at: point, withAttributes: attrs) }
    }

    private func draw(_ text: String, in rect: NSRect, _ attrs: [NSAttributedString.Key: Any]) {
        withTextAlpha { text.draw(in: rect, withAttributes: attrs) }
    }

    private func strokeLine(from start: CGPoint, to end: CGPoint, color: NSColor) {
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(1)
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()
        context.restoreGState()
    }
}
