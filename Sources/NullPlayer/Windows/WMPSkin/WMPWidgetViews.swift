import AppKit

@MainActor
final class WMPPlaylistSurfaceView: NSView {
    var onAction: ((WMPTransportAction, WMPHostValue?) -> Void)?
    private var snapshot = WMPHostSnapshot()
    private var selectedIndex = -1
    private var lastPlayingIndex = -1
    /// The row drawn at the top. `private(set)` rather than `private` so the W246 scrolling tests
    /// can read the position back: the alternative is asserting on rendered text, which measures
    /// the font rather than the scroll.
    private(set) var firstVisibleIndex = 0
    /// Points of precise scrolling delta not yet worth a whole row.
    private var scrollRemainder: CGFloat = 0
    private let rowHeight: CGFloat = 18
    private var style = WMPSurfacePalette(viewID: "").surfaceStyle

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func update(_ snapshot: WMPHostSnapshot) {
        // What this surface actually draws, before the update: the rows, the play marker, the
        // highlight and the scroll position. A host refresh arrives with every clock tick and
        // behind every present, and marking the view dirty unconditionally redrew the whole list
        // 11.8 times a second with all four of them unchanged (W224). Nothing else in `snapshot`
        // reaches `draw`.
        let drawnItems = self.snapshot.playlistItems
        let drawnPlaying = self.snapshot.playlistIndex
        let drawnSelection = selectedIndex
        let drawnScroll = firstVisibleIndex
        self.snapshot = snapshot
        // The highlight follows the track that is playing. Seeding it once and leaving it there
        // left every WMP skin's playlist highlighting row 1 for the whole session while the play
        // marker walked down the list on its own — reported against `nvidia`, but this surface is
        // shared by every skin that declares a `<PLAYLIST>`, so it was all of them. A click or an
        // arrow key still moves the highlight; the next track change takes it back, the way WMP's
        // own playlist does.
        var trackChanged = false
        if snapshot.playlistIndex != lastPlayingIndex {
            lastPlayingIndex = snapshot.playlistIndex
            if snapshot.playlistItems.indices.contains(snapshot.playlistIndex) {
                selectedIndex = snapshot.playlistIndex
                trackChanged = true
            }
        }
        if selectedIndex < 0 { selectedIndex = snapshot.playlistIndex }
        selectedIndex = min(selectedIndex, snapshot.playlistItems.count - 1)
        // **Scrolling to the selection is an event, not a state (W246).** A host refresh arrives
        // ~12 times a second whether or not anything moved, and pulling the scroll position back
        // onto `selectedIndex` from every one of them clamped `firstVisibleIndex` into
        // `selected - visibleRows + 1 ... selected` permanently: a wheel gesture moved the list and
        // the next refresh put it back within ~85 ms. Measured live on `Xbox Live Skin` with a
        // 200-row playlist — 70 wheel events down reached row 19 and stopped, 40 back up reached
        // row 2 and stopped, because the playing row was pinned to the bottom and then the top of
        // an 11-row window. The list could not be scrolled at all beyond one page around the
        // current track. A refresh that changes nothing now only *clamps* the scroll position into
        // the list; the track change is what still scrolls it, the way WMP's own playlist does.
        if trackChanged { scrollSelectionIntoView() } else { clampScroll() }
        if drawnItems != snapshot.playlistItems || drawnPlaying != snapshot.playlistIndex
            || drawnSelection != selectedIndex || drawnScroll != firstVisibleIndex {
            needsDisplay = true
        }
        setAccessibilityValue(selectedIndex >= 0 ? selectedIndex + 1 : 0)
    }

    /// The playlist is a native surface, but its colours are authored by the WMP skin.  Keeping
    /// that palette here avoids the generic black AppKit list appearing inside a coloured skin.
    func apply(style: SkinnedSurfaceStyle) {
        guard self.style != style else { return }
        self.style = style
        needsDisplay = true
    }

    /// Pull `firstVisibleIndex` the shortest distance that puts `selectedIndex` on screen, and
    /// clamp it when the playlist shrinks under it.
    private func scrollSelectionIntoView() {
        let visibleRows = max(1, Int(bounds.height / rowHeight))
        if selectedIndex >= 0 {
            firstVisibleIndex = max(firstVisibleIndex, selectedIndex - visibleRows + 1)
            firstVisibleIndex = min(firstVisibleIndex, selectedIndex)
        }
        clampScroll()
    }

