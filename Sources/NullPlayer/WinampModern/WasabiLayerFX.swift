import CoreGraphics
import Foundation

/// Winamp's **Layer FX** — the per-layer image warp a `.wal` skin drives from MAKI.
///
/// A layer that turns FX on is covered by a grid of `fx_setGridSize(x, y)` cells. For every grid
/// **vertex** Winamp calls back into the skin with that point's polar coordinates (`r` the angle in
/// radians, `d` the distance from the layer's centre) and its rectangular `(x, y)`, and the script
/// answers with the coordinate to **sample from**. The image is then drawn as that warped mesh,
/// interpolating between vertices — so the callback runs per vertex per frame, not per pixel, which
/// is what makes it tractable through an interpreted VM.
///
/// The naming is Winamp's and it is not what it looks like: `fx_onGetPixelR` answers with the source
/// **angle** and `fx_onGetPixelD` with the source **distance** (`R` for rotation, `D` for distance).
/// Measured, not guessed — Defix's needle and cassette scripts implement only `fx_onGetPixelR` and
/// return `argument0 + rotation`, where `rotation` is a value the timer computes in degrees and
/// divides by 57.295 (180/π) before storing. A radius answer would translate the needle radially
/// instead of sweeping it, and the reference video sweeps it.
struct WasabiLayerFXState: Equatable {
    var enabled = false
    /// Rectangular (`fx_onGetPixelX`/`Y`) rather than polar (`R`/`D`) callbacks.
    var rect = false
    /// Sampling past the edge wraps around instead of clamping to the edge pixel.
    var wrap = false
    var bilinear = true
    var localized = true
    var clear = false
    /// Warp what is *behind* the layer rather than the layer's own image. Not implemented: nothing
    /// in the measured corpus asks for it (Defix sets `fx_setBgFx(0)` on every FX layer), and the
    /// scene is composited straight into one context with no per-layer backdrop to resample.
    var backgroundFX = false
    /// Re-evaluate the mesh every frame rather than only when the skin calls `fx_update()`.
    var realtime = false
    var speedMilliseconds: Int32 = 0
    var alphaMode = false
    var gridX = 8
    var gridY = 8

    /// Winamp's grid is a count of **cells**; a 1×1 grid is the four corners of the layer. A pure
    /// rotation is affine in x/y, so interpolating the corner samples reproduces it exactly — which
    /// is why Defix's cassette reels ask for 1×1 and still spin cleanly.
    static let maximumGridCells = 64

    var vertexColumns: Int { min(Self.maximumGridCells, max(1, gridX)) + 1 }
    var vertexRows: Int { min(Self.maximumGridCells, max(1, gridY)) + 1 }
}

/// The evaluated warp for one layer: where each destination grid vertex samples **from**, in
/// normalized layer coordinates (0…1, top-left origin, the same space the callbacks are handed).
struct WasabiLayerFXMesh: Equatable {
    let columns: Int
    let rows: Int
    /// Row-major, `columns * rows` entries.
    let sources: [CGPoint]
    let wrap: Bool
    let bilinear: Bool

