import Foundation

/// One active colour theme per loaded skin, and everyone who has to repaint when it changes.
///
/// A `.wal` colour theme (`<gammaset>`) is a property of the *skin*, not of a window: MMD3 ships 83 of
/// them and switching one is meant to recolour the player, the playlist window, and every embedded
/// surface at once. Each renderer used to build its own `WasabiColorThemeCatalog` from the same
/// document, so a theme switch in the player left the playlist window on the old colours until
/// something else happened to invalidate its bitmap cache.
///
/// The catalog now lives here, once, and every renderer, hosted AppKit view, and palette consumer
/// subscribes. Each subscriber still owns its own bounded bitmap cache — the notification tells it to
/// drop and redraw, it does not share pixels.
final class WinampModernThemeCoordinator {
    let catalog: WasabiColorThemeCatalog

    private var observers: [(token: ObjectIdentifier, onChange: () -> Void)] = []

    init(loadedSkin: WinampModernLoadedSkin) {
        self.catalog = WasabiColorThemeCatalog(loadedSkin: loadedSkin)
    }

    var activeTheme: String { catalog.activeTheme }
    var themeNames: [String] { catalog.themeNames }

    /// Subscribe `token`'s repaint. Re-subscribing the same token replaces its callback, so a view
    /// rebuilt against the same skin cannot accumulate duplicates.
    func addObserver(_ token: AnyObject, onChange: @escaping () -> Void) {
        let id = ObjectIdentifier(token)
        observers.removeAll { $0.token == id }
        observers.append((id, onChange))
    }

    func removeObserver(_ token: AnyObject) {
        let id = ObjectIdentifier(token)
        observers.removeAll { $0.token == id }
    }

    /// Switch themes and tell everyone. Returns false when the name is unknown or already active, so
    /// callers can skip a redraw.
    @discardableResult
    func activate(_ name: String) -> Bool {
        guard catalog.activate(name) else { return false }
        for observer in observers { observer.onChange() }
        return true
    }

    func transform(group: String?) -> WasabiGammaTransform? { catalog.transform(group: group) }
}
