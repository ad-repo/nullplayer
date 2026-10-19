import AppKit

/// One of the Studio's two looks, in the hosting skin's colours: each kind keeps its own type,
/// grids and fader shapes, and maps the skin's surface roles onto its parts. One layout reads it,
/// and the looks differ in these values, except for the three things drawn per `kind`: the analyser
/// (bars or a filled curve), the fader caps, and the fader scale's engraving.
struct StudioFaceplate {
    enum Kind: String { case console, boutique }

    let kind: Kind
    let panel: NSColor
    let well: NSColor
    let edge: NSColor
    /// Text on the panel; every text colour here clears the contrast guard on the ground it is
    /// drawn on (`SkinnedSurfaceStyle.legible`).
    let text: NSColor
    let dimText: NSColor
    /// A disabled dial's readout: fainter than `dimText`, still readable.
    let inactiveText: NSColor
    /// Text inside a well: the analyser's and graph's labels, the profile name.
    let wellText: NSColor
    let wellDimText: NSColor
    /// What is engaged — the response curve and its dots — in the lit tab's label colour, readable on the panel.
    let accent: NSColor
    let scale: NSColor
    let slot: NSColor
    /// Fader caps by range: low, mid, high.
    let caps: [NSColor]
    let peak: NSColor
    /// Colours at analyser levels (dB), coolest first: Console's bars step through them, Boutique
    /// grades its analyser fill and peak embers with them.
    let heat: [(db: Float, color: NSColor)]
    let legendFont: NSFont
    let buttonFont: NSFont
    /// The analyser's dB lines: their spacing, weight and colour (0 dB's own). Labelled every 12 dB.
    let graticuleStep: Float
    let graticuleWeight: CGFloat
    let graticule: NSColor
    let graticuleZero: NSColor
    /// A hairline at every octave behind the analyser.
    let octaveGrid: Bool
    /// The fader scale's lines, and the preamp's guides and dB labels.
    let faderTicks: [Float]
    let faderTickLabels: [Float]
    let slotWidth: CGFloat
    let capWidth: CGFloat
    /// Boutique on a dark skin draws its analyser, faders and graph through the Metal bloom. On a
    /// light ground everything would cross the bloom's threshold.
    let glows: Bool
    let tab: StudioTab

    static let defaultsKey = "equalizerStudioFaceplate"

    func capColor(band: Int) -> NSColor { caps[band < 10 ? 0 : band < 21 ? 1 : 2] }

