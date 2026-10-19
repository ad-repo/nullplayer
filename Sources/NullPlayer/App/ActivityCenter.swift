import AppKit

/// Background-work progress (a rip, an EQ Cast render), shown as a stack of rows in a small
/// borderless "NullPlayer" notification panel at the top-right of the screen holding the main window.
///
/// It lives off the main window because `.wal`, `.wmz` and Audion players are arbitrary shapes —
/// a bar inside the player lands on transparent pixels or skin chrome. One row per `id`, so two
/// jobs running at once never overwrite each other; newest at the bottom. The header's chevron
/// collapses the rows to a one-line summary, remembered across launches.
@MainActor
final class ActivityCenter: NSObject {
    static let shared = ActivityCenter()

    private static let collapsedKey = "activityCenterCollapsed"
    private let width: CGFloat = 300
    private let screenInset: CGFloat = 16
    private var labels: [String: NSTextField] = [:]
    private let rows = NSStackView()
    private let title = NSTextField(labelWithString: "NullPlayer")
    private let toggle = NSButton()
    private lazy var panel = makePanel()

    private var collapsed: Bool {
        get { UserDefaults.standard.bool(forKey: Self.collapsedKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.collapsedKey) }
    }

    private override init() {
        super.init()
        // Follow the player to another display. Any window's move is posted; only the main
        // window's matters, and the controller can be swapped by a skin change, so match by object.
        NotificationCenter.default.addObserver(forName: NSWindow.didChangeScreenNotification,
                                               object: nil, queue: .main) { note in
            MainActor.assumeIsolated {
                guard !self.labels.isEmpty,
                      note.object as? NSWindow === WindowManager.shared.mainWindowController?.window
                else { return }
                self.place()
            }
        }
    }

    /// Show a spinner row for `id`, or update its message if it is already showing.
    func show(id: String, message: String) {
        guard !AudioEngine.isHeadless else { return }
        if let label = labels[id] {
            label.stringValue = message
            return
        }

        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.startAnimation(nil)

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 12)
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [spinner, label])
        row.spacing = 8
        rows.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        labels[id] = label
        place()
    }

    func hide(id: String) {
        guard let label = labels.removeValue(forKey: id) else { return }
        label.superview?.removeFromSuperview()
        if labels.isEmpty { panel.orderOut(nil) } else { place() }
    }

    @objc private func toggleCollapsed() {
        collapsed.toggle()
        place()
    }

    /// Apply the collapsed state, size the panel to its content and park it in the top-right of
    /// the main window's screen.
    private func place() {
        rows.isHidden = collapsed
        title.stringValue = collapsed
            ? "NullPlayer — \(labels.count) running"
            : "NullPlayer"
        toggle.image = NSImage(systemSymbolName: collapsed ? "chevron.down" : "chevron.up",
                               accessibilityDescription: collapsed ? "Show" : "Hide")

        let height = panel.contentView?.fittingSize.height ?? 40
        let size = NSSize(width: width, height: height)
        let bounds = HUDPanel.anchorFrame
        let origin = NSPoint(x: bounds.maxX - screenInset - size.width,
                             y: bounds.maxY - screenInset - size.height)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
        panel.invalidateShadow()
    }

    private func makePanel() -> NSPanel {
        let (panel, container) = HUDPanel.make(size: NSSize(width: width, height: 40), cornerRadius: 10)
        panel.becomesKeyOnlyIfNeeded = true

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.alphaValue = 0.5
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 32).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 32).isActive = true

        title.font = .boldSystemFont(ofSize: 11)
        title.textColor = .secondaryLabelColor
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        toggle.isBordered = false
        toggle.imagePosition = .imageOnly
        toggle.contentTintColor = .secondaryLabelColor
        toggle.target = self
        toggle.action = #selector(toggleCollapsed)

        let header = NSStackView(views: [title, NSView(), toggle])
        header.spacing = 4

        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 6

        let text = NSStackView(views: [header, rows])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 6
        header.widthAnchor.constraint(equalTo: text.widthAnchor).isActive = true
        rows.widthAnchor.constraint(equalTo: text.widthAnchor).isActive = true

        let outer = NSStackView(views: [icon, text])
        outer.alignment = .top
        outer.spacing = 12
        outer.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        outer.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(outer)
        NSLayoutConstraint.activate([
            outer.widthAnchor.constraint(equalToConstant: width),
            outer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            outer.topAnchor.constraint(equalTo: container.topAnchor),
            outer.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            // A `.top`-aligned stack does not make its bottom hold the taller arranged view, so
            // without this the panel is sized to the icon and clips the rows below it.
            text.bottomAnchor.constraint(lessThanOrEqualTo: outer.bottomAnchor, constant: -outer.edgeInsets.bottom),
            // The text column runs to the right inset, so the padding is even on every side.
            text.trailingAnchor.constraint(equalTo: outer.trailingAnchor, constant: -outer.edgeInsets.right),
        ])

        return panel
    }
}
