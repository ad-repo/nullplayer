import Accelerate
import CoreGraphics

/// A `.wal` window's pixels at device resolution, kept between frames.
///
/// The scene is recorded on the main thread into a `WasabiDrawList` and rendered here, one set of
/// dirty rects at a time. This class touches nothing but its own buffer and the lists a `Job` hands
/// it, so it can run on any thread, one at a time. That is what takes the rasterizing off the main
/// thread.
///
/// **Device resolution, like `.wmz`.** `draw(_:)` is handed a display-list context at CTM 1.0 even
/// on a 2x panel (B80), and the opaque path used to rasterize at that scale, so every opaque layout
/// was drawn at point resolution and stretched 2x by the replay. Measured 2026-10-20: Anunaki's
/// player buffer was 708x349 at 100% on a 2x panel. The canvas is `bounds × backingScaleFactor`, so
/// the UI Size is already in it and every pixel it holds is one the window shows.
///
/// **In the window's colour space.** The picture is copied into AppKit's backing store on the main
/// thread every frame, and a canvas in any other space is colour-matched there, whole: in Device RGB
/// that conversion was 15.7% of cPro Bento's main thread (debug, playing), more than the walk that
/// records the frame. In the window's own space the copy is a copy. The skin's bitmaps are matched
/// into that space once each and kept (`matched`): CoreGraphics matches a bitmap on *every* draw,
/// and that was 68% of a playing frame's render on a "Color LCD" panel.
///
/// **RGBA, and measured rather than assumed.** BGRA is the layout the window server composites
/// natively, and it is the *wrong* choice here: the skin's own artwork is RGBA, so the scene draw pays
/// a swizzle per bitmap. `main/normal` went from 2.8 to **4.8 ms/frame** on the scene pass alone. The
/// one conversion at the blit is cheaper than one per bitmap.
final class WinampModernCanvas {
    /// One frame's work, recorded on the main thread.
    struct Job {
        let pixelWidth: Int
        let pixelHeight: Int
        /// The window's own colour space: see `WinampModernCanvas`.
        let colorSpace: CGColorSpace
        /// Canvas pixels per view point: both lists are recorded at this scale.
        let scale: CGFloat
        /// The rects to redraw, in canvas pixels with a bottom-left origin, on whole pixels.
        let rects: [CGRect]
        let scene: WasabiDrawList
        /// The host's own chrome, drawn *under* the scene once the scene's alpha is promoted.
        let chrome: WasabiDrawList?
        /// Promote every drawn pixel to opaque: the layout has not opted in to per-pixel alpha
        /// (`WasabiSceneRenderer.layoutWantsOpaqueBacking`).
        let promotesAlpha: Bool
    }

    /// What a frame hands back to the main thread.
    struct Frame {
        /// The whole window's picture.
        let picture: CGImage
        /// The canvas's alpha as an alpha-only image, when this frame changed it; nil when every
        /// pixel it drew kept its alpha. The window's drop shadow is cut from it.
        let outline: CGImage?
    }

    /// The canvas space for a window or context in `space`: that space when it is an RGB one, which
    /// every display's is; sRGB otherwise.
    static func colorSpace(matching space: CGColorSpace?) -> CGColorSpace {
        if let space, space.model == .rgb { return space }
        return CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    }

    private var context: CGContext?
    /// The canvas's alpha, top row first, one byte a pixel: what decides `Frame.outline`. Compared
    /// over a frame's own rects only, so a readout tick inside the outline costs a row compare.
    private var alpha: [UInt8] = []
    private var scratch: [UInt8] = []
    /// Each bitmap matched into the canvas's colour space, holding its source so the identifier
    /// cannot be reused. Emptied with a new canvas, which may be in another space.
    private var matchedImages: [ObjectIdentifier: (source: CGImage, matched: CGImage)] = [:]
    private var matchedPixels = 0

    /// Whether a frame would start a new canvas, and so has to be drawn whole: only the dirty rects
    /// would be filled otherwise, over a blank buffer.
    func isFresh(pixelWidth: Int, pixelHeight: Int, colorSpace: CGColorSpace) -> Bool {
        context?.width != pixelWidth || context?.height != pixelHeight || context?.colorSpace != colorSpace
    }

