import Foundation

extension Notification.Name {
    static let reeltoneSkinDidChange = Notification.Name("ReeltoneSkinDidChange")
}

/// Phase-2 ownership boundary for validated Reeltone packages and selection state.
/// Rendering and surface reconciliation remain owned by later phases.
final class ReeltoneSkinEngine {
    static let shared = ReeltoneSkinEngine()

    private(set) var currentInstallation: ReeltoneInstalledSkin?
    private(set) var currentSkin: ReeltoneLoadedSkin?
    private(set) var currentTheme = ReeltoneThemeAdapter(manifest: nil)
    private(set) var preferredSkinLoadDiagnostic: ReeltoneDiagnostic?

    private let store: ReeltoneSkinStore
    private let defaults: UserDefaults
    private let notificationCenter: NotificationCenter

    init(
        store: ReeltoneSkinStore = ReeltoneSkinStore(),
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) {
        self.store = store
        self.defaults = defaults
        self.notificationCenter = notificationCenter
    }

    var availableSkins: ReeltoneDiscoveryResult { store.discover() }

    @discardableResult
    func loadPreferredSkin() throws -> ReeltoneLoadedSkin? {
        guard let preferred = store.preferredSkin(in: defaults) else {
            replaceCurrent(with: nil, installation: nil)
            return nil
        }
        let loaded = try store.load(preferred)
        replaceCurrent(with: loaded, installation: preferred)
        return loaded
    }

    /// Restore the preferred installation when possible and deterministically fall back to the
    /// built-in Reeltone palette when the preference is missing, stale, or no longer valid.
    @discardableResult
    func activatePreferredTheme() -> ReeltoneThemeAdapter {
        preferredSkinLoadDiagnostic = nil
        let hadPreferredIdentity = ReeltoneSkinState.selectedSkinIdentity(in: defaults) != nil
        do {
            let loaded = try loadPreferredSkin()
            if hadPreferredIdentity, loaded == nil {
                store.selectPreferred(nil, in: defaults)
            }
        } catch let diagnostic as ReeltoneDiagnostic {
            preferredSkinLoadDiagnostic = diagnostic
            store.selectPreferred(nil, in: defaults)
            replaceCurrent(with: nil, installation: nil)
        } catch {
            preferredSkinLoadDiagnostic = ReeltoneDiagnostic(
                code: .storeFailure,
                message: "The preferred Reeltone skin could not be loaded: \(error.localizedDescription)"
            )
            store.selectPreferred(nil, in: defaults)
            replaceCurrent(with: nil, installation: nil)
        }
        return currentTheme
    }

    func selectDefaultTheme() {
        store.selectPreferred(nil, in: defaults)
        replaceCurrent(with: nil, installation: nil)
    }

    @discardableResult
    func installAndSelect(archiveAt url: URL) throws -> ReeltoneLoadedSkin {
        let installation = try store.install(archiveAt: url)
        let loaded = try store.load(installation)
        store.selectPreferred(installation, in: defaults)
        replaceCurrent(with: loaded, installation: installation)
        return loaded
    }

    @discardableResult
    func select(identity: String) throws -> ReeltoneLoadedSkin {
        guard let installation = store.discover().installations.first(where: { $0.record.identity == identity }) else {
            throw ReeltoneDiagnostic(code: .installationNotFound, message: "Reeltone installation was not found")
        }
        let loaded = try store.load(installation)
        store.selectPreferred(installation, in: defaults)
        replaceCurrent(with: loaded, installation: installation)
        return loaded
    }

    func remove(identity: String) throws {
        let removedCurrent = currentInstallation?.record.identity == identity
        try store.remove(identity: identity, defaults: defaults)
        if removedCurrent { replaceCurrent(with: nil, installation: nil) }
    }

    private func replaceCurrent(with skin: ReeltoneLoadedSkin?, installation: ReeltoneInstalledSkin?) {
        currentSkin?.close()
        currentSkin = skin
        currentInstallation = installation
        currentTheme = ReeltoneThemeAdapter(manifest: skin?.manifest)
        notificationCenter.post(name: .reeltoneSkinDidChange, object: self)
    }
}
