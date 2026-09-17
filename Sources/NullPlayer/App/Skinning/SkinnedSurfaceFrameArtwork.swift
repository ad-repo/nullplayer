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

    /// How wide the ring's own top-right corner piece is, in points, where it declares one.
    ///
    /// **The close control is inset by this, not by the client hole's right border.** The hole says
    /// where the donor's *content* goes and a panel with a side rack leaves a third of the window
    /// outside it — `Star Wars`'s playlist view leaves 164 of 575pt — so a close aligned with the
    /// hole lands mid-band with ring artwork either side (reported 2026-09-15). The corner bitmap is
    /// the thing that has to be cleared, because that is where a skin paints its own close button.
    var trailingCornerWidth: CGFloat? = nil

    /// True when the window is smaller than the donor view's own declared minimum and the frame had
    /// to be scaled down to fit it. Kept as a fact about the artwork rather than hidden, because it
    /// is the one case where the ring is not drawn at the proportions its author chose.
    let wasScaledToFit: Bool

    /// **Whether this frame can be painted over our content whole, with no hole cut in it (W209).**
    ///
    /// A ring is drawn *over* the surface, and until now the client rect was cut out of it first,
    /// because these interiors are often opaque — a corner bitmap in this corpus is a border with
    /// the skin's own content area filled in behind it, and uncut it would paint a still picture
    /// over a running visualiser. But the cut takes the frame's **inner bezel** with it wherever the
    /// bezel dips into the client rect, and that is a real shape in these skins: `Back to the Future
    /// Trilogy`'s bottom bar rises into a tab at its centre, which came out as a black notch
    /// punched through the frame, with the left edge stepped for the same reason. Reported
    /// 2026-09-16: *"there is a notch on the bottom and the content does not fit smoothly on the
    /// left — the border/pane should sit on top of the content in the z order"*.
    ///
    /// So the interior fill is erased from the artwork instead, and what is left — bezel, tab,
    /// corners, every pixel the skin drew as frame — is painted over the content whole. True only
    /// where that erase left the client rect substantially clear; a donor whose interior is a
    /// *picture* rather than a fill erases to nothing and keeps the cut it always had.
    var paintsOverContent: Bool = false

    /// The band the window title and close control are drawn in: everything above the client panel.
    var captionHeight: CGFloat { max(0, contentRect.minY) }

    /// The same four numbers `SkinnedSurfaceChrome` already lays a window out from, so a view that
    /// asks the chrome for its metrics gets the skin's insets wherever a frame is available and its
    /// own classic constants everywhere else.
    /// The close *hit area* in the ring's caption band — nothing is drawn there, so it is sized to
    /// be easy to hit rather than to match a glyph: the corner of one of these bands is where the
    /// skin paints its own close button, and that painted × is what the user aims at. Wider than it
    /// is tall, reaching left from the corner (asked for on 2026-09-15), because a painted × is
    /// rarely flush to the edge — `NVIDIA`'s sits 20-30pt in, behind a rounded corner. 40pt covers
    /// it and stops short of the minimise its skin paints beside it. The height is capped by the
    /// band, so a shallow one never puts the target over the window's content.
    static let closeHitWidth: CGFloat = 40
    static let closeHitHeight: CGFloat = 26

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
