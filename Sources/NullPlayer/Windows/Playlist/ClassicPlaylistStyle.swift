import AppKit

/// **Playlist Style**: the Classic playlist as NullPlayer draws it (thin border, no controls), or
/// the standard Winamp 2 playlist editor (`PlaylistView+WinampStyle.swift`), the default.
///
/// Classic UI only: every other family's fallback playlist and the compact library's embedded one
/// keep the NullPlayer look (`PlaylistView.isWinampStyle`).
enum ClassicPlaylistStyle: String, CaseIterable {
    case nullPlayer, winamp

    static let defaultsKey = "classicPlaylistStyle"

    /// Read once and kept, since the playlist asks on every layout pass; setting it saves the
    /// choice and redraws every playlist.
    @MainActor
    static var current: ClassicPlaylistStyle = stored {
        didSet {
            UserDefaults.standard.set(current.rawValue, forKey: defaultsKey)
            WindowManager.shared.redrawPlaylistViews()
        }
    }

    private static var stored: ClassicPlaylistStyle {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(Self.init(rawValue:)) ?? .winamp
    }

    var title: String {
        switch self {
        case .nullPlayer: return "NullPlayer"
        case .winamp: return "Winamp Classic"
        }
    }
}
