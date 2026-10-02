import Accelerate
import CoreGraphics
import Foundation

/// **A keyed window's outline, antialiased at the backing scale (W316).**
///
/// A colour key is binary — a pixel is the skin or it is not — so a keyed window's outline is a
/// staircase one skin pixel to a step, and on a 2x display every step is two device pixels tall.
/// Real WMP drew 1-bit window regions too; this is beyond-WMP polish, not compatibility.
///
/// **The outline is traced, smoothed along its own length, and filled antialiased.** A skin pixel
/// is in the window when any device pixel of it is at least half opaque; the boundary between
/// those and the rest is traced as closed polygons along the pixel edges, every vertex of each
/// polygon is replaced by the average of its neighbours along it, and the result is filled at
/// device resolution. Averaging *along the outline* is what straightens a shallow slope:
/// `BlueCrush_MP7`'s flanks step one pixel across for every four to six down, and a kernel over
/// the pixel grid that only sees a pixel or two either side of a step — the first version of
/// this — trimmed one device pixel per step and left the staircase standing.
///
/// **No vertex moves more than half a skin pixel**, which is as far as any staircase is from the
/// line it approximates. That bound is what keeps artwork as drawn: a one-pixel line's two sides
/// are both straight and stay put, and a real corner is chamfered by half a pixel at most. A
/// polygon shorter than `minimumLoop` — a dot, a small hole — is filled exactly as traced.
///
/// **Only pixels within one skin pixel of the outline are touched.** Fainter artwork further out
/// is never removed: `corona` paints its own soft shadow at alpha 1-60 under its edge.
///
/// `WMP_OUTLINE_FEATHER=0` restores the hard outline — the A/B switch for this rule.
enum WMPOutlineFeather {
    static let isEnabled = ProcessInfo.processInfo.environment["WMP_OUTLINE_FEATHER"] != "0"

    /// Half opacity is the edge, as it is for the effects silhouette.
    private static let opaque: UInt8 = 128

    /// Vertices either side averaged, per pass of two. Two passes of nine is a triangle seventeen
    /// edges long, which straightens a slope of one in six — `BlueCrush_MP7`'s flanks.
    private static let reach = 4

    /// Polygons with fewer edges than this are small artwork and are not smoothed.
    private static let minimumLoop = 24

    /// What one render's outline feather does to its layers: a few thousand pixel edits on the
    /// outline. It is a function of their alpha alone, so a repaint that leaves the alpha alone
    /// reuses it.
    struct Feather {
        /// The device size of the layers it was read off; `apply` leaves any other size alone.
        let width: Int
        let height: Int
        /// The pixels at least half opaque that the smoothed outline only partly covers.
        let cuts: [Cut]
        /// The fainter pixels beside the outline that the smoothed outline covers.
        let growth: [Growth]
    }

    /// A pixel multiplied by `coverage`. Device index, row-major, top-first.
    struct Cut {
        let index: Int32
        let coverage: UInt8
    }

    /// A pixel filled from the opaque pixel `donor` at `coverage`, if that raises it.
    struct Growth {
        let index: Int32
        let donor: Int32
        let coverage: UInt8
    }

    /// Nil when the feather would change nothing. `solid` is canvas rects that are window whatever
    /// the layers hold there — a windowed visualizer, punched out of the overlay.
    static func feather(layers: [CGImage?], canvasSize: WMPSize, backingScale: CGFloat,
                        solid: [WMPRect] = []) -> Feather? {
        let images = layers.compactMap { $0 }
        // An integer scale, which is every backing scale a Mac has: each skin pixel is then an
        // exact block of device pixels, and the grid is a strided read.
        let blockSize = Int(backingScale.rounded())
        guard let first = images.first, blockSize >= 1,
              CGFloat(blockSize) == backingScale else { return nil }
        let skinWidth = Int(canvasSize.width.rounded(.up))
        let skinHeight = Int(canvasSize.height.rounded(.up))
        guard skinWidth > 0, skinHeight > 0,
              first.width == skinWidth * blockSize, first.height == skinHeight * blockSize
        else { return nil }
        let alpha = Plane(width: first.width, height: first.height)
        let coverage = Plane(width: first.width, height: first.height)
        defer { alpha.deallocate(); coverage.deallocate() }
        guard let alphaContext = alpha.context(CGImageAlphaInfo.alphaOnly) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: alpha.width, height: alpha.height)
        for image in images { alphaContext.draw(image, in: bounds) }

