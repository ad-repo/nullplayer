import AppKit

/// **A rendered ring moved to another window size the way its author's alignment rules move it:
/// the border keeps its thickness and everything anchored stays anchored.**
///
/// A ring is a full scene build per size — 0.3 to 1.3 s on `ALXVortex` — so while a hosted window is
/// being dragged no exact render can exist for most of the sizes it passes through. Stretching the
/// nearest render proportionally was the old answer and it is what the user saw as a distorted
/// frame: corners squashed, borders thickened by the ratio. So the nearest render is *re-laid out*
/// instead, the way a nine-patch is — except that the slice lines are not the client-hole insets.
/// These corners are decorative and routinely run far past the border they sit in (190pt wide on a
/// 406pt `Halo 2` window), and a slice at the insets would stretch half of each corner.
///
/// Instead each axis is cut where the frame is **uniform** — where one column (or row) of the border
/// bands is the same as the next, which is exactly what an edge piece the skin stretches or spans
/// looks like — once in each half of the window. Growing repeats a column from inside that run;
/// shrinking removes columns from inside it. Everything else is copied pixel for pixel, so:
///
/// - the borders keep their thickness, because the seams are confined to the columns over the
///   client hole;
/// - corners and anything anchored to an edge stay 1:1 and stay put;
/// - a centred ornament stays centred, because each half gives or takes half the difference.
///
/// Where a half has no uniform run (a tiled or noisy edge) the seam falls in the middle of that
/// half, and the exact render that replaces the relaid one may shift the detail there — that is
/// the one residual, and `WMP_FRAME_TRACE` names the source every stand-in was relaid from.
struct WMPHostedFrameRelayout {
    /// One run of output columns (or rows): `length` copies of the source starting at `source`,
    /// either one for one (`repeats == false`) or the single source column repeated.
    struct Segment: Equatable {
        let source: Int
        let length: Int
        let repeats: Bool
    }

    private let pixels: [UInt32]
    let width: Int
    let height: Int
    private let colorSpace: CGColorSpace
    /// Border thickness in source pixels.
    private let left: Int, top: Int, right: Int, bottom: Int
    /// `columnUniform[i]` — column `i` matches column `i + 1` across the top and bottom bands.
    private let columnUniform: [Bool]
    /// `rowUniform[j]` — row `j` matches row `j + 1` across the left and right bands.
    private let rowUniform: [Bool]

    /// Per-channel difference two pixels may have and still count as the same colour. Enough to
    /// absorb the rounding of a resampled edge piece, not enough to hide a highlight.
    private static let tolerance = 6

