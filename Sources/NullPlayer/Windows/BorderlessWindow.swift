import AppKit

/// A borderless window that can become key/main without edge-drag resizing.
/// Used by modern skin windows which have fixed dimensions and handle their
/// own dragging via the view layer. Supports fullscreen via style mask.
///
/// Optionally supports bottom-edge resize for windows like the playlist
/// that need vertical expansion. Configure via `allowedResizeEdges`.
class BorderlessWindow: NSWindow {
    
    /// Edges that allow resize dragging. Empty (default) = no resize allowed.
    var allowedResizeEdges: Set<ResizeEdge> = []
    
    /// Available resize edges
    enum ResizeEdge {
        case bottom
    }
    
    // MARK: - Resize State
    
    /// Width of the resize edge detection zone in pixels
    private let edgeThickness: CGFloat = 8
    
    /// Whether we're currently in a resize operation
    private var isResizing = false
    
    /// Initial mouse location in screen coordinates when resize started
    private var initialMouseLocation: NSPoint = .zero
    
    /// Initial window frame when resize started
    private var initialFrame: NSRect = .zero
    
    // MARK: - Key/Main Support
    
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    
    // MARK: - Edge Detection
    
    /// Check if the point is near the bottom edge (for resize)
    private func isNearBottomEdge(at windowPoint: NSPoint) -> Bool {
        guard allowedResizeEdges.contains(.bottom) else { return false }
        return windowPoint.y < edgeThickness
    }
    
    // MARK: - Event Handling
    
    override func sendEvent(_ event: NSEvent) {
        // Only intercept if we have allowed edges
        guard !allowedResizeEdges.isEmpty else {
            super.sendEvent(event)
            return
        }
        
        switch event.type {
        case .leftMouseDown:
            let windowPoint = event.locationInWindow
            if isNearBottomEdge(at: windowPoint) {
                isResizing = true
                initialMouseLocation = NSEvent.mouseLocation
                initialFrame = frame
                return
            }
            
        case .leftMouseDragged:
            if isResizing {
                performBottomResize()
                return
            }
            
        case .leftMouseUp:
            if isResizing {
                isResizing = false
                return
            }
            
        case .mouseMoved:
            let windowPoint = event.locationInWindow
            if isNearBottomEdge(at: windowPoint) {
                NSCursor.resizeUpDown.set()
            } else if !isResizing {
                NSCursor.arrow.set()
            }
            
        default:
            break
        }
        
        super.sendEvent(event)
    }
    
    // MARK: - Resize Logic
    
    private func performBottomResize() {
        let currentMouseLocation = NSEvent.mouseLocation
        let deltaY = currentMouseLocation.y - initialMouseLocation.y
        
        // Bottom edge: moving mouse down (negative deltaY) increases height,
        // and moves the origin down
        let newHeight = initialFrame.height - deltaY
        
        guard newHeight >= minSize.height else {
            // Snap to minimum
            var newFrame = initialFrame
            newFrame.origin.y = initialFrame.maxY - minSize.height
            newFrame.size.height = minSize.height
            setFrame(newFrame, display: true)
            return
        }
        
        if maxSize.height > 0 && newHeight > maxSize.height {
            // Snap to maximum
            var newFrame = initialFrame
            newFrame.origin.y = initialFrame.maxY - maxSize.height
            newFrame.size.height = maxSize.height
            setFrame(newFrame, display: true)
            return
        }
        
        var newFrame = initialFrame
        newFrame.origin.y = initialFrame.origin.y + deltaY
        newFrame.size.height = newHeight
        setFrame(newFrame, display: true)
    }
}
