import AppKit

/// Central coordinator for the modern skin system.
/// Manages skin lifecycle: loading, selection, caching, and providing the active skin.
///
/// This is a singleton that is completely independent of `WindowManager.shared.currentSkin`
/// (which manages classic skins). They coexist without conflict.
class ModernSkinEngine {
    
    // MARK: - Singleton
    
    static let shared = ModernSkinEngine()
    
    // MARK: - Properties
    
    /// The currently active modern skin
    private(set) var currentSkin: ModernSkin?
    
    /// Name of the currently loaded skin
    private(set) var currentSkinName: String?
    
    /// The skin loader
    let loader = ModernSkinLoader.shared
    
    /// The animation engine
    let animationEngine = ModernSkinAnimation()
    
    /// The bloom post-processor
    let bloomProcessor = BloomPostProcessor()
    
    /// UserDefaults key for the selected skin name
    private let skinNameKey = "modernSkinName"
    
    /// Notification posted when the modern skin changes
    static let skinDidChangeNotification = Notification.Name("ModernSkinDidChange")
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Skin Lifecycle
    
    /// Load the preferred skin (from UserDefaults) or the default
    func loadPreferredSkin() {
        if let name = UserDefaults.standard.string(forKey: skinNameKey) {
            if loadSkin(named: name) { return }
        }
        loadDefaultSkin()
    }
    
    /// Load the default bundled skin (NeonWave)
    func loadDefaultSkin() {
        currentSkin = loader.loadDefault()
        currentSkinName = currentSkin?.config.meta.name ?? "NeonWave"
        configureSkinDependencies()
        notifySkinChanged()
        NSLog("ModernSkinEngine: Loaded default skin")
    }
    
    /// Load a skin by name (searches bundled and user skins)
    @discardableResult
    func loadSkin(named name: String) -> Bool {
        let available = loader.availableSkins()
        let resolvedName = resolvedSkinName(for: name)

        guard let skinInfo = available.first(where: { $0.name == name })
                          ?? available.first(where: { $0.name == resolvedName }) else {
            NSLog("ModernSkinEngine: Skin '%@' not found", name)
            return false
        }

        do {
            let ext = skinInfo.path.pathExtension.lowercased()
            if ModernSkinLoader.isSupportedBundleExtension(ext) {
                currentSkin = try loader.loadFromBundle(at: skinInfo.path)
            } else {
                currentSkin = try loader.load(from: skinInfo.path)
            }
            currentSkinName = skinInfo.name
            UserDefaults.standard.set(skinInfo.name, forKey: skinNameKey)
            configureSkinDependencies()
            notifySkinChanged()
            NSLog("ModernSkinEngine: Loaded skin '%@'", skinInfo.name)
            return true
        } catch {
            NSLog("ModernSkinEngine: Failed to load skin '%@': %@", skinInfo.name, error.localizedDescription)
            return false
        }
    }
    
    /// Load a skin from a directory path
    func loadSkin(from url: URL) -> Bool {
        do {
            currentSkin = try loader.load(from: url)
            currentSkinName = currentSkin?.config.meta.name ?? url.lastPathComponent
            configureSkinDependencies()
            notifySkinChanged()
            return true
        } catch {
            NSLog("ModernSkinEngine: Failed to load skin from %@: %@", url.path, error.localizedDescription)
            return false
        }
    }

    /// Import a `.nsz` skin bundle into the user's ModernSkins directory.
    /// Returns the imported skin name (derived from filename without extension).
    ///
    /// The bundle is validated before replacing an existing installed file,
    /// and the selected skin preference is updated only after a successful import.
    func importSkinBundle(
        from sourceURL: URL,
        destinationDirectory: URL? = nil,
        userDefaults: UserDefaults = .standard
    ) throws -> String {
        let ext = sourceURL.pathExtension.lowercased()
        guard ModernSkinLoader.isSupportedBundleExtension(ext) else {
            throw ModernSkinError.unsupportedBundleExtension(ext)
        }

        // Validate first so invalid bundles cannot replace existing installed skins.
        _ = try loader.loadFromBundle(at: sourceURL)

        let userDir = destinationDirectory ?? loader.userSkinsDirectory
        try FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)

        let destinationURL = userDir.appendingPathComponent(sourceURL.lastPathComponent)
        if sourceURL.standardizedFileURL != destinationURL.standardizedFileURL {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        }

