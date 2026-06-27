import AppKit

/// Central coordinator for the modern skin system.
/// Manages skin lifecycle: loading, selection, caching, and providing the active skin.
///
/// This is a singleton that is completely independent of `WindowManager.shared.currentSkin`
/// (which manages classic skins). They coexist without conflict.
class ModernSkinEngine {
    struct SkinInfo {
        let name: String
        let path: URL?
        let isBundled: Bool
    }
    
    // MARK: - Singleton
    
    static let shared = ModernSkinEngine()
    
    // MARK: - Properties
    
    /// The currently active modern skin
    private(set) var currentSkin: ModernSkin?
    
    /// Name of the currently loaded skin
    private(set) var currentSkinName: String?

    /// The modern-family namespace for the currently loaded skin.
    private(set) var currentFamily: ModernSkinFamily = .modern

    var currentRenderStyle: ModernRenderStyle {
        currentFamily.renderStyle
    }
    
    /// The skin loader
    let loader = ModernSkinLoader.shared
    
    /// The animation engine
    let animationEngine = ModernSkinAnimation()
    
    /// The bloom post-processor
    let bloomProcessor = BloomPostProcessor()
    
    /// Notification posted when the modern skin changes
    static let skinDidChangeNotification = Notification.Name("ModernSkinDidChange")
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Skin Lifecycle
    
    /// Load the preferred skin (from UserDefaults) or the default
    func loadPreferredSkin() {
        loadPreferredSkin(for: .modern)
    }

    /// Load the preferred skin for a family (from UserDefaults) or the default.
    func loadPreferredSkin(for family: ModernSkinFamily) {
        if let name = UserDefaults.standard.string(forKey: family.skinNameKey) {
            if loadSkin(named: name, family: family, preservePersistedProfiles: true) { return }
        }
        loadDefaultSkin(for: family, preservePersistedProfiles: true)
    }
    
    /// Full reset of the active modern/metal skin: clear every persisted
    /// visualization override (analyzer mode, vis_classic profile/fit/transparent/
    /// opacity, and the per-mode style/intensity/color keys for both the main and
    /// dedicated spectrum windows), reload the skin re-applying its shipped defaults,
    /// then push the live windows back to the default analyzer immediately.
    func resetCurrentSkinToDefault() {
        let defaults = UserDefaults.standard

        // 1. Clear persisted visualization overrides so skin/app defaults take effect.
        var keys: [String] = [
            "mainWindowVisMode", "modernMainWindowVisMode", "spectrumQualityMode",
            "spectrumNormalizationMode", "mainWindowNormalizationMode",
            // Fire
            "mainWindowFlameStyle", "mainWindowFlameIntensity", "flameStyle", "flameIntensity",
            // Lightning
            "mainWindowLightningStyle", "lightningStyle",
            // Matrix
            "mainWindowMatrixColorScheme", "mainWindowMatrixIntensity", "matrixColorScheme", "matrixIntensity",
            // EKG / decay
            "mainWindowEKGStyle", "ekgStyle", "mainWindowDecayMode", "decayMode",
            // Legacy vis_classic (pre-scoped keys)
            "visClassicLastProfileName", "visClassicFitToWidth",
        ]
        for scope in [VisClassicBridge.PreferenceScope.mainWindow, .spectrumWindow] {
            keys.append(scope.lastProfileNameKey)
            keys.append(scope.fitToWidthKey)
            keys.append(scope.transparentBgKey)
            keys.append(scope.opacityKey)
        }
        for key in keys { defaults.removeObject(forKey: key) }

        // 2. Reload the active skin, re-applying its shipped visualization defaults.
        let family = currentFamily
        if let name = currentSkinName {
            _ = loadSkin(named: name, family: family, preservePersistedProfiles: false)
        } else {
            loadDefaultSkin(for: family, preservePersistedProfiles: false)
        }

        // 3. If the skin didn't re-seed a main-window analyzer mode, fall back to the
        //    app default (Spectrum) so the live window leaves any black vis_classic box.
        if defaults.string(forKey: "mainWindowVisMode") == nil {
            defaults.set(MainWindowVisMode.spectrum.rawValue, forKey: "mainWindowVisMode")
            defaults.set(MainWindowVisMode.spectrum.rawValue, forKey: "modernMainWindowVisMode")
        }

        // 4. Push the live windows to re-read the (reset) analyzer mode/settings now.
        NotificationCenter.default.post(name: NSNotification.Name("MainWindowVisChanged"), object: nil)
        NotificationCenter.default.post(name: NSNotification.Name("SpectrumSettingsChanged"), object: nil)
    }

