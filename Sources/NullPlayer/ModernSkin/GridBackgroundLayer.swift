import AppKit
import QuartzCore

/// CALayer subclass that draws a configurable grid background pattern.
/// Supports perspective (vanishing point) for Tron-style grids.
class GridBackgroundLayer: CALayer {
    
    // MARK: - Properties
    
    /// Grid line color
    var gridColor: NSColor = NSColor.from(hex: "#0a2a2a") {
        didSet { setNeedsDisplay() }
    }
    
    /// Grid line spacing in points
    var spacing: CGFloat = 20.0 {
        didSet { setNeedsDisplay() }
    }
    
    /// Grid angle in degrees (0 = horizontal, 90 = vertical, 75 = angled like Tron)
    var angle: CGFloat = 75.0 {
        didSet { setNeedsDisplay() }
    }
    
    /// Grid line opacity
    var gridOpacity: CGFloat = 0.15 {
        didSet { setNeedsDisplay() }
    }
    
    /// Enable perspective effect (vanishing point at top)
    var perspectiveEnabled: Bool = true {
        didSet { setNeedsDisplay() }
    }
    
    /// Grid line width
    var lineWidth: CGFloat = 0.5 {
        didSet { setNeedsDisplay() }
    }
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        needsDisplayOnBoundsChange = true
        contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        setNeedsDisplay()
    }
    
    override init(layer: Any) {
        super.init(layer: layer)
        if let grid = layer as? GridBackgroundLayer {
            self.gridColor = grid.gridColor
            self.spacing = grid.spacing
            self.angle = grid.angle
            self.gridOpacity = grid.gridOpacity
            self.perspectiveEnabled = grid.perspectiveEnabled
            self.lineWidth = grid.lineWidth
        }
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        needsDisplayOnBoundsChange = true
    }
    
    // MARK: - Drawing
    
    override func draw(in ctx: CGContext) {
        let rect = bounds
        guard rect.width > 0, rect.height > 0 else { return }
        
        ctx.saveGState()
        
        let color = gridColor.withAlphaComponent(gridOpacity).cgColor
        ctx.setStrokeColor(color)
        ctx.setLineWidth(lineWidth)
        
        if perspectiveEnabled {
            drawPerspectiveGrid(in: rect, context: ctx)
        } else {
            drawFlatGrid(in: rect, context: ctx)
        }
        
        ctx.restoreGState()
    }
    
    // MARK: - Flat Grid
    
    private func drawFlatGrid(in rect: NSRect, context: CGContext) {
        let angleRad = angle * .pi / 180.0
        
        // Horizontal lines
        var y = rect.minY
        while y <= rect.maxY {
            context.move(to: CGPoint(x: rect.minX, y: y))
            context.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += spacing
        }
        context.strokePath()
        
        // Angled lines
        let dx = cos(angleRad)
        let dy = sin(angleRad)
        let diagonal = sqrt(rect.width * rect.width + rect.height * rect.height)
        
        var offset: CGFloat = -diagonal
        while offset <= diagonal {
            let startX = rect.midX + offset
            context.move(to: CGPoint(x: startX - dx * diagonal, y: rect.minY - dy * diagonal))
            context.addLine(to: CGPoint(x: startX + dx * diagonal, y: rect.minY + dy * diagonal))
            offset += spacing
        }
        context.strokePath()
    }
    
    // MARK: - Perspective Grid (Tron-style)
    
    private func drawPerspectiveGrid(in rect: NSRect, context: CGContext) {
        // Vanishing point at top-center
        let vanishX = rect.midX
        let vanishY = rect.maxY + rect.height * 0.5
        
        // Draw horizontal lines with perspective (closer together near top)
        let numHLines = Int(rect.height / spacing) + 2
        for i in 0...numHLines {
            // Exponential spacing for perspective effect
            let t = CGFloat(i) / CGFloat(numHLines)
            let perspT = t * t  // Quadratic for perspective compression
            let y = rect.minY + perspT * rect.height
            
            // Fade out lines near top
            let alpha = gridOpacity * (0.3 + 0.7 * t)
            context.setStrokeColor(gridColor.withAlphaComponent(alpha).cgColor)
            
            context.move(to: CGPoint(x: rect.minX, y: y))
            context.addLine(to: CGPoint(x: rect.maxX, y: y))
            context.strokePath()
        }
        
        // Draw converging vertical lines toward vanishing point
        let numVLines = Int(rect.width / spacing) + 1
        let halfLines = numVLines / 2
        
        context.setStrokeColor(gridColor.withAlphaComponent(gridOpacity).cgColor)
        
        for i in -halfLines...halfLines {
            let bottomX = rect.midX + CGFloat(i) * spacing
            
            // Lines converge toward vanishing point
            context.move(to: CGPoint(x: bottomX, y: rect.minY))
            context.addLine(to: CGPoint(x: vanishX, y: vanishY))
            context.strokePath()
        }
    }
    
    // MARK: - Configuration from Skin
    
    /// Configure from a modern skin's background config
    func configure(with config: GridConfig) {
        gridColor = NSColor.from(hex: config.color)
        spacing = config.spacing
        angle = config.angle
        gridOpacity = config.opacity
        perspectiveEnabled = config.perspective ?? false
        setNeedsDisplay()
    }
}