    /// Resample one layer through this mesh.
    ///
    /// `source` is the layer's own image rasterized at `width × height`, RGBA8 premultiplied, row 0
    /// at the top — the orientation the mesh's normalized coordinates are in. Every destination pixel
    /// takes its source from the bilinear interpolation of the four grid vertices around it: a
    /// rotation is affine in x/y, so even a 1×1 grid (Defix's cassette reels) reproduces one exactly,
    /// and a genuinely non-affine warp gets the fidelity of the grid the skin asked for.
    func resample(source: [UInt8], width: Int, height: Int) -> [UInt8]? {
        guard columns >= 2, rows >= 2, sources.count == columns * rows,
              width > 0, height > 0, source.count == width * height * 4 else { return nil }
        var destination = [UInt8](repeating: 0, count: width * height * 4)
        let columns = self.columns
        let rows = self.rows
        let wrap = self.wrap
        let bilinear = self.bilinear
        sources.withUnsafeBufferPointer { vertices in
            source.withUnsafeBufferPointer { source in
                destination.withUnsafeMutableBufferPointer { destination in
                    /// One source pixel, with the layer's own wrap/clamp rule at the edges.
                    func accumulate(_ x: Int, _ y: Int, into channels: inout (Double, Double, Double, Double),
                                    weight: Double) {
                        let sampleX = wrap ? ((x % width) + width) % width : min(width - 1, max(0, x))
                        let sampleY = wrap ? ((y % height) + height) % height : min(height - 1, max(0, y))
                        let index = (sampleY * width + sampleX) * 4
                        channels.0 += Double(source[index]) * weight
                        channels.1 += Double(source[index + 1]) * weight
                        channels.2 += Double(source[index + 2]) * weight
                        channels.3 += Double(source[index + 3]) * weight
                    }

                    for y in 0..<height {
                        let v = (Double(y) + 0.5) / Double(height)
                        let meshY = min(Double(rows - 1) - 1e-9, max(0, v * Double(rows - 1)))
                        let row0 = min(rows - 2, Int(meshY))
                        let ty = meshY - Double(row0)
                        for x in 0..<width {
                            let u = (Double(x) + 0.5) / Double(width)
                            let meshX = min(Double(columns - 1) - 1e-9, max(0, u * Double(columns - 1)))
                            let column0 = min(columns - 2, Int(meshX))
                            let tx = meshX - Double(column0)
                            let topLeft = vertices[row0 * columns + column0]
                            let topRight = vertices[row0 * columns + column0 + 1]
                            let bottomLeft = vertices[(row0 + 1) * columns + column0]
                            let bottomRight = vertices[(row0 + 1) * columns + column0 + 1]
                            let sourceU = (Double(topLeft.x) * (1 - tx) + Double(topRight.x) * tx) * (1 - ty)
                                + (Double(bottomLeft.x) * (1 - tx) + Double(bottomRight.x) * tx) * ty
                            let sourceV = (Double(topLeft.y) * (1 - tx) + Double(topRight.y) * tx) * (1 - ty)
                                + (Double(bottomLeft.y) * (1 - tx) + Double(bottomRight.y) * tx) * ty
                            guard sourceU.isFinite, sourceV.isFinite else { continue }
                            // Sampling past the edge of a layer that does not wrap draws nothing:
                            // clamping instead would smear the edge pixel across everything the warp
                            // sweeps, and a needle would trail a comb of streaks behind it.
                            if !wrap, sourceU < 0 || sourceU > 1 || sourceV < 0 || sourceV > 1 { continue }
                            let sampleX = sourceU * Double(width) - 0.5
                            let sampleY = sourceV * Double(height) - 0.5
                            var channels = (0.0, 0.0, 0.0, 0.0)
                            if bilinear {
                                let x0 = Int(sampleX.rounded(.down))
                                let y0 = Int(sampleY.rounded(.down))
                                let fx = sampleX - Double(x0)
                                let fy = sampleY - Double(y0)
                                accumulate(x0, y0, into: &channels, weight: (1 - fx) * (1 - fy))
                                accumulate(x0 + 1, y0, into: &channels, weight: fx * (1 - fy))
                                accumulate(x0, y0 + 1, into: &channels, weight: (1 - fx) * fy)
                                accumulate(x0 + 1, y0 + 1, into: &channels, weight: fx * fy)
                            } else {
                                accumulate(Int(sampleX.rounded()), Int(sampleY.rounded()),
                                           into: &channels, weight: 1)
                            }
                            let index = (y * width + x) * 4
                            destination[index] = UInt8(min(255, max(0, channels.0.rounded())))
                            destination[index + 1] = UInt8(min(255, max(0, channels.1.rounded())))
                            destination[index + 2] = UInt8(min(255, max(0, channels.2.rounded())))
                            destination[index + 3] = UInt8(min(255, max(0, channels.3.rounded())))
                        }
                    }
                }
            }
        }
        return destination
    }

    /// A mesh that samples every destination pixel from its own position — the layer drawn as-is.
    var isIdentity: Bool {
        for row in 0..<rows {
            for column in 0..<columns {
                let point = sources[row * columns + column]
                let x = CGFloat(column) / CGFloat(max(1, columns - 1))
                let y = CGFloat(row) / CGFloat(max(1, rows - 1))
                if abs(point.x - x) > 0.0005 || abs(point.y - y) > 0.0005 { return false }
            }
        }
        return true
    }
}

/// The coordinate conventions the callbacks are handed and answer in, in one place so the forward
/// (destination → polar) and inverse (polar → source) halves cannot drift apart.
///
/// Normalized layer space is 0…1 on both axes with a top-left origin, matching the space every other
/// bitmap in this renderer is drawn in; the centre is (0.5, 0.5). The angle grows clockwise on
/// screen, because y grows downward — the same handedness Winamp's own screen space has. The
/// distance is scaled so that the edge midpoints sit at 1.0. A skin that only *rotates* (the whole
/// measured corpus) is invariant to that scaling, since the same normalization is used both ways.
enum WasabiLayerFXCoordinates {
    static func angle(x: CGFloat, y: CGFloat) -> CGFloat { atan2(y - 0.5, x - 0.5) }
    static func distance(x: CGFloat, y: CGFloat) -> CGFloat { 2 * hypot(x - 0.5, y - 0.5) }

    static func point(angle: CGFloat, distance: CGFloat) -> CGPoint {
        CGPoint(x: 0.5 + distance / 2 * cos(angle), y: 0.5 + distance / 2 * sin(angle))
    }
}