    /// Load the default bundled skin (NeonWave)
    func loadDefaultSkin() {
        loadDefaultSkin(for: .modern)
    }

    func loadDefaultSkin(for family: ModernSkinFamily) {
        loadDefaultSkin(for: family, preservePersistedProfiles: false)
    }

    private func loadDefaultSkin(for family: ModernSkinFamily, preservePersistedProfiles: Bool) {
        currentSkin = loader.loadDefault(for: family)
        currentSkinName = currentSkin?.config.meta.name ?? family.defaultSkinName
        currentFamily = family
        UserDefaults.standard.set(currentSkinName, forKey: family.skinNameKey)
        configureSkinDependencies(preservePersistedProfiles: preservePersistedProfiles)
        notifySkinChanged()
        NSLog("ModernSkinEngine: Loaded default %@ skin '%@'", String(describing: family), currentSkinName ?? family.defaultSkinName)
    }
    
    /// Load a skin by name (searches bundled and user skins)
    @discardableResult
    func loadSkin(named name: String) -> Bool {
        loadSkin(named: name, family: .modern)
    }

    @discardableResult
    func loadSkin(named name: String, family: ModernSkinFamily) -> Bool {
        loadSkin(named: name, family: family, preservePersistedProfiles: false)
    }

    @discardableResult
    private func loadSkin(named name: String, family: ModernSkinFamily, preservePersistedProfiles: Bool) -> Bool {
        let available = availableSkins(for: family)
        let resolvedName = resolvedSkinName(for: name)

        guard let skinInfo = available.first(where: { $0.name == name })
                          ?? available.first(where: { $0.name == resolvedName }) else {
            NSLog("ModernSkinEngine: Skin '%@' not found", name)
            return false
        }

        guard let path = skinInfo.path else {
            // Built-in (code-defined) skin: metal finishes are built by name; everything else
            // falls back to the family default.
            if family == .metal {
                currentSkin = loader.createBuiltInMetalSkin(named: skinInfo.name)
                currentSkinName = currentSkin?.config.meta.name ?? skinInfo.name
                currentFamily = family
                UserDefaults.standard.set(currentSkinName, forKey: family.skinNameKey)
                configureSkinDependencies(preservePersistedProfiles: preservePersistedProfiles)
                notifySkinChanged()
                NSLog("ModernSkinEngine: Loaded built-in metal skin '%@'", currentSkinName ?? skinInfo.name)
                return true
            }
            loadDefaultSkin(for: family, preservePersistedProfiles: preservePersistedProfiles)
            return true
        }

        do {
            let ext = path.pathExtension.lowercased()
            if ModernSkinLoader.isSupportedBundleExtension(ext) {
                currentSkin = try loader.loadFromBundle(at: path)
            } else {
                currentSkin = try loader.load(from: path)
            }
            currentSkinName = skinInfo.name
            currentFamily = family
            UserDefaults.standard.set(skinInfo.name, forKey: family.skinNameKey)
            configureSkinDependencies(preservePersistedProfiles: preservePersistedProfiles)
            notifySkinChanged()
            NSLog("ModernSkinEngine: Loaded %@ skin '%@'", String(describing: family), skinInfo.name)
            return true
        } catch {
            NSLog("ModernSkinEngine: Failed to load skin '%@': %@", skinInfo.name, error.localizedDescription)
            return false
        }
    }
    
    /// Load a skin from a directory path
    func loadSkin(from url: URL) -> Bool {
        loadSkin(from: url, family: .modern)
    }

    func loadSkin(from url: URL, family: ModernSkinFamily) -> Bool {
        do {
            currentSkin = try loader.load(from: url)
            currentSkinName = currentSkin?.config.meta.name ?? url.lastPathComponent
            currentFamily = family
            UserDefaults.standard.set(currentSkinName, forKey: family.skinNameKey)
            configureSkinDependencies(preservePersistedProfiles: false)
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
        family: ModernSkinFamily = .modern,
        destinationDirectory: URL? = nil,
        userDefaults: UserDefaults = .standard
    ) throws -> String {
        let ext = sourceURL.pathExtension.lowercased()
        guard ModernSkinLoader.isSupportedBundleExtension(ext) else {
            throw ModernSkinError.unsupportedBundleExtension(ext)
        }

        // Validate first so invalid bundles cannot replace existing installed skins.
        _ = try loader.loadFromBundle(at: sourceURL)

        let userDir = destinationDirectory ?? loader.userSkinsDirectory(for: family)
        try FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)

        let destinationURL = userDir.appendingPathComponent(sourceURL.lastPathComponent)
        if sourceURL.standardizedFileURL != destinationURL.standardizedFileURL {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        }

        let importedName = destinationURL.deletingPathExtension().lastPathComponent
        userDefaults.set(importedName, forKey: family.skinNameKey)
        return importedName
    }

