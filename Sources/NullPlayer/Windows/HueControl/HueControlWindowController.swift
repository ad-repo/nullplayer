import AppKit

final class HueControlWindowController: NSWindowController, NSWindowDelegate {
    private var hueView: HueControlView!
    private var placeholderView: NSView?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        self.init(window: window)
        setupWindow()
        setupView()
    }

    private func setupWindow() {
        guard let window else { return }
        window.title = "Hue Control"
        window.minSize = NSSize(width: 600, height: 620)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setAccessibilityIdentifier("HueControlWindow")
        window.setAccessibilityLabel("Hue Control Window")
    }

    private func setupView() {
        let placeholder = NSView(frame: window?.contentView?.bounds ?? .zero)
        placeholder.autoresizingMask = [.width, .height]

        let label = NSTextField(labelWithString: "Loading Hue controls…")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        placeholder.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: placeholder.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: placeholder.centerYAnchor)
        ])

        placeholderView = placeholder
        window?.contentView = placeholder

        DispatchQueue.main.async { [weak self] in
            self?.installHueView()
        }
    }

    private func installHueView() {
        guard hueView == nil else { return }
        guard let window else { return }
        let view = HueControlView(frame: window.contentView?.bounds ?? .zero)
        view.autoresizingMask = [.width, .height]
        hueView = view
        window.contentView = view
        placeholderView = nil
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        if hueView == nil {
            DispatchQueue.main.async { [weak self] in
                self?.installHueView()
            }
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        WindowManager.shared.bringAllWindowsToFront(keepingWindowOnTop: window)
    }

    func windowWillClose(_ notification: Notification) {
        // Keep manager alive and connected; window close only hides UI.
    }
}
