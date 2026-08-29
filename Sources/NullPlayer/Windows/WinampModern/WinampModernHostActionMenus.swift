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
    func showVisualizationMenu(from object: WasabiObject?) {
        // A live engine in the skin's own AVS window brings its own controls, and they are the ones
        // that act on what the user is looking at (B20a).
        if let surface = hostedVisualizationSurface {
            popUpMenu(surface.buildMenu(), from: object)
            return
        }
        let menu = NSMenu(title: "Visualization")
        menu.autoenablesItems = false
        if let mode = renderer.visualizationMode {
            // **One group of modes, whoever draws them.** Winamp's own analyzer and oscilloscope and
            // NullPlayer's engines are four answers to the same question — what is in this box — and
            // they are mutually exclusive, so they are one radio list rather than a skin list and a
            // host list that each hold half the answer. `Off` stays with them: it is the skin saying
            // "nothing here", which is a fifth answer to the same question.
            let analyzer = renderer.spectrumAnalyzer
            for candidate in WasabiVisualizationMode.allCases {
                let item = NSMenuItem(title: candidate.displayName,
                                      action: #selector(applyVisualizationModeFromMenu(_:)),
                                      keyEquivalent: "")
                item.target = self
                item.representedObject = candidate.attributeValue
                // Winamp's modes are only what is on screen while Winamp's own engine is drawing.
                item.state = candidate == mode && (analyzer == .skin || candidate == .off)
                    ? .on : .off
                menu.addItem(item)
            }
            for item in spectrumAnalyzerModeItems(current: analyzer) { menu.addItem(item) }
            menu.addItem(.separator())
            for item in visualizationOptionMenuItems(mode: mode) { menu.addItem(item) }
            menu.addItem(.separator())
        }
        let hostItem = NSMenuItem(title: "Visualizations", action: nil, keyEquivalent: "")
        hostItem.submenu = ContextMenuBuilder.buildVisualizationsMenu()
        menu.addItem(hostItem)
        popUpMenu(menu, from: object)
    }

    /// The right-click menu over an unhosted `{0000000A}` pane — Big Bento Modern's stretched Multi
    /// Content View pane, its mini pane, and its Visualization tab (BB9).
    ///
    /// The same question, the same shape and the same engines as a `<vis>` box's menu above, against
    /// this surface's **own** selection: the pane is an empty plugin slot and the butterfly is the
    /// skin's artwork, so putting Cava in the pane must not overpaint the artwork. Winamp's own
    /// analyzer and oscilloscope, Cava and vis_classic are one radio group with `Off` last, because
    /// they are five answers to "what is in this box" and `Off` is the one that means "nothing".
    ///
    /// A pane the view layer has filled with the real visualization engine never reaches here — that
    /// one answers with the engine's own menu, in `rightMouseDown`.
    func showVisualizationHolderMenu(from object: WasabiObject?) {
        let menu = NSMenu(title: "Visualization")
        menu.autoenablesItems = false
        let suite = renderer.spectrumAnalyzer(for: .componentHolder)
        let mode = renderer.visualizationHolderMode
        func modeItem(_ candidate: WasabiVisualizationMode) -> NSMenuItem {
            let item = NSMenuItem(title: candidate.displayName,
                                  action: #selector(applyHolderVisualizationModeFromMenu(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = candidate.attributeValue
            // Winamp's modes are only what is on screen while Winamp's own engine is drawing.
            item.state = candidate == mode && (suite == .skin || candidate == .off) ? .on : .off
            return item
        }
        // Winamp's own two modes, then NullPlayer's engines, then `Off` — one group, read as a list
        // of things that can be *in* the pane with "nothing" last. `Off` is not a peer of the other
        // four (it is the absence of all of them), so it sits at the end of the group rather than
        // third in Winamp's own enum order.
        for candidate in WasabiVisualizationMode.allCases where candidate != .off {
            menu.addItem(modeItem(candidate))
        }
        for candidate in WinampModernSpectrumAnalyzer.allCases where candidate != .skin {
            let item = NSMenuItem(title: candidate.displayName,
                                  action: #selector(applyHolderSpectrumAnalyzerFromMenu(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = candidate.rawValue
            item.state = candidate == suite ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(modeItem(.off))
        menu.addItem(.separator())
        // The controls of whatever is actually drawing. The pane has no `<vis>` attributes, so for
        // Winamp's own engine the one control that applies is how loud we draw it.
        if suite != .skin,
           let engine = renderer.spectrumAnalyzerMenus().first(where: { $0.suite == suite }) {
            engine.menu.autoenablesItems = false
            let settings = NSMenuItem(title: "\(suite.displayName) Settings", action: nil,
                                      keyEquivalent: "")
            settings.submenu = engine.menu
            menu.addItem(settings)
        } else {
            menu.addItem(WinampModernVisSensitivityMenu.shared.menuItem(for: .skin))
        }
        menu.addItem(.separator())
        let hostItem = NSMenuItem(title: "Visualizations", action: nil, keyEquivalent: "")
        hostItem.submenu = ContextMenuBuilder.buildVisualizationsMenu()
        menu.addItem(hostItem)
        popUpMenu(menu, from: object, atMouse: object == nil)
    }

    @objc private func applyHolderVisualizationModeFromMenu(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        let mode = WasabiVisualizationMode(attribute: value)
        // The modes and the engines are one group, so picking a mode is also a choice about the
        // engine — see `WinampModernSpectrumAnalyzer.chosen(byPicking:current:)`, which owns that
        // rule and the defect it exists to prevent.
        let current = renderer.spectrumAnalyzer(for: .componentHolder)
        WindowManager.shared.setWinampModernVisualizationHolderEngine(
            .chosen(byPicking: mode, current: current))
        WindowManager.shared.setWinampModernVisualizationHolderMode(mode)
    }

    @objc private func applyHolderSpectrumAnalyzerFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        WindowManager.shared.setWinampModernVisualizationHolderEngine(
            WinampModernSpectrumAnalyzer.from(storedValue: raw))
        // Picking an engine out of a group whose other rows are modes means "put this in the pane",
        // so a pane the user had switched off is switched back on — the same rule the `<vis>` menu
        // follows one level up.
        if renderer.visualizationHolderMode == .off {
            WindowManager.shared.setWinampModernVisualizationHolderMode(.analyzer)
        }
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
        // Which engine is painting the box comes first, because it decides whether anything under it
        // means anything: Winamp's `oscstyle` and `coloring` are attributes of *Winamp's* analyzer,
        // and while Cava or vis_classic is drawing they are settings for a visualization nobody can
        // see. They stay visible and greyed, so the menu says why (B51's rule, one level up).
        let suite = renderer.spectrumAnalyzer
        let isSkinEngine = suite == .skin
        let isAnalyzer = isSkinEngine && mode == .analyzer
        let isScope = isSkinEngine && mode == .oscilloscope
        // Winamp's own `<vis>` options only. Each NullPlayer engine's settings live in that engine's
        // own row up in the mode group, beside the choice they belong to.
        var items: [NSMenuItem] = []
        if let settings = activeSpectrumAnalyzerSettingsItem() {
            items.append(settings)
            items.append(.separator())
        }
        items.append(analyzerBandwidthMenuItem(enabled: isAnalyzer))
        // Winamp's own analyzer reads hot off its decibel curve; this is where it is turned down to
        // meet the other two. Each engine keeps its own — the setting calibrates an engine's scale,
        // and Cava's and vis_classic's live in their own settings rows.
        items.append(WinampModernVisSensitivityMenu.shared.menuItem(for: .skin,
                                                                    enabled: isSkinEngine))
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

    /// The engine picker: Winamp's own analyzer/scope, or one of NullPlayer's (B53).
    ///
    /// Per skin, and the skin's own is the default — a skin looks the way its author drew it until
    /// the user says otherwise, which is the same rule the colour themes and Text Size follow.
    /// Add the engine picker and every engine's controls to a menu **the skin built**.
    ///
    /// A skin may claim the right button over its own visualization — Big Bento Modern covers its
    /// header analyzers with an invisible `main.vis.trigger` layer and pops its own settings page
    /// there — and on those skins the host's `<vis>` menu never opens at all, so everything B53 adds
    /// was unreachable from the box the user was actually pointing at.
    ///
    /// It can be appended because the skin's menu is **ours to build**: MAKI's `popAtMouse` is
    /// presented by `presentScriptPopup`, which turns the script's `PopupMenu` tree into an `NSMenu`.
    /// The skin's own rows are untouched and keep their command ids; ours carry their own targets and
    /// leave the id the script reads at 0, so a pick here is "nothing chosen" as far as the skin is
    /// concerned — which is exactly what it was before this section existed.
    /// - Returns: the command ids of the skin's own mode rows, so the caller can tell that the user
    ///   picked one of them and hand the box back to Winamp's engine.
    @discardableResult
    func appendSpectrumAnalyzerSection(to menu: NSMenu) -> Set<Int> {
        removePluginVisualizationRows(from: menu)
        let analyzer = renderer.spectrumAnalyzer
        // The skin's own mode rows — "Spectrum Analyzer", "Oscilloscope", "No Visualization" — are
        // the same question ours answer, so ours **join that group** rather than starting a second
        // one at the bottom of the menu.
        let modeRows = menu.items.enumerated().filter {
            Self.modeRowTitles.contains($0.element.title.trimmingCharacters(in: .whitespaces).lowercased())
        }
        var index = modeRows.last.map { $0.offset + 1 } ?? menu.numberOfItems
        for item in spectrumAnalyzerModeItems(current: analyzer) {
            menu.insertItem(item, at: min(index, menu.numberOfItems))
            index += 1
        }
        // While one of ours is drawing, the skin's checkmark is describing a visualization that is
        // not on screen.
        if analyzer != .skin {
            for row in modeRows { row.element.state = .off }
        }
        // The running engine's own controls. For one of NullPlayer's that is its settings row; for
        // the skin's own analyzer the skin has just listed its `<vis>` options itself (Show Peaks,
        // the falloffs, Coloring) and the one thing missing from that page is ours — how loud we
        // draw it. Either way the menu ends with the controls for what is actually on screen.
        menu.addItem(.separator())
        if let settings = activeSpectrumAnalyzerSettingsItem() {
            menu.addItem(settings)
        } else {
            menu.addItem(WinampModernVisSensitivityMenu.shared.menuItem(for: .skin))
        }
        return Set(modeRows.flatMap { Self.commandIDs(of: $0.element) })
    }

    /// Winamp's own labels for the `<vis>` modes, as a skin's menu spells them — ours are the same
    /// two words for the first two, and `No Visualization` is Winamp's wording for off.
    private static let modeRowTitles: Set<String> = [
        "spectrum analyzer", "oscilloscope", "no visualization", "off"
    ]

    /// A row's command id and every id beneath it: a mode row may carry its own submenu (the skin's
    /// Spectrum Analyzer row holds wide/thin), and the pick then arrives from the child.
    ///
    /// **Zero is excluded, and that is the whole point.** `0` is MAKI's "nothing was chosen", and a
    /// submenu parent carries it too — the skin's own `Spectrum Analyzer ▸` and `Oscilloscope ▸` rows
    /// are exactly that. Leaving it in the set meant every pick of *ours* matched, because ours
    /// deliberately leave the script's id at 0: choosing Cava selected Cava and then handed the box
    /// straight back to the skin's engine four milliseconds later.
    static func commandIDs(of item: NSMenuItem) -> [Int] {
        let own = item.tag != 0 ? [item.tag] : []
        return own + (item.submenu?.items.flatMap { commandIDs(of: $0) } ?? [])
    }

    /// NullPlayer's engines as mode rows — the other half of the group the skin's own rows start.
    ///
    /// Each row carries that engine's own settings in its submenu, which is the shape the skin's own
    /// rows already have (its `Spectrum Analyzer ▸` holds wide/thin). One row per engine, holding
    /// both the choice and its options: listing the engines in the group *and* their settings again
    /// at the foot of the menu read as two Cavas.
    ///
    /// AppKit sends no action for a row that owns a submenu, so the choice is the submenu's first
    /// entry rather than the parent. The parent still carries the checkmark, because that is the row
    /// the eye goes to when reading the group.
    private func spectrumAnalyzerModeItems(current: WinampModernSpectrumAnalyzer) -> [NSMenuItem] {
        WinampModernSpectrumAnalyzer.allCases.filter { $0 != .skin }.map { suite in
            let item = NSMenuItem(title: suite.displayName,
                                  action: #selector(applySpectrumAnalyzerFromMenu(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = suite.rawValue
            item.state = suite == current ? .on : .off
            item.isEnabled = true
            return item
        }
    }

    /// The running engine's own settings, as one row — named after it, and only when one of
    /// NullPlayer's engines is what is drawing. The choice itself is a plain row up in the mode
    /// group, so nothing about an engine appears twice.
    private func activeSpectrumAnalyzerSettingsItem() -> NSMenuItem? {
        let active = renderer.spectrumAnalyzer
        guard active != .skin,
              let engine = renderer.spectrumAnalyzerMenus().first(where: { $0.suite == active })
        else { return nil }
        engine.menu.autoenablesItems = false
        let item = NSMenuItem(title: "\(active.displayName) Settings", action: nil, keyEquivalent: "")
        item.submenu = engine.menu
        return item
    }

    /// Drop the skin's **Classic Visualization** row on the way past.
    ///
    /// It is Winamp's *visualization plugin* switch — "draw this box with the classic vis plugin
    /// instead of the built-in analyzer" — and NullPlayer hosts no Winamp plugins, so the row does
    /// nothing here. It is also, word for word, the choice the section below now owns: leaving it in
    /// puts two answers to "what draws this box" in one menu, one of which is inert.
    ///
    /// **Only when we are appending our own section**, which is only over a `<vis>` box. Everywhere
    /// else the skin's menu is left exactly as the skin built it — filtering a skin's own rows is not
    /// something to do lightly, and this is the one row our section replaces outright.
    private func removePluginVisualizationRows(from menu: NSMenu) {
        for item in menu.items where Self.pluginVisualizationTitles.contains(
            item.title.trimmingCharacters(in: .whitespaces).lowercased()) {
            menu.removeItem(item)
        }
        // A row taken out of the middle can leave two separators against each other, or a trailing
        // one — the seam it used to fill.
        var index = menu.numberOfItems - 1
        while index > 0 {
            if menu.item(at: index)?.isSeparatorItem == true,
               index == menu.numberOfItems - 1 || menu.item(at: index - 1)?.isSeparatorItem == true {
                menu.removeItem(at: index)
            }
            index -= 1
        }
    }

    /// Winamp's own spelling of that row, and the British variant a translated skin may carry.
    private static let pluginVisualizationTitles: Set<String> = [
        "classic visualization", "classic visualisation"
    ]

    @objc private func applySpectrumAnalyzerFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        // Through the controller, not this view: a separate-window skin draws its `<vis>` in an
        // auxiliary container too, and setting only this renderer would move the checkmark while
        // half the skin kept drawing the outgoing engine. Same route the Text Size menu takes.
        WindowManager.shared.setWinampModernSpectrumAnalyzer(WinampModernSpectrumAnalyzer.from(storedValue: raw))
        // Picking an engine from a group whose other rows are modes means "put this in the box", so a
        // box the skin currently has switched off is switched on. Only ever on an explicit pick —
        // nothing else in the engine path writes the skin's `mode`.
        if renderer.visualizationMode == .off { applyVisualizationMode(.analyzer) }
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
