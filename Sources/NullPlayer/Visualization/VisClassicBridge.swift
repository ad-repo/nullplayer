import Foundation
import CVisClassicCore

final class VisClassicBridge {
    // Serializes all calls into the C++ core, which is not thread-safe.
    // The CVDisplayLink thread calls renderFrame() concurrently with main-thread
    // profile/option mutations — without this lock, setupFFT() (which calls
    // fft_.CleanUp() and sets bitrevtable=0) races with time_to_frequency_domain
    // reading bitrevtable, producing a null-dereference crash.
    private let coreLock = NSLock()

    enum PreferenceScope {
        case spectrumWindow
        case mainWindow
        /// A `.wal` skin's own `<vis>` box (B53). Its own keys, per CLAUDE.md's rule that
        /// vis_classic state is window-scoped: a profile picked inside a skin must not move the
        /// dedicated spectrum window's, and a skin embedding must not be able to write over either.
        case winampModernVisBox

        var lastProfileNameKey: String {
            switch self {
            case .spectrumWindow: return "visClassicLastProfileName.spectrumWindow"
            case .mainWindow: return "visClassicLastProfileName.mainWindow"
            case .winampModernVisBox: return "visClassicLastProfileName.winampModernVisBox"
            }
        }

        var fitToWidthKey: String {
            switch self {
            case .spectrumWindow: return "visClassicFitToWidth.spectrumWindow"
            case .mainWindow: return "visClassicFitToWidth.mainWindow"
            case .winampModernVisBox: return "visClassicFitToWidth.winampModernVisBox"
            }
        }

        var transparentBgKey: String {
            switch self {
            case .spectrumWindow: return "visClassicTransparentBg.spectrumWindow"
            case .mainWindow: return "visClassicTransparentBg.mainWindow"
            case .winampModernVisBox: return "visClassicTransparentBg.winampModernVisBox"
            }
        }

