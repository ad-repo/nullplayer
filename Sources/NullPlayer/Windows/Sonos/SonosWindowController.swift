import AppKit

final class SonosWindowController: NSWindowController, ModeDependentWindow, NSWindowDelegate {
    private(set) var mixerView: SonosWindowView!
    private var observers: [NSObjectProtocol] = []
    private(set) var wasDockedWhenHidden = false

    convenience init() {
        let window = BorderlessWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 260),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
        self.init(window: window)
        window.title = "Sonos Rooms"
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.minSize = NSSize(width: 250, height: 160)
        window.allowedResizeEdges = [.bottom, .left, .right]
        window.collectionBehavior = [.managed, .fullScreenPrimary]
        window.delegate = self
        window.setAccessibilityIdentifier("SonosRoomsWindow")
        window.setAccessibilityLabel("Sonos rooms and volume")
        mixerView = SonosWindowView(frame: NSRect(origin: .zero, size: window.frame.size))
        mixerView.autoresizingMask = [.width, .height]
        window.contentView = mixerView
        for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                     NSWindow.didDeminiaturizeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                guard let self, let window = self.window else { return }
                if window.isVisible, !window.isMiniaturized, window.occlusionState.contains(.visible) {
                    self.mixerView.resume()
                } else { self.mixerView.suspend() }
            })
        }
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        mixerView.needsLayout = true
        mixerView.layoutSubtreeIfNeeded()
        mixerView.refresh()
        mixerView.resume()
    }

    func prepareForUITeardown() {
        if let window, window.isVisible { wasDockedWhenHidden = WindowManager.shared.isWindowDocked(window) }
        mixerView.suspend()
    }

    func skinDidChange() { mixerView.needsLayout = true; mixerView.needsDisplay = true }

    func windowWillClose(_ notification: Notification) {
        if let window { WindowManager.shared.handleCenterStackWindowWillClose(window) }
        prepareForUITeardown()
        WindowManager.shared.notifyMainWindowVisibilityChanged()
    }

    func windowDidResize(_ notification: Notification) {
        mixerView.needsLayout = true
        WindowManager.shared.postWindowLayoutDidChange()
    }

    func windowDidMove(_ notification: Notification) {
        guard let window else { return }
        let origin = WindowManager.shared.windowWillMove(window, to: window.frame.origin)
        WindowManager.shared.applySnappedPosition(window, to: origin)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        mixerView.needsDisplay = true
        WindowManager.shared.bringAllWindowsToFront(keepingWindowOnTop: window)
    }

    func windowDidResignKey(_ notification: Notification) { mixerView.needsDisplay = true }
}

/// Shared room controls. Skin-specific chrome is supplied by SonosWindowChrome.
final class SonosWindowView: NSView {
    private var refreshTimer: Timer?
    private var pollTask: Task<Void, Never>?
    private var hostedContext: WinampModernHostedSurfaceContext?
    private var hostedDrag = WinampModernHostedWindowDrag()
    private var hostedStyle: WinampModernSurfaceStyle?
    private let scroll = NSScrollView()
    private let document = SonosRoomDocumentView()
    private let status = NSTextField(labelWithString: "Choose rooms to cast to")
    private let castButton = NSButton(title: "Start Casting", target: nil, action: nil)
    private let refreshButton = NSButton(title: "Refresh", target: nil, action: nil)
    private var rows: [String: SonosRoomRow] = [:]
    private var roomIDs: [String] = []
    private var busy = false
    private var message: String?
    private var dragStart: NSPoint?
    private var closePressed = false
    private let mixer: SonosRoomMixer
    private let roomSource: () -> [UPnPManager.SonosRoomSummary]
    private var controlScale: CGFloat { WindowManager.shared.uiScaleLevel.scaleFactor }
    private var chrome: SonosWindowChrome { SonosWindowChrome(window: window) }

    override convenience init(frame: NSRect) {
        self.init(frame: frame, mixer: .shared, rooms: { CastManager.shared.sonosRooms })
    }

