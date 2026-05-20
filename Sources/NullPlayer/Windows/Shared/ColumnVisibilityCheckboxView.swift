import AppKit

final class ColumnVisibilityCheckboxView: NSView {
    private let button: NSButton
    private let onToggle: (Bool) -> Void

    init(title: String, isChecked: Bool, isEnabled: Bool = true, onToggle: @escaping (Bool) -> Void) {
        self.button = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        self.onToggle = onToggle
        button.state = isChecked ? .on : .off
        button.isEnabled = isEnabled
        button.font = NSFont.menuFont(ofSize: 0)
        button.sizeToFit()

        let frame = NSRect(x: 0, y: 0, width: max(220, button.frame.width + 32), height: 24)
        super.init(frame: frame)

        button.target = self
        button.action = #selector(toggleFromButton)
        button.frame.origin = NSPoint(x: 16, y: (frame.height - button.frame.height) / 2)
        button.autoresizingMask = [.width, .height]
        addSubview(button)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        guard button.isEnabled else { return }
        setChecked(button.state != .on)
    }

    @objc private func toggleFromButton() {
        onToggle(button.state == .on)
    }

    private func setChecked(_ checked: Bool) {
        button.state = checked ? .on : .off
        onToggle(checked)
    }
}
