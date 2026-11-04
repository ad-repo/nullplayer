import AppKit

/// The text field a skin's quick search box types into: laid over the box in its font while it
/// types, editing that list's search in the skin's state; the skin draws the search the rest of the
/// time. One per view, made on the first search.
@MainActor
final class AIMPSkinSearchField: NSObject, NSTextFieldDelegate {
    private unowned let view: AIMPSkinMainView
    private var made: NSTextField?
    /// The list it types into.
    private var list = AIMPSkinList.playlist

    init(view: AIMPSkinMainView) {
        self.view = view
    }

    private var field: NSTextField {
        if let made { return made }
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.isHidden = true
        field.delegate = self
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        view.addSubview(field)
        made = field
        return field
    }

    /// Whether it is typing and `point` (view points) is on it: it takes its own clicks there.
    func isTyping(at point: NSPoint) -> Bool {
        guard let made, !made.isHidden else { return false }
        return made.frame.contains(point)
    }

    /// Types into `list`'s search over the box at `rect`, in skin pixels.
    func begin(_ list: AIMPSkinList, in rect: CGRect) {
        self.list = list
        let bounds = view.bounds, content = view.contentRect
        let scaleX = bounds.width / max(1, content.width), scaleY = bounds.height / max(1, content.height)
        let box = NSRect(x: (rect.minX - content.minX) * scaleX + 2, y: (rect.minY - content.minY) * scaleY,
                         width: rect.width * scaleX - 4, height: rect.height * scaleY)
        let font = view.drawnFrame?.searchFont ?? .standard
        let size = font.pointSize * view.uiScale
        field.font = NSFont(name: font.name, size: size) ?? .systemFont(ofSize: size, weight: font.bold ? .bold : .regular)
        field.textColor = NSColor(srgbRed: CGFloat(font.color >> 16 & 0xFF) / 255, green: CGFloat(font.color >> 8 & 0xFF) / 255,
                                  blue: CGFloat(font.color & 0xFF) / 255, alpha: 1)
        let height = min(box.height, field.intrinsicContentSize.height)
        field.frame = NSRect(x: box.minX, y: box.midY - height / 2, width: box.width, height: height)
        field.stringValue = view.skinState.lists.search(list)
        field.isHidden = false
        view.skinState.lists.searchEditing = list
        view.window?.makeKey()
        view.window?.makeFirstResponder(field)
    }

    func end() {
        guard let made, !made.isHidden else { return }
        made.isHidden = true
        view.skinState.lists.searchEditing = nil
        view.window?.makeFirstResponder(view)
    }

    // MARK: - NSTextFieldDelegate

    /// Each keystroke narrows the list to what holds every word, from the top.
    func controlTextDidChange(_ notification: Notification) {
        view.skinState.lists.setSearch(list, field.stringValue)
    }

    /// Return plays the playlist's first match (in the library, the table's); Escape clears the
    /// search; either ends typing.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            let search = view.skinState.lists.search(list)
            let host = view.host
            if !search.isEmpty, list == .playlist, let first = host.playlistIndices(matching: search).first {
                view.runtime?.onAction?(.playRow(first))
            } else if !search.isEmpty, list == .libraryTable, let library = host.player.library,
                      let first = library.table(view.skinState.lists.libraryGrouping, path: view.skinState.lists.libraryPath, search: search).first {
                view.runtime?.onAction?(.playLibraryTrack(library.tracks[first].id))
            }
            end()
            return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            view.skinState.lists.setSearch(list, "")
            field.stringValue = ""
            end()
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ notification: Notification) { end() }
}
