import AppKit

/// What one row of the Rip window's list shows: a job, or a history entry.
struct RipRowModel {
    struct Action {
        let symbol: String
        let label: String
        let perform: () -> Void
    }

    let id: String
    let title: String
    let detail: String
    /// The full text behind a shortened detail (a failure's whole error).
    let detailToolTip: String?
    /// Shown as a bar while the job runs; nil with `showsProgress` is an indeterminate bar.
    let fraction: Double?
    let showsProgress: Bool
    let isFailure: Bool
    let actions: [Action]
}

final class RipJobRowView: NSView {
    static let height: CGFloat = 50

    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let bar = NSProgressIndicator()
    private var buttons: [NSButton] = []
    private var actions: [RipRowModel.Action] = []
    private var accent = NSColor.labelColor
    /// Flashed when a duplicate Rip points at this job.
    var highlighted = false { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        for view in [title, detail, bar] { addSubview(view) }
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        detail.font = .systemFont(ofSize: 10)
        detail.lineBreakMode = .byTruncatingTail
        bar.style = .bar
        bar.controlSize = .small
        bar.minValue = 0
        bar.maxValue = 1
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ model: RipRowModel, color: NSColor) {
        accent = color
        title.stringValue = model.title
        title.toolTip = model.title
        title.textColor = color
        detail.stringValue = model.detail
        detail.toolTip = model.detailToolTip ?? model.detail
        detail.textColor = model.isFailure ? .systemRed : color.withAlphaComponent(0.7)
        bar.isHidden = !model.showsProgress
        if let fraction = model.fraction {
            bar.isIndeterminate = false
            bar.doubleValue = fraction
        } else if model.showsProgress {
            bar.isIndeterminate = true
            bar.startAnimation(nil)
        }
        if actions.map(\.symbol) != model.actions.map(\.symbol) {
            buttons.forEach { $0.removeFromSuperview() }
            buttons = model.actions.map { action in
                let button = NSButton(image: NSImage(systemSymbolName: action.symbol, accessibilityDescription: action.label) ?? NSImage(),
                                      target: self, action: #selector(actionPressed(_:)))
                button.isBordered = false
                button.toolTip = action.label
                button.setAccessibilityLabel(action.label)
                addSubview(button)
                return button
            }
            needsLayout = true
        }
        actions = model.actions
        buttons.forEach { $0.contentTintColor = color }
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let buttonSize: CGFloat = 22
        var x = bounds.width - 8
        for button in buttons.reversed() {
            x -= buttonSize
            button.frame = NSRect(x: x, y: 8, width: buttonSize, height: buttonSize)
            x -= 2
        }
        let textWidth = max(0, x - 14)
        title.frame = NSRect(x: 10, y: 5, width: textWidth, height: 16)
        detail.frame = NSRect(x: 10, y: 22, width: textWidth, height: 13)
        bar.frame = NSRect(x: 10, y: 37, width: max(0, bounds.width - 20), height: 8)
    }

    override func draw(_ dirtyRect: NSRect) {
        if highlighted { accent.withAlphaComponent(0.15).setFill(); bounds.fill() }
        accent.withAlphaComponent(0.13).setFill()
        NSRect(x: 10, y: bounds.height - 1, width: max(0, bounds.width - 20), height: 1).fill()
    }

    @objc private func actionPressed(_ sender: NSButton) {
        guard let index = buttons.firstIndex(of: sender), actions.indices.contains(index) else { return }
        actions[index].perform()
    }
}
