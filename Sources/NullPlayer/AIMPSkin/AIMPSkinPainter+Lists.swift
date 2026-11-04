import CoreGraphics
import CoreText
import Foundation

extension AIMPSkinPainter {
    /// NullPlayer's playlist in the skin's colours and fonts: a row per track, its number and title
    /// left, its length right; the playing row and the selected one lit. `shown` are the rows the
    /// quick search leaves, `rows` those in view (`AIMPSkinLayout.Look.playlist`).
    func drawPlaylist(_ style: AIMPSkinControl.Playlist, rows: AIMPSkinLayout.Rows, shown: [Int], in rect: CGRect) {
        // Its own background picture (GX-77's paper sheet), else its background colour.
        if let picture = image(style.picture), picture.hasPixels {
            paint(picture, in: rect)
        } else {
            canvas.fill(rect, argb: style.background)
        }
        let lists = flow.state.lists
        context.saveGState()
        context.clip(to: rect)
        for (offset, index) in rows.inView(shown).enumerated() {
            let row = host.player.playlist.rows[index]
            let line = rows.line(offset, in: rect)
            let playing = index == host.player.playlistIndex, selected = index == lists.playlistSelected
            let state: AIMPSkinControl.Playlist.Row = playing && selected ? .playingSelected : playing ? .playing : selected ? .selected : .normal
            canvas.fill(line, argb: style.fills[state])
            guard let font = style.fonts[state].map({ self.font($0) }) else { continue }
            let time = row.seconds > 0 ? String(format: "%d:%02d", row.seconds / 60, row.seconds % 60) : ""
            let timeWidth = CGFloat(time.count) * CGFloat(font.height) * 0.55 + 6
            canvas.draw(time, font: font, at: CGPoint(x: line.maxX - timeWidth, y: line.midY), centeredIn: nil, clippedTo: line)
            canvas.draw("\(index + 1). \(row.title)", font: font, at: CGPoint(x: line.minX + 3, y: line.midY), centeredIn: nil,
                 clippedTo: CGRect(x: line.minX, y: line.minY, width: max(0, line.width - timeWidth - 4), height: line.height))
        }
        context.restoreGState()
    }

    /// A library row's fill and its text colour: alternating, the chosen one lit.
    func listRow(_ style: AIMPSkinControl.Library, _ line: CGRect, index: Int, selected: Bool) -> AIMPSkinFont {
        var font = self.font(style.font)
        if selected, let fill = style.selected {
            canvas.fill(line, argb: fill)
        } else if let fill = index % 2 == 0 ? style.rows.0 : style.rows.1 {
            canvas.fill(line, argb: fill)
        }
        if selected, let text = style.selectedText { font.color = text }
        else if let text = style.rowText { font.color = text }
        return font
    }

    /// The library's group tree: "All Tracks", then each group with its count, subgroups indented
    /// under an open one; the chosen row lit. Groups open and close on the skin's `RowExpandButton`
    /// (its frames closed, then open), else on an arrow.
    func drawLibraryTree(_ style: AIMPSkinControl.Library, rows: AIMPSkinLayout.Rows, tree: [AIMPSkinLibrary.Row], in rect: CGRect) {
        canvas.fill(rect, argb: style.fill)
        let lists = flow.state.lists
        let searching = !lists.libraryTreeSearch.isEmpty
        let arrow = image(style.expandButton)
        context.saveGState()
        context.clip(to: rect)
        for (offset, row) in rows.inView(tree).enumerated() {
            let line = rows.line(offset, in: rect)
            let rowFont = listRow(style, line, index: rows.first + offset, selected: row.path == lists.libraryPath)
            let indent = line.minX + 3 + CGFloat(row.level) * 14
            if row.expandable {
                let open = searching || lists.libraryExpanded.contains(row.path)
                if let arrow, arrow.hasPixels, arrow.frameCount >= 2 {
                    let size = arrow.frameSize
                    let frame = arrow.frameCount >= 4 ? (open ? 2 : 0) : (open ? 1 : 0)
                    paint(arrow, in: CGRect(x: indent, y: (line.midY - size.height / 2).rounded(), width: size.width, height: size.height), frame: frame)
                } else {
                    canvas.draw(open ? "▾" : "▸", font: rowFont, at: CGPoint(x: indent, y: line.midY), centeredIn: nil, clippedTo: line)
                }
            }
            let count = String(row.count)
            let countWidth = CGFloat(count.count) * CGFloat(rowFont.height) * 0.55 + 6
            canvas.draw(count, font: rowFont, at: CGPoint(x: line.maxX - countWidth, y: line.midY), centeredIn: nil, clippedTo: line)
            canvas.draw(row.name, font: rowFont, at: CGPoint(x: indent + 13, y: line.midY), centeredIn: nil,
                 clippedTo: CGRect(x: line.minX, y: line.minY, width: max(0, line.width - countWidth - 4), height: line.height))
        }
        context.restoreGState()
    }

    /// The library table's columns across `width`: number, title, artist, album, length.
    static func libraryColumns(_ width: CGFloat) -> [(title: String, x: CGFloat, width: CGFloat)] {
        let number: CGFloat = 30, length: CGFloat = 50
        let rest = max(0, width - number - length)
        let widths = [number, (rest * 0.42).rounded(), (rest * 0.29).rounded(), rest - (rest * 0.42).rounded() - (rest * 0.29).rounded(), length]
        var x: CGFloat = 0
        return zip(["#", "Title", "Artist", "Album", "Length"], widths).map { title, w in
            defer { x += w }
            return (title, x, w)
        }
    }

    /// The library's table: a header in the skin's `ColumnHeader` picture and font, then the chosen
    /// group's tracks, alternating, the chosen one lit.
    func drawLibraryTable(_ style: AIMPSkinControl.Library, library: AIMPSkinLibrary, rows: AIMPSkinLayout.Rows, table: [Int],
                          header: CGFloat, in rect: CGRect) {
        canvas.fill(rect, argb: style.fill)
        let headerFont = font(style.headerFont)
        let headerImage = image(style.header)
        let columns = Self.libraryColumns(rect.width)
        for column in columns {
            let cell = CGRect(x: rect.minX + column.x, y: rect.minY, width: column.width, height: header)
            paint(headerImage, in: cell)
            canvas.draw(column.title, font: headerFont, at: CGPoint(x: cell.minX + 4, y: cell.midY), centeredIn: nil, clippedTo: cell)
        }
        let body = CGRect(x: rect.minX, y: rect.minY + header, width: rect.width, height: max(0, rect.height - header))
        context.saveGState()
        context.clip(to: body)
        for (offset, index) in rows.inView(table).enumerated() {
            let track = library.tracks[index]
            let line = rows.line(offset, in: body)
            let rowFont = listRow(style, line, index: rows.first + offset, selected: track.id == flow.state.lists.librarySelected)
            let number = track.trackNumber ?? 0, seconds = AIMPSkinLibrary.seconds(track)
            let cells = [number > 0 ? String(number) : "", track.title, track.artist ?? "", track.album ?? "",
                         seconds > 0 ? String(format: "%d:%02d", seconds / 60, seconds % 60) : ""]
            for (column, text) in zip(columns, cells) where !text.isEmpty {
                let cell = CGRect(x: line.minX + column.x, y: line.minY, width: column.width - 4, height: line.height)
                canvas.draw(text, font: rowFont, at: CGPoint(x: cell.minX + 4, y: cell.midY), centeredIn: nil, clippedTo: cell)
            }
        }
        context.restoreGState()
    }
}
