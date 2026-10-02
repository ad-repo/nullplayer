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

    /// What one render's outline feather does to its layers. It is a function of their alpha
    /// alone, so a repaint that leaves the alpha alone reuses it.
    struct Feather {
        /// 8-bit grey, top-first, the layers' own device size, 255 keeps: what every pixel at
        /// least half opaque is multiplied by. Nil when it would keep everything.
        let shrink: CGImage?
        /// The fainter pixels beside the outline that the smoothed outline covers, each filled
        /// from the nearest opaque pixel at `coverage`. Device indices, row-major, top-first.
        let growth: [Growth]
    }

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
        let width = first.width, height = first.height
        let skinWidth = Int(canvasSize.width.rounded(.up))
        let skinHeight = Int(canvasSize.height.rounded(.up))
        guard width > 0, height > 0, skinWidth > 0, skinHeight > 0,
              skinWidth * blockSize <= width, skinHeight * blockSize <= height,
              let alphaContext = CGContext(data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue),
              let alphaData = alphaContext.data else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        for image in images { alphaContext.draw(image, in: bounds) }
        let alphaRow = alphaContext.bytesPerRow
        let alpha = alphaData.bindMemory(to: UInt8.self, capacity: alphaRow * height)

        // The skin-pixel grid, 1 inside and 0 outside, with a one-cell border of outside so that
        // nothing below needs a bounds check. **Vectorised, as is finding the outline below**: it
        // runs on every render whose alpha moved, and a per-pixel loop cost ~35 ms of a debug
        // build's frame on `corona`.
        let gridWidth = skinWidth + 2, gridHeight = skinHeight + 2
        let gridCount = gridWidth * gridHeight
        let grid = UnsafeMutablePointer<Float>.allocate(capacity: gridCount)
        let row = UnsafeMutablePointer<Float>.allocate(capacity: skinWidth)
        defer { grid.deallocate(); row.deallocate() }
        vDSP_vclr(grid, 1, vDSP_Length(gridCount))
        var threshold = Float(opaque) - 0.5, half: Float = 0.5
        for skinY in 0..<skinHeight {
            let cells = grid + (skinY + 1) * gridWidth + 1
            // In wherever any device pixel of it is at least half opaque, so a glyph stroke
            // thinner than a skin pixel still owns the pixel it is drawn in.
            for dy in 0..<blockSize {
                for dx in 0..<blockSize {
                    vDSP_vfltu8(alpha + (skinY * blockSize + dy) * alphaRow + dx,
                                vDSP_Stride(blockSize), row, 1, vDSP_Length(skinWidth))
                    vDSP_vmax(cells, 1, row, 1, cells, 1, vDSP_Length(skinWidth))
                }
            }
            vDSP_vthrsc(cells, 1, &threshold, &half, cells, 1, vDSP_Length(skinWidth))
            vDSP_vsadd(cells, 1, &half, cells, 1, vDSP_Length(skinWidth))
        }
        for rect in solid where !rect.isEmpty {
            let x0 = max(0, Int(rect.x.rounded(.down))), x1 = min(skinWidth, Int(rect.maxX.rounded(.up)))
            let y0 = max(0, Int(rect.y.rounded(.down))), y1 = min(skinHeight, Int(rect.maxY.rounded(.up)))
            guard x0 < x1, y0 < y1 else { continue }
            for y in y0..<y1 { for x in x0..<x1 { grid[(y + 1) * gridWidth + x + 1] = 1 } }
        }
        var total: Float = 0
        vDSP_sve(grid, 1, &total, vDSP_Length(gridCount))
        guard total > 0 else { return nil }

        // How many of each skin pixel and its eight neighbours are inside: the outline is
        // wherever that is neither none nor all of them.
        let neighbourhood = UnsafeMutablePointer<Float>.allocate(capacity: gridCount)
        defer { neighbourhood.deallocate() }
        var source = vImage_Buffer(data: grid, height: vImagePixelCount(gridHeight),
                                   width: vImagePixelCount(gridWidth),
                                   rowBytes: gridWidth * MemoryLayout<Float>.stride)
        var destination = vImage_Buffer(data: neighbourhood, height: vImagePixelCount(gridHeight),
                                        width: vImagePixelCount(gridWidth),
                                        rowBytes: gridWidth * MemoryLayout<Float>.stride)
        guard vImageConvolve_PlanarF(&source, &destination, nil, 0, 0,
                                     [Float](repeating: 1, count: 9), 3, 3, 0,
                                     vImage_Flags(kvImageBackgroundColorFill)) == kvImageNoError
        else { return nil }

        // Every skin pixel near the outline, gathered a row at a time by `vDSP_vcmprs` — a few
        // thousand of a window's ~100,000.
        var nearOutline: [(x: Int32, y: Int32)] = []
        let columns = UnsafeMutablePointer<Float>.allocate(capacity: skinWidth)
        let gate = UnsafeMutablePointer<Float>.allocate(capacity: skinWidth)
        let found = UnsafeMutablePointer<Float>.allocate(capacity: skinWidth)
        defer { columns.deallocate(); gate.deallocate(); found.deallocate() }
        var zero: Float = 0, step: Float = 1
        vDSP_vramp(&zero, &step, columns, 1, vDSP_Length(skinWidth))
        var centre: Float = -4.5, edge: Float = 4, one: Float = 1
        for skinY in 0..<skinHeight {
            // |count - 4.5| < 4 is 1 through 8 of 9; the gate is -1 there and 0 everywhere else.
            vDSP_vsadd(neighbourhood + (skinY + 1) * gridWidth + 1, 1, &centre, gate, 1,
                       vDSP_Length(skinWidth))
            vDSP_vabs(gate, 1, gate, 1, vDSP_Length(skinWidth))
            vDSP_vthrsc(gate, 1, &edge, &half, gate, 1, vDSP_Length(skinWidth))
            vDSP_vsadd(gate, 1, &half, gate, 1, vDSP_Length(skinWidth))
            vDSP_vsub(&one, 0, gate, 1, gate, 1, vDSP_Length(skinWidth))
            var gated: Float = 0
            vDSP_sve(gate, 1, &gated, vDSP_Length(skinWidth))
            let count = Int((-gated).rounded())
            guard count > 0 else { continue }
            vDSP_vcmprs(columns, 1, gate, 1, found, 1, vDSP_Length(skinWidth))
            for entry in 0..<count { nearOutline.append((Int32(found[entry]), Int32(skinY))) }
        }
        guard !nearOutline.isEmpty else { return nil }

        let loops = traceOutline(nearOutline, grid: grid, neighbourhood: neighbourhood,
                                 gridWidth: gridWidth, skinWidth: skinWidth,
                                 skinHeight: skinHeight)
        guard let coverageContext = CGContext(data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let coverageData = coverageContext.data else { return nil }
        coverageContext.setFillColor(gray: 0, alpha: 1)
        coverageContext.fill(bounds)
        // Skin space is top-first; a bitmap context's row zero is its top, at y = height.
        coverageContext.translateBy(x: 0, y: CGFloat(height))
        coverageContext.scaleBy(x: backingScale, y: -backingScale)
        coverageContext.setShouldAntialias(true)
        coverageContext.setFillColor(gray: 1, alpha: 1)
        let path = CGMutablePath()
        for loop in loops {
            path.addLines(between: loop.points.count >= minimumLoop
                ? smoothed(loop.points, pinned: loop.pinned) : loop.points)
            path.closeSubpath()
        }
        coverageContext.addPath(path)
        coverageContext.fillPath(using: .winding)
        let coverageRow = coverageContext.bytesPerRow
        let coverage = coverageData.bindMemory(to: UInt8.self, capacity: coverageRow * height)

        let mask = UnsafeMutablePointer<UInt8>.allocate(capacity: width * height)
        mask.initialize(repeating: 255, count: width * height)
        var cuts = false
        var growth: [Growth] = []
        for cell in nearOutline {
            let skinX = Int(cell.x), skinY = Int(cell.y)
            let endColumn = skinX == skinWidth - 1 ? width : (skinX + 1) * blockSize
            let endRow = skinY == skinHeight - 1 ? height : (skinY + 1) * blockSize
            let cellInside = grid[(skinY + 1) * gridWidth + skinX + 1] > 0
            for y in (skinY * blockSize)..<endRow {
                let alphaLine = alpha + y * alphaRow, covered = coverage + y * coverageRow
                for x in (skinX * blockSize)..<endColumn {
                    let value = covered[x]
                    if alphaLine[x] >= opaque {
                        if value < 255 { mask[y * width + x] = value; cuts = true }
                        continue
                    }
                    // A fainter pixel the smoothed outline covers is filled in as the outline, from
                    // the nearest opaque pixel — the inner corner of a step. It is only ever
                    // raised, so faint artwork beside the edge keeps what it had, and **only
                    // outside the traced outline**: a skin pixel already inside it is the artist's
                    // own antialiasing, and filling its faint device pixels to the outline's
                    // coverage turned `Heart_Butterfly`'s soft dotted string into fat beads.
                    guard value > 0, !cellInside else { continue }
                    var donor = -1, best = Int.max, bestAlpha: UInt8 = 0
                    for dy in -blockSize...blockSize {
                        let ny = y + dy
                        guard ny >= 0, ny < height else { continue }
                        let line = alpha + ny * alphaRow
                        for dx in -blockSize...blockSize {
                            let nx = x + dx
                            guard nx >= 0, nx < width, line[nx] >= opaque else { continue }
                            let distance = dx * dx + dy * dy
                            if distance < best || (distance == best && line[nx] > bestAlpha) {
                                donor = ny * width + nx; best = distance; bestAlpha = line[nx]
                            }
                        }
                    }
                    guard donor >= 0 else { continue }
                    growth.append(Growth(index: Int32(y * width + x), donor: Int32(donor),
                                         coverage: value))
                }
            }
        }
        var shrink: CGImage?
        if cuts {
            let bytes = Data(bytesNoCopy: mask, count: width * height,
                             deallocator: .custom { pointer, _ in pointer.deallocate() })
            if let provider = CGDataProvider(data: bytes as CFData) {
                shrink = CGImage(width: width, height: height, bitsPerComponent: 8,
                                 bitsPerPixel: 8, bytesPerRow: width,
                                 space: CGColorSpaceCreateDeviceGray(),
                                 bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                 provider: provider, decode: nil, shouldInterpolate: false,
                                 intent: .defaultIntent)
            }
        } else {
            mask.deallocate()
        }
        guard shrink != nil || !growth.isEmpty else { return nil }
        return Feather(shrink: shrink, growth: growth)
    }

    /// The boundary of the grid as closed polygons in skin coordinates, through the pixel corners,
    /// each walked with the inside on its right in top-first space — so one non-zero fill of all
    /// of them is the window, holes included.
    ///
    /// Where two inside pixels touch only at a corner the walk turns toward the inside, so a
    /// diagonal line of pixels is one polygon rather than a chain of squares.
    ///
    /// **A vertex on the edge of small artwork is pinned where it was traced.** Smoothing moves
    /// both sides of a one-pixel line or slit toward each other wherever it bends or ends, which
    /// at 1x thinned all 27 of `Erektorset`'s one-pixel lines and filled 71 of its 120 one-pixel
    /// gaps. An edge borders small artwork when the pixel on either side of it has fewer than five
    /// of its 3x3 neighbourhood on its own side — a staircase step always has six.
    private static func traceOutline(_ cells: [(x: Int32, y: Int32)],
                                     grid: UnsafeMutablePointer<Float>,
                                     neighbourhood: UnsafeMutablePointer<Float>, gridWidth: Int,
                                     skinWidth: Int, skinHeight: Int)
        -> [(points: [CGPoint], pinned: [Bool])] {
        func inside(_ x: Int, _ y: Int) -> Bool { grid[(y + 1) * gridWidth + x + 1] > 0 }
        func insideCount(_ x: Int, _ y: Int) -> Float { neighbourhood[(y + 1) * gridWidth + x + 1] }
        // The pixels either side of the edge leaving (x, y) in `direction`, inside then outside.
        let insideX = [0, -1, -1, 0], insideY = [0, 0, -1, -1]
        let outsideX = [0, 0, -1, -1], outsideY = [-1, 0, 0, -1]
        func small(_ x: Int, _ y: Int, _ direction: Int) -> Bool {
            insideCount(x + insideX[direction], y + insideY[direction]) < 4.5
                || insideCount(x + outsideX[direction], y + outsideY[direction]) > 4.5
        }
        // Directions: 0 +x, 1 +y, 2 -x, 3 -y. A vertex has at most two edges leaving it.
        let stepX = [1, 0, -1, 0], stepY = [0, 1, 0, -1]
        let vertexWidth = skinWidth + 1
        let vertexCount = vertexWidth * (skinHeight + 1)
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
            guard inside(x, y) else { continue }
            if !inside(x, y - 1) { add(x, y, 0) }
            if !inside(x + 1, y) { add(x + 1, y, 1) }
            if !inside(x, y + 1) { add(x + 1, y + 1, 2) }
            if !inside(x - 1, y) { add(x, y + 1, 3) }
        }
        var loops: [(points: [CGPoint], pinned: [Bool])] = []
        for start in starts {
            guard let firstSlot = [0, 1].first(where: { outgoing[start * 2 + $0] >= 0 })
            else { continue }
            var vertex = start
            var direction = Int(outgoing[start * 2 + firstSlot])
            outgoing[start * 2 + firstSlot] = -1
            var loop: [CGPoint] = []
            var pinned: [Bool] = []
            var arrivedSmall = false
            while true {
                let x = vertex % vertexWidth, y = vertex / vertexWidth
                loop.append(CGPoint(x: x, y: y))
                let leavingSmall = small(x, y, direction)
                pinned.append(arrivedSmall || leavingSmall)
                arrivedSmall = leavingSmall
                vertex += stepY[direction] * vertexWidth + stepX[direction]
                // Right first, then straight, then left: a right turn keeps the inside close.
                var next: Int?
                for turn in [1, 0, 3] {
                    let wanted = Int8((direction + turn) % 4)
                    if outgoing[vertex * 2] == wanted { outgoing[vertex * 2] = -1; next = Int(wanted); break }
                    if outgoing[vertex * 2 + 1] == wanted {
                        outgoing[vertex * 2 + 1] = -1; next = Int(wanted); break
                    }
                }
                guard let next else { break }
                direction = next
            }
            // The first vertex was reached again by the last edge.
            if arrivedSmall, !pinned.isEmpty { pinned[0] = true }
            if loop.count >= 4 { loops.append((loop, pinned)) }
        }
        return loops
    }

    /// Each vertex the average of up to `reach` either side of it along the loop, twice, then held
    /// within half a skin pixel of where it was traced.
    ///
    /// **A pinned vertex stays put and bounds its neighbours' windows**, which shrink
    /// symmetrically as they near it. Averaging across a square corner while pinning only the
    /// corner itself sagged the edges either side of it into a wave and left the corner standing
    /// proud as a spike; bounded, a straight edge between two square corners averages only points
    /// on itself, and stays straight.
    private static func smoothed(_ loop: [CGPoint], pinned: [Bool]) -> [CGPoint] {
        let count = loop.count
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
        var points = loop
        for _ in 0..<2 {
            var next = points
            for index in 0..<count where window[index] > 0 {
                var sumX: CGFloat = 0, sumY: CGFloat = 0
                for offset in -window[index]...window[index] {
                    let point = points[((index + offset) % count + count) % count]
                    sumX += point.x; sumY += point.y
                }
                let size = CGFloat(window[index] * 2 + 1)
                next[index] = CGPoint(x: sumX / size, y: sumY / size)
            }
            points = next
        }
        for index in 0..<count {
            points[index] = CGPoint(
                x: min(loop[index].x + 0.5, max(loop[index].x - 0.5, points[index].x)),
                y: min(loop[index].y + 0.5, max(loop[index].y - 0.5, points[index].y)))
        }
        return points
    }

    /// `image` with `feather` applied, or `image` itself if it cannot be drawn.
    ///
    /// A filled pixel takes its donor's colour **in this layer**: a donor opaque only in the other
    /// layer has nothing here to lend, and that layer is filled instead.
    static func apply(_ feather: Feather, to image: CGImage) -> CGImage {
        let width = image.width, height = image.height
        guard feather.shrink.map({ $0.width == width && $0.height == height }) ?? true,
              let context = CGContext(data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return image }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        context.saveGState()
        if let shrink = feather.shrink { context.clip(to: bounds, mask: shrink) }
        context.setBlendMode(.copy)
        context.draw(image, in: bounds)
        context.restoreGState()
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let count = width * height
        for grown in feather.growth {
            let index = Int(grown.index), donor = Int(grown.donor)
            guard index < count, donor < count else { continue }
            let donorAlpha = Int(pixels[donor * 4 + 3])
            guard donorAlpha > 0 else { continue }
            let alpha = Int(grown.coverage) * donorAlpha / 255
            guard alpha > Int(pixels[index * 4 + 3]) else { continue }
            // Premultiplied, so the donor's colour at the new alpha is a straight rescale.
            for channel in 0..<3 {
                pixels[index * 4 + channel] = UInt8(min(alpha,
                    Int(pixels[donor * 4 + channel]) * alpha / donorAlpha))
            }
            pixels[index * 4 + 3] = UInt8(alpha)
        }
        return context.makeImage() ?? image
    }
}
