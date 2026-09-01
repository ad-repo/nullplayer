import AppKit

/// WMP's app-authored recovery/default player. It intentionally contains no skin resource or
/// borrowed artwork and remains usable when every archive path fails.
final class WMPUnskinnedMainView: NSView {
    var onImport: (() -> Void)?
    var onMinimize: (() -> Void)?
    var onClose: (() -> Void)?
    weak var host: (any WMPHost)? { didSet { if let host { refresh(host.snapshot) } } }

    private let titleLabel = NSTextField(labelWithString: "Windows Media Player")
    private let messageLabel = NSTextField(wrappingLabelWithString: "Import a .wmz skin to begin.")
    private let importButton = NSButton(title: "Import WMZ…", target: nil, action: nil)
    private let minimizeButton = NSButton(title: "Minimize", target: nil, action: nil)
    private let closeButton = NSButton(title: "Close", target: nil, action: nil)
    private let previousButton = NSButton(title: "◀◀", target: nil, action: nil)
    private let playPauseButton = NSButton(title: "▶", target: nil, action: nil)
    private let stopButton = NSButton(title: "■", target: nil, action: nil)
    private let nextButton = NSButton(title: "▶▶", target: nil, action: nil)
    private let muteButton = NSButton(title: "Mute", target: nil, action: nil)
    private let timeLabel = NSTextField(labelWithString: "0:00 / 0:00")

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.09, alpha: 1).cgColor
        layer?.cornerRadius = 12
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(calibratedWhite: 0.3, alpha: 1).cgColor

        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textColor = .white
        messageLabel.font = .systemFont(ofSize: 12)
        messageLabel.textColor = .secondaryLabelColor
        for view in [titleLabel, messageLabel, previousButton, playPauseButton, stopButton, nextButton,
                     muteButton, timeLabel, importButton, minimizeButton, closeButton] { addSubview(view) }
        importButton.target = self
        importButton.action = #selector(importPressed)
        minimizeButton.target = self
        minimizeButton.action = #selector(minimizePressed)
        closeButton.target = self
        closeButton.action = #selector(closePressed)
        previousButton.target = self; previousButton.action = #selector(previousPressed)
        playPauseButton.target = self; playPauseButton.action = #selector(playPausePressed)
        stopButton.target = self; stopButton.action = #selector(stopPressed)
        nextButton.target = self; nextButton.action = #selector(nextPressed)
        muteButton.target = self; muteButton.action = #selector(mutePressed)
        previousButton.setAccessibilityIdentifier("wmp.unskinned.previous")
        playPauseButton.setAccessibilityIdentifier("wmp.unskinned.playPause")
        stopButton.setAccessibilityIdentifier("wmp.unskinned.stop")
        nextButton.setAccessibilityIdentifier("wmp.unskinned.next")
        muteButton.setAccessibilityIdentifier("wmp.unskinned.mute")
        setAccessibilityIdentifier("WMPUnskinnedMainView")
        setAccessibilityLabel("Windows Media Player unskinned player")
    }

    required init?(coder: NSCoder) { nil }

    func show(message: String?) {
        messageLabel.stringValue = message ?? "Import a .wmz skin to begin."
        needsLayout = true
    }

    func refresh(_ snapshot: WMPHostSnapshot) {
        playPauseButton.title = snapshot.state == .playing ? "Ⅱ" : "▶"
        previousButton.isEnabled = snapshot.isEnabled(.previous)
        playPauseButton.isEnabled = snapshot.isEnabled(snapshot.state == .playing ? .pause : .play)
        stopButton.isEnabled = snapshot.isEnabled(.stop)
        nextButton.isEnabled = snapshot.isEnabled(.next)
        muteButton.title = snapshot.muted ? "Unmute" : "Mute"
        timeLabel.stringValue = "\(snapshot.elapsedText) / \(snapshot.durationText)"
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = 22
        titleLabel.frame = NSRect(x: inset, y: 18, width: bounds.width - inset * 2, height: 24)
        messageLabel.frame = NSRect(x: inset, y: 50, width: bounds.width - inset * 2, height: 48)
        var x = inset
        for button in [previousButton, playPauseButton, stopButton, nextButton] {
            button.frame = NSRect(x: x, y: 94, width: 42, height: 26); x += 44
        }
        muteButton.frame = NSRect(x: x + 4, y: 94, width: 62, height: 26)
        timeLabel.frame = NSRect(x: bounds.width - inset - 105, y: 99, width: 105, height: 18)
        importButton.frame = NSRect(x: inset, y: bounds.height - 40, width: 116, height: 26)
        closeButton.frame = NSRect(x: bounds.width - inset - 70, y: bounds.height - 40, width: 70, height: 26)
        minimizeButton.frame = NSRect(x: closeButton.frame.minX - 88, y: bounds.height - 40, width: 80, height: 26)
    }

    @objc private func importPressed() { onImport?() }
    @objc private func minimizePressed() { onMinimize?() }
    @objc private func closePressed() { onClose?() }
    @objc private func previousPressed() { host?.perform(.previous, value: nil) }
    @objc private func playPausePressed() {
        guard let host else { return }
        host.perform(host.snapshot.state == .playing ? .pause : .play, value: nil)
        refresh(host.snapshot)
    }
    @objc private func stopPressed() { host?.perform(.stop, value: nil) }
    @objc private func nextPressed() { host?.perform(.next, value: nil) }
    @objc private func mutePressed() {
        host?.perform(.toggleMute, value: nil)
        if let host { refresh(host.snapshot) }
    }
}