        var opacityKey: String {
            switch self {
            case .spectrumWindow: return "visClassicOpacity.spectrumWindow"
            case .mainWindow: return "visClassicOpacity.mainWindow"
            case .winampModernVisBox: return "visClassicOpacity.winampModernVisBox"
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
    private let defaults: UserDefaults
    private(set) var currentProfileName: String?
    private(set) var currentProfileURL: URL?
    private static let legacyLastProfileNameKey = "visClassicLastProfileName"
    private static let legacyFitToWidthKey = "visClassicFitToWidth"

    init?(
        width: Int,
        height: Int,
        scope: PreferenceScope = .spectrumWindow,
        defaults: UserDefaults = .standard
    ) {
        guard let handle = vc_create(Int32(width), Int32(height)) else {
            return nil
        }
        core = handle
        preferenceScope = scope
        self.defaults = defaults

        ensureProfilesBootstrapped()
        let profiles = availableProfiles()
        if let lastName = Self.lastProfileName(for: scope, defaults: defaults),
           let lastProfile = profiles.first(where: { $0.name == lastName }) {
            _ = loadProfile(url: lastProfile.url)
        } else if let defaultProfile = profiles.first {
            _ = loadProfile(url: defaultProfile.url)
        }

        let fitDefault = Self.fitToWidthDefault(for: scope, defaults: defaults)
        _ = setFitToWidth(fitDefault)

        let transparentDefault = Self.transparentBgDefault(for: scope, defaults: defaults)
        _ = setTransparentBackground(transparentDefault)
    }

    deinit {
        if let core {
            vc_destroy(core)
        }
    }

    /// Set reference width for band computation — call once after creation.
    @discardableResult
    func setReferenceWidth(_ width: Int) -> Bool {
        guard let core else { return false }
        return coreLock.withLock { vc_set_option(core, "referencewidth", Int32(width)) == 1 }
    }

    /// Process waveform + run FFT — call once per audio chunk, not per render frame.
    func processUpdate(leftData: [UInt8], rightData: [UInt8], sampleRate: Double) {
        guard let core else { return }
        coreLock.withLock {
            leftData.withUnsafeBufferPointer { lp in
                rightData.withUnsafeBufferPointer { rp in
                    vc_set_waveform_u8(core, lp.baseAddress, rp.baseAddress,
                                       leftData.count, sampleRate)
                }
            }
            vc_process_frame_only(core)
        }
    }

    /// Render current state at given canvas size — call per display frame, no FFT.
    func drawAtSize(width: Int, height: Int, into buffer: inout [UInt8], stride: Int) {
        guard let core else { return }
        let needed = stride * height
        if buffer.count < needed { buffer = [UInt8](repeating: 0, count: needed) }
        coreLock.withLock {
            buffer.withUnsafeMutableBufferPointer { bp in
                _ = vc_draw_at_size(core, bp.baseAddress, Int32(width), Int32(height), Int32(stride))
            }
        }
    }

    /// Process and draw atomically — prevents another view from calling processUpdate
    /// between this view's processUpdate and drawAtSize on the shared bridge.
    func processAndDraw(leftData: [UInt8], rightData: [UInt8], sampleRate: Double,
                        width: Int, height: Int, into buffer: inout [UInt8], stride: Int) {
        guard let core else { return }
        let needed = stride * height
        if buffer.count < needed { buffer = [UInt8](repeating: 0, count: needed) }
        coreLock.withLock {
            leftData.withUnsafeBufferPointer { lp in
                rightData.withUnsafeBufferPointer { rp in
                    vc_set_waveform_u8(core, lp.baseAddress, rp.baseAddress,
                                       leftData.count, sampleRate)
                }
            }
            vc_process_frame_only(core)
            buffer.withUnsafeMutableBufferPointer { bp in
                _ = vc_draw_at_size(core, bp.baseAddress, Int32(width), Int32(height), Int32(stride))
            }
        }
    }

    func updateWaveform(left: [UInt8], right: [UInt8], sampleRate: Double) {
        guard let core else { return }
        guard !left.isEmpty, !right.isEmpty else { return }

        coreLock.withLock {
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
    }

    func renderFrame(width: Int, height: Int) -> Data {
        guard let core, width > 0, height > 0 else { return Data() }
        var data = Data(count: width * height * 4)
        coreLock.withLock {
            data.withUnsafeMutableBytes { raw in
                guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                vc_render_rgba(core, base, Int32(width), Int32(height), width * 4)
            }
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
        return coreLock.withLock {
            buffer.withUnsafeMutableBufferPointer { ptr in
                guard let base = ptr.baseAddress else { return false }
                vc_render_rgba(core, base, Int32(width), Int32(height), width * 4)
                return true
            }
        }
    }

    @discardableResult
    func loadProfile(url: URL) -> Bool {
        guard let core else { return false }
        let ok = coreLock.withLock {
            url.path.withCString { cPath in
                vc_load_profile_ini(core, cPath) == 1
            }
        }
        if ok {
            currentProfileURL = url
            currentProfileName = url.deletingPathExtension().lastPathComponent
            defaults.set(currentProfileName, forKey: preferenceScope.lastProfileNameKey)
            let fitDefault = Self.fitToWidthDefault(for: preferenceScope, defaults: defaults)
            _ = setFitToWidth(fitDefault)
        }
        return ok
    }

    @discardableResult
    func setFitToWidth(_ enabled: Bool) -> Bool {
        guard let core else { return false }
        let value: Int32 = enabled ? 1 : 0
        let ok = coreLock.withLock { vc_set_option(core, "FitToWidth", value) == 1 }
        if ok {
            defaults.set(enabled, forKey: preferenceScope.fitToWidthKey)
        }
        return ok
    }

    func fitToWidthEnabled() -> Bool {
        guard let core else { return true }
        var value: Int32 = 1
        let got = coreLock.withLock { vc_get_option(core, "FitToWidth", &value) == 1 }
        return got ? value != 0 : true
    }

    @discardableResult
    func setTransparentBackground(_ enabled: Bool) -> Bool {
        guard let core else { return false }
        let value: Int32 = enabled ? 1 : 0
        let ok = coreLock.withLock { vc_set_option(core, "transparentbg", value) == 1 }
        if ok {
            defaults.set(enabled, forKey: preferenceScope.transparentBgKey)
        }
        return ok
    }

    func transparentBackgroundEnabled() -> Bool {
        guard let core else { return false }
        var value: Int32 = 0
        let got = coreLock.withLock { vc_get_option(core, "transparentbg", &value) == 1 }
        return got ? value != 0 : false
    }

    /// Rehydrate every persisted, window-scoped renderer setting.
    ///
    /// WindowManager caches bridges across UI-family rebuilds, so changing UserDefaults alone
    /// is insufficient: profile loading updates the profile and fit-to-width option, but the
    /// C++ transparent-background option is independent and otherwise remains stale.
    func reloadPersistedSettings() {
        if let name = Self.lastProfileName(for: preferenceScope, defaults: defaults) {
            _ = loadProfile(named: name)
        }
        _ = setFitToWidth(Self.fitToWidthDefault(for: preferenceScope, defaults: defaults))
        _ = setTransparentBackground(Self.transparentBgDefault(for: preferenceScope, defaults: defaults))
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
        let ok = coreLock.withLock {
            url.path.withCString { cPath in
                vc_save_profile_ini(core, cPath) == 1
            }
        }
        if ok {
            currentProfileURL = url
            currentProfileName = url.deletingPathExtension().lastPathComponent
            defaults.set(currentProfileName, forKey: preferenceScope.lastProfileNameKey)
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

    static func lastProfileName(
        for scope: PreferenceScope = .spectrumWindow,
        defaults: UserDefaults = .standard
    ) -> String? {
        return defaults.string(forKey: scope.lastProfileNameKey)
            ?? defaults.string(forKey: legacyLastProfileNameKey)
    }

    static func fitToWidthDefault(
        for scope: PreferenceScope = .spectrumWindow,
        defaults: UserDefaults = .standard
    ) -> Bool {
        if let scoped = defaults.object(forKey: scope.fitToWidthKey) as? Bool {
            return scoped
        }
        if let legacy = defaults.object(forKey: legacyFitToWidthKey) as? Bool {
            return legacy
        }
        return true
    }

    static func transparentBgDefault(
        for scope: PreferenceScope = .spectrumWindow,
        defaults: UserDefaults = .standard
    ) -> Bool {
        if let scoped = defaults.object(forKey: scope.transparentBgKey) as? Bool {
            return scoped
        }
        // A `.wal` skin's `<vis>` box is a recess its author drew, and the analyzer that normally
        // lives there paints only its bars — an opaque black rectangle would cover the artwork.
        if scope == .winampModernVisBox {
            return true
        }
        // Metal finishes default to a transparent vis_classic background so the analyzer
        // bars sit on the brushed-metal chrome instead of an opaque black box. Only the
        // main-window scope is defaulted; the dedicated spectrum window keeps its own seed.
        if scope == .mainWindow && WindowManager.shared.uiMode == .metal {
            return true
        }
        return false
    }

    static func opacityDefault(
        for scope: PreferenceScope = .spectrumWindow,
        defaults: UserDefaults = .standard
    ) -> Double? {
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
