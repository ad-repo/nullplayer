import AppKit
import CoreGraphics
import Foundation

/// Sprite drawing: the scaled blit and its prescale cache, tiling, nine-slice `<grid>`,
/// and the animated/filmstrip frame selection that feeds them. Split out of
/// `WasabiRenderer.swift`; see `skills/winamp-modern-skin-guide/reference/rendering.md`.
extension WasabiSceneRenderer {
    /// Draw a `CGImage` into the flipped (top-left origin) skin space `draw(in:)` establishes.
    /// `CGContext.draw` always puts the image's *bottom* row at `rect.minY`, which under that flip is
    /// the visual top — so every bitmap has to be re-flipped about its own rect or it renders
    /// vertically mirrored in place. Text uses the same trick (`drawFlippedText`).
    func drawImage(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: 0, y: rect.midY)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: -rect.midY)
        let quality = WasabiBitmapInterpolationPolicy.quality(
            sourcePixelSize: CGSize(width: image.width, height: image.height),
            destination: rect,
            in: context)
        context.interpolationQuality = quality
        context.draw(prescaled(image, for: rect, in: context, quality: quality), in: rect)
        context.restoreGState()
    }

    /// The same artwork, already rasterized at the size this context will put it on screen.
    ///
    /// A `.wal` scene is laid out in skin pixels and drawn through a scaled CTM — ×2 on a Retina
    /// display, more at a larger UI Size — so `CGContext.draw` resampled every bitmap in the window
    /// with `.high` interpolation on *every frame*. That is the measured cost of a Defix frame:
    /// 6.7 ms in unnamed layers, 3.7 ms in the layout's own background, all of it re-derived from
    /// artwork that had not changed. Scaling once and keeping the result turns the per-frame draw
    /// into a blit at the device resolution, and the pixels are identical — the same interpolation
    /// runs, just not sixty times a second.
    ///
    /// Only a genuine rescale is cached: art already at its device size is drawn straight through,
    /// so a skin at 1× on a non-Retina display pays nothing for this at all.
    private func prescaled(_ image: CGImage, for rect: CGRect, in context: CGContext,
                           quality: CGInterpolationQuality) -> CGImage {
        let ctm = context.ctm
        let width = Int((rect.width * abs(ctm.a)).rounded())
        let height = Int((rect.height * abs(ctm.d)).rounded())
        guard width > 0, height > 0, width * height <= Self.maximumPrescaledPixels,
              width * height >= Self.minimumPrescaledPixels,
              width != image.width || height != image.height else { return image }
        let key = WarpSourceKey(image: ObjectIdentifier(image), width: width, height: height)
        if let cached = prescaledCache[key] { return cached.image }
        guard let scaled = Self.resized(image, width: width, height: height, quality: quality)
        else { return image }
        // Bounded by pixel budget rather than by entry count: a skin's window backgrounds are the
        // entries that matter and one of those is worth a hundred button faces.
        prescaledPixelCost += width * height
        if prescaledPixelCost > Self.maximumPrescaledCachePixels {
            prescaledCache.removeAll()
            prescaledPixelCost = width * height
        }
        prescaledCache[key] = (image, scaled)
        return scaled
    }

    private static func resized(_ image: CGImage, width: Int, height: Int,
                                quality: CGInterpolationQuality) -> CGImage? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = quality
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    func draw(_ bitmap: WasabiBitmap, object: WasabiObject,
                      frame: CGRect, context: CGContext) {
        let tileX = object.attributes["tile"] == "1" || object.attributes["tilex"] == "1"
        let tileY = object.attributes["tile"] == "1" || object.attributes["tiley"] == "1"
        if tileX || tileY {
            drawTiled(bitmap, in: frame, tileX: tileX, tileY: tileY, context: context)
            return
        }
        // A non-tiled layer stretches its bitmap to fill its rect. Resizable window chrome depends on
        // this: `wasabi.frame.top` is a 10×18 sprite stretched across the whole titlebar, and the
        // menubar/titlebar streaks are 5–10px sprites stretched to hundreds of pixels. Drawing them
        // at natural size instead painted one sprite and left the rest of the bar blank.
        drawImage(bitmap.image, in: frame, context: context)
    }

    /// `tile`/`tilex`/`tiley`: repeat the bitmap across the layer instead of stretching it. Every
    /// resizable strip in a Bento-style frame (top/bottom/left/right/center) is a tiled layer, so
    /// without this the frame paints one tile and leaves the rest of the window empty.
    func drawTiled(_ bitmap: WasabiBitmap, in frame: CGRect, tileX: Bool, tileY: Bool,
                           context: CGContext) {
        let tileWidth = CGFloat(bitmap.width)
        let tileHeight = CGFloat(bitmap.height)
        guard tileWidth >= 1, tileHeight >= 1, frame.width > 0, frame.height > 0 else { return }
        context.saveGState()
        context.clip(to: frame)
        // Tiles are blitted 1:1; smoothing would resample each tile's edge and leave a visible seam
        // grid across every tiled background strip.
        context.interpolationQuality = .none
        // One tiling draw, not one blit per tile. The loop this replaces issued up to 8192 separate
        // `drawImage` calls per frame, and Big Bento Modern's window-sized tiled `<grid>` measured
        // **60.4 ms/frame** at Retina scale on its own — with the spectrum analyzer invalidating the
        // scene at the audio tap's rate, that is the main thread gone.
        //
        // `draw(_:in:byTiling:)` repeats the image across the whole clip, so the tiling axes are
        // chosen by the size of the rect handed to it: an axis that should *stretch* instead of
        // repeating is given the frame's full extent, and its repeats then fall outside the clip.
        //
        // The y-flip is the same one `drawImage` applies, and it has to be here too: skin artwork is
        // top-left origin against a bottom-left context, and tiling straight through drew every tiled
        // background upside down across 20 skins in the corpus. Flipping about the tile's own midY
        // leaves the tiling grid anchored where the old per-tile loop put it.
        let tile = CGRect(x: frame.minX, y: frame.minY,
                          width: tileX ? tileWidth : frame.width,
                          height: tileY ? tileHeight : frame.height)
        context.translateBy(x: 0, y: tile.midY)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: -tile.midY)
        context.draw(bitmap.image, in: tile, byTiling: true)
        context.restoreGState()
    }

    /// The single image a bitmap layer paints right now: an animated layer's current frame, or the
    /// whole bitmap for a plain one. Shared with the Layer FX path, which warps exactly that image.
    func layerImage(_ bitmap: WasabiBitmap, object: WasabiObject, type: String) -> CGImage? {
        guard type == "animatedlayer" else { return bitmap.image }
        return animatedFrameImage(bitmap, object: object)
    }

    /// How an animated layer's sheet is cut into frames: one frame's size, how many there are, and how
    /// many sit side by side. Shared by the frame the layer draws and the region it can be clicked on.
    private func animationGrid(_ bitmap: WasabiBitmap,
                               object: WasabiObject) -> (width: Int, height: Int, count: Int, columns: Int) {
        let frameWidth = max(1, Int(Double(object.attributes["framewidth"] ?? object.attributes["w"] ?? "") ?? Double(bitmap.width)))
        let frameHeight = max(1, Int(Double(object.attributes["frameheight"] ?? object.attributes["h"] ?? "") ?? Double(bitmap.height)))
        let columns = max(1, bitmap.width / frameWidth)
        let rows = max(1, bitmap.height / frameHeight)
        let count = max(1, Int(Double(object.attributes["frames"] ?? "") ?? Double(columns * rows)))
        return (frameWidth, frameHeight, count, columns)
    }

    /// The most opaque any frame is at `point` — the layer's region, see the call site in `object(at:)`.
    func animationUnionAlpha(_ bitmap: WasabiBitmap, object: WasabiObject,
                                     node: WasabiSceneNode, point: CGPoint) -> Int {
        let grid = animationGrid(bitmap, object: object)
        let x = (point.x - node.frame.minX) / max(1, node.frame.width) * CGFloat(grid.width)
        let y = (point.y - node.frame.minY) / max(1, node.frame.height) * CGFloat(grid.height)
        var strongest = 0
        for index in 0..<grid.count {
            let origin = CGPoint(x: CGFloat((index % grid.columns) * grid.width),
                                 y: CGFloat((index / grid.columns) * grid.height))
            strongest = max(strongest, Int(bitmap.alpha(at: CGPoint(x: origin.x + x, y: origin.y + y))))
            if strongest > Self.regionAlphaFloor { break }
        }
        return strongest
    }

    /// `<images>` — a filmstrip whose frame is chosen by a **host value**, not by a play head.
    ///
    /// ```xml
    /// <bitmap id="volume.bg2" file="volume_ani.png" x="0" y="0" w="97"/>   <!-- 97x288 -->
    /// <images id="volume.images" source="volume" images="volume.bg2" imagesspacing="16"
    ///         x="-109" y="82" w="97" h="15" relatx="1"/>
    /// ```
    ///
    /// `images=` is the sheet (**not** `image=`, which is why nothing drew before B88 — the object
    /// never reached a bitmap at all), `imagesspacing` is the **pitch** between frame tops, and the
    /// object's own `h` is how much of each frame is shown. They differ here on purpose: 16px pitch,
    /// 15px tall, one blank row between frames. Frames run down the sheet, so the count is the
    /// sheet's height over the pitch — 18 for the volume bar.
    ///
    /// Only `source="volume"` is answered. That is the entire corpus: one declaration, in the
    /// ClassicPro engine, reaching all five cPro skins (B88's [M27]). The rest of the `source`
    /// vocabulary is unmeasured, and a guessed binding would draw a confidently wrong frame rather
    /// than nothing — so an unknown source draws nothing, exactly as an unknown `<vis mode>` does.
    func filmstripFrameImage(_ object: WasabiObject) -> CGImage? {
        guard let sheetID = object.attributes["images"],
              let bitmap = resources.bitmap(identifier: sheetID),
              let normalized = filmstripValue(of: object) else { return nil }
        guard let crop = WasabiFilmstrip.crop(
            sheetWidth: bitmap.width, sheetHeight: bitmap.height,
            pitch: Int(object.attributes["imagesspacing"] ?? "") ?? 0,
            frameHeight: Int(object.attributes["h"] ?? ""),
            normalized: normalized) else { return nil }
        return cropped(bitmap.image, to: crop)
    }

    /// What an `<images source="…">` stands at, 0…1. Deliberately narrow — see `filmstripFrameImage`.
    private func filmstripValue(of object: WasabiObject) -> CGFloat? {
        switch object.attributes["source"]?.lowercased() {
        case "volume": return CGFloat(host.volume)
        default: return nil
        }
    }

    private func animatedFrameImage(_ bitmap: WasabiBitmap, object: WasabiObject) -> CGImage? {
        let (frameWidth, frameHeight, count, columns) = animationGrid(bitmap, object: object)
        let frameIndex = max(0, min(count - 1, WasabiAnimation.state(of: object, frameCount: count,
                                                                     clock: clock()).frame))
        let column = frameIndex % columns
        let row = frameIndex / columns
        let crop = CGRect(x: column * frameWidth, y: row * frameHeight,
                          width: frameWidth, height: frameHeight)
        guard crop.maxY <= CGFloat(bitmap.height), crop.maxX <= CGFloat(bitmap.width) else { return nil }
        return cropped(bitmap.image, to: crop)
    }

    /// One sub-rectangle of a sheet, **stably**. `CGImage.cropping(to:)` allocates a fresh image on
    /// every call, so a glyph or an animation frame had a different object identity each frame — and
    /// every cache downstream of it (the pre-scaled raster, the warp's source raster) is keyed by
    /// exactly that identity. Without this, drawing an animated layer or a line of bitmap-font text
    /// missed those caches on every frame *and* churned them, which is worse than not caching at all.
    func cropped(_ image: CGImage, to rect: CGRect) -> CGImage? {
        let key = CropKey(image: ObjectIdentifier(image), x: Int(rect.minX), y: Int(rect.minY),
                          width: Int(rect.width), height: Int(rect.height))
        if let cached = cropCache[key] { return cached.crop }
        guard let crop = image.cropping(to: rect) else { return nil }
        // The source is held with the entry: an `ObjectIdentifier` is an address, and an address that
        // has been freed can come back attached to a different image.
        if cropCache.count > Self.maximumCachedCrops { cropCache.removeAll() }
        cropCache[key] = (image, crop)
        return crop
    }

    struct CropKey: Hashable {
        let image: ObjectIdentifier
        let x: Int
        let y: Int
        let width: Int
        let height: Int
    }

    func drawAnimated(_ bitmap: WasabiBitmap, object: WasabiObject,
                              frame: CGRect, context: CGContext) {
        guard let image = animatedFrameImage(bitmap, object: object) else { return }
        drawImage(image, in: frame, context: context)
    }

    /// `<ProgressGrid>` — the *filled* part of a bar, drawn as `left` cap + stretched `middle` +
    /// `right` cap growing from the edge `orientation` names.
    ///
    /// A skin pairs one with a `<slider>` over the same rect and gives the slider a thumb that is
    /// deliberately invisible — Love is War Miku's seek "thumb" is a 1×1 pixel, and the grid is the
    /// only thing that shows a position at all. Drawing nothing for the grid left its seek bar an
    /// empty white box with no indication of progress anywhere in the window.
    ///
    /// The grid carries no `action` of its own there, so the value comes from the sibling that does:
    /// pairing them by rect is the whole idiom.
    func drawProgressGrid(_ object: WasabiObject, frame: CGRect, context: CGContext) {
        guard frame.width > 0, frame.height > 0 else { return }
        let source = object.attributes["action"] != nil ? object : (valueSibling(of: object) ?? object)
        let clamped = normalizedValue(of: source)
        let left = resources.bitmap(identifier: object.attributes["left"])
        let middle = resources.bitmap(identifier: object.attributes["middle"])
        let right = resources.bitmap(identifier: object.attributes["right"])
        guard left != nil || middle != nil || right != nil else { return }

        // `orientation` names the direction the fill *grows*, so it is also the edge it is anchored
        // to. Skins spell it both ways round and in both axes; the vertical forms anchor the same way.
        let orientation = object.attributes["orientation"]?.lowercased() ?? "right"
        let vertical = orientation == "up" || orientation == "down" || orientation == "vertical"
        let reversed = orientation == "left" || orientation == "up"
        let span = (vertical ? frame.height : frame.width) * clamped
        guard span > 0 else { return }
        let filled: CGRect
        if vertical {
            filled = CGRect(x: frame.minX, y: reversed ? frame.maxY - span : frame.minY,
                            width: frame.width, height: span)
        } else {
            filled = CGRect(x: reversed ? frame.maxX - span : frame.minX, y: frame.minY,
                            width: span, height: frame.height)
        }

        context.saveGState()
        context.clip(to: filled)
        // The caps keep their own size and the middle takes everything between them, which is what
        // makes a one-pixel `middle` stretch across the whole elapsed span.
        var body = filled
        if let left {
            let width = min(CGFloat(left.width), body.width)
            drawImage(left.image, in: CGRect(x: body.minX, y: body.minY,
                                             width: width, height: body.height), context: context)
            body = CGRect(x: body.minX + width, y: body.minY,
                          width: body.width - width, height: body.height)
        }
        if let right {
            let width = min(CGFloat(right.width), body.width)
            drawImage(right.image, in: CGRect(x: body.maxX - width, y: body.minY,
                                              width: width, height: body.height), context: context)
            body = CGRect(x: body.minX, y: body.minY,
                          width: body.width - width, height: body.height)
        }
        if let middle, body.width > 0, body.height > 0 {
            draw(middle, object: object, frame: body, context: context)
        }
        context.restoreGState()
    }

    /// `<grid>` — nine-slice chrome: the element every framed surface in a Bento-style skin is made of.
    ///
    /// The corners keep their own size, the four edges stretch (or tile) along one axis only, and
    /// `middle` fills what is left. Every part is optional and a grid carries no `image` of its own, so
    /// before this it fell through to the bitmap fallback and drew **nothing** — which is why
    /// cPro-Bento's tab pills read as bare text on black, and its SUI sheet, playlist box, mini-view
    /// strip and seek track as flat black holes. 49 of them in that skin's include graph alone.
    ///
    /// A grid with only the three `top*` parts is a horizontal three-slice (the tab pills, and the
    /// engine's `left`/`middle`/`right` seek track is the same thing rotated); its absent rows take no
    /// height, rather than a missing `middle` being stretched over everything.
    func drawGrid(_ object: WasabiObject, frame: CGRect, context: CGContext) {
        guard frame.width > 0, frame.height > 0 else { return }
        func part(_ key: String) -> WasabiBitmap? { resources.bitmap(identifier: object.attributes[key]) }
        let topLeft = part("topleft"), top = part("top"), topRight = part("topright")
        let left = part("left"), middle = part("middle"), right = part("right")
        let bottomLeft = part("bottomleft"), bottom = part("bottom"), bottomRight = part("bottomright")
        drawNineSlice([topLeft, top, topRight, left, middle, right, bottomLeft, bottom, bottomRight],
                      in: frame, tile: object.attributes["tile"] == "1", context: context)
    }

    /// The nine-slice itself, given its parts row-major and already resolved.
    ///
    /// Split out of `drawGrid` so a widget whose slices are *conventional ids* rather than an
    /// object's attributes can draw the same way — a `<Wasabi:TabSheet>` tab is cut from
    /// `wasabi.tabsheet.button.*` and is a three-slice with no bottom row, which is a case this
    /// already handles.
    func drawNineSlice(_ parts: [WasabiBitmap?], in frame: CGRect, tile: Bool,
                               context: CGContext) {
        guard frame.width > 0, frame.height > 0 else { return }
        guard parts.contains(where: { $0 != nil }) else { return }
        let topLeft = parts[0], top = parts[1], topRight = parts[2]
        let left = parts[3], middle = parts[4], right = parts[5]
        let bottomLeft = parts[6], bottom = parts[7], bottomRight = parts[8]

        // Which of the three columns and rows the skin actually declared. A grid that declares one
        // row is a **three-slice**, and its row takes the whole height: cPro's tab pills carry only
        // `topleft`/`top`/`topright`, and the engine's seek track only `left`/`middle`/`right`.
        // Splitting the extent as though the absent rows were there would leave most of the surface
        // blank — the same hole the missing element left in the first place.
        let declaredColumns = (0..<3).filter { column in (0..<3).contains { parts[$0 * 3 + column] != nil } }
        let declaredRows = (0..<3).filter { row in (0..<3).contains { parts[row * 3 + $0] != nil } }

        /// Extents for the three slots along one axis: a single declared slot spans everything, and
        /// otherwise the edges keep their art's own size and the centre takes the remainder. Edges
        /// that together exceed the box (a pane the user collapsed) shrink instead of overlapping.
        func extents(total: CGFloat, declared: [Int], natural: (Int) -> CGFloat) -> [CGFloat] {
            if declared.count == 1 {
                var result: [CGFloat] = [0, 0, 0]
                result[declared[0]] = total
                return result
            }
            var (start, end) = (natural(0), natural(2))
            if start + end > total {
                let scale = total / max(1, start + end)
                start = (start * scale).rounded(.down)
                end = total - start
            }
            return [start, total - start - end, end]
        }
        func widest(_ candidates: [WasabiBitmap?]) -> CGFloat {
            CGFloat(candidates.compactMap { $0?.width }.max() ?? 0)
        }
        func tallest(_ candidates: [WasabiBitmap?]) -> CGFloat {
            CGFloat(candidates.compactMap { $0?.height }.max() ?? 0)
        }
        let columnArt = [[topLeft, left, bottomLeft], [top, middle, bottom], [topRight, right, bottomRight]]
        let rowArt = [[topLeft, top, topRight], [left, middle, right], [bottomLeft, bottom, bottomRight]]
        let columns = extents(total: frame.width, declared: declaredColumns) { widest(columnArt[$0]) }
        let rows = extents(total: frame.height, declared: declaredRows) { tallest(rowArt[$0]) }

        let tiles = tile
        context.saveGState()
        var y = frame.minY
        for (row, rowHeight) in rows.enumerated() {
            var x = frame.minX
            for (column, columnWidth) in columns.enumerated() {
                defer { x += columnWidth }
                guard let bitmap = parts[row * 3 + column], columnWidth > 0, rowHeight > 0 else { continue }
                let cell = CGRect(x: x, y: y, width: columnWidth, height: rowHeight)
                // A corner is one natural-size blit whatever `tile` says; only the stretched axes of
                // an edge or the middle repeat.
                let tileX = tiles && column == 1
                let tileY = tiles && row == 1
                if tileX || tileY {
                    drawTiled(bitmap, in: cell, tileX: tileX, tileY: tileY, context: context)
                } else {
                    drawImage(bitmap.image, in: cell, context: context)
                }
            }
            y += rowHeight
        }
        context.restoreGState()
    }
}
