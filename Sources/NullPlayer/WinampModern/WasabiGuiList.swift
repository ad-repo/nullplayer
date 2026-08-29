import Foundation

/// The `<list>` control's contents, held on the object itself.
///
/// Wasabi's list is a native child window that a script fills — Big Bento's playlist search puts its
/// hits in one (`deleteAllItems` / `addItem` per match / `scrollToItem`), then reads the row the user
/// picked back out with `getFirstItemSelected` and `getItemLabel`. Nothing about it is in the markup
/// beyond the box, so the rows have to live somewhere of ours.
///
/// They live in the object's own attributes, the way every other piece of script-written state does
/// (`WasabiTextMetrics.scriptTextKey`, the scroll percentage): the renderer draws from the graph and
/// the runtime writes to it, so a single home means no second copy to keep in step, and a skin that
/// rebuilds the list gets a repaint from the same mutation notice as any other attribute write.
enum WasabiGuiList {

    /// The rows, joined by a separator no track title can contain (U+0001 is not text).
    static let itemsKey = "nullplayer.script.listitems"
    /// The selected rows, as comma-separated indices. Wasabi lists are multi-select and Big Bento's
    /// declares `multiselect="1"`, so this is a set rather than one index.
    static let selectionKey = "nullplayer.script.listselection"
    /// The first visible row — what `scrollToItem` moves.
    static let scrollKey = "nullplayer.script.listscroll"

    /// The per-row icon ids, in the same order and joined by the same separator as the rows. A row
    /// with no icon holds an empty entry, so the two lists stay index-aligned however a script fills
    /// them: Big Bento Modern's Web Reader sets the label, the comment and the icon of each row from
    /// three independent branches of one loop over the element's attributes.
    static let iconsKey = "nullplayer.script.listicons"
    /// Whether the icon column is drawn, written by `setShowIcons`.
    static let showIconsKey = "nullplayer.script.listshowicons"

    private static let separator = "\u{1}"
    /// Columns *within* one row. A Wasabi list is a report view — Big Bento Modern's provider
    /// drop-down declares `numcolumns="2"` and fills the second with `setSubItem(row, 1, …)` — so a
    /// row is a list of cells rather than a string. A row written as a plain `addItem` has one cell,
    /// which is exactly what every earlier caller wrote and reads back.
    private static let columnSeparator = "\u{2}"

    /// A cap on what a script can put in one list. The rows are a string attribute, and a runaway
    /// `addItem` loop in a skin must not be able to grow it without bound.
    static let maximumItems = 4096

    static func isList(_ object: WasabiObject) -> Bool {
        object.typeName.lowercased().components(separatedBy: ":").last == "list"
    }

    static func items(of object: WasabiObject) -> [String] {
        guard let raw = object.attributes[itemsKey], !raw.isEmpty else { return [] }
        return raw.components(separatedBy: separator)
    }

    static func setItems(_ items: [String], on object: WasabiObject) {
        _ = object.setAttribute(itemsKey, value: items.joined(separator: separator))
    }

    /// One row's cells, left to right.
    static func columns(ofRow row: Int, on object: WasabiObject) -> [String] {
        let items = items(of: object)
        guard items.indices.contains(row) else { return [] }
        return items[row].components(separatedBy: columnSeparator)
    }

    static func setColumn(_ column: Int, ofRow row: Int, to value: String, on object: WasabiObject) {
        guard column >= 0, column < maximumColumns else { return }
        var items = items(of: object)
        guard items.indices.contains(row) else { return }
        var cells = items[row].components(separatedBy: columnSeparator)
        while cells.count <= column { cells.append("") }
        cells[column] = value.replacingOccurrences(of: columnSeparator, with: " ")
            .replacingOccurrences(of: separator, with: " ")
        items[row] = cells.joined(separator: columnSeparator)
        setItems(items, on: object)
    }

    static func icons(of object: WasabiObject) -> [String] {
        guard let raw = object.attributes[iconsKey], !raw.isEmpty else { return [] }
        return raw.components(separatedBy: separator)
    }

    static func setIcon(_ icon: String, ofRow row: Int, on object: WasabiObject) {
        guard row >= 0, row < maximumItems else { return }
        var icons = icons(of: object)
        while icons.count <= row { icons.append("") }
        icons[row] = icon.replacingOccurrences(of: separator, with: " ")
        _ = object.setAttribute(iconsKey, value: icons.joined(separator: separator))
    }

    static func icon(ofRow row: Int, on object: WasabiObject) -> String? {
        let icons = icons(of: object)
        guard icons.indices.contains(row), !icons[row].isEmpty else { return nil }
        return icons[row]
    }

    static func showsIcons(_ object: WasabiObject) -> Bool {
        (object.attributes[showIconsKey].map { $0 != "0" && !$0.isEmpty } ?? false)
    }

    /// A cap on the cells one row may hold, for the same reason `maximumItems` exists.
    static let maximumColumns = 16

    static func selection(of object: WasabiObject) -> [Int] {
        (object.attributes[selectionKey] ?? "").split(separator: ",").compactMap { Int($0) }.sorted()
    }

    static func setSelection(_ rows: [Int], on object: WasabiObject) {
        _ = object.setAttribute(selectionKey,
                                value: rows.sorted().map(String.init).joined(separator: ","))
    }

    static func scrollOffset(of object: WasabiObject) -> Int {
        max(0, Int(object.attributes[scrollKey] ?? "") ?? 0)
    }

    static func setScrollOffset(_ row: Int, on object: WasabiObject) {
        _ = object.setAttribute(scrollKey, value: String(max(0, row)))
    }

    /// Row height in skin pixels: the em the row actually draws at, plus Wasabi's 3px of leading.
    ///
    /// Not the `fontsize` cell — `fontsize` is a GDI cell height and the em inside it is smaller
    /// (`pixelHeightToPointSize`). The skin sizes the window around its *own* expectation of this, so
    /// the number has to match: Big Bento asks its search popup for 118px to hold four hits over a
    /// 36px banner, i.e. 20.5px a row at the `fontsize="22"` its script sets on the list — and a
    /// fontsize-based row of 24 fitted only three, cropping the last hit every time. The em is
    /// floored before the leading is added, because a row that rounds *up* is the one that costs the
    /// list its last visible line: 21 left the fourth hit one pixel outside an 82px box.
    static func rowHeight(of object: WasabiObject) -> Double {
        let em = WasabiTextMetrics.pixelHeight(of: object) * WasabiTextMetrics.pixelHeightToPointSize
        return max(8, em.rounded(.down) + 3)
    }
}
