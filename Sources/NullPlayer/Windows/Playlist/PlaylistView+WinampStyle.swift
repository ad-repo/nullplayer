import AppKit

/// The Classic playlist's **Winamp Classic** style (`ClassicPlaylistStyle.winamp`): the standard
/// Winamp 2 playlist editor. `SkinElements.Playlist.Editor` has its geometry and
/// `SkinRenderer.drawWinampPlaylistWindow` draws it; this is the behaviour behind it.
extension PlaylistView {
    /// Classic UI's own playlist window, the only one that offers **Playlist Style**.
    var canChooseStyle: Bool {
        !isEmbedded && WindowManager.shared.runningControllerFamily == .classic
    }

    /// A skin without PLEDIT.BMP (the built-in default) has no editor art to draw or hit-test,
    /// so it keeps the NullPlayer look whatever the choice.
    var isWinampStyle: Bool {
        canChooseStyle && ClassicPlaylistStyle.current == .winamp
            && WindowManager.shared.currentSkin?.pledit != nil
    }

    /// A Playlist Style or skin change moves the list's bottom edge (the 38px bar against the 7px
    /// border), so an offset that was valid can leave rows clipped above a list that now fits.
    func fitScrollOffsetToStyle() {
        guard canChooseStyle else { return }
        scrollOffset = min(scrollOffset, maxScrollOffset)
    }

    /// Winamp rows: PLEDIT.TXT's font at the row size (`SkinLoader` falls back to the system font
    /// for one not installed), its SelectedBG under a selected row, and no title marquee.
    static func winampRowStyle(_ colors: PlaylistColors, fontSize: CGFloat) -> RowStyle {
        RowStyle(font: colors.font.withSize(fontSize), selectionFill: colors.selectedBackground,
                 selectedText: nil, playingText: colors.currentText, normalText: colors.normalText,
                 scrollsTitle: false)
    }

    /// A press on the bottom bar: its menus open on the press, as Winamp's do. False when the press
    /// is elsewhere.
    func pressWinampBar(at skinPoint: NSPoint, viewPoint: NSPoint) -> Bool {
        guard isWinampStyle,
              let control = SkinElements.Playlist.Editor.control(at: skinPoint, size: effectiveWindowSize) else {
            return false
        }
        switch control {
        case .scrollUp: scroll(by: -itemHeight)
        case .scrollDown: scroll(by: itemHeight)
        default:
            WinampPlaylistBar.press(control, target: self, selectedRows: selectedIndices)?
                .popUp(positioning: nil, at: viewPoint, in: self)
        }
        needsDisplay = true
        return true
    }

    /// True over a bar control. The mini transport and the scroll arrows sit inside the window's
    /// bottom and right resize bands, which would otherwise take the press for a resize.
    func isOverWinampControl(windowPoint: NSPoint) -> Bool {
        guard isWinampStyle else { return false }
        let skinPoint = convertToSkinCoordinates(convert(windowPoint, from: nil))
        return SkinElements.Playlist.Editor.control(at: skinPoint, size: effectiveWindowSize) != nil
    }

    /// Winamp's playlist hotkeys; false for any other key.
    func performWinampHotkey(_ event: NSEvent) -> Bool {
        guard isWinampStyle, let hotkey = WinampPlaylistBar.Hotkey(event) else { return false }
        switch hotkey {
        case .command(let action): NSApp.sendAction(action, to: self, from: self)
        case .transport(let action): WindowManager.shared.perform(action)
        case .move(let offset):
            selectedIndices = WindowManager.shared.audioEngine.moveTracks(selectedIndices, by: offset)
            selectionAnchor = offset < 0 ? selectedIndices.min() : selectedIndices.max()
            scrollToSelection()
        }
        needsDisplay = true
        return true
    }

    @objc func choosePlaylistStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let style = ClassicPlaylistStyle(rawValue: raw) else { return }
        ClassicPlaylistStyle.current = style
    }
}

/// The Winamp playlist editor's controls and keys, apart from the view so they can be tested.
@MainActor
enum WinampPlaylistBar {
    typealias Control = SkinElements.Playlist.Editor.Control

    /// Winamp's running time: the selected rows' length over the whole queue's.
    // ponytail: sums the queue on every repaint (once a second while playing); cache it if a queue
    // change signal appears that also covers durations filled in after import.
    static func runningTime(selectedRows: Set<Int>) -> String {
        let tracks = WindowManager.shared.audioEngine.playlist
        let seconds = { (track: Track) in Int(track.duration ?? 0) }
        let selected = selectedRows.filter(tracks.indices.contains).reduce(0) { $0 + seconds(tracks[$1]) }
        let total = tracks.reduce(0) { $0 + seconds($1) }
        return "\(PlaylistView.clock(selected, hours: true))/\(PlaylistView.clock(total, hours: true))"
    }

