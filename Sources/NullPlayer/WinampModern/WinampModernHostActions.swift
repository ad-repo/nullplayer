import Foundation

/// The four Winamp **host-action families** a `.wal` skin hangs on a toolbar button: the
/// visualization (`VIS_*`), the playlist editor (`PE_*`), the video window (`VID_*`) and the
/// component bucket (`CB_*`).
///
/// Measured across the 17-skin corpus (2026-08-20): **108 declarations in 11 skins** — `VIS_*` 27 in
/// 5, `PE_*` 39 in 7, `VID_*` 28 in 5, `CB_*` 14 in 4. Every one of them was a visible button whose
/// click reached the action switch's `default:` and stopped there.
///
/// The families are decoded in one place so that what we answer, and what we deliberately do not,
/// is a list rather than a scattering of `case` labels. Two things a skin declares have no host
/// behind them here and say so through `.inert`, which records itself once in the skin's diagnostics
/// so a triage pass can see the demand rather than guess at it.
enum WinampModernHostAction: Equatable {
    // Visualization
    case visualizationMenu
    case visualizationNext
    case visualizationPrevious
    case visualizationConfig
    case visualizationFullscreen
    // Playlist editor
    case playlistAdd
    case playlistRemove
    case playlistSelect
    case playlistMisc
    case playlistList
    // Video
    case videoFullscreen
    case videoMenu
    /// `VID_1X` / `VID_2X` — size the video window so its picture is the stream's own pixel size
    /// times this multiple (B20).
    case videoNativeSize(multiple: Int)
    // Component bucket
    /// `CB_NEXT` / `CB_PREV` (`page: false`) and `CB_NEXTPAGE` / `CB_PREVPAGE` — scroll the thinger
    /// by one icon or by a whole screenful.
    case componentBucketScroll(delta: Int, page: Bool)
    /// Declared by the corpus and answered by nothing here, with the reason a triage pass needs.
    case inert(action: String, reason: String)

    /// Decode one of the four families. Case-insensitive: skins spell these `VIS_Prev`, `vis_prev`
    /// and `VIS_PREV` in the same file.
    init?(action: String) {
        let name = action.trimmingCharacters(in: .whitespaces).uppercased()
        switch name {
        case "VIS_MENU": self = .visualizationMenu
        case "VIS_NEXT": self = .visualizationNext
        case "VIS_PREV", "VIS_PREVIOUS": self = .visualizationPrevious
        case "VIS_CFG": self = .visualizationConfig
        case "VIS_FS": self = .visualizationFullscreen
        case "PE_ADD": self = .playlistAdd
        case "PE_REM": self = .playlistRemove
        case "PE_SEL": self = .playlistSelect
        case "PE_MISC": self = .playlistMisc
        // Winamp's "playlist of playlists" is its saved-playlist manager, which is the same list of
        // playlists our `PE_LIST` menu offers — one menu, not a second thinner one.
        case "PE_LIST", "PE_LISTOFLISTS": self = .playlistList
        case "VID_FS": self = .videoFullscreen
        case "VID_MISC": self = .videoMenu
        // Winamp's video window sizes itself to the stream's own dimensions. Inert until B20, because
        // nothing read `presentationSize` and there was nothing to size *to*; a hosted surface has a
        // native size, and the skin's own window is what gets sized around it.
        case "VID_1X": self = .videoNativeSize(multiple: 1)
        case "VID_2X": self = .videoNativeSize(multiple: 2)
        // SHOUTcast TV. NullPlayer has no internet-TV source and will not gain one here.
        case "VID_TV": self = .inert(action: name, reason: "no internet TV source in NullPlayer")
        // Winamp's **Send To** menu: hand the current item to a Media Library playlist, a portable
        // device, the CD burner or a transcoder — a menu built by whatever plugins are installed.
        // NullPlayer publishes no such targets, so the menu would be empty and every item in it a lie
        // about something the app can do. Declared by Big Bento Modern (both editions, 2 each) and
        // Defix (1), which is why it says so here rather than falling through the switch unnamed.
        case "ML_SENDTO":
            self = .inert(action: name, reason: "NullPlayer publishes no Send To targets")
        // The component bucket is Winamp's scrolling strip of *installed component* icons — the
        // "thinger". These were inert for as long as the engine published no icon set for a bucket to
        // scroll; it publishes one now (`WinampModernComponentBucketCatalog`, B34), so they scroll it:
        // by one icon, or by a whole screenful for the `*PAGE` pair that winampmodern566 and S7Reflex
        // page their config drawers with.
        case "CB_NEXT": self = .componentBucketScroll(delta: 1, page: false)
        case "CB_PREV": self = .componentBucketScroll(delta: -1, page: false)
        case "CB_NEXTPAGE": self = .componentBucketScroll(delta: 1, page: true)
        case "CB_PREVPAGE": self = .componentBucketScroll(delta: -1, page: true)
        default: return nil
        }
    }
}

