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
    /// **Both keep the window's own geometry, not the ring's.** Every caller hit-tests its close box
    /// at `width - 25` and its title bar by `titleHeight`, so moving the glyph inside the skin's
    /// client hole would draw a button some pixels from where clicking one is. The frame changes what
    /// is *under* these two; it does not move them. Drawn in the palette's lettering rather than
    /// sampled from the artwork behind it — the same colour the surface inside the frame uses.
    func drawBorrowedCaption(in context: CGContext, bounds: CGRect, captionHeight: CGFloat,
                             title: String, isActive: Bool, isClosePressed: Bool,
                             controlScale: CGFloat) {
        guard captionHeight >= SkinnedSurfaceStyle.classicCharHeight else { return }
        context.saveGState()
        context.setShouldAntialias(false)
        let caption = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: captionHeight)
        let labelColor = isActive ? style.legibleText(style.text, on: style.background)
                                  : style.legibleDimText(on: style.background)
        let scale = max(controlScale, 0.01)
        let titleWidth = SkinnedSurfaceStyle.measuredWidth(title, scale: scale)
        let closeRegionWidth = min(25, bounds.width)
        let labelLimit = max(bounds.minX, bounds.maxX - closeRegionWidth)
        let labelX = max(bounds.minX, min(labelLimit - titleWidth, bounds.midX - titleWidth / 2))
        let labelY = caption.minY
            + max(0, (caption.height - SkinnedSurfaceStyle.classicCharHeight * scale) / 2)
        SkinnedSurfaceStyle.drawText(title, at: NSPoint(x: labelX, y: labelY),
                                     scale: scale, color: labelColor, in: context)
        drawCloseButton(in: context,
                        rect: CGRect(x: bounds.maxX - closeRegionWidth, y: caption.minY,
                                     width: closeRegionWidth, height: caption.height),
                        pressed: isClosePressed,
                        color: labelColor)
        context.restoreGState()
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
