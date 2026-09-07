import AppKit

/// Gives a hosted NullPlayer window back the window drag it has when it stands on its own.
///
/// A NullPlayer window mounted in a `.wal` skin's standard frame is the same view class as the
/// Classic and Original one, so B55 read the frame's chrome as owning the drag and had every hosted
/// surface swallow presses it did not consume. The frame supplies chrome, not a drag surface: its
/// title strip measures 15–45 skin pixels across the installed corpus, and a fixed strip is a
/// smaller and smaller share of the window as the window grows — 27px of a 580px-tall projectM
/// window on Nullsoft 2000, against a body that is a handle everywhere in Classic and Original.
///
/// Presses arrive here only after the surface has had its own chance at them, so a slider, a row or
/// a button still wins. What is left is background, and background moves the window.
///
/// The prime-then-move idiom is the app's own (`ModernLibraryBrowserView` drags a hidden-title-bar
/// window this way): the press is *primed* at `mouseDown` and only becomes a drag once the pointer
/// has travelled, so a press that never moves is still a click and a double-click still lands.
@MainActor
struct WinampModernHostedWindowDrag {

    /// Travel, in window points, that separates a drag from a click. Small enough that a deliberate
    /// move feels immediate, large enough to survive the jitter of a click on a trackpad.
    private static let threshold: CGFloat = 3

    private weak var primedWindow: NSWindow?
    private var startPoint: NSPoint = .zero
    private var isMoving = false

    /// Whether this press has become an actual window move.
    var isDragging: Bool { isMoving }

    /// Arm a press the surface did not consume. Harmless when the view is not hosted.
    mutating func prime(_ event: NSEvent, context: WinampModernHostedSurfaceContext?) {
        guard let window = context?.nativeWindow() else { return }
        primedWindow = window
        startPoint = event.locationInWindow
        isMoving = false
        WindowManager.shared.windowWillPrimeDragging(window)
    }

    /// Move the window once the press has travelled far enough. Answers whether it took the event.
    @discardableResult
    mutating func drag(_ event: NSEvent) -> Bool {
        guard let window = primedWindow else { return false }
        let current = event.locationInWindow
        let delta = NSPoint(x: current.x - startPoint.x, y: current.y - startPoint.y)
        if !isMoving {
            guard abs(delta.x) >= Self.threshold || abs(delta.y) >= Self.threshold else { return false }
            isMoving = true
            // Not a title-bar drag: the skin's frame owns the title bar, and this is the body below
            // it. The flag is documentation at the manager, but it should still say what happened.
            WindowManager.shared.windowWillStartDragging(window, fromTitleBar: false)
        }
        // `locationInWindow` is measured against the window, which is following the pointer, so the
        // press point stays put and each event carries only the increment. Same arithmetic as every
        // standalone drag in these views.
        var origin = window.frame.origin
        origin.x += delta.x
        origin.y += delta.y
        window.setFrameOrigin(WindowManager.shared.windowWillMove(window, to: origin))
        return true
    }

    /// Finish the press. Answers whether it was a drag, so a caller can drop the click it would
    /// otherwise have performed on release.
    @discardableResult
    mutating func end() -> Bool {
        guard let window = primedWindow else { return false }
        primedWindow = nil
        guard isMoving else {
            WindowManager.shared.windowDidCancelDragPrime(window)
            return false
        }
        isMoving = false
        WindowManager.shared.windowDidFinishDragging(window)
        return true
    }
}
