import Foundation

/// A press on a playlist row that may become a drag moving the selection (M69), shared by the
/// Classic, Original and `.wal` playlists; each finds the row under the pointer its own way. The
/// selection moves live, row by row, keeping its order and the gaps inside it, as Winamp's does.
struct PlaylistRowDrag {
    /// The row the pointer holds, which follows it as the selection moves.
    private(set) var row: Int
    /// A plain press inside a multi-row selection keeps the selection so it can be dragged; a
    /// release without moving collapses it to this row, as the click alone would have.
    let collapsesTo: Int?
    private(set) var moved = false

    init(row: Int, selection: Set<Int>) {
        self.row = row
        collapsesTo = Self.keepsSelection(pressing: row, in: selection) ? row : nil
    }

    /// Whether a plain press on `row` keeps `selection` for a drag instead of selecting the row alone.
    static func keepsSelection(pressing row: Int, in selection: Set<Int>) -> Bool {
        selection.count > 1 && selection.contains(row)
    }

    /// Moves `selection` so the held row follows the pointer to `target`, through `move` (the
    /// engine's `moveTracks`, or the `.wal` host's), and returns the selection where it now is.
    mutating func drag(to target: Int, selection: Set<Int>,
                       move: (Set<Int>, Int) -> Set<Int>) -> Set<Int> {
        guard target != row, let oldFirst = selection.min() else { return selection }
        let moved = move(selection, target - row)
        guard let newFirst = moved.min(), newFirst != oldFirst else { return selection }
        row += newFirst - oldFirst
        self.moved = true
        return moved
    }
}
