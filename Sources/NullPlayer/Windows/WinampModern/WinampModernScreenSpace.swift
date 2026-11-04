import AppKit

/// Winamp's screen space: top-left points on a display. Window origins, the cursor,
/// `clientToScreen*` and `popAtXY` all answer in it, so a script can compare across them; this is
/// the one place the flip to and from Cocoa's bottom-left global space is made.
enum WinampModernScreenSpace {
    static func point(fromCocoa point: NSPoint, on screen: NSScreen) -> CGPoint {
        CGPoint(x: point.x - screen.frame.minX, y: screen.frame.maxY - point.y)
    }

    static func cocoaPoint(_ point: CGPoint, on screen: NSScreen) -> NSPoint {
        NSPoint(x: screen.frame.minX + point.x, y: screen.frame.maxY - point.y)
    }
}
