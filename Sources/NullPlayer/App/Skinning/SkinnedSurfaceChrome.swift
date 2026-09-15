import AppKit

/// Palette-derived chrome for NullPlayer's own windows shown beside somebody else's skin — a
/// `.wal` skin that declares no such window, or a `.wmz` skin, which has no frame system to mount one
/// in at all.
///
/// The caller continues to own its window geometry and hit testing. This painter only replaces the
/// classic `.wsz` artwork when `WindowManager.hostedSurfaceStyle` is available; a surface
/// mounted in a Wasabi holder never calls it.
struct SkinnedSurfaceChrome {
    struct Metrics: Equatable {
        let titleHeight: CGFloat
        let leftBorder: CGFloat
        let rightBorder: CGFloat
        let bottomBorder: CGFloat

        /// The name the hosted windows' own layout constants use for the same number, so a view can
        /// swap its `SkinElements…Layout` for these metrics without touching its call sites.
        var titleBarHeight: CGFloat { titleHeight }

        static var spectrumFamily: Metrics {
            Metrics(
                titleHeight: SkinElements.SpectrumWindow.Layout.titleBarHeight,
                leftBorder: SkinElements.SpectrumWindow.Layout.leftBorder,
                rightBorder: SkinElements.SpectrumWindow.Layout.rightBorder,
                bottomBorder: SkinElements.SpectrumWindow.Layout.bottomBorder
            )
        }

        static var projectM: Metrics {
            Metrics(
                titleHeight: SkinElements.ProjectM.Layout.titleBarHeight,
                leftBorder: SkinElements.ProjectM.Layout.leftBorder,
                rightBorder: SkinElements.ProjectM.Layout.rightBorder,
                bottomBorder: SkinElements.ProjectM.Layout.bottomBorder
            )
        }

        static var waveform: Metrics {
            Metrics(
                titleHeight: SkinElements.WaveformWindow.Layout.titleBarHeight,
                leftBorder: SkinElements.WaveformWindow.Layout.leftBorder,
                rightBorder: SkinElements.WaveformWindow.Layout.rightBorder,
                bottomBorder: SkinElements.WaveformWindow.Layout.bottomBorder
            )
        }
    }

    let style: SkinnedSurfaceStyle

    /// The window frame the hosting skin draws for its own panels, when it draws one. A `.wmz` skin
    /// with an eight-piece ring lends it here (`WMPHostedFrameTemplate`); every other case is nil
    /// and the palette-derived bands below are the whole frame, exactly as before.
    var artwork: SkinnedSurfaceFrameArtwork?

    init(style: SkinnedSurfaceStyle, artwork: SkinnedSurfaceFrameArtwork? = nil) {
        self.style = style
        self.artwork = artwork
    }

    /// The layout a hosted window measures its content and its hit targets from: the skin's own
    /// client hole wherever a frame was lent, and the caller's classic constants otherwise.
    static func metrics(for bounds: CGRect, fallback: Metrics) -> Metrics {
        WindowManager.shared.hostedSurfaceFrameArtwork(for: bounds.size)?.metrics ?? fallback
    }

    /// Draws spectrum-family chrome in the same flipped, top-left coordinate system used by
    /// `SkinRenderer`. `fillBackground` distinguishes the old full-window and overlay entry points.
    func drawSpectrumFamilyWindow(
        in context: CGContext,
        bounds: CGRect,
        metrics: Metrics,
        isActive: Bool,
        isClosePressed: Bool,
        controlScale: CGFloat,
        title: String,
        fillBackground: Bool
    ) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        if let artwork {
            drawSkinFrame(artwork, in: context, bounds: bounds, isActive: isActive,
                          isClosePressed: isClosePressed, controlScale: controlScale,
                          title: title, fillBackground: fillBackground)
            return
        }

        context.saveGState()
        context.setShouldAntialias(false)

        if fillBackground {
            context.setFillColor(style.background.cgColor)
            context.fill(bounds)
        }

