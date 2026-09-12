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

    /// True when the window is smaller than the donor view's own declared minimum and the frame had
    /// to be scaled down to fit it. Kept as a fact about the artwork rather than hidden, because it
    /// is the one case where the ring is not drawn at the proportions its author chose.
    let wasScaledToFit: Bool

    /// The band the window title and close control are drawn in: everything above the client panel.
    var captionHeight: CGFloat { max(0, contentRect.minY) }

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
