import Foundation

/// A skin family's saved choice: the installed skin's name under `key`. WMP pairs it with a view id
/// and keeps that itself.
struct SkinSelection {
    let key: String
    let defaults: UserDefaults

    var name: String? { defaults.string(forKey: key) }

    func select(_ name: String) { defaults.set(name, forKey: key) }

    func reset() { defaults.removeObject(forKey: key) }

    /// After `name` is removed: the selection, if it was that skin, is cleared.
    func forget(_ name: String) {
        if self.name == name { reset() }
    }
}