    /// The playing track's elapsed seconds; nil when nothing has played.
    static func trackSeconds() -> Int? {
        let wm = WindowManager.shared
        let video = wm.isVideoActivePlayback
        let time = video ? wm.videoCurrentTime : wm.audioEngine.currentTime
        let playing = video ? wm.isVideoPlaying : wm.audioEngine.state == .playing
        return playing || time > 0 ? Int(time) : nil
    }

    /// A press on `control`: the menu to pop up, or nil once it has acted. The view scrolls for
    /// `scrollUp` / `scrollDown` itself.
    static func press(_ control: Control, target: PlaylistFileCommands, selectedRows: Set<Int>) -> NSMenu? {
        switch control {
        case .add: return PlaylistMenuBuilder.addMenu(target: target)
        case .remove: return PlaylistMenuBuilder.removeMenu(target: target, hasSelection: !selectedRows.isEmpty)
        case .select: return PlaylistMenuBuilder.selectMenu(target: target)
        case .misc: return PlaylistMenuBuilder.miscMenu(target: target, selectedRows: selectedRows,
                                                        canShowFileInfo: selectedRows.count == 1)
        case .list: return PlaylistMenuBuilder.playlistMenu(target: target)
        case .eject: target.addFiles(nil)
        case .previous: WindowManager.shared.perform(.previous)
        case .play: WindowManager.shared.perform(.play)
        case .pause: WindowManager.shared.perform(.pause)
        case .stop: WindowManager.shared.perform(.stop)
        case .next: WindowManager.shared.perform(.next)
        case .scrollUp, .scrollDown: break
        }
        return nil
    }

    /// Winamp's playlist editor hotkeys, with Ctrl as ⌘ and Alt as ⌥. Left out where something
    /// already owns the key: ⌘A is the Edit menu's Select All (which reaches the playlist anyway),
    /// Delete / Return / arrows / Home / End / Page keys are the playlist's own, and ⌘⇧3 (Sort by
    /// Path) is the macOS screenshot.
    enum Hotkey: Equatable {
        case command(Selector)
        case transport(TransportAction)
        /// Move the selected rows this many places (⌥↑ / ⌥↓).
        case move(Int)

        init?(_ event: NSEvent) {
            self.init(characters: event.charactersIgnoringModifiers?.lowercased() ?? "",
                      keyCode: event.keyCode, flags: event.modifierFlags)
        }

        /// Letters by character, so they follow the keyboard layout; digits, Delete and arrows by
        /// key code, since Shift changes a digit's character.
        init?(characters: String, keyCode: UInt16, flags: NSEvent.ModifierFlags) {
            let mods = flags.intersection([.command, .shift, .option, .control])
            switch (mods, characters, keyCode) {
            case ([], "z", _): self = .transport(.previous)
            case ([], "x", _): self = .transport(.play)
            case ([], "c", _): self = .transport(.pause)
            case ([], "v", _): self = .transport(.stop)
            case ([], "b", _): self = .transport(.next)
            case ([], "l", _): self = .command(#selector(PlaylistFileCommands.addFiles(_:)))
            case ([.shift], "l", _): self = .command(#selector(PlaylistFileCommands.addDirectory(_:)))
            case ([.command], "l", _): self = .command(#selector(PlaylistFileCommands.addURL(_:)))
            case ([.command], "i", _): self = .command(#selector(PlaylistMenuTarget.invertSelection(_:)))
            case ([.command], _, 51): self = .command(#selector(PlaylistMenuTarget.cropSelection(_:)))
            case ([.command, .shift], _, 51): self = .command(#selector(PlaylistMenuTarget.removeAll(_:)))
            case ([.command, .shift], _, 18): self = .command(#selector(PlaylistMenuTarget.sortByTitle(_:)))
            case ([.command, .shift], _, 19): self = .command(#selector(PlaylistMenuTarget.sortByFilename(_:)))
            case ([.command], "r", _): self = .command(#selector(PlaylistMenuTarget.reverse(_:)))
            case ([.command, .shift], "r", _): self = .command(#selector(PlaylistMenuTarget.randomize(_:)))
            case ([.option], _, 20): self = .command(#selector(PlaylistMenuTarget.showFileInfo(_:)))
            case ([.command], "n", _): self = .command(#selector(PlaylistMenuTarget.removeAll(_:)))
            case ([.command], "o", _): self = .command(#selector(PlaylistFileCommands.loadPlaylist(_:)))
            case ([.command], "s", _): self = .command(#selector(PlaylistFileCommands.savePlaylist(_:)))
            case ([.option], _, 126): self = .move(-1)
            case ([.option], _, 125): self = .move(1)
            default: return nil
            }
        }
    }
}
