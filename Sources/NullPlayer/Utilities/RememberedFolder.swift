import Foundation

/// A user-chosen folder remembered across launches. A sandboxed build (the App Store one) loses an
/// `NSOpenPanel` grant at quit, so the folder is also kept as a security-scoped bookmark. The plain
/// path stays the fallback: the Developer ID build reads it, and so does a setting saved before
/// bookmarks.
final class RememberedFolder: @unchecked Sendable {  // `lock` guards the opened bookmark
    let pathKey: String
    var bookmarkKey: String { pathKey + ".bookmark" }

    private let lock = NSLock()
    private var openedData: Data?  // the bookmark `openedURL` was resolved from
    private var openedURL: URL?    // holds the folder's security scope while it is the choice

    init(pathKey: String) {
        self.pathKey = pathKey
    }

    deinit {
        openedURL?.stopAccessingSecurityScopedResource()
    }

    /// The folder: its bookmark when that opens, else the saved path. A bookmark that fails to open
    /// (a volume not mounted yet) is tried again on the next read.
    var url: URL? {
        let defaults = UserDefaults.standard
        let opened: URL? = lock.withLock {
            let data = defaults.data(forKey: bookmarkKey)
            if data != openedData {
                openedURL?.stopAccessingSecurityScopedResource()
                openedURL = data.flatMap { Self.open($0, bookmarkKey: bookmarkKey) }
                openedData = openedURL == nil ? nil : defaults.data(forKey: bookmarkKey)  // refreshed when stale
            }
            return openedURL
        }
        return opened ?? defaults.string(forKey: pathKey).map { URL(fileURLWithPath: $0) }
    }

    var path: String? { url?.path }

    /// Remembers `url`, a folder the user just chose, or forgets the folder when nil.
    func set(_ url: URL?) {
        let defaults = UserDefaults.standard
        lock.withLock {  // so a read on another thread never pairs one folder's URL with another's bookmark
            defaults.set(url?.path, forKey: pathKey)
            defaults.set(url.flatMap(Self.bookmark), forKey: bookmarkKey)
        }
    }

    private static func bookmark(_ url: URL) -> Data? {
        try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                              includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// Resolves and opens a bookmark, saving a fresh one when it is stale.
    private static func open(_ data: Data, bookmarkKey: String) -> URL? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource() else { return nil }
        if stale, let fresh = bookmark(url) {
            UserDefaults.standard.set(fresh, forKey: bookmarkKey)
        }
        return url
    }
}