    func availableSkins(for family: ModernSkinFamily) -> [SkinInfo] {
        let discovered = loader.availableSkins(for: family).map {
            SkinInfo(name: $0.name, path: $0.path, isBundled: $0.isBundled)
        }

        switch family {
        case .modern:
            return discovered
        case .metal:
            // An imported metal bundle whose name collides with a built-in finish should win:
            // expose the user skin (with a real path) and drop only the synthesized built-in
            // entry, so loadSkin(named:) resolves the bundle instead of the path-nil built-in.
            let userNames = Set(discovered.map(\.name))
            let builtIns = ModernSkinLoader.builtInMetalSkinNames
                .filter { !userNames.contains($0) }
                .map { SkinInfo(name: $0, path: nil, isBundled: true) }
            return builtIns + discovered
        }
    }
    
    // MARK: - Skin Selection Menu
    
    /// Build a menu of available skins with a checkmark on the active one
    func buildSkinMenu() -> NSMenu {
        let menu = NSMenu(title: "Modern Skin")
        
        let available = availableSkins(for: currentFamily)
        
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
        loadSkin(named: name, family: currentFamily)
    }
    
    @objc func openSkinsFolder() {
        openSkinsFolderForFamily(.modern)
    }

    func openSkinsFolderForFamily(_ family: ModernSkinFamily) {
        let dir = loader.userSkinsDirectory(for: family)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }
    
    // MARK: - Private
    
    private func configureSkinDependencies(preservePersistedProfiles: Bool = false) {
        guard let skin = currentSkin else { return }

        // Stamp the render style onto the skin instance so renderers and windows derive
        // "is this metal?" from the skin they're drawing, not the global currentRenderStyle
        // (which could lag a skin swap and leak the modern darkened top-chrome band into metal).
        skin.renderStyle = currentFamily.renderStyle

        // Apply base scale factor from skin config (sizeMultiplier is preserved independently)
        ModernSkinElements.baseScaleFactor = skin.config.window.scale ?? 1.25

        // Apply per-skin visualization defaults (mode + mode-specific presets/profiles).
        // window.spectrumTransparentBackground seeds the spectrum transparent state;
        // visualization.visClassic.spectrumWindowTransparentBackground overrides it if both are set.
        // Metal finishes own their analyzer look: always apply the per-finish vis_classic
        // profile so it follows the finish (a stale non-metal profile from an earlier
        // session must not survive into metal mode), even though other persisted profiles
        // are preserved across launches.
        applyVisualizationDefaults(from: skin.config.visualization,
                                   windowSpectrumTransparentBackground: skin.config.window.spectrumTransparentBackground,
                                   preservePersistedProfiles: preservePersistedProfiles,
                                   forceProfileDefaults: currentFamily == .metal)
        
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
                                             windowSpectrumTransparentBackground: Bool? = nil,
                                             preservePersistedProfiles: Bool = false,
                                             forceProfileDefaults: Bool = false) {
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
            if let profile = visClassic.mainWindowProfile,
               Self.shouldApplyProfileDefault(
                   forKey: VisClassicBridge.PreferenceScope.mainWindow.lastProfileNameKey,
                   preservePersistedProfiles: preservePersistedProfiles,
                   forceProfileDefaults: forceProfileDefaults,
                   defaults: defaults
               ) {
                defaults.set(profile, forKey: "visClassicLastProfileName.mainWindow")
                visClassicMainProfileToLoad = profile
                mainVisChanged = true
            }
            if let profile = visClassic.spectrumWindowProfile,
               Self.shouldApplyProfileDefault(
                   forKey: VisClassicBridge.PreferenceScope.spectrumWindow.lastProfileNameKey,
                   preservePersistedProfiles: preservePersistedProfiles,
                   forceProfileDefaults: forceProfileDefaults,
                   defaults: defaults
               ) {
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

    /// On app launch, a skin's profile acts as a first-use default rather than
    /// replacing a profile the user selected during an earlier session. Explicit
    /// skin changes still apply the newly selected skin's profile defaults.
    static func shouldApplyProfileDefault(
        forKey key: String,
        preservePersistedProfiles: Bool,
        forceProfileDefaults: Bool = false,
        defaults: UserDefaults
    ) -> Bool {
        let shouldPreserve = preservePersistedProfiles && !forceProfileDefaults
        return !shouldPreserve || defaults.object(forKey: key) == nil
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
