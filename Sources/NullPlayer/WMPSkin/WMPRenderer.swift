import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct WMPRenderResult {
    let image: CGImage
    /// The artwork a skin draws *over* its effects surface, when it has one: everything from
    /// `WMPScene.effectsCommandSplitIndex` onwards, on a transparent canvas of the same size.
    /// Nil for every scene without an `<EFFECTS>` widget, where `image` is the whole picture and
    /// the output is byte-identical to a single-layer render.
    ///
    /// This is what makes a negative `zIndex` mean what WMP means by it — Cerulean's `face.bmp`
    /// with its 73px keyed-out hole composites over the visualizer, rather than the visualizer
    /// covering the bezel — without any shape fitting in the surface view itself.
    let overlayImage: CGImage?
    let renderMilliseconds: Double
    let backingScale: CGFloat
    let imageMetrics: WMPImageStoreMetrics
    let wasRenderedOnMainThread: Bool

    init(image: CGImage, overlayImage: CGImage? = nil, renderMilliseconds: Double,
         backingScale: CGFloat, imageMetrics: WMPImageStoreMetrics,
         wasRenderedOnMainThread: Bool) {
        self.image = image
        self.overlayImage = overlayImage
        self.renderMilliseconds = renderMilliseconds
        self.backingScale = backingScale
        self.imageMetrics = imageMetrics
        self.wasRenderedOnMainThread = wasRenderedOnMainThread
    }
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
                clock: TimeInterval = 0,
                slotClocks: [WMPAnimationSlot: TimeInterval] = [:]) async throws -> WMPRenderResult {
        try await Task.detached(priority: .userInitiated) {
            try renderOffMain(scene: scene, backingScale: backingScale, clock: clock,
                              slotClocks: slotClocks)
        }.value
    }

    /// What a repaint loop needs to drive this scene's animated artwork, and nothing more: the
    /// shortest frame delay anything in it uses, and the union of the frames that move. Answered
    /// from the image store, so a still scene costs one cached lookup per resource and returns nil.
    /// **One animated image in one place in the scene — the thing that owns an animation clock.**
    ///
    /// An animation belongs to the *slot* it is drawn in, not to the view it is drawn in (W182).
    /// A skin animates by assigning a new GIF to an element it already drew — `AlienMorph`'s
    /// `toggleShutter()` writes `shutterSub.backgroundImage` a second after the view loaded — and a
    /// clock shared by the whole view starts that GIF wherever the view had already got to, which
    /// is anywhere from "a second in" to "past its last frame".
    ///
    /// The identity is the node **and** the resource, and both halves are load-bearing. The node
    /// alone would keep the old epoch when the script swapped the image, which is the defect. The
    /// resource alone would make two elements drawing the same GIF share one clock, and would
    /// restart the animation whenever a rebuild moved it between nodes. Together they mean: the
    /// same picture in the same place keeps running, and anything else is a new animation starting
    /// now — which is also what makes a rebuild free, since a scene rebuilt with no change produces
    /// exactly the same slots (W142's no-flicker property).
    struct WMPAnimationSlot: Hashable {
        let stableID: Int
        let resourcePath: String

        init(stableID: Int, resourcePath: String) {
            self.stableID = stableID
            self.resourcePath = resourcePath
        }
    }

    struct WMPAnimationCadence: Equatable {
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

    /// Every animated image in the scene, by slot, with the animation it is playing.
    ///
    /// The caller owns the epochs — this only says what there is to clock. A slot appears once even
    /// if the same command is rasterized into both layers of a split scene, because the key is the
    /// node and the resource rather than the draw.
    func animatedSlots(in scene: WMPScene) -> [WMPAnimationSlot: WMPImageAnimation] {
        var slots: [WMPAnimationSlot: WMPImageAnimation] = [:]
        for command in scene.commands {
            guard case let .image(specification) = command.paint,
                  let animation = try? imageStore.animation(for: specification.resourcePath)
            else { continue }
            slots[WMPAnimationSlot(stableID: command.stableID,
                                   resourcePath: specification.resourcePath)] = animation
        }
        return slots
    }

    func animationCadence(for scene: WMPScene) -> WMPAnimationCadence? {
        var shortest: TimeInterval?
        var bounds: WMPRect?
        var endsAt: TimeInterval? = 0
        for command in scene.commands {
            let visible = command.clipRect.flatMap { command.frame.intersection($0) } ?? command.frame
            // A marquee is an animation like any other, and it is the only one a skin turns on from
            // script rather than by naming a GIF. It never ends while it is on, so it makes the
            // scene endless — and its bounds are its own box, which is why the repaint stays cheap.
            if case let .text(text) = command.paint, text.scrolling,
               WMPTextMetrics.width(of: text.value, fontName: text.fontName,
                                    fontSize: text.fontSize, bold: text.bold,
                                    italic: text.italic) > command.frame.width {
                let delay = text.effectiveScrollDelayMilliseconds / 1_000
                shortest = min(shortest ?? delay, delay)
                bounds = bounds.map { $0.union(visible) } ?? visible
                endsAt = nil
                continue
            }
            guard case let .image(specification) = command.paint,
                  let animation = try? imageStore.animation(for: specification.resourcePath),
                  let delay = animation.delays.min() else { continue }
            shortest = min(shortest ?? delay, delay)
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
            let result = try renderOffMain(scene: scene, backingScale: backingScale, clock: clock,
                                           splitAtEffects: false)
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

    /// `splitAtEffects` is false for a render dump: a dump is a flat picture of the skin's
    /// artwork, the effects surface is an AppKit overlay that never appears in one, and splitting
    /// the list there would drop everything above the visualizer out of the PNG. Every dump stays
    /// byte-identical to what it was before the split existed.
    private func renderOffMain(scene: WMPScene, backingScale: CGFloat,
                               clock: TimeInterval = 0,
                               slotClocks: [WMPAnimationSlot: TimeInterval] = [:],
                               splitAtEffects: Bool = true) throws -> WMPRenderResult {
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
        let started = CFAbsoluteTimeGetCurrent()
        // A scene that hosts an `<EFFECTS>` is rasterized as two layers: everything the walk
        // reached before the effects node, and everything after it. The surface view is hosted
        // between them, which is the whole of the z-order fix — the skin's own artwork occludes
        // the visualizer exactly where it declares it does. With no effects widget there is no
        // split and this is one pass over the same list as before.
        let split = splitAtEffects ? scene.effectsCommandSplitIndex : nil
        let below = split.map { Array(scene.commands[..<$0]) } ?? scene.commands
        // **The visualizer's own backdrop goes under the below layer, never over it** — so a skin
        // that paints its own ground behind the rect still covers this completely and renders
        // byte-identically, and one that paints nothing there stops being a hole (W174). It is
        // drawn whether or not the list is split, because it is the *skin's* backdrop and not the
        // hosted surface: a flat render dump has to show it, and that is what makes this class the
        // rare one a corpus sweep can arbitrate. See `WMPEffectsGround`.
        let image = try rasterize(below, scene: scene, pixelWidth: pixelWidth,
                                  pixelHeight: pixelHeight, backingScale: backingScale, clock: clock,
                                  slotClocks: slotClocks, grounds: scene.effectsGrounds)
        // **A windowed visualization is not something the skin can draw over.** Its rects are
        // punched out of the overlay after it is rasterized, so the surface hosted underneath shows
        // through and whatever the skin painted *before* the effects node stands where the
        // visualization is idle. See `WMPScene.windowedEffectsRects` (W144).
        let overlay = try split.map {
            try rasterize(Array(scene.commands[$0...]), scene: scene, pixelWidth: pixelWidth,
                          pixelHeight: pixelHeight, backingScale: backingScale, clock: clock,
                          slotClocks: slotClocks, punchingOut: scene.windowedEffectsRects)
        }
        return WMPRenderResult(image: image, overlayImage: overlay,
            renderMilliseconds: (CFAbsoluteTimeGetCurrent() - started) * 1_000,
            backingScale: backingScale, imageMetrics: imageStore.metrics,
            wasRenderedOnMainThread: Thread.isMainThread)
    }

    /// One layer of the scene, on its own transparent canvas.
    private func rasterize(_ commands: [WMPPaintCommand], scene: WMPScene,
                           pixelWidth: Int, pixelHeight: Int, backingScale: CGFloat,
                           clock: TimeInterval,
                           slotClocks: [WMPAnimationSlot: TimeInterval] = [:],
                           punchingOut: [WMPRect] = [],
                           grounds: [WMPEffectsGround] = []) throws -> CGImage {
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight,
            bitsPerComponent: 8, bytesPerRow: pixelWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo) else {
            throw WMPFailure(WMPDiagnostic(.renderFailed, "Unable to allocate render surface."))
        }
        context.clear(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.scaleBy(x: backingScale, y: backingScale)
        context.translateBy(x: 0, y: scene.canvasSize.height)
        context.scaleBy(x: 1, y: -1)

        for ground in grounds {
            context.saveGState()
            // A shape is the skin's own statement about where its window is; without one the
            // backdrop is simply the rect, which is what WMP paints behind a visualization.
            if let shape = ground.shape {
                guard let mask = try? imageStore.regionMask(for: shape)
                else { context.restoreGState(); continue }
                clip(to: shape.frame, mask: mask, context: context)
            }
            context.setFillColor(red: CGFloat(ground.color.red) / 255,
                green: CGFloat(ground.color.green) / 255,
                blue: CGFloat(ground.color.blue) / 255, alpha: 1)
            context.fill(ground.frame.cgRect)
            context.restoreGState()
        }

        for command in commands {
            // `alphaBlend="0"` means invisible, and 717 of the corpus's 778 uses are exactly that.
            // Skipping the draw rather than setting alpha to zero saves the decode as well.
            guard command.alpha > 0 else { continue }
            context.saveGState()
            if command.alpha < 1 { context.setAlpha(command.alpha) }
            if let clip = command.clipRect { context.clip(to: clip.cgRect) }
            // An ancestor's clipping shape, against the *container's* frame rather than this
            // command's. Applied before the paint switch because a container shapes everything it
            // holds — a fill and a `<TEXT>` as much as an image. See `WMPSceneClipMask`.
            // **A container's shape is a region, not a clipping image (W172).** The two differ
            // only on a mask that carries transparency of its own, and there the difference is
            // total: `Ice`'s `Clip.png` is 379x183 in exactly two values — 17,558 px of opaque
            // `#FF00FF` outside the player and 51,799 px of **alpha-zero** white over it — so
            // reading its own alpha as "cut away" cut the keep region and the key alike, and the
            // two `Frost` layers it shapes disappeared. The colour is the whole statement here, as
            // `regionMask` says: in the region wherever the pixel is not the key, whatever its
            // alpha. An opaque mask, which is every other one in the corpus, reads the same either
            // way. A `<BUTTONGROUP>`'s own `clippingImage` is unchanged and still honours alpha —
            // that is an authored mask bitmap, not a container's ground.
            for shape in command.inheritedClipMasks {
                let mask = try imageStore.regionMask(for: shape)
                if !shape.boundedByFrame, let (padded, extent) = Self.pad(mask, frame: shape.frame,
                                                                          toCover: command.frame) {
                    clip(to: extent, mask: padded, context: context)
                } else {
                    clip(to: shape.frame, mask: mask, context: context)
                }
            }
            switch command.paint {
            case let .fill(color):
                context.setFillColor(red: CGFloat(color.red) / 255,
                    green: CGFloat(color.green) / 255, blue: CGFloat(color.blue) / 255, alpha: 1)
                context.fill(command.frame.cgRect)
            case let .image(specification):
                let animation = (try? imageStore.animation(for: specification.resourcePath)) ?? nil
                // **This slot's own clock, falling back to the view's** (W182). A caller that
                // names one clock for the whole scene — every render dump, and `WMP_RENDER_CLOCK` —
                // gets exactly what it asked for, because it supplies no slot table.
                let slotClock = slotClocks[WMPAnimationSlot(stableID: command.stableID,
                                                            resourcePath: specification.resourcePath)]
                    ?? clock
                // A finished terminator animation has nothing left to draw, and holding its last
                // frame buries whatever it was drawn over — see `WMPGIFTerminator`.
                if animation?.isCleared(at: slotClock) == true { context.restoreGState(); continue }
                let frame = animation?.frameIndex(at: slotClock) ?? 0
                let decoded = try imageStore.image(for: specification.resourcePath,
                                                   colorKeys: specification.colorKeys,
                                                   implicitKey: specification.implicitColorKey,
                                                   frame: frame,
                                                   hueShift: specification.hueShift)
                let sourceImage = crop(specification.sourceRect, from: decoded.image)
                if let mappingMask = specification.mappingMask,
                   let mask = imageStore.mappingMask(for: mappingMask) {
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
                                let image = try resampled(sourceImage, of: specification,
                                                          frame: frame, in: tile, context: context)
                                drawImage(image, in: tile, context: context)
                                x += tileWidth
                            }
                            y += tileHeight
                        }
                    }
                } else {
                    let image = try resampled(sourceImage, of: specification, frame: frame,
                                              in: command.frame, context: context)
                    drawImage(image, in: command.frame, context: context)
                }
            case let .text(text):
                draw(text, in: command.frame, context: context, clock: clock)
            }
            context.restoreGState()
        }
        // After every command, not by clipping each one: the punch-out is an occlusion, so it has
        // to remove what the skin drew there rather than stop it from being drawn elsewhere.
        for rect in punchingOut where !rect.isEmpty {
            context.clear(CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height))
        }
        guard let image = context.makeImage() else {
            throw WMPFailure(WMPDiagnostic(.renderFailed, "Unable to finalize render surface."))
        }
        return image
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
    /// A region mask extended to cover `target`, keeping everything past its own `frame` — the
    /// shape of a container that states no extent beyond its bitmap (see `boundedByFrame`). Nil
    /// when `target` already lies inside `frame`, which is the plain mask's answer anyway.
    private static func pad(_ mask: CGImage, frame: WMPRect,
                            toCover target: WMPRect) -> (CGImage, WMPRect)? {
        let minX = min(frame.x, target.x), minY = min(frame.y, target.y)
        let maxX = max(frame.x + frame.width, target.x + target.width)
        let maxY = max(frame.y + frame.height, target.y + target.height)
        guard frame.width > 0, frame.height > 0,
              minX < frame.x || minY < frame.y
                || maxX > frame.x + frame.width || maxY > frame.y + frame.height else { return nil }
        let extent = WMPRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        let scaleX = CGFloat(mask.width) / frame.width, scaleY = CGFloat(mask.height) / frame.height
        let width = Int((extent.width * scaleX).rounded(.up))
        let height = Int((extent.height * scaleY).rounded(.up))
        guard width > 0, height > 0, width * height <= WMPPhase0Limits.imagePixels,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        // 255 keeps, the convention `makeClippingMask` states. Bottom-up here, so the bitmap's
        // offset is measured from the extent's bottom edge.
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setBlendMode(.copy)
        context.draw(mask, in: CGRect(x: (frame.x - extent.x) * scaleX,
                                      y: (extent.y + extent.height - frame.y - frame.height) * scaleY,
                                      width: CGFloat(mask.width), height: CGFloat(mask.height)))
        return context.makeImage().map { ($0, extent) }
    }

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

    /// The bitmap to blit, and the filter to blit it through, set on `context` as a side effect.
    ///
    /// A `.wmz` is 1x artwork on a 2x display, and neither filter CoreGraphics offers upscales it
    /// acceptably — so when the draw qualifies, the artwork is resampled by Lanczos once, cached,
    /// and blitted 1:1 here. See `WMPBitmapInterpolationPolicy` for what qualifies and why.
    ///
    /// A resample that cannot be produced returns the authored bitmap, which then draws exactly as
    /// it did before: the store answers with the unscaled image past its own pixel ceiling, and the
    /// size check below catches that without having to ask it what it did.
    private func resampled(_ image: CGImage, of specification: WMPSceneImage, frame: Int,
                           in destination: WMPRect, context: CGContext) throws -> CGImage {
        let decision = WMPBitmapInterpolationPolicy.decision(
            sourcePixelSize: CGSize(width: image.width, height: image.height),
            destination: destination.cgRect, in: context)
        switch decision {
        case let .filter(quality):
            context.interpolationQuality = quality
            return image
        case let .prescale(scale):
            let upscaled = try imageStore.upscaledImage(
                for: specification.resourcePath, colorKeys: specification.colorKeys,
                implicitKey: specification.implicitColorKey, frame: frame,
                sourceRect: specification.sourceRect, scale: scale,
                hueShift: specification.hueShift)
            guard upscaled.image.width == image.width * scale,
                  upscaled.image.height == image.height * scale else {
                context.interpolationQuality = .low
                return image
            }
            // 1:1 in device pixels, so the filter never runs — but `.none` is what says so.
            context.interpolationQuality = .none
            return upscaled.image
        }
    }

    /// The gap between the tail of a marquee and the head of its repeat, in skin pixels. WMP leaves
    /// clear air between the two so a wrapping string does not read as one run-on word.
    private static let marqueeGap: CGFloat = 16

    private func draw(_ text: WMPSceneText, in frame: WMPRect, context: CGContext,
                      clock: TimeInterval) {
        // `fontStyle` is a space- or comma-separated set, not one word: the corpus writes
        // "bold underline" and "UNDERLINE, bold" as well as each alone. Bold and italic are a face
        // request; underline is a decoration CoreText draws for us.
        let font = WMPTextMetrics.font(text.fontName, size: text.fontSize,
                                       bold: text.bold, italic: text.italic)
        let color = CGColor(red: CGFloat(text.color.red) / 255,
            green: CGFloat(text.color.green) / 255, blue: CGFloat(text.color.blue) / 255, alpha: 1)
        // `fontSmoothing="false"` is a readout the skin drew as pixels; antialiasing it turns a
        // 6 px digit into grey mush.
        context.setShouldAntialias(text.smoothed)
        context.setShouldSmoothFonts(text.smoothed)
        let line = WMPTextMetrics.line(text.value, font: font, color: color,
                                       underline: text.underline)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        // **The baseline is measured from the box's bottom, and it may never sit higher than the
        // face's own ascent.** The old rule was `max(fontSize, (height + fontSize) / 2)`, which
        // reads as "put the baseline `(height − fontSize) / 2` below the top" — fine while every
        // `<TEXT>` had a generously tall authored box, and four pixels *above* the box once a text
        // is sized by its own glyphs: at `height = 12`, `fontSize = 7`, that put the baseline 2.5 px
        // below the top of a box whose ascent is 6.3. `Cablemusic`'s show/clip/author/copyright
        // column drew above the LCD it belongs in, over the bezel. The ascent floor changes nothing
        // for a box that was already tall enough and stops the overflow that is measurable here;
        // the clip below still leaves the vertical overflow that is not.
        let ascent = CTFontGetAscent(font)
        let baseline = frame.y + frame.height
            - max(ascent, (frame.height - text.fontSize) / 2)
        let centerY = frame.y + frame.height / 2
        context.saveGState()
        // **A `<TEXT>` is a box, and the clip is horizontal only.** WMP clips its text to the
        // element's frame; drawing it unclipped let `WoW`'s 77x30 `metadata` readout paint
        // "- AC/DC - Shoot to Thrill / Playing" straight across the player's buttons, and it is
        // what a marquee has to be drawn inside. The *vertical* half is deliberately left open:
        // a skin routinely authors a row of links shorter than their own line box —
        // `v2_underworld`'s About page is eight of them — and this engine's baseline is derived
        // from `fontSize` rather than from the face's real metrics, so clipping to the authored
        // height shaved those to a sliver. Cut the overflow that is measured here; leave the one
        // that is not.
        context.clip(to: CGRect(x: frame.cgRect.minX, y: -.greatestFiniteMagnitude / 2,
                                width: frame.cgRect.width, height: .greatestFiniteMagnitude))
        context.translateBy(x: 0, y: centerY)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: -centerY)
        // A marquee only runs when the skin asked for one *and* there is something to reveal;
        // scrolling a string that already fits would just jitter a static readout.
        if text.scrolling, width > frame.width {
            let period = width + Self.marqueeGap
            let step = text.effectiveScrollDelayMilliseconds / 1_000
            let travelled = (clock / step) * Double(text.scrollAmount)
            var offset = CGFloat(travelled.truncatingRemainder(dividingBy: Double(period)))
            if offset < 0 { offset += period }
            // Two draws, one period apart, so the tail and the head of the next pass are both on
            // screen through the wrap and the readout never blanks.
            for repetition in 0...1 {
                context.textPosition = CGPoint(x: frame.x - offset + period * CGFloat(repetition),
                                               y: baseline)
                CTLineDraw(line, context)
            }
        } else {
            let x: CGFloat
            switch text.alignment {
            case .left: x = frame.x
            case .center: x = frame.x + max(0, (frame.width - width) / 2)
            case .right: x = frame.maxX - min(frame.width, width)
            }
            context.textPosition = CGPoint(x: x, y: baseline)
            CTLineDraw(line, context)
        }
        context.restoreGState()
    }
}
