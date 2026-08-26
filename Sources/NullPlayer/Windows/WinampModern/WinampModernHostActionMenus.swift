import AppKit
import Foundation
import NullPlayerCore
import UniformTypeIdentifiers

/// The four Winamp host-action families a `.wal` skin puts on a toolbar button — `VIS_*`, `PE_*`,
/// `VID_*` and `CB_*` (backlog B5).
///
/// Measured across the 17-skin corpus: **108 declarations in 11 skins**, every one of them a visible,
/// pressable button that reached the action switch's `default:` and stopped there. The commands
/// themselves are all machinery NullPlayer already has — the playlist queue, the visualization
/// window, the video window — so this file is mostly *routing*, plus the five playlist menus Winamp
/// puts behind ADD / REM / SEL / MISC / LIST.
///
/// One rule runs through all of it: **open the menu the app already has, not a second thinner one.**
/// The video button opens the video window's own context menu; the visualization button carries the
/// host's Visualizations menu; a playlist command is the same `AudioEngine` call the classic playlist
/// window makes. Three routes to the same feature must not drift apart.
extension WinampModernMainView {
    func performHostAction(_ hostAction: WinampModernHostAction, object: WasabiObject?) {
        switch hostAction {
        case .visualizationMenu: showVisualizationMenu(from: object)
        case .visualizationNext: stepVisualization(by: 1)
        case .visualizationPrevious: stepVisualization(by: -1)
        case .visualizationConfig: showVisualizationOptionsMenu(from: object)
        case .visualizationFullscreen: toggleVisualizationFullscreen()
        case .playlistAdd: showPlaylistAddMenu(from: object)
        case .playlistRemove: showPlaylistRemoveMenu(from: object)
        case .playlistSelect: showPlaylistSelectMenu(from: object)
        case .playlistMisc: showPlaylistMiscMenu(from: object)
        case .playlistList: showPlaylistListMenu(from: object)
        case .videoFullscreen: toggleVideoFullscreen()
        case .videoMenu: showVideoMenu(from: object)
        case .videoNativeSize(let multiple): sizeVideoToNative(multiple: multiple)
        case .componentBucketScroll(let delta, let page):
            // The strip is skin-wide, so an arrow in one window moves the bucket in all of them —
            // repaint whichever one this button lives in either way.
            renderer.scrollComponentBucket(by: delta, page: page)
            needsDisplay = true
        case .inert(let action, let reason): recordInertHostAction(action, reason: reason)
        }
    }

    /// A declared action we deliberately answer with nothing, recorded **once** in the skin's own
    /// diagnostics (`record` dedupes by message) so the demand shows up in a compatibility report
    /// instead of looking like a dead button of unknown cause.
    private func recordInertHostAction(_ action: String, reason: String) {
        renderer.loadedSkin.runtime.record(
            WalDiagnostic(.unsupportedElement,
                          "host action '\(action)' is accepted and inert: \(reason).",
                          severity: .warning))
    }

    // MARK: - VIS_* — the visualization

    /// `VIS_FS`. The skin's own AVS window carries this button in five of the eight corpus skins, and
    /// answering it with NullPlayer's window opened a *second* visualization beside the one already
    /// running in the skin's box. When the skin hosts the engine, the engine goes fullscreen.
    private func toggleVisualizationFullscreen() {
        if let surface = hostedVisualizationSurface {
            surface.toggleFullscreen()
            return
        }
        WindowManager.shared.showProjectMFullscreen()
    }

