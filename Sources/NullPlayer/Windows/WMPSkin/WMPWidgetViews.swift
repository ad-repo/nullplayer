import AppKit

@MainActor
final class WMPPlaylistSurfaceView: NSView {
    var onAction: ((WMPTransportAction, WMPHostValue?) -> Void)?
    private var snapshot = WMPHostSnapshot()
    private var selectedIndex = -1
    private var firstVisibleIndex = 0
    private let rowHeight: CGFloat = 18

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func update(_ snapshot: WMPHostSnapshot) {
        self.snapshot = snapshot
        if selectedIndex < 0 { selectedIndex = snapshot.playlistIndex }
        selectedIndex = min(selectedIndex, snapshot.playlistItems.count - 1)
        needsDisplay = true
        setAccessibilityValue(selectedIndex >= 0 ? selectedIndex + 1 : 0)
    }

    override func draw(_ dirtyRect: NSRect) {
        // `bounds`, never `dirtyRect`: AppKit is free to hand a view a dirty rect larger than
        // itself — here the whole 596x468 window arrives as {{-269, -26}, {596, 468}} in this
        // view's coordinates — and a layer-backed view does not clip it (`masksToBounds` is
        // false). Filling it painted this surface's translucent wash over the entire skin.
        NSColor(calibratedWhite: 0.08, alpha: 0.9).setFill(); bounds.fill()
        let visibleRows = max(1, Int(bounds.height / rowHeight))
        for index in firstVisibleIndex..<min(snapshot.playlistItems.count, firstVisibleIndex + visibleRows) {
            let rect = NSRect(x: 0, y: CGFloat(index - firstVisibleIndex) * rowHeight,
                              width: bounds.width, height: rowHeight)
            if index == selectedIndex || index == snapshot.playlistIndex {
                (index == selectedIndex ? NSColor.controlAccentColor : NSColor.darkGray).setFill()
                rect.fill()
            }
            let item = snapshot.playlistItems[index]
            let prefix = index == snapshot.playlistIndex ? "▶ " : ""
            let artist = item.artist.isEmpty ? "" : " — \(item.artist)"
            (prefix + item.title + artist).draw(in: rect.insetBy(dx: 4, dy: 1), withAttributes: [
                .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.white])
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = firstVisibleIndex + Int(point.y / rowHeight)
        guard snapshot.playlistItems.indices.contains(index) else { return }
        selectedIndex = index; needsDisplay = true; window?.makeFirstResponder(self)
        if event.clickCount > 1 { onAction?(.playPlaylistItem(index), nil) }
    }

    override func scrollWheel(with event: NSEvent) {
        let visibleRows = max(1, Int(bounds.height / rowHeight))
        let maximum = max(0, snapshot.playlistItems.count - visibleRows)
        firstVisibleIndex = max(0, min(maximum, firstVisibleIndex + (event.scrollingDeltaY > 0 ? -1 : 1)))
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

@MainActor
final class WMPEffectsSurfaceView: NSView {
    private var levels: [Float] = []
    override var isFlipped: Bool { true }

    func updateSpectrum(_ levels: [Float]) { self.levels = levels; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        // `bounds`, never `dirtyRect`: AppKit is free to hand a view a dirty rect larger than
        // itself — here the whole 596x468 window arrives as {{-269, -26}, {596, 468}} in this
        // view's coordinates — and a layer-backed view does not clip it (`masksToBounds` is
        // false). Filling it painted this surface's translucent wash over the entire skin.
        NSColor(calibratedWhite: 0.04, alpha: 0.9).setFill(); bounds.fill()
        guard !levels.isEmpty else { return }
        let count = min(32, levels.count), width = bounds.width / CGFloat(count)
        NSColor.systemGreen.setFill()
        for index in 0..<count {
            let level = CGFloat(max(0, min(1, levels[index])))
            NSRect(x: CGFloat(index) * width, y: bounds.height * (1 - level),
                   width: max(1, width - 1), height: bounds.height * level).fill()
        }
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