    init(frame: NSRect, mixer: SonosRoomMixer, rooms: @escaping () -> [UPnPManager.SonosRoomSummary]) {
        self.mixer = mixer
        self.roomSource = rooms
        super.init(frame: frame)
        wantsLayer = true
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
        NotificationCenter.default.addObserver(self, selector: #selector(layoutChanged),
                                               name: .windowLayoutDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(layoutChanged),
                                               name: ModernSkinEngine.skinDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(layoutChanged),
                                               name: .doubleSizeDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(layoutChanged),
                                               name: .connectedWindowHighlightDidChange, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit {
        refreshTimer?.invalidate()
        pollTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func layoutChanged() { needsLayout = true; needsDisplay = true }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let area = hostedContext == nil ? chrome.contentRect(bounds) : bounds
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
        status.textColor = (hostedStyle?.text ?? chrome.textColor).withAlphaComponent(0.8)
        if hostedContext == nil { (window as? BorderlessWindow)?.titleBarHeight = chrome.titleHeight }
    }

    override func draw(_ dirtyRect: NSRect) {
        if let hostedStyle {
            hostedStyle.background.setFill()
            bounds.fill()
        } else { chrome.draw(bounds, closePressed: closePressed) }
    }

    func refresh() {
        let background = (hostedStyle?.background ?? chrome.backgroundColor).usingColorSpace(.deviceRGB) ?? .black
        let brightness = 0.299 * background.redComponent + 0.587 * background.greenComponent + 0.114 * background.blueComponent
        let appearanceName: NSAppearance.Name = brightness < 0.5 ? .darkAqua : .aqua
        if appearance?.name != appearanceName { appearance = NSAppearance(named: appearanceName) }
        let tint = hostedStyle?.text ?? chrome.textColor
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
                                  casting: casting, enabled: !changing, color: hostedStyle?.text ?? chrome.textColor)
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

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        if let hostedContext { hostedDrag.prime(event, context: hostedContext); return }
        let point = convert(event.locationInWindow, from: nil)
        if hostedContext == nil && chrome.closeRect(bounds).contains(point) { closePressed = true; needsDisplay = true; return }
        dragStart = event.locationInWindow
        if let window { WindowManager.shared.windowWillStartDragging(window, fromTitleBar: true) }
    }
    override func mouseDragged(with event: NSEvent) {
        if hostedContext != nil { hostedDrag.drag(event); return }
        guard let start = dragStart, let window else { return }
        let mouse = NSEvent.mouseLocation
        let origin = NSPoint(x: mouse.x - start.x, y: mouse.y - start.y)
        window.setFrameOrigin(WindowManager.shared.windowWillMove(window, to: origin))
    }
    override func mouseUp(with event: NSEvent) {
        if hostedContext != nil { hostedDrag.end(); return }
        if closePressed && chrome.closeRect(bounds).contains(convert(event.locationInWindow, from: nil)) {
            WindowManager.shared.toggleSonos()
        }
        closePressed = false
        if dragStart != nil, let window { WindowManager.shared.windowDidFinishDragging(window) }
        dragStart = nil
        needsDisplay = true
    }
}

extension SonosWindowView: WinampModernHostedSurface {
    var view: NSView { self }
    func configureForHostedSurface(context: WinampModernHostedSurfaceContext) {
        hostedContext = context
        autoresizingMask = [.width, .height]
    }
    func applyPalette(_ style: WinampModernSurfaceStyle) {
        hostedStyle = style
        needsLayout = true
        refresh()
    }
    func applySkinScale(_ scale: CGFloat) { needsLayout = true; needsDisplay = true }
    func resume() {
        needsLayout = true
        layoutSubtreeIfNeeded()
        refresh()
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
    func suspend() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        pollTask?.cancel()
        pollTask = nil
    }
    func unmountFromHolder() { suspend(); removeFromSuperview() }
    func prepareForUITeardown() { suspend(); hostedContext = nil; removeFromSuperview() }
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
