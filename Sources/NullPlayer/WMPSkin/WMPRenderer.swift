import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct WMPRenderResult {
    let image: CGImage
    let renderMilliseconds: Double
    let backingScale: CGFloat
    let imageMetrics: WMPImageStoreMetrics
    let wasRenderedOnMainThread: Bool
}

struct WMPRenderDumpRecord: Codable {
    let viewID: String
    let pngFilename: String
    let canvasSize: WMPSize
    let resolvedNodeCount: Int
    let unresolvedNodeCount: Int
    let visibleBounds: WMPRect?
    let drawOrder: [Int]
    let diagnostics: [WMPDiagnostic]
    let peakCacheBytes: Int
    let renderMilliseconds: Double
    let backingScale: CGFloat
}

struct WMPRenderer: @unchecked Sendable {
    let imageStore: WMPImageStore

    /// `clock` is seconds since the scene was presented, and is the *only* thing that advances an
    /// animation. Keeping it here rather than in the scene means a 10 fps GIF costs a re-render and
    /// not a rebuild — a rebuild runs the skin's script transaction, which is not something to do
    /// ten times a second.
    func render(scene: WMPScene, backingScale: CGFloat = 1,
                clock: TimeInterval = 0) async throws -> WMPRenderResult {
        try await Task.detached(priority: .userInitiated) {
            try renderOffMain(scene: scene, backingScale: backingScale, clock: clock)
        }.value
    }

    /// What a repaint loop needs to drive this scene's animated artwork, and nothing more: the
    /// shortest frame delay anything in it uses, and the union of the frames that move. Answered
    /// from the image store, so a still scene costs one cached lookup per resource and returns nil.
    struct WMPAnimationCadence {
        let shortestDelay: TimeInterval
        /// Only the animated commands. Repainting the whole window at 10 fps for one blinking LED
        /// is the difference between a skin that animates and a skin that burns a core doing it.
        let bounds: WMPRect
        /// When every animation in the scene has played the number of times it asked for, or `nil`
        /// while any of them loops forever. A one-shot scene must stop repainting when its last
        /// frame lands, or the loop re-renders a still picture at the GIF's frame rate for as long
        /// as the view is open — `Halo 2`'s shutter is 34 frames of a 327x294 window.
        let endsAt: TimeInterval?
    }

    func animationCadence(for scene: WMPScene) -> WMPAnimationCadence? {
        var shortest: TimeInterval?
        var bounds: WMPRect?
        var endsAt: TimeInterval? = 0
        for command in scene.commands {
            guard case let .image(specification) = command.paint,
                  let animation = try? imageStore.animation(for: specification.resourcePath),
                  let delay = animation.delays.min() else { continue }
            shortest = min(shortest ?? delay, delay)
            let visible = command.clipRect.flatMap { command.frame.intersection($0) } ?? command.frame
            bounds = bounds.map { $0.union(visible) } ?? visible
            // One endless animation makes the whole scene endless; otherwise the scene stops when
            // its longest-running one does.
            if let end = animation.endOfPlayback, let running = endsAt {
                endsAt = max(running, end)
            } else {
                endsAt = nil
            }
        }
        guard let shortest, let bounds else { return nil }
        return WMPAnimationCadence(shortestDelay: shortest, bounds: bounds, endsAt: endsAt)
    }

