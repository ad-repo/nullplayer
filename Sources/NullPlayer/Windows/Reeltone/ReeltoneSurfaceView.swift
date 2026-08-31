import AppKit
import AVFoundation

protocol ReeltoneSurfaceViewDelegate: AnyObject {
    func reeltoneSurfaceViewDidRequestClose(_ view: ReeltoneSurfaceView)
    func reeltoneSurfaceViewDidRequestMinimise(_ view: ReeltoneSurfaceView)
    func reeltoneSurfaceView(_ view: ReeltoneSurfaceView, togglePanel name: String)
    func reeltoneSurfaceViewDidRequestLibraryBack(_ view: ReeltoneSurfaceView)
}

private final class ReeltoneAccessibilityElement: NSAccessibilityElement {
    var pressHandler: (() -> Void)?
    var incrementHandler: (() -> Void)?
    var decrementHandler: (() -> Void)?

    override func accessibilityPerformPress() -> Bool {
        guard let pressHandler else { return false }
        pressHandler()
        return true
    }

    override func accessibilityPerformIncrement() -> Bool {
        guard let incrementHandler else { return false }
        incrementHandler()
        return true
    }

    override func accessibilityPerformDecrement() -> Bool {
        guard let decrementHandler else { return false }
        decrementHandler()
        return true
    }
}

private final class ReeltoneRegionRenderView: NSView {
    weak var owner: ReeltoneSurfaceView?
    let regionIndex: Int

    init(regionIndex: Int, owner: ReeltoneSurfaceView) {
        self.regionIndex = regionIndex
        self.owner = owner
        super.init(frame: .zero)
        wantsLayer = true
        layer?.isOpaque = false
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) { owner?.drawRegion(index: regionIndex, dirtyRect: dirtyRect) }
}

final class ReeltoneSurfaceView: NSView {
    private struct HostedRegion {
        let regionIndex: Int
        let host: ReeltoneComponentHosting
    }

    let surface: ReeltoneSurface
    private let skin: ReeltoneLoadedSkin
    private let bridge: ReeltoneComponentBridging
    private let hostFactory: ReeltoneComponentHostFactory
    weak var delegate: ReeltoneSurfaceViewDelegate?

    private var hostedRegions: [HostedRegion] = []
    private var renderViews: [Int: ReeltoneRegionRenderView] = [:]
    private var hoveredRegionIndex: Int?
    private var pressedRegionIndex: Int?
    private var draggedRegionIndex: Int?
    private var focusedRegionIndex: Int?
    private var currentTrack: Track?
    private var currentTime: TimeInterval = 0
    private var currentDuration: TimeInterval = 0
    private var spectrum: [Float] = []
    private var artwork: NSImage?
    private var artworkLoadTask: Task<Void, Never>?
    private var animationTimer: Timer?
    private var spectrumInvalidationScheduled = false
    private var animationStart = CACurrentMediaTime()
    private var surfaceIsVisible = false
    private var accessibilityRegionElements: [Int: ReeltoneAccessibilityElement] = [:]
    private var attemptedFontResources = Set<String>()
    var invalidationObserver: ((Int?) -> Void)?

    var scale: CGFloat {
        guard surface.authoredSize.width > 0 else { return 1 }
        return bounds.width / CGFloat(surface.authoredSize.width)
    }

    init(
        surface: ReeltoneSurface,
        skin: ReeltoneLoadedSkin,
        bridge: ReeltoneComponentBridging,
        hostFactory: ReeltoneComponentHostFactory = .live
    ) {
        self.surface = surface
        self.skin = skin
        self.bridge = bridge
        self.hostFactory = hostFactory
        let size = NSSize(width: surface.authoredSize.width, height: surface.authoredSize.height)
        super.init(frame: NSRect(origin: .zero, size: size))
        wantsLayer = true
        layer?.isOpaque = false
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        setAccessibilityIdentifier("ReeltoneSurface.\(surface.id.rawValue)")
        setAccessibilityRole(.group)
        setAccessibilityLabel(surface.displayName)
        installRegions()
        updateAnimationTimer()
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        animationTimer?.invalidate()
        artworkLoadTask?.cancel()
    }

    var hostedRegionComponents: [ReeltoneComponent] {
        hostedRegions.map(\.host.component)
    }

    var isAnimationTimerRunning: Bool { animationTimer != nil }

    func hostedFrame(forRegionIndex index: Int) -> NSRect? {
        hostedRegions.first { $0.regionIndex == index }?.host.view.frame
    }

