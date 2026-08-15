import AppKit

/// Phase 1 stub for the Winamp 5.x `.wal` (Wasabi XML + MAKI) main window.
///
/// This is the third controller family (`PlayerUIControllerFamily.winampModern`). It exists so
/// the mode/lifecycle plumbing — persistence, live switching, teardown/rebuild, auxiliary-window
/// routing — can be built and exercised end-to-end **before** the real Wasabi/MAKI renderer lands
/// in Phases 2–3.
///
/// It deliberately:
/// - imports **no** `Skin/` or `ModernSkin/` types (no classic or NullPlayer-modern rendering),
/// - renders only a labelled placeholder window,
/// - satisfies `MainWindowProviding` with no-op update methods (there is nothing to draw yet).
///
/// Its window uses the classic main-window footprint so the classic auxiliary windows that
/// `winampModern` reuses in Phase 1 (playlist/EQ/library/…) dock and lay out against a known size.
final class WinampModernMainWindowController: NSWindowController, MainWindowProviding {

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Skin.mainWindowSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        self.init(window: window)
        setupWindow()
        setupPlaceholderView()
    }

    private func setupWindow() {
        guard let window else { return }
        window.title = "NullPlayer — Winamp Modern"
        window.isReleasedWhenClosed = false
        window.center()
        window.setAccessibilityIdentifier("WinampModernMainWindow")
        window.setAccessibilityLabel("Winamp Modern Main Window (placeholder)")
    }

    private func setupPlaceholderView() {
        guard let window else { return }
        let content = NSView(frame: NSRect(origin: .zero, size: Skin.mainWindowSize))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(white: 0.08, alpha: 1.0).cgColor

        let label = NSTextField(labelWithString: "Winamp Modern (.wal)\nrenderer not yet implemented")
        label.font = .systemFont(ofSize: 11)
        label.textColor = NSColor(white: 0.65, alpha: 1.0)
        label.alignment = .center
        label.maximumNumberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: content.centerYAnchor)
        ])

        window.contentView = content
    }

    // MARK: - MainWindowProviding (no-op until the Wasabi/MAKI renderer exists)

    func updateTrackInfo(_ track: Track?) {}
    func updateVideoTrackInfo(title: String, artworkTrack: Track?) {}
    func clearVideoTrackInfo() {}
    func updateTime(current: TimeInterval, duration: TimeInterval) {}
    func updatePlaybackState() {}
    func updateSpectrum(_ levels: [Float]) {}
    func skinDidChange() {}
    func windowVisibilityDidChange() {}
}
