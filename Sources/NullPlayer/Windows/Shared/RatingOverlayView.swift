import AppKit

/// Semi-transparent glass-style star rating overlay for rating Plex tracks
class RatingOverlayView: NSView {
    
    var onRatingSelected: ((Int) -> Void)?
    var onDismiss: (() -> Void)?
    
    private var hoveredStar: Int = 0
    private var selectedRating: Int = 0
    private let starCount = 5
    /// 48 pt, shrunk to keep the panel (stars, gaps and 20 pt padding each side) inside a narrow view.
    private var starSize: CGFloat {
        min(48, max(12, (bounds.width - 40 - 8 - CGFloat(starCount - 1) * starSpacing) / CGFloat(starCount)))
    }
    private let starSpacing: CGFloat = 12
    
    override init(frame: NSRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        wantsLayer = true
        // Semi-transparent dark background for the full overlay
        layer?.backgroundColor = NSColor(white: 0, alpha: 0.5).cgColor
    }
    
    func setRating(_ rating: Int) {
        // rating is on Plex 0-10 scale, convert to 1-5 stars
        selectedRating = rating / 2
        needsDisplay = true
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // Calculate centered position for star container
        let totalWidth = CGFloat(starCount) * starSize + CGFloat(starCount - 1) * starSpacing
        let containerWidth = totalWidth + 40  // padding
        let containerHeight = starSize + 40
        let containerX = (bounds.width - containerWidth) / 2
        let containerY = (bounds.height - containerHeight) / 2
        let containerRect = NSRect(x: containerX, y: containerY, width: containerWidth, height: containerHeight)
        
        // Draw frosted glass background for star container
        context.saveGState()
        let path = NSBezierPath(roundedRect: containerRect, xRadius: 16, yRadius: 16)
        NSColor(white: 1.0, alpha: 0.15).setFill()
        path.fill()
        
        // Draw subtle border
        NSColor(white: 1.0, alpha: 0.3).setStroke()
        path.lineWidth = 1
        path.stroke()
        context.restoreGState()
        
        // Draw stars
        let startX = containerX + 20
        let starY = containerY + 20
        
        for i in 0..<starCount {
            let starX = startX + CGFloat(i) * (starSize + starSpacing)
            let starRect = NSRect(x: starX, y: starY, width: starSize, height: starSize)
            
            let starNumber = i + 1
            let isFilled = starNumber <= max(hoveredStar, selectedRating)
            let isHovered = starNumber <= hoveredStar && hoveredStar > 0
            
            drawStar(in: starRect, filled: isFilled, hovered: isHovered, context: context)
        }
    }
    
    private func drawStar(in rect: NSRect, filled: Bool, hovered: Bool, context: CGContext) {
        // Star path (5-pointed star)
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let outerRadius = rect.width / 2
        let innerRadius = outerRadius * 0.4
        
        let path = NSBezierPath()
        for i in 0..<10 {
            let radius = i % 2 == 0 ? outerRadius : innerRadius
            // Start at the top point so stars render upright in AppKit coordinates.
            let angle = CGFloat(i) * .pi / 5 + .pi / 2
            let point = NSPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
            if i == 0 {
                path.move(to: point)
            } else {
                path.line(to: point)
            }
        }
        path.close()
        
        // Glass effect colors
        if filled {
            // Filled star: warm gold (slightly brighter on hover).
            (hovered
                ? NSColor(calibratedRed: 1.00, green: 0.86, blue: 0.28, alpha: 0.98)
                : NSColor(calibratedRed: 0.98, green: 0.78, blue: 0.20, alpha: 0.92)
            ).setFill()
        } else {
            // Empty star: dim gold glass fill.
            NSColor(calibratedRed: 0.75, green: 0.63, blue: 0.30, alpha: 0.22).setFill()
        }
        path.fill()
        
        // Gold-tinted outline for both filled and empty states.
        (filled
            ? NSColor(calibratedRed: 1.00, green: 0.90, blue: 0.45, alpha: 0.85)
            : NSColor(calibratedRed: 0.86, green: 0.72, blue: 0.35, alpha: 0.45)
        ).setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }
    
    // MARK: - Mouse Handling
    
    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        hoveredStar = starAtPoint(point)
        needsDisplay = true
    }
    
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let clickedStar = starAtPoint(point)

        if clickedStar > 0 {
            selectedRating = clickedStar
            needsDisplay = true
            // Convert 1-5 stars to Plex 0-10 scale (each star = 2 points)
            onRatingSelected?(clickedStar * 2)
        } else {
            // Clicked outside stars - dismiss
            onDismiss?()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        // Consume drag events to prevent them from propagating to the parent view,
        // which would otherwise interpret the drag as a window move (when Hide Title Bars is on).
    }

    private func starAtPoint(_ point: NSPoint) -> Int {
        let totalWidth = CGFloat(starCount) * starSize + CGFloat(starCount - 1) * starSpacing
        let containerWidth = totalWidth + 40
        let containerHeight = starSize + 40
        let containerX = (bounds.width - containerWidth) / 2
        let containerY = (bounds.height - containerHeight) / 2
        let startX = containerX + 20
        let starY = containerY + 20
        
        for i in 0..<starCount {
            let starX = startX + CGFloat(i) * (starSize + starSpacing)
            let starRect = NSRect(x: starX, y: starY, width: starSize, height: starSize)
            if starRect.contains(point) {
                return i + 1
            }
        }
        return 0
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        ))
    }
}

