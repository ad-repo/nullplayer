import AppKit

/// The queue commands a `.wal` playlist answers: the right-click menu over its list (the same
/// `PlaylistMenuBuilder` menu every other family's playlist opens) and the `PE_REM` / `PE_SEL` /
/// `PE_MISC` button menus. One object rather than the view, because `WinampModernMainView` backs
/// every `.wal` window and must not answer `selectAll(_:)` for all of them.
@MainActor
final class WinampModernPlaylistMenuTarget: NSObject, PlaylistMenuTarget {
    private unowned let view: WinampModernMainView

    init(view: WinampModernMainView) {
        self.view = view
    }

    private var engine: AudioEngine { WindowManager.shared.audioEngine }
    private var componentHost: WinampModernComponentHost? { view.componentHost }

    /// The row File Info is about: the selection's anchor, or the playing track when the user has
    /// not picked a row.
    var selectedTrack: Track? {
        let index = componentHost?.playlistSnapshot().selectedIndex ?? -1
        if engine.playlist.indices.contains(index) { return engine.playlist[index] }
        return engine.currentTrack
    }

    func selectForMenu(_ row: Int) {
        componentHost?.playlistSelect(row: row)
        view.needsDisplay = true
    }

    func playSelected(_ sender: Any?) {
        guard let componentHost, let row = componentHost.playlistSnapshot().selectedRows.min() else { return }
        componentHost.playlistPlay(row: row)
        view.playlistDidChange()
    }

    // MARK: PE_REM

    func removeSelected(_ sender: Any?) {
        guard let componentHost else { return }
        componentHost.playlistRemoveRows(componentHost.playlistSnapshot().selectedRows)
        view.playlistDidChange()
    }

    func cropSelection(_ sender: Any?) {
        guard let componentHost else { return }
        let snapshot = componentHost.playlistSnapshot()
        let victims = WinampModernPlaylistSelection.cropVictims(keeping: snapshot.selectedRows,
                                                               count: snapshot.rows.count)
        guard !victims.isEmpty else { return }
        componentHost.playlistRemoveRows(victims)
        view.playlistDidChange()
    }

    func removeAll(_ sender: Any?) {
        engine.clearPlaylist()
        componentHost?.playlistSetSelection([])
        view.playlistDidChange()
    }

    func removeDeadFiles(_ sender: Any?) {
        let dead = PlaylistMenuBuilder.deadFileRows()
        guard !dead.isEmpty, let componentHost else { return }
        componentHost.playlistRemoveRows(dead)
        view.playlistDidChange()
    }

    // MARK: PE_SEL

    func selectAll(_ sender: Any?) {
        componentHost?.playlistSetSelection(
            WinampModernPlaylistSelection.all(count: engine.playlist.count))
        view.playlistDidChange()
    }

    func selectNone(_ sender: Any?) {
        componentHost?.playlistSetSelection([])
        view.playlistDidChange()
    }

    func invertSelection(_ sender: Any?) {
        guard let componentHost else { return }
        let snapshot = componentHost.playlistSnapshot()
        componentHost.playlistSetSelection(
            WinampModernPlaylistSelection.inverted(snapshot.selectedRows, count: snapshot.rows.count))
        view.playlistDidChange()
    }

    // MARK: PE_MISC

    func sortByTitle(_ sender: Any?) { sort(.title) }
    func sortByArtist(_ sender: Any?) { sort(.artist) }
    func sortByAlbum(_ sender: Any?) { sort(.album) }
    func sortByFilename(_ sender: Any?) { sort(.filename) }
    func sortByPath(_ sender: Any?) { sort(.path) }

    func randomize(_ sender: Any?) {
        engine.shufflePlaylist()
        view.playlistDidChange()
    }

    func reverse(_ sender: Any?) {
        engine.reversePlaylist()
        view.playlistDidChange()
    }

    /// The same File Info sheet `TRACKINFO` opens (Phase 36), aimed at the selected row rather than
    /// at whatever is playing — never `runModal()`, for the reason recorded there.
    func showFileInfo(_ sender: Any?) {
        guard let window = view.window, let track = selectedTrack else { return }
        PlaylistMenuBuilder.fileInfoAlert(for: track).beginSheetModal(for: window)
    }

    private func sort(_ criteria: AudioEngine.SortCriteria) {
        engine.sortPlaylist(by: criteria)
        view.playlistDidChange()
    }
}

extension WinampModernMainView {
    /// NullPlayer's playlist menu over a `.wal` list, at the pointer. A right-click on a row outside
    /// the selection selects it first, as every other family's playlist does.
    func showPlaylistContextMenu(at point: CGPoint, holder: WinampModernComponentHolder) {
        let snapshot = componentHost?.playlistSnapshot() ?? .empty
        let menu = PlaylistMenuBuilder.menu(
            target: playlistMenuTarget,
            clickedRow: renderer.playlistRow(at: point, in: holder.frame, holder: holder.object),
            state: .init(selectedRows: snapshot.selectedRows, hasTracks: !snapshot.rows.isEmpty),
            autoenablesItems: false)
        popUpMenu(menu, from: nil, atMouse: true)
    }
}
