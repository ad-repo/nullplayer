import Foundation

/// The AVS engine's preset list and the choices it remembers: the bundled upstream presets, then a
/// user folder's, and the preset showing. Its auto-cycle choice is `VisualizationCycleSettings`'s.
enum AvsPresets {
    private enum Key {
        static let customFolder = "avs.customPresetsFolder"
        static let currentPreset = "avs.presetPath"
    }

    /// Cleared by "Reset All Visualization Preferences".
    static let preferenceKeys = [Key.customFolder, Key.currentPreset]

    /// A plain path, like `ProjectMWrapper.customPresetsFolder` (tasks/MISC_TASKS.md has the
    /// security-scoped bookmark row both need for a sandboxed build).
    static var customFolder: String? {
        get { UserDefaults.standard.string(forKey: Key.customFolder) }
        set { UserDefaults.standard.set(newValue, forKey: Key.customFolder) }
    }

    static var currentPreset: String? {
        get { UserDefaults.standard.string(forKey: Key.currentPreset) }
        set { UserDefaults.standard.set(newValue, forKey: Key.currentPreset) }
    }

    static var bundledFolder: URL? { BundleHelper.url(forResource: "AVSPresets", withExtension: nil) }

    /// Every preset, bundled first, each group sorted by name; the user folder is searched
    /// recursively, as Winamp's AVS folder was.
    static func all() -> [URL] {
        let folders = [bundledFolder, customFolder.map { URL(fileURLWithPath: $0) }].compactMap { $0 }
        return folders.flatMap { folder -> [URL] in
            let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL } ?? []
            return files.filter { $0.pathExtension.lowercased() == "avs" }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        }
    }
}