    /// Console: SSL / Neve / Manley mastering — engraved scales, colour-coded caps, bar metering on
    /// a dB graticule. Boutique DSP: Weiss / Dangerous / Bricasti — one accent, slim line faders, the
    /// analyser as a curve filled with heat on a fine grid. Both take the skin's ground for the panel
    /// and its current-text colour for the accent; `meter` is the skin's low, mid and high level
    /// colours, for the heat and Console's caps. Text is in the Library's content font; the strip's
    /// switches are its tabs (`tab`), the buttons SF Symbols, and the profile name is in the main
    /// window's display face.
    ///
    /// An Original skin (`originalSkin`) leaves the panel clear, so the chrome's window background —
    /// the main window's own, background image or brushed surface — shows through. An
    /// Original-Metal skin has no palette ground: its wells and lines are the material's, as the
    /// Original EQ draws them, its levels the material's spectrum colours, and its text the skin's
    /// own text colours, which the palette's — chosen against a dark ground that is not drawn — are not.
    init(_ kind: Kind, style: SkinnedSurfaceStyle, meter: [NSColor], tab: StudioTab, originalSkin: ModernSkin?) {
        let metalSkin = originalSkin?.renderStyle == .metal ? originalSkin : nil
        let metal = metalSkin?.metalMaterial
        let blend = SkinnedSurfaceStyle.blend
        let (low, mid, high) = metal.map { ($0.spectrumLow, blend($0.spectrumLow, $0.spectrumHigh, 0.5), $0.spectrumHigh) }
            ?? (meter[0], meter[1], meter[2])
        self.tab = tab
        legendFont = .systemFont(ofSize: 8)
        buttonFont = .systemFont(ofSize: 10)
        // An Original skin's wells are its main-window display panels' surface fill.
        let well = metal?.eqPanelFill ?? originalSkin?.surfaceColor ?? blend(style.background, .black, 0.4)
        self.kind = kind
        panel = originalSkin == nil ? style.background : .clear
        self.well = well
        edge = metal?.eqStroke ?? style.border

        // Metal's panel is the brushed surface; its base fill stands for it.
        let ground = metal?.backgroundBase ?? style.background
        let rawText = metalSkin?.textColor ?? style.text
        let rawDim = metalSkin?.textDimColor ?? style.dimText
        let textCandidates = [rawText, style.text, style.currentText, style.selectionText]
        func dim(_ text: NSColor, on ground: NSColor) -> NSColor {
            SkinnedSurfaceStyle.legible(preferring: [rawDim, blend(text, ground, 0.25), blend(text, ground, 0.12), text],
                                        on: ground)
        }
        let text = SkinnedSurfaceStyle.legible(preferring: textCandidates, on: ground)
        let dimText = dim(text, on: ground)
        self.text = text
        self.dimText = dimText
        let faint = blend(dimText, ground, 0.35)
        inactiveText = SkinnedSurfaceStyle.contrastRatio(faint, ground) >= 2 ? faint : dimText
        wellText = SkinnedSurfaceStyle.legible(preferring: textCandidates, on: well)
        wellDimText = dim(wellText, on: well)
        accent = SkinnedSurfaceStyle.legible(preferring: [tab.labelColor(isActive: true), text], on: ground)
        scale = metal?.eqStroke ?? style.divider
        // A track is recessed — darker than the panel — wherever that still shows; on a ground too
        // dark to go darker it is lifted toward the text instead, so it never vanishes.
        let recessed = metal?.eqControlFill ?? blend(well, .black, 0.4)
        slot = [recessed, blend(ground, text, 0.25), blend(ground, text, 0.4)].first {
            SkinnedSurfaceStyle.contrastRatio(SkinnedSurfaceStyle.composited($0, over: ground), ground) >= 1.8
        } ?? blend(ground, text, 0.55)
        peak = metal?.spectrumHigh ?? WaveformView.playheadColor(for: style)
        // The bloom composites over an opaque ground, which a clear panel is not.
        glows = kind == .boutique && style.prefersDarkAppearance && originalSkin == nil
        switch kind {
        case .console:
            caps = [low, mid, high]
            heat = [(-78, low), (-12, mid), (-3, high)]
            graticuleStep = 12
            graticuleWeight = 1
            graticule = text.withAlphaComponent(0.15)
            graticuleZero = text.withAlphaComponent(0.35)
            octaveGrid = false
            faderTicks = [12, 6, 3, 0, -3, -6, -12]
            faderTickLabels = [12, 6, 0, -6, -12]
            slotWidth = 3
            capWidth = 14
        case .boutique:
            caps = [accent, accent, accent]
            heat = [(-78, blend(well, low, 0.15)), (-48, blend(well, low, 0.5)), (-30, low), (-18, mid),
                    (-9, blend(mid, high, 0.5)), (-3, high), (0, blend(high, .white, 0.7))]
            graticuleStep = 6
            graticuleWeight = 0.5
            graticule = scale
            graticuleZero = scale
            octaveGrid = true
            faderTicks = [0]
            faderTickLabels = [12, 6, 0, -6, -12]
            slotWidth = 1
            capWidth = 10
        }
    }

    static var storedKind: Kind {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(Kind.init) ?? .console
    }
}

