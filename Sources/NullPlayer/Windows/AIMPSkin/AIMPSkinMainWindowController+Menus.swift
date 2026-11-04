import AppKit
import NullPlayerCore

/// The menus a skin's keys pop up that NullPlayer has its own of.
extension AIMPSkinMainWindowController {
    /// NullPlayer's menu like one a skin pops up (`AIMPSkinPopup`): the EQ presets; the playlist's
    /// (adding files, taking them out, sorting, its own) over the skin playlist's selected row; and
    /// the library window's (its tree's and table's, grouping presets, removing, the rest) over its
    /// chosen group and track, changing the skin's live state through `update`.
    @MainActor static func popupMenu(_ popup: AIMPSkinPopup, state: AIMPSkinState, library: AIMPSkinLibrary?,
                                     update: @escaping ((inout AIMPSkinState) -> Void) -> Void) -> NSMenu {
        let engine = WindowManager.shared.audioEngine
        let menu = NSMenu()
        // Items honour their own enabled state (Remove with nothing selected).
        menu.autoenablesItems = false
        let selection = state.lists.playlistSelected.flatMap { engine.playlist.indices.contains($0) ? $0 : nil }
        let library = library ?? AIMPSkinLibrary(tracks: [])
        let grouping = state.lists.libraryGrouping
        /// The library tracks a menu acts on: the chosen track, else the chosen group's.
        func libraryItems(_ title: String, track: Bool, run: @escaping ([Track]) -> Void) -> NSMenuItem {
            let ids = track ? [state.lists.librarySelected].compactMap { $0 }
                : library.table(grouping, path: state.lists.libraryPath, search: "").map { library.tracks[$0].id }
            let item = AIMPSkinMenuItem(title: title) { run(library.tracks(ids).map { $0.toTrack() }) }
            item.isEnabled = !ids.isEmpty
            return item
        }
        func libraryPlay(track: Bool) -> [NSMenuItem] {
            [libraryItems("Play", track: track) { tracks in
                 guard !tracks.isEmpty else { return }
                 engine.appendTracks(tracks)
                 engine.playTrack(at: engine.playlist.count - tracks.count)
             },
             libraryItems("Play Next", track: track) { engine.insertTracksAfterCurrent($0) },
             libraryItems("Add to Playlist", track: track) { engine.appendTracks($0) },
             libraryItems("Replace Playlist", track: track) { tracks in
                 guard !tracks.isEmpty else { return }
                 engine.loadTracks(tracks)
             }]
        }
        func groupings(_ menu: NSMenu) {
            for preset in AIMPSkinLibrary.Grouping.allCases {
                let item = AIMPSkinMenuItem(title: preset.title) {
                    update { state in
                        state.lists.libraryGrouping = preset
                        state.lists.libraryPath = ""
                        state.lists.libraryExpanded = []
                        state.lists.libraryTreeTop = 0
                        state.lists.libraryTableTop = 0
                    }
                }
                item.state = preset == grouping ? .on : .off
                menu.addItem(item)
            }
        }
        func libraryRemove() -> NSMenuItem {
            let item = AIMPSkinMenuItem(title: "Remove from Library") {
                guard let id = state.lists.librarySelected else { return }
                library.tracks([id]).first.map(MediaLibrary.shared.removeTrack)
            }
            item.isEnabled = state.lists.librarySelected != nil
            return item
        }
        func libraryAdd(_ menu: NSMenu) {
            menu.addItem(AIMPSkinMenuItem(title: "Add Files or Folders to Library…") { AIMPSkinLibrarySource.addFilesOrFolders() })
            menu.addItem(AIMPSkinMenuItem(title: "Rescan Library") { MediaLibrary.shared.rescanWatchFolders() })
        }
        func remove() -> NSMenuItem {
            let item = AIMPSkinMenuItem(title: "Remove Selected") { if let selection { engine.removeTrack(at: selection) } }
            item.isEnabled = selection != nil
            return item
        }
        func play() -> NSMenuItem {
            let item = AIMPSkinMenuItem(title: "Play") { if let selection { engine.playTrack(at: selection) } }
            item.isEnabled = selection != nil
            return item
        }
        func sorting(_ menu: NSMenu) {
            for (title, criteria) in [("By Title", AudioEngine.SortCriteria.title), ("By Artist", .artist), ("By Album", .album),
                                      ("By File Name", .filename), ("By Path", .path), ("By Duration", .duration)] {
                menu.addItem(AIMPSkinMenuItem(title: title) { engine.sortPlaylist(by: criteria) })
            }
            menu.addItem(.separator())
            menu.addItem(AIMPSkinMenuItem(title: "Shuffle") { engine.shufflePlaylist() })
        }
        switch popup {
        case .libraryTree:
            libraryPlay(track: false).forEach(menu.addItem)
        case .libraryTable:
            libraryPlay(track: true).forEach(menu.addItem)
            menu.addItem(.separator())
            menu.addItem(libraryRemove())
        case .libraryGroupings:
            groupings(menu)
        case .libraryRemove:
            menu.addItem(libraryRemove())
        case .library:
            libraryAdd(menu)
            menu.addItem(.separator())
            let presets = NSMenuItem(title: "Grouping", action: nil, keyEquivalent: "")
            presets.submenu = NSMenu()
            groupings(presets.submenu!)
            menu.addItem(presets)
        case .remove:
            menu.addItem(remove())
            menu.addItem(.separator())
            menu.addItem(AIMPSkinMenuItem(title: "Clear Playlist") { engine.clearPlaylist() })
        case .sort:
            sorting(menu)
        case .playlist:
            menu.addItem(play())
            menu.addItem(remove())
            menu.addItem(.separator())
            let sort = NSMenuItem(title: "Sort", action: nil, keyEquivalent: "")
            sort.submenu = NSMenu()
            sorting(sort.submenu!)
            menu.addItem(sort)
            menu.addItem(.separator())
            menu.addItem(AIMPSkinMenuItem(title: "Add Files…") { MenuActions.shared.openFile() })
            menu.addItem(AIMPSkinMenuItem(title: "Add Folder…") { MenuActions.shared.openFolder() })
            menu.addItem(.separator())
            menu.addItem(AIMPSkinMenuItem(title: "Clear Playlist") { engine.clearPlaylist() })
            PlaylistRowFields.addItems(to: menu)
        case .equalizer:
            let toggle = AIMPSkinMenuItem(title: "Equalizer On") { engine.setEQEnabled(!engine.isEQEnabled()) }
            toggle.state = engine.isEQEnabled() ? .on : .off
            menu.addItem(toggle)
            menu.addItem(.separator())
            for preset in EQPreset.allPresets {
                menu.addItem(AIMPSkinMenuItem(title: preset.name) {
                    Self.apply(preset, to: engine)
                    if !engine.isEQEnabled() { engine.setEQEnabled(true) }
                })
            }
        case .add:
            menu.addItem(AIMPSkinMenuItem(title: "Add Files…") { MenuActions.shared.openFile() })
            menu.addItem(AIMPSkinMenuItem(title: "Add Folder…") { MenuActions.shared.openFolder() })
        }
        return menu
    }

    /// Sets the engine to `preset`: its preamp and ten classic bands, each clamped to ±12 dB and
    /// remapped onto the engine's band layout, as WMP's `eq.currentPreset` does. Turning the EQ on is
    /// the caller's.
    @MainActor private static func apply(_ preset: EQPreset, to engine: AudioEngine) {
        engine.setPreamp(Float(max(-12, min(12, preset.preamp))))
        let clamped = preset.bands.map { Float(max(-12, min(12, $0))) }
        let remapped = EQBandRemapper.remap(gains: clamped, from: .classic10, to: engine.eqConfiguration)
        for (band, gain) in remapped.enumerated() { engine.setEQBand(band, gain: gain) }
    }
}
