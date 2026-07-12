import CoreGraphics
import Foundation

enum VisualizationPreferenceResetScope: Equatable {
    case mainWindow
    case spectrumWindow
    case visualizationWindow
    case browserArtwork
    case all
}

enum VisualizationPreferences {
    static func reset(
        _ scope: VisualizationPreferenceResetScope,
        defaults: UserDefaults = .standard,
        applySkinDefaults: Bool = true,
        postNotifications: Bool = true
    ) {
        for key in keys(for: scope) {
            defaults.removeObject(forKey: key)
        }

        if applySkinDefaults {
            applyCurrentSkinDefaults(for: scope, defaults: defaults)
        }

        if postNotifications {
            postResetNotifications(for: scope)
        }
    }

    static func keys(for scope: VisualizationPreferenceResetScope) -> [String] {
        switch scope {
        case .mainWindow:
            return mainWindowKeys
        case .spectrumWindow:
            return spectrumWindowKeys
        case .visualizationWindow:
            return visualizationWindowKeys
        case .browserArtwork:
            return browserArtworkKeys
        case .all:
            return Array(Set(mainWindowKeys + spectrumWindowKeys + visualizationWindowKeys + browserArtworkKeys))
        }
    }

    private static let legacyVisClassicKeys = [
        "visClassicLastProfileName",
        "visClassicFitToWidth"
    ]

    private static let mainWindowKeys = [
        "mainWindowVisMode",
        "modernMainWindowVisMode",
        "mainWindowNormalizationMode",
        "mainWindowDecayMode",
        "mainWindowFlameStyle",
        "mainWindowFlameIntensity",
        "mainWindowLightningStyle",
        "mainWindowMatrixColorScheme",
        "mainWindowMatrixIntensity",
        "mainWindowEKGStyle",
        VisClassicBridge.PreferenceScope.mainWindow.lastProfileNameKey,
        VisClassicBridge.PreferenceScope.mainWindow.fitToWidthKey,
        VisClassicBridge.PreferenceScope.mainWindow.transparentBgKey,
        VisClassicBridge.PreferenceScope.mainWindow.opacityKey
    ] + legacyVisClassicKeys

    private static let spectrumWindowKeys = [
        "spectrumQualityMode",
        "spectrumNormalizationMode",
        "spectrumDecayMode",
        "decayMode",
        "flameStyle",
        "flameIntensity",
        "lightningStyle",
        "matrixColorScheme",
        "matrixIntensity",
        "ekgStyle",
        VisClassicBridge.PreferenceScope.spectrumWindow.lastProfileNameKey,
        VisClassicBridge.PreferenceScope.spectrumWindow.fitToWidthKey,
        VisClassicBridge.PreferenceScope.spectrumWindow.transparentBgKey,
        VisClassicBridge.PreferenceScope.spectrumWindow.opacityKey
    ] + legacyVisClassicKeys

    private static var visualizationWindowKeys: [String] {
        var keys = [
            "visualizationEngineType",
            "projectM.cycleMode",
            "projectM.cycleInterval",
            "projectMDefaultPresetPath",
            "projectMDefaultPresetName",
            TripexEngine.DefaultsKey.lastEffectIndex,
            TripexEngine.DefaultsKey.lockedEffectIndex,
            TripexEngine.DefaultsKey.intensityScale,
            TripexEngine.DefaultsKey.cycleMode,
            TripexEngine.DefaultsKey.cycleInterval,
            MetMuseumEngine.DefaultsKey.departmentID,
            MetMuseumEngine.DefaultsKey.intervalSeconds,
            MetMuseumEngine.DefaultsKey.transitionMode,
            MetMuseumEngine.DefaultsKey.transitionDuration,
            MetMuseumEngine.DefaultsKey.audioReactive,
            MetMuseumEngine.DefaultsKey.beatTriggered,
            MetMuseumEngine.DefaultsKey.aspectMode,
            MetMuseumEngine.DefaultsKey.showAttribution,
            "geiss.sensitivity",
            "geiss.gamma",
            "geiss.beatDetection",
            "geiss.syncColorToSound",
            "geiss.slideShift",
            "geiss.modeLocked",
            "geiss.paletteLocked",
            "geiss.autoSwitchSeconds",
            "geiss.visMode",
            "viz.legacyMigrationV1",
            "projectMPCMGain",
            "projectMLowPowerMode",
            "projectMBeatSensitivity"
        ]

        for type in VisualizationType.allCases {
            keys.append("viz.\(type.rawValue).pcmGain")
            keys.append("viz.\(type.rawValue).lowPowerMode")
            keys.append("viz.\(type.rawValue).beatSensitivity")
        }

        return keys
    }

