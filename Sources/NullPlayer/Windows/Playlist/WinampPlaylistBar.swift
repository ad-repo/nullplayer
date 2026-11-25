import AppKit

/// **Playlist Style** — the Classic playlist as NullPlayer draws it (thin border, no controls), or
/// the standard Winamp 2 playlist editor: PLEDIT's 38px bottom bar (ADD / REM / SEL / MISC,
/// LIST OPTS, the mini transport, running and track time) and its 20px scrollbar border.
///
/// Classic UI only: every other family's fallback playlist and the compact library's embedded one
/// keep the NullPlayer look (`PlaylistView.isWinampStyle`).
enum ClassicPlaylistStyle: String {
    case nullPlayer, winamp

    static let defaultsKey = "classicPlaylistStyle"

    static var current: ClassicPlaylistStyle {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(Self.init(rawValue:)) ?? .winamp
    }

    var title: String {
        switch self {
        case .nullPlayer: return "NullPlayer"
        case .winamp: return "Winamp Classic"
        }
    }

    /// The **Playlist Style ▸** submenu.
    @MainActor
    static func menuItem() -> NSMenuItem {
        let submenu = NSMenu(title: "Playlist Style")
        for style in [ClassicPlaylistStyle.nullPlayer, .winamp] {
            let item = NSMenuItem(title: style.title, action: #selector(MenuTarget.choose(_:)), keyEquivalent: "")
            item.target = MenuTarget.shared
            item.representedObject = style.rawValue
            item.state = style == current ? .on : .off
            submenu.addItem(item)
        }
        let item = NSMenuItem(title: "Playlist Style", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    /// `NSMenuItem.target` is weak, so the items share one long-lived target.
    @MainActor
    private final class MenuTarget: NSObject {
        static let shared = MenuTarget()

        @objc func choose(_ sender: NSMenuItem) {
            guard let raw = sender.representedObject as? String else { return }
            UserDefaults.standard.set(raw, forKey: ClassicPlaylistStyle.defaultsKey)
            WindowManager.shared.redrawPlaylistViews()
        }
    }
}

/// The Winamp playlist editor's bottom bar and scrollbar, at the positions PLEDIT.BMP's art puts
/// them (measured from the base 2.91 skin). Skin coordinates, top-left origin, unscaled.
enum WinampPlaylistBar {
    static let bottomHeight: CGFloat = 38
    static let rightBorder: CGFloat = 20
    /// The right corner piece, which carries LIST OPTS, the transport and both time displays.
    static let rightCornerWidth: CGFloat = 150

    enum Control: CaseIterable {
        case add, remove, select, misc, list
        case previous, play, pause, stop, next, eject
        case scrollUp, scrollDown
    }

    /// The control under `point` in a window of `size`, or nil.
    static func control(at point: NSPoint, size: NSSize) -> Control? {
        Control.allCases.first { rect(for: $0, size: size).contains(point) }
    }

    static func rect(for control: Control, size: NSSize) -> NSRect {
        let barTop = size.height - bottomHeight
        let right = size.width - rightCornerWidth
        func left(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
            NSRect(x: x, y: barTop + y, width: w, height: h)
        }
        func corner(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
            NSRect(x: right + x, y: barTop + y, width: w, height: h)
        }
        switch control {
        case .add: return left(11, 8, 25, 18)
        case .remove: return left(40, 8, 25, 18)
        case .select: return left(69, 8, 25, 18)
        case .misc: return left(98, 8, 25, 18)
        case .list: return corner(103, 8, 25, 18)
        case .previous: return corner(3, 22, 10, 9)
        case .play: return corner(13, 22, 9, 9)
        case .pause: return corner(22, 22, 10, 9)
        case .stop: return corner(32, 22, 9, 9)
        case .next: return corner(41, 22, 9, 9)
        case .eject: return corner(50, 22, 10, 9)
        case .scrollUp: return corner(134, 1, 10, 6)
        case .scrollDown: return corner(134, 7, 10, 6)
        }
    }

    /// The scrollbar groove inside the right border.
    static func scrollbarRect(size: NSSize, titleHeight: CGFloat) -> NSRect {
        NSRect(x: size.width - 15, y: titleHeight, width: 8,
               height: max(0, size.height - titleHeight - bottomHeight))
    }

    /// Where the running time (`selected/total`) and the playing track's `M:SS` are drawn, in
    /// TEXT.BMP's 5×6 font. The art bakes in the track time's colon at x+83.
    static func runningTimeOrigin(size: NSSize) -> NSPoint {
        NSPoint(x: size.width - rightCornerWidth + 7, y: size.height - bottomHeight + 10)
    }

    static func trackTimeColonX(size: NSSize) -> CGFloat {
        size.width - rightCornerWidth + 83
    }

    static func trackTimeY(size: NSSize) -> CGFloat {
        size.height - bottomHeight + 23
    }

    /// `M:SS`, or `H:MM:SS` past an hour.
    static func format(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }

    /// Winamp's running time: the selected rows' length over the whole queue's.
    @MainActor
    static func runningTime(selectedRows: Set<Int>) -> String {
        let tracks = WindowManager.shared.audioEngine.playlist
        let seconds = { (track: Track) in Int(track.duration ?? 0) }
        let selected = selectedRows.filter(tracks.indices.contains).reduce(0) { $0 + seconds(tracks[$1]) }
        return "\(format(selected))/\(format(tracks.reduce(0) { $0 + seconds($1) }))"
    }

    /// The playing track's elapsed time either side of the art's colon; nil when nothing has played.
    @MainActor
    static func trackTime() -> (minutes: String, seconds: String)? {
        let wm = WindowManager.shared
        let video = wm.isVideoActivePlayback
        let time = video ? wm.videoCurrentTime : wm.audioEngine.currentTime
        let playing = video ? wm.isVideoPlaying : wm.audioEngine.state == .playing
        guard playing || time > 0 else { return nil }
        let s = Int(time)
        return (String(s / 60), String(format: "%02d", s % 60))
    }

    /// A press on `control`: the menu to pop up, or nil once it has acted. The view scrolls for
    /// `scrollUp` / `scrollDown` itself.
    @MainActor
    static func press(_ control: Control, target: PlaylistFileCommands, selectedRows: Set<Int>) -> NSMenu? {
        switch control {
        case .add: return addMenu(target: target)
        case .remove: return PlaylistMenuBuilder.removeMenu(target: target, hasSelection: !selectedRows.isEmpty)
        case .select: return PlaylistMenuBuilder.selectMenu(target: target)
        case .misc: return PlaylistMenuBuilder.miscMenu(target: target, selectedRows: selectedRows,
                                                        canShowFileInfo: selectedRows.count == 1)
        case .list: return listMenu(target: target)
        case .eject: target.addFiles(nil)
        case .previous, .play, .pause, .stop, .next: performTransport(control)
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
        case transport(Control)
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

    /// The mini transport, as the main window's buttons behave (video first when one is playing).
    @MainActor
    static func performTransport(_ control: Control) {
        let wm = WindowManager.shared
        let engine = wm.audioEngine
        let video = wm.isVideoActivePlayback
        switch control {
        case .previous: video ? wm.skipVideoBackward(10) : engine.previous()
        case .play: video ? wm.toggleVideoPlayPause() : engine.play()
        case .pause: video ? wm.toggleVideoPlayPause() : engine.pause()
        case .stop: video ? wm.stopVideo() : engine.stop()
        case .next: video ? wm.skipVideoForward(10) : engine.next()
        default: break
        }
    }

    @MainActor
    private static func addMenu(target: PlaylistFileCommands) -> NSMenu {
        menu("Add", [("Add URL...", #selector(PlaylistFileCommands.addURL(_:))),
                     ("Add Directory...", #selector(PlaylistFileCommands.addDirectory(_:))),
                     ("Add Files...", #selector(PlaylistFileCommands.addFiles(_:)))], target: target)
    }

    @MainActor
    private static func listMenu(target: PlaylistFileCommands) -> NSMenu {
        menu("List", [("New Playlist", #selector(PlaylistMenuTarget.removeAll(_:))),
                      ("Save Playlist...", #selector(PlaylistFileCommands.savePlaylist(_:))),
                      ("Load Playlist...", #selector(PlaylistFileCommands.loadPlaylist(_:)))], target: target)
    }

    @MainActor
    private static func menu(_ title: String, _ rows: [(String, Selector)], target: AnyObject) -> NSMenu {
        let menu = NSMenu(title: title)
        for (title, action) in rows {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = target
            menu.addItem(item)
        }
        return menu
    }
}
