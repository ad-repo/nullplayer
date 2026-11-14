import Foundation

/// A user-chosen folder remembered across launches. A sandboxed build (the App Store one) loses an
/// `NSOpenPanel` grant at quit, so the folder is also kept as a security-scoped bookmark, opened
/// once per launch. The plain path stays the fallback: the Developer ID build reads it, and so does a
/// setting saved before bookmarks.
final class RememberedFolder: @unchecked Sendable {  // `lock` guards the resolved bookmark
    let pathKey: String
    var bookmarkKey: String { pathKey + ".bookmark" }

    private let lock = NSLock()
    private var resolvedData: Data?  // the bookmark `resolvedURL` came from; a reset or new choice changes it
    private var resolvedURL: URL?

    init(pathKey: String) {
        self.pathKey = pathKey
    }

    var url: URL? {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: bookmarkKey) else {
            return defaults.string(forKey: pathKey).map { URL(fileURLWithPath: $0) }
        }
        return lock.withLock {
            if data != resolvedData {
                resolvedURL?.stopAccessingSecurityScopedResource()
                resolvedURL = Self.open(data, bookmarkKey: bookmarkKey)
                resolvedData = defaults.data(forKey: bookmarkKey)  // refreshed when it was stale
            }
            return resolvedURL ?? defaults.string(forKey: pathKey).map { URL(fileURLWithPath: $0) }
        }
    }

    var path: String? { url?.path }

    /// Remembers `url`, a folder the user just chose, or forgets the folder when nil.
    func set(_ url: URL?) {
        let defaults = UserDefaults.standard
        defaults.set(url?.path, forKey: pathKey)
        defaults.set(try? url?.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                            includingResourceValuesForKeys: nil, relativeTo: nil),
                     forKey: bookmarkKey)
    }

    /// Resolves and opens a bookmark, refreshing it when stale. Access is held until the bookmark
    /// changes, since presets are read from the folder at any time.
    private static func open(_ data: Data, bookmarkKey: String) -> URL? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        guard url.startAccessingSecurityScopedResource() else { return nil }
        if stale, let fresh = try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                                     includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: bookmarkKey)
        }
        return url
    }
}
