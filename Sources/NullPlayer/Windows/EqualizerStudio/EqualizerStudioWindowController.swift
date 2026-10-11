import AppKit

/// **Equalizer Studio** — the one place EQ profiles are made and edited. One controller for every
/// skin family: a borderless window whose rim is the gloss frame in the hosting skin's colours,
/// around a faceplate of its own. Not a centre-stack window: it is 700×560 and floats free.
final class EqualizerStudioWindowController: NSWindowController, NSWindowDelegate {
    static let size = NSSize(width: 700, height: 560)
    fileprivate static var current: EqualizerStudioWindowController?

    private let studioView: EqualizerStudioView

    init() {
        let window = BorderlessWindow(contentRect: NSRect(origin: .zero, size: Self.size),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.title = "Equalizer Studio"
        studioView = EqualizerStudioView(frame: NSRect(origin: .zero, size: Self.size))
        window.contentView = studioView
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func showWindow(_ sender: Any?) {
        if window?.isVisible != true { studioView.studioDidOpen() }
        super.showWindow(sender)
    }

    func windowWillClose(_ notification: Notification) {
        studioView.studioDidClose()
    }

    func windowDidBecomeKey(_ notification: Notification) { studioView.needsDisplay = true }
    func windowDidResignKey(_ notification: Notification) { studioView.needsDisplay = true }
}

extension WindowManager {
    var isEqualizerStudioVisible: Bool { EqualizerStudioWindowController.current?.window?.isVisible ?? false }

    var equalizerStudioWindowFrame: NSRect? { EqualizerStudioWindowController.current?.window?.frame }

    func showEqualizerStudio(at restoredFrame: NSRect? = nil) {
        let controller = EqualizerStudioWindowController.current ?? EqualizerStudioWindowController()
        EqualizerStudioWindowController.current = controller
        guard let window = controller.window else { return }
        if let restoredFrame {
            window.setFrameOrigin(restoredFrame.origin)
        } else if !window.isVisible {
            window.center()
        }
        window.level = isAlwaysOnTop ? .floating : .normal
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func toggleEqualizerStudio() {
        if isEqualizerStudioVisible {
            EqualizerStudioWindowController.current?.window?.close()
        } else {
            showEqualizerStudio()
        }
    }
}
