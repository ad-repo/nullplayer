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

        /// The four borders as a plain inset, for a donor that states them without reference to a
        /// window (`WMPHostedFrameTemplate.borderInsets`, W207).
        init(insets: NSEdgeInsets) {
            self.init(titleHeight: insets.top, leftBorder: insets.left,
                      rightBorder: insets.right, bottomBorder: insets.bottom)
        }

        init(titleHeight: CGFloat, leftBorder: CGFloat, rightBorder: CGFloat, bottomBorder: CGFloat) {
            self.titleHeight = titleHeight
            self.leftBorder = leftBorder
            self.rightBorder = rightBorder
            self.bottomBorder = bottomBorder
        }

        /// The library's own chrome. Its status bar is the bottom border, which is why it is the one
        /// window in this family whose bottom inset is not a plain edge.
        static var plexBrowser: Metrics {
            Metrics(
                titleHeight: SkinElements.PlexBrowser.Layout.titleBarHeight,
                leftBorder: SkinElements.PlexBrowser.Layout.leftBorder,
                rightBorder: SkinElements.PlexBrowser.Layout.rightBorder,
                bottomBorder: SkinElements.PlexBrowser.Layout.statusBarHeight
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

    /// **The ground a hosted window paints: its content hole wherever a frame was lent, and the
    /// whole window otherwise.**
    ///
    /// Every window in the spectrum family paints its own ground in its own `draw` — there is no
    /// shared step that owns it — and `drawSkinFrame` deliberately fills *only* the client hole,
    /// because a borrowed frame is authored against whatever is behind it and most of these bitmaps
    /// are keyed-out shapes. So a view that fills its whole bounds first turns a shaped frame into a
    /// black box with the skin drawn inside it, which is what `anemone`'s nine-sliced panel (W207)
    /// exposed in three windows at once: cava, `flow` and PeppyMeter, each with its own
    /// `NSColor.black.setFill(); bounds.fill()`. It was latent the whole time — every donor until
    /// now was an eight-piece ring laid out to the window's own edges, so there were no cut-away
    /// pixels for the slab to show through.
    ///
    /// The rule lives here, once, so a window added later inherits it instead of rediscovering it.
    /// The library never had the defect for the same reason it has none of this family's chrome
    /// bugs: it lays itself out from `metrics` and clips its content to the hole.
    static func hostedGroundRect(in bounds: CGRect) -> CGRect {
        guard let artwork = WindowManager.shared.hostedSurfaceFrameArtwork(for: bounds.size) else {
            return bounds
        }
        let hole = artwork.scaled(to: bounds.size).contentRect.offsetBy(dx: bounds.minX, dy: bounds.minY)
        return hole.isEmpty ? bounds : hole
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
        Self.traceBorrowedChrome(bounds: bounds, artwork: artwork,
                                 captionHeight: max(0, content.minY - bounds.minY))
        context.restoreGState()
    }

    /// **Nothing of ours is drawn over a borrowed ring.** The ring is the window's chrome, whole.
    ///
    /// Four rules used to live here: find the ring's lit title bar in the rendered pixels, centre
    /// between that bar and the band, plate each control in a palette tone the artwork cannot be
    /// confused with, and inset the close by the ring's border. Each was measured, each shipped, and
    /// each had a counter-example in the next skin — because all four are inferences about *someone
    /// else's finished chrome*, and `.wmz` markup states none of it. (A `.wal` skin has a real frame
    /// system — `<Wasabi:StandardFrame:*>`, a declared client rect, declared buttons — which is why
    /// none of this class of defect exists there.) `NVIDIA` is where the model broke rather than the
    /// tuning: its 84pt band has too little contrast to call a bar, so our controls centred in the
    /// whole band and landed on the curve where its body starts, under the restore, minimise and
    /// close the skin paints there itself.
    ///
    /// So we draw no title and no close glyph. **The skin's own painted close is the close** — it
    /// was always the control the user reached for, and `closeButtonRect` now simply puts a generous
    /// hit area in the corner it is painted in. Reported 2026-09-15: *"you don't even need to draw
    /// it, just make a good sized hit area"*.

    /// `WMP_CAPTION_TRACE=1` — the hosted window's resolved geometry, once per chrome redraw, from
    /// wherever a borrowed ring is actually drawn. It survived the caption that used to print it
    /// because the numbers are the point: the window's size, the hole the donor states, and the
    /// close target over the corner. Printed through `NSLog`, because a `print` into
    /// `kill_build_run.sh --log` is block-buffered and never arrives.
    static func traceBorrowedChrome(bounds: CGRect, artwork: SkinnedSurfaceFrameArtwork?,
                                    captionHeight: CGFloat, closeWidth: CGFloat = 25) {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["WMP_CAPTION_TRACE"] != nil else { return }
        let close = closeButtonRect(in: bounds, captionHeight: captionHeight, width: closeWidth,
                                    artwork: artwork)
        NSLog("[wmp/caption] bounds=\(Int(bounds.width))x\(Int(bounds.height)) "
            + "captionHeight=\(captionHeight) close=\(close) "
            + "artwork=\(artwork.map { "\($0.size) content=\($0.scaled(to: bounds.size).contentRect)" } ?? "none")")
        #endif
    }

    /// Where the close control goes: **the window's own top-right corner**, ring or no ring.
    ///
    /// No inset, no band detection, no client hole. Every previous answer here was an attempt to
    /// dodge whatever the skin had painted nearby — the ring's right border, the corner bitmap, the
    /// client hole — and each one moved the control somewhere a user does not look for it. Nothing
    /// is drawn now, so there is nothing to dodge: the target simply covers the corner, which is
    /// both where a close button belongs and where these skins paint their own.
    ///
    /// Every window that hit-tests a close box reads its rect from here, so what is clickable is
    /// what is drawn.
    static func closeButtonRect(in bounds: CGRect, captionHeight: CGFloat, width requested: CGFloat = 25,
                                artwork: SkinnedSurfaceFrameArtwork?) -> CGRect {
        let width = min(requested, bounds.width)
        guard artwork != nil else {
            return CGRect(x: bounds.maxX - width, y: bounds.minY, width: width,
                          height: max(0, min(captionHeight, bounds.height)))
        }
        // Flush into the corner, because nothing is drawn here: the whole point is that the target
        // covers the painted × wherever in that corner the skin put it.
        let hitWidth = max(0, min(SkinnedSurfaceFrameArtwork.closeHitWidth, bounds.width))
        let hitHeight = max(0, min(SkinnedSurfaceFrameArtwork.closeHitHeight, captionHeight))
        return CGRect(x: bounds.maxX - hitWidth, y: bounds.minY, width: hitWidth, height: hitHeight)
    }

    /// The same rect for a caller that has no artwork in hand — the hit tests, which ask
    /// `WindowManager` for the ring exactly as `metrics(for:fallback:)` does.
    static func closeButtonRect(in bounds: CGRect, captionHeight: CGFloat,
                                width requested: CGFloat = 25) -> CGRect {
        closeButtonRect(in: bounds, captionHeight: captionHeight, width: requested,
                        artwork: WindowManager.shared.hostedSurfaceFrameArtwork(for: bounds.size))
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