/// The Studio's drawing primitives: they read only the faceplate.
extension StudioFaceplate {
    func drawText(_ string: String, font: NSFont, color: NSColor, in rect: CGRect,
                  alignment: NSTextAlignment = .left) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
        let height = (string as NSString).size(withAttributes: attributes).height
        (string as NSString).draw(in: CGRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height),
                                  withAttributes: attributes)
    }

    /// A button as the Library's tab: lit is the selected tab. Its label shrinks to fit `rect`.
    func drawButton(_ title: String, in rect: CGRect, lit: Bool) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        tab.draw(title, isSelected: lit, box: rect, scale: tab.scale(fitting: title, in: rect.size), context: context)
    }

    /// The profile name as the main window's display draws its title: an Original skin's marquee —
    /// its font, capitals and colour (where legible in the well) — or the classic text sheet at twice
    /// its size, in its own colour; in a `.wal` or `.wmz` session, that style's matched face.
    func drawDisplayText(_ text: String, in rect: CGRect) {
        switch tab {
        case .original(let skin):
            let color = SkinnedSurfaceStyle.legible(preferring: [skin.applyTextOpacity(to: skin.marqueeColor), wellText], on: well)
            drawText(text.uppercased(), font: skin.primaryFont(size: 14), color: color, in: rect)
        case .classic(let renderer, let style, _):
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            let scale: CGFloat = 2
            context.saveGState()
            context.clip(to: rect)
            ClassicLibraryTab.drawSkinText(text, at: CGPoint(x: rect.minX, y: rect.midY - SkinElements.TextFont.charHeight * scale / 2),
                                           scale: scale, color: wellText, renderer: renderer, style: style, context: context)
            context.restoreGState()
        }
    }

    /// A mixing console's channel label: a dark display with the name in bold monospaced capitals,
    /// over a colour bar in the accent when `lit`, else the edge.
    func drawScribbleStrip(_ name: String, in rect: CGRect, lit: Bool) {
        let shape = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
        well.setFill()
        shape.fill()
        edge.setStroke()
        NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 2, yRadius: 2).stroke()
        (lit ? accent : edge).setFill()
        NSRect(x: rect.minX + 2, y: rect.maxY - 4, width: rect.width - 4, height: 2).fill()
        drawText(name, font: .monospacedSystemFont(ofSize: 10, weight: .bold), color: lit ? accent : wellText,
                 in: rect.insetBy(dx: 2, dy: 0).offsetBy(dx: 0, dy: -1.5), alignment: .center)
    }

    /// A toolbar button: an SF Symbol in the panel's text colour; lit sits in a well in the accent,
    /// `faint` draws it at a third.
    @MainActor
    func drawIcon(_ symbol: String, in rect: CGRect, lit: Bool, faint: Bool) {
        if lit {
            well.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
        }
        guard let context = NSGraphicsContext.current?.cgContext, let image = Self.symbol(symbol) else { return }
        let size = image.size
        let icon = CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
        // Tinted in a layer of its own: the colour lands only on the glyph, then the layer is faded.
        context.saveGState()
        context.setAlpha(faint ? 0.35 : 1)
        context.beginTransparencyLayer(in: icon, auxiliaryInfo: nil)
        image.draw(in: icon, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        (lit ? accent : text).setFill()
        icon.fill(using: .sourceAtop)
        context.endTransparencyLayer()
        context.restoreGState()
    }

    /// SF Symbols at the toolbar's size, looked up once each: the view redraws at the analyser's rate.
    @MainActor private static var symbols: [String: NSImage] = [:]

    @MainActor
    private static func symbol(_ name: String) -> NSImage? {
        if let image = symbols[name] { return image }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        symbols[name] = image
        return image
    }

    /// How far a fader has moved from 0 dB, filled along its track.
    typealias Travel = (color: NSColor, width: CGFloat)

    /// A band fader's travel: a hairline in its cap's colour on Boutique; Console's caps show it alone.
    func bandTravel(cap: NSColor) -> Travel? { kind == .boutique ? (cap.withAlphaComponent(0.35), 1) : nil }

    /// The preamp's travel on either faceplate: its track lit in the accent, as a console lights its preamp.
    var preampTravel: Travel { (accent, max(slotWidth, 3)) }

    /// A fader: its track, a notch across the track at each labelled dB step, its travel, and the cap over them.
    func drawFader(x: CGFloat, value: Float, in rect: CGRect, cap: NSColor, width: CGFloat, travel: Travel?) {
        slot.setFill()
        NSRect(x: x - slotWidth / 2, y: rect.minY + 4, width: slotWidth, height: rect.height - 8).fill()
        for tick in faderTickLabels {
            dimText.withAlphaComponent(tick == 0 ? 1 : 0.6).setFill()
            NSRect(x: x - slotWidth / 2 - 2, y: rect.y(gain: tick).rounded(), width: slotWidth + 4, height: 1).fill()
        }
        let y = rect.y(gain: value)
        if let travel {
            let zero = rect.y(gain: 0)
            travel.color.setFill()
            NSRect(x: x - travel.width / 2, y: min(y, zero), width: travel.width, height: abs(y - zero)).fill()
        }
        switch kind {
        case .console:
            let capRect = CGRect(x: x - width / 2, y: y - 4.5, width: width, height: 9)
            NSColor.black.withAlphaComponent(0.4).setFill()
            capRect.offsetBy(dx: 0, dy: 1).fill()
            cap.setFill()
            NSBezierPath(roundedRect: capRect, xRadius: 1.5, yRadius: 1.5).fill()
            NSColor.white.withAlphaComponent(0.45).setFill()
            NSRect(x: capRect.minX + 1, y: capRect.minY + 1, width: capRect.width - 2, height: 1).fill()
            NSColor.black.withAlphaComponent(0.55).setFill()
            NSRect(x: capRect.minX + 1, y: capRect.midY - 0.5, width: capRect.width - 2, height: 1).fill()
        case .boutique:
            cap.setFill()
            NSRect(x: x - width / 2, y: y - 1, width: width, height: 2).fill()
        }
    }

    /// A dB scale label: signed, but a bare 0.
    static func dbLabel(_ db: Float) -> String {
        String(format: "%+.0f", db).replacingOccurrences(of: "+0", with: "0")
    }
}

