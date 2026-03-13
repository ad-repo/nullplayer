import Foundation
import CVisClassicCore

final class VisClassicBridge {
    enum PreferenceScope {
        case spectrumWindow
        case mainWindow

        var lastProfileNameKey: String {
            switch self {
            case .spectrumWindow: return "visClassicLastProfileName.spectrumWindow"
            case .mainWindow: return "visClassicLastProfileName.mainWindow"
            }
        }

        var fitToWidthKey: String {
            switch self {
            case .spectrumWindow: return "visClassicFitToWidth.spectrumWindow"
            case .mainWindow: return "visClassicFitToWidth.mainWindow"
            }
        }

        var transparentBgKey: String {
            switch self {
            case .spectrumWindow: return "visClassicTransparentBg.spectrumWindow"
            case .mainWindow: return "visClassicTransparentBg.mainWindow"
            }
        }

        var opacityKey: String {
            switch self {
            case .spectrumWindow: return "visClassicOpacity.spectrumWindow"
            case .mainWindow: return "visClassicOpacity.mainWindow"
            }
        }
    }

    struct ProfileEntry {
        let name: String
        let url: URL
        let isUserProfile: Bool
    }

    private var core: OpaquePointer?
    private let preferenceScope: PreferenceScope
    private(set) var currentProfileName: String?
    private(set) var currentProfileURL: URL?
    private static let legacyLastProfileNameKey = "visClassicLastProfileName"
    private static let legacyFitToWidthKey = "visClassicFitToWidth"

    init?(width: Int, height: Int, scope: PreferenceScope = .spectrumWindow) {
        guard let handle = vc_create(Int32(width), Int32(height)) else {
            return nil
        }
        core = handle
        preferenceScope = scope

        ensureProfilesBootstrapped()
        let profiles = availableProfiles()
        if let lastName = Self.lastProfileName(for: scope),
           let lastProfile = profiles.first(where: { $0.name == lastName }) {
            _ = loadProfile(url: lastProfile.url)
        } else if let defaultProfile = profiles.first {
            _ = loadProfile(url: defaultProfile.url)
        }

        let fitDefault = Self.fitToWidthDefault(for: scope)
        _ = setFitToWidth(fitDefault)

        let transparentBgDefault = Self.transparentBgDefault(for: scope)
        _ = setTransparentBackground(transparentBgDefault)
    }

    deinit {
        if let core {
            vc_destroy(core)
        }
    }

    func updateWaveform(left: [UInt8], right: [UInt8], sampleRate: Double) {
        guard let core else { return }
        guard !left.isEmpty, !right.isEmpty else { return }

        left.withUnsafeBufferPointer { l in
            right.withUnsafeBufferPointer { r in
                vc_set_waveform_u8(
                    core,
                    l.baseAddress,
                    r.baseAddress,
                    min(l.count, r.count),
                    sampleRate
                )
            }
        }
    }

