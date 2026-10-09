import AppKit

/// The colours NullPlayer's own windows wear beside a face, taken from what the face authored:
///
/// - **ground**: the dominant colour of the drawn face under the text display (the album line's box,
///   else the artist line's) — the surface the face itself puts lettering on;
/// - **text / current text**: the face's album and artist colours;
/// - **selection**: the dominant colour of the whole drawn face, its body.
///
/// "Drawn" is the stopped face through `AudionFaceRenderer`, so the mask has cut it to its window;
/// a face that cannot be drawn gets `neutral` whole.
///
/// A role the face cannot answer falls back to `neutral`, which is app-authored, never another
/// family's chrome. `SkinnedSurfaceStyle` runs every foreground through `legible`.
enum AudionFacePalette {
    static let neutral = SkinnedSurfaceStyle(roles: neutralRoles)

    static func surfaceStyle(for face: AudionFace) -> SkinnedSurfaceStyle {
        SkinnedSurfaceStyle(roles: roles(for: face))
    }

    /// What the face authored, before `SkinnedSurfaceStyle` runs its foregrounds through `legible`.
    static func roles(for face: AudionFace) -> SkinnedSurfaceRoles {
        // The face as it stands stopped, mask applied: a pixel the mask cuts away is not the face.
        guard let drawn = AudionFaceRenderer.render(AudionFaceScene(face: face, host: AudionFaceHostState()))
        else { return neutralRoles }
        let display = displayed(face.album) ?? displayed(face.artist)
        let body = dominantColor(of: drawn, in: nil)
        let ground = display.flatMap { dominantColor(of: drawn, in: $0.rect) } ?? body
            ?? neutralRoles.background
        let text = display.flatMap { NSColor(cgColor: $0.color) } ?? neutralRoles.text
        let current = (displayed(face.artist) ?? display).flatMap { NSColor(cgColor: $0.color) }
            ?? neutralRoles.currentText
        // A face whose body and display are one colour would give selection no contrast with rows;
        // blend toward a text colour that can be read there (the style's own `currentText`), since
        // the authored one may be the ground.
        let readable = SkinnedSurfaceStyle.legible(preferring: [current, text], on: ground)
        let selection = SkinnedSurfaceStyle.legible(
            preferring: [body ?? neutralRoles.selectionBackground,
                         SkinnedSurfaceStyle.blend(ground, toward: readable, by: 0.35)],
            on: ground, threshold: 1.3)
        return roles(background: ground, text: text, currentText: current, selection: selection)
    }

    /// A line that can show text. 85 faces author a 1×1 box at 0,0 as a placeholder for "no display";
    /// its colour is a default and the pixel under it is a corner, so neither is the face's.
    static func displayed(_ line: AudionFace.TextLine?) -> AudionFace.TextLine? {
        line.flatMap { $0.rect.width > 1 && $0.rect.height > 1 ? $0 : nil }
    }

    private static let neutralRoles = roles(
        background: NSColor(calibratedWhite: 0.12, alpha: 1), text: NSColor(calibratedWhite: 0.78, alpha: 1),
        currentText: .white, selection: NSColor(calibratedRed: 0.22, green: 0.36, blue: 0.62, alpha: 1))

    private static func roles(background: NSColor, text: NSColor, currentText: NSColor,
                              selection: NSColor) -> SkinnedSurfaceRoles {
        SkinnedSurfaceRoles(background: background, text: text, currentText: currentText,
                            selectionBackground: selection, selectionText: currentText,
                            treeText: text, treeSelection: selection)
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
        // Ties go to the higher bucket key: `Dictionary` order is seeded per process, so breaking
        // them by iteration order gave a face a different palette from one launch to the next.
        guard let top = counts.max(by: { ($0.value.n, $0.key) < ($1.value.n, $1.key) })?.value
        else { return nil }
        return NSColor(srgbRed: CGFloat(top.r) / CGFloat(top.n * 255), green: CGFloat(top.g) / CGFloat(top.n * 255),
                       blue: CGFloat(top.b) / CGFloat(top.n * 255), alpha: 1)
    }
}