    private static let browserArtworkKeys = [
        "browserVisDefaultEffect",
        "browserVisEffect",
        "browserVisIntensity"
    ]

    private static func applyCurrentSkinDefaults(
        for scope: VisualizationPreferenceResetScope,
        defaults: UserDefaults
    ) {
        guard scope == .mainWindow || scope == .spectrumWindow || scope == .all else { return }

        let skin = ModernSkinEngine.shared.currentSkin
        let config = skin?.config.visualization
        let windowSpectrumTransparentBackground = skin?.config.window.spectrumTransparentBackground

        if scope == .mainWindow || scope == .all {
            applyMainWindowDefaults(from: config, defaults: defaults)
        }
        if scope == .spectrumWindow || scope == .all {
            applySpectrumWindowDefaults(
                from: config,
                windowSpectrumTransparentBackground: windowSpectrumTransparentBackground,
                defaults: defaults
            )
        }
    }

    private static func applyMainWindowDefaults(
        from config: VisualizationConfig?,
        defaults: UserDefaults
    ) {
        var appliedMode = false

        if let raw = config?.mainWindowMode,
           let mode = MainWindowVisMode(rawValue: raw),
           mode.spectrumQualityMode.map(SpectrumAnalyzerView.isShaderAvailable(for:)) ?? true {
            defaults.set(mode.rawValue, forKey: "mainWindowVisMode")
            defaults.set(mode.rawValue, forKey: "modernMainWindowVisMode")
            appliedMode = true
        }

        if !appliedMode {
            defaults.set(MainWindowVisMode.spectrum.rawValue, forKey: "mainWindowVisMode")
            defaults.set(MainWindowVisMode.spectrum.rawValue, forKey: "modernMainWindowVisMode")
        }

        if let visClassic = config?.visClassic {
            set(visClassic.mainWindowProfile, forKey: VisClassicBridge.PreferenceScope.mainWindow.lastProfileNameKey, defaults: defaults)
            set(visClassic.mainWindowFitToWidth, forKey: VisClassicBridge.PreferenceScope.mainWindow.fitToWidthKey, defaults: defaults)
            set(visClassic.mainWindowTransparentBackground, forKey: VisClassicBridge.PreferenceScope.mainWindow.transparentBgKey, defaults: defaults)
            setClampedOpacity(visClassic.mainWindowOpacity, forKey: VisClassicBridge.PreferenceScope.mainWindow.opacityKey, defaults: defaults)
        }

        if let fire = config?.fire {
            setRaw(fire.mainWindowStyle, as: FlameStyle.self, forKey: "mainWindowFlameStyle", defaults: defaults)
            setRaw(fire.mainWindowIntensity, as: FlameIntensity.self, forKey: "mainWindowFlameIntensity", defaults: defaults)
        }
        if let lightning = config?.lightning {
            setRaw(lightning.mainWindowStyle, as: LightningStyle.self, forKey: "mainWindowLightningStyle", defaults: defaults)
        }
        if let matrix = config?.matrix {
            setRaw(matrix.mainWindowColorScheme, as: MatrixColorScheme.self, forKey: "mainWindowMatrixColorScheme", defaults: defaults)
            setRaw(matrix.mainWindowIntensity, as: MatrixIntensity.self, forKey: "mainWindowMatrixIntensity", defaults: defaults)
        }
    }

