import CoreGraphics
import Foundation

/// How a `.wmz`'s artwork is resampled on the way to the screen.
///
/// **A `.wmz` is authored at 1x and this app presents it on a 2x display**, so a bitmap a skin draws
/// at its natural size is still upscaled before it reaches the screen — and CoreGraphics offers
/// nothing good to do it with. `.low` and `.high` are *byte-identical* on the draw path (measured on
/// `Plus! Hard Boiled/Egg_Body_Normal.jpg` at 2x) and both are bilinear, which blurs; `.none` is
/// nearest, which blocks. A reporter looking at the Plus! family rejected both in turn: bilinear as
/// a "low res look", nearest as no better.
///
/// So the upscale is taken away from the draw and done once, by Lanczos, in
/// `WMPImageStore.upscaledImage` — which reconstructs an edge instead of smearing or replicating
/// one. This type decides only *whether* a given draw qualifies.
///
/// The two-filter fallback is the rule the other skin engines apply to their own 1x artwork —
/// `WasabiBitmapInterpolationPolicy` for `.wal`, `SkinRenderer`'s "keep pixel-perfect look" for
/// Classic. It is deliberately not an import of either: `WMPSkin/` owns its copy so that a change
/// here cannot reach Classic or Winamp Modern.
enum WMPBitmapInterpolationPolicy {
    private static let integerTolerance: CGFloat = 0.001

    enum Decision: Equatable {
        /// Resample the bitmap to `scale`x its authored size first, then blit it 1:1.
        case prescale(Int)
        /// Draw the bitmap as it is, through this filter.
        case filter(CGInterpolationQuality)
    }

    /// The decision for drawing `sourcePixelSize` into `destination`, in the space `context` is
    /// currently transformed to.
    ///
    /// `destination` is in skin space and the CTM carries the display's backing scale and UI Size,
    /// so the two questions this asks are separable: *is the skin drawing this bitmap at its
    /// authored size*, and *is the surface it lands on a whole multiple of that*.
    ///
    /// **The device's scale and a skin's own stretch are different things and only the first one
    /// qualifies.** Both arrive as one number in the CTM, and separating them is what makes this
    /// rule safe. A skin that draws a 2px gradient strip across a 200px bar is *asking* to be
    /// interpolated; resampling it as if it were artwork at natural size changes a picture nobody
    /// complained about. A corpus sweep of the version that conflated the two moved **148 of 535**
    /// dumped views at **1x**, where the device scale is 1 and nothing about the report applies.
    static func decision(sourcePixelSize: CGSize, destination: CGRect,
                         in context: CGContext) -> Decision {
        guard sourcePixelSize.width > 0, sourcePixelSize.height > 0,
              destination.width > 0, destination.height > 0 else { return .filter(.low) }

        // 1. The skin must be drawing the bitmap at its authored size.
        guard abs(destination.width - sourcePixelSize.width) <= integerTolerance,
              abs(destination.height - sourcePixelSize.height) <= integerTolerance else {
            return .filter(.low)
        }

        // 2. The device scale must be a whole multiple. `hypot` reads the CTM's basis vectors,
        //    which is robust to the y-flip the scene transform carries.
        let transform = context.ctm
        let horizontal = hypot(transform.a, transform.b)
        let vertical = hypot(transform.c, transform.d)
        guard horizontal >= 1 - integerTolerance, vertical >= 1 - integerTolerance,
              isInteger(horizontal), isInteger(vertical),
              abs(horizontal - vertical) <= integerTolerance else { return .filter(.low) }

        // 3. The bitmap must land *on* the pixel grid. A node at a fractional coordinate has no
        //    whole-pixel destination to resample into, and snapping it to one would move the
        //    artwork by up to half a pixel — a shift, not a sharpening. Leaving it to the draw's
        //    own filter is what the engine already did, and it is the honest answer here.
        let deviceRect = destination.applying(transform)
        guard isInteger(deviceRect.origin.x), isInteger(deviceRect.origin.y) else {
            return .filter(.low)
        }

        let scale = Int(horizontal.rounded())
        // At 1x there is nothing to reconstruct: the bitmap already is the pixels.
        return scale > 1 ? .prescale(scale) : .filter(.none)
    }

    private static func isInteger(_ value: CGFloat) -> Bool {
        abs(value - value.rounded()) <= integerTolerance
    }
}
