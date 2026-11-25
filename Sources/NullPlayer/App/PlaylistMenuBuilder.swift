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
    /// Make `row` the whole selection, before a menu opened on it.
    func selectForMenu(_ row: Int)
    /// A **Playlist Style ▸** row: its `representedObject` is the `ClassicPlaylistStyle` raw value.
    @objc optional func choosePlaylistStyle(_ sender: NSMenuItem)
}

/// The old ADD / LIST bar's commands, for a playlist that owns them. A conformer's context menu gains
/// Add ▸ and Playlist ▸; a skin-drawn playlist (`.wal`, `.wmz`) does not conform, so its menu is unchanged.
@MainActor
@objc protocol PlaylistFileCommands: PlaylistMenuTarget {
    func addFiles(_ sender: Any?)
    func addDirectory(_ sender: Any?)
    func addURL(_ sender: Any?)
    func loadPlaylist(_ sender: Any?)
    func savePlaylist(_ sender: Any?)
}

/// **NullPlayer's playlist context menu, shared by every view that shows the play queue.** The
/// Modern playlist built it inline; a `.wmz` skin's `<PLAYLIST>` pane needs the same rows because
/// WMP skins authored no playlist controls of their own — WMP's menus supplied them (W272). Lifted
/// here rather than reached for in `ModernPlaylistView`, which WMP code may not depend on.
@MainActor
enum PlaylistMenuBuilder {
    struct State {
        var selectedRows: Set<Int>
        var hasTracks: Bool
        /// False while the view shows something other than the live queue (a `.wmz` library
        /// preview), so every row that edits the queue is disabled and nothing is assigned.
        var canEdit = true
        /// The Classic playlist's current style, which adds **Playlist Style ▸**; nil elsewhere.
        var playlistStyle: ClassicPlaylistStyle?
        var selectionCount: Int { selectedRows.count }
        var hasSelection: Bool { selectionCount > 0 }
    }

    /// `autoenablesItems` stays AppKit's default for the Modern playlist, which never validated
    /// these rows — so its `isEnabled` values have always been overridden to enabled, and are kept
    /// exactly as they were. A caller whose disabled rows must hold passes `false`.
    ///
    /// A right-click on `clickedRow` outside the selection selects that row first, so the menu acts
    /// on the row clicked; inside the selection it acts on the whole selection.
    static func menu(target: PlaylistMenuTarget, clickedRow: Int? = nil, state: State,
                     autoenablesItems: Bool = true) -> NSMenu {
        var state = state
        if let row = clickedRow, !state.selectedRows.contains(row) {
            target.selectForMenu(row)
            state.selectedRows = [row]
        }
        let menu = NSMenu()
        menu.autoenablesItems = autoenablesItems
        let hasSelection = state.hasSelection, hasTracks = state.hasTracks, canEdit = state.canEdit

        func item(_ title: String, _ action: Selector, enabled: Bool, key: String = "") -> NSMenuItem {
            Self.item(title, action, target: target, enabled: enabled, key: key)
        }
        func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
            Self.submenu(title, autoenablesItems: autoenablesItems, items)
        }
        let fileCommands = target as? PlaylistFileCommands

