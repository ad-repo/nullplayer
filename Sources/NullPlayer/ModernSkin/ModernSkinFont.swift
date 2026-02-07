import AppKit

/// Font loading and resolution for the modern skin system.
/// Supports bundled TTF fonts, skin-provided fonts, and system font fallbacks.
enum ModernSkinFont {
    
    /// Default font name bundled with the app
    static let defaultFontName = "DepartureMono-Regular"
    
    /// Default font sizes
    static let defaultTitleSize: CGFloat = 10.0
    static let defaultBodySize: CGFloat = 9.0
    static let defaultSmallSize: CGFloat = 7.0
    static let defaultTimeSize: CGFloat = 20.0
    
    /// Track whether the bundled font has been registered
    private static var bundledFontRegistered = false
    
    // MARK: - Font Registration
    
    /// Register the bundled Departure Mono font if not already registered.
    /// This must be called before attempting to use the font.
    static func registerBundledFont() {
        guard !bundledFontRegistered else { return }
        
        // Try to find the font in the app's resource bundle
        if let fontURL = findBundledFontURL() {
            var errorRef: Unmanaged<CFError>?
            if CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &errorRef) {
                bundledFontRegistered = true
                NSLog("ModernSkinFont: Registered bundled font from %@", fontURL.path)
            } else {
                // Font might already be registered
                bundledFontRegistered = true
                NSLog("ModernSkinFont: Font may already be registered")
            }
        } else {
            NSLog("ModernSkinFont: Bundled font not found, will use system fallback")
        }
    }
    
    /// Register a font from a skin bundle
    static func registerSkinFont(at url: URL) -> Bool {
        var errorRef: Unmanaged<CFError>?
        return CTFontManagerRegisterFontsForURL(url as CFURL, .process, &errorRef)
    }
    
    // MARK: - Font Resolution
    
    /// Resolve the complete set of fonts for a skin configuration.
    /// Returns (primary, time, small) font tuple.
    static func resolve(config: FontConfig, skinBundle: URL?) -> (primary: NSFont, time: NSFont, small: NSFont) {
        // Register bundled font first
        registerBundledFont()
        
        // Try to register skin-provided font if it exists
        if let skinBundle = skinBundle {
            let fontExtensions = ["ttf", "otf", "woff"]
            for ext in fontExtensions {
                let fontFile = skinBundle.appendingPathComponent("fonts").appendingPathComponent("\(config.primaryName).\(ext)")
                if FileManager.default.fileExists(atPath: fontFile.path) {
                    _ = registerSkinFont(at: fontFile)
                    break
                }
            }
        }
        
        let primaryFont = resolveFont(
            name: config.primaryName,
            fallback: config.fallbackName,
            size: config.bodySize ?? defaultBodySize
        )
        
        let timeFont = resolveFont(
            name: config.primaryName,
            fallback: config.fallbackName,
            size: config.timeSize ?? defaultTimeSize
        )
        
        let smallFont = resolveFont(
            name: config.primaryName,
            fallback: config.fallbackName,
            size: config.smallSize ?? defaultSmallSize
        )
        
        return (primaryFont, timeFont, smallFont)
    }
    
    /// Resolve a single font by name with fallback
    static func resolveFont(name: String, fallback: String?, size: CGFloat) -> NSFont {
        // Try primary font name
        if let font = NSFont(name: name, size: size) {
            return font
        }
        
        // Try fallback font name
        if let fallbackName = fallback, let font = NSFont(name: fallbackName, size: size) {
            return font
        }
        
        // Try bundled default font
        if let font = NSFont(name: defaultFontName, size: size) {
            return font
        }
        
        // Last resort: monospace system font
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
    
    // MARK: - Private
    
    private static func findBundledFontURL() -> URL? {
        let bundle = Bundle.main
        let fontExtensions = ["otf", "ttf"]
        
        // Check resource bundle
        if let resourceURL = bundle.resourceURL {
            for ext in fontExtensions {
                let paths = [
                    resourceURL.appendingPathComponent("Resources/Fonts/DepartureMono-Regular.\(ext)"),
                    resourceURL.appendingPathComponent("NullPlayer_NullPlayer.bundle/Resources/Fonts/DepartureMono-Regular.\(ext)"),
                    resourceURL.appendingPathComponent("Fonts/DepartureMono-Regular.\(ext)"),
                ]
                for path in paths {
                    if FileManager.default.fileExists(atPath: path.path) {
                        return path
                    }
                }
            }
        }
        
        return nil
    }
}
