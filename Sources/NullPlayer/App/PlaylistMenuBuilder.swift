import AppKit

/// The actions NullPlayer's playlist context menu sends. A view that shows the play queue and keeps
/// a row selection conforms, and `PlaylistMenuBuilder` wires the menu to it.
@MainActor
@objc protocol PlaylistMenuTarget: AnyObject {
    func playSelected(_ sender: Any?)
    func removeSelected(_ sender: Any?)
    func removeAll(_ sender: Any?)
    func removeDeadFiles(_ sender: Any?)
    func selectAll(_ sender: Any?)
    func selectNone(_ sender: Any?)
    func invertSelection(_ sender: Any?)
    func cropSelection(_ sender: Any?)
    func sortByTitle(_ sender: Any?)
    func sortByArtist(_ sender: Any?)
    func sortByAlbum(_ sender: Any?)
    func sortByFilename(_ sender: Any?)
    func sortByPath(_ sender: Any?)
    func reverse(_ sender: Any?)
    func randomize(_ sender: Any?)
    func showFileInfo(_ sender: Any?)
}

/// **NullPlayer's playlist context menu, shared by every view that shows the play queue.** The
/// Modern playlist built it inline; a `.wmz` skin's `<PLAYLIST>` pane needs the same rows because
/// WMP skins authored no playlist controls of their own — WMP's menus supplied them (W272). Lifted
/// here rather than reached for in `ModernPlaylistView`, which WMP code may not depend on.
@MainActor
enum PlaylistMenuBuilder {
    struct State {
        var selectionCount: Int
        var hasTracks: Bool
        /// False while the view shows something other than the live queue (a `.wmz` library
        /// preview), so every row that edits the queue is disabled.
        var canEdit = true
        /// The selected queue rows' tracks, for **Assign EQ Profile**; empty hides it.
        var selectedTracks: [Track] = []
        var hasSelection: Bool { selectionCount > 0 }
    }

    /// `autoenablesItems` stays AppKit's default for the Modern playlist, which never validated
    /// these rows — so its `isEnabled` values have always been overridden to enabled, and are kept
    /// exactly as they were. A caller whose disabled rows must hold passes `false`.
    static func menu(target: PlaylistMenuTarget, state: State, autoenablesItems: Bool = true) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = autoenablesItems
        let hasSelection = state.hasSelection, hasTracks = state.hasTracks, canEdit = state.canEdit

        func item(_ title: String, _ action: Selector, enabled: Bool, key: String = "") -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = target
            item.isEnabled = enabled
            return item
        }

        menu.addItem(item("Play", #selector(PlaylistMenuTarget.playSelected(_:)), enabled: hasSelection))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item("Remove Selected", #selector(PlaylistMenuTarget.removeSelected(_:)),
                          enabled: hasSelection && canEdit))
        menu.addItem(item("Clear Playlist", #selector(PlaylistMenuTarget.removeAll(_:)),
                          enabled: hasTracks && canEdit))
        menu.addItem(item("Remove Dead Files", #selector(PlaylistMenuTarget.removeDeadFiles(_:)),
                          enabled: hasTracks && canEdit))
        menu.addItem(NSMenuItem.separator())

        let selectionMenu = NSMenu()
        selectionMenu.autoenablesItems = autoenablesItems
        let selectAllItem = item("Select All", #selector(PlaylistMenuTarget.selectAll(_:)),
                                 enabled: hasTracks, key: "a")
        selectAllItem.keyEquivalentModifierMask = .command
        selectionMenu.addItem(selectAllItem)
        selectionMenu.addItem(item("Select None", #selector(PlaylistMenuTarget.selectNone(_:)),
                                   enabled: hasSelection))
        selectionMenu.addItem(item("Invert Selection", #selector(PlaylistMenuTarget.invertSelection(_:)),
                                   enabled: hasTracks))
        selectionMenu.addItem(item("Crop Selection", #selector(PlaylistMenuTarget.cropSelection(_:)),
                                   enabled: hasSelection && canEdit))
        let selectionMenuItem = NSMenuItem(title: "Selection", action: nil, keyEquivalent: "")
        selectionMenuItem.submenu = selectionMenu
        menu.addItem(selectionMenuItem)

        let sortMenu = NSMenu()
        sortMenu.autoenablesItems = autoenablesItems
        let canSort = hasTracks && canEdit
        sortMenu.addItem(item("Sort by Title", #selector(PlaylistMenuTarget.sortByTitle(_:)), enabled: canSort))
        sortMenu.addItem(item("Sort by Artist", #selector(PlaylistMenuTarget.sortByArtist(_:)), enabled: canSort))
        sortMenu.addItem(item("Sort by Album", #selector(PlaylistMenuTarget.sortByAlbum(_:)), enabled: canSort))
        sortMenu.addItem(item("Sort by Filename", #selector(PlaylistMenuTarget.sortByFilename(_:)),
                              enabled: canSort))
        sortMenu.addItem(item("Sort by Path", #selector(PlaylistMenuTarget.sortByPath(_:)), enabled: canSort))
        sortMenu.addItem(NSMenuItem.separator())
        sortMenu.addItem(item("Reverse", #selector(PlaylistMenuTarget.reverse(_:)), enabled: canSort))
        sortMenu.addItem(item("Randomize", #selector(PlaylistMenuTarget.randomize(_:)), enabled: canSort))
        let sortMenuItem = NSMenuItem(title: "Sort", action: nil, keyEquivalent: "")
        sortMenuItem.submenu = sortMenu
        menu.addItem(sortMenuItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(item("File Info...", #selector(PlaylistMenuTarget.showFileInfo(_:)),
                          enabled: state.selectionCount == 1 && canEdit))
        let selectedTracks = state.selectedTracks
        if !selectedTracks.isEmpty {
            EQProfileMenu.addAssignItem(to: menu, level: .track, tracks: selectedTracks)
        }
        return menu
    }

    // MARK: - Queue edits both views make

    static func removeTracks(at indices: Set<Int>) {
        let engine = WindowManager.shared.audioEngine
        for index in indices.sorted(by: >) {
            engine.removeTrack(at: index)
        }
    }

    /// Remove every track not in `indices`.
    static func cropPlaylist(to indices: Set<Int>) {
        removeTracks(at: Set(0..<WindowManager.shared.audioEngine.playlist.count).subtracting(indices))
    }

    static func removeDeadFiles() {
        let engine = WindowManager.shared.audioEngine
        var indicesToRemove: [Int] = []
        for (index, track) in engine.playlist.enumerated() {
            if !track.url.isFileURL || !FileManager.default.fileExists(atPath: track.url.path) {
                indicesToRemove.append(index)
            }
        }
        for index in indicesToRemove.reversed() {
            engine.removeTrack(at: index)
        }
    }

    static func showFileInfo(forTrackAt index: Int) {
        let tracks = WindowManager.shared.audioEngine.playlist
        guard index < tracks.count else { return }
        let track = tracks[index]
        let alert = NSAlert()
        alert.messageText = track.displayTitle
        alert.informativeText = """
        Artist: \(track.artist ?? "Unknown")
        Album: \(track.album ?? "Unknown")
        Duration: \(String(format: "%d:%02d", Int(track.duration ?? 0) / 60, Int(track.duration ?? 0) % 60))
        Path: \(track.url.path)
        """ + (track.mediaType == .audio ? "\nEQ Profile: \(EQProfileStore.shared.describe(track))" : "")
        alert.runModal()
    }
}
