import AppKit

extension Notification.Name {
    /// Posted by a `ResizableWindow` (the object) when the user starts dragging one of its edges, and
    /// `windowEdgeResizeDidEnd` when they let go. The resize is done by hand with `setFrame`, which
    /// never enters AppKit's live resize, so `willStartLiveResizeNotification` is never posted for
    /// these windows — a hosted `.wmz` frame needs to know a drag is on (`HostedWindowBorderLayout`).
    static let windowEdgeResizeDidBegin = Notification.Name("windowEdgeResizeDidBegin")
    static let windowEdgeResizeDidEnd = Notification.Name("windowEdgeResizeDidEnd")
}

/// A borderless window that can become key/main and supports manual edge resizing
class ResizableWindow: NSWindow {
    
    // MARK: - Resize Edge Detection
    
    /// Width of the resize edge detection zone in pixels (larger = easier to grab)
    private let edgeThickness: CGFloat = 14
    /// The 3 pt band AppKit's own `.resizable` frame used to give. The top edge and the right edge
    /// above the bottom corner resize only through it.
    private let frameEdgeThickness: CGFloat = 3

    /// Which edges are being resized
    struct ResizeEdges: OptionSet {
        let rawValue: Int
        
        static let left   = ResizeEdges(rawValue: 1 << 0)
        static let right  = ResizeEdges(rawValue: 1 << 1)
        static let top    = ResizeEdges(rawValue: 1 << 2)
        static let bottom = ResizeEdges(rawValue: 1 << 3)
        
        static let topLeft: ResizeEdges     = [.top, .left]
        static let topRight: ResizeEdges    = [.top, .right]
        static let bottomLeft: ResizeEdges  = [.bottom, .left]
        static let bottomRight: ResizeEdges = [.bottom, .right]
        
        static let none: ResizeEdges = []
    }
    
    /// Current resize operation state
    private var resizeEdges: ResizeEdges = .none
    
    /// Initial mouse location in screen coordinates when resize started
    private var initialMouseLocation: NSPoint = .zero
    
    /// Initial window frame when resize started
    private var initialFrame: NSRect = .zero
    
    /// Whether we're currently in a resize operation
    private var isResizing: Bool = false
    
    /// Default size for double-click restore (set from minSize)
    private var defaultSize: NSSize?
    
    // MARK: - Initialization
    
