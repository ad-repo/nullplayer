import AppKit

/// **Show Artist / Show Album** — which fields every skin family's playlist rows draw,
/// `Artist - Title - Album` as the two toggles allow. Every playlist menu adds them here.
struct PlaylistRowFields {
    var showArtist = true
    var showAlbum = false

    /// Both default false, so the default row is `Artist - Title`.
    static let hideArtistKey = "playlistHideArtist"
    static let showAlbumKey = "playlistShowAlbum"

    static var current: PlaylistRowFields {
        let defaults = UserDefaults.standard
        return PlaylistRowFields(showArtist: !defaults.bool(forKey: hideArtistKey),
                                 showAlbum: defaults.bool(forKey: showAlbumKey))
    }

    func text(for track: Track) -> String {
        text(title: track.title, artist: track.artist, album: track.album, isVideo: track.mediaType == .video)
    }

    /// `.wal` and `.wmz` rows are not `Track`s, so they pass their own fields.
    func text(title: String, artist: String?, album: String?, isVideo: Bool) -> String {
        var parts = [title]
        if showArtist, let artist, !artist.isEmpty { parts.insert(artist, at: 0) }
        if showAlbum, let album, !album.isEmpty { parts.append(album) }
        // Remove newlines and other control characters that break playlist display
        let text = parts.joined(separator: " - ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        return isVideo ? "\(MediaType.video.rowMarker) \(text)" : text
    }

    @MainActor
    static func addItems(to menu: NSMenu) {
        let fields = current
        menu.addItem(.separator())
        for (title, key, isOn) in [("Show Artist", hideArtistKey, fields.showArtist),
                                   ("Show Album", showAlbumKey, fields.showAlbum)] {
            let item = NSMenuItem(title: title, action: #selector(MenuTarget.toggle(_:)), keyEquivalent: "")
            item.target = MenuTarget.shared
            item.representedObject = key
            item.state = isOn ? .on : .off
            menu.addItem(item)
        }
    }

    /// `NSMenuItem.target` is weak, so the items share one long-lived target.
    @MainActor
    private final class MenuTarget: NSObject {
        static let shared = MenuTarget()

        @objc func toggle(_ sender: NSMenuItem) {
            guard let key = sender.representedObject as? String else { return }
            UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: key), forKey: key)
            WindowManager.shared.redrawPlaylistViews()
        }
    }
}
