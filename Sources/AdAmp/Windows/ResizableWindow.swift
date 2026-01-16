import AppKit

/// A borderless window that supports edge/corner resizing like a normal window
class ResizableWindow: NSWindow {
    
    /// Edge threshold for resize detection (pixels from edge that triggers resize)
    private let resizeThreshold: CGFloat = 10
    
    /// Set to false to disable resizing (e.g., in shade mode)
    var resizingEnabled: Bool = true
    
    private var resizeTrackingArea: NSTrackingArea?
    
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        // Always include resizable for our windows
        var finalStyle = style
        finalStyle.insert(.resizable)
        
        super.init(contentRect: contentRect, styleMask: finalStyle, backing: backingStoreType, defer: flag)
        
        // Enable mouse moved events for cursor updates
        acceptsMouseMovedEvents = true
    }
    
    override var contentView: NSView? {
        didSet {
            setupResizeTrackingArea()
        }
    }
    
    private func setupResizeTrackingArea() {
        guard let contentView = contentView else { return }
        
        // Remove old tracking area
        if let old = resizeTrackingArea {
            contentView.removeTrackingArea(old)
        }
        
        // Add new tracking area covering the whole content view
        resizeTrackingArea = NSTrackingArea(
            rect: contentView.bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        contentView.addTrackingArea(resizeTrackingArea!)
    }
    
    override func mouseMoved(with event: NSEvent) {
        guard resizingEnabled else {
            super.mouseMoved(with: event)
            return
        }
        
        let windowPoint = event.locationInWindow
        let edge = detectEdge(at: windowPoint)
        cursor(for: edge).set()
    }
    
    override func mouseDown(with event: NSEvent) {
        let windowPoint = event.locationInWindow
        let edge = resizingEnabled ? detectEdge(at: windowPoint) : .none
        
        if edge != .none {
            // Start resize - don't pass to super
            resizeEdge = edge
            resizeStartFrame = frame
            resizeStartMouse = convertPoint(toScreen: windowPoint)
            cursor(for: edge).set()
        } else {
            super.mouseDown(with: event)
        }
    }
    
    override func mouseDragged(with event: NSEvent) {
        if resizeEdge != .none {
            let windowPoint = event.locationInWindow
            let currentMouse = convertPoint(toScreen: windowPoint)
            performResize(to: currentMouse)
        } else {
            super.mouseDragged(with: event)
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        if resizeEdge != .none {
            resizeEdge = .none
            NSCursor.arrow.set()
        } else {
            super.mouseUp(with: event)
        }
    }
    
    private func performResize(to currentMouse: NSPoint) {
        let deltaX = currentMouse.x - resizeStartMouse.x
        let deltaY = currentMouse.y - resizeStartMouse.y
        
        var newFrame = resizeStartFrame
        
        switch resizeEdge {
        case .right:
            newFrame.size.width += deltaX
        case .left:
            newFrame.origin.x += deltaX
            newFrame.size.width -= deltaX
        case .top:
            newFrame.size.height += deltaY
        case .bottom:
            newFrame.origin.y += deltaY
            newFrame.size.height -= deltaY
        case .topRight:
            newFrame.size.width += deltaX
            newFrame.size.height += deltaY
        case .topLeft:
            newFrame.origin.x += deltaX
            newFrame.size.width -= deltaX
            newFrame.size.height += deltaY
        case .bottomRight:
            newFrame.size.width += deltaX
            newFrame.origin.y += deltaY
            newFrame.size.height -= deltaY
        case .bottomLeft:
            newFrame.origin.x += deltaX
            newFrame.size.width -= deltaX
            newFrame.origin.y += deltaY
            newFrame.size.height -= deltaY
        case .none:
            break
        }
        
        // Apply min size
        if newFrame.size.width < minSize.width {
            if resizeEdge == .left || resizeEdge == .topLeft || resizeEdge == .bottomLeft {
                newFrame.origin.x = resizeStartFrame.maxX - minSize.width
            }
            newFrame.size.width = minSize.width
        }
        if newFrame.size.height < minSize.height {
            if resizeEdge == .bottom || resizeEdge == .bottomLeft || resizeEdge == .bottomRight {
                newFrame.origin.y = resizeStartFrame.maxY - minSize.height
            }
            newFrame.size.height = minSize.height
        }
        
        setFrame(newFrame, display: true)
    }
    
    // MARK: - Edge Detection
    
    private enum ResizeEdge {
        case none
        case top, bottom, left, right
        case topLeft, topRight, bottomLeft, bottomRight
    }
    
    private func detectEdge(at point: NSPoint) -> ResizeEdge {
        let frameRect = NSRect(origin: .zero, size: frame.size)
        
        let nearLeft = point.x < resizeThreshold
        let nearRight = point.x > frameRect.width - resizeThreshold
        let nearTop = point.y > frameRect.height - resizeThreshold
        let nearBottom = point.y < resizeThreshold
        
        // Corners first
        if nearTop && nearLeft { return .topLeft }
        if nearTop && nearRight { return .topRight }
        if nearBottom && nearLeft { return .bottomLeft }
        if nearBottom && nearRight { return .bottomRight }
        
        // Then edges
        if nearTop { return .top }
        if nearBottom { return .bottom }
        if nearLeft { return .left }
        if nearRight { return .right }
        
        return .none
    }
    
    private func cursor(for edge: ResizeEdge) -> NSCursor {
        switch edge {
        case .none:
            return .arrow
        case .left, .right:
            return .resizeLeftRight
        case .top, .bottom:
            return .resizeUpDown
        case .topLeft, .bottomRight:
            return Self.diagonalNWSECursor
        case .topRight, .bottomLeft:
            return Self.diagonalNESWCursor
        }
    }
    
    // MARK: - Diagonal Cursors
    
    private static let diagonalNWSECursor: NSCursor = {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1.5
            path.move(to: NSPoint(x: 2, y: 14))
            path.line(to: NSPoint(x: 14, y: 2))
            path.move(to: NSPoint(x: 2, y: 14))
            path.line(to: NSPoint(x: 2, y: 9))
            path.move(to: NSPoint(x: 2, y: 14))
            path.line(to: NSPoint(x: 7, y: 14))
            path.move(to: NSPoint(x: 14, y: 2))
            path.line(to: NSPoint(x: 14, y: 7))
            path.move(to: NSPoint(x: 14, y: 2))
            path.line(to: NSPoint(x: 9, y: 2))
            path.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 8, y: 8))
    }()
    
    private static let diagonalNESWCursor: NSCursor = {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1.5
            path.move(to: NSPoint(x: 14, y: 14))
            path.line(to: NSPoint(x: 2, y: 2))
            path.move(to: NSPoint(x: 14, y: 14))
            path.line(to: NSPoint(x: 14, y: 9))
            path.move(to: NSPoint(x: 14, y: 14))
            path.line(to: NSPoint(x: 9, y: 14))
            path.move(to: NSPoint(x: 2, y: 2))
            path.line(to: NSPoint(x: 2, y: 7))
            path.move(to: NSPoint(x: 2, y: 2))
            path.line(to: NSPoint(x: 7, y: 2))
            path.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 8, y: 8))
    }()
    
    // MARK: - Mouse Handling
    
    private var resizeEdge: ResizeEdge = .none
    private var resizeStartFrame: NSRect = .zero
    private var resizeStartMouse: NSPoint = .zero
    
    // Intercept events BEFORE they go to views
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            let windowPoint = event.locationInWindow
            let edge = resizingEnabled ? detectEdge(at: windowPoint) : .none
            
            if edge != .none {
                // Start resize - don't dispatch to views
                resizeEdge = edge
                resizeStartFrame = frame
                resizeStartMouse = convertPoint(toScreen: windowPoint)
                cursor(for: edge).set()
                return  // Don't call super - we're handling this
            }
            
        case .leftMouseDragged:
            if resizeEdge != .none {
                let windowPoint = event.locationInWindow
                let currentMouse = convertPoint(toScreen: windowPoint)
                performResize(to: currentMouse)
                return  // Don't call super
            }
            
        case .leftMouseUp:
            if resizeEdge != .none {
                resizeEdge = .none
                NSCursor.arrow.set()
                return  // Don't call super
            }
            
        default:
            break
        }
        
        super.sendEvent(event)
    }
    
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