    private static func applySpectrumWindowDefaults(
        from config: VisualizationConfig?,
        windowSpectrumTransparentBackground: Bool?,
        defaults: UserDefaults
    ) {
        if let raw = config?.spectrumWindowMode,
           let mode = SpectrumQualityMode(rawValue: raw),
           SpectrumAnalyzerView.isShaderAvailable(for: mode) {
            defaults.set(mode.rawValue, forKey: "spectrumQualityMode")
        } else {
            defaults.set(SpectrumQualityMode.classic.rawValue, forKey: "spectrumQualityMode")
        }

        if let transparent = windowSpectrumTransparentBackground {
            defaults.set(transparent, forKey: VisClassicBridge.PreferenceScope.spectrumWindow.transparentBgKey)
        }

        if let visClassic = config?.visClassic {
            set(visClassic.spectrumWindowProfile, forKey: VisClassicBridge.PreferenceScope.spectrumWindow.lastProfileNameKey, defaults: defaults)
            set(visClassic.spectrumWindowFitToWidth, forKey: VisClassicBridge.PreferenceScope.spectrumWindow.fitToWidthKey, defaults: defaults)
            set(visClassic.spectrumWindowTransparentBackground, forKey: VisClassicBridge.PreferenceScope.spectrumWindow.transparentBgKey, defaults: defaults)
            setClampedOpacity(visClassic.spectrumWindowOpacity, forKey: VisClassicBridge.PreferenceScope.spectrumWindow.opacityKey, defaults: defaults)
        }

        if let fire = config?.fire {
            setRaw(fire.spectrumWindowStyle, as: FlameStyle.self, forKey: "flameStyle", defaults: defaults)
            setRaw(fire.spectrumWindowIntensity, as: FlameIntensity.self, forKey: "flameIntensity", defaults: defaults)
        }
        if let lightning = config?.lightning {
            setRaw(lightning.spectrumWindowStyle, as: LightningStyle.self, forKey: "lightningStyle", defaults: defaults)
        }
        if let matrix = config?.matrix {
            setRaw(matrix.spectrumWindowColorScheme, as: MatrixColorScheme.self, forKey: "matrixColorScheme", defaults: defaults)
            setRaw(matrix.spectrumWindowIntensity, as: MatrixIntensity.self, forKey: "matrixIntensity", defaults: defaults)
        }
    }

    private static func postResetNotifications(for scope: VisualizationPreferenceResetScope) {
        if scope == .mainWindow || scope == .all {
            NotificationCenter.default.post(name: NSNotification.Name("MainWindowVisChanged"), object: nil)
            postVisClassicOptionRefresh(for: .mainWindow)
        }
        if scope == .spectrumWindow || scope == .all {
            NotificationCenter.default.post(name: NSNotification.Name("SpectrumSettingsChanged"), object: nil)
            postVisClassicOptionRefresh(for: .spectrumWindow)
        }
        if scope == .visualizationWindow || scope == .all {
            WindowManager.shared.switchVisualizationEngine(to: .projectM)
        }
    }

    private static func postVisClassicOptionRefresh(for scope: VisClassicBridge.PreferenceScope) {
        if let profile = VisClassicBridge.lastProfileName(for: scope) {
            NotificationCenter.default.post(
                name: .visClassicProfileCommand,
                object: nil,
                userInfo: ["command": "load", "profileName": profile, "target": targetName(for: scope)]
            )
        }
        NotificationCenter.default.post(
            name: .visClassicProfileCommand,
            object: nil,
            userInfo: ["command": "fitToWidth", "enabled": VisClassicBridge.fitToWidthDefault(for: scope), "target": targetName(for: scope)]
        )
        NotificationCenter.default.post(
            name: .visClassicProfileCommand,
            object: nil,
            userInfo: ["command": "transparentBg", "enabled": VisClassicBridge.transparentBgDefault(for: scope), "target": targetName(for: scope)]
        )
    }

    private static func targetName(for scope: VisClassicBridge.PreferenceScope) -> String {
        switch scope {
        case .mainWindow: return "mainWindow"
        case .spectrumWindow: return "spectrumWindow"
        }
    }

    private static func set(_ value: String?, forKey key: String, defaults: UserDefaults) {
        guard let value else { return }
        defaults.set(value, forKey: key)
    }

    private static func set(_ value: Bool?, forKey key: String, defaults: UserDefaults) {
        guard let value else { return }
        defaults.set(value, forKey: key)
    }

    private static func setClampedOpacity(_ value: CGFloat?, forKey key: String, defaults: UserDefaults) {
        guard let value else { return }
        defaults.set(max(0.0, min(1.0, Double(value))), forKey: key)
    }

    private static func setRaw<T: RawRepresentable>(
        _ rawValue: String?,
        as type: T.Type,
        forKey key: String,
        defaults: UserDefaults
    ) where T.RawValue == String {
        guard let rawValue, let value = T(rawValue: rawValue) else { return }
        defaults.set(value.rawValue, forKey: key)
    }
}
