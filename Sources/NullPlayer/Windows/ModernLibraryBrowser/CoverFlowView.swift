import AppKit

/// A source-agnostic media item for the cover flow carousel. Both the modern/metal
/// (`ModernLibraryBrowserView`) and classic (`PlexBrowserView`) browsers build these from
/// whatever eligible library list they are currently showing.
struct CoverFlowItem {
    let id: String                          // stable identity for diffing/caching
    let title: String                       // display title
    let subtitle: String                    // secondary metadata
    let artwork: () -> NSImage?             // synchronous cache hit, if present
    let loadArtwork: () async -> NSImage?   // async per-source loader
    var isBack: Bool = false               // synthetic "‹ Back" cover for drill-out navigation
}

/// Theming for the cover flow overlay. Background is always clear so the Cava/art backdrop
/// shows through; callers supply text and placeholder colors from their active skin.
struct CoverFlowStyle {
    var titleColor: NSColor
    var subtitleColor: NSColor
    var placeholderFill: NSColor
    var placeholderTextColor: NSColor
    var reflectionStrength: CGFloat = 0.35

    static let fallback = CoverFlowStyle(
        titleColor: .white,
        subtitleColor: NSColor.white.withAlphaComponent(0.6),
        placeholderFill: NSColor(white: 0.16, alpha: 1),
        placeholderTextColor: NSColor.white.withAlphaComponent(0.5)
    )
}

/// A self-contained Core Animation cover-flow carousel: a 3D, horizontally-scrolling wall of
/// media artwork. Layer-backed so the covers are GPU-composited, leaving CPU headroom for the
/// Cava backdrop that renders behind this view. Hosted as a toggled overlay by each browser.
final class CoverFlowView: NSView {

    enum LabelPlacement {
        case bottomBand
        case belowCenteredCover
    }

    // MARK: Callbacks

    /// Fired when the centered cover changes (scroll, arrows, or clicking a side cover).
    var onCenterChanged: ((Int) -> Void)?
    /// Fired when the already-centered cover is clicked — activates that media item.
    var onActivate: ((Int) -> Void)?
    /// Fired once when navigation reaches the final preload window. Hosts use this to append the
    /// next page of a paginated library before the user reaches the final loaded cover.
    var onApproachingEnd: (() -> Void)?

    // MARK: Configuration

    var style: CoverFlowStyle = .fallback {
        didSet { rebuildLayers(); updateCenterLabel() }
    }

    /// Classic's taller, freely-resizable library window needs the label to follow the artwork;
    /// otherwise the shared bottom-band position can leave it detached at the window edge.
    var labelPlacement: LabelPlacement = .bottomBand {
        didSet { needsLayout = true }
    }

    private(set) var items: [CoverFlowItem] = []

    // MARK: Layout tuning

    /// Perspective foreshortening (smaller magnitude = flatter).
    private let perspective: CGFloat = -1.0 / 900.0
    /// Max Y rotation of a fully-turned side cover, in radians.
    private let maxAngle: CGFloat = 65 * .pi / 180
    /// Upper bound on covers laid out / loaded per side (keeps a very wide window's work bounded).
    private let maxRadius = 12
    /// Covers per side to lay out — enough to fill the window's width so a stretched window shows
    /// more of the fan (classic Cover Flow) rather than empty side margins. Cover size stays keyed
    /// to height, so wider means *more* covers, not bigger ones.
    private var virtualRadius: Int {
        let cover = coverSize
        guard cover > 0 else { return 6 }
        // Side covers stack ~cover*0.16 apart; count how many span the half-width, plus a margin.
        let approx = Int((bounds.width / 2) / (cover * 0.16)) + 1
        return min(max(approx, 5), maxRadius)
    }

    // MARK: State

    /// Fractional index of the centered cover; animates toward `targetOffset`.
    private var selectedOffset: CGFloat = 0
    private var targetOffset: CGFloat = 0
    private var centerIndex = 0

    private var animationTimer: Timer?

