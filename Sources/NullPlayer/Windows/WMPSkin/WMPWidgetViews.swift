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
        NSColor(calibratedWhite: 0.08, alpha: 0.9).setFill(); dirtyRect.fill()
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
final class WMPEqualizerSurfaceView: NSView {
    var onAction: ((WMPTransportAction, WMPHostValue?) -> Void)?
    private let enabledButton = NSButton(checkboxWithTitle: "EQ", target: nil, action: nil)
    private var sliders: [NSSlider] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true; layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.82).cgColor
        enabledButton.target = self; enabledButton.action = #selector(toggleEnabled(_:)); addSubview(enabledButton)
        for index in 0...10 {
            let slider = NSSlider(value: 0, minValue: -12, maxValue: 12, target: self,
                                  action: #selector(changed(_:)))
            slider.isVertical = true
            slider.setAccessibilityLabel(index == 0 ? "Preamp" : "Equalizer band \(index)")
            sliders.append(slider); addSubview(slider)
        }
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        enabledButton.frame = NSRect(x: 4, y: 2, width: 42, height: 18)
        let top: CGFloat = 22, width = max(1, bounds.width / CGFloat(sliders.count))
        for (index, slider) in sliders.enumerated() {
            slider.frame = NSRect(x: CGFloat(index) * width, y: top, width: width,
                                  height: max(16, bounds.height - top - 2))
        }
    }

    func update(_ snapshot: WMPHostSnapshot) {
        enabledButton.state = snapshot.equalizer.enabled ? .on : .off
        sliders.first?.doubleValue = snapshot.equalizer.preamp
        for (slider, gain) in zip(sliders.dropFirst(), snapshot.equalizer.gains) { slider.doubleValue = gain }
    }

    @objc private func toggleEnabled(_ sender: NSButton) {
        onAction?(.setEQEnabled, .bool(sender.state == .on))
    }

    @objc private func changed(_ sender: NSSlider) {
        guard let index = sliders.firstIndex(where: { $0 === sender }) else { return }
        if index == 0 { onAction?(.setPreamp, .number(sender.doubleValue)) }
        else { onAction?(.setEQBand(index - 1), .number(sender.doubleValue)) }
    }
}

@MainActor
final class WMPEffectsSurfaceView: NSView {
    private var levels: [Float] = []
    override var isFlipped: Bool { true }

    func updateSpectrum(_ levels: [Float]) { self.levels = levels; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.04, alpha: 0.9).setFill(); dirtyRect.fill()
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

@MainActor
final class WMPVideoPlaceholderView: NSView {
    private let label = NSTextField(labelWithString: "Video surface unavailable in WMP skins")
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true; layer?.backgroundColor = NSColor.black.cgColor
        label.textColor = .secondaryLabelColor; label.alignment = .center
        label.setAccessibilityLabel("Video placeholder"); addSubview(label)
    }
    required init?(coder: NSCoder) { nil }
    override func layout() { super.layout(); label.frame = bounds.insetBy(dx: 8, dy: 8) }
}

@MainActor
final class WMPPopupSurfaceView: NSPopUpButton {
    var onAction: ((WMPTransportAction, WMPHostValue?) -> Void)?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect, pullsDown: false)
        addItems(withTitles: ["Presets", "Flat EQ", "Enable EQ", "Disable EQ"])
        target = self; action = #selector(chosen(_:))
    }
    required init?(coder: NSCoder) { nil }
    @objc private func chosen(_ sender: Any?) {
        switch indexOfSelectedItem {
        case 1: for band in 0..<10 { onAction?(.setEQBand(band), .number(0)) }; onAction?(.setPreamp, .number(0))
        case 2: onAction?(.setEQEnabled, .bool(true))
        case 3: onAction?(.setEQEnabled, .bool(false))
        default: break
        }
        selectItem(at: 0)
    }
}
