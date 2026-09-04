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
    ///
    /// **This is a per-frame `width × height` loop on the main thread** for any layer whose mesh
    /// moves — B118 measured the `Double` form this replaces at **24.1%** of a release build's main
    /// thread on WMP11-BlueVU, against a control skin's 0.0% — so the shape below is deliberate, and
    /// each part of it is worth a measured 264×264 frame (Defix's needle size, the corpus's largest):
    ///
    /// | | ms/frame |
    /// |---|---|
    /// | `Double`, four-corner lerp per pixel, `accumulate` closure | 2.05 |
    /// | `Float` | 1.53 |
    /// | fixed-point channels | 1.22 |
    /// | + `SIMD4` channels (this) | **0.73** |
    ///
    /// The three changes are:
    ///
    /// - **The mesh is interpolated once per destination row** into `rowU`/`rowV`, and the walk along
    ///   each axis is incremental — `column0` advances with a `while` that steps at most once per
    ///   mesh column per row — so the inner loop has two lerps and no divide, where the four-corner
    ///   form had eight lerps, two divides and two float→`Int` conversions per pixel.
    /// - **The four channels are one `SIMD4`**, gathered from the four taps with an unaligned load
    ///   each. The old code accumulated into a tuple of `Double` through a local function taking it
    ///   `inout`, which is four separate round-trips per pixel.
    /// - **The blend is fixed-point**, weights in 10 bits, so the hot path has no float→integer
    ///   conversion (each of which is bounds-checked and traps) and no per-channel clamp: the four
    ///   weights sum to exactly `1 << 20`, so the rounded sum of four bytes is a byte by
    ///   construction. Against the `Double` form this moves 4% of channels by exactly 1.
    func resample(source: [UInt8], width: Int, height: Int) -> [UInt8]? {
        guard columns >= 2, rows >= 2, sources.count == columns * rows,
              width > 0, height > 0, source.count == width * height * 4 else { return nil }
        var destination = [UInt8](repeating: 0, count: width * height * 4)
        let columns = self.columns
        let rows = self.rows
        let wrap = self.wrap
        let bilinear = self.bilinear
        let widthAsFloat = Float(width)
        let heightAsFloat = Float(height)
        // Destination pixel → mesh coordinate is linear on both axes, so the walk below is one add
        // per pixel from a step computed here rather than a divide per pixel.
        let columnStep = Float(columns - 1) / widthAsFloat
        let rowStep = Float(rows - 1) / heightAsFloat

        // The vertices flattened to `Float`, so the loop never converts a `CGPoint`'s `Double` again.
        var vertexU = [Float](repeating: 0, count: columns * rows)
        var vertexV = [Float](repeating: 0, count: columns * rows)
        for index in 0..<(columns * rows) {
            vertexU[index] = Float(sources[index].x)
            vertexV[index] = Float(sources[index].y)
        }
        /// The mesh row under the destination row being filled, already interpolated in y.
        var rowU = [Float](repeating: 0, count: columns)
        var rowV = [Float](repeating: 0, count: columns)

        vertexU.withUnsafeBufferPointer { vertexU in
        vertexV.withUnsafeBufferPointer { vertexV in
        rowU.withUnsafeMutableBufferPointer { rowU in
        rowV.withUnsafeMutableBufferPointer { rowV in
        source.withUnsafeBufferPointer { sourceBuffer in
        destination.withUnsafeMutableBufferPointer { destinationBuffer in
            let sourceBytes = UnsafeRawPointer(sourceBuffer.baseAddress!)
            let destinationBytes = UnsafeMutableRawPointer(destinationBuffer.baseAddress!)
            var meshY = 0.5 * rowStep
            var row0 = 0
            for y in 0..<height {
                defer { meshY += rowStep }
                while row0 < rows - 2 && meshY >= Float(row0 + 1) { row0 += 1 }
                let ty = max(0, meshY - Float(row0))
                let top = row0 * columns
                let bottom = top + columns
                for column in 0..<columns {
                    rowU[column] = vertexU[top + column] + (vertexU[bottom + column] - vertexU[top + column]) * ty
                    rowV[column] = vertexV[top + column] + (vertexV[bottom + column] - vertexV[top + column]) * ty
                }

                var destinationIndex = y * width * 4
                var meshX = 0.5 * columnStep
                var column0 = 0
                for _ in 0..<width {
                    defer { destinationIndex += 4; meshX += columnStep }
                    while column0 < columns - 2 && meshX >= Float(column0 + 1) { column0 += 1 }
                    let tx = max(0, meshX - Float(column0))
                    let leftU = rowU[column0], leftV = rowV[column0]
                    let sourceU = leftU + (rowU[column0 + 1] - leftU) * tx
                    let sourceV = leftV + (rowV[column0 + 1] - leftV) * tx
                    guard sourceU.isFinite, sourceV.isFinite else { continue }
                    // Sampling past the edge of a layer that does not wrap draws nothing:
                    // clamping instead would smear the edge pixel across everything the warp
                    // sweeps, and a needle would trail a comb of streaks behind it.
                    if !wrap, sourceU < 0 || sourceU > 1 || sourceV < 0 || sourceV > 1 { continue }
                    let sampleX = sourceU * widthAsFloat - 0.5
                    let sampleY = sourceV * heightAsFloat - 0.5
                    // A wrapping mesh may answer with a coordinate arbitrarily far outside the layer,
                    // and float→`Int` traps rather than saturating. `tap` folds anything inside this
                    // bound back into the layer; past it there is no meaningful pixel to fetch.
                    guard abs(sampleX) < 1e7, abs(sampleY) < 1e7 else { continue }

                    let pixel: SIMD4<UInt8>
                    if bilinear {
                        let flooredX = sampleX.rounded(.down)
                        let flooredY = sampleY.rounded(.down)
                        let fx = UInt32((sampleX - flooredX) * 1024)
                        let fy = UInt32((sampleY - flooredY) * 1024)
                        let left = Self.tap(Int(flooredX), width, wrap)
                        let right = Self.tap(Int(flooredX) + 1, width, wrap)
                        let above = Self.tap(Int(flooredY), height, wrap) * width
                        let below = Self.tap(Int(flooredY) + 1, height, wrap) * width
                        var total = Self.tapPixel(sourceBytes, (above + left) * 4) &* SIMD4(repeating: (1024 - fx) * (1024 - fy))
                        total &+= Self.tapPixel(sourceBytes, (above + right) * 4) &* SIMD4(repeating: fx * (1024 - fy))
                        total &+= Self.tapPixel(sourceBytes, (below + left) * 4) &* SIMD4(repeating: (1024 - fx) * fy)
                        total &+= Self.tapPixel(sourceBytes, (below + right) * 4) &* SIMD4(repeating: fx * fy)
                        pixel = SIMD4<UInt8>(truncatingIfNeeded: (total &+ SIMD4(repeating: 1 << 19)) &>> SIMD4(repeating: 20))
                    } else {
                        let index = (Self.tap(Int(sampleY.rounded()), height, wrap) * width
                                     + Self.tap(Int(sampleX.rounded()), width, wrap)) * 4
                        pixel = sourceBytes.loadUnaligned(fromByteOffset: index, as: SIMD4<UInt8>.self)
                    }
                    destinationBytes.storeBytes(of: pixel, toByteOffset: destinationIndex, as: SIMD4<UInt8>.self)
                }
            }
        }}}}}}
        return destination
    }

    /// One sample coordinate brought inside the layer, with the layer's own wrap/clamp rule.
    @inline(__always)
    private static func tap(_ coordinate: Int, _ extent: Int, _ wrap: Bool) -> Int {
        wrap ? ((coordinate % extent) + extent) % extent : min(extent - 1, max(0, coordinate))
    }

    /// One RGBA8 source pixel widened to the lanes the fixed-point blend accumulates in. The source
    /// raster is an `[UInt8]`, whose base address carries no four-byte alignment guarantee.
    @inline(__always)
    private static func tapPixel(_ source: UnsafeRawPointer, _ byteOffset: Int) -> SIMD4<UInt32> {
        SIMD4<UInt32>(truncatingIfNeeded: source.loadUnaligned(fromByteOffset: byteOffset, as: SIMD4<UInt8>.self))
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
