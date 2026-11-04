import AppKit

extension AIMPSkinMainView {
    // MARK: - Library

    /// The tree row under `point`.
    func libraryRow(_ target: AIMPSkinTarget, at point: CGPoint) -> AIMPSkinLibrary.Row? {
        guard case .libraryTree(let first, let rowHeight) = target.kind, let library = host.player.library else { return nil }
        let lists = skinState.lists
        let rows = library.rows(lists.libraryGrouping, expanded: lists.libraryExpanded, search: lists.libraryTreeSearch)
        let index = first + Int((point.y - target.rect.minY) / rowHeight)
        return rows.indices.contains(index) ? rows[index] : nil
    }

    /// A tree row is chosen, its tracks fill the table; a click on its arrow, or a double click,
    /// opens or closes a group.
    func clickLibraryTree(_ target: AIMPSkinTarget, at point: CGPoint, clicks: Int) {
        guard let row = libraryRow(target, at: point) else { return }
        var state = skinState
        let onArrow = point.x - target.rect.minX < 3 + CGFloat(row.level) * 14 + 13
        if row.expandable, onArrow || clicks >= 2 {
            if state.lists.libraryExpanded.contains(row.path) { state.lists.libraryExpanded.remove(row.path) } else { state.lists.libraryExpanded.insert(row.path) }
        }
        if state.lists.libraryPath != row.path {
            state.lists.libraryPath = row.path
            state.lists.libraryTableTop = 0
        }
        skinState = state
    }

    /// The track under `point` in the library table, below its header.
    func libraryTrack(_ target: AIMPSkinTarget, at point: CGPoint) -> LibraryTrack? {
        guard case .libraryTable(let first, let rowHeight, let header) = target.kind, let library = host.player.library,
              point.y >= target.rect.minY + header else { return nil }
        let lists = skinState.lists
        let rows = library.table(lists.libraryGrouping, path: lists.libraryPath, search: lists.librarySearch)
        let index = first + Int((point.y - target.rect.minY - header) / rowHeight)
        return rows.indices.contains(index) ? library.tracks[rows[index]] : nil
    }

    /// A click chooses a track; a double click adds it to the playlist and plays it.
    func clickLibraryTable(_ target: AIMPSkinTarget, at point: CGPoint, clicks: Int) {
        guard let track = libraryTrack(target, at: point) else { return }
        skinState.lists.librarySelected = track.id
        if clicks >= 2 { runtime?.onAction?(.playLibraryTrack(track.id)) }
    }

    /// The track under `point` in the skin's playlist, through the quick search.
    func playlistIndex(_ target: AIMPSkinTarget, at point: CGPoint) -> Int? {
        guard case .playlist(let first, let rowHeight) = target.kind else { return nil }
        let shown = host.playlistIndices(matching: skinState.lists.playlistSearch)
        let row = first + Int((point.y - target.rect.minY) / rowHeight)
        return shown.indices.contains(row) ? shown[row] : nil
    }
}
