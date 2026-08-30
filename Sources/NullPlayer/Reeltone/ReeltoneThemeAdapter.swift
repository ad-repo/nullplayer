import AppKit

struct ReeltoneThemePalette: Equatable, Sendable {
    let screen: String
    let ink: String
    let inkDim: String
    let panel: String
    let panelText: String
}

/// Adapts a Reeltone v1 deck palette to the content-only Original presentation used by Phase 3.
/// The resulting skin is transient: it is never installed in the Original skin namespace and
/// never writes the user's `modernSkinName` preference.
struct ReeltoneThemeAdapter {
    static let defaultPalette = ReeltoneThemePalette(
        screen: "#071418",
        ink: "#63F5C8",
        inkDim: "#378A73",
        panel: "#10272B",
        panelText: "#E7FFF7"
    )

    let name: String
    let palette: ReeltoneThemePalette
    let presentationSkin: ModernSkin

    init(manifest: ReeltoneManifest?) {
        let fallback = Self.defaultPalette
        let colors = manifest?.colors
        palette = ReeltoneThemePalette(
            screen: Self.normalizedRGB(colors?.screen, fallback: fallback.screen),
            ink: Self.normalizedRGB(colors?.ink, fallback: fallback.ink),
            inkDim: Self.normalizedRGB(colors?.inkDim, fallback: fallback.inkDim),
            panel: Self.normalizedRGB(colors?.panel, fallback: fallback.panel),
            panelText: Self.normalizedRGB(colors?.panelText, fallback: fallback.panelText)
        )
        name = manifest?.name ?? "Default Reeltone"

        let config = ModernSkinConfig(
            meta: SkinMeta(
                name: "Reeltone — \(name)",
                author: manifest?.author ?? "NullPlayer",
                version: manifest?.version ?? "1",
                description: "Reeltone v1 Original-content theme adapter"
            ),
            palette: ColorPalette(
                primary: palette.ink,
                secondary: palette.panelText,
                accent: palette.ink,
                highlight: palette.panelText,
                background: palette.screen,
                surface: palette.panel,
                text: palette.panelText,
                textDim: palette.inkDim,
                positive: palette.ink,
                negative: nil,
                warning: nil,
                border: palette.ink,
                timeColor: palette.ink,
                marqueeColor: palette.ink,
                dataColor: palette.panelText,
                eqLow: palette.inkDim,
                eqMid: palette.ink,
                eqHigh: palette.panelText
            ),
            fonts: FontConfig(
                primaryName: "System",
                fallbackName: nil,
                titleSize: nil,
                bodySize: nil,
                smallSize: nil,
                timeSize: nil,
                infoSize: nil,
                eqLabelSize: nil,
                eqValueSize: nil,
                marqueeSize: nil,
                playlistSize: nil
            ),
            background: BackgroundConfig(image: nil, grid: nil),
            glow: GlowConfig(
                enabled: false,
                radius: nil,
                intensity: nil,
                threshold: nil,
                color: palette.ink,
                elementBlur: nil
            ),
            window: WindowConfig(
                borderWidth: 1,
                borderColor: palette.ink,
                cornerRadius: 6,
                scale: 1.25,
                opacity: 1,
                textOpacity: 1,
                mainSpectrumOpacity: 1,
                spectrumTransparentBackground: false,
                waveformWindowOpacity: 1,
                seamlessDocking: 1,
                areaOpacity: nil
            ),
            visualization: nil,
            waveform: nil,
            marquee: nil,
            titleText: nil,
            elements: nil,
            animations: nil
        )
        presentationSkin = ModernSkin(config: config, bundlePath: nil)
    }

    private static func normalizedRGB(_ candidate: String?, fallback: String) -> String {
        guard var value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.hasPrefix("#") else { return fallback }
        value.removeFirst()
        guard value.count == 6 || value.count == 8,
              value.allSatisfy({ $0.isHexDigit }) else { return fallback }
        // Reeltone accepts #RRGGBBAA. Original's palette is RGB-only, so retain the authored
        // color channels and let the Original window opacity model remain coherent.
        return "#" + String(value.prefix(6)).uppercased()
    }
}