    /// `VIS_NEXT` / `VIS_PREV`.
    ///
    /// Two things can be "the visualization" at once, so the button points at whichever one the user
    /// is actually looking at: with NullPlayer's visualization window open, these step its **presets**
    /// (which is what Defix's Previous/Next pair, sat next to a Presets button, is asking for);
    /// otherwise they step the mode of the skin's own `<vis>` box — analyzer → oscilloscope → off,
    /// Winamp's own order — which is the visualization the skin is drawing in its own window.
    private func stepVisualization(by delta: Int) {
        // The skin's own AVS window first (B20a): when the box beside the button is a live engine,
        // that is unambiguously the visualization the user means, and it wins over both our separate
        // window and the `<vis>` box's mode.
        if let surface = hostedVisualizationSurface {
            surface.stepPreset(by: delta)
            return
        }
        if WindowManager.shared.isProjectMVisible {
            WindowManager.shared.stepProjectMPreset(by: delta)
            return
        }
        guard let mode = renderer.visualizationMode else { return }
        applyVisualizationMode(mode.stepped(by: delta))
    }

    private func applyVisualizationMode(_ mode: WasabiVisualizationMode) {
        guard renderer.setVisualizationMode(mode) else { return }
        needsDisplay = true
    }

    /// `VIS_MENU` — *which* visualization. The skin's own modes when it draws one, then the host's
    /// Visualizations menu, which is where the visualization window and the engine choice live.
    private func showVisualizationMenu(from object: WasabiObject?) {
        // A live engine in the skin's own AVS window brings its own controls, and they are the ones
        // that act on what the user is looking at (B20a).
        if let surface = hostedVisualizationSurface {
            popUpMenu(surface.buildMenu(), from: object)
            return
        }
        let menu = NSMenu(title: "Visualization")
        menu.autoenablesItems = false
        if let mode = renderer.visualizationMode {
            for candidate in WasabiVisualizationMode.allCases {
                let item = NSMenuItem(title: candidate.displayName,
                                      action: #selector(applyVisualizationModeFromMenu(_:)),
                                      keyEquivalent: "")
                item.target = self
                item.representedObject = candidate.attributeValue
                item.state = candidate == mode ? .on : .off
                menu.addItem(item)
            }
            menu.addItem(.separator())
            for item in visualizationOptionMenuItems(mode: mode) { menu.addItem(item) }
            menu.addItem(.separator())
        }
        let hostItem = NSMenuItem(title: "Visualizations", action: nil, keyEquivalent: "")
        hostItem.submenu = ContextMenuBuilder.buildVisualizationsMenu()
        menu.addItem(hostItem)
        popUpMenu(menu, from: object)
    }

    /// `VIS_CFG` — the options *of* the current visualization, which is what Defix labels "Options"
    /// next to its "Presets" button. With the visualization window up that is its own live menu
    /// (preset list, rating, engine settings); otherwise it is the analyzer's one real option.
    private func showVisualizationOptionsMenu(from object: WasabiObject?) {
        if let surface = hostedVisualizationSurface {
            popUpMenu(surface.buildMenu(), from: object)
            return
        }
        if WindowManager.shared.isProjectMVisible, let live = WindowManager.shared.buildVisualizationMenu() {
            popUpMenu(live, from: object)
            return
        }
        guard let mode = renderer.visualizationMode else {
            popUpMenu(ContextMenuBuilder.buildVisualizationsMenu(), from: object)
            return
        }
        let menu = NSMenu(title: "Visualization Options")
        menu.autoenablesItems = false
        for item in visualizationOptionMenuItems(mode: mode) { menu.addItem(item) }
        popUpMenu(menu, from: object)
    }

