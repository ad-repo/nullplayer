import AppKit

/// The large hover preview of a library row thumbnail: the art in its own shape, beside the
/// hovered row. It hides itself on any click, scroll or key press and when a window closes,
/// resigns key or minimizes, so a browser only shows it on hover and hides it on `mouseExited`.
@MainActor
final class RowThumbnailPreview {
    /// The preview's longer side in points; the shorter follows the art's aspect.
    static let maxSide: CGFloat = 200

    private let resolve: (LibraryRowThumbnails.Source) async -> CGImage?
    private var panel: NSPanel?
    private var shownKey: String?
    private var resolveTask: Task<Void, Never>?
    private var eventMonitor: Any?

    init(resolve: @escaping (LibraryRowThumbnails.Source) async -> CGImage?) {
        self.resolve = resolve
        // A browser closing or losing key while hovered never sends it `mouseExited`.
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification, NSWindow.didMiniaturizeNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.hide() }
            }
        }
    }

    /// Show `source`'s art beside `anchor`, the hovered thumbnail in screen coordinates. A no-op
    /// while that source is already showing or resolving.
    func show(_ source: LibraryRowThumbnails.Source, anchor: NSRect) {
        guard shownKey != source.key else { return }
        hide()
        shownKey = source.key
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .keyDown]
        ) { [weak self] event in
            MainActor.assumeIsolated { self?.hide() }
            return event
        }
        resolveTask = Task {
            guard let image = await resolve(source), !Task.isCancelled, shownKey == source.key else { return }
            present(image, anchor: anchor)
        }
    }

    func hide() {
        resolveTask?.cancel()
        resolveTask = nil
        shownKey = nil
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        panel?.orderOut(nil)
    }

    private func present(_ image: CGImage, anchor: NSRect) {
        let scale = Self.maxSide / CGFloat(max(image.width, image.height))
        let size = NSSize(width: (CGFloat(image.width) * scale).rounded(), height: (CGFloat(image.height) * scale).rounded())
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView?.layer?.contents = image

        // Right of the thumbnail, centred on it; left of it when the screen runs out.
        let gap: CGFloat = 8
        var origin = NSPoint(x: anchor.maxX + gap, y: anchor.midY - size.height / 2)
        let center = NSPoint(x: anchor.midX, y: anchor.midY)
        if let visible = (NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main)?.visibleFrame {
            if origin.x + size.width > visible.maxX { origin.x = anchor.minX - gap - size.width }
            origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFront(nil)
    }

    private func makePanel() -> NSPanel {
        let frame = NSRect(x: 0, y: 0, width: Self.maxSide, height: Self.maxSide)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = true
        panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]

        let view = NSView(frame: frame)
        view.autoresizingMask = [.width, .height]
        view.wantsLayer = true
        if let layer = view.layer {
            layer.cornerRadius = 4
            layer.masksToBounds = true
            layer.contentsGravity = .resize
            layer.borderWidth = 1
            layer.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
            layer.backgroundColor = NSColor.black.cgColor
        }
        panel.contentView = view
        return panel
    }
}
