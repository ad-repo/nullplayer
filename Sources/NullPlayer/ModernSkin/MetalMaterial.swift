import AppKit

/// A physically-styled metal finish for the `.metal` render style.
///
/// The metal appearance is intentionally code-driven (not palette-driven): the same set of
/// surfaces — window sheen, panels, sliders, transport icons, EQ — is drawn for every metal skin,
/// and this struct supplies the per-finish colors. Built-in metal skins each pick a preset; user
/// metal skins (and any non-metal skin) fall back to `.brushedSteel`.
///
/// Text contrast note: on-chrome text (EQ labels/buttons, playlist/library rows, window controls)
/// reads from the skin *palette* (`text`/`textDim`/`dataColor`), which each finish tunes light or
/// dark. The only text drawn on the green LCD panels that would otherwise follow the palette — the
/// main-window info labels and the EQ curve line — is redirected to `lcdInk` so it stays dark on
/// the light display regardless of finish.
struct MetalMaterial {

    struct GradientStop {
        let location: CGFloat
        let color: NSColor
    }

    // Window background
    let backgroundBase: NSColor            // opaque base fill drawn before the sheen
    let backgroundStops: [GradientStop]    // vertical sheen, top (maxY) -> bottom (minY)
    let brushHighlightStrong: CGFloat      // even brushed-stripe alpha (white)
    let brushHighlightFaint: CGFloat       // odd brushed-stripe alpha (white)
    let accentStrip: NSColor               // top catch-light strip (its alpha is scaled by opacity)

    // Window border
    let borderDark: NSColor                // outer stroke
    let borderLight: NSColor               // inner stroke

    // Title bar
    let titleBarStops: [GradientStop]      // gradient top -> bottom (alpha baked in)
    let titleBarHighlight: NSColor         // top highlight line
    let separator: NSColor                 // title bar bottom separator

    // Panels
    let insetFill: NSColor
    let insetBorder: NSColor
    let displayFill: NSColor               // backlit LCD (the green hi-fi display)
    let lcdInk: NSColor                    // dark text/curve drawn on the LCD display

    // Sliders (seek / volume)
    let sliderTrack: NSColor
    let sliderFill: NSColor
    let sliderThumb: NSColor

    // Transport icons
    let transportButton: NSColor
    let transportButtonPressed: NSColor

    // EQ window
    let eqPanelFill: NSColor
    let eqControlFill: NSColor
    let eqActiveFill: NSColor
    let eqStroke: NSColor
    let faderLow: NSColor                  // -12 dB (cut)
    let faderMid: NSColor                  // 0 dB
    let faderHigh: NSColor                 // +12 dB (boost)

    // Spectrum analyzer (main + dedicated spectrum window). Per-finish so the bars read
    // against each chrome — the chrome `accentColor` is a dark metal tone that would
    // otherwise render the bars near-black. Ramp runs low amplitude -> high amplitude.
    let spectrumLow: NSColor               // bar base (quiet)
    let spectrumHigh: NSColor              // bar peak (loud)
}

private func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1.0) -> NSColor {
    NSColor(calibratedRed: r, green: g, blue: b, alpha: a)
}

private func white(_ w: CGFloat, _ a: CGFloat = 1.0) -> NSColor {
    NSColor(calibratedWhite: w, alpha: a)
}

extension MetalMaterial {

    /// Shared backlit-green LCD used by all finishes (matches the main-window display).
    fileprivate static let lcdGreen = rgb(0.64, 0.80, 0.58)
    fileprivate static let lcdInkDark = rgb(0.05, 0.09, 0.05)

    // MARK: Brushed Steel (baseline — exact pre-material values)