    /// The `<vis>` options the renderer actually reads, on the standing principle that *a menu item
    /// that changes nothing on screen is worse than no item*. Every one of these was inert until the
    /// renderer learned to read it, which is also why the skins that ship their own visualization
    /// page (Big Bento Modern, Love is War Miku) had a page that did nothing: they write these same
    /// attributes themselves.
    ///
    /// Each is enabled only for the mode it belongs to — greyed rather than hidden, so the menu says
    /// *why* an option is not available.
    private func visualizationOptionMenuItems(mode: WasabiVisualizationMode) -> [NSMenuItem] {
        let isAnalyzer = mode == .analyzer
        let isScope = mode == .oscilloscope
        var items = [analyzerBandwidthMenuItem(enabled: isAnalyzer)]
        // Winamp's own spelling of the values, which is what the skins' scripts write.
        items.append(visualizationSubmenu(
            title: "Oscilloscope Style", attribute: "oscstyle", enabled: isScope,
            entries: [("Lines", "Lines"), ("Dots", "Dots"), ("Solid", "Solid")],
            current: renderer.visualizationAttribute("oscstyle") ?? "Lines"))
        items.append(visualizationSubmenu(
            title: "Analyzer Coloring", attribute: "coloring", enabled: isAnalyzer,
            entries: [("Normal", "Normal"), ("Fire", "Fire"), ("Line", "Line")],
            current: renderer.visualizationAttribute("coloring") ?? "Normal"))
        // `peaks` is a flag, not a choice, so it is a single checked item rather than a submenu.
        let peaksOn = renderer.visualizationAttribute("peaks")?
            .trimmingCharacters(in: .whitespaces) != "0"
        let peaks = NSMenuItem(title: "Show Peaks", action: #selector(toggleAnalyzerPeaksFromMenu(_:)),
                               keyEquivalent: "")
        peaks.target = self
        peaks.state = peaksOn ? .on : .off
        peaks.representedObject = peaksOn ? "0" : "1"
        peaks.isEnabled = isAnalyzer
        items.append(peaks)
        // 0…4, Slower…Faster — measured off Big Bento's own menu script, not guessed
        // (`WasabiVisStyle.barFalloffSteps`).
        let speeds = ["Slower", "Slow", "Moderate", "Fast", "Faster"]
        for (title, attribute) in [("Analyzer Falloff Speed", "falloff"),
                                   ("Peak Falloff Speed", "peakfalloff")] {
            let step = WasabiVisStyle.falloffStep(renderer.visualizationAttribute(attribute))
            items.append(visualizationSubmenu(
                title: title, attribute: attribute, enabled: isAnalyzer,
                entries: speeds.enumerated().map { ($1, String($0)) },
                current: String(step)))
        }
        return items
    }

