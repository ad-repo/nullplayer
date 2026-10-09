import AppKit

/// Audion mode's app-authored player for when no face is selected or the selected one fails to
/// load. It carries no Panic artwork and stays usable whatever the faces folder holds.
final class AudionFaceUnskinnedView: NSView {
    var onLoadFace: (() -> Void)?
    var onButton: ((AudionFace.ButtonRole) -> Void)?

    private let titleLabel = NSTextField(labelWithString: "Audion Faces")
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let loadButton = NSButton(title: "Load Face…", target: nil, action: nil)
    private let transport: [(NSButton, AudionFace.ButtonRole)] = [
        (NSButton(title: "◀◀", target: nil, action: nil), .rewind),
        (NSButton(title: "▶", target: nil, action: nil), .play),
        (NSButton(title: "Ⅱ", target: nil, action: nil), .pause),
        (NSButton(title: "■", target: nil, action: nil), .stop),
        (NSButton(title: "▶▶", target: nil, action: nil), .fastForward),
    ]

    private var drag = AudionFaceWindowDrag()

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 1).cgColor
        layer?.cornerRadius = 10
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .white
        messageLabel.font = .systemFont(ofSize: 11)
        messageLabel.textColor = .secondaryLabelColor
        loadButton.target = self
        loadButton.action = #selector(loadPressed)
        [titleLabel, messageLabel, loadButton].forEach(addSubview)
        for (button, _) in transport {
            button.target = self
            button.action = #selector(transportPressed(_:))
            addSubview(button)
        }
        setAccessibilityIdentifier("AudionFaceUnskinnedView")
        show(message: nil)
    }

    required init?(coder: NSCoder) { nil }

    func show(message: String?) {
        messageLabel.stringValue = message ?? "Choose a face from Skins ▸ Audion Faces, or load one."
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = 14
        titleLabel.frame = NSRect(x: inset, y: 10, width: bounds.width - inset * 2, height: 20)
        messageLabel.frame = NSRect(x: inset, y: 32, width: bounds.width - inset * 2, height: 30)
        var x = inset
        for (button, _) in transport {
            button.frame = NSRect(x: x, y: bounds.height - 36, width: 38, height: 24)
            x += 40
        }
        loadButton.frame = NSRect(x: bounds.width - inset - 96, y: bounds.height - 36, width: 96, height: 24)
    }

    @objc private func loadPressed() { onLoadFace?() }
    @objc private func transportPressed(_ sender: NSButton) {
        if let role = transport.first(where: { $0.0 === sender })?.1 { onButton?(role) }
    }

    override func mouseDown(with event: NSEvent) { drag.begin(event) }
    override func mouseDragged(with event: NSEvent) { drag.move(event) }
    override func mouseUp(with event: NSEvent) { drag.end(event) }

    override func menu(for event: NSEvent) -> NSMenu? {
        ContextMenuBuilder.buildMenu(includeOutputDevices: false, includeRepeatShuffle: false)
    }
}
