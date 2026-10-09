import AppKit

/// The colours NullPlayer's own windows wear beside a face, taken from what the face authored:
///
/// - **ground**: the dominant colour of `base` under the text display (the album line's box, else
///   the artist line's) — the surface the face itself puts lettering on;
/// - **text / current text**: the face's album and artist colours;
/// - **selection**: the dominant colour of the whole face, its body.
///
/// A role the face cannot answer falls back to `neutral`, which is app-authored, never another
/// family's chrome. `SkinnedSurfaceStyle` runs every foreground through `legible`.
enum AudionFacePalette {
    static let neutral = style(background: NSColor(calibratedWhite: 0.12, alpha: 1),
                               text: NSColor(calibratedWhite: 0.78, alpha: 1), currentText: .white,
                               selection: NSColor(calibratedRed: 0.22, green: 0.36, blue: 0.62, alpha: 1))

    static func surfaceStyle(for face: AudionFace) -> SkinnedSurfaceStyle {
        let display = face.album?.rect ?? face.artist?.rect
        let ground = display.flatMap { dominantColor(of: face.base, in: $0) }
            ?? dominantColor(of: face.base, in: nil) ?? neutral.background
        let text = (face.album ?? face.artist).flatMap { NSColor(cgColor: $0.color) } ?? neutral.text
        let current = (face.artist ?? face.album).flatMap { NSColor(cgColor: $0.color) } ?? neutral.currentText
        let body = dominantColor(of: face.base, in: nil) ?? neutral.selectionBackground
        // A face whose body and display are one colour would give selection no contrast with rows.
        let selection = SkinnedSurfaceStyle.contrastRatio(body, ground) < 1.3
            ? SkinnedSurfaceStyle.blend(ground, toward: current, by: 0.35) : body
        return style(background: ground, text: text, currentText: current, selection: selection)
    }

    private static func style(background: NSColor, text: NSColor, currentText: NSColor,
                              selection: NSColor) -> SkinnedSurfaceStyle {
        SkinnedSurfaceStyle(roles: SkinnedSurfaceRoles(
            background: background, text: text, currentText: currentText,
            selectionBackground: selection, selectionText: currentText,
            treeText: text, treeSelection: selection))
    }

    /// The commonest opaque colour of `image` inside `rect` (face pixels, top-left), or of all of it.
    /// Bucketed at 4 bits a channel rather than averaged: an average of dark chrome and a bright
    /// display is a grey the face never drew.
    static func dominantColor(of image: CGImage, in rect: AudionFaceRect?) -> NSColor? {
        let source = rect.flatMap {
            image.cropping(to: CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height))
        } ?? image
        let side = 32
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .none
        context.draw(source, in: CGRect(x: 0, y: 0, width: side, height: side))
        var counts: [Int: (n: Int, r: Int, g: Int, b: Int)] = [:]
        for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i + 3] > 127 {
            let a = Int(pixels[i + 3])
            let r = min(255, Int(pixels[i]) * 255 / a), g = min(255, Int(pixels[i + 1]) * 255 / a)
            let b = min(255, Int(pixels[i + 2]) * 255 / a)
            let key = (r >> 4) << 8 | (g >> 4) << 4 | b >> 4
            let c = counts[key] ?? (0, 0, 0, 0)
            counts[key] = (c.n + 1, c.r + r, c.g + g, c.b + b)
        }
        guard let top = counts.values.max(by: { $0.n < $1.n }) else { return nil }
        return NSColor(srgbRed: CGFloat(top.r) / CGFloat(top.n * 255), green: CGFloat(top.g) / CGFloat(top.n * 255),
                       blue: CGFloat(top.b) / CGFloat(top.n * 255), alpha: 1)
    }
}
