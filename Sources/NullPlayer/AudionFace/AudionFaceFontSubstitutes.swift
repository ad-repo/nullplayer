import AppKit

/// Bundled lookalikes for the fonts faces name and macOS no longer has: Apple's Mac OS 8.5 theme
/// fonts, and the freeware pixel fonts face authors used. A departure from FaceKit, which draws
/// all of them as Helvetica. A font the user has installed always wins; this is consulted only
/// when the authored name does not resolve.
///
/// Techno, Gadget, Sand and Capitals share Chicago's metrics, so Chicago Kare keeps their layout.
/// The fonts are never registered: the descriptors are read from the bundle, so no other window
/// or skin family sees them.
enum AudionFaceFontSubstitutes {
    /// A bundled font file; `file` is both its `Fonts/` basename and its PostScript name.
    private struct Substitute {
        let file: String
        var scale: CGFloat = 1
    }

    private static let chicago = Substitute(file: "ChicagoKare-Regular")
    private static let tiny = Substitute(file: "Tiny5-Regular")
    // SF Digital Readout is a fourteen-segment LCD face, as DSEG14 is. NullPlayer Segment14 is
    // DSEG14 Classic Light renamed (OFL reserves "DSEG") with a descent added: DSEG has none,
    // and FaceKit's baseline, (ascent − descent) / 2, then cut each glyph in half. Its capitals
    // fill the whole em; at the authored size they overrun walkman 1.0's 10 px lines, and 0.56
    // brings them to the ~7.5 px the face's Audion screenshot shows.
    private static let segment = Substitute(file: "NullPlayerSegment14-Light", scale: 0.56)

    private static let substitutes: [String: Substitute] = {
        var map: [String: Substitute] = [:]
        for name in ["chicago", "charcoal", "techno", "gadget", "sand", "capitals"] { map[name] = chicago }
        for name in ["mini", "mini tight", "04b-03", "04b-08", "04b-09", "04b-11", "04b-20", "04b-24",
                     "04bit-10", "04bit-16", "orchis 5", "orchis 6", "redensek", "bitbit", "bitsumishi",
                     "squarodynamic 08", "hooge 05_53", "freecemini", "lilliput steps", "ikkio_square"] {
            map[name] = tiny
        }
        map["silkscreen"] = Substitute(file: "Silkscreen-Regular")
        map["textile"] = Substitute(file: "ComicNeue-BoldItalic")
        map["sf digital readout medium"] = segment
        return map
    }()

    private static let descriptors: [String: CTFontDescriptor] = {
        var byFile: [String: CTFontDescriptor] = [:]
        for file in Set(substitutes.values.map(\.file)) {
            guard let url = BundleHelper.url(forResource: file, withExtension: "ttf", subdirectory: "Fonts"),
                  let found = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] else { continue }
            // Tiny5 is a variable font; take the default instance.
            byFile[file] = found.first { CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String == file } ?? found.first
        }
        return byFile
    }()

    static func font(for name: String, size: CGFloat) -> NSFont? {
        let key = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard let substitute = substitutes[key], let descriptor = descriptors[substitute.file] else { return nil }
        return CTFontCreateWithFontDescriptor(descriptor, size * substitute.scale, nil) as NSFont
    }
}