    override var isFlipped: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0, bounds.contains(point) else { return nil }
        let authored = ReeltoneAuthoredRect.topLeftPoint(
            fromAppKitPoint: point,
            surfaceHeight: surface.authoredSize.height,
            scale: Double(scale)
        )
        let coversDeclaredRegion = surface.regions.contains {
            $0.authoredRect.containsTopLeftPoint(
                x: authored.x,
                y: authored.y,
                clipShape: $0.manifestRegion.clipShape
            )
        }
        if coversDeclaredRegion {
            return super.hitTest(point) ?? self
        }

        guard let backgroundPath = ReeltoneControlArtSelector.resourcePath(
            in: surface.art,
            isPlaying: bridge.playbackState == .playing,
            isHovered: false,
            isPressed: false
        ) else { return self }
        let normalized = CGPoint(
            x: point.x / max(bounds.width, 1),
            y: (bounds.height - point.y) / max(bounds.height, 1)
        )
        guard (try? skin.containsVisiblePixel(
            in: backgroundPath,
            normalizedTopLeftPoint: normalized
        )) == false else {
            return super.hitTest(point) ?? self
        }
        return nil
    }

    override func layout() {
        super.layout()
        for hosted in hostedRegions {
            guard let region = surface.regions.first(where: { $0.index == hosted.regionIndex }) else { continue }
            let rect = region.authoredRect.appKitRect(
                surfaceHeight: surface.authoredSize.height,
                scale: Double(scale)
            )
            hosted.host.layout(in: rect)
            applyClip(to: hosted.host.view, shape: region.manifestRegion.clipShape)
        }
        for region in surface.regions {
            renderViews[region.index]?.frame = appKitRect(for: region)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(bounds)
        drawArt(surface.art, in: bounds, region: nil, context: context)
    }

    /// Produces a flattened surface image for printing, diagnostics, and acceptance snapshots.
    /// Drawing transparent region subviews separately can preserve holes in an offscreen bitmap;
    /// flattening through the same region renderer matches the on-screen layer composition.
    func renderFlattened(in context: CGContext) {
        context.clear(bounds)
        drawArt(surface.art, in: bounds, region: nil, context: context)
        for region in surface.regions where host(for: region) == nil {
            let rect = appKitRect(for: region)
            context.saveGState()
            clip(region.manifestRegion.clipShape, rect: rect, context: context)
            draw(region: region, in: rect, context: context)
            context.restoreGState()
        }
    }

    fileprivate func drawRegion(index: Int, dirtyRect: NSRect) {
        guard let region = surface.regions.first(where: { $0.index == index }),
              let renderView = renderViews[index],
              let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(renderView.bounds)
        context.saveGState()
        clip(region.manifestRegion.clipShape, rect: renderView.bounds, context: context)
        draw(region: region, in: renderView.bounds, context: context)
        context.restoreGState()
        if focusedRegionIndex == index {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            NSBezierPath(rect: renderView.bounds.insetBy(dx: 1, dy: 1)).stroke()
        }
    }

    func updatePlaybackState() {
        invalidateDynamicRegions(components: [.play, .pause, .playPause, .shuffle, .repeatMode])
        for region in surface.regions where ReeltoneControlArtSelector.changesWithPlayback(region.manifestRegion.art) {
            invalidateRegion(index: region.index)
        }
        if ReeltoneControlArtSelector.changesWithPlayback(surface.art) {
            invalidationObserver?(nil)
            needsDisplay = true
        }
        surface.regions
            .filter { $0.manifestRegion.frames != nil && $0.manifestRegion.drivenBy == .playback }
            .forEach { invalidateRegion(index: $0.index) }
        refreshAccessibilityElements()
        updateAnimationTimer()
    }

    func updateTime(current: TimeInterval, duration: TimeInterval) {
        currentTime = current
        currentDuration = duration
        invalidateDynamicRegions(components: [.elapsed, .duration, .seek])
        refreshAccessibilityElements()
    }

    func updateTrack(_ track: Track?) {
        currentTrack = track
        animationStart = CACurrentMediaTime()
        artwork = nil
        invalidateDynamicRegions(components: [.title, .artwork])
        loadArtwork(for: track)
        refreshAccessibilityElements()
        updateAnimationTimer()
    }

    func updateSpectrum(_ levels: [Float]) {
        spectrum = levels
        hostedRegions.forEach { $0.host.updateSpectrum(levels) }
        guard surfaceIsVisible, !spectrumInvalidationScheduled else { return }
        spectrumInvalidationScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.spectrumInvalidationScheduled = false
            guard self.surfaceIsVisible else { return }
            self.surface.regions
                .filter { $0.component == .visualiser && self.host(for: $0) == nil }
                .forEach { self.invalidateRegion(index: $0.index) }
        }
    }

    func visibilityDidChange(_ visible: Bool) {
        surfaceIsVisible = visible
        hostedRegions.forEach { $0.host.visibilityDidChange(visible) }
        updateAnimationTimer()
    }

    func updateTheme() {
        hostedRegions.forEach { $0.host.updateTheme() }
        renderViews.values.forEach { $0.needsDisplay = true }
        needsDisplay = true
    }

    func prepareForTeardown() {
        surfaceIsVisible = false
        animationTimer?.invalidate()
        animationTimer = nil
        artworkLoadTask?.cancel()
        artworkLoadTask = nil
        hostedRegions.forEach { $0.host.prepareForTeardown() }
        hostedRegions.removeAll()
        renderViews.values.forEach { $0.removeFromSuperview() }
        renderViews.removeAll()
        accessibilityRegionElements.removeAll()
    }

    func focusHostedComponent(_ component: ReeltoneComponent) -> Bool {
        guard let host = hostedRegions.lazy.map(\.host).first(where: { $0.component == component }) else { return false }
        host.focus()
        return true
    }

    override func mouseMoved(with event: NSEvent) {
        let old = hoveredRegionIndex
        hoveredRegionIndex = hitRegion(event)?.index
        invalidateRegion(index: old)
        invalidateRegion(index: hoveredRegionIndex)
    }

    override func mouseExited(with event: NSEvent) {
        let old = hoveredRegionIndex
        hoveredRegionIndex = nil
        invalidateRegion(index: old)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let region = hitRegion(event) else {
            window?.performDrag(with: event)
            return
        }
        window?.makeFirstResponder(self)
        focusedRegionIndex = region.index
        refreshAccessibilityElements()
        pressedRegionIndex = region.index
        draggedRegionIndex = [.seek, .volume].contains(region.component) ? region.index : nil
        updateContinuousControl(region, event: event)
        invalidateRegion(index: region.index)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let index = draggedRegionIndex,
              let region = surface.regions.first(where: { $0.index == index }) else { return }
        updateContinuousControl(region, event: event)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            invalidateRegion(index: pressedRegionIndex)
            pressedRegionIndex = nil
            draggedRegionIndex = nil
        }
        guard let pressed = pressedRegionIndex,
              let region = hitRegion(event), region.index == pressed else { return }
        perform(region.component, region: region)
    }

    override func keyDown(with event: NSEvent) {
        let interactive = surface.regions.filter(\.isInteractive)
        guard !interactive.isEmpty else { return super.keyDown(with: event) }
        if event.keyCode == 48 {
            let direction = event.modifierFlags.contains(.shift) ? -1 : 1
            let current = interactive.firstIndex { $0.index == focusedRegionIndex } ?? (direction > 0 ? -1 : 0)
            let next = (current + direction + interactive.count) % interactive.count
            invalidateRegion(index: focusedRegionIndex)
            focusedRegionIndex = interactive[next].index
            invalidateRegion(index: focusedRegionIndex)
            refreshAccessibilityElements()
            NSAccessibility.post(element: self, notification: .focusedUIElementChanged)
            return
        }
        guard let region = interactive.first(where: { $0.index == focusedRegionIndex }) ?? interactive.first else {
            return super.keyDown(with: event)
        }
        if event.keyCode == 36 || event.keyCode == 49 {
            perform(region.component, region: region)
            return
        }
        if [.seek, .volume].contains(region.component), (event.keyCode == 123 || event.keyCode == 124) {
            let direction: Double = event.keyCode == 124 ? 1 : -1
            adjustContinuousControl(region, direction: direction)
            return
        }
        super.keyDown(with: event)
    }

    override func accessibilityChildren() -> [Any]? {
        surface.regions.filter { $0.isInteractive || $0.isAccessibilityText }.map { region in
            let element: ReeltoneAccessibilityElement
            if let existing = accessibilityRegionElements[region.index] {
                element = existing
            } else {
                element = ReeltoneAccessibilityElement()
                element.pressHandler = { [weak self] in self?.perform(region.component, region: region) }
                if [.seek, .volume].contains(region.component) {
                    element.incrementHandler = { [weak self] in self?.adjustContinuousControl(region, direction: 1) }
                    element.decrementHandler = { [weak self] in self?.adjustContinuousControl(region, direction: -1) }
                }
                accessibilityRegionElements[region.index] = element
            }
            configureAccessibilityElement(element, for: region)
            return element
        }
    }

    private func adjustContinuousControl(_ region: ReeltoneSurfaceRegion, direction: Double) {
        if region.component == .volume {
            bridge.volume = Float(min(1, max(0, Double(bridge.volume) + direction * 0.05)))
        } else if region.component == .seek {
            bridge.seek(to: min(bridge.duration, max(0, bridge.currentTime + direction * max(1, bridge.duration * 0.02))))
        } else {
            return
        }
        invalidateRegion(index: region.index)
        refreshAccessibilityElements()
        NSAccessibility.post(element: self, notification: .valueChanged)
    }

    private func perform(_ component: ReeltoneComponent, region: ReeltoneSurfaceRegion) {
        switch component {
        case .play: bridge.play()
        case .pause: bridge.pause()
        case .playPause: bridge.playbackState == .playing ? bridge.pause() : bridge.play()
        case .stop: bridge.stop()
        case .prev: bridge.previous()
        case .next: bridge.next()
        case .shuffle: bridge.shuffleEnabled.toggle()
        case .repeatMode: bridge.repeatEnabled.toggle()
        case .close: delegate?.reeltoneSurfaceViewDidRequestClose(self)
        case .minimise: delegate?.reeltoneSurfaceViewDidRequestMinimise(self)
        case .togglePanel:
            if let panel = region.manifestRegion.panel { delegate?.reeltoneSurfaceView(self, togglePanel: panel) }
        case .libraryBack: delegate?.reeltoneSurfaceViewDidRequestLibraryBack(self)
        default: break
        }
        updatePlaybackState()
    }

    private func updateContinuousControl(_ region: ReeltoneSurfaceRegion, event: NSEvent) {
        guard region.component == .seek || region.component == .volume else { return }
        let point = convert(event.locationInWindow, from: nil)
        let rect = appKitRect(for: region)
        let fraction = ReeltoneControlMapping.fraction(
            point: point,
            in: rect,
            style: region.manifestRegion.controlStyle
        )
        if region.component == .volume {
            bridge.volume = Float(fraction)
        } else if bridge.duration > 0 {
            bridge.seek(to: Double(fraction) * bridge.duration)
        }
        invalidateRegion(index: region.index)
        refreshAccessibilityElements()
    }

    private func hitRegion(_ event: NSEvent) -> ReeltoneSurfaceRegion? {
        let point = convert(event.locationInWindow, from: nil)
        let authored = ReeltoneAuthoredRect.topLeftPoint(
            fromAppKitPoint: point,
            surfaceHeight: surface.authoredSize.height,
            scale: Double(scale)
        )
        return surface.hitRegion(atTopLeftX: authored.x, y: authored.y)
    }

    private func draw(region: ReeltoneSurfaceRegion, in rect: NSRect, context: CGContext) {
        let component = region.component
        if region.manifestRegion.frames != nil {
            drawAnimation(region, in: rect, context: context)
            return
        }
        if region.manifestRegion.art != nil && component != .seek && component != .volume {
            drawArt(region.manifestRegion.art!, in: rect, region: region, context: context)
            return
        }
        switch component {
        case .title:
            drawText(currentTrack.map { [$0.artist, $0.title].compactMap { $0 }.joined(separator: " — ") } ?? "", region: region, rect: rect)
        case .elapsed: drawText(formatTime(currentTime), region: region, rect: rect)
        case .duration: drawText(formatTime(currentDuration), region: region, rect: rect)
        case .artwork:
            artwork?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        case .visualiser: drawSpectrum(in: rect, color: color(region.manifestRegion.color) ?? .systemGreen, context: context)
        case .seek:
            drawControl(fraction: currentDuration > 0 ? currentTime / currentDuration : 0, region: region, rect: rect, context: context)
        case .volume: drawControl(fraction: Double(bridge.volume), region: region, rect: rect, context: context)
        case .decoration, .trackList, .equaliser, .library: break
        default: drawFallbackControl(component, region: region, rect: rect, context: context)
        }
    }

    private func drawArt(_ art: ReeltoneArt, in rect: NSRect, region: ReeltoneSurfaceRegion?, context: CGContext) {
        let isPlaying = bridge.playbackState == .playing
        let path = ReeltoneControlArtSelector.resourcePath(
            in: art,
            isPlaying: isPlaying,
            isHovered: region.map { hoveredRegionIndex == $0.index } ?? false,
            isPressed: region.map { pressedRegionIndex == $0.index } ?? false
        )
        guard let path, let image = image(path) else { return }
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
    }

    private func drawAnimation(_ region: ReeltoneSurfaceRegion, in rect: NSRect, context: CGContext) {
        guard let frames = region.manifestRegion.frames,
              let index = ReeltoneAnimationClock.frameIndex(
                frameCount: frames.count,
                fps: region.manifestRegion.fps ?? 12,
                elapsed: CACurrentMediaTime() - animationStart,
                driver: region.manifestRegion.drivenBy,
                isPlaying: bridge.playbackState == .playing
              ), let image = image(frames[index]) else { return }
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    private func drawText(_ value: String, region: ReeltoneSurfaceRegion, rect: NSRect) {
        let fontSize = CGFloat(region.manifestRegion.size ?? max(9, region.authoredRect.height * 0.65)) * scale
        let font = font(for: region.component, size: fontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = {
            switch region.manifestRegion.align ?? .left { case .left: return .left; case .center: return .center; case .right: return .right }
        }()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color(region.manifestRegion.color) ?? ReeltoneSkinEngine.shared.currentTheme.presentationSkin.textColor,
            .paragraphStyle: paragraph
        ]
        let text = value as NSString
        let measuredWidth = text.size(withAttributes: attributes).width
        if region.manifestRegion.marquee == true, measuredWidth > rect.width {
            let gap = 32 * scale
            let cycle = measuredWidth + gap
            let offset = CGFloat((CACurrentMediaTime() - animationStart) * 30 * Double(scale)).truncatingRemainder(dividingBy: cycle)
            let y = rect.midY - text.size(withAttributes: attributes).height / 2
            text.draw(at: NSPoint(x: rect.minX - offset, y: y), withAttributes: attributes)
            text.draw(at: NSPoint(x: rect.minX - offset + cycle, y: y), withAttributes: attributes)
        } else {
            text.draw(in: rect, withAttributes: attributes)
        }
    }

    private func drawSpectrum(in rect: NSRect, color: NSColor, context: CGContext) {
        guard !spectrum.isEmpty else { return }
        let count = min(spectrum.count, max(1, Int(rect.width / 3)))
        let barWidth = rect.width / CGFloat(count)
        context.setFillColor(color.cgColor)
        for index in 0..<count {
            let source = index * spectrum.count / count
            let value = CGFloat(min(1, max(0, spectrum[source])))
            context.fill(NSRect(x: rect.minX + CGFloat(index) * barWidth, y: rect.minY, width: max(1, barWidth - 1), height: rect.height * value))
        }
    }

    private func drawControl(fraction: Double, region: ReeltoneSurfaceRegion, rect: NSRect, context: CGContext) {
        let value = CGFloat(min(1, max(0, fraction)))
        let base = color(region.manifestRegion.color) ?? NSColor.white.withAlphaComponent(0.25)
        let highlight = color(region.manifestRegion.highlightColor) ?? ReeltoneSkinEngine.shared.currentTheme.presentationSkin.primaryColor
        let authoredImage: NSImage? = {
            guard let path = ReeltoneControlArtSelector.resourcePath(
                in: region.manifestRegion.art,
                isPlaying: bridge.playbackState == .playing,
                isHovered: hoveredRegionIndex == region.index,
                isPressed: pressedRegionIndex == region.index
            ) else { return nil }
            return image(path)
        }()
        switch region.manifestRegion.controlStyle ?? .bar {
        case .knob:
            if let authoredImage {
                authoredImage.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            } else {
                context.setFillColor(base.cgColor)
                context.fillEllipse(in: rect)
                context.setFillColor(highlight.cgColor)
                context.fillEllipse(in: rect.insetBy(dx: rect.width * 0.12, dy: rect.height * 0.12))
                let inset = rect.insetBy(dx: rect.width * 0.18, dy: rect.height * 0.18)
                let angle = CGFloat.pi * (0.75 + 1.5 * value)
                context.setStrokeColor(NSColor.black.cgColor)
                context.setLineWidth(max(1, 2 * scale))
                context.move(to: CGPoint(x: inset.midX, y: inset.midY))
                context.addLine(to: CGPoint(x: inset.midX + cos(angle) * inset.width * 0.4, y: inset.midY + sin(angle) * inset.height * 0.4))
                context.strokePath()
            }
        case .slider:
            let trackHeight = max(2 * scale, rect.height * 0.22)
            let track = NSRect(x: rect.minX, y: rect.midY - trackHeight / 2, width: rect.width, height: trackHeight)
            context.setFillColor(base.cgColor)
            context.fill(track)
            context.setFillColor(highlight.cgColor)
            context.fill(NSRect(x: track.minX, y: track.minY, width: track.width * value, height: track.height))
            if let authoredImage {
                let thumb = ReeltoneControlGeometry.sliderThumbRect(
                    in: rect,
                    authoredThumbSize: authoredImage.size,
                    scale: scale,
                    fraction: value
                )
                authoredImage.draw(in: thumb, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            } else {
                let thumbWidth = min(rect.height * 0.45, max(4 * scale, rect.width * 0.08))
                let thumb = NSRect(
                    x: min(rect.maxX - thumbWidth, max(rect.minX, rect.minX + rect.width * value - thumbWidth / 2)),
                    y: rect.minY,
                    width: thumbWidth,
                    height: rect.height
                )
                context.addPath(CGPath(roundedRect: thumb, cornerWidth: thumbWidth / 2, cornerHeight: thumbWidth / 2, transform: nil))
                context.fillPath()
            }
        case .bar:
            if let authoredImage {
                authoredImage.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            } else {
                context.setFillColor(base.cgColor)
                context.fill(rect)
            }
            context.setFillColor(highlight.cgColor)
            context.fill(NSRect(x: rect.minX, y: rect.minY, width: rect.width * value, height: rect.height))
        }
    }

    private func font(for component: ReeltoneComponent, size: CGFloat) -> NSFont {
        let source: ReeltoneFontSource?
        switch component {
        case .elapsed, .duration: source = skin.manifest.fonts?.digits
        case .title: source = skin.manifest.fonts?.display
        default: source = skin.manifest.fonts?.body
        }
        guard let source else { return NSFont.systemFont(ofSize: size) }

        if let builtin = source.builtin {
            if let exact = NSFont(name: builtin, size: size) { return exact }
            let weight: NSFont.Weight = builtin.hasSuffix("-Bold") ? .bold : .regular
            return component == .elapsed || component == .duration
                ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
                : NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        }

        if let path = source.file, let postScriptName = source.postScriptName {
            if !attemptedFontResources.contains(path) {
                attemptedFontResources.insert(path)
                try? skin.resources[path]?.registerFont(expectedPostScriptName: postScriptName)
            }
            if let registered = NSFont(name: postScriptName, size: size) { return registered }
        }
        return NSFont.systemFont(ofSize: size)
    }

    private func drawFallbackControl(_ component: ReeltoneComponent, region: ReeltoneSurfaceRegion, rect: NSRect, context: CGContext) {
        let active = (component == .shuffle && bridge.shuffleEnabled) || (component == .repeatMode && bridge.repeatEnabled)
        let fill = active ? NSColor.controlAccentColor : NSColor.black.withAlphaComponent(0.35)
        context.setFillColor(fill.cgColor)
        context.fillEllipse(in: rect)
        let labels: [ReeltoneComponent: String] = [.play: "▶", .pause: "Ⅱ", .playPause: bridge.playbackState == .playing ? "Ⅱ" : "▶", .stop: "■", .prev: "◀", .next: "▶", .shuffle: "S", .repeatMode: "R", .close: "×", .minimise: "–", .togglePanel: "+", .libraryBack: "‹"]
        let label = labels[component] ?? component.rawValue
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: max(9, rect.height * 0.45)), .foregroundColor: NSColor.white]
        let size = (label as NSString).size(withAttributes: attrs)
        (label as NSString).draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attrs)
    }

    private func installRegions() {
        for region in surface.regions {
            let host = region.ownsSingletonHost ? hostFactory.makeHost(region, appKitRect(for: region)) : nil
            if let host {
                hostedRegions.append(HostedRegion(regionIndex: region.index, host: host))
                addSubview(host.view)
                applyClip(to: host.view, shape: region.manifestRegion.clipShape)
            } else {
                let renderView = ReeltoneRegionRenderView(regionIndex: region.index, owner: self)
                renderView.frame = appKitRect(for: region)
                renderViews[region.index] = renderView
                addSubview(renderView)
            }
        }
    }

    private func host(for region: ReeltoneSurfaceRegion) -> ReeltoneComponentHosting? {
        guard region.ownsSingletonHost else { return nil }
        return hostedRegions.first { $0.regionIndex == region.index }?.host
    }

    private func appKitRect(for region: ReeltoneSurfaceRegion) -> NSRect {
        region.authoredRect.appKitRect(surfaceHeight: surface.authoredSize.height, scale: Double(scale))
    }

    private func applyClip(to view: NSView, shape: ReeltoneRegion.ClipShape?) {
        view.wantsLayer = true
        view.layer?.masksToBounds = true
        if shape == .ellipse {
            let mask = CAShapeLayer()
            mask.frame = view.bounds
            mask.path = CGPath(ellipseIn: view.bounds, transform: nil)
            view.layer?.mask = mask
        } else {
            view.layer?.mask = nil
        }
    }

    private func clip(_ shape: ReeltoneRegion.ClipShape?, rect: NSRect, context: CGContext) {
        if shape == .ellipse { context.addEllipse(in: rect) } else { context.addRect(rect) }
        context.clip()
    }

    private func image(_ path: String) -> NSImage? {
        try? skin.image(for: path)
    }

    private func color(_ value: String?) -> NSColor? {
        guard let value else { return nil }
        var hex = String(value.dropFirst())
        if hex.count == 6 { hex += "FF" }
        guard hex.count == 8, let raw = UInt64(hex, radix: 16) else { return nil }
        return NSColor(
            red: CGFloat((raw >> 24) & 0xff) / 255,
            green: CGFloat((raw >> 16) & 0xff) / 255,
            blue: CGFloat((raw >> 8) & 0xff) / 255,
            alpha: CGFloat(raw & 0xff) / 255
        )
    }

    private func formatTime(_ value: TimeInterval) -> String {
        guard value.isFinite, value >= 0 else { return "0:00" }
        return String(format: "%d:%02d", Int(value) / 60, Int(value) % 60)
    }

    private func accessibilityLabel(for component: ReeltoneComponent) -> String {
        switch component {
        case .play: return "Play"
        case .pause: return "Pause"
        case .playPause: return bridge.playbackState == .playing ? "Pause" : "Play"
        case .stop: return "Stop"
        case .prev: return "Previous"
        case .next: return "Next"
        case .seek: return "Seek"
        case .volume: return "Volume"
        case .shuffle: return bridge.shuffleEnabled ? "Shuffle On" : "Shuffle Off"
        case .repeatMode: return bridge.repeatEnabled ? "Repeat On" : "Repeat Off"
        case .close: return "Close \(surface.displayName)"
        case .minimise: return "Minimize \(surface.displayName)"
        case .togglePanel: return "Toggle Panel"
        case .libraryBack: return "Library Back"
        case .title: return "Track Title"
        case .elapsed: return "Elapsed Time"
        case .duration: return "Duration"
        default: return component.rawValue
        }
    }

    private func configureAccessibilityElement(
        _ element: ReeltoneAccessibilityElement,
        for region: ReeltoneSurfaceRegion
    ) {
        element.setAccessibilityIdentifier("ReeltoneRegion.\(surface.id.rawValue).\(region.index).\(region.component.rawValue)")
        element.setAccessibilityLabel(accessibilityLabel(for: region.component))
        if region.isAccessibilityText {
            element.setAccessibilityRole(.staticText)
            switch region.component {
            case .title:
                element.setAccessibilityValue(currentTrack.map { [$0.artist, $0.title].compactMap { $0 }.joined(separator: " — ") } ?? "")
            case .elapsed: element.setAccessibilityValue(formatTime(currentTime))
            case .duration: element.setAccessibilityValue(formatTime(currentDuration))
            default: break
            }
        } else {
            element.setAccessibilityRole([.seek, .volume].contains(region.component) ? .slider : .button)
        }
        element.setAccessibilityParent(self)
        element.setAccessibilityFocused(focusedRegionIndex == region.index)
        if let window {
            element.setAccessibilityFrame(window.convertToScreen(convert(appKitRect(for: region), to: nil)))
        }
        if region.component == .seek {
            element.setAccessibilityMinValue(NSNumber(value: 0))
            element.setAccessibilityMaxValue(NSNumber(value: 1))
            element.setAccessibilityValue(NSNumber(value: currentDuration > 0 ? currentTime / currentDuration : 0))
        } else if region.component == .volume {
            element.setAccessibilityMinValue(NSNumber(value: 0))
            element.setAccessibilityMaxValue(NSNumber(value: 1))
            element.setAccessibilityValue(NSNumber(value: bridge.volume))
        }
    }

    private func refreshAccessibilityElements() {
        for region in surface.regions where region.isInteractive || region.isAccessibilityText {
            guard let element = accessibilityRegionElements[region.index] else { continue }
            configureAccessibilityElement(element, for: region)
        }
    }

    private func invalidateDynamicRegions(components: Set<ReeltoneComponent>) {
        surface.regions.filter { components.contains($0.component) }.forEach { invalidateRegion(index: $0.index) }
    }

    private func invalidateRegion(index: Int?) {
        guard let index, let region = surface.regions.first(where: { $0.index == index }) else { return }
        invalidationObserver?(index)
        if let renderView = renderViews[index] {
            renderView.needsDisplay = true
        } else {
            host(for: region)?.view.needsDisplay = true
        }
    }

    private func updateAnimationTimer() {
        let activeRegions = surface.regions.filter { region in
            guard region.manifestRegion.frames != nil else { return false }
            switch region.manifestRegion.drivenBy ?? .always {
            case .always: return true
            case .playback: return bridge.playbackState == .playing
            case .never: return false
            }
        }
        let marqueeRegions = surface.regions.filter { marqueeNeedsAnimation($0) }
        let shouldAnimate = surfaceIsVisible && (!activeRegions.isEmpty || !marqueeRegions.isEmpty)
        if shouldAnimate, animationTimer == nil {
            let frameRate = activeRegions.map { $0.manifestRegion.fps ?? 12 }.max() ?? 1
            let refreshRate = min(60, max(marqueeRegions.isEmpty ? 1 : 30, frameRate))
            animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / refreshRate, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.surface.regions.filter { region in
                    guard region.manifestRegion.frames != nil else { return false }
                    switch region.manifestRegion.drivenBy ?? .always {
                    case .always: return true
                    case .playback: return self.bridge.playbackState == .playing
                    case .never: return false
                    }
                }.forEach { self.invalidateRegion(index: $0.index) }
                self.surface.regions.filter { self.marqueeNeedsAnimation($0) }
                    .forEach { self.invalidateRegion(index: $0.index) }
            }
        } else if !shouldAnimate {
            animationTimer?.invalidate()
            animationTimer = nil
        }
    }

    private func marqueeNeedsAnimation(_ region: ReeltoneSurfaceRegion) -> Bool {
        guard region.component == .title, region.manifestRegion.marquee == true else { return false }
        let value = currentTrack.map { [$0.artist, $0.title].compactMap { $0 }.joined(separator: " — ") } ?? ""
        let fontSize = CGFloat(region.manifestRegion.size ?? max(9, region.authoredRect.height * 0.65)) * scale
        let width = (value as NSString).size(withAttributes: [.font: font(for: .title, size: fontSize)]).width
        return width > appKitRect(for: region).width
    }

    private func loadArtwork(for track: Track?) {
        artworkLoadTask?.cancel()
        artworkLoadTask = nil
        guard let track else { return }
        artworkLoadTask = Task { [weak self] in
            var result: NSImage?
            if track.plexRatingKey != nil,
               let thumbPath = track.artworkThumb,
               let url = PlexManager.shared.artworkURL(thumb: thumbPath, size: 400) {
                result = await ReeltoneArtworkLoader.remoteArtwork(url: url)
            } else if let subsonicId = track.subsonicId,
                      let url = SubsonicManager.shared.coverArtURL(coverArtId: subsonicId, size: 400) {
                result = await ReeltoneArtworkLoader.remoteArtwork(url: url)
            } else if let jellyfinId = track.jellyfinId {
                result = await ReeltoneArtworkLoader.remoteArtwork(url: JellyfinManager.shared.imageURL(
                    itemId: jellyfinId,
                    imageTag: track.artworkThumb?.isEmpty == false ? track.artworkThumb : nil,
                    size: 400
                ))
            } else if let embyId = track.embyId {
                result = await ReeltoneArtworkLoader.remoteArtwork(url: EmbyManager.shared.imageURL(
                    itemId: embyId,
                    imageTag: track.artworkThumb?.isEmpty == false ? track.artworkThumb : nil,
                    size: 400
                ))
            } else if track.url.isFileURL {
                result = await ReeltoneArtworkLoader.localArtwork(url: track.url)
            } else if let artwork = track.artworkThumb, let url = URL(string: artwork), ["http", "https"].contains(url.scheme?.lowercased()) {
                result = await ReeltoneArtworkLoader.remoteArtwork(url: url)
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self?.currentTrack?.id == track.id else { return }
                self?.artwork = result
                self?.invalidateDynamicRegions(components: [.artwork])
            }
        }
    }
}

private enum ReeltoneArtworkLoader {
    static func remoteArtwork(url: URL?) async -> NSImage? {
        guard let url, !Task.isCancelled,
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return NSImage(data: data)
    }

    static func localArtwork(url: URL) async -> NSImage? {
        let asset = AVURLAsset(url: url)
        for format in [try? await asset.load(.metadata), try? await asset.loadMetadata(for: .id3Metadata), try? await asset.loadMetadata(for: .iTunesMetadata)] {
            guard let items = format else { continue }
            for item in items {
                guard item.commonKey == .commonKeyArtwork else { continue }
                if let data = try? await item.load(.dataValue), let image = NSImage(data: data) { return image }
            }
        }
        return nil
    }
}
