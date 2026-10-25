import AppKit

/// A skin family's borderless main window (an Audion face, a Sonique skin): clear, so the skin's
/// shape is the window's. AppKit refuses a borderless window key status by default, which would also
/// cut off its key events and mouse-moved stream.
final class SkinnedBorderlessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// A drag of a borderless skinned window, through `WindowManager` so docking and snapping see it;
/// AppKit's own background drag would bypass both.
struct SkinnedWindowDrag {
    private var start: NSPoint?

    mutating func begin(_ event: NSEvent) {
        guard let window = event.window else { return }
        start = event.locationInWindow
        WindowManager.shared.windowWillStartDragging(window, fromTitleBar: true)
    }

    func move(_ event: NSEvent) {
        guard let start, let window = event.window else { return }
        var origin = window.frame.origin
        origin.x += event.locationInWindow.x - start.x
        origin.y += event.locationInWindow.y - start.y
        window.setFrameOrigin(WindowManager.shared.windowWillMove(window, to: origin))
    }

    mutating func end(_ event: NSEvent) {
        guard start != nil, let window = event.window else { return }
        start = nil
        WindowManager.shared.windowDidFinishDragging(window)
    }
}
