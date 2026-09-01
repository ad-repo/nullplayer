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

    func render(scene: WMPScene, backingScale: CGFloat = 1) async throws -> WMPRenderResult {
        try await Task.detached(priority: .userInitiated) {
            try renderOffMain(scene: scene, backingScale: backingScale)
        }.value
    }

    func dump(scene: WMPScene, to directory: URL, backingScale: CGFloat = 1) async throws -> WMPRenderDumpRecord {
        try await Task.detached(priority: .userInitiated) {
            let result = try renderOffMain(scene: scene, backingScale: backingScale)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let safeID = scene.viewID.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" }
            let filename = "\(String(safeID))@\(WMPNumber.format(backingScale))x.png"
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

    private func renderOffMain(scene: WMPScene, backingScale: CGFloat) throws -> WMPRenderResult {
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
            context.saveGState()
            if let clip = command.clipRect { context.clip(to: clip.cgRect) }
            switch command.paint {
            case let .fill(color):
                context.setFillColor(red: CGFloat(color.red) / 255,
                    green: CGFloat(color.green) / 255, blue: CGFloat(color.blue) / 255, alpha: 1)
                context.fill(command.frame.cgRect)
            case let .image(specification):
                let decoded = try imageStore.image(for: specification.resourcePath,
                                                   colorKey: specification.colorKey)
                let sourceImage = crop(specification.sourceRect, from: decoded.image)
                if let mappingMask = specification.mappingMask,
                   let mask = mappingMask.mapping.maskImage(for: Set(mappingMask.nodeIDs)) {
                    context.clip(to: command.frame.cgRect, mask: mask)
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
        let fontName = text.bold ? text.fontName + " Bold" : text.fontName
        let font = CTFontCreateWithName(fontName as CFString, text.fontSize, nil)
        let color = CGColor(red: CGFloat(text.color.red) / 255,
            green: CGFloat(text.color.green) / 255, blue: CGFloat(text.color.blue) / 255, alpha: 1)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
        ]
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
