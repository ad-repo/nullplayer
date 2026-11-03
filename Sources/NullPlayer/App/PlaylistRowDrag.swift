import Foundation

/// A plain press on a playlist row and the drag it may become (M69), shared by the Classic,
/// Original and `.wal` playlists; each finds the row under the pointer its own way and writes
/// `selection` back. The selection moves live, row by row, keeping its order and the gaps inside
/// it, as Winamp's does.
struct PlaylistRowDrag {
    /// The row the pointer holds, which follows it as the selection moves.
    private(set) var row: Int
    private(set) var selection: Set<Int>
    /// A press inside a multi-row selection keeps it so it can be dragged; a release without
    /// moving collapses it to the pressed row, as the click alone would have.
    private let keptSelection: Bool
    private var moved = false

    init(pressing row: Int, in selection: Set<Int>) {
        self.row = row
        keptSelection = selection.count > 1 && selection.contains(row)
        self.selection = keptSelection ? selection : [row]
    }

    /// Moves the selection so the held row follows the pointer to `target`, through `move` (the
    /// engine's `moveTracks`, or the `.wal` host's), which clamps it at either end of the list.
    mutating func drag(to target: Int, move: (Set<Int>, Int) -> Set<Int>) {
        guard target != row, let oldFirst = selection.min() else { return }
        let landed = move(selection, target - row)
        guard let newFirst = landed.min(), newFirst != oldFirst else { return }
        row += newFirst - oldFirst
        selection = landed
        moved = true
    }

    /// The selection a release leaves behind.
    var releasedSelection: Set<Int> { keptSelection && !moved ? [row] : selection }
}
