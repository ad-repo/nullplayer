import AppKit

final class YouTubeMusicPlayerWindowController: NSWindowController {
    private let playerView = YouTubeMusicPlayerView(frame: NSRect(x: 0, y: 0, width: 560, height: 315))

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 160, y: 160, width: 560, height: 315),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "YouTube Music"
        window.minSize = NSSize(width: 360, height: 220)
        window.contentView = playerView
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func load(rawSource: String, autoplay: Bool = true) {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        YouTubeMusicController.shared.load(rawSource: rawSource, autoplay: autoplay)
    }
}
