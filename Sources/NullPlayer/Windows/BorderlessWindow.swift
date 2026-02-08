import AppKit

/// A borderless window that can become key/main without edge-drag resizing.
/// Used by modern skin windows which have fixed dimensions and handle their
/// own dragging via the view layer. Supports fullscreen via style mask.
///
/// Optionally supports edge resize for windows that need it.
/// Configure via `allowedResizeEdges`:
/// - Empty (default) = no resize allowed (ModernEQ, ModernSpectrum, ModernMainWindow)
/// - `[.bottom]` = vertical-only expansion (ModernPlaylist)
/// - `[.left, .right, .top, .bottom]` = full multi-edge resize (ModernLibraryBrowser)
class BorderlessWindow: NSWindow {
    
    /// Edges that allow resize dragging. Empty (default) = no resize allowed.
    var allowedResizeEdges: Set<ResizeEdge> = []
    
    /// Available resize edges
    enum ResizeEdge {
        case bottom
        case top
        case left
        case right
    }
    
    // MARK: - Resize State
    
    /// Width of the resize edge detection zone in pixels
    private let edgeThickness: CGFloat = 8
    
    /// Whether we're currently in a resize operation
    private var isResizing = false
    
    /// Which edges are actively being resized
    private var activeResizeEdges: Set<ResizeEdge> = []
    
    /// Initial mouse location in screen coordinates when resize started
    private var initialMouseLocation: NSPoint = .zero
    
    /// Initial window frame when resize started
    private var initialFrame: NSRect = .zero
    
    // MARK: - Key/Main Support
    
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    
    // MARK: - Edge Detection
    
    /// Detect which allowed resize edges the point is near
    private func detectResizeEdges(at windowPoint: NSPoint) -> Set<ResizeEdge> {
        var edges = Set<ResizeEdge>()
        
        if allowedResizeEdges.contains(.bottom) && windowPoint.y < edgeThickness {
            edges.insert(.bottom)
        }
        if allowedResizeEdges.contains(.top) && windowPoint.y > frame.height - edgeThickness {
            edges.insert(.top)
        }
        if allowedResizeEdges.contains(.left) && windowPoint.x < edgeThickness {
            edges.insert(.left)
        }
        if allowedResizeEdges.contains(.right) && windowPoint.x > frame.width - edgeThickness {
            edges.insert(.right)
        }
        
        return edges
    }
    
    /// Get the appropriate cursor for the given resize edges
    private func cursor(for edges: Set<ResizeEdge>) -> NSCursor {
        let hasH = edges.contains(.left) || edges.contains(.right)
        let hasV = edges.contains(.top) || edges.contains(.bottom)
        
        if hasH && hasV {
            // Corner - use crosshair since macOS doesn't have diagonal resize cursors
            return NSCursor.crosshair
        } else if hasH {
            return NSCursor.resizeLeftRight
        } else if hasV {
            return NSCursor.resizeUpDown
        }
        return NSCursor.arrow
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
            let edges = detectResizeEdges(at: windowPoint)
            if !edges.isEmpty {
                isResizing = true
                activeResizeEdges = edges
                initialMouseLocation = NSEvent.mouseLocation
                initialFrame = frame
                return
            }
            
        case .leftMouseDragged:
            if isResizing {
                performResize()
                return
            }
            
        case .leftMouseUp:
            if isResizing {
                isResizing = false
                activeResizeEdges = []
                return
            }
            
        case .mouseMoved:
            let windowPoint = event.locationInWindow
            let edges = detectResizeEdges(at: windowPoint)
            if !edges.isEmpty {
                cursor(for: edges).set()
            } else if !isResizing {
                NSCursor.arrow.set()
            }
            
        default:
            break
        }
        
        super.sendEvent(event)
    }
    
    // MARK: - Resize Logic
    
    private func performResize() {
        let currentMouseLocation = NSEvent.mouseLocation
        let deltaX = currentMouseLocation.x - initialMouseLocation.x
        let deltaY = currentMouseLocation.y - initialMouseLocation.y
        
        var newFrame = initialFrame
        
        // Bottom edge: moving mouse down (negative deltaY) increases height,
        // and moves the origin down
        if activeResizeEdges.contains(.bottom) {
            let newHeight = initialFrame.height - deltaY
            newFrame.size.height = newHeight
            newFrame.origin.y = initialFrame.origin.y + deltaY
        }
        
        // Top edge: moving mouse up (positive deltaY) increases height,
        // origin stays the same
        if activeResizeEdges.contains(.top) {
            let newHeight = initialFrame.height + deltaY
            newFrame.size.height = newHeight
        }
        
        // Left edge: moving mouse left (negative deltaX) increases width,
        // and moves the origin left
        if activeResizeEdges.contains(.left) {
            let newWidth = initialFrame.width - deltaX
            newFrame.size.width = newWidth
            newFrame.origin.x = initialFrame.origin.x + deltaX
        }
        
        // Right edge: moving mouse right (positive deltaX) increases width,
        // origin stays the same
        if activeResizeEdges.contains(.right) {
            let newWidth = initialFrame.width + deltaX
            newFrame.size.width = newWidth
        }
        
        // Clamp to min/max size, adjusting origin as needed
        if newFrame.size.width < minSize.width {
            if activeResizeEdges.contains(.left) {
                newFrame.origin.x = initialFrame.maxX - minSize.width
            }
            newFrame.size.width = minSize.width
        }
        if maxSize.width > 0 && newFrame.size.width > maxSize.width {
            if activeResizeEdges.contains(.left) {
                newFrame.origin.x = initialFrame.maxX - maxSize.width
            }
            newFrame.size.width = maxSize.width
        }
        
        if newFrame.size.height < minSize.height {
            if activeResizeEdges.contains(.bottom) {
                newFrame.origin.y = initialFrame.maxY - minSize.height
            }
            newFrame.size.height = minSize.height
        }
        if maxSize.height > 0 && newFrame.size.height > maxSize.height {
            if activeResizeEdges.contains(.bottom) {
                newFrame.origin.y = initialFrame.maxY - maxSize.height
            }
            newFrame.size.height = maxSize.height
        }
        
        setFrame(newFrame, display: true)
    }
}
