import AppKit

// The Skins menu's per-family submenus, and the "Remove …" action they share.

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

    /// Selects a skin, switching into its family first when another is on screen.
    @objc func selectModernFamilySkin(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? ModernFamilySkinChoice else { return }
        let wm = WindowManager.shared
        let mode = choice.family.playerUIMode
        // Persisted first: `prepareUIRuntime` → `loadPreferredSkin()` reads this key when entering
        // the family, so the live switch loads exactly this skin.
        UserDefaults.standard.set(choice.name, forKey: choice.family.skinNameKey)
        SkinLoadingOverlay.shared.run {
            if wm.uiMode != mode {
                wm.reloadUI(to: mode)
            } else {
                ModernSkinEngine.shared.loadSkin(named: choice.name, family: choice.family)
            }
        }
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

        var name: String {
            switch self {
            case .classic(let url): return url.deletingPathExtension().lastPathComponent
            case .modernFamily(let skin, _): return skin.name
            case .winampModern(let skin): return skin.name
            case .wmp(let name): return name
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
        if case .wmp = skin {
            alert.informativeText = "\u{201c}\(skin.name)\u{201d} will be removed from NullPlayer. "
                + "The original downloaded file is not affected."
        } else {
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