    static let brushedSteel = MetalMaterial(
        backgroundBase: white(0.73),
        backgroundStops: [
            .init(location: 0.0,  color: white(0.93)),
            .init(location: 0.08, color: white(0.73)),
            .init(location: 0.32, color: white(0.86)),
            .init(location: 0.58, color: white(0.66)),
            .init(location: 0.78, color: white(0.78)),
            .init(location: 1.0,  color: white(0.54)),
        ],
        brushHighlightStrong: 0.14,
        brushHighlightFaint: 0.07,
        accentStrip: rgb(0.86, 0.90, 0.91, 0.18),
        borderDark: white(0.0, 0.62),
        borderLight: white(1.0, 0.38),
        titleBarStops: [
            .init(location: 0.0,  color: white(0.98, 0.40)),
            .init(location: 0.48, color: white(0.78, 0.18)),
            .init(location: 1.0,  color: white(0.47, 0.16)),
        ],
        titleBarHighlight: white(1.0, 0.34),
        separator: white(0.0, 0.34),
        insetFill: rgb(0.44, 0.49, 0.52),
        insetBorder: rgb(0.22, 0.25, 0.27),
        displayFill: lcdGreen,
        lcdInk: lcdInkDark,
        sliderTrack: rgb(0.50, 0.56, 0.59),
        sliderFill: rgb(0.70, 0.76, 0.78),
        sliderThumb: rgb(0.18, 0.21, 0.23),
        transportButton: rgb(0.14, 0.17, 0.19),
        transportButtonPressed: rgb(0.20, 0.23, 0.25),
        eqPanelFill: rgb(0.44, 0.49, 0.52),
        eqControlFill: rgb(0.70, 0.75, 0.77, 0.30),
        eqActiveFill: rgb(0.78, 0.82, 0.84, 0.38),
        eqStroke: rgb(0.24, 0.27, 0.29, 0.58),
        faderLow: rgb(0.17, 0.20, 0.21),
        faderMid: rgb(0.42, 0.46, 0.48),
        faderHigh: rgb(0.90, 0.92, 0.94),
        spectrumLow: rgb(0.10, 0.34, 0.42),
        spectrumHigh: rgb(0.66, 0.93, 1.0)
    )

    // MARK: Aluminum (bright polished/shiny silver faceplate)

    static let aluminum = MetalMaterial(
        backgroundBase: white(0.80),
        backgroundStops: [
            .init(location: 0.0,  color: white(0.99)),
            .init(location: 0.08, color: white(0.80)),
            .init(location: 0.32, color: white(0.93)),
            .init(location: 0.58, color: white(0.72)),
            .init(location: 0.78, color: white(0.86)),
            .init(location: 1.0,  color: white(0.62)),
        ],
        brushHighlightStrong: 0.18,
        brushHighlightFaint: 0.09,
        accentStrip: rgb(0.92, 0.95, 0.97, 0.22),
        borderDark: white(0.0, 0.58),
        borderLight: white(1.0, 0.45),
        titleBarStops: [
            .init(location: 0.0,  color: white(1.0, 0.45)),
            .init(location: 0.48, color: white(0.85, 0.20)),
            .init(location: 1.0,  color: white(0.55, 0.16)),
        ],
        titleBarHighlight: white(1.0, 0.40),
        separator: white(0.0, 0.30),
        insetFill: rgb(0.52, 0.56, 0.60),
        insetBorder: rgb(0.28, 0.31, 0.34),
        displayFill: lcdGreen,
        lcdInk: lcdInkDark,
        sliderTrack: rgb(0.58, 0.62, 0.66),
        sliderFill: rgb(0.80, 0.84, 0.87),
        sliderThumb: rgb(0.22, 0.25, 0.28),
        transportButton: rgb(0.16, 0.19, 0.22),
        transportButtonPressed: rgb(0.24, 0.27, 0.30),
        eqPanelFill: rgb(0.52, 0.56, 0.60),
        eqControlFill: rgb(0.78, 0.82, 0.85, 0.30),
        eqActiveFill: rgb(0.86, 0.89, 0.92, 0.38),
        eqStroke: rgb(0.28, 0.31, 0.34, 0.58),
        faderLow: rgb(0.20, 0.23, 0.25),
        faderMid: rgb(0.48, 0.52, 0.55),
        faderHigh: rgb(0.94, 0.96, 0.98),
        spectrumLow: rgb(0.30, 0.34, 0.38),
        spectrumHigh: rgb(0.92, 0.96, 1.0)
    )

