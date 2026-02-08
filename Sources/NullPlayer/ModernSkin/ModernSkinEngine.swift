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
    private let loader = ModernSkinLoader.shared
    
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
        let preferredName = UserDefaults.standard.string(forKey: skinNameKey)
        
        if let name = preferredName {
            if loadSkin(named: name) {
                return
            }
        }
        
        // Fall back to default
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
        
        guard let skinInfo = available.first(where: { $0.name == name }) else {
            NSLog("ModernSkinEngine: Skin '%@' not found", name)
            return false
        }
        
        do {
            let ext = skinInfo.path.pathExtension.lowercased()
            if ext == "nps" {
                currentSkin = try loader.loadFromBundle(at: skinInfo.path)
            } else {
                currentSkin = try loader.load(from: skinInfo.path)
            }
            currentSkinName = name
            UserDefaults.standard.set(name, forKey: skinNameKey)
            configureSkinDependencies()
            notifySkinChanged()
            NSLog("ModernSkinEngine: Loaded skin '%@'", name)
            return true
        } catch {
            NSLog("ModernSkinEngine: Failed to load skin '%@': %@", name, error.localizedDescription)
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
    
    @objc private func openSkinsFolder() {
        let dir = loader.userSkinsDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }
    
    // MARK: - Private
    
    private func configureSkinDependencies() {
        guard let skin = currentSkin else { return }
        
        // Apply scale factor from skin config
        ModernSkinElements.scaleFactor = skin.config.window.scale ?? 1.25
        
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
    
    private func notifySkinChanged() {
        NotificationCenter.default.post(name: Self.skinDidChangeNotification, object: self)
    }
}
