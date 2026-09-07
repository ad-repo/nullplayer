import AppKit
import CoreGraphics
import Foundation

/// The Layer FX warp: mesh resampling for `fx_*` layers, and the two caches that keep a
/// per-frame warp off the CPU. Split out of `WasabiRenderer.swift`; see
/// `skills/winamp-modern-skin-guide/reference/rendering.md`.
extension WasabiSceneRenderer {
    /// Largest warped surface, per axis. A warp is a CPU resample of the whole layer, so the work is
    /// its area; every FX layer measured in the corpus is a few hundred pixels square (Defix's
    /// needles are 264×264), and this is the ceiling that keeps a skin asking for a full-window warp
    /// off the frame budget.
    private static let maximumWarpExtent = 1_024

    /// Draw `image` warped by `mesh`, filling `rect`. Returns false when the warp could not be built,
    /// so the caller can fall back to the layer's ordinary draw rather than paint nothing.
    ///
    /// The mesh gives the source coordinate at each grid **vertex**; every destination pixel takes
    /// its source from the bilinear interpolation of the four vertices around it. A rotation is
    /// affine in x/y, so a 1×1 grid — Defix's cassette reels — reproduces one exactly, and a warp
    /// that is not affine gets as much fidelity as the grid the skin asked for.
    @discardableResult
    func drawWarped(_ image: CGImage, in rect: CGRect, mesh: WasabiLayerFXMesh,
                            context: CGContext) -> Bool {
        let width = min(Self.maximumWarpExtent, max(1, Int(rect.width.rounded())))
        let height = min(Self.maximumWarpExtent, max(1, Int(rect.height.rounded())))
        let key = WarpSourceKey(image: ObjectIdentifier(image), width: width, height: height)
        // The resample is the expensive half of the warp and it depends on nothing but the source
        // raster and the mesh. A repaint the *skin* did not ask for — the window invalidating a rect
        // for its own reasons, a neighbouring object moving, a partial repaint being widened by
        // AppKit — would otherwise re-run the whole pixel loop for a warp that has not moved a
        // vertex since the last frame.
        if let cached = warpedImageCache[key], cached.mesh == mesh {
            drawImage(cached.image, in: rect, context: context)
            return true
        }
        guard let source = warpSourcePixels(image, width: width, height: height),
              let warpedPixels = mesh.resample(source: source, width: width, height: height),
              let warped = Self.image(fromPixels: warpedPixels, width: width, height: height)
        else { return false }
        // Bounded for the same reason as `warpSourceCache`: one entry per FX layer, and a skin has a
        // handful of them.
        if warpedImageCache.count > 16 { warpedImageCache.removeAll() }
        warpedImageCache[key] = (image, mesh, warped)
        drawImage(warped, in: rect, context: context)
        return true
    }

    /// The layer's own image rasterized at the size it draws at, in top-left row order — the space
    /// the mesh's normalized coordinates are in. Cached: the source only changes when the layer's
    /// bitmap or its box does, while the mesh changes every frame a meter moves.
    private func warpSourcePixels(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
        let key = WarpSourceKey(image: ObjectIdentifier(image), width: width, height: height)
        if let cached = warpSourceCache[key] { return cached.pixels }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = WasabiBitmapInterpolationPolicy.quality(
                sourceWidth: image.width, sourceHeight: image.height,
                destinationWidth: width, destinationHeight: height)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        // Bounded: a handful of FX layers per skin, and one entry each. Cleared wholesale rather than
        // aged, because the only thing that invalidates an entry is the layer being redrawn at a
        // different size, which happens on resize and theme changes.
        if warpSourceCache.count > 16 { warpSourceCache.removeAll() }
        warpSourceCache[key] = (image, pixels)
        return pixels
    }

    struct WarpSourceKey: Hashable {
        let image: ObjectIdentifier
        let width: Int
        let height: Int
    }

    private static func image(fromPixels pixels: [UInt8], width: Int, height: Int) -> CGImage? {
        var pixels = pixels
        return pixels.withUnsafeMutableBytes { bytes -> CGImage? in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            return context.makeImage()
        }
    }
}