    /// Keep the scroll position inside the list without moving it otherwise — the half of
    /// `scrollSelectionIntoView` that a refresh which changed nothing is still entitled to run.
    private func clampScroll() {
        let visibleRows = max(1, Int(bounds.height / rowHeight))
        let maximum = max(0, snapshot.playlistItems.count - visibleRows)
        firstVisibleIndex = max(0, min(maximum, firstVisibleIndex))
    }

    override func draw(_ dirtyRect: NSRect) {
        // `bounds`, never `dirtyRect`: AppKit is free to hand a view a dirty rect larger than
        // itself — here the whole 596x468 window arrives as {{-269, -26}, {596, 468}} in this
        // view's coordinates — and a layer-backed view does not clip it (`masksToBounds` is
        // false). Filling it painted this surface's translucent wash over the entire skin.
        #if DEBUG
        wmpWidgetTrace("playlist draw rows=\(snapshot.playlistItems.count) bounds=\(bounds.size) selected=\(selectedIndex)")
        #endif
        style.background.setFill(); bounds.fill()
        let visibleRows = max(1, Int(bounds.height / rowHeight))
        for index in firstVisibleIndex..<min(snapshot.playlistItems.count, firstVisibleIndex + visibleRows) {
            let rect = NSRect(x: 0, y: CGFloat(index - firstVisibleIndex) * rowHeight,
                              width: bounds.width, height: rowHeight)
            if index == selectedIndex || index == snapshot.playlistIndex {
                (index == selectedIndex ? style.selectionBackground : style.background).setFill()
                rect.fill()
            }
            let item = snapshot.playlistItems[index]
            let prefix = index == snapshot.playlistIndex ? "▶ " : ""
            let artist = item.artist.isEmpty ? "" : " — \(item.artist)"
            (prefix + item.title + artist).draw(in: rect.insetBy(dx: 4, dy: 1), withAttributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: index == selectedIndex ? style.selectionText :
                    (index == snapshot.playlistIndex ? style.currentText : style.text)])
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = firstVisibleIndex + Int(point.y / rowHeight)
        guard snapshot.playlistItems.indices.contains(index) else { return }
        selectedIndex = index; needsDisplay = true; window?.makeFirstResponder(self)
        if event.clickCount > 1 { onAction?(.playPlaylistItem(index), nil) }
    }

    /// A wheel event carries a distance, and this surface used to read only its sign (W246): every
    /// event moved the list by exactly one row, so a trackpad flick that delivers hundreds of
    /// points of precise delta moved a 200-row playlist one row, and reaching its end took one
    /// event per row. Precise deltas accumulate in points — a fractional remainder is kept so slow
    /// scrolling is not rounded away to nothing — and line deltas move a row each, carrying the
    /// system's own wheel acceleration with them.
    override func scrollWheel(with event: NSEvent) {
        let rows: Int
        if event.hasPreciseScrollingDeltas {
            scrollRemainder -= event.scrollingDeltaY
            rows = Int((scrollRemainder / rowHeight).rounded(.towardZero))
            scrollRemainder -= CGFloat(rows) * rowHeight
        } else {
            scrollRemainder = 0
            rows = -Int(event.scrollingDeltaY.rounded(event.scrollingDeltaY < 0 ? .down : .up))
        }
        guard rows != 0 else { return }
        firstVisibleIndex += rows
        clampScroll()
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.option), selectedIndex >= 0, [125, 126].contains(event.keyCode) {
            let destination = max(0, min(snapshot.playlistItems.count - 1,
                                         selectedIndex + (event.keyCode == 125 ? 1 : -1)))
            if destination != selectedIndex {
                onAction?(.movePlaylistItem(selectedIndex, destination), nil); selectedIndex = destination
            }
            return
        }
        switch event.keyCode {
        case 125: selectedIndex = min(snapshot.playlistItems.count - 1, selectedIndex + 1)
        case 126: selectedIndex = max(0, selectedIndex - 1)
        case 36, 76: if selectedIndex >= 0 { onAction?(.playPlaylistItem(selectedIndex), nil) }
        case 51, 117: if selectedIndex >= 0 { onAction?(.removePlaylistItem(selectedIndex), nil) }
        default: super.keyDown(with: event); return
        }
        scrollSelectionIntoView()
        needsDisplay = true
    }
}

@MainActor
final class WMPDropdownPlaylistSurfaceView: NSPopUpButton {
    var onAction: ((WMPTransportAction, WMPHostValue?) -> Void)?

    func update(_ snapshot: WMPHostSnapshot) {
        removeAllItems()
        addItems(withTitles: snapshot.playlistItems.map { $0.artist.isEmpty ? $0.title : "\($0.title) — \($0.artist)" })
        if snapshot.playlistItems.indices.contains(snapshot.playlistIndex) { selectItem(at: snapshot.playlistIndex) }
        target = self; action = #selector(selected(_:))
    }