/// The Studio's ±12 dB scale — faders, the preamp, the response curves — inset 6 points at each end.
extension CGRect {
    func y(gain: Float) -> CGFloat {
        minY + 6 + CGFloat((12 - gain) / 24) * (height - 12)
    }

    /// To 0.1 dB, clamped.
    func gain(y: CGFloat) -> Float {
        let g = 12 - Float((y - minY - 6) / (height - 12)) * 24
        return EQCurve.clamp((g * 10).rounded() / 10)
    }
}

/// The Library's tab in the running family — the Studio's buttons are drawn as it, by the same
/// code (`ModernLibraryTab`, `ClassicLibraryTab`), so the two windows' tabs are identical.
enum StudioTab {
    case original(ModernSkin)
    case classic(renderer: SkinRenderer, style: SkinnedSurfaceStyle?, colors: PlaylistColors)

    /// The classic tab's text scale at 1: the Library's `bitmapTextScale` at normal size.
    private static let classicTextScale: CGFloat = 1.5

    /// The label's size at `scale` 1.
    private func naturalSize(_ label: String) -> CGSize {
        switch self {
        case .original(let skin):
            return label.size(withAttributes: [.font: ModernLibraryTab.font(skin: skin)])
        case .classic:
            return CGSize(width: CGFloat(label.count) * SkinElements.TextFont.charWidth * Self.classicTextScale,
                          height: SkinElements.TextFont.charHeight * Self.classicTextScale)
        }
    }

    /// The largest scale, up to 1, at which `label` fits a box of `size` — the Library's own
    /// narrow-window shrink, applied per box.
    func scale(fitting label: String, in size: CGSize) -> CGFloat {
        let natural = naturalSize(label)
        guard natural.width > 0, natural.height > 0 else { return 1 }
        return min(1, (size.width - 8) / natural.width, (size.height - 2) / natural.height)
    }

    /// The colour the tab's label is drawn in, lit or not.
    func labelColor(isActive: Bool) -> NSColor {
        switch self {
        case .original(let skin):
            return skin.applyTextOpacity(to: ModernLibraryTab.labelColor(isActive: isActive, skin: skin))
        case .classic(let renderer, let style, _):
            return ClassicLibraryTab.labelColor(isSelected: isActive, renderer: renderer, style: style)
        }
    }

    /// `box` is the drawn box; the Library insets it from a tab slot, which is undone here.
    func draw(_ label: String, isSelected: Bool, box: CGRect, scale: CGFloat, context: CGContext) {
        switch self {
        case .original(let skin):
            ModernLibraryTab.draw(label, isActive: isSelected, rect: box,
                                  font: ModernLibraryTab.font(skin: skin, scale: scale), skin: skin, context: context)
        case .classic(let renderer, let style, let colors):
            ClassicLibraryTab.draw(label, isSelected: isSelected, in: box.insetBy(dx: -3 * scale, dy: -3),
                                   boxInsetX: 3 * scale, textScale: Self.classicTextScale * scale,
                                   colors: colors, renderer: renderer, style: style, context: context)
        }
    }
}
