import AppKit
import CoreGraphics
import Foundation

/// Colour resolution: the palette and its report, the `gammagroup`/`gammaset` transform
/// applied to a declared colour, the `<gradient>` stop list, and the id-chain dereference
/// behind `resolvedColor`. Split out of `WasabiRenderer.swift`; see
/// `skills/winamp-modern-skin-guide/reference/rendering/colour.md`.
extension WasabiSceneRenderer {
    @discardableResult
    func activateTheme(_ name: String) -> Bool {
        // The coordinator switches once and notifies every subscriber, this renderer included.
        themeCoordinator.activate(name)
    }

    /// Drop this renderer's themed bitmaps and repaint. Called for every renderer of the skin when
    /// any of them switches theme.
    func themeDidChange() {
        resources.invalidateTheme()
        paletteCache = nil
        surfaceStyleCache = nil
        warpSourceCache.removeAll()
        warpedImageCache.removeAll()
        clearPrescaledCache()
        invalidateSceneCache()
        loadedSkin.runtime.graph.markAllDirty(.appearance)
    }

    /// The colours NullPlayer's own surfaces draw with inside this skin, resolved through the very
    /// same resource + gamma path the skin's own drawing uses.
    var palette: WasabiPalette {
        if let paletteCache { return paletteCache }
        let palette = WasabiPalette.make { [weak self] identifier in
            guard let self,
                  let definition = loadedSkin.runtime.resources.resolvedColorDefinition(identifier: identifier),
                  Self.declaredColor(of: definition) != nil else { return nil }
            return resolvedColor(identifier)
        }
        paletteCache = palette
        return palette
    }

    /// The chrome those same colours widen into — what NullPlayer paints where a skin expected
    /// Winamp's own artwork. Identical to the style the app's fallback windows use, so a hosted
    /// standard frame and the playlist window beside it are the same surface.
    var surfaceStyle: WinampModernSurfaceStyle {
        if let surfaceStyleCache { return surfaceStyleCache }
        let style = WinampModernSurfaceStyle(palette: palette)
        surfaceStyleCache = style
        return style
    }

    /// A line-per-link account of how `palette` resolved, for the `RENDER_PALETTE` probe.
    ///
    /// The palette is the one thing about an embedded surface that *is* observable headlessly — the
    /// harness sets no component host, so nothing is drawn into a holder, but the colours those
    /// surfaces would be painted in resolve exactly as they do in the app. Every link reports why it
    /// answered or did not (missing definition, a bitmap with no `color=`, a value that is not three
    /// numbers), plus the declared value, the gammagroup, and the RGB the gamma left behind — which
    /// is what tells "the skin never declared it" apart from "a colour theme crushed it" (BB2a).
    func paletteResolutionReport() -> [String] {
        var lines: [String] = []
        let palette = palette
        for role in WasabiPalette.Role.allCases {
            let resolved = palette.color(for: role)
            lines.append("PALETTE \(role.rawValue) = \(Self.describe(resolved)) "
                         + "(fallback: \(role.fallbackDescription))")
            for identifier in role.identifiers {
                lines.append("PALETTE   \(identifier): \(describeLink(identifier))")
            }
        }
        return lines
    }

    /// Why one identifier in a role's chain answered, or did not.
    private func describeLink(_ identifier: String) -> String {
        guard let definition = loadedSkin.runtime.resources.resolvedColorDefinition(identifier: identifier) else {
            return "undeclared"
        }
        let origin = "kind=\(definition.kind)"
            + (definition.attributes["file"].map { " file=\($0)" } ?? "")
        guard let declared = Self.declaredColor(of: definition) else {
            // A bitmap that is a real image file carries no colour, so the chain skips it.
            return "\(origin) — no declared colour, skipped"
        }
        let (literal, gammaGroup) = Self.dereference(declared,
                                                     gammaGroup: definition.attributes["gammagroup"],
                                                     resources: loadedSkin.runtime.resources)
        let reference = literal == declared ? "" : " -> \(literal)"
        let gammagroup = gammaGroup.map { " gammagroup=\($0)" } ?? ""
        return "\(origin) value=\(declared)\(reference)\(gammagroup) -> \(Self.describe(resolvedColor(identifier)))"
    }