        menu.addItem(item("Play", #selector(PlaylistMenuTarget.playSelected(_:)), enabled: hasSelection))
        menu.addItem(NSMenuItem.separator())
        if let fileCommands { menu.addItem(submenu("Add", addItems(target: fileCommands))) }
        menu.addItem(item("Remove Selected", #selector(PlaylistMenuTarget.removeSelected(_:)),
                          enabled: hasSelection && canEdit))
        menu.addItem(item("Clear Playlist", #selector(PlaylistMenuTarget.removeAll(_:)),
                          enabled: hasTracks && canEdit))
        menu.addItem(item("Remove Dead Files", #selector(PlaylistMenuTarget.removeDeadFiles(_:)),
                          enabled: hasTracks && canEdit))
        menu.addItem(NSMenuItem.separator())

        let selectAllItem = item("Select All", #selector(PlaylistMenuTarget.selectAll(_:)),
                                 enabled: hasTracks, key: "a")
        selectAllItem.keyEquivalentModifierMask = .command
        menu.addItem(submenu("Selection", [
            selectAllItem,
            item("Select None", #selector(PlaylistMenuTarget.selectNone(_:)), enabled: hasSelection),
            item("Invert Selection", #selector(PlaylistMenuTarget.invertSelection(_:)), enabled: hasTracks),
            item("Crop Selection", #selector(PlaylistMenuTarget.cropSelection(_:)), enabled: hasSelection && canEdit)
        ]))

        let canSort = hasTracks && canEdit
        menu.addItem(submenu("Sort", [
            item("Sort by Title", #selector(PlaylistMenuTarget.sortByTitle(_:)), enabled: canSort),
            item("Sort by Artist", #selector(PlaylistMenuTarget.sortByArtist(_:)), enabled: canSort),
            item("Sort by Album", #selector(PlaylistMenuTarget.sortByAlbum(_:)), enabled: canSort),
            item("Sort by Filename", #selector(PlaylistMenuTarget.sortByFilename(_:)), enabled: canSort),
            item("Sort by Path", #selector(PlaylistMenuTarget.sortByPath(_:)), enabled: canSort),
            NSMenuItem.separator(),
            item("Reverse", #selector(PlaylistMenuTarget.reverse(_:)), enabled: canSort),
            item("Randomize", #selector(PlaylistMenuTarget.randomize(_:)), enabled: canSort)
        ]))
        if let fileCommands { menu.addItem(submenu("Playlist", playlistItems(target: fileCommands))) }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(item("File Info...", #selector(PlaylistMenuTarget.showFileInfo(_:)),
                          enabled: state.selectionCount == 1 && canEdit))
        if canEdit { EQProfileMenu.addAssignItem(to: menu, queueRows: state.selectedRows) }
        PlaylistRowFields.addItems(to: menu)
        if let current = state.playlistStyle {
            menu.addItem(NSMenuItem.separator())
            menu.addItem(submenu("Playlist Style", ClassicPlaylistStyle.allCases.map { style in
                let row = item(style.title, #selector(PlaylistMenuTarget.choosePlaylistStyle(_:)), enabled: true)
                row.representedObject = style.rawValue
                row.state = style == current ? .on : .off
                return row
            }))
        }
        return menu
    }

    // MARK: - A skin's ADD, REM, SEL, MISC and LIST OPTS buttons

    /// Winamp's ADD button, and the context menu's **Add ▸**.
    static func addMenu(target: PlaylistFileCommands) -> NSMenu {
        section("Add", addItems(target: target))
    }

    /// Winamp's LIST OPTS button, and the context menu's **Playlist ▸**.
    static func playlistMenu(target: PlaylistFileCommands) -> NSMenu {
        section("Playlist", playlistItems(target: target))
    }

    private static func addItems(target: PlaylistFileCommands) -> [NSMenuItem] {
        [item("Add URL...", #selector(PlaylistFileCommands.addURL(_:)), target: target, enabled: true),
         item("Add Directory...", #selector(PlaylistFileCommands.addDirectory(_:)), target: target, enabled: true),
         item("Add Files...", #selector(PlaylistFileCommands.addFiles(_:)), target: target, enabled: true)]
    }

    private static func playlistItems(target: PlaylistFileCommands) -> [NSMenuItem] {
        [item("New Playlist", #selector(PlaylistMenuTarget.removeAll(_:)), target: target, enabled: true),
         item("Save Playlist...", #selector(PlaylistFileCommands.savePlaylist(_:)), target: target, enabled: true),
         item("Load Playlist...", #selector(PlaylistFileCommands.loadPlaylist(_:)), target: target, enabled: true)]
    }

    /// Winamp's `PE_REM`, for a skin that draws the playlist editor's buttons itself. "Selected" and
    /// "Crop" are disabled with nothing selected rather than hidden — a greyed item says *why* it did
    /// nothing, an absent one does not.
    static func removeMenu(target: PlaylistMenuTarget, hasSelection: Bool) -> NSMenu {
        section("Remove", [
            item("Remove Selected", #selector(PlaylistMenuTarget.removeSelected(_:)), target: target, enabled: hasSelection),
            item("Crop Selection", #selector(PlaylistMenuTarget.cropSelection(_:)), target: target, enabled: hasSelection),
            item("Remove All", #selector(PlaylistMenuTarget.removeAll(_:)), target: target, enabled: true),
            item("Remove Dead Files", #selector(PlaylistMenuTarget.removeDeadFiles(_:)), target: target, enabled: true)
        ])
    }

    /// Winamp's `PE_SEL`.
    static func selectMenu(target: PlaylistMenuTarget) -> NSMenu {
        section("Select", [
            item("Select All", #selector(PlaylistMenuTarget.selectAll(_:)), target: target, enabled: true),
            item("Select None", #selector(PlaylistMenuTarget.selectNone(_:)), target: target, enabled: true),
            item("Invert Selection", #selector(PlaylistMenuTarget.invertSelection(_:)), target: target, enabled: true)
        ])
    }

    /// Winamp's `PE_MISC`: its sort submenu, and File Info for `selectedRows` (enabled when the target
    /// has a track to show), with the EQ-profile and row-field items every playlist menu carries.
    static func miscMenu(target: PlaylistMenuTarget, selectedRows: Set<Int>, canShowFileInfo: Bool) -> NSMenu {
        let menu = section("Misc", [
            submenu("Sort", autoenablesItems: false, [
                item("Sort by Title", #selector(PlaylistMenuTarget.sortByTitle(_:)), target: target, enabled: true),
                item("Sort by Filename", #selector(PlaylistMenuTarget.sortByFilename(_:)), target: target, enabled: true),
                item("Sort by Path", #selector(PlaylistMenuTarget.sortByPath(_:)), target: target, enabled: true),
                item("Randomize", #selector(PlaylistMenuTarget.randomize(_:)), target: target, enabled: true),
                item("Reverse", #selector(PlaylistMenuTarget.reverse(_:)), target: target, enabled: true)
            ]),
            .separator(),
            item("File Info...", #selector(PlaylistMenuTarget.showFileInfo(_:)), target: target, enabled: canShowFileInfo)
        ])
        EQProfileMenu.addAssignItem(to: menu, queueRows: selectedRows)
        PlaylistRowFields.addItems(to: menu)
        return menu
    }

    // MARK: - Building

    private static func item(_ title: String, _ action: Selector, target: PlaylistMenuTarget, enabled: Bool,
                             key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target
        item.isEnabled = enabled
        return item
    }

    private static func submenu(_ title: String, autoenablesItems: Bool, _ items: [NSMenuItem]) -> NSMenuItem {
        let submenu = NSMenu(title: title)
        submenu.autoenablesItems = autoenablesItems
        items.forEach(submenu.addItem)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    /// A skin button's menu: its enabled states hold.
    private static func section(_ title: String, _ items: [NSMenuItem]) -> NSMenu {
        let menu = NSMenu(title: title)
        menu.autoenablesItems = false
        items.forEach(menu.addItem)
        return menu
    }

    // MARK: - Add ▸ and Playlist ▸

    /// Ask for a URL and append it with `AudioEngine.appendFiles`. True when a URL was added.
    static func promptAddURL() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Add URL"
        alert.informativeText = "Enter the URL of the media file:"
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        input.placeholderString = "https://example.com/audio.mp3"
        alert.accessoryView = input
        guard alert.runModal() == .alertFirstButtonReturn,
              let url = URL(string: input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return false }
        WindowManager.shared.audioEngine.appendFiles([url])
        return true
    }

    /// Pick audio or video files and append them with `AudioEngine.appendFiles`. True when files
    /// were picked.
    static func promptAddFiles() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.audio, .movie]
        guard panel.runModal() == .OK else { return false }
        WindowManager.shared.audioEngine.appendFiles(panel.urls)
        return true
    }

    /// Pick a folder, find its audio and video off the main thread, and hand them to
    /// `AudioEngine.appendFiles`. `onLoad` runs on main once added.
    static func promptAddDirectory(onLoad: @escaping () -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        LocalFileDiscovery.discoverMediaURLsAsync(from: [url], includeVideo: true) { mediaURLs in
            guard !mediaURLs.isEmpty else { return }
            WindowManager.shared.audioEngine.appendFiles(mediaURLs)
            onLoad()
        }
    }

    /// Pick an `.m3u`/`.m3u8` and replace the queue with it. True when the queue was replaced.
    static func promptLoadPlaylist() -> Bool {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "m3u")!, .init(filenameExtension: "m3u8")!]
        // `Playlist.load` resolves a relative entry against the playlist's folder; a local
        // `URL(string:)` test accepts a bare filename and returns something unplayable.
        guard panel.runModal() == .OK, let url = panel.url,
              let urls = Playlist.load(from: url)?.trackURLs, !urls.isEmpty else { return false }
        let engine = WindowManager.shared.audioEngine
        engine.clearPlaylist()
        engine.loadFiles(urls)
        return true
    }

    /// Save the queue as an extended M3U (`Playlist.m3u(for:)`).
    static func promptSaveQueue() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "m3u")!]
        panel.nameFieldStringValue = "playlist.m3u"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? Playlist.m3u(for: WindowManager.shared.audioEngine.playlist)
            .write(to: url, atomically: true, encoding: .utf8)
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

    /// Rows whose file is gone from disk. A stream or server track has no file to check, so it is
    /// never dead.
    static func deadFileRows() -> Set<Int> {
        Set(WindowManager.shared.audioEngine.playlist.enumerated().filter { _, track in
            track.url.isFileURL && !FileManager.default.fileExists(atPath: track.url.path)
        }.map(\.offset))
    }

    static func removeDeadFiles() {
        removeTracks(at: deadFileRows())
    }

    static func showFileInfo(forTrackAt index: Int) {
        let tracks = WindowManager.shared.audioEngine.playlist
        guard index < tracks.count else { return }
        fileInfoAlert(for: tracks[index]).runModal()
    }

    /// The File Info sheet every playlist shows; the caller picks modal or sheet.
    static func fileInfoAlert(for track: Track) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = track.displayTitle
        alert.informativeText = [
            "Artist: \(track.artist ?? "Unknown")",
            "Album: \(track.album ?? "Unknown")",
            "Duration: \(track.formattedDuration)",
            track.url.isFileURL ? "Path: \(track.url.path)" : "URL: \(track.url.absoluteString)",
            EQProfileResolver.shared.fileInfoLine(for: track)
        ].compactMap { $0 }.joined(separator: "\n")
        return alert
    }
}
