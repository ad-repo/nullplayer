import AppKit
import ZIPFoundation

/// Loads modern skins from directory paths or `.nps` (ZIP) bundles.
/// Returns a fully configured `ModernSkin` with images, fonts, and config.
class ModernSkinLoader {
    
    // MARK: - Singleton
    
    static let shared = ModernSkinLoader()
    
    private init() {}
    
    // MARK: - Loading
    
    /// Load a skin from a directory path
    func load(from directory: URL) throws -> ModernSkin {
        let configURL = directory.appendingPathComponent("skin.json")
        
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            throw ModernSkinError.configNotFound(directory.path)
        }
        
        let data = try Data(contentsOf: configURL)
        let config = try JSONDecoder().decode(ModernSkinConfig.self, from: data)
        
        let skin = ModernSkin(config: config, bundlePath: directory)
        
        // Load images
        loadImages(for: skin, from: directory)
        
        // Resolve fonts
        let fonts = ModernSkinFont.resolve(config: config.fonts, skinBundle: directory)
        skin.setFonts(primary: fonts.primary, time: fonts.time, small: fonts.small)
        
        // Load background image if specified
        if let bgImagePath = config.background.image {
            let bgURL = directory.appendingPathComponent("images").appendingPathComponent(bgImagePath)
            if let bgImage = NSImage(contentsOf: bgURL) {
                skin.setBackgroundImage(bgImage)
            }
        }
        
