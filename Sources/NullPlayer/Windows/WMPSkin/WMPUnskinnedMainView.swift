import AppKit

/// WMP's app-authored recovery/default player. It intentionally contains no skin resource or
/// borrowed artwork and remains usable when every archive path fails.
final class WMPUnskinnedMainView: NSView {
    var onImport: (() -> Void)?
    var onMinimize: (() -> Void)?
    var onClose: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "Windows Media Player")
    private let messageLabel = NSTextField(wrappingLabelWithString: "Import a .wmz skin to begin.")
    private let importButton = NSButton(title: "Import WMZ…", target: nil, action: nil)
    private let minimizeButton = NSButton(title: "Minimize", target: nil, action: nil)
    private let closeButton = NSButton(title: "Close", target: nil, action: nil)

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
        for view in [titleLabel, messageLabel, importButton, minimizeButton, closeButton] { addSubview(view) }
        importButton.target = self
        importButton.action = #selector(importPressed)
        minimizeButton.target = self
        minimizeButton.action = #selector(minimizePressed)
        closeButton.target = self
        closeButton.action = #selector(closePressed)
        setAccessibilityIdentifier("WMPUnskinnedMainView")
        setAccessibilityLabel("Windows Media Player unskinned player")
    }

    required init?(coder: NSCoder) { nil }

    func show(message: String?) {
        messageLabel.stringValue = message ?? "Import a .wmz skin to begin."
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = 22
        titleLabel.frame = NSRect(x: inset, y: 18, width: bounds.width - inset * 2, height: 24)
        messageLabel.frame = NSRect(x: inset, y: 50, width: bounds.width - inset * 2, height: 48)
        importButton.frame = NSRect(x: inset, y: bounds.height - 50, width: 116, height: 30)
        closeButton.frame = NSRect(x: bounds.width - inset - 70, y: bounds.height - 50, width: 70, height: 30)
        minimizeButton.frame = NSRect(x: closeButton.frame.minX - 88, y: bounds.height - 50, width: 80, height: 30)
    }

    @objc private func importPressed() { onImport?() }
    @objc private func minimizePressed() { onMinimize?() }
    @objc private func closePressed() { onClose?() }
}
