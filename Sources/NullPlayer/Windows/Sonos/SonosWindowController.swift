import AppKit

final class SonosWindowController: AuxiliarySurfaceWindowController {
    init() {
        super.init(surface: SonosWindowView(frame: NSRect(x: 0, y: 0, width: 360, height: 260)),
                   title: "Sonos Rooms", size: NSSize(width: 360, height: 260), minSize: NSSize(width: 250, height: 160),
                   accessibilityID: "SonosRoomsWindow", accessibilityLabel: "Sonos rooms and volume",
                   close: { WindowManager.shared.toggleSonos() })
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Shared room controls. Skin-specific chrome is supplied by AuxiliaryWindowChrome.
final class SonosWindowView: AuxiliarySurfaceView {
    private var refreshTimer: Timer?
    private var pollTask: Task<Void, Never>?
    private let scroll = NSScrollView()
    private let document = SonosRoomDocumentView()
    private let status = NSTextField(labelWithString: "Choose rooms to cast to")
    private let castButton = NSButton(title: "Start Casting", target: nil, action: nil)
    private let refreshButton = NSButton(title: "Refresh", target: nil, action: nil)
    private var rows: [String: SonosRoomRow] = [:]
    private var roomIDs: [String] = []
    private var busy = false
    private var message: String?
    private let mixer: SonosRoomMixer
    private let roomSource: () -> [UPnPManager.SonosRoomSummary]

    convenience init(frame: NSRect) {
        self.init(frame: frame, mixer: .shared, rooms: { CastManager.shared.sonosRooms })
    }

    init(frame: NSRect, mixer: SonosRoomMixer, rooms: @escaping () -> [UPnPManager.SonosRoomSummary]) {
        self.mixer = mixer
        self.roomSource = rooms
        super.init(frame: frame, chromeTitle: "SONOS")
        needsLayout = true
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = document
        addSubview(scroll)
        for view in [status, castButton, refreshButton] { addSubview(view) }
        status.font = .systemFont(ofSize: 10)
        status.lineBreakMode = .byTruncatingTail
        castButton.bezelStyle = .rounded
        refreshButton.bezelStyle = .rounded
        castButton.target = self
        castButton.action = #selector(castClicked)
        refreshButton.target = self
        refreshButton.action = #selector(refreshClicked)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit {
        refreshTimer?.invalidate()
        pollTask?.cancel()
    }

    override func layout() {
        super.layout()
        let area = contentArea
        let scale = controlScale
        let padding: CGFloat = 10 * scale
        let width = max(0, area.width - padding * 2)
        status.frame = NSRect(x: area.minX + padding, y: area.maxY - 24 * scale, width: width, height: 15 * scale)
        refreshButton.frame = NSRect(x: area.minX + padding, y: area.minY + 7 * scale, width: 76 * scale, height: 26 * scale)
        castButton.frame = NSRect(x: area.maxX - padding - 116 * scale, y: area.minY + 7 * scale, width: 116 * scale, height: 26 * scale)
        for control in [status, refreshButton, castButton] {
            control.setBoundsSize(NSSize(width: control.frame.width / scale, height: control.frame.height / scale))
        }
        scroll.frame = NSRect(x: area.minX, y: area.minY + 40 * scale, width: area.width,
                              height: max(0, area.height - 70 * scale))
        let rowWidth = scroll.contentSize.width
        document.frame = NSRect(x: 0, y: 0, width: rowWidth, height: CGFloat(roomIDs.count) * 65 * scale)
        for (index, id) in roomIDs.enumerated() {
            rows[id]?.frame = NSRect(x: 0, y: CGFloat(index) * 65 * scale, width: rowWidth, height: 65 * scale)
            rows[id]?.setBoundsSize(NSSize(width: rowWidth / scale, height: 65))
            rows[id]?.needsLayout = true
        }
        status.textColor = textColor.withAlphaComponent(0.8)
        finishLayout()
    }

    override func refresh() {
        super.refresh()
        let tint = textColor
        refreshButton.contentTintColor = tint
        castButton.contentTintColor = tint
        let manager = CastManager.shared
        let rooms = roomSource()
        let ids = rooms.map(\.id)
        if ids != roomIDs {
            for row in rows.values { row.removeFromSuperview() }
            rows.removeAll()
            roomIDs = ids
            for room in rooms {
                let row = SonosRoomRow(id: room.id, mixer: mixer)
                row.onSelection = { [weak self] selected in
                    guard let self else { return }
                    self.performOperation {
                        try await self.mixer.selectRoom(room.id, selected: selected)
                    }
                }
                rows[room.id] = row
                document.addSubview(row)
            }
            needsLayout = true
        }
        let casting = manager.activeSession?.device.type == .sonos
        let selected = (casting ? Set(manager.getRoomsInActiveCastGroup()) : manager.selectedSonosRooms).intersection(ids)
        let changing = busy || mixer.changingRooms
        for room in rooms {
            rows[room.id]?.update(name: room.name, selected: selected.contains(room.id),
                                  casting: casting, enabled: !changing, color: tint)
        }
        castButton.title = casting ? "Stop Casting" : "Start Casting"
        castButton.isEnabled = !changing && (casting || (!selected.isEmpty && WindowManager.shared.audioEngine.currentTrack != nil))
        refreshButton.isEnabled = !changing
        if let message { status.stringValue = message }
        else if changing { status.stringValue = "Updating rooms…" }
        else if rooms.isEmpty { status.stringValue = "No Sonos rooms found. Try Refresh." }
        else if casting { status.stringValue = "Casting to \(selected.count) of \(rooms.count) rooms" }
        else if WindowManager.shared.audioEngine.currentTrack == nil { status.stringValue = "Choose rooms, then load music to cast." }
        else { status.stringValue = "\(selected.count) of \(rooms.count) rooms selected" }
        status.toolTip = status.stringValue
        needsDisplay = true
    }

    private func performOperation(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        message = nil
        refresh()
        Task { @MainActor [weak self] in
            do { try await operation() }
            catch { self?.message = error.localizedDescription }
            self?.busy = false
            self?.refresh()
        }
    }

    @objc private func castClicked() {
        performOperation {
            if CastManager.shared.activeSession?.device.type == .sonos {
                await CastManager.shared.stopCasting()
            } else { try await self.mixer.startCasting() }
        }
    }

    @objc private func refreshClicked() {
        CastManager.shared.refreshDevices()
        performOperation {
            await CastManager.shared.refreshSonosGroups()
            await self.mixer.refreshVolumes()
        }
    }

    override func resume() {
        super.resume()
        guard refreshTimer == nil else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, self.window?.isVisible == true else { return }
            self.refresh()
        }
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard self?.window != nil else { break }
                await self?.mixer.refreshVolumes()
                self?.refresh()
                do { try await Task.sleep(nanoseconds: 4_000_000_000) } catch { break }
            }
        }
    }
    override func suspend() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        pollTask?.cancel()
        pollTask = nil
    }
}

