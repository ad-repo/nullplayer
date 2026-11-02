import Foundation

/// One row in the Windows menu's skin section: a skin-owned window, an item the skin added to
/// Winamp's own Windows menu, or a ClassicPro SUI tab (B350).
struct WinampModernSkinMenuEntry {
    enum Target {
        /// A skin-owned container, by id.
        case window(String)
        /// A Windows-menu attribute the skin registered, by attribute name.
        case menuItem(String)
        /// A ClassicPro strip tab, by label.
        case tab(String)
    }

    let title: String
    let isOn: Bool
    var isEnabled = true
    let target: Target
}

extension WinampModernMainWindowController {
    /// The skin section of the Windows menu: the skin's own windows, then the items it put in
    /// Winamp's Windows menu, then a ClassicPro strip's tabs — ticked while in the strip, less Media
    /// Library and Playlist, which are NullPlayer's Library Browser and Playlist Editor items. The
    /// strip's own Windows-menu items ("Web Browser", each widget tab) are its tabs, listed once.
    var skinMenuEntries: [WinampModernSkinMenuEntry] {
        let windows = skinWindows.map {
            WinampModernSkinMenuEntry(title: $0.name, isOn: $0.isVisible, target: .window($0.id))
        }
        guard let scripts = skinView?.scripts else { return windows }
        let strip = classicProTabs
        let menuItems = scripts.windowsMenuItems.filter { strip?.ownsMenuItem(named: $0.name) != true }.map {
            WinampModernSkinMenuEntry(title: WinampModernContainerTopology.menuLabel($0.name),
                                      isOn: scripts.configAttributeValue($0) == "1", target: .menuItem($0.name))
        }
        let tabs = strip?.tabs ?? []
        let tabEntries = tabs.filter { $0.kind == nil }.map {
            WinampModernSkinMenuEntry(title: $0.label, isOn: $0.isInStrip,
                                      isEnabled: !$0.isInStrip || ClassicProTabStrip.canClose($0, among: tabs),
                                      target: .tab($0.label))
        }
        return windows + menuItems + tabEntries
    }

    func toggleSkinMenuEntry(_ target: WinampModernSkinMenuEntry.Target) {
        switch target {
        case .window(let id):
            toggleSkinWindow(id: id)
        case .menuItem(let key):
            guard let scripts = skinView?.scripts,
                  let item = scripts.windowsMenuItems.first(where: { $0.name == key }) else { return }
            scripts.toggleWindowsMenuItem(item)
        case .tab(let label):
            guard let strip = classicProTabs, let tab = strip.tab(named: label) else { return }
            if tab.isInStrip { strip.close(tab) } else { strip.open(tab) }
        }
        skinView?.needsDisplay = true
    }

    /// Put ClassicPro's tab strip back to its first-start layout: every tab open, in the engine's
    /// order. Reset between unload and load, because the engine saves its order as it unloads.
    func restoreDefaultClassicProTabs() {
        guard let url = loadedSkinURL, let configuration = loadedSkin?.configuration else { return }
        loadSkin(at: url, afterTeardown: { ClassicProTabStrip.resetLayout(in: configuration) })
    }
}