/// What a `<vis>` box is currently showing. `1` is the spectrum analyzer and `2` the oscilloscope;
/// `0` and `3` are off, and an undeclared mode is the analyzer — the pairing MMD3's `ShowVISBg` and
/// Love is War Miku's `visualizer.maki` both pin (see `WasabiSceneRenderer.drawVisualization`).
///
/// The renderer reads this attribute; `VIS_NEXT`/`VIS_PREV` and the `VIS_MENU` items write it, which
/// is exactly what a skin's own script does through `setMode`.
enum WasabiVisualizationMode: CaseIterable {
    case analyzer
    case oscilloscope
    case off

    init(attribute: String?) {
        switch attribute?.trimmingCharacters(in: .whitespaces) {
        case "2": self = .oscilloscope
        case "0", "3": self = .off
        default: self = .analyzer
        }
    }

    /// What `setMode` would write. `off` is written as `0`: a skin that ships `3` (MMD3's own
    /// animated display) reads back as off either way, and `0` is the value Winamp itself stores.
    var attributeValue: String {
        switch self {
        case .analyzer: return "1"
        case .oscilloscope: return "2"
        case .off: return "0"
        }
    }

    var displayName: String {
        switch self {
        case .analyzer: return "Spectrum Analyzer"
        case .oscilloscope: return "Oscilloscope"
        case .off: return "Off"
        }
    }

    /// The next mode in Winamp's own order, wrapping. `delta` is +1 for `VIS_NEXT`, −1 for
    /// `VIS_PREV`.
    func stepped(by delta: Int) -> WasabiVisualizationMode {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[((index + delta) % all.count + all.count) % all.count]
    }
}

/// The set arithmetic behind `PE_SEL` and `PE_REM`. Pure, so the menus can be tested without a
/// playlist, a window, or a menu-tracking run loop.
enum WinampModernPlaylistSelection {
    static func all(count: Int) -> Set<Int> { count > 0 ? Set(0..<count) : [] }

    static func inverted(_ selection: Set<Int>, count: Int) -> Set<Int> {
        all(count: count).subtracting(selection)
    }

    /// The rows a crop removes: everything that is *not* selected. Empty when nothing is selected —
    /// cropping to no selection would empty the queue, which is `Remove All` under another name.
    static func cropVictims(keeping selection: Set<Int>, count: Int) -> Set<Int> {
        guard !selection.isEmpty else { return [] }
        return inverted(selection, count: count)
    }

    /// Removal order: highest row first, so each removal cannot shift the rows still to come.
    static func removalOrder(_ rows: Set<Int>) -> [Int] { rows.sorted(by: >) }

    /// Where the selection lands after `rows` have been removed — the row that took the place of the
    /// lowest removed one, clamped into the shortened list, or `-1` when nothing is left.
    static func selectionAfterRemoval(of rows: Set<Int>, count: Int) -> Int {
        let remaining = count - rows.count
        guard remaining > 0, let lowest = rows.min() else { return -1 }
        return max(0, min(remaining - 1, lowest))
    }
}