        let titleHeight = min(max(metrics.titleHeight, 0), bounds.height)
        let bottomHeight = min(max(metrics.bottomBorder, 0), max(0, bounds.height - titleHeight))
        let sideHeight = max(0, bounds.height - titleHeight - bottomHeight)
        let leftWidth = min(max(metrics.leftBorder, 0), bounds.width)
        let rightWidth = min(max(metrics.rightBorder, 0), max(0, bounds.width - leftWidth))

        let titleColor = isActive ? style.barBackground : style.background
        let edgeColor = isActive ? style.border : style.divider
        // The title bar is a *derived* colour and the title a declared one, so nothing so far has
        // guaranteed they can be seen together — five skins in the corpus drew a title that was
        // literally invisible, and `dimText` (the inactive title) was the worse half nearly
        // everywhere. Guard against the strip this label actually lands on (B48).
        let labelColor = isActive ? style.legibleText(style.text, on: titleColor)
                                  : style.legibleDimText(on: titleColor)

        context.setFillColor(titleColor.cgColor)
        context.fill(CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: titleHeight))

        context.setFillColor(style.barBackground.cgColor)
        context.fill(CGRect(x: bounds.minX, y: bounds.minY + titleHeight,
                            width: leftWidth, height: sideHeight))
        context.fill(CGRect(x: bounds.maxX - rightWidth, y: bounds.minY + titleHeight,
                            width: rightWidth, height: sideHeight))
        context.fill(CGRect(x: bounds.minX, y: bounds.maxY - bottomHeight,
                            width: bounds.width, height: bottomHeight))

        // One-pixel palette-derived seams make the frame legible on both very dark and very light
        // themes without importing any fixed classic-skin colours.
        context.setFillColor(edgeColor.cgColor)
        context.fill(CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: 1))
        context.fill(CGRect(x: bounds.minX, y: bounds.minY + max(0, titleHeight - 1),
                            width: bounds.width, height: min(1, titleHeight)))
        context.fill(CGRect(x: bounds.minX, y: bounds.minY + titleHeight, width: min(1, leftWidth),
                            height: sideHeight))
        context.fill(CGRect(x: bounds.maxX - min(1, rightWidth), y: bounds.minY + titleHeight,
                            width: min(1, rightWidth), height: sideHeight))
        context.fill(CGRect(x: bounds.minX, y: bounds.maxY - min(1, bottomHeight),
                            width: bounds.width, height: min(1, bottomHeight)))

        let scale = max(controlScale, 0.01)
        let titleWidth = SkinnedSurfaceStyle.measuredWidth(title, scale: scale)
        let closeRegionWidth = min(25, bounds.width)
        let labelLimit = max(bounds.minX, bounds.maxX - closeRegionWidth)
        let labelX = max(bounds.minX + leftWidth,
                         min(labelLimit - titleWidth,
                             bounds.midX - titleWidth / 2))
        let labelY = bounds.minY + max(0, (titleHeight - SkinnedSurfaceStyle.classicCharHeight * scale) / 2)
        SkinnedSurfaceStyle.drawText(title, at: NSPoint(x: labelX, y: labelY),
                                          scale: scale, color: labelColor, in: context)

        drawCloseButton(in: context,
                        rect: CGRect(x: bounds.maxX - closeRegionWidth, y: bounds.minY,
                                     width: closeRegionWidth, height: titleHeight),
                        pressed: isClosePressed,
                        color: labelColor)
        context.restoreGState()
    }

    /// The skin's own ring, with our title and close control laid into the band above its client
    /// hole.
    ///
    /// The skin draws no title text of its own — a `.wmz` panel is identified by its artwork — but
    /// ours is not the skin's window: it is a NullPlayer surface wearing the skin's frame, and a
    /// user with four of them open needs to be able to tell them apart and shut them. Both are drawn
    /// in the palette's lettering rather than sampled from the artwork behind them, which is the
    /// same colour the surface inside the frame uses.
    private func drawSkinFrame(
        _ artwork: SkinnedSurfaceFrameArtwork,
        in context: CGContext,
        bounds: CGRect,
        isActive: Bool,
        isClosePressed: Bool,
        controlScale: CGFloat,
        title: String,
        fillBackground: Bool
    ) {
        context.saveGState()
        let content = artwork.scaled(to: bounds.size).contentRect
            .offsetBy(dx: bounds.minX, dy: bounds.minY)

        // Only the client hole is filled. The ring is authored against whatever is behind it — most
        // of these bitmaps are keyed-out shapes — so painting the whole window first would put a
        // flat slab inside every rounded corner the skin cut.
        if fillBackground {
            context.setFillColor(style.background.cgColor)
            context.fill(content)
        }

        // Top-left origin, like every other path here: the caller has already flipped the context,
        // so the image is drawn through a local flip rather than upside down.
        context.saveGState()
        // The ring is the frame *around* the surface, never wallpaper behind it (W177). It is drawn
        // at the window's full size because that is how its eight pieces were laid out, so the
        // client hole is cut out of it before it lands: several rings in this corpus are opaque
        // rather than keyed — `Half-Life_2` builds its panels out of solid `f_*.png` strips — and
        // these windows draw their content *first* and this chrome over it, so an uncut ring paints
        // a still picture over a running visualiser. Only the hole is protected; corners, edges and
        // the caption band are untouched, and a window with no borrowed ring never reaches here.
        // `PlexBrowserView` has cut the same hole for the library since the rings arrived.
        if !content.isEmpty {
            context.beginPath()
            context.addRect(bounds)
            context.addRect(content)
            context.clip(using: .evenOdd)
        }
        context.translateBy(x: bounds.minX, y: bounds.minY + bounds.height)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = artwork.wasScaledToFit ? .high : .none
        context.draw(artwork.image, in: CGRect(origin: .zero, size: bounds.size))
        context.restoreGState()

        drawBorrowedCaption(in: context, bounds: bounds,
                            captionHeight: max(0, content.minY - bounds.minY),
                            title: title, isActive: isActive, isClosePressed: isClosePressed,
                            controlScale: controlScale)
        context.restoreGState()
    }

    /// The window title and close control over a borrowed ring, in the band above its client hole.
    ///
    /// **Neither is drawn on the picture.** The palette's own background is the right ground for a
    /// flat frame and the wrong one for a borrowed ring: `Half-Life_2`'s caption is a bright orange
    /// strip crossed by a dark pipe, and a label checked for contrast against a dark palette and
    /// then drawn over that strip clears the threshold on paper and is unreadable on screen — the
    /// same mistake B48 fixed for the derived title bar. Sampling the artwork per glyph and
    /// outlining against it was the first answer and it read as mess (2026-09-15: *"works but looks
    /// bad"*). So each of the two gets a **plate** in a palette tone the ring behind it cannot be
    /// confused with, and is lettered on that. The ring still frames the window; the two controls
    /// that are ours are legible because they are not competing with it.
    ///
    /// **The close control keeps the window's hit geometry and the ring's inset** — see
    /// `closeButtonRect(in:captionHeight:width:artwork:)`, which every close hit test reads too.
    ///
    /// **The band is never too short to draw in.** Measured 2026-09-15 with `WMP_HOSTED_FRAME` over
    /// the installed corpus at the library's own 550x464: **87 of 184 archives lend a ring**, their
    /// captions run 7px to 104px, and **none is shorter than one character** — so the old
    /// `captionHeight >= classicCharHeight` guard never fired on a real skin, and what it protected
    /// against was not the case that exists. The case that does exist is a band shorter than the
    /// *lettering asked for*: `The_Sentinel_v.1.0` lends 7px, `TheUnit` and `The` 9px, and the
    /// library asks for 1.6x glyphs that are 9.6px tall. Dropping the caption there would take the
    /// window's only close control with it, so the lettering is scaled down to the band instead.
    func drawBorrowedCaption(in context: CGContext, bounds: CGRect, captionHeight: CGFloat,
                             title: String, isActive: Bool, isClosePressed: Bool,
                             controlScale: CGFloat, titleScale: CGFloat = 1,
                             closeRegionWidth requestedCloseWidth: CGFloat = 25) {
        guard captionHeight > 0 else { return }
        context.saveGState()
        context.setShouldAntialias(false)
        // The band our two controls are laid out in is the ring's own top strip where it draws one,
        // not the whole gap above the client hole — see `SkinnedSurfaceFrameArtwork.captionBand`.
        let caption = Self.captionBand(captionHeight: captionHeight, artwork: artwork, in: bounds)
        let scale = min(max(controlScale, 0.01) * max(titleScale, 0.01),
                        caption.height / SkinnedSurfaceStyle.classicCharHeight)
        let titleWidth = SkinnedSurfaceStyle.measuredWidth(title, scale: scale)
        let closeRect = Self.closeButtonRect(in: bounds, captionHeight: captionHeight,
                                             width: requestedCloseWidth, artwork: artwork)
        let labelLimit = max(bounds.minX, closeRect.minX)
        let labelX = max(bounds.minX, min(labelLimit - titleWidth, bounds.midX - titleWidth / 2))
        let labelHeight = SkinnedSurfaceStyle.classicCharHeight * scale
        let labelY = caption.minY + max(0, (caption.height - labelHeight) / 2)
        let labelRect = CGRect(x: labelX, y: labelY, width: titleWidth, height: labelHeight)

        // **Both sit on a plate of their own.** Sampling the ring and guarding the lettering against
        // it was not enough: `Half-Life_2`'s band is a bright orange strip crossed by a dark pipe,
        // and lettering outlined against both reads as mess rather than as a title (reported
        // 2026-09-15 as "works but looks bad"). A plate is the thing a caption over a picture
        // actually needs — the ring still frames the window, and the two controls that are *ours*
        // are legible because they are not drawn on the picture at all.
        let labelPlate = labelRect.insetBy(dx: -5, dy: -2).intersection(caption)
        #if DEBUG
        if ProcessInfo.processInfo.environment["WMP_CAPTION_TRACE"] != nil {
            NSLog("[wmp/caption] \(title) bounds=\(Int(bounds.width))x\(Int(bounds.height)) "
                + "captionHeight=\(captionHeight) band=\(caption.minY)+\(caption.height) "
                + "plate=\(labelPlate.minY)+\(labelPlate.height) close=\(closeRect)")
        }
        #endif
        let labelGround = plate(over: labelRect, in: bounds)
        drawPlate(labelPlate, color: labelGround, in: context)
        SkinnedSurfaceStyle.drawText(title, at: NSPoint(x: labelX, y: labelY), scale: scale,
                                     color: lettering(on: labelGround, isActive: isActive),
                                     in: context)

        // The close plate is a square in the column, not the whole column: a 104px band — the
        // deepest the corpus lends — would otherwise carry a shutter down one corner of the window.
        let side = max(7, min(closeRect.width - 4, closeRect.height - 4, 16))
        let closePlate = CGRect(x: floor(closeRect.midX - side / 2), y: floor(closeRect.midY - side / 2),
                                width: side, height: side)
        let closeGround = isClosePressed ? style.pressedFill : plate(over: closePlate, in: bounds)
        drawPlate(closePlate, color: closeGround, in: context)
        drawCloseButton(in: context, rect: closePlate, pressed: false,
                        color: lettering(on: closeGround, isActive: isActive))
        context.restoreGState()
    }

    /// The palette's lettering, guarded against the ground it is about to be drawn on.
    private func lettering(on ground: NSColor, isActive: Bool) -> NSColor {
        isActive ? style.legibleText(style.text, on: ground) : style.legibleDimText(on: ground)
    }

    /// Where the close control goes in a window of `bounds` whose caption band is `captionHeight`.
    ///
    /// **Inset by the ring's own right border**, so it lands in the caption band rather than on the
    /// corner piece — which in this corpus is routinely a rivet strip, a logo, or the skin's *own*
    /// painted close button. `Combat_Flight_Simulator_3` draws a round × in its corner and ours was
    /// landing 15px to its right: the control the user reaches for is the one the skin drew, and it
    /// is artwork (reported 2026-09-15 as "can't close the library from the x").
    ///
    /// Every window that hit-tests a close box reads its rect from here, so what is clickable is
    /// what is drawn. With no ring lent this is the top-right box it has always been.
    static func closeButtonRect(in bounds: CGRect, captionHeight: CGFloat, width requested: CGFloat = 25,
                                artwork: SkinnedSurfaceFrameArtwork?) -> CGRect {
        let width = min(requested, bounds.width)
        let band = captionBand(captionHeight: captionHeight, artwork: artwork, in: bounds)
        guard let artwork else {
            return CGRect(x: bounds.maxX - width, y: band.minY, width: width, height: band.height)
        }
        let inset = min(max(0, artwork.scaled(to: bounds.size).metrics.rightBorder),
                        max(0, bounds.width - width))
        return CGRect(x: bounds.maxX - inset - width, y: band.minY, width: width, height: band.height)
    }

    /// The band a borrowed caption's controls are centred in: the ring's own top strip where it
    /// draws one, and the whole gap above the client hole where it does not.
    private static func captionBand(captionHeight: CGFloat, artwork: SkinnedSurfaceFrameArtwork?,
                                    in bounds: CGRect) -> CGRect {
        let whole = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: captionHeight)
        guard let artwork else { return whole }
        let band = artwork.scaled(to: bounds.size).captionBandRect
            .offsetBy(dx: bounds.minX, dy: bounds.minY)
        return band.height > 0 ? band.intersection(whole) : whole
    }

    /// The same rect for a caller that has no artwork in hand — the hit tests, which ask
    /// `WindowManager` for the ring exactly as `metrics(for:fallback:)` does.
    static func closeButtonRect(in bounds: CGRect, captionHeight: CGFloat,
                                width requested: CGFloat = 25) -> CGRect {
        closeButtonRect(in: bounds, captionHeight: captionHeight, width: requested,
                        artwork: WindowManager.shared.hostedSurfaceFrameArtwork(for: bounds.size))
    }

    /// The ground one of our own controls is drawn on, over somebody else's ring: the palette's own
    /// chrome tone wherever it can be told apart from the artwork behind it, and the opposite
    /// extreme where it cannot — a plate that matches the picture it sits on is not a plate.
    private func plate(over rect: CGRect, in bounds: CGRect) -> NSColor {
        let ground = ringGround(under: rect, in: bounds).tone
        let luminance = SkinnedSurfaceStyle.relativeLuminance(ground)
        for candidate in [style.barBackground, style.background] {
            if abs(SkinnedSurfaceStyle.relativeLuminance(candidate) - luminance) >= 0.25 {
                return candidate
            }
        }
        return luminance > 0.5 ? .black : .white
    }

    /// A plate with a one-pixel seam, in the same palette-derived colours the flat chrome uses.
    private func drawPlate(_ rect: CGRect, color: NSColor, in context: CGContext) {
        guard rect.width > 0, rect.height > 0 else { return }
        context.setFillColor(color.cgColor)
        context.fill(rect)
        context.setStrokeColor(style.legibleText(style.divider, on: color).cgColor)
        context.setLineWidth(1)
        context.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
    }

    /// What is behind a piece of the caption once the ring has been drawn.
    private struct Ground {
        /// The average tone there — the ground the contrast guard is run against.
        let tone: NSColor
        /// True when the artwork under it spans too much of the luminance range for any one colour
        /// to be read against all of it.
        let isBusy: Bool
    }

    /// The artwork's own pixels behind `rect`, or the palette's background where no ring is lent or
    /// the ring is transparent there.
    ///
    /// Averaged rather than sampled at a point because these captions are artwork — a gradient, a
    /// bevel, a logo — and one pixel is as likely to be a highlight as the band. The spread is
    /// carried beside the average because the average alone is a trap: half a bright strip and half
    /// a dark pipe average to a mid tone that flatters a colour neither half can show. Mostly
    /// transparent artwork answers the palette instead — the window is `isOpaque = false` there and
    /// what shows through is the surface's own ground, which is what the palette describes.
    private func ringGround(under rect: CGRect, in bounds: CGRect) -> Ground {
        let flat = Ground(tone: style.background, isBusy: false)
        guard let artwork, bounds.width > 0, bounds.height > 0,
              rect.width >= 1, rect.height >= 1 else { return flat }
        let image = artwork.image
        // The ring is drawn into `bounds` from its own top-left origin, so a rect in the caller's
        // (already flipped) space maps straight onto the image's pixels.
        let scaleX = CGFloat(image.width) / bounds.width
        let scaleY = CGFloat(image.height) / bounds.height
        let crop = CGRect(x: (rect.minX - bounds.minX) * scaleX,
                          y: (rect.minY - bounds.minY) * scaleY,
                          width: rect.width * scaleX, height: rect.height * scaleY)
            .integral
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !crop.isEmpty, let region = image.cropping(to: crop) else { return flat }

        // Resampled down to at most one cell per glyph rather than read pixel by pixel: this runs on
        // every chrome redraw, and what it needs is the band's tones, not its detail.
        let width = min(Int(crop.width), 32)
        let height = min(Int(crop.height), 8)
        guard width > 0, height > 0 else { return flat }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let sampled: Ground? = pixels.withUnsafeMutableBytes { buffer -> Ground? in
            guard let small = CGContext(data: buffer.baseAddress, width: width, height: height,
                                        bitsPerComponent: 8, bytesPerRow: width * 4,
                                        space: CGColorSpaceCreateDeviceRGB(),
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return nil
            }
            small.interpolationQuality = .medium
            small.draw(region, in: CGRect(x: 0, y: 0, width: width, height: height))

            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0
            var covered = 0
            var darkest = CGFloat.greatestFiniteMagnitude
            var lightest = -CGFloat.greatestFiniteMagnitude
            for index in stride(from: 0, to: width * height * 4, by: 4) {
                let alpha = CGFloat(buffer[index + 3]) / 255
                guard alpha >= 0.5 else { continue }
                // Premultiplied: undo the alpha so a half-transparent ring answers its own colour
                // rather than a darkened one.
                let color = NSColor(deviceRed: min(1, CGFloat(buffer[index]) / 255 / alpha),
                                    green: min(1, CGFloat(buffer[index + 1]) / 255 / alpha),
                                    blue: min(1, CGFloat(buffer[index + 2]) / 255 / alpha),
                                    alpha: 1)
                red += color.redComponent
                green += color.greenComponent
                blue += color.blueComponent
                let luminance = SkinnedSurfaceStyle.relativeLuminance(color)
                darkest = min(darkest, luminance)
                lightest = max(lightest, luminance)
                covered += 1
            }
            // Half-covered artwork is the surface showing through, not a ground of its own.
            guard covered * 2 >= width * height else { return nil }
            let count = CGFloat(covered)
            return Ground(tone: NSColor(deviceRed: red / count, green: green / count,
                                        blue: blue / count, alpha: 1),
                          isBusy: lightest - darkest > 0.25)
        }
        return sampled ?? flat
    }

    private func drawCloseButton(in context: CGContext, rect: CGRect, pressed: Bool, color: NSColor) {
        guard rect.width > 0, rect.height > 0 else { return }
        if pressed {
            context.setFillColor(style.pressedFill.cgColor)
            context.fill(rect)
        }

        let size = min(7, max(3, floor(min(rect.width, rect.height) - 6)))
        let originX = floor(rect.midX - size / 2)
        let originY = floor(rect.midY - size / 2)
        context.setFillColor(color.cgColor)
        for offset in 0..<Int(size) {
            let d = CGFloat(offset)
            context.fill(CGRect(x: originX + d, y: originY + d, width: 1, height: 1))
            context.fill(CGRect(x: originX + size - 1 - d, y: originY + d, width: 1, height: 1))
        }
    }
}