    private func visualizationSubmenu(title: String, attribute: String, enabled: Bool,
                                      entries: [(String, String)], current: String) -> NSMenuItem {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for (label, value) in entries {
            let item = NSMenuItem(title: label, action: #selector(applyVisualizationAttributeFromMenu(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = "\(attribute)=\(value)"
            item.state = value.caseInsensitiveCompare(current) == .orderedSame ? .on : .off
            item.isEnabled = enabled
            submenu.addItem(item)
        }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        item.isEnabled = enabled
        return item
    }

    /// `bandwidth` — Winamp's fat blocks (`wide`) or the full comb (`thin`). The only `<vis>` option
    /// the renderer actually reads, so it is the only one offered: a menu item that changes nothing
    /// on screen is worse than no item.
    private func analyzerBandwidthMenuItem(enabled: Bool) -> NSMenuItem {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let isThin = renderer.analyzerBandwidthIsThin
        for (title, value, on) in [("Wide", "wide", !isThin), ("Thin", "thin", isThin)] {
            let item = NSMenuItem(title: title, action: #selector(applyAnalyzerBandwidthFromMenu(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.state = on ? .on : .off
            item.isEnabled = enabled
            submenu.addItem(item)
        }
        let item = NSMenuItem(title: "Analyzer Bandwidth", action: nil, keyEquivalent: "")
        item.submenu = submenu
        item.isEnabled = enabled
        return item
    }

    @objc private func applyVisualizationModeFromMenu(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        applyVisualizationMode(WasabiVisualizationMode(attribute: value))
    }

    @objc private func applyVisualizationAttributeFromMenu(_ sender: NSMenuItem) {
        guard let spec = sender.representedObject as? String else { return }
        let parts = spec.split(separator: "=", maxSplits: 1)
        guard parts.count == 2 else { return }
        if renderer.setVisualizationAttribute(String(parts[0]), value: String(parts[1])) {
            needsDisplay = true
        }
    }

    @objc private func toggleAnalyzerPeaksFromMenu(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        if renderer.setVisualizationAttribute("peaks", value: value) { needsDisplay = true }
    }

    @objc private func applyAnalyzerBandwidthFromMenu(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        if renderer.setVisualizationAttribute("bandwidth", value: value) { needsDisplay = true }
    }

    // MARK: - PE_* — the playlist editor's five menus

    private var engine: AudioEngine { WindowManager.shared.audioEngine }

    /// `PE_ADD`.
    private func showPlaylistAddMenu(from object: WasabiObject?) {
        let menu = NSMenu(title: "Add")
        menu.autoenablesItems = false
        for (title, selector) in [("Add Files...", #selector(playlistAddFiles(_:))),
                                  ("Add Directory...", #selector(playlistAddDirectory(_:))),
                                  ("Add URL...", #selector(playlistAddURL(_:)))] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        popUpMenu(menu, from: object)
    }

    /// `PE_REM`. "Selected" and "Crop" are disabled with nothing selected rather than hidden — a
    /// greyed item says *why* it did nothing, an absent one does not.
    private func showPlaylistRemoveMenu(from object: WasabiObject?) {
        let hasSelection = !(componentHost?.playlistSnapshot().selectedRows.isEmpty ?? true)
        let menu = NSMenu(title: "Remove")
        menu.autoenablesItems = false
        for (title, selector, enabled) in
            [("Remove Selected", #selector(playlistRemoveSelected(_:)), hasSelection),
             ("Crop Selection", #selector(playlistCropSelection(_:)), hasSelection),
             ("Remove All", #selector(playlistRemoveAll(_:)), true),
             ("Remove Dead Files", #selector(playlistRemoveDeadFiles(_:)), true)] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self
            item.isEnabled = enabled
            menu.addItem(item)
        }
        popUpMenu(menu, from: object)
    }

    /// `PE_SEL`.
    private func showPlaylistSelectMenu(from object: WasabiObject?) {
        let menu = NSMenu(title: "Select")
        menu.autoenablesItems = false
        for (title, selector) in [("Select All", #selector(playlistSelectAll(_:))),
                                  ("Select None", #selector(playlistSelectNone(_:))),
                                  ("Invert Selection", #selector(playlistInvertSelection(_:)))] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        popUpMenu(menu, from: object)
    }

    /// `PE_MISC` — Winamp's sort submenu and the file info of the selected row.
    private func showPlaylistMiscMenu(from object: WasabiObject?) {
        let sort = NSMenu(title: "Sort")
        sort.autoenablesItems = false
        for (title, selector) in [("Sort by Title", #selector(playlistSortByTitle(_:))),
                                  ("Sort by Filename", #selector(playlistSortByFilename(_:))),
                                  ("Sort by Path", #selector(playlistSortByPath(_:))),
                                  ("Randomize", #selector(playlistRandomize(_:))),
                                  ("Reverse", #selector(playlistReverse(_:)))] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self
            sort.addItem(item)
        }
        let menu = NSMenu(title: "Misc")
        menu.autoenablesItems = false
        let sortItem = NSMenuItem(title: "Sort", action: nil, keyEquivalent: "")
        sortItem.submenu = sort
        menu.addItem(sortItem)
        menu.addItem(.separator())
        let info = NSMenuItem(title: "File Info...", action: #selector(playlistFileInfo(_:)),
                              keyEquivalent: "")
        info.target = self
        info.isEnabled = selectedPlaylistTrack() != nil
        menu.addItem(info)
        popUpMenu(menu, from: object)
    }

    /// `PE_LIST` (and `PE_LISTOFLISTS`, Winamp's playlist manager).
    private func showPlaylistListMenu(from object: WasabiObject?) {
        let menu = NSMenu(title: "List")
        menu.autoenablesItems = false
        for (title, selector) in [("New Playlist", #selector(playlistNew(_:))),
                                  ("Load Playlist...", #selector(playlistLoad(_:))),
                                  ("Save Playlist...", #selector(playlistSave(_:)))] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        popUpMenu(menu, from: object)
    }

    /// The row `PE_MISC`'s File Info is about: the selection's anchor, or the playing track when the
    /// user has not picked a row.
    private func selectedPlaylistTrack() -> Track? {
        let snapshot = componentHost?.playlistSnapshot() ?? .empty
        let index = snapshot.selectedIndex
        if index >= 0, engine.playlist.indices.contains(index) { return engine.playlist[index] }
        return engine.currentTrack
    }

    /// Everything a playlist command changes is visible in the skin's own embedded list, and in the
    /// classic playlist window if that is open too.
    private func playlistDidChange() {
        clampPlaylistScroll()
        WindowManager.shared.refreshWinampModernSurfaces()
        needsDisplay = true
    }

    // MARK: PE_ADD

    @objc private func playlistAddFiles(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.audio, .movie]
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        engine.loadFiles(panel.urls)
        playlistDidChange()
    }

    @objc private func playlistAddDirectory(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        LocalFileDiscovery.discoverMediaURLsAsync(from: [url], includeVideo: true) { [weak self] urls in
            guard let self, !urls.isEmpty else { return }
            self.engine.loadFiles(urls)
            self.playlistDidChange()
        }
    }

    @objc private func playlistAddURL(_ sender: Any?) {
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
        else { return }
        engine.loadFiles([url])
        playlistDidChange()
    }

    // MARK: PE_REM

    @objc private func playlistRemoveSelected(_ sender: Any?) {
        guard let componentHost else { return }
        componentHost.playlistRemoveRows(componentHost.playlistSnapshot().selectedRows)
        playlistDidChange()
    }

    @objc private func playlistCropSelection(_ sender: Any?) {
        guard let componentHost else { return }
        let snapshot = componentHost.playlistSnapshot()
        let victims = WinampModernPlaylistSelection.cropVictims(keeping: snapshot.selectedRows,
                                                               count: snapshot.rows.count)
        guard !victims.isEmpty else { return }
        componentHost.playlistRemoveRows(victims)
        playlistDidChange()
    }

    @objc private func playlistRemoveAll(_ sender: Any?) {
        engine.clearPlaylist()
        componentHost?.playlistSetSelection([])
        playlistDidChange()
    }

    /// Winamp's "remove dead files": every row whose file is gone, plus nothing else. A stream URL is
    /// not a dead file — it has no path to check — so remote rows are left alone.
    @objc private func playlistRemoveDeadFiles(_ sender: Any?) {
        let dead = Set(engine.playlist.enumerated().filter { _, track in
            track.url.isFileURL && !FileManager.default.fileExists(atPath: track.url.path)
        }.map(\.offset))
        guard !dead.isEmpty, let componentHost else { return }
        componentHost.playlistRemoveRows(dead)
        playlistDidChange()
    }

    // MARK: PE_SEL

    @objc private func playlistSelectAll(_ sender: Any?) {
        componentHost?.playlistSetSelection(
            WinampModernPlaylistSelection.all(count: engine.playlist.count))
        playlistDidChange()
    }

    @objc private func playlistSelectNone(_ sender: Any?) {
        componentHost?.playlistSetSelection([])
        playlistDidChange()
    }

    @objc private func playlistInvertSelection(_ sender: Any?) {
        guard let componentHost else { return }
        let snapshot = componentHost.playlistSnapshot()
        componentHost.playlistSetSelection(
            WinampModernPlaylistSelection.inverted(snapshot.selectedRows, count: snapshot.rows.count))
        playlistDidChange()
    }

    // MARK: PE_MISC

    @objc private func playlistSortByTitle(_ sender: Any?) {
        engine.sortPlaylist(by: .title)
        playlistDidChange()
    }

    @objc private func playlistSortByFilename(_ sender: Any?) {
        engine.sortPlaylist(by: .filename)
        playlistDidChange()
    }

    @objc private func playlistSortByPath(_ sender: Any?) {
        engine.sortPlaylist(by: .path)
        playlistDidChange()
    }

    @objc private func playlistRandomize(_ sender: Any?) {
        engine.shufflePlaylist()
        playlistDidChange()
    }

    @objc private func playlistReverse(_ sender: Any?) {
        engine.reversePlaylist()
        playlistDidChange()
    }

    /// The same File Info sheet `TRACKINFO` opens (Phase 36), aimed at the selected row rather than
    /// at whatever is playing — never `runModal()`, for the reason recorded there.
    @objc private func playlistFileInfo(_ sender: Any?) {
        guard let window, let track = selectedPlaylistTrack() else { return }
        let alert = NSAlert()
        alert.messageText = track.displayTitle
        alert.informativeText = [
            "Artist: \(track.artist ?? "Unknown")",
            "Album: \(track.album ?? "Unknown")",
            "Duration: \(track.formattedDuration)",
            track.url.isFileURL ? "Path: \(track.url.path)" : "URL: \(track.url.absoluteString)"
        ].joined(separator: "\n")
        alert.beginSheetModal(for: window)
    }

    // MARK: PE_LIST

    @objc private func playlistNew(_ sender: Any?) {
        playlistRemoveAll(sender)
    }

    @objc private func playlistSave(_ sender: Any?) {
        guard let type = UTType(filenameExtension: "m3u") else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = "playlist.m3u"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var content = "#EXTM3U\n"
        for track in engine.playlist {
            content += "#EXTINF:\(Int(track.duration ?? 0)),\(track.displayTitle)\n"
            content += "\(track.url.isFileURL ? track.url.path : track.url.absoluteString)\n"
        }
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    @objc private func playlistLoad(_ sender: Any?) {
        let types = ["m3u", "m3u8"].compactMap { UTType(filenameExtension: $0) }
        guard !types.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = types
        guard panel.runModal() == .OK, let url = panel.url,
              let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        let base = url.deletingLastPathComponent()
        let urls: [URL] = content.components(separatedBy: .newlines).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
            if let parsed = URL(string: trimmed), parsed.scheme != nil { return parsed }
            // A relative entry is relative to the playlist's own folder, which is how every .m3u
            // written next to its music is spelled.
            return trimmed.hasPrefix("/") ? URL(fileURLWithPath: trimmed)
                                          : base.appendingPathComponent(trimmed)
        }
        guard !urls.isEmpty else { return }
        engine.loadFiles(urls)
        playlistDidChange()
    }

    // MARK: - VID_* — the video window

    /// `VID_FS`. With no video window there is nothing to make fullscreen, and opening an empty one
    /// would be a black rectangle over the user's screen, so the button is inert until a video plays.
    private func toggleVideoFullscreen() {
        guard let controller = WindowManager.shared.currentVideoPlayerController,
              controller.window != nil else { return }
        // A hosted picture borrows itself back into the host's own window first: a `.wal` window is
        // `.borderless` and owns no fullscreen behaviour, and leaving fullscreen hands it back.
        if controller.isVideoOutputHosted {
            controller.enterFullScreenReclaimingOutput()
            return
        }
        controller.showWindow(nil)
        controller.toggleFullScreen(nil)
    }

    /// `VID_1X` / `VID_2X`. Only a **skin-hosted** picture has a box to size: the host's own video
    /// window is a free-floating rectangle the user sizes by dragging, and resizing it to the stream's
    /// dimensions behind their back is not what these buttons mean. Nothing happens when no video is
    /// playing or the decoder has not published a size yet.
    private func sizeVideoToNative(multiple: Int) {
        WindowManager.shared.sizeWinampModernVideoSurface(toNativeMultiple: CGFloat(multiple))
    }

    /// `VID_MISC` — the video window's own context menu (play/pause, skip, audio and subtitle track
    /// pickers), popped under the skin's button. Its items target the video view, so they work from
    /// here exactly as they do in that window.
    private func showVideoMenu(from object: WasabiObject?) {
        guard let menu = WindowManager.shared.currentVideoPlayerController?.contextMenu else { return }
        popUpMenu(menu, from: object)
    }
}
