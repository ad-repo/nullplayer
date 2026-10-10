import AppKit

// The Skins menu's per-family submenus, picking and loading a skin in any family, and the
// "Remove …" action they share.

extension ContextMenuBuilder {

    /// One skin family's submenu, in the order every family uses: a "Switch to" row outside its own
    /// mode, the family's options, then its skins after one divider.
    static func buildSkinFamilyMenu(switchItem: NSMenuItem?, options: [NSMenuItem],
                                            skins: [NSMenuItem]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        if let switchItem {
            menu.addItem(switchItem)
            menu.addItem(.separator())
        }
        options.forEach(menu.addItem)
        menu.addItem(.separator())
        if skins.isEmpty {
            let empty = NSMenuItem(title: "No skins installed", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            skins.forEach(menu.addItem)
        }
        return menu
    }

    private static func skinMenuItem(_ title: String, _ action: Selector,
                                     representedObject: Any? = nil, isOn: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = MenuActions.shared
        item.representedObject = representedObject
        if isOn { item.state = .on }
        return item
    }

    /// "Switch to <family> (<skin>)", or nil while that family is already the one on screen.
    private static func switchItem(to mode: PlayerUIMode, skinName: String? = nil,
                                   action: Selector) -> NSMenuItem? {
        guard WindowManager.shared.uiMode != mode else { return nil }
        return skinMenuItem("Switch to \(mode.displayName)" + (skinName.map { " (\($0))" } ?? ""), action)
    }

    /// "Remove “Name”...", present only while the family's current skin is one the user installed.
    private static func removeSkinItem(for mode: PlayerUIMode) -> NSMenuItem? {
        MenuActions.removableSkin(for: mode).map {
            skinMenuItem("Remove \u{201c}\($0.name)\u{201d}...", #selector(MenuActions.removeCurrentSkin(_:)),
                         representedObject: mode)
        }
    }

    /// The family submenu with its parent item, checked while that family is on screen.
    static func skinFamilyItem(_ mode: PlayerUIMode, menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: mode.displayName, action: nil, keyEquivalent: "")
        if WindowManager.shared.uiMode == mode { item.state = .on }
        item.submenu = menu
        return item
    }

    // MARK: - Classic

