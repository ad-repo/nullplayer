import AppKit
import Foundation

/// Font resolution and text measurement for Wasabi text objects.
///
/// This is deliberately shared by the renderer and the script runtime rather than duplicated: a skin
/// lays itself out from `getAutoWidth()` (ClassicPro's menu bar positions File/Play/Options/View/Help
/// that way, and its SUI sizes every tab to its label), so a script that measures text differently
/// from the code that draws it produces boxes that do not fit their own contents. Neither may depend
/// on the other — the render harness runs the scripts before any renderer exists — so the measurement
/// lives here, on the loaded skin, and both sides ask it the same question.
final class WasabiTextMetrics {
    let loadedSkin: WinampModernLoadedSkin
    private var fonts: [String: CGFont] = [:]
    /// The **resolved** font for a request, which is not what `fonts` holds.
    ///
    /// `fonts` caches the raw `CGFont` parsed out of the skin, and everything after it ran per
    /// string, per frame: `CTFontCreateWithGraphicsFont` at the size, `applying(_:to:)` (an
    /// `NSFontManager.convert` round trip), and — for the far more common case of a skin naming a
    /// plain family rather than a declared resource — the whole `installedFont` branch, whose
    /// `NSFontManager.font(withFamily:)` reaches
    /// `CTFontDescriptorCreateMatchingFontDescriptorsWithOptions`. That subtree measured 5.7% of the
    /// main thread on `cPro_T2T-by-MAC` (B103). The answer is a pure function of the key, so it is
    /// cached on the whole key the signature already offers.
    ///
    /// `nil` is cached too: a skin naming a font nobody has is the case that pays the *full*
    /// descriptor-matching cost before failing, so it is the one most worth not repeating.
    private var resolvedFonts: [FontKey: NSFont?] = [:]

    /// How wide a string draws in a font — memoized, because it is a pure function of exactly that
    /// and it is asked on the **layout** path, not only the paint one.
    ///
    /// `autoWidth(of:)` is reached from `append`, so every `<text>` sized from its own content is
    /// measured on every scene rebuild, and `NSString.size(withAttributes:)` is a full CoreText
    /// typesetting pass (`__NSStringDrawingEngine` → `TTypesetterAttrString`). Measured at 4.7% of
    /// the main thread from `append` alone on cPro Bento, with the playlist and `drawText` paths
    /// asking the same question again (B106).
    ///
    /// Keyed on the font's *name and size* rather than its identity, so it stays correct if the
    /// font cache ever hands back a different instance for the same face.
    private var stringWidths: [StringWidthKey: CGFloat] = [:]
    private(set) var isTornDown = false

    private struct StringWidthKey: Hashable {
        let text: String
        let fontName: String
        let pointSize: CGFloat
    }

    /// A ticking clock produces a new string every second, so this is bounded rather than unbounded;
    /// the cap is a guard, not a working limit.
    private static let maximumStringWidths = 4096

    /// The width of `text` drawn in `font`, exactly as `NSString.size(withAttributes: [.font:])`
    /// answers it. Callers that measure with any *other* attribute must not use this.
    func measuredWidth(of text: String, font: NSFont) -> CGFloat {
        let key = StringWidthKey(text: text, fontName: font.fontName, pointSize: font.pointSize)
        if let cached = stringWidths[key] { return cached }
        let width = (text as NSString).size(withAttributes: [.font: font]).width
        if stringWidths.count >= Self.maximumStringWidths { stringWidths.removeAll(keepingCapacity: true) }
        stringWidths[key] = width
        return width
    }

    /// A laid-out line, cached — the drawing half of what `stringWidths` does for the measuring
    /// half, and the larger of the two costs.
    ///
    /// `drawText` built an `NSAttributedString` and entered `NSString.draw` per string, per frame,
    /// and the embedded playlist did it per row: a full TextKit typesetting pass to redraw a string
    /// that has not changed since the last frame. A `CTLine` is that pass's result, and it is a pure
    /// function of the text and the face.
    ///
    /// **Built colourless**, with `kCTForegroundColorFromContextAttributeName`, and the colour set
    /// on the context before `CTLineDraw`. Baking the colour in would give a playlist two entries
    /// per row — selected and not — and a hover state a third, for text that is otherwise identical.
    private var lines: [LineKey: CTLine] = [:]

    private struct LineKey: Hashable {
        let text: String
        let fontName: String
        let pointSize: CGFloat
    }

    /// A ticking clock makes a new string a second, so this is bounded rather than unbounded; the
    /// cap is a guard, not a working limit.
    private static let maximumLines = 1024