private final class SonosRoomDocumentView: NSView {
    override var isFlipped: Bool { true }
}

private final class SonosRoomRow: NSView {
    let id: String
    private let mixer: SonosRoomMixer
    var onSelection: ((Bool) -> Void)?
    private let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let subtitle = NSTextField(labelWithString: "")
    private let slider = NSSlider(value: 0, minValue: 0, maxValue: 100, target: nil, action: nil)
    private let value = NSTextField(labelWithString: "—")
    private var accent = NSColor.controlAccentColor
    private var selected = false
    override var isFlipped: Bool { true }

    init(id: String, mixer: SonosRoomMixer) {
        self.id = id
        self.mixer = mixer
        super.init(frame: .zero)
        for view in [checkbox, subtitle, slider, value] { addSubview(view) }
        checkbox.target = self
        checkbox.action = #selector(selectChanged)
        checkbox.font = .systemFont(ofSize: 12, weight: .semibold)
        checkbox.cell?.lineBreakMode = .byTruncatingTail
        subtitle.font = .systemFont(ofSize: 9)
        subtitle.lineBreakMode = .byTruncatingTail
        value.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        value.alignment = .right
        slider.isContinuous = true
        slider.cell = SonosVolumeSliderCell()
        slider.minValue = 0
        slider.maxValue = 100
        slider.controlSize = .small
        slider.target = self
        slider.action = #selector(volumeChanged)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        checkbox.frame = NSRect(x: 10, y: 6, width: max(0, bounds.width - 64), height: 20)
        value.frame = NSRect(x: bounds.width - 47, y: 10, width: 34, height: 15)
        subtitle.frame = NSRect(x: 30, y: 27, width: max(0, bounds.width - 40), height: 12)
        slider.frame = NSRect(x: 28, y: 40, width: max(0, bounds.width - 40), height: 18)
    }
    func update(name: String, selected: Bool, casting: Bool, enabled: Bool, color: NSColor) {
        self.selected = selected
        accent = color
        (slider.cell as? SonosVolumeSliderCell)?.accent = color
        checkbox.title = name
        checkbox.contentTintColor = color
        checkbox.state = selected ? .on : .off
        checkbox.isEnabled = enabled
        value.textColor = color
        subtitle.textColor = color.withAlphaComponent(0.65)
        if let volume = mixer.volumes[id] {
            slider.integerValue = volume
            value.stringValue = "\(volume)"
            slider.isEnabled = true
        } else {
            value.stringValue = "—"
            slider.isEnabled = false
        }
        subtitle.stringValue = mixer.errors[id] != nil ? "Volume unavailable · Refresh to retry" :
            (selected ? (casting ? "Receiving audio" : "Ready to cast") : "Not selected")
        subtitle.toolTip = mixer.errors[id]
        slider.setAccessibilityLabel("\(name) volume")
        slider.toolTip = "\(name) volume (0–100)"
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        if selected { accent.withAlphaComponent(0.08).setFill(); bounds.fill() }
        accent.withAlphaComponent(0.13).setFill()
        NSRect(x: 10, y: bounds.height - 1, width: max(0, bounds.width - 20), height: 1).fill()
    }
    @objc private func selectChanged() { onSelection?(checkbox.state == .on) }
    @objc private func volumeChanged() {
        value.stringValue = "\(slider.integerValue)"
        mixer.setVolume(slider.integerValue, room: id)
    }
}

private final class SonosVolumeSliderCell: NSSliderCell {
    var accent: NSColor = .controlAccentColor
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let track = NSRect(x: rect.minX, y: rect.midY - 1.5, width: rect.width, height: 3)
        accent.withAlphaComponent(0.2).setFill()
        NSBezierPath(roundedRect: track, xRadius: 1.5, yRadius: 1.5).fill()
        guard isEnabled else { return }
        let fraction = CGFloat((doubleValue - minValue) / max(1, maxValue - minValue))
        accent.setFill()
        NSBezierPath(roundedRect: NSRect(x: track.minX, y: track.minY, width: track.width * fraction, height: track.height),
                     xRadius: 1.5, yRadius: 1.5).fill()
    }
    override func drawKnob(_ knobRect: NSRect) {
        (isEnabled ? accent : accent.withAlphaComponent(0.3)).setFill()
        let knob = NSRect(x: knobRect.midX - 5, y: knobRect.midY - 5, width: 10, height: 10)
        NSBezierPath(ovalIn: knob).fill()
    }
}