    func renderFrame(width: Int, height: Int) -> Data {
        guard let core, width > 0, height > 0 else { return Data() }
        var data = Data(count: width * height * 4)
        data.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            vc_render_rgba(core, base, Int32(width), Int32(height), width * 4)
        }
        return data
    }

    @discardableResult
    func renderFrame(width: Int, height: Int, into buffer: inout [UInt8]) -> Bool {
        guard let core, width > 0, height > 0 else { return false }
        let expectedCount = width * height * 4
        if buffer.count != expectedCount {
            buffer = Array(repeating: 0, count: expectedCount)
        }
        return buffer.withUnsafeMutableBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return false }
            vc_render_rgba(core, base, Int32(width), Int32(height), width * 4)
            return true
        }
    }

    @discardableResult
    func loadProfile(url: URL) -> Bool {
        guard let core else { return false }
        let ok = url.path.withCString { cPath in
            vc_load_profile_ini(core, cPath) == 1
        }
        if ok {
            currentProfileURL = url
            currentProfileName = url.deletingPathExtension().lastPathComponent
            UserDefaults.standard.set(currentProfileName, forKey: preferenceScope.lastProfileNameKey)
            let fitDefault = Self.fitToWidthDefault(for: preferenceScope)
            _ = setFitToWidth(fitDefault)
        }
        return ok
    }

    @discardableResult
    func setFitToWidth(_ enabled: Bool) -> Bool {
        guard let core else { return false }
        let value: Int32 = enabled ? 1 : 0
        let ok = vc_set_option(core, "FitToWidth", value) == 1
        if ok {
            UserDefaults.standard.set(enabled, forKey: preferenceScope.fitToWidthKey)
        }
        return ok
    }

    func fitToWidthEnabled() -> Bool {
        guard let core else { return true }
        var value: Int32 = 1
        guard vc_get_option(core, "FitToWidth", &value) == 1 else { return true }
        return value != 0
    }

    @discardableResult
    func setTransparentBackground(_ enabled: Bool) -> Bool {
        guard let core else { return false }
        let value: Int32 = enabled ? 1 : 0
        let ok = vc_set_option(core, "transparentbg", value) == 1
        if ok {
            UserDefaults.standard.set(enabled, forKey: preferenceScope.transparentBgKey)
        }
        return ok
    }

    func transparentBackgroundEnabled() -> Bool {
        guard let core else { return false }
        var value: Int32 = 0
        guard vc_get_option(core, "transparentbg", &value) == 1 else { return false }
        return value != 0
    }

    @discardableResult
    func loadProfile(named name: String) -> Bool {
        guard let profile = availableProfiles().first(where: { $0.name == name }) else {
            return false
        }
        return loadProfile(url: profile.url)
    }

    @discardableResult
    func saveCurrentProfile(to url: URL) -> Bool {
        guard let core else { return false }
        let ok = url.path.withCString { cPath in
            vc_save_profile_ini(core, cPath) == 1
        }
        if ok {
            currentProfileURL = url
            currentProfileName = url.deletingPathExtension().lastPathComponent
            UserDefaults.standard.set(currentProfileName, forKey: preferenceScope.lastProfileNameKey)
        }
        return ok
    }

    @discardableResult
    func saveCurrentProfileAsUserNamed(_ name: String) -> Bool {
        let url = Self.userProfilesDirectory.appendingPathComponent(name).appendingPathExtension("ini")
        return saveCurrentProfile(to: url)
    }

    @discardableResult
    func importProfile(from source: URL) -> Bool {
        let fm = FileManager.default
        let baseName = source.deletingPathExtension().lastPathComponent
        var target = Self.userProfilesDirectory.appendingPathComponent(baseName).appendingPathExtension("ini")
        var suffix = 2
        while fm.fileExists(atPath: target.path) {
            target = Self.userProfilesDirectory.appendingPathComponent("\(baseName) \(suffix)").appendingPathExtension("ini")
            suffix += 1
        }

        do {
            try fm.copyItem(at: source, to: target)
            return loadProfile(url: target)
        } catch {
            return false
        }
    }

    func availableProfiles() -> [ProfileEntry] {
        Self.availableProfilesCatalog()
    }

    static func availableProfilesCatalog() -> [ProfileEntry] {
        var byName: [String: ProfileEntry] = [:]

        let fm = FileManager.default
        if let bundled = bundledProfilesDirectory,
           let items = try? fm.contentsOfDirectory(at: bundled, includingPropertiesForKeys: nil) {
            for url in items where url.pathExtension.lowercased() == "ini" {
                let name = url.deletingPathExtension().lastPathComponent
                byName[name] = ProfileEntry(name: name, url: url, isUserProfile: false)
            }
        }

        if let items = try? fm.contentsOfDirectory(at: userProfilesDirectory, includingPropertiesForKeys: nil) {
            for url in items where url.pathExtension.lowercased() == "ini" {
                let name = url.deletingPathExtension().lastPathComponent
                byName[name] = ProfileEntry(name: name, url: url, isUserProfile: true)
            }
        }

        return byName.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func lastProfileName(for scope: PreferenceScope = .spectrumWindow) -> String? {
        let defaults = UserDefaults.standard
        return defaults.string(forKey: scope.lastProfileNameKey)
            ?? defaults.string(forKey: legacyLastProfileNameKey)
    }

    static func fitToWidthDefault(for scope: PreferenceScope = .spectrumWindow) -> Bool {
        let defaults = UserDefaults.standard
        if let scoped = defaults.object(forKey: scope.fitToWidthKey) as? Bool {
            return scoped
        }
        if let legacy = defaults.object(forKey: legacyFitToWidthKey) as? Bool {
            return legacy
        }
        return true
    }

    static func transparentBgDefault(for scope: PreferenceScope = .spectrumWindow) -> Bool {
        return UserDefaults.standard.bool(forKey: scope.transparentBgKey)
    }

    static func opacityDefault(for scope: PreferenceScope = .spectrumWindow) -> Double? {
        let defaults = UserDefaults.standard
        guard let value = defaults.object(forKey: scope.opacityKey) as? NSNumber else {
            return nil
        }
        return max(0.0, min(1.0, value.doubleValue))
    }

    @discardableResult
    func loadNextProfile() -> Bool {
        let profiles = availableProfiles()
        guard !profiles.isEmpty else { return false }
        guard let current = currentProfileName,
              let idx = profiles.firstIndex(where: { $0.name == current }) else {
            return loadProfile(url: profiles[0].url)
        }
        return loadProfile(url: profiles[(idx + 1) % profiles.count].url)
    }

    @discardableResult
    func loadPreviousProfile() -> Bool {
        let profiles = availableProfiles()
        guard !profiles.isEmpty else { return false }
        guard let current = currentProfileName,
              let idx = profiles.firstIndex(where: { $0.name == current }) else {
            return loadProfile(url: profiles[0].url)
        }
        let prev = (idx - 1 + profiles.count) % profiles.count
        return loadProfile(url: profiles[prev].url)
    }

    static var userProfilesDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NullPlayer")
            .appendingPathComponent("vis_classic")
            .appendingPathComponent("profiles")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static var bundledProfilesDirectory: URL? {
        if let url = BundleHelper.url(forResource: "profiles", withExtension: nil, subdirectory: "vis_classic") {
            return url
        }

        if let resourceURL = Bundle.main.resourceURL {
            let direct = resourceURL.appendingPathComponent("vis_classic").appendingPathComponent("profiles")
            if FileManager.default.fileExists(atPath: direct.path) {
                return direct
            }
            let nested = resourceURL.appendingPathComponent("Resources/vis_classic/profiles")
            if FileManager.default.fileExists(atPath: nested.path) {
                return nested
            }
        }

        return nil
    }

    private func ensureProfilesBootstrapped() {
        let fm = FileManager.default
        let userDir = Self.userProfilesDirectory

        let existing = (try? fm.contentsOfDirectory(at: userDir, includingPropertiesForKeys: nil)) ?? []
        if !existing.isEmpty { return }

        guard let bundled = Self.bundledProfilesDirectory,
              let bundledProfiles = try? fm.contentsOfDirectory(at: bundled, includingPropertiesForKeys: nil) else {
            return
        }

        for src in bundledProfiles where src.pathExtension.lowercased() == "ini" {
            let dst = userDir.appendingPathComponent(src.lastPathComponent)
            try? fm.copyItem(at: src, to: dst)
        }
    }
}