    /// Draw `job` into the canvas.
    func render(_ job: Job) -> Frame? {
        let fresh = isFresh(pixelWidth: job.pixelWidth, pixelHeight: job.pixelHeight, colorSpace: job.colorSpace)
        if fresh {
            context = CGContext(data: nil, width: job.pixelWidth, height: job.pixelHeight,
                                bitsPerComponent: 8, bytesPerRow: 0, space: job.colorSpace,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            alpha = [UInt8](repeating: 0, count: job.pixelWidth * job.pixelHeight)
            matchedImages = [:]
            matchedPixels = 0
        }
        guard let context, let data = context.data else { return nil }
        for rect in job.rects { context.clear(rect) }
        let match = { [unowned self] (image: CGImage) in matched(image, into: job.colorSpace) }

        context.saveGState()
        context.clip(to: job.rects)
        context.scaleBy(x: job.scale, y: job.scale)
        job.scene.replay(into: context, matchImage: match)
        context.restoreGState()

        if job.promotesAlpha {
            for rect in job.rects {
                var region = buffer(data, rect: rect, in: context)
                WasabiSceneRenderer.promoteAlphaToRegion(&region)
            }
        }

        if let chrome = job.chrome {
            // A transparency layer, so the chrome's own blend modes compose among themselves and the
            // result goes under the scene as one picture.
            context.saveGState()
            context.clip(to: job.rects)
            context.setBlendMode(.destinationOver)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            context.scaleBy(x: job.scale, y: job.scale)
            chrome.replay(into: context, matchImage: match)
            context.endTransparencyLayer()
            context.restoreGState()
        }

        guard let picture = context.makeImage() else { return nil }
        // A new canvas always reports its outline, even an empty one: the last was another size.
        let changed = job.rects.reduce(fresh) { updateAlpha(data, rect: $1, in: context) || $0 }
        return Frame(picture: picture, outline: changed ? outlineImage(width: context.width,
                                                                       height: context.height) : nil)
    }

    /// `image` in `space`, matched once and kept. An image already in it, or one that is not 8-bit
    /// RGB, draws as it is. Bounded by pixels like the renderer's prescale cache, which feeds it.
    private func matched(_ image: CGImage, into space: CGColorSpace) -> CGImage {
        guard let source = image.colorSpace, source != space, source.model == .rgb,
              image.bitsPerComponent == 8 else { return image }
        if let hit = matchedImages[ObjectIdentifier(image)] { return hit.matched }
        let pixels = image.width * image.height
        guard pixels <= WasabiSceneRenderer.maximumPrescaledPixels,
              let matcher = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        matcher.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let result = matcher.makeImage() else { return image }
        matchedPixels += pixels
        if matchedPixels > WasabiSceneRenderer.maximumPrescaledCachePixels {
            matchedImages = [:]
            matchedPixels = pixels
        }
        matchedImages[ObjectIdentifier(image)] = (image, result)
        return result
    }

    /// The RGBA pixels under `rect` (bottom-left origin, whole pixels) as a vImage buffer.
    private func buffer(_ data: UnsafeMutableRawPointer, rect: CGRect, in context: CGContext) -> vImage_Buffer {
        // Memory rows run top first.
        let row = context.height - Int(rect.maxY)
        return vImage_Buffer(data: data + row * context.bytesPerRow + Int(rect.minX) * 4,
                             height: vImagePixelCount(rect.height), width: vImagePixelCount(rect.width),
                             rowBytes: context.bytesPerRow)
    }

    /// Copy `rect`'s alpha into the mirror, reporting whether any of it differed.
    ///
    /// **vImage extracts it, never a Swift loop.** A hand-written pass over the alpha byte measured
    /// 7.5 ms/frame on a 354x147 player at 2x in a debug build (`promoteAlphaToRegion`).
    private func updateAlpha(_ data: UnsafeMutableRawPointer, rect: CGRect, in context: CGContext) -> Bool {
        let width = Int(rect.width), height = Int(rect.height)
        guard width > 0, height > 0 else { return false }
        var source = buffer(data, rect: rect, in: context)
        if scratch.count < width * height { scratch = [UInt8](repeating: 0, count: width * height) }
        let top = context.height - Int(rect.maxY), left = Int(rect.minX), stride = context.width
        return scratch.withUnsafeMutableBytes { scratch in
            var plane = vImage_Buffer(data: scratch.baseAddress, height: vImagePixelCount(height),
                                      width: vImagePixelCount(width), rowBytes: width)
            // Channel 3 of RGBA memory order is alpha.
            _ = vImageExtractChannel_ARGB8888(&source, &plane, 3, vImage_Flags(kvImageNoFlags))
            return alpha.withUnsafeMutableBytes { mirror in
                var changed = false
                for row in 0..<height {
                    let fresh = scratch.baseAddress! + row * width
                    let kept = mirror.baseAddress! + (top + row) * stride + left
                    guard memcmp(fresh, kept, width) != 0 else { continue }
                    changed = true
                    memcpy(kept, fresh, width)
                }
                return changed
            }
        }
    }

    /// The mirror as an alpha-only image, copied out of it: the shadow reads nothing but alpha, and
    /// the canvas is never shared with it. Made through a context because `CGImage`'s own
    /// initializer answers nil for an alpha-only image.
    private func outlineImage(width: Int, height: Int) -> CGImage? {
        alpha.withUnsafeMutableBytes { bytes in
            CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                      bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)?.makeImage()
        }
    }
}