    /// `text` laid out in `font`, ready to draw at a baseline.
    ///
    /// Deliberately has **no truncating form**. `.byTruncatingTail` is not just a cut: before
    /// AppKit truncates it tightens inter-character spacing by up to
    /// `NSParagraphStyle.tighteningFactorForTruncation`, which defaults to 0.05, and that drift is
    /// cumulative across the line. Measured against `NSString.draw`: the first dozen columns of an
    /// over-long row match to the byte and the rest diverge steadily, ~85% of the ink. A
    /// `CTLineCreateTruncatedLine` reproduces the cut and not the tightening, so a caller that has
    /// to truncate keeps `NSString.draw` — see `WasabiSceneRenderer.drawFlippedText`.
    func line(for text: String, font: NSFont) -> CTLine {
        let key = LineKey(text: text, fontName: font.fontName, pointSize: font.pointSize)
        if let cached = lines[key] { return cached }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, kCTForegroundColorFromContextAttributeName as NSAttributedString.Key: true
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text,
                                                                      attributes: attributes))
        if lines.count >= Self.maximumLines { lines.removeAll(keepingCapacity: true) }
        lines[key] = line
        return line
    }

    /// How far below a line's box top its baseline sits, as **TextKit** places it.
    ///
    /// This is the whole of the conversion's vertical arithmetic: `NSString.draw(in:)` lays a line
    /// out from its rect's top edge, `CTLineDraw` draws from an explicit baseline, and this is the
    /// distance between them. Established by pixel comparison rather than derived
    /// (`WinampModernTextDrawingTests.testCachedLineMatchesStringDrawing`), because it is *not* the
    /// font's own ascender: at 8pt every face tested answers 8 while their ascenders run from 6.03
    /// to 7.73, and Helvetica at 17.6pt answers 18 against an ascender of 13.55. Asking the same
    /// layout manager AppKit's own drawing asks is what makes the two agree.
    func baselineOffset(of font: NSFont) -> CGFloat {
        let key = FontMetricKey(fontName: font.fontName, pointSize: font.pointSize)
        if let cached = baselineOffsets[key] { return cached }
        let offset = NSLayoutManager().defaultBaselineOffset(for: font)
        if baselineOffsets.count >= Self.maximumResolvedFonts {
            baselineOffsets.removeAll(keepingCapacity: true)
        }
        baselineOffsets[key] = offset
        return offset
    }

    private var baselineOffsets: [FontMetricKey: CGFloat] = [:]

    private struct FontMetricKey: Hashable {
        let fontName: String
        let pointSize: CGFloat
    }

    private struct FontKey: Hashable {
        let identifier: String
        let size: CGFloat
        let traits: UInt
    }

    /// A skin declares a handful of sizes and the UI Size scales them, so this is small in practice.
    /// The cap is a guard against a script driving `fontsize` continuously, not a working limit.
    private static let maximumResolvedFonts = 512

    init(loadedSkin: WinampModernLoadedSkin) {
        self.loadedSkin = loadedSkin
    }

    func teardown() {
        fonts.removeAll()
        resolvedFonts.removeAll()
        stringWidths.removeAll()
        lines.removeAll()
        baselineOffsets.removeAll()
        isTornDown = true
    }

    /// A font for a text object, or `nil` when nothing usable could be produced.
    ///
    /// Optional on purpose: these are ObjC constructors imported as non-optional that can still
    /// return null, and a null font reaches CoreText as a nil attribute value, which aborts the
    /// **process** (`attempt to insert nil object`) from inside `NSView.draw`. A skin resource must
    /// never be able to do that, so the null is caught here — assigning to an `NSFont?` is what makes
    /// it visible — and answered by the caller's guaranteed fallback.
    func font(identifier: String?, size: CGFloat, traits: NSFontTraitMask = []) -> NSFont? {
        guard !isTornDown else { return nil }
        guard let identifier else { return resolvedFont(identifier: nil, size: size, traits: traits) }
        let key = FontKey(identifier: identifier, size: size, traits: traits.rawValue)
        if let cached = resolvedFonts[key] { return cached }
        let resolved = resolvedFont(identifier: identifier, size: size, traits: traits)
        if resolvedFonts.count >= Self.maximumResolvedFonts { resolvedFonts.removeAll(keepingCapacity: true) }
        resolvedFonts[key] = resolved
        return resolved
    }

    private func resolvedFont(identifier: String?, size: CGFloat, traits: NSFontTraitMask) -> NSFont? {
        guard !isTornDown, let identifier,
              let definition = loadedSkin.runtime.resources.resolvedDefinition(identifier: identifier),
              definition.kind == "truetypefont", let path = definition.logicalFile else {
            // `font=` is an id **or** a plain family name. A skin that ships no font resource simply
            // names one it expects the system to have ("Arial", "Tahoma"), which is what Winamp asks
            // GDI for — resolving only declared resources drew every such string in the monospaced
            // fallback (the whole of Love is War Miku's display).
            if let identifier, let installed = Self.systemFont(namedBySkin: identifier, size: size,
                                                                traits: traits) {
                return installed
            }
            if let identifier {
                // Two different failures land here and they are not the same report. A skin that
                // *declared* a `<truetypefont>` whose file never made it into the archive resolves a
                // definition with no `logicalFile`, so it falls past the guard into the name branch
                // and would otherwise be filed as "you named a font nobody has" — which is the
                // opposite of what happened, and the commonest case in the corpus (25 of 73 skins,
                // the whole cPro family's `font.ttf`).
                let declared = loadedSkin.runtime.resources
                    .resolvedDefinition(identifier: identifier)?.kind == "truetypefont"
                recordUnresolved(identifier, declared
                                 ? "is declared as a <truetypefont> whose file is not in the archive"
                                 : "is neither a declared font resource nor a font installed on this "
                                   + "system")
            }
            return substituteFont(size: size, traits: traits)
        }
        let key = path.lowercased()
        let cgFont: CGFont?
        if let cached = fonts[key] {
            cgFont = cached
        } else if let data = try? loadedSkin.vfs.data(at: path, location: definition.source),
                  let provider = CGDataProvider(data: data as CFData),
                  let decoded = CGFont(provider) {
            fonts[key] = decoded
            cgFont = decoded
        } else {
            cgFont = nil
        }
        if let cgFont {
            let created = CTFontCreateWithGraphicsFont(cgFont, size, nil, nil)
            // A font parsed out of a skin can come back null from a constructor imported as
            // non-optional. Put in an attributes dictionary, that null reaches the ObjC bridge as a
            // real nil and aborts the **process** from inside `NSString.size(withAttributes:)`:
            //
            //   -[__NSPlaceholderDictionary initWithObjects:forKeys:count:]: attempt to insert nil
            //   object from objects[0]
            //
            // which is the 2026-08-16 cPro-Bento report exactly. Assigning to an `NSFont?` is the
            // whole defence: a nil class reference lands as `.none`, so `if let` catches it and the
            // caller's guaranteed fallback answers instead.
            //
            // **Do not reinstate a PostScript-name check here.** Two have been tried and neither
            // could ever fire. `CTFontCopyPostScriptName(created) == nil` is *always false* — the
            // overlay returns a non-optional `CFString`. Testing the name for `isEmpty` (0.30.0) is
            // no better: CoreGraphics **synthesizes** a name (`font00000000308faa8`) for any font
            // whose `name` table is missing, empty, or carries a zero-length nameID 6, and rejects
            // outright anything malformed enough to have no name at all — so no font that reaches
            // this line can have an empty name. Measured, not reasoned:
            // `WinampModernNamelessFontTests`.
            let bridged: NSFont? = created as NSFont
            if let bridged { return Self.applying(traits, to: bridged) }
        }
        recordUnresolved(identifier,
                         "declares file=\"\(path)\", which is not in the archive or cannot be read "
                         + "as a font")
        return substituteFont(size: size, traits: traits)
    }

    /// What a name this system cannot produce draws in.
    ///
    /// **Proportional, not monospaced** (B131). The fixed-pitch fallback that stood here was defended
    /// as a diagnostic and was not one: nothing recorded it, so the only reader was a person looking
    /// at the skin, and what they saw could not be told apart from a skin that wanted a fixed-pitch
    /// face. It is also not what Winamp does — GDI substitutes for a name it cannot match and returns
    /// a proportional face, never a monospaced one — and it was not rare: **25 of the 73 corpus skins**
    /// declare a `<truetypefont>` whose file is absent (the whole cPro family's `font.ttf`), and 34
    /// distinct `font=` names do not resolve on macOS at all, among them plain Windows families
    /// (Calibri ×4 skins, Segoe UI, Century Gothic) and raw Windows font *filenames* used as names
    /// (`ariblk`, `micross`, `trebuc`, `UNVR67X.ttf` ×5). A third of the corpus was drawing its
    /// display text in a console face to raise an alarm nobody received. The alarm is now a
    /// `.unresolvedFont` diagnostic, which is where it belongs.
    private func substituteFont(size: CGFloat, traits: NSFontTraitMask) -> NSFont? {
        if let installed = Self.installedFont(named: Self.substituteFamily, size: size,
                                              traits: traits) {
            return installed
        }
        let fallback: NSFont? = .systemFont(ofSize: size)
        return fallback.flatMap { Self.applying(traits, to: $0) }
    }

    /// The face an unresolvable name substitutes to — the same default an *undeclared* list font
    /// takes, so the two never disagree about what "the skin did not give us a face" looks like.
    static let substituteFamily = "Arial"

    /// Records the substitution once per name. `resolvedFont` runs only on a cache miss and
    /// `WinampModernLoadedSkin.record` de-duplicates and bounds besides, so this cannot grow per
    /// frame.
    private func recordUnresolved(_ identifier: String, _ reason: String) {
        guard !isTornDown else { return }
        // The host asks for the substitute family by name for its own surfaces (an undeclared list
        // font). A system without Arial is our problem, not the skin's — do not file it against one.
        guard identifier.caseInsensitiveCompare(Self.substituteFamily) != .orderedSame else { return }
        loadedSkin.runtime.record(WalDiagnostic(
            .unresolvedFont,
            "font=\"\(identifier)\" \(reason); it draws in \(Self.substituteFamily) instead.",
            severity: .warning))
    }

    /// A system face for a name a skin wrote where a family belongs (B132).
    ///
    /// A skin author names the font they have, and what they have is a *file*: `ariblk`, `micross`,
    /// `trebuc`, `tahoma.ttf`, `UNVR67X.ttf`, `SUPERGLU.ttf` all appear as `font=` values in the
    /// corpus. GDI cannot match those either — this is not Winamp behaviour being reproduced, it is
    /// the intent behind the declaration being honoured, since the *faces* behind three of them do
    /// ship here (Arial Black, Trebuchet MS, and MS Sans Serif's stand-in Helvetica).
    ///
    /// Two cheap steps, in the order that lets a real name always win:
    ///
    /// 1. the name as written — an installed family or PostScript name is what it says it is;
    /// 2. the name with a font-file extension removed, so `tahoma.ttf` reaches Tahoma the same way
    ///    the bare `tahoma` in five other skins does;
    /// 3. the Windows filename → family map below.
    ///
    /// The map only helps names whose face exists on this system: `UNVR67X` and `SUPERGLU` are not
    /// Windows core fonts and stay substituted and stay diagnosed, as do Calibri and Segoe UI, which
    /// are mapped honestly and simply are not installed here.
    private static func systemFont(namedBySkin name: String, size: CGFloat,
                                   traits: NSFontTraitMask) -> NSFont? {
        if let installed = installedFont(named: name, size: size, traits: traits) { return installed }
        let stem = windowsFontFileStem(of: name)
        if stem != name, let installed = installedFont(named: stem, size: size, traits: traits) {
            return installed
        }
        guard let family = windowsFontFileFamilies[stem.lowercased()] else { return nil }
        return installedFont(named: family, size: size, traits: traits)
    }

    private static func windowsFontFileStem(of name: String) -> String {
        let extensions = ["ttf", "ttc", "otf", "fon"]
        guard let dot = name.lastIndex(of: "."),
              extensions.contains(name[name.index(after: dot)...].lowercased()) else { return name }
        return String(name[name.startIndex..<dot])
    }

    /// Windows font filenames to the families they hold. Bold/italic variants map to the same family
    /// because `bold="1"`/`italic="1"` are their own attributes here — the file the skin happened to
    /// name does not get to set a trait the object did not ask for.
    private static let windowsFontFileFamilies: [String: String] = [
        "arial": "Arial", "arialbd": "Arial", "ariali": "Arial", "arialbi": "Arial",
        "ariblk": "Arial Black",
        "calibri": "Calibri", "calibrib": "Calibri", "calibrii": "Calibri", "calibriz": "Calibri",
        "comic": "Comic Sans MS", "comicbd": "Comic Sans MS",
        "consola": "Consolas", "consolab": "Consolas", "consolai": "Consolas", "consolaz": "Consolas",
        "cour": "Courier New", "courbd": "Courier New", "couri": "Courier New", "courbi": "Courier New",
        "framd": "Franklin Gothic Medium", "framdit": "Franklin Gothic Medium",
        "georgia": "Georgia", "georgiab": "Georgia", "georgiai": "Georgia", "georgiaz": "Georgia",
        "impact": "Impact",
        "lucon": "Lucida Console",
        // MS Sans Serif is the Windows UI face of the era and ships nowhere here; Helvetica is what
        // it substitutes to, and is the reason this entry earns its place at all.
        "micross": "Helvetica",
        "pala": "Palatino", "palab": "Palatino", "palai": "Palatino", "palabi": "Palatino",
        "segoeui": "Segoe UI", "segoeuib": "Segoe UI", "segoeuii": "Segoe UI", "segoeuiz": "Segoe UI",
        "symbol": "Symbol",
        "tahoma": "Tahoma", "tahomabd": "Tahoma",
        "times": "Times New Roman", "timesbd": "Times New Roman", "timesi": "Times New Roman",
        "timesbi": "Times New Roman",
        "trebuc": "Trebuchet MS", "trebucbd": "Trebuchet MS", "trebucit": "Trebuchet MS",
        "trebucbi": "Trebuchet MS",
        "verdana": "Verdana", "verdanab": "Verdana", "verdanai": "Verdana", "verdanaz": "Verdana",
        "webdings": "Webdings",
        "wingding": "Wingdings",
    ]

    /// A font installed on the system, by family or PostScript name. Optional for the same reason as
    /// everything else here: the name comes from the skin, and a null must never reach CoreText.
    private static func installedFont(named name: String, size: CGFloat,
                                      traits: NSFontTraitMask) -> NSFont? {
        let manager = NSFontManager.shared
        if let family: NSFont = manager.font(withFamily: name, traits: traits, weight: 5, size: size) {
            return family
        }
        guard let exact: NSFont = NSFont(name: name, size: size) else { return nil }
        return applying(traits, to: exact)
    }

    private static func applying(_ traits: NSFontTraitMask, to font: NSFont) -> NSFont? {
        guard !traits.isEmpty else { return font }
        let converted: NSFont? = NSFontManager.shared.convert(font, toHaveTrait: traits)
        return converted ?? font
    }

    /// A cell width per character, for a text object that asks to be drawn fixed-pitch.
    ///
    /// `forcefixed="1"` gives every glyph the same advance — a clock whose digits do not shuffle
    /// sideways as they tick — and `timecolonwidth` gives the colon a narrower cell of its own, since
    /// a full digit cell around a colon leaves a visible hole. Love is War Miku's `0:00` readout is
    /// exactly this pair, and drawn proportionally it is both narrower and unstable.
    struct FixedPitch {
        let cell: CGFloat
        let colon: CGFloat

        func width(of text: String) -> CGFloat {
            text.reduce(0) { $0 + ($1 == ":" ? colon : cell) }
        }
    }

    /// The widest digit is the cell: Winamp sizes the run so any digit fits any position.
    static func fixedPitch(of object: WasabiObject, font: NSFont) -> FixedPitch? {
        guard isEnabled(object.attributes["forcefixed"]) else { return nil }
        // A skin pixel, not a point size: this is a width in the same units as `w`/`h`.
        let colon = object.attributes["timecolonwidth"].flatMap { Double($0) }
        let cell = digitCell(font)
        return FixedPitch(cell: cell, colon: colon.map { CGFloat($0) } ?? cell)
    }

    /// A clock readout laid out field by field, rather than as one string.
    ///
    /// A time is `hours`, `:`, `minutes`, `:`, `seconds`, and the colons carry cells of their own so
    /// the digits keep their columns as the clock ticks. `timecolonwidth` sizes that cell, and a skin
    /// that narrows it is buying room beside the readout: Big Bento Modern parks a `/` separator in a
    /// box that overlaps the elapsed time's box by four pixels, and the two only read as separate
    /// because neither draws flush against the edge it is aligned to.
    struct ClockRun {
        /// One field with the cell it occupies, which is not always the width it draws in — a
        /// fixed-pitch cell is wider than the glyph it centres.
        struct Cell {
            let text: String
            let width: CGFloat
            /// Whether the glyph sits in the middle of its cell or at the cell's left edge. A colon
            /// always centres: a skin sizing that cell means to move the digits around it, not to
            /// leave the colon leaning against the digits on one side (Sony Walkman, Styx, T800 and
            /// the Nokia 5220 all declare a cell wider than the glyph).
            let centred: Bool
        }

        let cells: [Cell]
        /// The room the run is aligned by, which is the room its *longest* value needs — so a clock
        /// that rolls from `9:59` to `10:00` grows into the space it was already holding instead of
        /// shoving its own digits a column sideways. Never less than what is on screen now.
        let layoutWidth: CGFloat

        /// What the value on screen actually draws in — the answer `getTextWidth()` wants.
        var width: CGFloat { cells.reduce(0) { $0 + $1.width } }

        /// Clearance kept between the run and the box edge it aligns against.
        static let edgeInset: CGFloat = 2
    }

    /// How the object's clock lays out, or `nil` if it is not drawing one.
    ///
    /// The renderer and `getTextWidth()` both ask here, because a skin measures this run to decide
    /// where to put everything beside it.
    static func clockRun(of object: WasabiObject, text: String, font: NSFont) -> ClockRun? {
        guard isClockDisplay(object), text.contains(":") else { return nil }
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        func measure(_ string: String) -> CGFloat {
            (string as NSString).size(withAttributes: attributes).width
        }
        let pitch = fixedPitch(of: object, font: font)
        // A skin pixel, in the same units as `w`/`h`. Left undeclared, the colon keeps its own advance
        // and the run measures exactly as the string does.
        let declaredColon = object.attributes["timecolonwidth"].flatMap { Double($0) }.map { CGFloat($0) }
        let colonWidth = pitch?.colon ?? declaredColon ?? measure(":")

        var cells: [ClockRun.Cell] = []
        var leadingField = CGFloat(0)
        for (index, field) in text.split(separator: ":", omittingEmptySubsequences: false).enumerated() {
            if index > 0 { cells.append(.init(text: ":", width: colonWidth, centred: true)) }
            let field = String(field)
            guard let pitch else {
                let width = measure(field)
                if index == 0 { leadingField = width }
                cells.append(.init(text: field, width: width, centred: false))
                continue
            }
            // Fixed pitch is per glyph, not per field: every digit needs its own cell to be centred in.
            if index == 0 { leadingField = pitch.cell * CGFloat(field.count) }
            cells.append(contentsOf: field.map { .init(text: String($0), width: pitch.cell, centred: true) })
        }
        let drawn = cells.reduce(0) { $0 + $1.width }
        // A skin that sizes the colon's cell is asking for a clock in columns, so the leading field
        // holds room for the two digits it can reach even while it is showing one. Big Bento Modern's
        // elapsed time is the case that shows it: right-aligned, it would otherwise sit hard against
        // the `/` beside it and then jump a whole digit sideways at 10:00.
        let leadingRoom = declaredColon == nil ? leadingField : max(leadingField, 2 * digitCell(font))
        return ClockRun(cells: cells, layoutWidth: drawn - leadingField + leadingRoom)
    }

    /// The cell a colon takes in a **bitmap-font** clock readout, or `nil` when the object is not
    /// one or declares no `timecolonwidth`.
    ///
    /// A bitmap font is a fixed-pitch atlas, so its colon is inked into part of a full-width cell and
    /// advancing the whole cell leaves the remainder as a gap before the next field. Only a clock has
    /// fields, so only a clock reads the attribute — the same restriction `clockRun` puts on the Core
    /// Text path. See `WasabiSceneRenderer.drawBitmapText`.
    static func bitmapColonWidth(of object: WasabiObject) -> CGFloat? {
        guard isClockDisplay(object),
              let declared = object.attributes["timecolonwidth"].flatMap({ Double($0) }),
              declared > 0 else { return nil }
        return CGFloat(declared)
    }

    /// The cell a digit needs: the widest of them, so any digit fits any column.
    private static func digitCell(_ font: NSFont) -> CGFloat {
        "0123456789".map {
            (String($0) as NSString).size(withAttributes: [.font: font]).width
        }.max() ?? font.pointSize
    }

    /// Whether this object's text is a playback time — the only text drawn as a clock run.
    private static func isClockDisplay(_ object: WasabiObject) -> Bool {
        switch object.attributes["display"]?.lowercased() {
        case "time", "timeelapsed", "songlength": return true
        default: return false
        }
    }

    /// The bold/italic a text object asks for. Winamp spells them as their own attributes rather than
    /// as part of the font name.
    static func traits(of object: WasabiObject) -> NSFontTraitMask {
        var traits: NSFontTraitMask = []
        if isEnabled(object.attributes["bold"]) { traits.insert(.boldFontMask) }
        if isEnabled(object.attributes["italic"]) { traits.insert(.italicFontMask) }
        return traits
    }

    /// Where a text object sits inside its own box vertically.
    ///
    /// Wasabi centres a string in its rect unless the skin says otherwise, and `valign=` is how it
    /// says so: 63 declarations across 9 of the 17 corpus skins, 54 of them `top`. It is the
    /// difference between a songticker on its baseline and one floating in the middle of a tall
    /// display (Defix), and between a bitmap-font readout inside its LED window and one riding its
    /// upper edge (multipass).
    enum VerticalAlignment {
        case top, center, bottom

        /// The offset from the box's top edge for a run `cell` tall inside a box `height` tall.
        func offset(cell: CGFloat, in height: CGFloat) -> CGFloat {
            switch self {
            case .top: return 0
            case .center: return (height - cell) / 2
            case .bottom: return height - cell
            }
        }
    }

    /// A declared `valign` Wasabi does not know is **not** the default: it reads as `top`.
    ///
    /// Only the absent attribute centres. The difference is a skin whose author corrected for it:
    /// Big Bento Modern's two small clock readouts declare `valign="middle"` — which is not one of
    /// the three spellings — and `songticker.maki` then pushes each of them down by 4px, which is
    /// exactly `(30 - 21) / 2`, the gap between the top of a 30px box and a 21px line centred in it.
    /// Read `middle` as `center` and that correction lands on top of a centring we already did, so
    /// the two times sit 4px below the `/` between them, which declares no `valign` at all.
    static func verticalAlignment(of object: WasabiObject) -> VerticalAlignment {
        guard let declared = object.attributes["valign"]?.lowercased() else { return .center }
        switch declared {
        case "center": return .center
        case "bottom": return .bottom
        default: return .top
        }
    }

    /// `wrap="1"` — the Text class's multi-line mode. The string is broken at word boundaries inside
    /// the object's own width and laid out downward; it never scrolls, because a paragraph is not a
    /// ticker. This is the whole difference between a label and the body of a `<Wasabi:TitleBox>`,
    /// and without it a paragraph draws as its first clipped line (B91).
    static func wraps(of object: WasabiObject) -> Bool {
        isEnabled(object.attributes["wrap"])
    }

    private static func isEnabled(_ value: String?) -> Bool {
        guard let value = value?.lowercased() else { return false }
        return !["0", "off", "false", "no", ""].contains(value)
    }

    /// Point size a text object draws at, clamped to something CoreText will accept. A skin (or one
    /// of its scripts) may name 0, a negative, or an unparseable size.
    ///
    /// `fontsize=` is a **pixel height**, not a point size: Winamp hands it to GDI as a font height,
    /// and the em it ends up drawing is measurably smaller than the number. Measured against Love is
    /// War Miku's own screenshot (its shipped reference for the skin): `fontsize="30"` draws digits
    /// 17px tall — Arial's cap height at a 24px em — and `fontsize="10"` matches an 8px em, both at
    /// the same 0.8 ratio. Taken as a point size, every string is a quarter too big and overflows the
    /// box the skin drew for it.
    static func pointSize(of object: WasabiObject) -> CGFloat {
        CGFloat(pixelHeight(of: object) * pixelHeightToPointSize)
    }

    /// The `fontsize=` a text object declares, clamped — a pixel cell height in the skin's own units,
    /// before the conversion to a point size the drawing needs.
    static func pixelHeight(of object: WasabiObject) -> Double {
        let requested = Double(object.attributes["fontsize"] ?? "11") ?? 11
        return requested.isFinite ? min(max(requested, 1), 256) : 11
    }

    static let pixelHeightToPointSize = 0.8

    /// The one place a component's own text comes from.
    ///
    /// A skin's playlist status line is `<text id="PE_Info">`, whose contents Winamp fills in from the
    /// playlist component. The renderer draws it and a script measures it with `getAutoWidth()`, so
    /// both have to ask the same question — and neither may reach into the component host directly
    /// (the script runtime has no host adapter, and the measurement runs in the headless harness).
    /// The window controller installs this; unset, a `PE_Info` simply reads empty.
    static var componentTextProvider: (() -> WinampModernPlaylistSnapshot?)?

    /// The name beside the thinger: `<text display="componentbucket">` reads whichever icon the
    /// bucket has the focus on (B34). Installed alongside `componentTextProvider` and for the same
    /// reason — the state is the loaded skin's, and neither the renderer's static text resolution nor
    /// a script's `getAutoWidth()` has a route to it. Unset, the caption reads empty, which is what
    /// it did before there were any icons.
    static var componentBucketTextProvider: (() -> String?)?

    /// Whether this object's content comes from the **host** rather than from its own markup — a
    /// `display=` binding, a songticker, or the playlist status line. Only these can change without a
    /// script touching them, so only these are worth polling for `onTextChanged`.
    static func isHostBoundText(_ object: WasabiObject) -> Bool {
        if isPlaylistStatusLine(object) { return true }
        if object.typeName.caseInsensitiveCompare("songticker") == .orderedSame { return true }
        return !(object.attributes["display"] ?? "").isEmpty
    }

    /// Whether this object is the skin's playlist status line, by **either** of the two forms skins
    /// use: `id="PE_Info"` or `display="PE_Info"`. Both are live in the measured corpus.
    static func isPlaylistStatusLine(_ object: WasabiObject) -> Bool {
        if let identifier = object.xmlID, identifier.caseInsensitiveCompare("PE_Info") == .orderedSame {
            return true
        }
        return object.attributes["display"]?.caseInsensitiveCompare("PE_Info") == .orderedSame
    }

    /// What a text object currently shows. `display=` binds it to a playback value; a `songticker`
    /// carries no text of its own and always shows the current track.
    static func content(of object: WasabiObject, host: WinampModernHost) -> String {
        // The status line is claimed **either** by `id="PE_Info"` (mmd3) **or** by
        // `display="PE_Info"` (Defix, whose `<text id="info.input" display="PE_Info" w="0" h="0"
        // visible="0"/>` is a hidden feed its script parses into the playlist box's track count and
        // total time). Matching only the id left Defix's script reading an empty string, so
        // `onTextChanged` never fired and both readouts sat on their XML placeholder, "-".
        if isPlaylistStatusLine(object) {
            return componentTextProvider?()?.infoLine ?? ""
        }
        // A script's `setAlternateText` *overrides* the content for as long as it is set (MMD3 shows
        // its SEEK/VOLUME/BASS/TREBLE readouts on the song ticker this way). The XML attribute of the
        // same name is a different thing: a placeholder for "nothing to show". Treating the two as one
        // value pinned MMD3's display to its shipped placeholder, "updating songticker", forever.
        if let override = object.attributes[scriptAlternateTextKey], !override.isEmpty { return override }
        // A script's `setText` beats the object's `display=` binding, which is how Winamp behaves:
        // there the binding *writes* the object's text when its value changes, so whatever was
        // written last is what shows. Skins rely on both halves. Big Bento Modern gives all 17 of its
        // `Bento:InfoLine` objects `display="SONGNAME"` **purely so `ticker="1"` works**
        // ("Victhor trick", `xml/player-normal-mcv.xml:378`) and fills each one from `fileinfo.m`;
        // resolving the binding first drew the song title on every line. The revert half is the
        // commoner pattern — a transient readout over the songticker (MMD3's VOLUME/BASS/TREBLE,
        // Styx's and Ebonite's seek and volume overlays, micro's `oldtimer.m` clock over
        // `display="time"`) that is taken back down with `setText("")`.
        if let override = object.attributes[scriptTextKey], !override.isEmpty { return override }
        let resolved = bound(object, host: host)
        if resolved.isEmpty, let placeholder = object.attributes["alternatetext"], !placeholder.isEmpty {
            return placeholder
        }
        return resolved
    }

    /// Where `setAlternateText` keeps its value — deliberately not the XML `alternatetext` attribute.
    /// Not a Wasabi attribute name, so a skin cannot declare it.
    static let scriptAlternateTextKey = "nullplayer.script.alternatetext"

    /// Where `setText` keeps its value, for the same reason: a skin must not be able to declare an
    /// override in markup. The XML `text=` attribute keeps its own meaning — the literal an unbound
    /// object draws — and `setText` writes it too, so anything reading the attribute directly (a
    /// `<Wasabi:Button>` label) still follows the script.
    static let scriptTextKey = "nullplayer.script.text"

    private static func bound(_ object: WasabiObject, host: WinampModernHost) -> String {
        switch object.attributes["display"]?.lowercased() {
        // `time` and `timeelapsed` are the same value under two spellings; both are live in the
        // corpus (64 and 4 declarations respectively).
        case "time", "timeelapsed": return clock(host.currentTime, on: object)
        case "songlength": return clock(host.duration, on: object)
        // Winamp's "song name" is the playlist's display title — "Artist - Title" — which is exactly
        // what a skin puts in its main display, and what `songticker` shows. `songtitle` is the
        // *title alone*, which is a different field: Big Bento Modern's main display is
        // `display="SONGTITLE"` with the artist on its own line beside it.
        case "songname": return host.trackDisplayTitle
        case "songtitle": return host.trackTitle
        case "songartist", "artistname": return host.trackArtist
        case "songalbum": return host.trackAlbum
        // Both are bare numbers next to a `KBPS` / `KHZ` label the skin draws itself, so the sample
        // rate is in kHz rather than Hz — Big Bento Modern gives its `Frequency` readout 35 pixels,
        // which fits "44" and not "44100".
        case "songbitrate": return host.bitrateKbps > 0 ? String(host.bitrateKbps) : ""
        case "songsamplerate":
            return host.sampleRateHz > 0 ? String(Int((Double(host.sampleRateHz) / 1000).rounded())) : ""
        // `songinfo` is the **stream info** line, not the artist/album: `songinfo.maki` reads this
        // object's own text back and tokenises it looking for `kbps`, `khz` and the channel words,
        // which is the only way MMD3's KBPS/KHZ fields are ever filled in.
        case "songinfo": return host.songInfoText
        // The thinger's caption — the component its strip is pointing at.
        case "componentbucket": return componentBucketTextProvider?() ?? ""
        default:
            if object.typeName.caseInsensitiveCompare("songticker") == .orderedSame {
                return host.trackDisplayTitle
            }
            let literal = object.attributes["text"] ?? object.attributes["default"] ?? ""
            return resolvePlaceholder(unescaped(literal), on: object)
        }
    }

    /// Line breaks a skin spelled in its markup. XML has no way to write one inside an attribute, so
    /// a multi-paragraph literal is written the way the MAKI compiler takes it — `\n` — and the pair
    /// has to be turned back into the character before anything measures or draws it. Hal's Eye's
    /// credits box is the corpus's only such literal, and the escapes ran straight through into the
    /// drawn paragraph: *"…use his scripts!\n\nIdeas: SLoB…"* (B91).
    ///
    /// Deliberately only the markup literal. A string a script assigned already carries real
    /// newlines — MAKI resolves its own escapes at compile time — so translating there would eat a
    /// backslash the script meant to keep.
    private static func unescaped(_ literal: String) -> String {
        guard literal.contains("\\") else { return literal }
        return literal.replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\t", with: "\t")
    }

    /// A playback time in the form a clock readout draws it. `timerhours="1"` asks for an `h:mm:ss`
    /// field once the value passes an hour — without it a long set or a podcast reads as `93:20`,
    /// and the skin sized the box for `1:33:20`.
    private static func clock(_ time: TimeInterval, on object: WasabiObject) -> String {
        let total = max(0, Int(time.isFinite ? time : 0))
        let (hours, minutes, seconds) = (total / 3600, (total / 60) % 60, total % 60)
        if hours > 0, isEnabled(object.attributes["timerhours"]) {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", total / 60, seconds)
    }

    /// Wasabi's title-bar placeholders. A standard frame's title is
    /// `<text default=":componentname"/>` — the colon marks a value the frame supplies, not a string
    /// to draw. Left unresolved, a window's title bar reads ":componentname" *and* the script's
    /// `getAutoWidth()` sizes the title to that literal, so the box does not fit the real name.
    private static func resolvePlaceholder(_ value: String, on object: WasabiObject) -> String {
        guard value.hasPrefix(":") else { return value }
        let key = String(value.dropFirst()).lowercased()
        guard key == "componentname" || key == "name" else { return value }
        // Nearest wins: the XUI frame instance that declares `componentname=`, else the container's
        // own `name=`.
        var current: WasabiObject? = object
        var depth = 0
        while let node = current, depth < 64 {
            if let name = node.attributes["componentname"], !name.isEmpty { return name }
            if node.typeName.caseInsensitiveCompare("container") == .orderedSame,
               let name = node.attributes["name"], !name.isEmpty {
                return name
            }
            current = node.parent
            depth += 1
        }
        return ""
    }

    /// Width the object's text occupies when drawn, in skin pixels, including its horizontal padding.
    /// Bitmap fonts are a fixed-pitch atlas (`charwidth` + `hspacing` per glyph); everything else is
    /// measured with the very font `WasabiSceneRenderer.drawText` would use.
    func width(of object: WasabiObject, text: String) -> CGFloat {
        let padding = CGFloat((Double(object.attributes["leftpadding"] ?? "0") ?? 0)
                              + (Double(object.attributes["rightpadding"] ?? "0") ?? 0))
        if let fontID = object.attributes["font"],
           let definition = loadedSkin.runtime.resources.resolvedDefinition(identifier: fontID),
           definition.kind == "bitmapfont" {
            let charWidth = max(1, Int(Double(definition.attributes["charwidth"] ?? "1") ?? 1))
            let spacing = Int(Double(definition.attributes["hspacing"] ?? "0") ?? 0)
            let advance = CGFloat(max(1, charWidth + spacing))
            // The colon's cell, on the one atlas glyph that has one — the same rule the bitmap draw
            // path applies, because a skin lays out everything beside a clock from this measurement.
            guard let colon = Self.bitmapColonWidth(of: object) else {
                return CGFloat(text.count) * advance + padding
            }
            return text.reduce(padding) { $0 + ($1 == ":" ? max(1, colon.rounded()) : advance) }
        }
        let size = Self.pointSize(of: object)
        let font = font(identifier: object.attributes["font"], size: size,
                        traits: Self.traits(of: object)) ?? NSFont.systemFont(ofSize: size)
        if let run = Self.clockRun(of: object, text: text, font: font) {
            return run.width + padding
        }
        if let pitch = Self.fixedPitch(of: object, font: font) {
            return pitch.width(of: text) + padding
        }
        return measuredWidth(of: text, font: font) + padding
    }

    /// Height of one line of the object's text, in skin pixels — the vertical answer to `width(of:)`,
    /// and what a script's `getAutoHeight()` reads. A bitmap font's atlas states its own cell height;
    /// everything else is the drawing font's line height.
    func lineHeight(of object: WasabiObject) -> CGFloat {
        if let fontID = object.attributes["font"],
           let definition = loadedSkin.runtime.resources.resolvedDefinition(identifier: fontID),
           definition.kind == "bitmapfont" {
            let charHeight = Double(definition.attributes["charheight"] ?? "") ?? 0
            let spacing = Double(definition.attributes["vspacing"] ?? "0") ?? 0
            if charHeight > 0 { return CGFloat(charHeight + spacing) }
        }
        // For everything else the line height *is* `fontsize`: Winamp hands that number to GDI as the
        // font's cell height, so the height a script reads back is the number the skin wrote, not a
        // value derived from the face's own metrics. That is exactly what Big Bento Modern's tab strip
        // counts on — `4 * label.y + label.getAutoHeight()` with `y="9"` and `fontsize="24"` is the
        // skin's own 60-pixel tab — and a CoreText line height for the same label answers 25, which
        // drifts the whole strip two pixels per tab. The point size the *drawing* uses is a different
        // number (`pointSize(of:)`, 0.8 of this one), because the em GDI ends up rendering inside that
        // cell is smaller than the cell.
        return CGFloat(Self.pixelHeight(of: object))
    }

    /// The Wasabi default cell height, and the base every host-drawn size is a multiple of.
    ///
    /// What a **host-drawn** list (the embedded playlist, the embedded library) actually draws at is
    /// `WinampModernTextScale`, not anything measured here: there is no `fontsize` on a
    /// `<windowholder>` to read, and the skin's *nearby* fonts turned out not to separate the skins
    /// that want large rows from the ones that do not. The `<text>`/`<edit>`/`<list>` paths above,
    /// which read a size the skin really did declare for its own object, are unaffected.
    static let defaultPixelHeight = 11.0
}