    static func buildClassicSkinsMenu() -> NSMenu {
        let wm = WindowManager.shared
        let lastSkinName = UserDefaults.standard.string(forKey: WindowManager.lastClassicSkinPathKey)
            .map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }
        let options = [
            skinMenuItem("Load Skin...", #selector(MenuActions.loadSkinFromFile)),
            skinMenuItem("Get More Skins...", #selector(MenuActions.getMoreClassicSkins)),
            skinMenuItem("Open Skins Folder...", #selector(MenuActions.openClassicSkinsFolder)),
            removeSkinItem(for: .classic),
        ].compactMap { $0 }
        let isActive = wm.uiMode == .classic
        let skins = wm.availableSkins().map {
            skinMenuItem($0.name, #selector(MenuActions.selectClassicSkin(_:)), representedObject: $0.url,
                         isOn: isActive && wm.currentSkinPath == $0.url.path)
        }
        return buildSkinFamilyMenu(
            switchItem: switchItem(to: .classic, skinName: lastSkinName, action: #selector(MenuActions.setClassicMode)),
            options: options, skins: skins)
    }

    // MARK: - Original and Original-Metal

    /// The Original or Original-Metal submenu. Every item carries its family, so both families
    /// share one action per job.
    static func buildModernFamilySkinsMenu(_ family: ModernSkinFamily) -> NSMenu {
        let mode = family.playerUIMode
        let engine = ModernSkinEngine.shared
        let isActive = WindowManager.shared.uiMode == mode
        let current = engine.currentSkinName(for: family)
        // Original-Metal names itself in its own entries; Original, the older family, does not.
        let qualifier = family == .metal ? "\(family.displayName) " : ""
        let options = [
            skinMenuItem("Load \(qualifier)Skin...", #selector(MenuActions.loadModernFamilySkin(_:)),
                         representedObject: family),
            isActive ? skinMenuItem("Reset Skin to Default", #selector(MenuActions.resetCurrentSkinToDefault)) : nil,
            skinMenuItem("Open \(qualifier)Skins Folder...", #selector(MenuActions.openModernFamilySkinsFolder(_:)),
                         representedObject: family),
            removeSkinItem(for: mode),
        ].compactMap { $0 }
        let skins = engine.availableSkins(for: family).map {
            skinMenuItem($0.name, #selector(MenuActions.selectModernFamilySkin(_:)),
                         representedObject: MenuActions.ModernFamilySkinChoice(family: family, name: $0.name),
                         isOn: isActive && $0.name == current)
        }
        let switchItem = switchItem(to: mode, skinName: UserDefaults.standard.string(forKey: family.skinNameKey),
                                    action: #selector(MenuActions.setModernFamilyMode(_:)))
        switchItem?.representedObject = family
        return buildSkinFamilyMenu(switchItem: switchItem, options: options, skins: skins)
    }

    // MARK: - Modern (.wal)

    /// Winamp 5.x `.wal` skins, presented to the user as the **Modern** family. The runtime loads,
    /// scripts, and renders real skins, but widgets backed by Winamp's built-in `wasabi.*` artwork
    /// draw empty and the hosted playlist/EQ are engine-drawn rather than painted with the skin's
    /// own bitmaps. See `skills/winamp-modern-skin-guide/`.
    static func buildWinampModernSkinsMenu() -> NSMenu {
        let wm = WindowManager.shared
        // Where skins come from: load one, find more (WinampHeritage is the archive that still
        // hosts `.wal` skins), and the folder they land in.
        var options = [
            skinMenuItem("Load Skin...", #selector(MenuActions.loadWinampModernSkinFromFile)),
            skinMenuItem("Get More Skins...", #selector(MenuActions.getMoreWinampModernSkins)),
            skinMenuItem("Open Skins Folder...", #selector(MenuActions.openWinampModernSkinsFolder)),
            removeSkinItem(for: .winampModern),
        ].compactMap { $0 }

        // Everything configured for the **loaded skin**, in one block: what it can be coloured
        // as and what it lets the user configure. Window-related controls live together in the
        // Windows menu: Text Size sits beside UI Size, and skin-defined windows follow the
        // NullPlayer window block. These entries depend on the skin declaring them, so the
        // group's separator is placed around what was actually added.
        var skinSpecific: [NSMenuItem] = []

        // Which visualization the skin's `<vis>` box draws (B53) — only for a skin that declares
        // one. Defix declares none (its VIS buttons are a toolbar over the host's own
        // visualization window), and an engine picker with no box to paint would be an item that
        // changes nothing on screen.
        if wm.winampModernHasVisualizationBox {
            skinSpecific.append(buildWinampModernSpectrumAnalyzerMenuItem(wm: wm))
        }

        // The waveform seeker the host fills a reserved strip with (BB18) — only for a skin that
        // reserves one. Two skins in the corpus do, so this is absent for almost every skin, on
        // the same rule as the analyzer picker above.
        let seeker = wm.winampModernWaveformSeeker
        if seeker.declared {
            let item = NSMenuItem(title: "Waveform Seeker",
                                  action: #selector(MenuActions.toggleWinampModernWaveformSeeker),
                                  keyEquivalent: "")
            item.target = MenuActions.shared
            item.state = seeker.enabled ? .on : .off
            skinSpecific.append(item)
        }

        // The skin's colour themes (Phase 32). A secondary route where the skin ships its own
        // picker, and the *only* route on the six measured skins that define themes and ship
        // none — in Winamp those live in its preferences dialog. Gated on more than one theme:
        // a skin with a single gammaset has nothing to choose between, and one with none at all
        // reports an empty list.
        let colorThemes = WindowManager.shared.winampModernColorThemes
        if colorThemes.names.count > 1 {
            let themesItem = NSMenuItem(title: "Color Themes", action: nil, keyEquivalent: "")
            let themesMenu = NSMenu()
            themesMenu.autoenablesItems = false
            for name in colorThemes.names {
                let item = NSMenuItem(title: name,
                                      action: #selector(MenuActions.selectWinampModernColorTheme(_:)),
                                      keyEquivalent: "")
                item.target = MenuActions.shared
                item.representedObject = name
                if name.caseInsensitiveCompare(colorThemes.active) == .orderedSame { item.state = .on }
                themesMenu.addItem(item)
            }
            themesItem.submenu = themesMenu
            skinSpecific.append(themesItem)
        }

        // The user's own colours for this skin (B146), directly under Color Themes because it is
        // scoped to the theme selected there: winampmodern566's 88 gammasets re-tint the list
        // roles independently, so an override belongs to one theme and the two entries are read
        // together. Gated on a *loaded* skin rather than on the mode alone — the placeholder has
        // no palette worth overriding, and nothing outside `.winampModern` has one at all.
        if wm.canEditWinampModernSkinColors {
            let colorsItem = NSMenuItem(title: "Skin Colors...",
                                        action: #selector(MenuActions.showWinampModernSkinColors),
                                        keyEquivalent: "")
            colorsItem.target = MenuActions.shared
            skinSpecific.append(colorsItem)
        }

        // Only when the loaded skin registered settings of its own: many skins register none,
        // and an empty window is worse than no entry point (Phase 27.3).
        if WindowManager.shared.hasWinampModernSkinSettings {
            let settingsItem = NSMenuItem(title: "Skin Settings...",
                                          action: #selector(MenuActions.showWinampModernSkinSettings),
                                          keyEquivalent: "")
            settingsItem.target = MenuActions.shared
            skinSpecific.append(settingsItem)
        }

        if !skinSpecific.isEmpty {
            options += [.separator()] + skinSpecific
        }

        // The ClassicPro engine a cPro skin needs imported before it can run at all. It follows
        // the loaded skin's options so the top of this menu matches Classic's and Media Player's.
        options.append(NSMenuItem.separator())
        let engineInstalled = ClassicProEngineStore.shared.isInstalled
        let engineItem = NSMenuItem(
            title: engineInstalled ? "Reimport ClassicPro Engine..." : "Import ClassicPro Engine...",
            action: #selector(MenuActions.importClassicProEngineFromFile), keyEquivalent: "")
        engineItem.target = MenuActions.shared
        if engineInstalled { engineItem.state = .on }
        options.append(engineItem)

        let downloadEngineItem = NSMenuItem(title: "Download ClassicPro Engine...",
                                            action: #selector(MenuActions.downloadClassicProEngine), keyEquivalent: "")
        downloadEngineItem.target = MenuActions.shared
        options.append(downloadEngineItem)

        // Whether the installed engine is the build we test against. The engine is third-party
        // and user-supplied, so an untested build is allowed \u{2014} it just must not be silent.
        if engineInstalled {
            let verdict = ClassicProEngineStore.shared.info()?.provenanceVerdict
            let title: String
            switch verdict {
            case .knownGood: title = "Engine: verified 2.01"
            // An installed engine with unreadable info is untested for the same reason an
            // unrecognized one is: nothing vouches for what is on disk.
            case .unrecognized, .none: title = "\u{26A0}\u{FE0E} Engine: untested build"
            case .treeMismatch: title = "\u{26A0}\u{FE0E} Engine: unexpected contents"
            }
            let status = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            status.isEnabled = false
            options.append(status)
        }


        let importer = WinampModernSkinImporter.shared
        let selected = importer.selectedSkin()?.archiveURL
        let skins = importer.installedSkins().map {
            skinMenuItem($0.name, #selector(MenuActions.selectWinampModernSkin(_:)),
                         representedObject: $0.archiveURL, isOn: $0.archiveURL == selected)
        }
        return buildSkinFamilyMenu(
            switchItem: switchItem(to: .winampModern, action: #selector(MenuActions.setWinampModernMode)),
            options: options, skins: skins)
    }

    // MARK: - Media Player (.wmz)

    static func buildWMPSkinsMenu() -> NSMenu {
        let wm = WindowManager.shared
        let importer = WMPSkinImporter()
        let isActive = wm.uiMode == .wmp
        var options = [
            skinMenuItem("Load Skin...", #selector(MenuActions.loadWMPSkinFromFile)),
            skinMenuItem("Get More Skins...", #selector(MenuActions.getMoreWMPSkins)),
            skinMenuItem("Open Skins Folder...", #selector(MenuActions.openWMPSkinsFolder)),
            removeSkinItem(for: .wmp),
        ].compactMap { $0 }
        if isActive,
           let controller = wm.mainWindowController as? WMPMainWindowController,
           controller.availableViewIDs.count > 1 {
            let viewsItem = NSMenuItem(title: "Views", action: nil, keyEquivalent: "")
            let viewsMenu = NSMenu()
            for viewID in controller.availableViewIDs {
                viewsMenu.addItem(skinMenuItem(
                    viewID, #selector(MenuActions.selectWMPView(_:)), representedObject: viewID,
                    isOn: controller.selectedViewID?.caseInsensitiveCompare(viewID) == .orderedSame))
            }
            viewsItem.submenu = viewsMenu
            options.append(viewsItem)
        }
        let skins = importer.installedSkins().map {
            skinMenuItem($0.name, #selector(MenuActions.selectWMPSkin(_:)), representedObject: $0.name,
                         isOn: isActive && importer.selectedSkinName?.caseInsensitiveCompare($0.name) == .orderedSame)
        }
        return buildSkinFamilyMenu(
            switchItem: switchItem(to: .wmp, action: #selector(MenuActions.setWMPMode)),
            options: options, skins: skins)
    }

    // MARK: - Audion Faces

    /// Above this many faces the list is grouped into A–Z submenus: Panic's archive alone is 856.
    static let audionFacesFlatListLimit = 40

    static func buildAudionFacesMenu() -> NSMenu {
        let importer = AudionFaceImporter()
        let isActive = WindowManager.shared.uiMode == .audion
        let options = [
            skinMenuItem("Load Face...", #selector(MenuActions.loadAudionFaceFromFile)),
            skinMenuItem("Get More Faces...", #selector(MenuActions.getMoreAudionFaces)),
            skinMenuItem("Open Faces Folder...", #selector(MenuActions.openAudionFacesFolder)),
            removeSkinItem(for: .audion),
        ].compactMap { $0 }
        let faces = importer.installedFaces().map {
            skinMenuItem($0.name, #selector(MenuActions.selectAudionFace(_:)), representedObject: $0.name,
                         isOn: isActive && importer.selectedFaceName == $0.name)
        }
        return buildSkinFamilyMenu(
            switchItem: switchItem(to: .audion, action: #selector(MenuActions.setAudionMode)),
            options: options, skins: groupedAlphabetically(faces, over: audionFacesFlatListLimit))
    }

    /// `items` as one submenu per initial letter (`#` for the rest) once there are more than `limit`.
    /// A submenu holding the checked item is checked too, so the current face can be found.
    static func groupedAlphabetically(_ items: [NSMenuItem], over limit: Int) -> [NSMenuItem] {
        guard items.count > limit else { return items }
        func key(_ item: NSMenuItem) -> String {
            let initial = item.title.trimmingCharacters(in: .whitespaces).prefix(1)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).uppercased()
            return ("A"..."Z").contains(initial) && initial.count == 1 ? initial : "#"
        }
        func rank(_ letter: String) -> String { letter == "#" ? "~" : letter } // `#` after Z
        let groups = Dictionary(grouping: items, by: key).sorted { rank($0.key) < rank($1.key) }
        return groups.map { letter, group in
            let menu = NSMenu()
            menu.autoenablesItems = false
            group.forEach(menu.addItem)
            let parent = NSMenuItem(title: letter, action: nil, keyEquivalent: "")
            if group.contains(where: { $0.state == .on }) { parent.state = .on }
            parent.submenu = menu
            return parent
        }
    }
}

// MARK: - Original and Original-Metal actions

extension MenuActions {

    /// A row in the Original or Original-Metal skin list.
    struct ModernFamilySkinChoice {
        let family: ModernSkinFamily
        let name: String
    }

    @objc func setModernFamilyMode(_ sender: NSMenuItem) {
        guard let family = sender.representedObject as? ModernSkinFamily,
              AppCapabilities.supports(family.appFeature) else { return }
        let wm = WindowManager.shared
        guard wm.uiMode != family.playerUIMode else { return }
        SkinLoadingOverlay.shared.run { wm.reloadUI(to: family.playerUIMode) }
    }

    @objc func loadModernFamilySkin(_ sender: NSMenuItem) {
        guard let family = sender.representedObject as? ModernSkinFamily else { return }
        loadModernFamilySkinFromFile(family: family)
    }

    @objc func openModernFamilySkinsFolder(_ sender: NSMenuItem) {
        guard let family = sender.representedObject as? ModernSkinFamily else { return }
        ModernSkinEngine.shared.openSkinsFolderForFamily(family)
    }
}

// MARK: - Picking and loading a skin

/// Picking a skin from a family's list, or loading one with its Load Skin..., shows that skin, switching
/// into the family from whichever one is on screen.
extension MenuActions {

    /// Shows the skin just chosen for `mode`'s family. The choice is already saved, so entering the
    /// family loads it; inside the family, `loadInPlace` does. `completion` runs once the skin is up,
    /// which Compact Mode can defer past the overlay.
    private func showChosenSkin(in mode: PlayerUIMode, loadInPlace: () -> Void,
                                completion: (() -> Void)? = nil) {
        let wm = WindowManager.shared
        SkinLoadingOverlay.shared.run {
            if wm.uiMode == mode {
                loadInPlace()
                completion?()
            } else {
                wm.reloadUI(to: mode, completion: completion)
            }
        }
    }

    private func chooseSkinFile(_ fileExtension: String, message: String? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.init(filenameExtension: fileExtension)!]
        if let message { panel.message = message }
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    private func showSkinAlert(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.alertStyle = .warning
        alert.runModal()
    }

    // MARK: Classic

    /// Classic windows render `currentSkin`, so the skin is loaded first. The switch does nothing
    /// when Classic is already on screen.
    @objc func selectClassicSkin(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        let wm = WindowManager.shared
        SkinLoadingOverlay.shared.run {
            wm.loadSkin(from: url)
            wm.reloadUI(to: .classic)
        }
    }

    @objc func loadSkinFromFile() {
        guard let url = chooseSkinFile("wsz") else { return }
        let wm = WindowManager.shared
        do {
            let importedURL = try wm.importClassicSkin(from: url)
            let loaded = SkinLoadingOverlay.shared.run { () -> Bool in
                guard wm.loadSkin(from: importedURL) else { return false }
                wm.reloadUI(to: .classic)
                return true
            }
            if !loaded {
                showSkinAlert("Failed to Load Classic Skin", "The skin was imported but could not be loaded.")
            }
        } catch {
            showSkinAlert("Failed to Import Classic Skin", error.localizedDescription)
        }
    }

    // MARK: Original and Original-Metal

    @objc func selectModernFamilySkin(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? ModernFamilySkinChoice else { return }
        // Entering the family loads this key (`prepareUIRuntime` → `loadPreferredSkin()`).
        UserDefaults.standard.set(choice.name, forKey: choice.family.skinNameKey)
        showChosenSkin(in: choice.family.playerUIMode) {
            ModernSkinEngine.shared.loadSkin(named: choice.name, family: choice.family)
        }
    }

    func loadModernFamilySkinFromFile(family: ModernSkinFamily) {
        let ext = ModernSkinLoader.bundleExtension
        guard let url = chooseSkinFile(ext, message: "Select a .\(ext) \(family.displayName) skin bundle")
        else { return }
        let engine = ModernSkinEngine.shared
        do {
            // The import saves the skin as the family's choice.
            let name = try engine.importSkinBundle(from: url, family: family)
            showChosenSkin(in: family.playerUIMode, loadInPlace: {
                engine.loadSkin(named: name, family: family)
            }, completion: {
                guard engine.currentSkinName != name else { return }
                // It did not load. The family's choice goes back to the skin left on screen: the one
                // that was showing, or the family default when entering it.
                UserDefaults.standard.set(engine.currentSkinName, forKey: family.skinNameKey)
                DispatchQueue.main.async {  // after the loading overlay is gone
                    self.showSkinAlert("Failed to Load \(family.displayName) Skin",
                                       "The skin was imported but could not be loaded.")
                }
            })
        } catch {
            showSkinAlert("Failed to Import \(family.displayName) Skin", error.localizedDescription)
        }
    }

    // MARK: Modern (.wal)

    @objc func selectWinampModernSkin(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        WinampModernSkinImporter.shared.selectSkin(
            WinampModernImportedSkin(name: url.deletingPathExtension().lastPathComponent, archiveURL: url))
        showChosenSkin(in: .winampModern) { loadWinampModernSkinInPlace(at: url) }
    }

    @objc func loadWinampModernSkinFromFile() {
        guard let url = chooseSkinFile("wal", message: "Select a Winamp 5.x .wal skin archive") else { return }
        do {
            // The import selects the skin.
            let imported = try WinampModernSkinImporter.shared.importContainer(at: url)
            NSLog("WinampModern: Imported validated skin '%@' to %@", imported.name, imported.archiveURL.path)
            showChosenSkin(in: .winampModern) { loadWinampModernSkinInPlace(at: imported.archiveURL) }
        } catch {
            showSkinAlert("Failed to Import \(PlayerUIMode.winampModern.displayName) Skin",
                          error.localizedDescription)
        }
    }

    /// A `.wal` window's size *is* the skin, so a larger one grows every window in place around its
    /// top-left — off the display, for a skin wide or tall enough.
    func loadWinampModernSkinInPlace(at url: URL) {
        (WindowManager.shared.mainWindowController as? WinampModernMainWindowController)?.loadSkin(at: url)
        WindowManager.shared.ensureAllWindowsOnScreen()
    }

    // MARK: Media Player (.wmz)

    // The WMP controller owns its in-place selection and import: both run asynchronously and report
    // into the skin window, so these do not go through `showChosenSkin`.

    @objc func selectWMPSkin(_ sender: NSMenuItem) {
        guard AppCapabilities.supports(.wmpSkinMode),
              let name = sender.representedObject as? String else { return }
        let wm = WindowManager.shared
        if let controller = wm.mainWindowController as? WMPMainWindowController {
            controller.selectInstalledSkin(named: name)
        } else if let skin = WMPSkinImporter().installedSkins().first(where: {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) {
            WMPSkinImporter().select(skin)
            wm.reloadUI(to: .wmp)
        }
    }

    @objc func loadWMPSkinFromFile() {
        guard AppCapabilities.supports(.wmpSkinMode) else { return }
        if let controller = WindowManager.shared.mainWindowController as? WMPMainWindowController {
            controller.importSkinFromPanel()
            return
        }
        guard let url = chooseSkinFile("wmz") else { return }
        Task {
            do {
                _ = try await WMPSkinImporter().importSkin(from: url)
                await MainActor.run { WindowManager.shared.reloadUI(to: .wmp) }
            } catch {
                await MainActor.run {
                    let alert = NSAlert(error: error)
                    alert.messageText = "Failed to Import WMP Skin"
                    alert.runModal()
                }
            }
        }
    }
}

// MARK: - Next skin

extension MenuActions {

    @objc func selectNextSkin() { stepSkin(by: 1) }
    @objc func selectPreviousSkin() { stepSkin(by: -1) }

    /// Steps through the on-screen family's skin list, wrapping, by sending that row's own action —
    /// so it switches exactly as picking the row from the Skins menu does.
    private func stepSkin(by step: Int) {
        let menu: NSMenu
        switch WindowManager.shared.uiMode {
        case .classic: menu = ContextMenuBuilder.buildClassicSkinsMenu()
        case .modern: menu = ContextMenuBuilder.buildModernFamilySkinsMenu(.modern)
        case .metal: menu = ContextMenuBuilder.buildModernFamilySkinsMenu(.metal)
        case .winampModern: menu = ContextMenuBuilder.buildWinampModernSkinsMenu()
        case .wmp: menu = ContextMenuBuilder.buildWMPSkinsMenu()
        case .audion: menu = ContextMenuBuilder.buildAudionFacesMenu()
        }
        // The skins follow the menu's last divider; Audion's may be grouped into A–Z submenus.
        func rows(_ items: [NSMenuItem]) -> [NSMenuItem] {
            items.flatMap { $0.submenu.map { rows($0.items) } ?? [$0] }
        }
        let start = (menu.items.lastIndex(where: \.isSeparatorItem) ?? -1) + 1
        let skins = rows(Array(menu.items[start...])).filter { $0.action != nil }
        guard !skins.isEmpty else { return }
        let current = skins.firstIndex { $0.state == .on } ?? (step > 0 ? -1 : skins.count)
        let next = skins[(current + step + skins.count) % skins.count]
        NSApp.sendAction(next.action!, to: next.target, from: next)
    }
}

// MARK: - Removing a skin

extension MenuActions {

    /// A skin "Remove …" can take away: the family's current skin, when the user installed it.
    enum RemovableSkin {
        case classic(URL)
        case modernFamily(ModernSkinEngine.SkinInfo, ModernSkinFamily)
        case winampModern(WinampModernImportedSkin)
        case wmp(name: String)
        case audion(name: String)

        var name: String {
            switch self {
            case .classic(let url): return url.deletingPathExtension().lastPathComponent
            case .modernFamily(let skin, _): return skin.name
            case .winampModern(let skin): return skin.name
            case .wmp(let name), .audion(let name): return name
            }
        }
    }

    static func removableSkin(for mode: PlayerUIMode) -> RemovableSkin? {
        switch mode {
        case .classic:
            return WindowManager.shared.removableClassicSkinURL().map(RemovableSkin.classic)
        case .modern, .metal:
            guard let family = mode.modernSkinFamily,
                  let skin = ModernSkinEngine.shared.removableSkin(for: family) else { return nil }
            return .modernFamily(skin, family)
        case .winampModern:
            return WinampModernSkinImporter.shared.removableSelectedSkin().map(RemovableSkin.winampModern)
        case .wmp:
            guard AppCapabilities.supports(.wmpSkinMode) else { return nil }
            return WMPSkinImporter().selectedSkinName.map { .wmp(name: $0) }
        case .audion:
            guard AppCapabilities.supports(.audionFaceMode) else { return nil }
            return AudionFaceImporter().selectedFaceName.map { .audion(name: $0) }
        }
    }

    /// Removes the current skin of the family named by the item's `representedObject` (its
    /// `PlayerUIMode`), after asking. A trashed skin can be recovered from the Trash; a
    /// `.wmz` skin's installed copy is deleted, and the file it was imported from is untouched.
    /// The family falls back to its built-in skin.
    @objc func removeCurrentSkin(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? PlayerUIMode,
              let skin = Self.removableSkin(for: mode) else { return }
        let alert = NSAlert()
        alert.messageText = "Remove Skin?"
        switch skin {
        case .wmp, .audion:
            alert.informativeText = "\u{201c}\(skin.name)\u{201d} will be removed from NullPlayer. "
                + "The original downloaded file is not affected."
        case .classic, .modernFamily, .winampModern:
            alert.informativeText = "\u{201c}\(skin.name)\u{201d} will be moved to the Trash."
        }
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let wm = WindowManager.shared
        let isOnScreen = wm.uiMode == mode
        do {
            switch skin {
            case .classic(let url):
                try wm.trashClassicSkin(at: url)
                if isOnScreen { SkinLoadingOverlay.shared.run { wm.loadBundledDefaultSkin() } }
            case .modernFamily(let info, let family):
                try ModernSkinEngine.shared.trashSkin(info, family: family)
                if isOnScreen { SkinLoadingOverlay.shared.run { ModernSkinEngine.shared.loadDefaultSkin(for: family) } }
            case .winampModern(let wal):
                let importer = WinampModernSkinImporter.shared
                try importer.trashSkin(wal)
                guard isOnScreen, let next = importer.selectedSkin() else { return }
                SkinLoadingOverlay.shared.run {
                    (wm.mainWindowController as? WinampModernMainWindowController)?.loadSkin(at: next.archiveURL)
                    wm.ensureAllWindowsOnScreen()
                }
            case .wmp(let name):
                removeWMPSkin(named: name)
            case .audion(let name):
                removeAudionFace(named: name)
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func removeWMPSkin(named name: String) {
        let importer = WMPSkinImporter()
        Task {
            do {
                try await importer.removeSkin(named: name)
                await MainActor.run {
                    // The skin's per-skin effects-slot settings go with it; a later re-import
                    // starts from the app's defaults rather than inheriting a stale record.
                    WMPVisualizationSettingsStore(defaults: importer.defaults).forget(skin: name)
                    (WindowManager.shared.mainWindowController as? WMPMainWindowController)?.resetToUnskinned()
                }
            } catch {
                _ = await MainActor.run { NSAlert(error: error).runModal() }
            }
        }
    }
}

// MARK: - Audion Faces actions

extension MenuActions {

    private var audionController: AudionFaceMainWindowController? {
        WindowManager.shared.mainWindowController as? AudionFaceMainWindowController
    }

    @objc func setAudionMode() {
        guard AppCapabilities.supports(.audionFaceMode), WindowManager.shared.uiMode != .audion else { return }
        WindowManager.shared.reloadUI(to: .audion)
    }

    /// In place inside the family; otherwise the selection is saved and entering the family loads it.
    @objc func selectAudionFace(_ sender: NSMenuItem) {
        guard AppCapabilities.supports(.audionFaceMode), let name = sender.representedObject as? String else { return }
        if let controller = audionController {
            controller.selectFace(named: name)
        } else {
            AudionFaceImporter().select(name)
            WindowManager.shared.reloadUI(to: .audion)
        }
    }

    @objc func loadAudionFaceFromFile() {
        guard AppCapabilities.supports(.audionFaceMode) else { return }
        if let controller = audionController {
            controller.importFaceFromPanel()
        } else {
            WindowManager.shared.reloadUI(to: .audion) { [weak self] in self?.audionController?.importFaceFromPanel() }
        }
    }

    @objc func getMoreAudionFaces() {
        guard let url = URL(string: "https://download.panic.com/audion/") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc func openAudionFacesFolder() {
        let importer = AudionFaceImporter()
        do {
            try importer.ensureDirectoryExists()
            NSWorkspace.shared.open(importer.directoryURL)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    fileprivate func removeAudionFace(named name: String) {
        Task { @MainActor in
            do {
                try await AudionFaceImporter().removeFace(named: name)
                self.audionController?.resetToUnskinned()
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }
}