/// The one way a scene becomes a canvas frame, or a direct draw when it is too large for one. The
/// window's frames (`WinampModernMainView+Frames`) and the harness's `draw(in:)` both come through
/// here, so the corpus sweep renders the recording the window does (B235).
extension WasabiSceneRenderer {
    /// Whether a canvas this size is within `maximumPrescaledPixels`; no corpus window comes near it.
    static func fitsCanvas(pixelWidth: Int, pixelHeight: Int) -> Bool {
        pixelWidth * pixelHeight <= maximumPrescaledPixels
    }

    /// One frame recorded for a `pixelWidth`×`pixelHeight` canvas at `scale` canvas pixels per point,
    /// redrawing `rects` (non-empty, canvas pixels). `origin` (points) lands at the canvas's corner, and
    /// `skinScale` applies within that. `chrome`, when given, records the host's chrome on the same
    /// terms.
    func canvasJob(pixelWidth: Int, pixelHeight: Int, scale: CGFloat, rects: [CGRect],
                   colorSpace: CGColorSpace, origin: CGPoint = .zero, skinScale: CGFloat = 1,
                   pressed: WasabiObjectID?, hovered: WasabiObjectID?,
                   chrome: ((WasabiDrawList) -> Void)? = nil) -> WinampModernCanvas.Job {
        let clip = rects.dropFirst().reduce(rects[0]) { $0.union($1) }
        func list() -> WasabiDrawList {
            let list = WasabiDrawList(ctm: CGAffineTransform(scaleX: scale, y: scale), clip: clip)
            if origin != .zero { list.translateBy(x: -origin.x, y: -origin.y) }
            if skinScale != 1 { list.scaleBy(x: skinScale, y: skinScale) }
            return list
        }
        let scene = list()
        record(into: scene, pressed: pressed, hovered: hovered)
        let chromeList = chrome.map { draw in
            let chromeList = list()
            draw(chromeList)
            return chromeList
        }
        return WinampModernCanvas.Job(pixelWidth: pixelWidth, pixelHeight: pixelHeight, colorSpace: colorSpace,
                                      scale: scale, rects: rects, scene: scene, chrome: chromeList,
                                      promotesAlpha: layoutWantsOpaqueBacking)
    }

    /// A scene too large for a canvas, drawn straight into `context`: chrome first, then the scene,
    /// as a translucent layout once was.
    func drawDirectly(in context: CGContext, pressed: WasabiObjectID?, hovered: WasabiObjectID?,
                      skinScale: CGFloat = 1, devicePixelsPerUnit: CGFloat = 1,
                      chrome: ((WasabiDrawList) -> Void)? = nil) {
        context.saveGState()
        if skinScale != 1 { context.scaleBy(x: skinScale, y: skinScale) }
        let clip = context.boundingBoxOfClipPath.applying(context.ctm)
        if let chrome {
            let list = WasabiDrawList(ctm: context.ctm, clip: clip, devicePixelsPerUnit: devicePixelsPerUnit)
            chrome(list)
            list.replay(into: context)
        }
        let scene = WasabiDrawList(ctm: context.ctm, clip: clip, interpolationQuality: context.interpolationQuality,
                                   devicePixelsPerUnit: devicePixelsPerUnit)
        record(into: scene, pressed: pressed, hovered: hovered)
        scene.replay(into: context)
        context.restoreGState()
    }
}