    private let containerLayer = CALayer()
    private let titleLayer = CATextLayer()
    private let subtitleLayer = CATextLayer()
    /// Bottom band reserved for the centered item's name/subtitle.
    private let labelAreaHeight: CGFloat = 46
    private var coverLayers: [Int: CoverLayer] = [:]
    private var loadedImages: [Int: NSImage] = [:]
    private var loadingIndices: Set<Int> = []
    /// Indices whose artwork load has been kicked off (or finished, image or nil). Prevents a
    /// cover that resolves to no artwork from re-launching its loader on every layout pass.
    private var attemptedIndices: Set<Int> = []
    /// Suppresses duplicate pagination requests while the host is rebuilding the same item set.
    private var lastApproachingEndItemCount: Int?

    // MARK: Init

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        var perspectiveTransform = CATransform3DIdentity
        perspectiveTransform.m34 = perspective
        containerLayer.sublayerTransform = perspectiveTransform
        containerLayer.backgroundColor = NSColor.clear.cgColor
        layer?.addSublayer(containerLayer)

        // Name + subtitle for the centered cover, shown in the reserved bottom band.
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        titleLayer.alignmentMode = .center
        titleLayer.truncationMode = .end
        titleLayer.contentsScale = scale
        titleLayer.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        titleLayer.fontSize = 15
        subtitleLayer.alignmentMode = .center
        subtitleLayer.truncationMode = .end
        subtitleLayer.contentsScale = scale
        subtitleLayer.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        subtitleLayer.fontSize = 12
        layer?.addSublayer(titleLayer)
        layer?.addSublayer(subtitleLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        animationTimer?.invalidate()
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Data

    /// Replace the carousel contents. Preserves the centered album by id when possible so a
    /// list refresh (source/search change) doesn't jump the user to a different cover.
    func setItems(_ newItems: [CoverFlowItem], preservingCenter: Bool = true) {
        let previousCenteredId = (centerIndex >= 0 && centerIndex < items.count) ? items[centerIndex].id : nil
        let previousFirstId = items.first?.id
        let previousLastId = items.last?.id
        let previousCount = items.count
        items = newItems

        // A replaced/cleared dataset starts a new pagination sequence. An appended page changes the
        // item count, which is already enough to permit the next request when its end is approached.
        if newItems.isEmpty || newItems.count <= previousCount &&
            (newItems.first?.id != previousFirstId || newItems.last?.id != previousLastId) {
            lastApproachingEndItemCount = nil
        }

        loadedImages.removeAll()
        loadingIndices.removeAll()
        attemptedIndices.removeAll()

        var newCenter = 0
        if preservingCenter, let previousCenteredId,
           let matched = newItems.firstIndex(where: { $0.id == previousCenteredId }) {
            newCenter = matched
        }
        newCenter = clampIndex(newCenter)
        centerIndex = newCenter
        selectedOffset = CGFloat(newCenter)
        targetOffset = CGFloat(newCenter)

        rebuildLayers()
        updateCenterLabel()
    }

    /// Update the name/subtitle shown beneath the carousel to the currently centered cover.
    private func updateCenterLabel() {
        guard centerIndex >= 0, centerIndex < items.count else {
            titleLayer.string = nil
            subtitleLayer.string = nil
            return
        }
        let item = items[centerIndex]
        titleLayer.string = item.isBack ? nil : item.title
        subtitleLayer.string = item.subtitle.isEmpty ? nil : item.subtitle
        titleLayer.foregroundColor = style.titleColor.cgColor
        subtitleLayer.foregroundColor = style.subtitleColor.cgColor
    }

    private func layoutCenterLabel() {
        let width = max(0, bounds.width - 32)
        let titleY: CGFloat
        let subtitleY: CGFloat
        switch labelPlacement {
        case .bottomBand:
            titleY = 22
            subtitleY = 5
        case .belowCenteredCover:
            let coverBottom = coverCenterY - coverSize / 2
            titleY = max(22, coverBottom - 24)
            subtitleY = max(5, titleY - 17)
        }
        titleLayer.frame = CGRect(x: 16, y: titleY, width: width, height: 20)
        subtitleLayer.frame = CGRect(x: 16, y: subtitleY, width: width, height: 16)
    }

    // MARK: Centering

    func setCenterIndex(_ index: Int, animated: Bool) {
        let clamped = clampIndex(index)
        guard clamped != centerIndex else {
            requestMoreItemsIfNeeded()
            return
        }
        centerIndex = clamped
        onCenterChanged?(clamped)
        updateCenterLabel()
        requestMoreItemsIfNeeded()
        targetOffset = CGFloat(clamped)
        if animated {
            startAnimation()
        } else {
            selectedOffset = targetOffset
            layoutCovers()
        }
    }

    private func clampIndex(_ index: Int) -> Int {
        guard !items.isEmpty else { return 0 }
        return min(max(index, 0), items.count - 1)
    }

    private func requestMoreItemsIfNeeded() {
        guard !items.isEmpty else { return }
        let threshold = min(10, max(1, items.count / 4))
        guard centerIndex >= items.count - threshold,
              lastApproachingEndItemCount != items.count else { return }
        lastApproachingEndItemCount = items.count
        onApproachingEnd?()
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        containerLayer.frame = bounds
        layoutCenterLabel()
        layoutCovers()
        CATransaction.commit()
    }

    private var coverSize: CGFloat {
        // Square album covers sized off the view (minus the reserved label band) so cover flow
        // scales with the window / UI size. Wider means more covers, not bigger ones.
        let usableHeight = max(0, bounds.height - labelAreaHeight)
        return max(80, min(usableHeight * 0.62, bounds.width * 0.5))
    }

    private var coverCenterY: CGFloat {
        labelAreaHeight + (bounds.height - labelAreaHeight) / 2 + coverSize * 0.10
    }

    /// Geometry for a cover at fractional distance `p` from the center (p = index - selectedOffset).
    private func geometry(for p: CGFloat) -> (x: CGFloat, z: CGFloat, angle: CGFloat) {
        let cover = coverSize
        let side: CGFloat = p == 0 ? 0 : (p > 0 ? 1 : -1)
        let absP = abs(p)
        let near = min(absP, 1)               // 0…1 as a cover approaches the flanking slot
        let far = max(absP - 1, 0)            // stacked distance beyond the flanking slot

        let focusGap = cover * 0.30           // spread of the two covers flanking center
        let stackGap = cover * 0.16           // tight spacing of stacked side covers

        let x = side * (cover * 0.5 * near + focusGap * near + far * stackGap)
        let z = -near * cover * 0.65 - far * cover * 0.04
        let angle = -side * maxAngle * near
        return (x, z, angle)
    }

    private func layoutCovers() {
        guard !items.isEmpty, bounds.width > 0 else { return }
        let cover = coverSize
        let centerX = bounds.midX
        // Center covers in the region above the reserved label band, nudged up for the reflection.
        let centerY = coverCenterY

        let lo = max(0, Int(selectedOffset.rounded()) - virtualRadius)
        let hi = min(items.count - 1, Int(selectedOffset.rounded()) + virtualRadius)

        // Remove layers that scrolled out of the virtual window.
        for (index, layer) in coverLayers where index < lo || index > hi {
            layer.removeFromSuperlayer()
            coverLayers.removeValue(forKey: index)
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        for index in lo...hi {
            let coverLayer = coverLayers[index] ?? makeCoverLayer(for: index)
            let p = CGFloat(index) - selectedOffset
            let g = geometry(for: p)

            coverLayer.bounds = CGRect(x: 0, y: 0, width: cover, height: cover)
            coverLayer.position = CGPoint(x: centerX + g.x, y: centerY)
            // Painter ordering: nearer covers (smaller |p|) draw on top.
            coverLayer.zPosition = g.z

            var transform = CATransform3DMakeTranslation(0, 0, g.z)
            transform = CATransform3DRotate(transform, g.angle, 0, 1, 0)
            coverLayer.transform = transform
            coverLayer.updateReflection(strength: style.reflectionStrength)
        }

        CATransaction.commit()

        // Load artwork center-out so the cover the user lands on fills in first.
        for index in (lo...hi).sorted(by: { abs(CGFloat($0) - selectedOffset) < abs(CGFloat($1) - selectedOffset) }) {
            ensureArtwork(for: index)
        }
    }

    // MARK: Cover layers

    private func makeCoverLayer(for index: Int) -> CoverLayer {
        let coverLayer = CoverLayer()
        coverLayer.contentsGravity = .resizeAspectFill
        coverLayer.masksToBounds = false
        // Cheap solid-color placeholder (a layer background) until artwork resolves — never an
        // NSImage.lockFocus bitmap, which is expensive per cover and was a source of main-thread hangs.
        coverLayer.setPlaceholderColor(style.placeholderFill.cgColor)
        if items[index].isBack {
            // The Back cover shows a text label (a single cheap CATextLayer) instead of artwork.
            coverLayer.setLabel(items[index].title, color: style.titleColor)
        } else if let image = loadedImages[index] {
            coverLayer.setImage(image)
        }
        containerLayer.addSublayer(coverLayer)
        coverLayers[index] = coverLayer
        return coverLayer
    }

    private func rebuildLayers() {
        for (_, layer) in coverLayers { layer.removeFromSuperlayer() }
        coverLayers.removeAll()
        needsLayout = true
        layoutCovers()
    }

    // MARK: Artwork

    private func ensureArtwork(for index: Int) {
        guard loadedImages[index] == nil, !attemptedIndices.contains(index) else { return }
        // Only load covers near the center to avoid a burst of network fetches.
        guard abs(CGFloat(index) - selectedOffset) <= CGFloat(virtualRadius) else { return }
        let item = items[index]

        if let cached = item.artwork() {
            apply(image: cached, to: index, fade: false)
            attemptedIndices.insert(index)
            return
        }

        // Mark attempted up front so a nil result never re-triggers a load on the next layout pass.
        attemptedIndices.insert(index)
        loadingIndices.insert(index)
        Task { [weak self] in
            let image = await item.loadArtwork()
            await MainActor.run {
                guard let self else { return }
                self.loadingIndices.remove(index)
                guard let image, index < self.items.count, self.items[index].id == item.id else { return }
                self.apply(image: image, to: index, fade: true)
            }
        }
    }

    private func apply(image: NSImage, to index: Int, fade: Bool) {
        loadedImages[index] = image
        guard let coverLayer = coverLayers[index] else { return }
        if fade {
            let transition = CATransition()
            transition.type = .fade
            transition.duration = 0.25
            coverLayer.add(transition, forKey: "contents")
            coverLayer.setImage(image)
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            coverLayer.setImage(image)
            CATransaction.commit()
        }
    }

    // MARK: Animation

    private func startAnimation() {
        guard animationTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.stepAnimation()
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    private func stepAnimation() {
        let delta = targetOffset - selectedOffset
        if abs(delta) < 0.001 {
            selectedOffset = targetOffset
            animationTimer?.invalidate()
            animationTimer = nil
        } else {
            selectedOffset += delta * 0.32
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layoutCovers()
        CATransaction.commit()
    }

    // MARK: Interaction

    override func scrollWheel(with event: NSEvent) {
        guard !items.isEmpty else { return }
        // Continuous 1:1 scrubbing, snapped to the nearest cover on release. Capping how far the
        // target can lead the rendered position keeps a momentum fling from shooting to the end and
        // outrunning artwork loads — the carousel stays able to keep up.
        let horizontalDelta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaX : event.deltaX
        let verticalDelta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY
        let dominantDelta = abs(horizontalDelta) > abs(verticalDelta) ? horizontalDelta : verticalDelta
        let sensitivity: CGFloat = event.hasPreciseScrollingDeltas ? 0.012 : 1.0
        let maxLead: CGFloat = 3
        var newTarget = targetOffset - dominantDelta * sensitivity
        newTarget = min(max(newTarget, selectedOffset - maxLead), selectedOffset + maxLead)
        targetOffset = min(max(newTarget, 0), CGFloat(items.count - 1))

        if !event.hasPreciseScrollingDeltas || event.phase == .ended ||
            event.momentumPhase == .ended || event.phase == .cancelled {
            targetOffset = targetOffset.rounded()
        }
        let newCenter = clampIndex(Int(targetOffset.rounded()))
        if newCenter != centerIndex {
            centerIndex = newCenter
            onCenterChanged?(newCenter)
            updateCenterLabel()
        }
        requestMoreItemsIfNeeded()
        startAnimation()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123: // left arrow
            setCenterIndex(centerIndex - 1, animated: true)
        case 124: // right arrow
            setCenterIndex(centerIndex + 1, animated: true)
        case 36, 76: // return / enter
            if !items.isEmpty { onActivate?(centerIndex) }
        default:
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard !items.isEmpty else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard let hit = coverIndex(at: point) else { return }
        if hit == centerIndex {
            onActivate?(hit)
        } else {
            setCenterIndex(hit, animated: true)
        }
    }

    /// Hit-test in view space: covers are checked front-to-back (nearest center first) so the
    /// visually-topmost cover under the click wins.
    private func coverIndex(at point: NSPoint) -> Int? {
        let cover = coverSize
        let centerX = bounds.midX
        let centerY = bounds.midY + cover * 0.12
        let indices = coverLayers.keys.sorted { abs(CGFloat($0) - selectedOffset) < abs(CGFloat($1) - selectedOffset) }
        for index in indices {
            let p = CGFloat(index) - selectedOffset
            let g = geometry(for: p)
            // Approximate the on-screen footprint; foreshorten side covers by their turn.
            let width = cover * (0.35 + 0.65 * (1 - min(abs(p), 1)))
            let rect = NSRect(x: centerX + g.x - width / 2, y: centerY - cover / 2,
                              width: width, height: cover)
            if rect.contains(point) { return index }
        }
        return nil
    }
}

// MARK: - CoverLayer

/// A single album cover with an attached, gradient-masked reflection. The reflection is a
/// sublayer so it shares the cover's 3D rotation.
private final class CoverLayer: CALayer {
    private let reflectionLayer = CALayer()
    private let reflectionMask = CAGradientLayer()

    override init() {
        super.init()
        reflectionLayer.contentsGravity = .resizeAspectFill
        reflectionLayer.transform = CATransform3DMakeScale(1, -1, 1)
        reflectionMask.colors = [
            NSColor(white: 1, alpha: 1).cgColor,
            NSColor(white: 1, alpha: 0).cgColor,
        ]
        reflectionMask.startPoint = CGPoint(x: 0.5, y: 1.0)
        reflectionMask.endPoint = CGPoint(x: 0.5, y: 0.4)
        reflectionLayer.mask = reflectionMask
        addSublayer(reflectionLayer)
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var placeholderColor: CGColor?
    private var textLayer: CATextLayer?

    /// Solid fill shown until artwork resolves (cheap — no bitmap rendering).
    func setPlaceholderColor(_ color: CGColor) {
        placeholderColor = color
        if contents == nil { backgroundColor = color }
    }

    func setImage(_ image: NSImage?) {
        let cgImage = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        contents = cgImage
        reflectionLayer.contents = cgImage
        // Once real artwork is shown, drop the placeholder fill so it doesn't tint transparent art.
        backgroundColor = cgImage == nil ? placeholderColor : nil
    }

    /// A centered text label (used for the synthetic Back cover). One cheap CATextLayer.
    func setLabel(_ text: String, color: NSColor) {
        let label = textLayer ?? {
            let l = CATextLayer()
            l.alignmentMode = .center
            l.truncationMode = .end
            l.isWrapped = true
            l.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
            addSublayer(l)
            textLayer = l
            return l
        }()
        label.string = text
        label.foregroundColor = color.cgColor
        label.fontSize = 30
    }

    func updateReflection(strength: CGFloat) {
        let reflectionHeight = bounds.height * 0.5
        // Reflection sits directly below the cover; the flip transform mirrors it downward.
        reflectionLayer.frame = CGRect(x: 0, y: -reflectionHeight, width: bounds.width, height: reflectionHeight)
        reflectionMask.frame = reflectionLayer.bounds
        reflectionLayer.opacity = Float(strength)
        if let textLayer {
            textLayer.frame = CGRect(x: 8, y: bounds.height / 2 - 24, width: bounds.width - 16, height: 48)
        }
    }
}
