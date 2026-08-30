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
        notificationCenter.post(name: .reeltoneSkinDidChange, object: self)
    }
}