        let importedName = destinationURL.deletingPathExtension().lastPathComponent
        userDefaults.set(importedName, forKey: skinNameKey)
        return importedName
    }
    
    // MARK: - Skin Selection Menu
    
    /// Build a menu of available skins with a checkmark on the active one
    func buildSkinMenu() -> NSMenu {
        let menu = NSMenu(title: "Modern Skin")
        
        let available = loader.availableSkins()
        
        if available.isEmpty {
            let item = NSMenuItem(title: "No skins available", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            for skinInfo in available {
                let item = NSMenuItem(title: skinInfo.name, action: #selector(skinMenuItemClicked(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = skinInfo.name
                if skinInfo.name == currentSkinName {
                    item.state = .on
                }
                if skinInfo.isBundled {
                    // No special indicator needed, but could add one
                }
                menu.addItem(item)
            }
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Open skins folder
        let openFolder = NSMenuItem(title: "Open Skins Folder...", action: #selector(openSkinsFolder), keyEquivalent: "")
        openFolder.target = self
        menu.addItem(openFolder)
        
        return menu
    }
    
    @objc private func skinMenuItemClicked(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        loadSkin(named: name)
    }
    
    @objc func openSkinsFolder() {
        let dir = loader.userSkinsDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }
    
    // MARK: - Private
    
    private func configureSkinDependencies() {
        guard let skin = currentSkin else { return }
        
        // Apply base scale factor from skin config (sizeMultiplier is preserved independently)
        ModernSkinElements.baseScaleFactor = skin.config.window.scale ?? 1.25

        // Apply per-skin visualization defaults (mode + mode-specific presets/profiles).
        // window.spectrumTransparentBackground seeds the spectrum transparent state;
        // visualization.visClassic.spectrumWindowTransparentBackground overrides it if both are set.
        applyVisualizationDefaults(from: skin.config.visualization,
                                   windowSpectrumTransparentBackground: skin.config.window.spectrumTransparentBackground)
        
        // Configure bloom processor
        bloomProcessor.configure(with: skin.config.glow)
        
        // Start any skin-defined animations
        animationEngine.stopAll()
        if let animations = skin.config.animations {
            for (elementId, animConfig) in animations {
                animationEngine.startAnimation(elementId: elementId, config: animConfig)
            }
        }
    }

    private func applyVisualizationDefaults(from config: VisualizationConfig?,
                                             windowSpectrumTransparentBackground: Bool? = nil) {
        guard config != nil || windowSpectrumTransparentBackground != nil else { return }

        let defaults = UserDefaults.standard
        var mainVisChanged = false
        var spectrumSettingsChanged = false
        var visClassicMainProfileToLoad: String?
        var visClassicSpectrumProfileToLoad: String?
        var visClassicMainFitToWidth: Bool?
        var visClassicSpectrumFitToWidth: Bool?
        var visClassicMainTransparentBackground: Bool?
        // Seed from window-level setting; visualization.visClassic overrides if also set
        var visClassicSpectrumTransparentBackground: Bool? = windowSpectrumTransparentBackground
        if let transparent = windowSpectrumTransparentBackground {
            defaults.set(transparent, forKey: "visClassicTransparentBg.spectrumWindow")
            spectrumSettingsChanged = true
        }
        var visClassicMainOpacity: Double?
        var visClassicSpectrumOpacity: Double?

        if let modeRaw = config?.mainWindowMode {
            if let mode = MainWindowVisMode(rawValue: modeRaw) {
                if let qualityMode = mode.spectrumQualityMode,
                   !SpectrumAnalyzerView.isShaderAvailable(for: qualityMode) {
                    NSLog("ModernSkinEngine: Ignoring unsupported mainWindowMode '%@' (shader unavailable)", modeRaw)
                } else {
                    defaults.set(mode.rawValue, forKey: "mainWindowVisMode")
                    defaults.set(mode.rawValue, forKey: "modernMainWindowVisMode")
                    mainVisChanged = true
                }
            } else {
                NSLog("ModernSkinEngine: Ignoring unknown mainWindowMode '%@'", modeRaw)
            }
        }

        if let modeRaw = config?.spectrumWindowMode {
            if let mode = SpectrumQualityMode(rawValue: modeRaw) {
                if SpectrumAnalyzerView.isShaderAvailable(for: mode) {
                    defaults.set(mode.rawValue, forKey: "spectrumQualityMode")
                    spectrumSettingsChanged = true
                } else {
                    NSLog("ModernSkinEngine: Ignoring unsupported spectrumWindowMode '%@' (shader unavailable)", modeRaw)
                }
            } else {
                NSLog("ModernSkinEngine: Ignoring unknown spectrumWindowMode '%@'", modeRaw)
            }
        }

        if let visClassic = config?.visClassic {
            if let profile = visClassic.mainWindowProfile {
                defaults.set(profile, forKey: "visClassicLastProfileName.mainWindow")
                visClassicMainProfileToLoad = profile
                mainVisChanged = true
            }
            if let profile = visClassic.spectrumWindowProfile {
                defaults.set(profile, forKey: "visClassicLastProfileName.spectrumWindow")
                visClassicSpectrumProfileToLoad = profile
                spectrumSettingsChanged = true
            }
            if let fit = visClassic.mainWindowFitToWidth {
                defaults.set(fit, forKey: "visClassicFitToWidth.mainWindow")
                visClassicMainFitToWidth = fit
                mainVisChanged = true
            }
            if let fit = visClassic.spectrumWindowFitToWidth {
                defaults.set(fit, forKey: "visClassicFitToWidth.spectrumWindow")
                visClassicSpectrumFitToWidth = fit
                spectrumSettingsChanged = true
            }
            if let transparent = visClassic.mainWindowTransparentBackground {
                defaults.set(transparent, forKey: "visClassicTransparentBg.mainWindow")
                visClassicMainTransparentBackground = transparent
                mainVisChanged = true
            }
            if let transparent = visClassic.spectrumWindowTransparentBackground {
                defaults.set(transparent, forKey: "visClassicTransparentBg.spectrumWindow")
                visClassicSpectrumTransparentBackground = transparent
                spectrumSettingsChanged = true
            }
            if let opacity = visClassic.mainWindowOpacity {
                let clamped = max(0.0, min(1.0, Double(opacity)))
                defaults.set(clamped, forKey: VisClassicBridge.PreferenceScope.mainWindow.opacityKey)
                visClassicMainOpacity = clamped
                mainVisChanged = true
            }
            if let opacity = visClassic.spectrumWindowOpacity {
                let clamped = max(0.0, min(1.0, Double(opacity)))
                defaults.set(clamped, forKey: VisClassicBridge.PreferenceScope.spectrumWindow.opacityKey)
                visClassicSpectrumOpacity = clamped
                spectrumSettingsChanged = true
            }
        }

        if let fire = config?.fire {
            if let styleRaw = fire.mainWindowStyle,
               let style = FlameStyle(rawValue: styleRaw) {
                defaults.set(style.rawValue, forKey: "mainWindowFlameStyle")
                mainVisChanged = true
            } else if let styleRaw = fire.mainWindowStyle {
                NSLog("ModernSkinEngine: Ignoring unknown fire.mainWindowStyle '%@'", styleRaw)
            }

            if let intensityRaw = fire.mainWindowIntensity,
               let intensity = FlameIntensity(rawValue: intensityRaw) {
                defaults.set(intensity.rawValue, forKey: "mainWindowFlameIntensity")
                mainVisChanged = true
            } else if let intensityRaw = fire.mainWindowIntensity {
                NSLog("ModernSkinEngine: Ignoring unknown fire.mainWindowIntensity '%@'", intensityRaw)
            }

            if let styleRaw = fire.spectrumWindowStyle,
               let style = FlameStyle(rawValue: styleRaw) {
                defaults.set(style.rawValue, forKey: "flameStyle")
                spectrumSettingsChanged = true
            } else if let styleRaw = fire.spectrumWindowStyle {
                NSLog("ModernSkinEngine: Ignoring unknown fire.spectrumWindowStyle '%@'", styleRaw)
            }

            if let intensityRaw = fire.spectrumWindowIntensity,
               let intensity = FlameIntensity(rawValue: intensityRaw) {
                defaults.set(intensity.rawValue, forKey: "flameIntensity")
                spectrumSettingsChanged = true
            } else if let intensityRaw = fire.spectrumWindowIntensity {
                NSLog("ModernSkinEngine: Ignoring unknown fire.spectrumWindowIntensity '%@'", intensityRaw)
            }
        }

        if let lightning = config?.lightning {
            if let styleRaw = lightning.mainWindowStyle,
               let style = LightningStyle(rawValue: styleRaw) {
                defaults.set(style.rawValue, forKey: "mainWindowLightningStyle")
                mainVisChanged = true
            } else if let styleRaw = lightning.mainWindowStyle {
                NSLog("ModernSkinEngine: Ignoring unknown lightning.mainWindowStyle '%@'", styleRaw)
            }

            if let styleRaw = lightning.spectrumWindowStyle,
               let style = LightningStyle(rawValue: styleRaw) {
                defaults.set(style.rawValue, forKey: "lightningStyle")
                spectrumSettingsChanged = true
            } else if let styleRaw = lightning.spectrumWindowStyle {
                NSLog("ModernSkinEngine: Ignoring unknown lightning.spectrumWindowStyle '%@'", styleRaw)
            }
        }

        if let matrix = config?.matrix {
            if let schemeRaw = matrix.mainWindowColorScheme,
               let scheme = MatrixColorScheme(rawValue: schemeRaw) {
                defaults.set(scheme.rawValue, forKey: "mainWindowMatrixColorScheme")
                mainVisChanged = true
            } else if let schemeRaw = matrix.mainWindowColorScheme {
                NSLog("ModernSkinEngine: Ignoring unknown matrix.mainWindowColorScheme '%@'", schemeRaw)
            }

            if let intensityRaw = matrix.mainWindowIntensity,
               let intensity = MatrixIntensity(rawValue: intensityRaw) {
                defaults.set(intensity.rawValue, forKey: "mainWindowMatrixIntensity")
                mainVisChanged = true
            } else if let intensityRaw = matrix.mainWindowIntensity {
                NSLog("ModernSkinEngine: Ignoring unknown matrix.mainWindowIntensity '%@'", intensityRaw)
            }

            if let schemeRaw = matrix.spectrumWindowColorScheme,
               let scheme = MatrixColorScheme(rawValue: schemeRaw) {
                defaults.set(scheme.rawValue, forKey: "matrixColorScheme")
                spectrumSettingsChanged = true
            } else if let schemeRaw = matrix.spectrumWindowColorScheme {
                NSLog("ModernSkinEngine: Ignoring unknown matrix.spectrumWindowColorScheme '%@'", schemeRaw)
            }

            if let intensityRaw = matrix.spectrumWindowIntensity,
               let intensity = MatrixIntensity(rawValue: intensityRaw) {
                defaults.set(intensity.rawValue, forKey: "matrixIntensity")
                spectrumSettingsChanged = true
            } else if let intensityRaw = matrix.spectrumWindowIntensity {
                NSLog("ModernSkinEngine: Ignoring unknown matrix.spectrumWindowIntensity '%@'", intensityRaw)
            }
        }

        if mainVisChanged {
            NotificationCenter.default.post(name: NSNotification.Name("MainWindowVisChanged"), object: nil)
        }
        if spectrumSettingsChanged {
            NotificationCenter.default.post(name: NSNotification.Name("SpectrumSettingsChanged"), object: nil)
        }

        if let profile = visClassicMainProfileToLoad {
            NotificationCenter.default.post(
                name: .visClassicProfileCommand,
                object: nil,
                userInfo: ["command": "load", "profileName": profile, "target": "mainWindow"]
            )
        }
        if let profile = visClassicSpectrumProfileToLoad {
            NotificationCenter.default.post(
                name: .visClassicProfileCommand,
                object: nil,
                userInfo: ["command": "load", "profileName": profile, "target": "spectrumWindow"]
            )
        }
        if let fit = visClassicMainFitToWidth {
            NotificationCenter.default.post(
                name: .visClassicProfileCommand,
                object: nil,
                userInfo: ["command": "fitToWidth", "enabled": fit, "target": "mainWindow"]
            )
        }
        if let fit = visClassicSpectrumFitToWidth {
            NotificationCenter.default.post(
                name: .visClassicProfileCommand,
                object: nil,
                userInfo: ["command": "fitToWidth", "enabled": fit, "target": "spectrumWindow"]
            )
        }
        if let transparent = visClassicMainTransparentBackground {
            NotificationCenter.default.post(
                name: .visClassicProfileCommand,
                object: nil,
                userInfo: ["command": "transparentBg", "enabled": transparent, "target": "mainWindow"]
            )
        }
        if let transparent = visClassicSpectrumTransparentBackground {
            NotificationCenter.default.post(
                name: .visClassicProfileCommand,
                object: nil,
                userInfo: ["command": "transparentBg", "enabled": transparent, "target": "spectrumWindow"]
            )
        }
        if let opacity = visClassicMainOpacity {
            NotificationCenter.default.post(
                name: .visClassicProfileCommand,
                object: nil,
                userInfo: ["command": "opacity", "value": opacity, "target": "mainWindow"]
            )
        }
        if let opacity = visClassicSpectrumOpacity {
            NotificationCenter.default.post(
                name: .visClassicProfileCommand,
                object: nil,
                userInfo: ["command": "opacity", "value": opacity, "target": "spectrumWindow"]
            )
        }
    }
    
    private func notifySkinChanged() {
        NotificationCenter.default.post(name: Self.skinDidChangeNotification, object: self)
    }

    private func resolvedSkinName(for name: String) -> String {
        switch name {
        case "smooth-glass": return "SmoothGlass"
        case "blood-glass": return "BloodGlass"
        default: return name
        }
    }
}
