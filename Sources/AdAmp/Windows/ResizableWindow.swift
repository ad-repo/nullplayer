import AppKit

/// A borderless window that can become key/main and supports manual edge resizing
class ResizableWindow: NSWindow {
    
    // MARK: - Resize Edge Detection
    
    /// Width of the resize edge detection zone in pixels (larger = easier to grab)
    private let edgeThickness: CGFloat = 12
    
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
    
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        
        // Enable mouse moved events for cursor updates
        acceptsMouseMovedEvents = true
        
        // Store default size
        defaultSize = contentRect.size
    }
    
    // MARK: - Key/Main Window Support
    
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    
    // MARK: - Edge Detection
    
    /// Detect which edges the mouse is near for a given point in window coordinates
    private func detectEdges(at windowPoint: NSPoint) -> ResizeEdges {
        let size = frame.size
        var edges: ResizeEdges = []
        
        // Exclude title bar button area (top-right corner where close/shade buttons are)
        // Title bar is ~14 pixels tall, buttons are in rightmost ~40 pixels
        let titleBarHeight: CGFloat = 14
        let buttonAreaWidth: CGFloat = 40
        let isInTitleBarButtonArea = windowPoint.y > size.height - titleBarHeight && 
                                      windowPoint.x > size.width - buttonAreaWidth
        
        if isInTitleBarButtonArea {
            return .none  // Don't detect edges in button area
        }
        
        // Check horizontal edges
        if windowPoint.x < edgeThickness {
            edges.insert(.left)
        } else if windowPoint.x > size.width - edgeThickness {
            edges.insert(.right)
        }
        
        // Check vertical edges (window coordinates: 0 is at bottom)
        if windowPoint.y < edgeThickness {
            edges.insert(.bottom)
        } else if windowPoint.y > size.height - edgeThickness {
            edges.insert(.top)
        }
        
        return edges
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
        
        setFrame(newFrame, display: true, animate: true)
    }
}
