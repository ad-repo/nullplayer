import CoreGraphics

/// Chooses filtering for `.wal` artwork from the UI-to-device scale.
/// Exact integer UI enlargement keeps authored pixels crisp even when the skin stretches an asset
/// within that space; fractional scaling and every actual downscale remain smooth.
enum WasabiBitmapInterpolationPolicy {
    private static let integerTolerance: CGFloat = 0.001

    static func quality(sourcePixelSize: CGSize, destination: CGRect,
                        in context: CGContext) -> CGInterpolationQuality {
        guard sourcePixelSize.width > 0, sourcePixelSize.height > 0,
              destination.width > 0, destination.height > 0 else { return .high }

        let transform = context.ctm
        let deviceRect = destination.applying(transform).standardized
        // Downscaling is about the bitmap's actual output size, not the surrounding UI scale.
        guard deviceRect.width >= sourcePixelSize.width - integerTolerance,
              deviceRect.height >= sourcePixelSize.height - integerTolerance else { return .high }

        // Stretching an authored bitmap does not change which UI Size stop the user selected. The
        // filter follows the basis vectors of the CTM, so 100% on Retina is 2x even when a skin
        // makes (for example) a logo a few points wider than its source raster.
        let horizontalScale = hypot(transform.a, transform.b)
        let verticalScale = hypot(transform.c, transform.d)
        guard horizontalScale >= 1 - integerTolerance,
              verticalScale >= 1 - integerTolerance,
              isInteger(horizontalScale), isInteger(verticalScale) else { return .high }
        return .none
    }

    static func quality(sourceWidth: Int, sourceHeight: Int,
                        destinationWidth: Int, destinationHeight: Int) -> CGInterpolationQuality {
        guard sourceWidth > 0, sourceHeight > 0,
              destinationWidth > 0, destinationHeight > 0 else { return .high }
        let horizontal = CGFloat(destinationWidth) / CGFloat(sourceWidth)
        let vertical = CGFloat(destinationHeight) / CGFloat(sourceHeight)
        guard horizontal >= 1, vertical >= 1,
              isInteger(horizontal), isInteger(vertical) else { return .high }
        return .none
    }

    private static func isInteger(_ value: CGFloat) -> Bool {
        abs(value - value.rounded()) <= integerTolerance
    }
}