    func dump(scene: WMPScene, to directory: URL, backingScale: CGFloat = 1,
              clock: TimeInterval = 0) async throws -> WMPRenderDumpRecord {
        try await Task.detached(priority: .userInitiated) {
            let result = try renderOffMain(scene: scene, backingScale: backingScale, clock: clock)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let safeID = scene.viewID.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" }
            // The clock is in the name only when it is non-zero, so every still dump keeps the
            // filename it has always had and a sweep comparison against an old capture still lines
            // up. An animated dump at two clocks writes two files instead of overwriting one.
            let atClock = clock > 0 ? "@t\(WMPNumber.format(CGFloat(clock)))" : ""
            let filename = "\(String(safeID))\(atClock)@\(WMPNumber.format(backingScale))x.png"
            let url = directory.appendingPathComponent(filename)
            guard let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                throw WMPFailure(WMPDiagnostic(.renderFailed, "Unable to create PNG destination."))
            }
            CGImageDestinationAddImage(destination, result.image, nil)
            guard CGImageDestinationFinalize(destination) else {
                throw WMPFailure(WMPDiagnostic(.renderFailed, "Unable to write '\(url.path)'."))
            }
            return WMPRenderDumpRecord(viewID: scene.viewID, pngFilename: filename,
                canvasSize: scene.canvasSize,
                resolvedNodeCount: scene.metrics.resolvedNodeCount,
                unresolvedNodeCount: scene.metrics.unresolvedNodeCount,
                visibleBounds: scene.metrics.visibleBounds,
                drawOrder: scene.commands.map(\.stableID), diagnostics: scene.diagnostics,
                peakCacheBytes: result.imageMetrics.peakCacheBytes,
                renderMilliseconds: result.renderMilliseconds, backingScale: backingScale)
        }.value
    }

    private func renderOffMain(scene: WMPScene, backingScale: CGFloat,
                               clock: TimeInterval = 0) throws -> WMPRenderResult {
        guard backingScale > 0, backingScale.isFinite,
              scene.canvasSize.width > 0, scene.canvasSize.height > 0 else {
            throw WMPFailure(WMPDiagnostic(.renderFailed, "Canvas and backing scale must be positive."))
        }
        let pixelWidth = Int(ceil(scene.canvasSize.width * backingScale))
        let pixelHeight = Int(ceil(scene.canvasSize.height * backingScale))
        let (pixels, overflow) = pixelWidth.multipliedReportingOverflow(by: pixelHeight)
        guard !overflow, pixels <= WMPPhase0Limits.imagePixels else {
            throw WMPFailure(WMPDiagnostic(.oversizedImage,
                "Render surface exceeds the \(WMPPhase0Limits.imagePixels)-pixel limit."))
        }
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight,
            bitsPerComponent: 8, bytesPerRow: pixelWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo) else {
            throw WMPFailure(WMPDiagnostic(.renderFailed, "Unable to allocate render surface."))
        }
        let started = CFAbsoluteTimeGetCurrent()
        context.clear(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.scaleBy(x: backingScale, y: backingScale)
        context.translateBy(x: 0, y: scene.canvasSize.height)
        context.scaleBy(x: 1, y: -1)

        for command in scene.commands {
            // `alphaBlend="0"` means invisible, and 717 of the corpus's 778 uses are exactly that.
            // Skipping the draw rather than setting alpha to zero saves the decode as well.
            guard command.alpha > 0 else { continue }
            context.saveGState()
            if command.alpha < 1 { context.setAlpha(command.alpha) }
            if let clip = command.clipRect { context.clip(to: clip.cgRect) }
            switch command.paint {
            case let .fill(color):
                context.setFillColor(red: CGFloat(color.red) / 255,
                    green: CGFloat(color.green) / 255, blue: CGFloat(color.blue) / 255, alpha: 1)
                context.fill(command.frame.cgRect)
            case let .image(specification):
                let frame = (try? imageStore.animation(for: specification.resourcePath))
                    .flatMap { $0?.frameIndex(at: clock) } ?? 0
                let decoded = try imageStore.image(for: specification.resourcePath,
                                                   colorKeys: specification.colorKeys,
                                                   implicitKey: specification.implicitColorKey,
                                                   frame: frame)
                let sourceImage = crop(specification.sourceRect, from: decoded.image)
                if let mappingMask = specification.mappingMask,
                   let mask = mappingMask.mapping.maskImage(for: Set(mappingMask.nodeIDs)) {
                    clip(to: command.frame, mask: mask, context: context)
                }
                // `clippingImage` shapes the element itself. Same counter-flip as every other mask:
                // the CTM is y-flipped in scene space and `clip(to:mask:)` maps the mask through it.
                if let path = specification.clippingMaskPath {
                    let mask = try imageStore.clippingMask(for: path,
                                                           keyedOut: specification.clippingMaskKeys)
                    clip(to: command.frame, mask: mask, context: context)
                }
                if specification.tiled {
                    context.clip(to: command.frame.cgRect)
                    let tileWidth = CGFloat(sourceImage.width), tileHeight = CGFloat(sourceImage.height)
                    if tileWidth > 0, tileHeight > 0 {
                        var y = command.frame.y
                        while y < command.frame.maxY {
                            var x = command.frame.x
                            while x < command.frame.maxX {
                                let tile = WMPRect(x: x, y: y, width: tileWidth, height: tileHeight)
                                setInterpolation(specification.interpolation, context: context)
                                drawImage(sourceImage, in: tile, context: context)
                                x += tileWidth
                            }
                            y += tileHeight
                        }
                    }
                } else {
                    setInterpolation(specification.interpolation, context: context)
                    drawImage(sourceImage, in: command.frame, context: context)
                }
            case let .text(text):
                draw(text, in: command.frame, context: context)
            }
            context.restoreGState()
        }
        guard let image = context.makeImage() else {
            throw WMPFailure(WMPDiagnostic(.renderFailed, "Unable to finalize render surface."))
        }
        return WMPRenderResult(image: image,
            renderMilliseconds: (CFAbsoluteTimeGetCurrent() - started) * 1_000,
            backingScale: backingScale, imageMetrics: imageStore.metrics,
            wasRenderedOnMainThread: Thread.isMainThread)
    }

    private func crop(_ rect: WMPRect?, from image: CGImage) -> CGImage {
        guard let rect else { return image }
        let imageRect = WMPRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
        guard let clipped = rect.intersection(imageRect) else { return image }
        let cgRect = CGRect(x: clipped.x, y: clipped.y,
                            width: clipped.width, height: clipped.height)
        return image.cropping(to: cgRect) ?? image
    }

    /// Quartz images use the opposite vertical basis from our already top-left-flipped scene CTM.
    /// Reflect around the destination's own horizontal center so its geometry stays put and pixels
    /// remain upright.
    /// `clip(to:mask:)` maps the mask through the current CTM, which in scene space is y-flipped,
    /// so a mapping mask whose row zero is the authored top row landed mirrored: pressing the top
    /// button of a BUTTONGROUP lit the bottom one. Apply the counter-flip `drawImage` uses. The clip
    /// is resolved at the call, so undoing the transform afterwards leaves the region correct —
    /// which is why this cannot use save/restore, as restoring would drop the clip with it.
    private func clip(to frame: WMPRect, mask: CGImage, context: CGContext) {
        let centerY = frame.y + frame.height / 2
        context.translateBy(x: 0, y: centerY)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: -centerY)
        context.clip(to: frame.cgRect, mask: mask)
        context.translateBy(x: 0, y: centerY)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: -centerY)
    }

    private func drawImage(_ image: CGImage, in frame: WMPRect, context: CGContext) {
        let centerY = frame.y + frame.height / 2
        context.saveGState()
        context.translateBy(x: 0, y: centerY)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: -centerY)
        context.draw(image, in: frame.cgRect)
        context.restoreGState()
    }

    private func setInterpolation(_ policy: WMPImageInterpolation, context: CGContext) {
        switch policy {
        case .none: context.interpolationQuality = .none
        case .low: context.interpolationQuality = .low
        case .medium: context.interpolationQuality = .medium
        case .high: context.interpolationQuality = .high
        }
    }

    private func draw(_ text: WMPSceneText, in frame: WMPRect, context: CGContext) {
        // `fontStyle` is a space- or comma-separated set, not one word: the corpus writes
        // "bold underline" and "UNDERLINE, bold" as well as each alone. Bold and italic are a face
        // request; underline is a decoration CoreText draws for us.
        var suffix = ""
        if text.bold { suffix += " Bold" }
        if text.italic { suffix += " Italic" }
        let font = CTFontCreateWithName((text.fontName + suffix) as CFString, text.fontSize, nil)
        let color = CGColor(red: CGFloat(text.color.red) / 255,
            green: CGFloat(text.color.green) / 255, blue: CGFloat(text.color.blue) / 255, alpha: 1)
        var attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
        ]
        if text.underline {
            attributes[NSAttributedString.Key(kCTUnderlineStyleAttributeName as String)] =
                CTUnderlineStyle.single.rawValue
        }
        // `fontSmoothing="false"` is a readout the skin drew as pixels; antialiasing it turns a
        // 6 px digit into grey mush.
        context.setShouldAntialias(text.smoothed)
        context.setShouldSmoothFonts(text.smoothed)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text.value,
                                                                        attributes: attributes))
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let x: CGFloat
        switch text.alignment {
        case .left: x = frame.x
        case .center: x = frame.x + max(0, (frame.width - width) / 2)
        case .right: x = frame.maxX - min(frame.width, width)
        }
        let baseline = frame.y + max(text.fontSize, (frame.height + text.fontSize) / 2)
        let centerY = frame.y + frame.height / 2
        context.saveGState()
        context.translateBy(x: 0, y: centerY)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: -centerY)
        context.textPosition = CGPoint(x: x, y: baseline)
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
