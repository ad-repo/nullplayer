import AppKit

/// Lookalikes for the fonts faces name and macOS no longer has: Apple's Mac OS 8.5 theme fonts,
/// the freeware pixel fonts face authors used, and the commercial families no Mac carries. Each is
/// judged against the faces' Audion screenshots (A12). A departure from FaceKit, which draws all of
/// them as Helvetica. A font the user has installed always wins; this is consulted only when the
/// authored name does not resolve.
///
/// Bundled fonts are never registered: the descriptors are read from the bundle, so no other
/// window or skin family sees them. The rest are fonts every macOS ships.
enum AudionFaceFontSubstitutes {
    /// `file` is the PostScript name, and a bundled font's `Fonts/` basename.
    private struct Substitute {
        let file: String
        var bundled = true
        var scale: CGFloat = 1
        /// Horizontal only, on top of `scale`: a condensed cut of the same design.
        var width: CGFloat = 1
    }

    // Chicago Kare's pixel grid is 16 px to the em, Chicago 12's at 96 dpi; at the authored size it
    // drew three-quarters the size of Chicago, Charcoal and Gadget in their Audion screenshots.
    private static let chicago = Substitute(file: "ChicagoKare-Regular", scale: 4 / 3)
    private static let tiny = Substitute(file: "Tiny5-Regular")
    // SF Digital Readout is a fourteen-segment LCD face, as DSEG14 is. NullPlayer Segment14 is
    // DSEG14 Classic Light renamed (OFL reserves "DSEG") with a descent added: DSEG has none,
    // and FaceKit's baseline, (ascent − descent) / 2, then cut each glyph in half. Its capitals
    // fill the whole em; at the authored size they overrun walkman 1.0's 10 px lines, and 0.56
    // brings them to the ~7.5 px the face's Audion screenshot shows.
    private static let segment = Substitute(file: "NullPlayerSegment14-Light", scale: 0.56)

    private static let substitutes: [String: Substitute] = {
        var map: [String: Substitute] = [:]
        for name in ["chicago", "charcoal", "gadget"] { map[name] = chicago }
        // Techno is Chicago condensed: its screenshots run four-fifths of Chicago Kare's width.
        map["techno"] = Substitute(file: chicago.file, scale: chicago.scale, width: 0.8)
        // Pixel fonts. Those whose originals NullPlayer ships draw in those (`AudionFaceOriginalFonts`);
        // the bitmap-only ones keep this outline for a line their strike cannot draw.
        for name in ["mini", "mini tight", "04b-11", "04b-20", "04bit-10", "04bit-16", "orchis 5", "orchis 6",
                     "bitbit", "freecemini", "redensek", "ikkio_square"] {
            map[name] = tiny
        }
        map["silkscreen"] = Substitute(file: "Silkscreen-Regular")
        map["textile"] = Substitute(file: "ComicNeue-BoldItalic")
        // Kidprint, Apple's rounded child's hand (Byte Me, ClassicPooh).
        map["kidprint"] = Substitute(file: "ComicNeue-Regular")
        map["sf digital readout medium"] = segment
        // Display faces no Mac carries, one face each.
        map["institution"] = Substitute(file: "PathwayGothicOne-Regular")      // Corrosion: condensed
        map["machine itc tt"] = Substitute(file: "BebasNeue-Regular")          // Nova Watch: heavy condensed caps
        map["junior pro"] = Substitute(file: "Sniglet-ExtraBold")             // X-factor: rounded bold
        map["stencil"] = Substitute(file: "StardosStencil-Bold")              // chirico biscuit
        for name in ["eurostile boldextendedtwo", "square721 ex bt roman"] {    // hyperboreal, Rust
            map[name] = Substitute(file: "KronaOne-Regular")                  // wide and heavy
        }
        for name in ["eurostile extendedtwo", "avalon quest"] {               // hyperboreal, FireFox
            map[name] = Substitute(file: "Michroma-Regular")                  // wide and light
        }
        // Fonts macOS ships: names it answers under another one, then lookalikes. Geneva and Monaco
        // draw their 1-bit strikes.
        let system: [String: String] = [
            "arial bl": "Arial-Black",                          // the name, cut short
            "arial mt condensed light": "ArialNarrow",
            "bradley hand itc tt-bold": "BradleyHandITCTT-Bold",
            "futura condensed": "Futura-CondensedMedium",
            "futura condensedlight": "Futura-CondensedMedium",
            "century gothic": "Futura-Medium",                  // geometric, single-storey a
            "avant guard": "Futura-Medium",
            "futuri light": "Futura-Medium",
            "new york": "Times-Roman",
            "vt100": "Monaco",
            "cubase data font": "Monaco",
            "espy sans": "Geneva",                              // the Newton's system face, Geneva's kin
            "espy sans bold": "Geneva",
            "facet": "Impact",
            "i/o sans italic": "Helvetica-BoldOblique",
            "weathered sf regular": "Times-Bold",
            "monotype.com": "AndaleMono",                       // its own later name
            "capitals": "Copperplate",                          // engraved Roman capitals
        ]
        for (name, file) in system { map[name] = Substitute(file: file, bundled: false) }
        // Sand is a felt-tip hand; Marker Felt Wide is its height but runs a fifth narrower.
        map["sand"] = Substitute(file: "MarkerFelt-Wide", bundled: false, width: 1.2)
        return map
    }()

    private static let descriptors: [String: CTFontDescriptor] = {
        var byFile: [String: CTFontDescriptor] = [:]
        for substitute in substitutes.values where byFile[substitute.file] == nil {
            let file = substitute.file
            guard substitute.bundled else {
                byFile[file] = CTFontDescriptorCreateWithNameAndSize(file as CFString, 0)
                continue
            }
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
        var matrix = CGAffineTransform(scaleX: substitute.width, y: 1)
        return CTFontCreateWithFontDescriptor(descriptor, size * substitute.scale, &matrix) as NSFont
    }
}