    // MARK: Gunmetal (dark blue-gray satin)

    static let gunmetal = MetalMaterial(
        backgroundBase: rgb(0.26, 0.29, 0.33),
        backgroundStops: [
            .init(location: 0.0,  color: rgb(0.40, 0.44, 0.49)),
            .init(location: 0.10, color: rgb(0.30, 0.34, 0.39)),
            .init(location: 0.34, color: rgb(0.35, 0.39, 0.44)),
            .init(location: 0.58, color: rgb(0.26, 0.29, 0.34)),
            .init(location: 0.80, color: rgb(0.31, 0.35, 0.40)),
            .init(location: 1.0,  color: rgb(0.21, 0.24, 0.28)),
        ],
        brushHighlightStrong: 0.10,
        brushHighlightFaint: 0.05,
        accentStrip: rgb(0.62, 0.70, 0.80, 0.16),
        borderDark: white(0.0, 0.70),
        borderLight: white(1.0, 0.22),
        titleBarStops: [
            .init(location: 0.0,  color: rgb(0.46, 0.50, 0.56, 0.45)),
            .init(location: 0.48, color: rgb(0.30, 0.34, 0.39, 0.22)),
            .init(location: 1.0,  color: rgb(0.20, 0.23, 0.27, 0.20)),
        ],
        titleBarHighlight: white(1.0, 0.20),
        separator: white(0.0, 0.45),
        insetFill: rgb(0.20, 0.23, 0.27),
        insetBorder: rgb(0.11, 0.13, 0.15),
        displayFill: lcdGreen,
        lcdInk: lcdInkDark,
        sliderTrack: rgb(0.24, 0.27, 0.31),
        sliderFill: rgb(0.52, 0.58, 0.64),
        sliderThumb: rgb(0.80, 0.86, 0.92),
        transportButton: rgb(0.84, 0.88, 0.92),
        transportButtonPressed: rgb(0.60, 0.65, 0.70),
        eqPanelFill: rgb(0.20, 0.23, 0.27),
        eqControlFill: rgb(0.55, 0.60, 0.66, 0.30),
        eqActiveFill: rgb(0.62, 0.68, 0.74, 0.38),
        eqStroke: rgb(0.60, 0.67, 0.75, 0.50),
        faderLow: rgb(0.30, 0.34, 0.39),
        faderMid: rgb(0.54, 0.59, 0.65),
        faderHigh: rgb(0.86, 0.90, 0.96),
        // Light neutral silver-blue so the bar floor stays visible on the dark satin chrome.
        spectrumLow: rgb(0.55, 0.60, 0.66),
        spectrumHigh: rgb(0.92, 0.96, 1.0)
    )

    // MARK: Anodized Black (near-matte charcoal)