    @objc private func selected(_ sender: Any?) {
        guard indexOfSelectedItem >= 0 else { return }
        onAction?(.playPlaylistItem(indexOfSelectedItem), nil)
    }
}

/// A `<POPUP>`, which in this corpus means one thing: an equaliser preset menu.
///
/// All four archives that author one do the same thing — `popupPreset.appendItem(...)` in an
/// `onLoad` fills it, and `selectedItem_onchange="eq.currentPreset = popupPreset.selectedItem"`
/// applies the choice. So the items come from the skin's own script, and the fallback when a skin
/// has not filled it yet is the engine's real preset list rather than an invented menu: the four
/// hardcoded entries that used to be here ("Presets", "Flat EQ", "Enable EQ", "Disable EQ") are in
/// no skin's markup and in no skin's script.
@MainActor
final class WMPPopupSurfaceView: NSPopUpButton {
    var onSelect: ((Int, String) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect, pullsDown: false)
        target = self; action = #selector(chosen(_:))
        update(items: [])
    }

    required init?(coder: NSCoder) { nil }

    func update(items: [String]) {
        let titles = items.isEmpty ? EQPreset.allPresets.map(\.name) : items
        guard titles != itemTitles else { return }
        removeAllItems()
        addItems(withTitles: titles)
    }

    @objc private func chosen(_ sender: Any?) {
        guard indexOfSelectedItem >= 0, let title = titleOfSelectedItem else { return }
        onSelect?(indexOfSelectedItem, title)
    }
}

/// An `<EDITBOX>`. Nine of the corpus's ten are `plSearchEdit` — the playlist search field whose
/// `onKeyUp` runs the skin's own `searchMediaLb()` — so what it owes the skin is a real text field
/// with the skin's own colours and face, and a `value` its script can read back.
@MainActor
final class WMPEditBoxSurfaceView: NSTextField {
    var onEdit: ((String) -> Void)?

    init() {
        super.init(frame: .zero)
        isBordered = false
        isBezeled = false
        drawsBackground = true
        focusRingType = .none
        target = self
        action = #selector(committed(_:))
        delegate = self
    }

    required init?(coder: NSCoder) { nil }

    func apply(background: NSColor?, foreground: NSColor?, font: NSFont?) {
        if let background { backgroundColor = background }
        if let foreground { textColor = foreground }
        if let font { self.font = font }
    }

    @objc private func committed(_ sender: Any?) { onEdit?(stringValue) }
}

extension WMPEditBoxSurfaceView: NSTextFieldDelegate {
    // `onKeyUp` is what the corpus binds, so the skin expects a callback per keystroke rather than
    // only on Return.
    func controlTextDidChange(_ notification: Notification) { onEdit?(stringValue) }
}

/// A `<LISTBOX>`. Sixteen uses across eight skins, and every one is a playlist chooser
/// (`plListBox1`/`plListBox2`) that the skin's own script fills by walking WMP's media collection.
/// The control is real and its selection reaches the skin; the rows are whatever the script has
/// appended, which stays empty until `player.mediaCollection` can answer — W66, and deliberately
/// not faked with rows this player invented.
@MainActor
final class WMPListBoxSurfaceView: NSView {
    var onSelect: ((Int) -> Void)?
    private var items: [String] = []
    private var selected = -1
    private let rowHeight: CGFloat = 14

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    var backgroundFill = NSColor(calibratedWhite: 1, alpha: 1)
    var textColor = NSColor.black

    func update(items: [String]) {
        guard items != self.items else { return }
        self.items = items
        selected = min(selected, items.count - 1)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // `bounds`, never `dirtyRect` — see WMPPlaylistSurfaceView.
        backgroundFill.setFill(); bounds.fill()
        for (index, item) in items.enumerated() {
            let rect = NSRect(x: 0, y: CGFloat(index) * rowHeight, width: bounds.width, height: rowHeight)
            guard rect.minY < bounds.height else { break }
            if index == selected { NSColor.selectedContentBackgroundColor.setFill(); rect.fill() }
            item.draw(in: rect.insetBy(dx: 3, dy: 0), withAttributes: [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: index == selected ? NSColor.white : textColor])
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = Int(point.y / rowHeight)
        guard items.indices.contains(index) else { return }
        selected = index; needsDisplay = true
        window?.makeFirstResponder(self)
        onSelect?(index)
    }
}
