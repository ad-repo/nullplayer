import Foundation

/// Helper to access bundled resources in both SPM development and standalone app bundle
enum BundleHelper {
    
    /// Returns the bundle containing app resources
    /// - In SPM development: Uses Bundle.module
    /// - In standalone app: Uses Bundle.main's Resources folder
    static var resourceBundle: Bundle {
        // First try Bundle.module (SPM development)
        #if DEBUG
        return Bundle.module
        #else
        // In release builds, check if we're in an app bundle
        if let resourceURL = Bundle.main.resourceURL,
           FileManager.default.fileExists(atPath: resourceURL.appendingPathComponent("Presets").path) {
            return Bundle.main
        }
        // Fallback to module bundle
        return Bundle.module
        #endif
    }
    
    /// Find a resource URL, checking both SPM module bundle and main app bundle
    static func url(forResource name: String, withExtension ext: String?, subdirectory: String? = nil) -> URL? {
        // Try Bundle.module first (works in SPM development)
        if let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: subdirectory) {
            return url
        }
        
        // Try main bundle (works in standalone app)
        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: subdirectory) {
            return url
        }
        
        // Try main bundle Resources subdirectory (common app bundle structure)
        if let subdirectory = subdirectory {
            if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources/\(subdirectory)") {
                return url
            }
        }
        
        // Try without subdirectory in main bundle
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url
        }
        
        return nil
    }
    
    /// Find a resource URL in a specific subdirectory
    static func url(forResource name: String, withExtension ext: String?, inDirectory directory: String) -> URL? {
        return url(forResource: name, withExtension: ext, subdirectory: directory)
    }
    
    /// Get the path to the Presets directory
    static var presetsDirectory: URL? {
        // Try module bundle first
        if let url = Bundle.module.url(forResource: "Presets", withExtension: nil, subdirectory: "Resources") {
            return url
        }
        if let url = Bundle.module.url(forResource: "Presets", withExtension: nil) {
            return url
        }
        
        // Try main bundle
        if let url = Bundle.main.url(forResource: "Presets", withExtension: nil) {
            return url
        }
        if let resourceURL = Bundle.main.resourceURL {
            let presetsURL = resourceURL.appendingPathComponent("Presets")
            if FileManager.default.fileExists(atPath: presetsURL.path) {
                return presetsURL
            }
        }
        
        return nil
    }
    
    /// Get the path to the Textures directory
    static var texturesDirectory: URL? {
        // Try module bundle first
        if let url = Bundle.module.url(forResource: "Textures", withExtension: nil, subdirectory: "Resources") {
            return url
        }
        if let url = Bundle.module.url(forResource: "Textures", withExtension: nil) {
            return url
        }
        
        // Try main bundle
        if let url = Bundle.main.url(forResource: "Textures", withExtension: nil) {
            return url
        }
        if let resourceURL = Bundle.main.resourceURL {
            let texturesURL = resourceURL.appendingPathComponent("Textures")
            if FileManager.default.fileExists(atPath: texturesURL.path) {
                return texturesURL
            }
        }
        
        return nil
    }
    
    /// Get the path to a skin file (wsz)
    static func skinURL(named name: String) -> URL? {
        return url(forResource: name, withExtension: "wsz")
    }
}