    /// A borderless window that resizes its own edges. It is deliberately not `.resizable`: from
    /// macOS 27 AppKit takes a press near a borderless `.resizable` window's frame for its own resize
    /// loop, which swallowed clicks on the title-bar buttons. `.miniaturizable` lets the skin's own
    /// minimize button reach the Dock.
    convenience init(contentRect: NSRect) {
        self.init(contentRect: contentRect, styleMask: [.borderless, .miniaturizable],
                  backing: .buffered, defer: false)
    }

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)

        NotificationCenter.default.addObserver(
            self, selector: #selector(dropResizableAfterFullScreen),
            name: NSWindow.didExitFullScreenNotification, object: self)

        // Enable mouse moved events for cursor updates
        acceptsMouseMovedEvents = true
        
        // Store default size
        defaultSize = contentRect.size
    }
    
    // MARK: - Key/Main Window Support
    
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // MARK: - Native Fullscreen

    /// Native fullscreen only fills the screen for a `.resizable` window, so the flag is held for
    /// the stay in fullscreen and dropped again on exit.
    override func toggleFullScreen(_ sender: Any?) {
        if !styleMask.contains(.fullScreen) {
            styleMask.insert(.resizable)
        }
        super.toggleFullScreen(sender)
    }

    @objc private func dropResizableAfterFullScreen(_ notification: Notification) {
        styleMask.remove(.resizable)
    }

    // MARK: - Edge Detection
    
    /// Detect which edges the mouse is near for a given point in window coordinates
    private func detectEdges(at windowPoint: NSPoint) -> ResizeEdges {
        let size = frame.size

        // The title bar drags the window, and holds the menu button on the left and the window
        // buttons on the right. Only its top frame band resizes, and never over a button.
        // Scale-aware: at 2x a 14px skin title bar is 28 window pixels, and the buttons span
        // ~38 skin pixels from the right edge.
        if windowPoint.y > size.height - max(20, size.height * 0.12) {
            let isOverButton = windowPoint.x < max(20, size.width * 0.06)
                || windowPoint.x > size.width - max(40, size.width * 0.14)
            return !isOverButton && windowPoint.y > size.height - frameEdgeThickness ? .top : .none
        }

        // Window coordinates: y is 0 at the bottom
        var edges: ResizeEdges = []
        if windowPoint.x < edgeThickness {
            edges.insert(.left)
        } else if windowPoint.y < edgeThickness * 3 ? windowPoint.x > size.width - edgeThickness
                                                    : windowPoint.x >= size.width - frameEdgeThickness {
            // Above the bottom corner the right edge holds the playlist scrollbar, so it resizes
            // on the frame band alone
            edges.insert(.right)
        }
        if windowPoint.y < edgeThickness {
            edges.insert(.bottom)
        }
        return edges
    }

    /// Classic main window: block edge-resize while docked to any connected window.
    private func shouldBlockEdgeResize(_ edges: ResizeEdges) -> Bool {
        guard edges != .none else { return false }
        let wm = WindowManager.shared
        guard !wm.isRunningModernUI else { return false }
        guard self === wm.mainWindowController?.window else { return false }
        let hasAttachedChildren = !(self.childWindows?.isEmpty ?? true)
        return hasAttachedChildren || wm.isWindowDocked(self)
    }
    
    // MARK: - Event Handling
    
    /// Override sendEvent to intercept mouse events for resize handling
    /// This allows isMovableByWindowBackground to work normally when not resizing
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            if handleResizeMouseDown(event) {
                return // We consumed the event for resize
            }
            
        case .leftMouseDragged:
            if isResizing {
                handleResizeMouseDragged(event)
                return
            }
            
        case .leftMouseUp:
            if isResizing {
                handleResizeMouseUp(event)
                return
            }
            
        case .mouseMoved:
            updateResizeCursor(event)
            
        default:
            break
        }
        
        // Let the normal event handling proceed
        super.sendEvent(event)
    }
    
    /// Handle mouse down for potential resize operation
    /// Returns true if we're starting a resize, false to let normal handling proceed
    private func handleResizeMouseDown(_ event: NSEvent) -> Bool {
        let windowPoint = event.locationInWindow
        let edges = detectEdges(at: windowPoint)
        if shouldBlockEdgeResize(edges) {
            return false
        }
        
        // Double-click on edge restores to default/minimum size
        if event.clickCount == 2 && edges != .none {
            restoreToDefaultSize()
            return true
        }
        
        if edges != .none {
            // Start resize operation
            isResizing = true
            resizeEdges = edges
            initialMouseLocation = NSEvent.mouseLocation
            initialFrame = frame
            NotificationCenter.default.post(name: .windowEdgeResizeDidBegin, object: self)
            return true
        }
        
        return false
    }
    
    private func handleResizeMouseDragged(_ event: NSEvent) {
        performResize()
    }
    
    private func handleResizeMouseUp(_ event: NSEvent) {
        isResizing = false
        resizeEdges = .none
        NotificationCenter.default.post(name: .windowEdgeResizeDidEnd, object: self)
        
        // Update cursor based on current position
        let windowPoint = event.locationInWindow
        let edges = detectEdges(at: windowPoint)
        if edges == .none {
            NSCursor.arrow.set()
        }
    }
    
    private func updateResizeCursor(_ event: NSEvent) {
        let windowPoint = event.locationInWindow
        let edges = detectEdges(at: windowPoint)

        if shouldBlockEdgeResize(edges) {
            NSCursor.arrow.set()
            return
        }
        
        if edges != .none {
            // Show appropriate resize cursor
            switch edges {
            case .left, .right:
                NSCursor.resizeLeftRight.set()
            case .top, .bottom:
                NSCursor.resizeUpDown.set()
            case .topLeft, .bottomRight, .topRight, .bottomLeft:
                // Use crosshair as fallback for diagonal (macOS doesn't expose diagonal cursors easily)
                NSCursor.crosshair.set()
            default:
                NSCursor.arrow.set()
            }
        } else {
            NSCursor.arrow.set()
        }
    }
    
    // MARK: - Resize Logic
    
    private func performResize() {
        let currentMouseLocation = NSEvent.mouseLocation
        let deltaX = currentMouseLocation.x - initialMouseLocation.x
        let deltaY = currentMouseLocation.y - initialMouseLocation.y
        
        var newFrame = initialFrame
        
        // Handle horizontal resizing
        if resizeEdges.contains(.left) {
            // Resizing from left edge moves origin and changes width
            let newWidth = initialFrame.width - deltaX
            if newWidth >= minSize.width && (maxSize.width == 0 || newWidth <= maxSize.width) {
                newFrame.origin.x = initialFrame.origin.x + deltaX
                newFrame.size.width = newWidth
            } else if newWidth < minSize.width {
                // Snap to minimum
                newFrame.origin.x = initialFrame.maxX - minSize.width
                newFrame.size.width = minSize.width
            }
        } else if resizeEdges.contains(.right) {
            // Resizing from right edge only changes width
            let newWidth = initialFrame.width + deltaX
            if newWidth >= minSize.width && (maxSize.width == 0 || newWidth <= maxSize.width) {
                newFrame.size.width = newWidth
            } else if newWidth < minSize.width {
                newFrame.size.width = minSize.width
            }
        }
        
        // Handle vertical resizing
        if resizeEdges.contains(.bottom) {
            // Resizing from bottom edge moves origin and changes height
            let newHeight = initialFrame.height - deltaY
            if newHeight >= minSize.height && (maxSize.height == 0 || newHeight <= maxSize.height) {
                newFrame.origin.y = initialFrame.origin.y + deltaY
                newFrame.size.height = newHeight
            } else if newHeight < minSize.height {
                // Snap to minimum
                newFrame.origin.y = initialFrame.maxY - minSize.height
                newFrame.size.height = minSize.height
            }
        } else if resizeEdges.contains(.top) {
            // Resizing from top edge only changes height
            let newHeight = initialFrame.height + deltaY
            if newHeight >= minSize.height && (maxSize.height == 0 || newHeight <= maxSize.height) {
                newFrame.size.height = newHeight
            } else if newHeight < minSize.height {
                newFrame.size.height = minSize.height
            }
        }
        
        // Apply the new frame
        setFrame(newFrame, display: true)
    }
    
    /// Restore window to default/minimum size
    private func restoreToDefaultSize() {
        let targetSize = defaultSize ?? minSize
        guard targetSize.width > 0 && targetSize.height > 0 else { return }
        
        // Keep the top-left corner in place when resizing
        var newFrame = frame
        let heightDiff = frame.height - targetSize.height
        newFrame.origin.y += heightDiff
        newFrame.size = targetSize
        
        NotificationCenter.default.post(name: .windowEdgeResizeDidBegin, object: self)
        setFrame(newFrame, display: true, animate: true)
        NotificationCenter.default.post(name: .windowEdgeResizeDidEnd, object: self)
    }
}