        guard let grid = SkinGrid(alpha: alpha, blockSize: blockSize, width: skinWidth,
                                  height: skinHeight, solid: solid) else { return nil }
        let cells = grid.outlineCells()
        guard !cells.isEmpty,
              fill(grid.traceOutline(cells), into: coverage, backingScale: backingScale)
        else { return nil }
        return edits(on: cells, of: grid, alpha: alpha, coverage: coverage, blockSize: blockSize)
    }

    /// `image` with `feather` applied, or `image` itself if it cannot be drawn.
    ///
    /// A filled pixel takes its donor's colour **in this layer**: a donor opaque only in the other
    /// layer has nothing here to lend, and that layer is filled instead.
    static func apply(_ feather: Feather, to image: CGImage) -> CGImage {
        let width = feather.width, height = feather.height
        guard image.width == width, image.height == height,
              let context = CGContext(data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return image }
        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        // Premultiplied, so a cut scales all four channels alike — and the donor's colour at a new
        // alpha is a straight rescale. Cuts first: a donor may be a cut pixel, and lends what is
        // left of it.
        for cut in feather.cuts {
            let pixel = pixels + Int(cut.index) * 4, coverage = Int(cut.coverage)
            for channel in 0..<4 {
                pixel[channel] = UInt8((Int(pixel[channel]) * coverage + 127) / 255)
            }
        }
        for grown in feather.growth {
            let pixel = pixels + Int(grown.index) * 4, donor = pixels + Int(grown.donor) * 4
            let donorAlpha = Int(donor[3])
            guard donorAlpha > 0 else { continue }
            let alpha = Int(grown.coverage) * donorAlpha / 255
            guard alpha > Int(pixel[3]) else { continue }
            for channel in 0..<3 {
                pixel[channel] = UInt8(min(alpha, Int(donor[channel]) * alpha / donorAlpha))
            }
            pixel[3] = UInt8(alpha)
        }
        return context.makeImage() ?? image
    }

    /// `loops` filled antialiased at device resolution into `coverage`, which starts at zero: 255
    /// inside, 0 outside, and the fraction covered in between.
    private static func fill(_ loops: [OutlineLoop], into coverage: Plane,
                             backingScale: CGFloat) -> Bool {
        guard let context = coverage.context(CGImageAlphaInfo.none) else { return false }
        // Skin space is top-first; a bitmap context's row zero is its top, at y = height.
        context.translateBy(x: 0, y: CGFloat(coverage.height))
        context.scaleBy(x: backingScale, y: -backingScale)
        context.setShouldAntialias(true)
        context.setFillColor(gray: 1, alpha: 1)
        let path = CGMutablePath()
        for loop in loops {
            path.addLines(between: loop.outline)
            path.closeSubpath()
        }
        context.addPath(path)
        context.fillPath(using: .winding)
        return true
    }

    /// The edits that take the drawn layers to `coverage`, read only in the skin pixels on the
    /// outline. Nil when there are none.
    private static func edits(on cells: [(x: Int32, y: Int32)], of grid: SkinGrid, alpha: Plane,
                              coverage: Plane, blockSize: Int) -> Feather? {
        let width = alpha.width
        var cuts: [Cut] = []
        var growth: [Growth] = []
        for cell in cells {
            let skinX = Int(cell.x), skinY = Int(cell.y)
            let cellInside = grid.isInside(skinX, skinY)
            for y in (skinY * blockSize)..<((skinY + 1) * blockSize) {
                let alphaLine = alpha.bytes + y * width, covered = coverage.bytes + y * width
                for x in (skinX * blockSize)..<((skinX + 1) * blockSize) {
                    let value = covered[x], index = Int32(y * width + x)
                    if alphaLine[x] >= opaque {
                        if value < 255 { cuts.append(Cut(index: index, coverage: value)) }
                        continue
                    }
                    // A fainter pixel the smoothed outline covers is filled in as the outline, from
                    // the nearest opaque pixel — the inner corner of a step. It is only ever
                    // raised, so faint artwork beside the edge keeps what it had, and **only
                    // outside the traced outline**: a skin pixel already inside it is the artist's
                    // own antialiasing, and filling its faint device pixels to the outline's
                    // coverage turned `Heart_Butterfly`'s soft dotted string into fat beads.
                    guard value > 0, !cellInside,
                          let donor = nearestOpaque(x, y, in: alpha, within: blockSize)
                    else { continue }
                    growth.append(Growth(index: index, donor: Int32(donor), coverage: value))
                }
            }
        }
        guard !cuts.isEmpty || !growth.isEmpty else { return nil }
        return Feather(width: alpha.width, height: alpha.height, cuts: cuts, growth: growth)
    }

    /// The device index of the nearest pixel at least half opaque within `reach` of (x, y) either
    /// way — the most opaque of the nearest — or nil.
    private static func nearestOpaque(_ x: Int, _ y: Int, in alpha: Plane, within reach: Int) -> Int? {
        var donor: Int?, best = Int.max, bestAlpha: UInt8 = 0
        for dy in -reach...reach {
            let ny = y + dy
            guard ny >= 0, ny < alpha.height else { continue }
            let line = alpha.bytes + ny * alpha.width
            for dx in -reach...reach {
                let nx = x + dx
                guard nx >= 0, nx < alpha.width, line[nx] >= opaque else { continue }
                let distance = dx * dx + dy * dy
                if distance < best || (distance == best && line[nx] > bestAlpha) {
                    donor = ny * alpha.width + nx; best = distance; bestAlpha = line[nx]
                }
            }
        }
        return donor
    }

    /// One byte per device pixel, row-major and top-first, zeroed: the layers' alpha, or the
    /// outline's coverage. `feather` owns both and frees them.
    private struct Plane {
        let bytes: UnsafeMutablePointer<UInt8>
        let width: Int
        let height: Int

        init(width: Int, height: Int) {
            bytes = .allocate(capacity: width * height)
            bytes.initialize(repeating: 0, count: width * height)
            self.width = width
            self.height = height
        }

        func deallocate() { bytes.deallocate() }

        /// A grey context drawing straight into `bytes`. Its row zero in memory is its top.
        func context(_ alphaInfo: CGImageAlphaInfo) -> CGContext? {
            CGContext(data: bytes, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                      bitmapInfo: alphaInfo.rawValue)
        }
    }

    /// The skin-pixel grid: which skin pixels are window, and the outline around them.
    ///
    /// A skin pixel is inside wherever any device pixel of it is at least half opaque, so a glyph
    /// stroke thinner than a skin pixel still owns the pixel it is drawn in. Stored with a one-cell
    /// border of outside, so nothing reading it needs a bounds check. **Built and searched
    /// vectorised**: it runs on every render whose alpha moved, and a per-pixel loop cost ~35 ms of
    /// a debug build's frame on `corona`.
    private final class SkinGrid {
        let width: Int
        let height: Int
        private let stride: Int
        /// 1 inside, 0 outside.
        private let cells: UnsafeMutablePointer<Float>
        /// How many of each cell and its eight neighbours are inside: the outline is wherever that
        /// is neither none nor all of them.
        private let neighbourhood: UnsafeMutablePointer<Float>

        /// Nil when nothing is inside.
        init?(alpha: Plane, blockSize: Int, width: Int, height: Int, solid: [WMPRect]) {
            self.width = width
            self.height = height
            stride = width + 2
            let count = stride * (height + 2)
            cells = .allocate(capacity: count)
            neighbourhood = .allocate(capacity: count)
            vDSP_vclr(cells, 1, vDSP_Length(count))

            let row = UnsafeMutablePointer<Float>.allocate(capacity: width)
            defer { row.deallocate() }
            let length = vDSP_Length(width)
            var threshold = Float(WMPOutlineFeather.opaque) - 0.5, half: Float = 0.5
            for y in 0..<height {
                let line = cells + index(0, y)
                for dy in 0..<blockSize {
                    for dx in 0..<blockSize {
                        vDSP_vfltu8(alpha.bytes + (y * blockSize + dy) * alpha.width + dx,
                                    vDSP_Stride(blockSize), row, 1, length)
                        vDSP_vmax(line, 1, row, 1, line, 1, length)
                    }
                }
                vDSP_vthrsc(line, 1, &threshold, &half, line, 1, length)
                vDSP_vsadd(line, 1, &half, line, 1, length)
            }
            for rect in solid where !rect.isEmpty {
                let x0 = max(0, Int(rect.x.rounded(.down))), x1 = min(width, Int(rect.maxX.rounded(.up)))
                let y0 = max(0, Int(rect.y.rounded(.down))), y1 = min(height, Int(rect.maxY.rounded(.up)))
                guard x0 < x1, y0 < y1 else { continue }
                for y in y0..<y1 { for x in x0..<x1 { cells[index(x, y)] = 1 } }
            }
            var total: Float = 0
            vDSP_sve(cells, 1, &total, vDSP_Length(count))
            guard total > 0 else { return nil }

            var source = vImage_Buffer(data: cells, height: vImagePixelCount(height + 2),
                                       width: vImagePixelCount(stride),
                                       rowBytes: stride * MemoryLayout<Float>.stride)
            var destination = vImage_Buffer(data: neighbourhood,
                                            height: vImagePixelCount(height + 2),
                                            width: vImagePixelCount(stride),
                                            rowBytes: stride * MemoryLayout<Float>.stride)
            guard vImageConvolve_PlanarF(&source, &destination, nil, 0, 0,
                                         [Float](repeating: 1, count: 9), 3, 3, 0,
                                         vImage_Flags(kvImageBackgroundColorFill)) == kvImageNoError
            else { return nil }
        }

        deinit {
            cells.deallocate()
            neighbourhood.deallocate()
        }

        private func index(_ x: Int, _ y: Int) -> Int { (y + 1) * stride + x + 1 }

        func isInside(_ x: Int, _ y: Int) -> Bool { cells[index(x, y)] > 0 }

        private func insideCount(_ x: Int, _ y: Int) -> Float { neighbourhood[index(x, y)] }

        /// Every skin pixel on the outline — some but not all of its 3x3 inside — gathered a row at
        /// a time by `vDSP_vcmprs`: a few thousand of a window's ~100,000.
        func outlineCells() -> [(x: Int32, y: Int32)] {
            var found: [(x: Int32, y: Int32)] = []
            let columns = UnsafeMutablePointer<Float>.allocate(capacity: width)
            let gate = UnsafeMutablePointer<Float>.allocate(capacity: width)
            let hits = UnsafeMutablePointer<Float>.allocate(capacity: width)
            defer { columns.deallocate(); gate.deallocate(); hits.deallocate() }
            let length = vDSP_Length(width)
            var zero: Float = 0, one: Float = 1
            vDSP_vramp(&zero, &one, columns, 1, length)
            // Some but not all is |count - 4.5| < 4. `vDSP_vthrsc` makes that -0.5 and the rest
            // +0.5; less a half, the gate is -1 on the outline and 0 off it, and `vDSP_vcmprs`
            // keeps the columns where it is not 0.
            var centre: Float = -4.5, edge: Float = 4, half: Float = 0.5, lessHalf: Float = -0.5
            for y in 0..<height {
                vDSP_vsadd(neighbourhood + index(0, y), 1, &centre, gate, 1, length)
                vDSP_vabs(gate, 1, gate, 1, length)
                vDSP_vthrsc(gate, 1, &edge, &half, gate, 1, length)
                vDSP_vsadd(gate, 1, &lessHalf, gate, 1, length)
                var gated: Float = 0
                vDSP_sve(gate, 1, &gated, length)
                let count = Int((-gated).rounded())
                guard count > 0 else { continue }
                vDSP_vcmprs(columns, 1, gate, 1, hits, 1, length)
                for entry in 0..<count { found.append((Int32(hits[entry]), Int32(y))) }
            }
            return found
        }

        /// The outline as closed polygons in skin coordinates, through the pixel corners, each
        /// walked with the inside on its right in top-first space — so one non-zero fill of all of
        /// them is the window, holes included. `cells` is `outlineCells()`.
        ///
        /// Where two inside pixels touch only at a corner the walk turns toward the inside, so a
        /// diagonal line of pixels is one polygon rather than a chain of squares.
        ///
        /// **A vertex on the edge of small artwork is pinned where it was traced.** Smoothing moves
        /// both sides of a one-pixel line or slit toward each other wherever it bends or ends, which
        /// at 1x thinned all 27 of `Erektorset`'s one-pixel lines and filled 71 of its 120 one-pixel
        /// gaps. An edge borders small artwork when the pixel on either side of it has fewer than
        /// five of its 3x3 neighbourhood on its own side — a staircase step always has six.
        func traceOutline(_ cells: [(x: Int32, y: Int32)]) -> [OutlineLoop] {
            // The pixels either side of the edge leaving (x, y) in `direction`, inside then outside.
            let insideX = [0, -1, -1, 0], insideY = [0, 0, -1, -1]
            let outsideX = [0, 0, -1, -1], outsideY = [-1, 0, 0, -1]
            func small(_ x: Int, _ y: Int, _ direction: Int) -> Bool {
                insideCount(x + insideX[direction], y + insideY[direction]) < 4.5
                    || insideCount(x + outsideX[direction], y + outsideY[direction]) > 4.5
            }
            // Directions: 0 +x, 1 +y, 2 -x, 3 -y. A vertex has at most two edges leaving it.
            let stepX = [1, 0, -1, 0], stepY = [0, 1, 0, -1]
            let vertexWidth = width + 1
            let vertexCount = vertexWidth * (height + 1)
            let outgoing = UnsafeMutablePointer<Int8>.allocate(capacity: vertexCount * 2)
            defer { outgoing.deallocate() }
            outgoing.initialize(repeating: -1, count: vertexCount * 2)
            var starts: [Int] = []
            func add(_ x: Int, _ y: Int, _ direction: Int8) {
                let vertex = y * vertexWidth + x
                if outgoing[vertex * 2] < 0 { outgoing[vertex * 2] = direction }
                else { outgoing[vertex * 2 + 1] = direction }
                starts.append(vertex)
            }
            for cell in cells {
                let x = Int(cell.x), y = Int(cell.y)
                guard isInside(x, y) else { continue }
                if !isInside(x, y - 1) { add(x, y, 0) }
                if !isInside(x + 1, y) { add(x + 1, y, 1) }
                if !isInside(x, y + 1) { add(x + 1, y + 1, 2) }
                if !isInside(x - 1, y) { add(x, y + 1, 3) }
            }
            var loops: [OutlineLoop] = []
            for start in starts {
                guard let firstSlot = [0, 1].first(where: { outgoing[start * 2 + $0] >= 0 })
                else { continue }
                var vertex = start
                var direction = Int(outgoing[start * 2 + firstSlot])
                outgoing[start * 2 + firstSlot] = -1
                var points: [CGPoint] = []
                var pinned: [Bool] = []
                var arrivedSmall = false
                while true {
                    let x = vertex % vertexWidth, y = vertex / vertexWidth
                    points.append(CGPoint(x: x, y: y))
                    let leavingSmall = small(x, y, direction)
                    pinned.append(arrivedSmall || leavingSmall)
                    arrivedSmall = leavingSmall
                    vertex += stepY[direction] * vertexWidth + stepX[direction]
                    // Right first, then straight, then left: a right turn keeps the inside close.
                    var next: Int?
                    for turn in [1, 0, 3] {
                        let wanted = Int8((direction + turn) % 4)
                        if outgoing[vertex * 2] == wanted {
                            outgoing[vertex * 2] = -1; next = Int(wanted); break
                        }
                        if outgoing[vertex * 2 + 1] == wanted {
                            outgoing[vertex * 2 + 1] = -1; next = Int(wanted); break
                        }
                    }
                    guard let next else { break }
                    direction = next
                }
                // The first vertex was reached again by the last edge.
                if arrivedSmall, !pinned.isEmpty { pinned[0] = true }
                if points.count >= 4 { loops.append(OutlineLoop(points: points, pinned: pinned)) }
            }
            return loops
        }
    }

    /// One closed polygon of the outline, as traced.
    private struct OutlineLoop {
        let points: [CGPoint]
        /// Per point: on the edge of small artwork, so it stays where it was traced.
        let pinned: [Bool]

        /// The polygon that is filled: smoothed, unless it is too short to be anything but small
        /// artwork.
        var outline: [CGPoint] { points.count >= minimumLoop ? smoothed() : points }

        /// Each vertex the average of up to `reach` either side of it along the loop, twice, then
        /// held within half a skin pixel of where it was traced.
        ///
        /// **A pinned vertex stays put and bounds its neighbours' windows**, which shrink
        /// symmetrically as they near it. Averaging across a square corner while pinning only the
        /// corner itself sagged the edges either side of it into a wave and left the corner
        /// standing proud as a spike; bounded, a straight edge between two square corners averages
        /// only points on itself, and stays straight.
        private func smoothed() -> [CGPoint] {
            let count = points.count
            // How far each vertex may look either way before it reaches a pin, capped at `reach`.
            var window = [Int](repeating: reach, count: count)
            if let anyPin = pinned.firstIndex(of: true) {
                var distance = 0
                for step in 0..<count {
                    let index = (anyPin + step) % count
                    distance = pinned[index] ? 0 : distance + 1
                    window[index] = min(reach, distance)
                }
                distance = 0
                for step in 0..<count {
                    let index = ((anyPin - step) % count + count) % count
                    distance = pinned[index] ? 0 : distance + 1
                    window[index] = min(window[index], distance)
                }
            }
            var smoothed = points
            for _ in 0..<2 {
                var next = smoothed
                for index in 0..<count where window[index] > 0 {
                    var sumX: CGFloat = 0, sumY: CGFloat = 0
                    for offset in -window[index]...window[index] {
                        let point = smoothed[((index + offset) % count + count) % count]
                        sumX += point.x; sumY += point.y
                    }
                    let size = CGFloat(window[index] * 2 + 1)
                    next[index] = CGPoint(x: sumX / size, y: sumY / size)
                }
                smoothed = next
            }
            for index in 0..<count {
                smoothed[index] = CGPoint(
                    x: min(points[index].x + 0.5, max(points[index].x - 0.5, smoothed[index].x)),
                    y: min(points[index].y + 0.5, max(points[index].y - 0.5, smoothed[index].y)))
            }
            return smoothed
        }
    }
}