        NSLog("ModernSkinLoader: Loaded skin '%@' from %@", config.meta.name, directory.path)
        return skin
    }
    
    /// Load a skin from a `.nps` ZIP bundle
    func loadFromBundle(at url: URL) throws -> ModernSkin {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModernSkin_\(UUID().uuidString)")
        
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // Extract ZIP
        try FileManager.default.unzipItem(at: url, to: tempDir)
        
        // Find skin.json - might be at root or in a subdirectory
        let configURL = tempDir.appendingPathComponent("skin.json")
        if FileManager.default.fileExists(atPath: configURL.path) {
            return try load(from: tempDir)
        }
        
        // Check subdirectories
        let contents = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: [.isDirectoryKey])
        for item in contents {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir)
            if isDir.boolValue {
                let subConfig = item.appendingPathComponent("skin.json")
                if FileManager.default.fileExists(atPath: subConfig.path) {
                    return try load(from: item)
                }
            }
        }
        
        throw ModernSkinError.configNotFound(url.path)
    }
    
    /// Load the default bundled skin (NeonWave)
    func loadDefault() -> ModernSkin {
        // Try to find NeonWave in the resource bundle
        if let skinDir = findBundledSkinDirectory("NeonWave") {
            do {
                return try load(from: skinDir)
            } catch {
                NSLog("ModernSkinLoader: Failed to load bundled NeonWave: %@", error.localizedDescription)
            }
        }
        
        // Create a minimal fallback skin with programmatic rendering
        NSLog("ModernSkinLoader: Using fallback minimal skin")
        return createFallbackSkin()
    }
    
    // MARK: - Skin Discovery
    
    /// User skins directory
    var userSkinsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("NullPlayer").appendingPathComponent("ModernSkins")
    }
    
    /// Get all available modern skins (bundled + user)
    func availableSkins() -> [(name: String, path: URL, isBundled: Bool)] {
        var skins: [(name: String, path: URL, isBundled: Bool)] = []
        
        // Bundled skins
        if let bundledDir = findBundledSkinsDirectory() {
            if let contents = try? FileManager.default.contentsOfDirectory(at: bundledDir, includingPropertiesForKeys: [.isDirectoryKey]) {
                for item in contents {
                    var isDir: ObjCBool = false
                    FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir)
                    if isDir.boolValue {
                        let skinJSON = item.appendingPathComponent("skin.json")
                        if FileManager.default.fileExists(atPath: skinJSON.path) {
                            skins.append((name: item.lastPathComponent, path: item, isBundled: true))
                        }
                    }
                }
            }
        }
        
        // User skins directory
        let userDir = userSkinsDirectory
        try? FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)
        
        if let contents = try? FileManager.default.contentsOfDirectory(at: userDir, includingPropertiesForKeys: nil) {
            for item in contents {
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir)
                
                if isDir.boolValue {
                    // Directory-based skin
                    let skinJSON = item.appendingPathComponent("skin.json")
                    if FileManager.default.fileExists(atPath: skinJSON.path) {
                        skins.append((name: item.lastPathComponent, path: item, isBundled: false))
                    }
                } else if item.pathExtension.lowercased() == "nps" {
                    // ZIP-bundled skin
                    let name = item.deletingPathExtension().lastPathComponent
                    skins.append((name: name, path: item, isBundled: false))
                }
            }
        }
        
        return skins.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    // MARK: - Image Loading
    
    private func loadImages(for skin: ModernSkin, from directory: URL) {
        let imagesDir = directory.appendingPathComponent("images")
        
        guard FileManager.default.fileExists(atPath: imagesDir.path) else {
            NSLog("ModernSkinLoader: No images directory found at %@", imagesDir.path)
            return
        }
        
        guard let files = try? FileManager.default.contentsOfDirectory(at: imagesDir, includingPropertiesForKeys: nil) else {
            return
        }
        
        let isRetina = NSScreen.main?.backingScaleFactor ?? 1.0 > 1.0
        
        for file in files {
            let ext = file.pathExtension.lowercased()
            guard ext == "png" || ext == "jpg" || ext == "jpeg" else { continue }
            
            let filename = file.deletingPathExtension().lastPathComponent
            
            // Skip @2x files in the primary pass (they're loaded as alternates)
            guard !filename.hasSuffix("@2x") else { continue }
            
            // Check for @2x version on Retina
            var imageToUse: NSImage?
            if isRetina {
                let retinaName = "\(filename)@2x.\(ext)"
                let retinaURL = imagesDir.appendingPathComponent(retinaName)
                if let retinaImage = NSImage(contentsOf: retinaURL) {
                    imageToUse = retinaImage
                }
            }
            
            // Fall back to 1x
            if imageToUse == nil {
                imageToUse = NSImage(contentsOf: file)
            }
            
            if let image = imageToUse {
                skin.setImage(image, for: filename)
            }
        }
        
        NSLog("ModernSkinLoader: Loaded %d images from %@", skin.images.count, imagesDir.path)
    }
    
    // MARK: - Bundle Path Helpers
    
    private func findBundledSkinDirectory(_ name: String) -> URL? {
        let bundle = Bundle.main
        if let resourceURL = bundle.resourceURL {
            let paths = [
                resourceURL.appendingPathComponent("Resources/Skins/\(name)"),
                resourceURL.appendingPathComponent("NullPlayer_NullPlayer.bundle/Resources/Skins/\(name)"),
                resourceURL.appendingPathComponent("Skins/\(name)"),
            ]
            for path in paths {
                if FileManager.default.fileExists(atPath: path.path) {
                    return path
                }
            }
        }
        return nil
    }
    
    private func findBundledSkinsDirectory() -> URL? {
        let bundle = Bundle.main
        if let resourceURL = bundle.resourceURL {
            let paths = [
                resourceURL.appendingPathComponent("Resources/Skins"),
                resourceURL.appendingPathComponent("NullPlayer_NullPlayer.bundle/Resources/Skins"),
                resourceURL.appendingPathComponent("Skins"),
            ]
            for path in paths {
                if FileManager.default.fileExists(atPath: path.path) {
                    return path
                }
            }
        }
        return nil
    }
    
    // MARK: - Fallback Skin
    
    private func createFallbackSkin() -> ModernSkin {
        let config = ModernSkinConfig(
            meta: SkinMeta(name: "NeonWave", author: "NullPlayer", version: "1.0", description: "Default neon skin"),
            palette: ColorPalette(
                primary: "#00ffcc",
                secondary: "#00ccff",
                accent: "#ff00aa",
                highlight: nil,
                background: "#080810",
                surface: "#0c1018",
                text: "#00ffcc",
                textDim: "#009977",
                positive: nil,
                negative: nil,
                warning: nil,
                border: nil
            ),
            fonts: FontConfig(
                primaryName: ModernSkinFont.defaultFontName,
                fallbackName: "Menlo",
                titleSize: 10,
                bodySize: 11,
                smallSize: 7,
                timeSize: 24
            ),
            background: BackgroundConfig(
                image: nil,
                grid: GridConfig(color: "#00ffcc", spacing: 18, angle: 75, opacity: 0.06, perspective: true)
            ),
            glow: GlowConfig(enabled: true, radius: 6, intensity: 0.7, threshold: 0.5, color: nil),
            window: WindowConfig(borderWidth: 1.5, borderColor: "#00ffcc", cornerRadius: 0),
            elements: nil,
            animations: nil
        )
        
        let skin = ModernSkin(config: config, bundlePath: nil)
        let fonts = ModernSkinFont.resolve(config: config.fonts, skinBundle: nil)
        skin.setFonts(primary: fonts.primary, time: fonts.time, small: fonts.small)
        return skin
    }
}

// MARK: - Errors

enum ModernSkinError: Error, LocalizedError {
    case configNotFound(String)
    case invalidConfig(String)
    case imageLoadFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .configNotFound(let path):
            return "skin.json not found at: \(path)"
        case .invalidConfig(let message):
            return "Invalid skin config: \(message)"
        case .imageLoadFailed(let path):
            return "Failed to load image: \(path)"
        }
    }
}