    init?(_ artwork: SkinnedSurfaceFrameArtwork) {
        let image = artwork.image
        let width = image.width, height = image.height
        guard width > 1, height > 1, artwork.size.width > 0, artwork.size.height > 0 else { return nil }
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        var pixels = [UInt32](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        let scaleX = CGFloat(width) / artwork.size.width
        let scaleY = CGFloat(height) / artwork.size.height
        let metrics = artwork.metrics
        let left = min(width, Int((metrics.leftBorder * scaleX).rounded()))
        let right = min(width - left, Int((metrics.rightBorder * scaleX).rounded()))
        let top = min(height, Int((metrics.titleHeight * scaleY).rounded()))
        let bottom = min(height - top, Int((metrics.bottomBorder * scaleY).rounded()))

        self.pixels = pixels
        self.width = width
        self.height = height
        self.colorSpace = space
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom

        // Only the border bands are compared: the client hole is covered by our content (or cut
        // out of the frame), so whatever the donor left there says nothing about where to cut.
        let bandRows = Array(0..<top) + Array((height - bottom)..<height)
        let sampleRows = bandRows.isEmpty ? Array(0..<height) : bandRows
        let bandColumns = Array(0..<left) + Array((width - right)..<width)
        let sampleColumns = bandColumns.isEmpty ? Array(0..<width) : bandColumns
        columnUniform = pixels.withUnsafeBufferPointer { p in
            (0..<(width - 1)).map { x in
                sampleRows.allSatisfy { y in Self.close(p[y * width + x], p[y * width + x + 1]) }
            }
        }
        rowUniform = pixels.withUnsafeBufferPointer { p in
            (0..<(height - 1)).map { y in
                sampleColumns.allSatisfy { x in Self.close(p[y * width + x], p[(y + 1) * width + x]) }
            }
        }
    }

    /// The frame re-laid out for a window of `target` points, or nil where the window is too small
    /// to carry the border at all.
    func relaid(_ artwork: SkinnedSurfaceFrameArtwork, to target: CGSize) -> SkinnedSurfaceFrameArtwork? {
        guard target.width > 0, target.height > 0 else { return nil }
        let scaleX = CGFloat(width) / artwork.size.width
        let scaleY = CGFloat(height) / artwork.size.height
        let targetWidth = max(1, Int((target.width * scaleX).rounded()))
        let targetHeight = max(1, Int((target.height * scaleY).rounded()))
        guard let columns = Self.plan(length: width, target: targetWidth, lead: left, trail: right,
                                      uniform: columnUniform),
              let rows = Self.plan(length: height, target: targetHeight, lead: top, trail: bottom,
                                   uniform: rowUniform),
              let image = compose(columns: columns, rows: rows,
                                  width: targetWidth, height: targetHeight)
        else { return nil }
        let metrics = artwork.metrics
        return SkinnedSurfaceFrameArtwork(
            image: image,
            size: target,
            contentRect: CGRect(x: artwork.contentRect.minX, y: artwork.contentRect.minY,
                                width: max(0, target.width - metrics.leftBorder - metrics.rightBorder),
                                height: max(0, target.height - metrics.titleHeight - metrics.bottomBorder)),
            trailingCornerWidth: artwork.trailingCornerWidth,
            wasScaledToFit: artwork.wasScaledToFit,
            paintsOverContent: artwork.paintsOverContent
        )
    }

    // MARK: - Where to cut

    /// The output columns (or rows) for one axis. The difference is split between the two halves
    /// of the span between the borders, and each half cuts inside its longest uniform run.
    static func plan(length: Int, target: Int, lead: Int, trail: Int, uniform: [Bool]) -> [Segment]? {
        let innerStart = lead
        let innerEnd = length - trail
        let inner = innerEnd - innerStart
        let delta = target - length
        if delta == 0 { return [Segment(source: 0, length: length, repeats: false)] }
        guard inner > 0, inner + delta > 0 else { return nil }
        let middle = innerStart + inner / 2
        let halves = [(innerStart, middle), (middle, innerEnd)]
        var shares = [delta / 2, delta - delta / 2]
        if delta < 0 {
            // A half cannot give up more columns than it has.
            let removing = -delta
            var first = min(removing / 2, middle - innerStart)
            var second = removing - first
            if second > innerEnd - middle {
                first += second - (innerEnd - middle)
                second = innerEnd - middle
            }
            shares = [-first, -second]
        }

        var segments: [Segment] = []
        var cursor = 0
        func copy(upTo end: Int) {
            if end > cursor { segments.append(Segment(source: cursor, length: end - cursor, repeats: false)) }
            cursor = max(cursor, end)
        }
        for (half, share) in zip(halves, shares) where share != 0 && half.1 > half.0 {
            let run = longestRun(from: half.0, to: half.1, uniform: uniform)
            if share > 0 {
                let seam = (run.lowerBound + run.upperBound) / 2
                copy(upTo: seam + 1)
                segments.append(Segment(source: seam, length: share, repeats: true))
            } else {
                let removing = -share
                let runLength = run.upperBound - run.lowerBound + 1
                var start: Int
                if runLength >= removing + 2 {
                    // Both columns either side of the cut are inside the run: the join is invisible.
                    start = run.lowerBound + 1 + (runLength - 2 - removing) / 2
                } else {
                    start = (run.lowerBound + run.upperBound + 1) / 2 - removing / 2
                }
                start = min(max(start, max(half.0, cursor)), half.1 - removing)
                copy(upTo: start)
                cursor = start + removing
            }
        }
        copy(upTo: length)
        return segments
    }

    /// The longest run of columns in `[from, to)` that are all the same as their neighbour, as the
    /// closed range of columns it spans. With no uniform pair at all, the middle column of the half.
    private static func longestRun(from: Int, to: Int, uniform: [Bool]) -> ClosedRange<Int> {
        var best: ClosedRange<Int>?
        var start: Int?
        let last = min(to - 1, uniform.count)
        var index = from
        while index <= last {
            let joined = index < last && uniform[index]
            if joined {
                if start == nil { start = index }
            } else if let open = start {
                let run = open...index
                if best == nil || run.count > best!.count { best = run }
                start = nil
            }
            index += 1
        }
        if let best { return best }
        let centre = (from + to - 1) / 2
        return centre...centre
    }

    // MARK: - Drawing it

    private func compose(columns: [Segment], rows: [Segment], width targetWidth: Int,
                         height targetHeight: Int) -> CGImage? {
        var sourceRows: [Int] = []
        sourceRows.reserveCapacity(targetHeight)
        for row in rows {
            for offset in 0..<row.length { sourceRows.append(row.repeats ? row.source : row.source + offset) }
        }
        guard sourceRows.count == targetHeight else { return nil }
        var output = [UInt32](repeating: 0, count: targetWidth * targetHeight)
        output.withUnsafeMutableBufferPointer { out in
            pixels.withUnsafeBufferPointer { source in
                guard let out = out.baseAddress, let source = source.baseAddress else { return }
                var previous = -1
                for y in 0..<targetHeight {
                    let destination = out + y * targetWidth
                    let sourceRow = sourceRows[y]
                    if sourceRow == previous {
                        destination.update(from: destination - targetWidth, count: targetWidth)
                        continue
                    }
                    previous = sourceRow
                    let origin = source + sourceRow * width
                    var x = 0
                    for column in columns {
                        if column.repeats {
                            (destination + x).update(repeating: origin[column.source], count: column.length)
                        } else {
                            (destination + x).update(from: origin + column.source, count: column.length)
                        }
                        x += column.length
                    }
                }
            }
        }
        let data = output.withUnsafeBytes { Data($0) }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: targetWidth, height: targetHeight, bitsPerComponent: 8,
                       bitsPerPixel: 32, bytesPerRow: targetWidth * 4, space: colorSpace,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)
    }

    @inline(__always)
    private static func close(_ a: UInt32, _ b: UInt32) -> Bool {
        if a == b { return true }
        var shift: UInt32 = 0
        while shift < 32 {
            let lhs = Int((a >> shift) & 0xff)
            let rhs = Int((b >> shift) & 0xff)
            if abs(lhs - rhs) > tolerance { return false }
            shift += 8
        }
        return true
    }
}
