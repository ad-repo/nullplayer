import AppKit

/// The borderless, non-activating floating panel with a native HUD backdrop that NullPlayer's
/// own transient chrome (the skin loader, the activity panel) is drawn in.
enum HUDPanel {
    /// A panel whose content view is the returned blurred, rounded backdrop; add content to it.
    static func make(size: NSSize, cornerRadius: CGFloat) -> (NSPanel, NSVisualEffectView) {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]

        let backdrop = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        backdrop.material = .hudWindow
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        // A `.behindWindow` backdrop is composited by the window server, which honours the view's
        // mask but not `layer.cornerRadius` — with a layer corner radius the blurred square (and
        // the window shadow traced from it) still show at the corners over light backgrounds.
        backdrop.maskImage = roundedMask(cornerRadius: cornerRadius)
        panel.contentView = backdrop
        return (panel, backdrop)
    }

    /// The visible frame of the screen holding the main window, where these panels are placed.
    static var anchorFrame: NSRect {
        let anchor = WindowManager.shared.mainWindowController?.window ?? NSApp.keyWindow
        return anchor?.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    /// A resizable rounded-rect mask; `NSVisualEffectView` stretches it from the cap insets, so the
    /// corners stay circular at any panel size.
    private static func roundedMask(cornerRadius radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
