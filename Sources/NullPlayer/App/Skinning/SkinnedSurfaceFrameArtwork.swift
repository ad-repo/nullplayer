import AppKit

/// A window frame a foreign skin supplies for one of NullPlayer's *own* windows, already rendered
/// for one window size.
///
/// `SkinnedSurfaceStyle` answers "what colour is this surface"; this answers "what does the frame
/// around it look like". A `.wal` skin already had a way to say that — a NullPlayer window mounted
/// in the skin's own `<Wasabi:StandardFrame>` gets the skin's real border, title bar and buttons
/// (`WinampModernHostedWindowMaterializer`). A `.wmz` has no frame system at all, so nothing but the
/// palette reached our windows and a skin with a whole authored window style — `xsn_sports`,
/// `Halo 2` and the 83 other corpus archives that build their panels out of an eight-piece
/// resizable ring — coloured our chrome and could not shape it.
///
/// This is the family-neutral shape of the answer: a picture of the frame at one size, and where the
/// hosted surface goes inside it. Deriving it is the family's job (`WMPHostedFrameTemplate`), and no
/// skin markup is known here.
struct SkinnedSurfaceFrameArtwork {
    /// The frame, drawn on a transparent canvas in top-left skin coordinates. Its pixel size is
    /// `size * backingScale`; it is drawn into `size` points.
    let image: CGImage

    /// The window size this frame was rendered for, in points.
    let size: CGSize

    /// Where NullPlayer's own content belongs inside it, in the same top-left coordinates — the
    /// skin's own client panel, not an inset guessed from the artwork's thickness. The corner pieces
    /// in this corpus are 190px wide on a 406px window and mostly transparent, so their size says
    /// nothing about where content can go; the skin's stretched client subview says it exactly.
    let contentRect: CGRect

    /// Where the skin's own title bar sits inside that band, when it paints a distinct one.
    ///
    /// **It is not the whole band.** `Half-Life_2` leaves 46px above its client hole and paints an
    /// orange bar across the middle of it; the rest is the frame's dark inner shadow. Controls
    /// centred in the 46 land below the bar a user reads as the title bar. Nil where the ring's
    /// caption is one flat tone, and then the whole band is used, as it always was.
    struct CaptionStrip: Equatable {
        /// Distance from the top of the window to the top of the bar, in points.
        let top: CGFloat
        /// The bar's own height, in points.
        let height: CGFloat

        func scaled(by factor: CGFloat) -> CaptionStrip {
            CaptionStrip(top: top * factor, height: height * factor)
        }
    }

    var captionStrip: CaptionStrip? = nil

    /// True when the window is smaller than the donor view's own declared minimum and the frame had
    /// to be scaled down to fit it. Kept as a fact about the artwork rather than hidden, because it
    /// is the one case where the ring is not drawn at the proportions its author chose.
    let wasScaledToFit: Bool

    /// The band the window title and close control are drawn in: everything above the client panel.
    var captionHeight: CGFloat { max(0, contentRect.minY) }

    /// Where those two are actually laid out: the skin's own title bar where it paints one, and the
    /// whole band where it does not.
    var captionBandRect: CGRect {
        let band = CGRect(x: 0, y: 0, width: size.width, height: captionHeight)
        guard let captionStrip, captionStrip.height > 0 else { return band }
        let bar = CGRect(x: 0, y: captionStrip.top, width: size.width,
                         height: captionStrip.height).intersection(band)
        guard !bar.isNull, bar.height > 0 else { return band }
        // **Half way between the bar's centre and the band's.** Centred on the lit bar alone the
        // controls read top-heavy — measured on `Half-Life_2`: its bar is the window's first 29px
        // and our plate landed at 5.5-21.5, centred on it to within a point, and the reporter's
        // answer was *"now its just flipped to the top being too close"*. The band below the bar is
        // not empty: the frame's own lit lower edge is part of what a reader calls the title bar,
        // and it is as far below the bar as the window's edge is above it. Splitting the two
        // centres is bounded by both — a stray highlight deep in the band cannot drag the title
        // down, and a bar flush against the window's top edge cannot pin it there.
        let centre = (bar.midY + band.midY) / 2
        return CGRect(x: 0, y: centre - bar.height / 2, width: size.width, height: bar.height)
            .intersection(band)
    }

    /// The same four numbers `SkinnedSurfaceChrome` already lays a window out from, so a view that
    /// asks the chrome for its metrics gets the skin's insets wherever a frame is available and its
    /// own classic constants everywhere else.
    var metrics: SkinnedSurfaceChrome.Metrics {
        SkinnedSurfaceChrome.Metrics(
            titleHeight: max(0, contentRect.minY),
            leftBorder: max(0, contentRect.minX),
            rightBorder: max(0, size.width - contentRect.maxX),
            bottomBorder: max(0, size.height - contentRect.maxY)
        )
    }

    /// Whether this frame can stand in for a window of `candidate` points without being redrawn.
    /// Exact, because the ring is laid out by the skin's own alignment rules and a frame rendered
    /// for another size has its corners in the wrong place.
    func matches(size candidate: CGSize) -> Bool {
        abs(candidate.width - size.width) < 0.5 && abs(candidate.height - size.height) < 0.5
    }
}

extension SkinnedSurfaceFrameArtwork: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.image === rhs.image && lhs.size == rhs.size && lhs.contentRect == rhs.contentRect
            && lhs.wasScaledToFit == rhs.wasScaledToFit
    }
}