    /// `r,g,b` in the 0…255 the skin's XML is written in, so a probe line can be compared against the
    /// skin file by eye.
    private static func describe(_ color: NSColor) -> String {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return "non-RGB" }
        return String(format: "rgb(%.0f,%.0f,%.0f)", rgb.redComponent * 255,
                      rgb.greenComponent * 255, rgb.blueComponent * 255)
    }

    /// The colour an object declares **inline**, with that object's own `gammagroup` applied.
    ///
    /// A named `<color>` resource carries its own gammagroup and `resolvedColor` already applies it;
    /// applying the object's on top would tint the same channels twice.
    func objectColor(_ raw: String, gammaGroup: String?) -> NSColor {
        if let definition = loadedSkin.runtime.resources.resolvedColorDefinition(identifier: raw),
           Self.declaredColor(of: definition) != nil {
            return resolvedColor(raw)
        }
        let base = Self.color(raw)
        guard let gamma = themes.transform(group: gammaGroup), !gamma.isIdentity else { return base }
        let (red, green, blue) = Self.themed(red: base.redComponent, green: base.greenComponent,
                                             blue: base.blueComponent, gamma: gamma)
        return NSColor(red: red, green: green, blue: blue, alpha: base.alphaComponent)
    }

    /// One colour through a `<gammagroup>`: desaturate first if the group asks, then offset or scale
    /// each channel per its `boost` mode — the same order the bitmap and `<color>` paths use.
    static func themed(red: CGFloat, green: CGFloat, blue: CGFloat,
                               gamma: WasabiGammaTransform) -> (CGFloat, CGFloat, CGFloat) {
        var (red, green, blue) = (red, green, blue)
        if gamma.grayscale {
            let luminance = red * 0.299 + green * 0.587 + blue * 0.114
            (red, green, blue) = (luminance, luminance, luminance)
        }
        return (max(0, min(1, gamma.apply(red, amount: gamma.red))),
                max(0, min(1, gamma.apply(green, amount: gamma.green))),
                max(0, min(1, gamma.apply(blue, amount: gamma.blue))))
    }

    /// A row colour that can be read on the bar behind it, for the lists **this renderer** draws
    /// itself — the skin's own playlist panel and colour-theme picker.
    ///
    /// The same guarantee `WinampModernSurfaceStyle` gives NullPlayer's AppKit surfaces (B48), needed
    /// again here because these rows never pass through a style: they read `WasabiPalette` directly,
    /// and the palette resolves each role from an independent id chain with nothing checking that the
    /// pair can be seen together. Big Bento is the measured case — `selectionText` is its pale
    /// blue-grey `color.display` and `selectionBackground` its orange `color.selected.active`, 1.06:1
    /// apart, and a *current* row over that same bar is orange on orange at 1.00:1.
    ///
    /// Unselected rows are returned untouched: they land on the content background, which is a
    /// separate pairing and a separate measurement.
    func legibleRowColor(_ preferred: NSColor, selected: Bool) -> NSColor {
        guard selected else { return preferred }
        return WinampModernSurfaceStyle.legible(
            preferring: [preferred, palette.selectionText, palette.currentText, palette.listText,
                         palette.contentBackground],
            on: rowSelectionBackground)
    }

    /// The bar a selected row is actually **filled** with, which is not always the one the skin
    /// named (B122).
    ///
    /// `selectionBackground` only marks a row when it can be told apart from the plate it sits on.
    /// Firefox declares `studio.list.item.selected` at `7,92,129` — the same value as its
    /// `wasabi.list.background` — so the fill paints the plate onto the plate and nothing appears.
    /// A bar derived from the skin's own two ends, the way `WinampModernSurfaceStyle` derives every
    /// other piece of chrome, is the smallest thing that gives such a skin a visible selection
    /// without inventing a colour from outside its palette. A skin whose bar already differs keeps
    /// it untouched.
    ///
    /// The threshold is deliberately far below `minimumContrast`: this asks "is anything drawn at
    /// all", not "can text be read on it".
    var rowSelectionBackground: NSColor {
        let plate = palette.contentBackground
        guard WinampModernSurfaceStyle.contrastRatio(palette.selectionBackground, plate) < 1.15 else {
            return palette.selectionBackground
        }
        return WinampModernSurfaceStyle.blend(plate, toward: palette.listText, by: 0.35)
    }

    /// The playing row's colour, which has to stay distinguishable from an ordinary row's.
    ///
    /// `legible` walks to the skin's *other* colours when the preferred one cannot be read, and on a
    /// skin whose current colour is unreadable that walk ends on `listText` — the very colour every
    /// other row is drawn in. The guard that made the row readable also made it anonymous, which is
    /// how Firefox's playlist ended up with no marker on the playing track at all. Dropping the plain
    /// colour from the candidates leaves the black/white extreme as the last resort, which always
    /// clears the threshold and can never collide with the row colour it exists to differ from.
    ///
    /// Only called when the skin actually named a current colour; a skin that named none is marked by
    /// its selection bar, as Winamp marks it.
    func legibleCurrentRowColor(on background: NSColor, plain: NSColor) -> NSColor {
        let candidates = [palette.currentText, palette.selectionText].filter { $0 != plain }
        return WinampModernSurfaceStyle.legible(preferring: candidates, on: background)
    }

    /// The `r,g,b` a resource declares, or `nil` when it declares no colour at all.
    ///
    /// Two kinds carry one. A `<color>` obviously does — and a **generated solid bitmap**
    /// (`<bitmap file="$solid" color="8,9,10">`) does too: it *is* a colour, with the pixels
    /// synthesized from it. cPro-Bento declares `wasabi.list.background` as both, and the bitmap wins
    /// the registry, so insisting on `kind == "color"` sent the name down the literal-parsing path,
    /// where it is not three numbers and became the **white** fallback — a white slab across the tab
    /// strip and behind the SUI list surfaces of a near-black skin.
    private static func declaredColor(of definition: WalResourceDefinition) -> String? {
        if definition.kind == "color" { return definition.attributes["value"] ?? "255,255,255" }
        guard definition.kind == "bitmap",
              definition.attributes["file"]?.hasPrefix("$") == true else { return nil }
        return definition.attributes["color"]
    }

    /// Follow a `<color>` whose value names another colour resource until a literal triple is
    /// reached, carrying the first `gammagroup` seen along the chain.
    ///
    /// Bounded and cycle-guarded like the alias walk in the registry: a skin can write
    /// `value="<id>"` pointing anywhere, including at itself.
    private static func dereference(_ declared: String, gammaGroup: String?,
                                    resources: WalResourceRegistry) -> (value: String, gammaGroup: String?) {
        var value = declared
        var group = gammaGroup
        var visited: Set<String> = []
        for _ in 0..<16 {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            // A literal (`r,g,b` or `#rrggbb`) ends the walk; anything else may be an id to follow.
            if channels(of: trimmed) != nil { return (value, group) }
            guard visited.insert(trimmed.lowercased()).inserted,
                  let next = resources.resolvedColorDefinition(identifier: trimmed),
                  let nextDeclared = declaredColor(of: next), nextDeclared != value else {
                return (value, group)
            }
            value = nextDeclared
            group = group ?? next.attributes["gammagroup"]
        }
        return (value, group)
    }

    private static func color(_ raw: String) -> NSColor {
        // A skin writes an inline colour two ways. `r,g,b` is the common one; **`#rrggbb` is not
        // rare** — Big Bento Modern writes all 22 of its analyzer colours that way
        // (`colorband1="#5a5490"` … `colorband16="#bda4fc"`, plus `colorbandpeak` and `colorosc1..5`),
        // and with only the triple parsed every one of them fell through to `unparseableColor`. That
        // is white, so the skin's purple analyzer drew as white slabs wherever it appeared.
        if let hex = hexColor(raw) { return hex }
        let values = raw.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard values.count >= 3 else { return unparseableColor }
        return NSColor(red: max(0, min(255, values[0])) / 255,
                       green: max(0, min(255, values[1])) / 255,
                       blue: max(0, min(255, values[2])) / 255,
                       alpha: 1)
    }

    /// The 0…255 channels a **declared** colour value spells out, either as `r,g,b` or as `#rrggbb`,
    /// or `nil` for a value that is neither.
    ///
    /// Only the colour-*resource* path uses this. A `<color value="#800000">` cannot be anything but
    /// a literal — Enkera declares its whole palette that way, and every one of those roles was
    /// resolving to `unparseableColor`, i.e. white text on a white list (BB2a). The inline-attribute
    /// path in `color(_:)` keeps its own rules, where a bare token may still be a resource id.
    private static func channels(of declared: String) -> [CGFloat]? {
        if let hex = hexColor(declared), let rgb = hex.usingColorSpace(.deviceRGB) {
            return [rgb.redComponent * 255, rgb.greenComponent * 255, rgb.blueComponent * 255]
        }
        let values = declared.split(separator: ",")
            .map { CGFloat(Double($0.trimmingCharacters(in: .whitespaces)) ?? 255) }
        return values.count >= 3 ? values : nil
    }

    /// `#rrggbb` or the three-digit shorthand, or `nil` for anything that is not one. Deliberately
    /// strict: a bare `abcdef` with no `#` stays a resource identifier, which is what the caller
    /// already tried it as.
    private static func hexColor(_ raw: String) -> NSColor? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }
        let digits = trimmed.dropFirst()
        guard digits.count == 3 || digits.count == 6, digits.allSatisfy(\.isHexDigit) else { return nil }
        let expanded = digits.count == 3 ? String(digits.flatMap { [$0, $0] }) : String(digits)
        guard let value = UInt32(expanded, radix: 16) else { return nil }
        return NSColor(red: CGFloat((value >> 16) & 0xFF) / 255,
                       green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    func resolvedColor(_ raw: String) -> NSColor {
        Self.resolvedColor(raw, resources: loadedSkin.runtime.resources, themes: themes)
    }

    /// The identifier → RGB resolution, without a renderer.
    ///
    /// Split out for `ColorMgr.getColor(name)`, which the script runtime answers and which has to
    /// resolve exactly as the drawing does — same reference-following, same gammagroup, same theme —
    /// or a widget that colours itself from the skin's palette disagrees with the palette.
    static func resolvedColor(_ raw: String, resources: WalResourceRegistry,
                              themes: WasabiColorThemeCatalog) -> NSColor {
        guard let definition = resources.resolvedColorDefinition(identifier: raw),
              let declared = Self.declaredColor(of: definition) else { return Self.color(raw) }
        // A `<color>`'s value may name **another colour resource** rather than spell out a triple,
        // and Big Bento Modern writes nearly every one of its list colours that way
        // (`wasabi.list.text` = `color.display`, `wasabi.list.background` = `color.window.bg`).
        // Without following the reference the value is not three numbers, so it became
        // `unparseableColor` — white — and the whole skin's list palette came out white-on-black
        // (BB2a). The gammagroup taken is the *referring* declaration's where it has one, so the
        // channels are tinted once, by the group the id that was actually asked for names.
        let (base, gammaGroup) = Self.dereference(declared,
                                                  gammaGroup: definition.attributes["gammagroup"],
                                                  resources: resources)
        guard var values = Self.channels(of: base) else { return Self.unparseableColor }
        let gamma = themes.transform(group: gammaGroup) ?? .identity
        if gamma.grayscale {
            // Same order as the bitmap path: desaturate, then tint.
            let luminance = values[0] * 0.299 + values[1] * 0.587 + values[2] * 0.114
            values = [luminance, luminance, luminance]
        }
        let r = gamma.apply(values[0] / 255, amount: gamma.red)
        let g = gamma.apply(values[1] / 255, amount: gamma.green)
        let b = gamma.apply(values[2] / 255, amount: gamma.blue)
        return NSColor(red: max(0, min(1, r)), green: max(0, min(1, g)),
                       blue: max(0, min(1, b)), alpha: 1)
    }
}