    static let anodizedBlack = MetalMaterial(
        backgroundBase: rgb(0.13, 0.13, 0.14),
        backgroundStops: [
            .init(location: 0.0,  color: rgb(0.185, 0.185, 0.195)),
            .init(location: 0.12, color: rgb(0.140, 0.140, 0.150)),
            .init(location: 0.50, color: rgb(0.155, 0.155, 0.165)),
            .init(location: 0.85, color: rgb(0.135, 0.135, 0.145)),
            .init(location: 1.0,  color: rgb(0.110, 0.110, 0.120)),
        ],
        brushHighlightStrong: 0.05,
        brushHighlightFaint: 0.025,
        accentStrip: rgb(0.50, 0.51, 0.53, 0.10),
        borderDark: white(0.0, 0.80),
        borderLight: white(1.0, 0.13),
        titleBarStops: [
            .init(location: 0.0,  color: rgb(0.22, 0.22, 0.24, 0.40)),
            .init(location: 0.50, color: rgb(0.15, 0.15, 0.16, 0.20)),
            .init(location: 1.0,  color: rgb(0.10, 0.10, 0.11, 0.20)),
        ],
        titleBarHighlight: white(1.0, 0.12),
        separator: white(0.0, 0.55),
        insetFill: rgb(0.10, 0.10, 0.11),
        insetBorder: rgb(0.05, 0.05, 0.06),
        displayFill: lcdGreen,
        lcdInk: lcdInkDark,
        sliderTrack: rgb(0.14, 0.14, 0.15),
        sliderFill: rgb(0.42, 0.43, 0.45),
        sliderThumb: rgb(0.74, 0.76, 0.78),
        transportButton: rgb(0.80, 0.81, 0.83),
        transportButtonPressed: rgb(0.55, 0.56, 0.58),
        eqPanelFill: rgb(0.10, 0.10, 0.11),
        eqControlFill: rgb(0.45, 0.46, 0.48, 0.30),
        eqActiveFill: rgb(0.55, 0.56, 0.58, 0.38),
        eqStroke: rgb(0.52, 0.54, 0.56, 0.50),
        faderLow: rgb(0.22, 0.22, 0.24),
        faderMid: rgb(0.45, 0.46, 0.48),
        faderHigh: rgb(0.82, 0.84, 0.86),
        // Light neutral silver so the bar floor stays visible on the near-black chrome.
        spectrumLow: rgb(0.55, 0.57, 0.60),
        spectrumHigh: rgb(0.95, 0.97, 1.0)
    )

    // MARK: Champagne (warm silver-gold vintage receiver faceplate)

    static let champagne = MetalMaterial(
        backgroundBase: rgb(0.80, 0.75, 0.64),
        backgroundStops: [
            .init(location: 0.0,  color: rgb(0.93, 0.89, 0.79)),
            .init(location: 0.08, color: rgb(0.82, 0.77, 0.66)),
            .init(location: 0.32, color: rgb(0.88, 0.83, 0.72)),
            .init(location: 0.58, color: rgb(0.76, 0.71, 0.60)),
            .init(location: 0.78, color: rgb(0.84, 0.79, 0.68)),
            .init(location: 1.0,  color: rgb(0.70, 0.65, 0.54)),
        ],
        brushHighlightStrong: 0.13,
        brushHighlightFaint: 0.06,
        accentStrip: rgb(0.96, 0.92, 0.81, 0.20),
        borderDark: rgb(0.30, 0.25, 0.16, 0.60),
        borderLight: rgb(1.0, 0.97, 0.88, 0.40),
        titleBarStops: [
            .init(location: 0.0,  color: rgb(0.98, 0.95, 0.86, 0.42)),
            .init(location: 0.48, color: rgb(0.84, 0.79, 0.68, 0.20)),
            .init(location: 1.0,  color: rgb(0.62, 0.57, 0.46, 0.18)),
        ],
        titleBarHighlight: rgb(1.0, 0.98, 0.90, 0.34),
        separator: rgb(0.32, 0.27, 0.18, 0.34),
        insetFill: rgb(0.52, 0.47, 0.37),
        insetBorder: rgb(0.30, 0.26, 0.18),
        displayFill: lcdGreen,
        lcdInk: lcdInkDark,
        sliderTrack: rgb(0.58, 0.53, 0.43),
        sliderFill: rgb(0.80, 0.74, 0.62),
        sliderThumb: rgb(0.30, 0.26, 0.18),
        transportButton: rgb(0.22, 0.18, 0.10),
        transportButtonPressed: rgb(0.34, 0.29, 0.18),
        eqPanelFill: rgb(0.52, 0.47, 0.37),
        eqControlFill: rgb(0.78, 0.72, 0.60, 0.30),
        eqActiveFill: rgb(0.86, 0.80, 0.68, 0.38),
        eqStroke: rgb(0.34, 0.29, 0.20, 0.55),
        faderLow: rgb(0.34, 0.30, 0.22),
        faderMid: rgb(0.55, 0.50, 0.40),
        faderHigh: rgb(0.96, 0.92, 0.82),
        spectrumLow: rgb(0.40, 0.24, 0.06),
        spectrumHigh: rgb(1.0, 0.86, 0.46)
    )
}
