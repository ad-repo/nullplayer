import AppKit

/// The vis_classic block of every analyzer menu — the Spectrum window's right-click (Classic and
/// Original), the menu bar's Spectrum Window submenu and the main window's visualization menu — so
/// the four cannot drift apart again. Each host passes its own target and selectors; the grouping is
/// fixed here: the profile and stepping through it, then how it draws, then its files. (The `.wmz` /
/// Sonique effects menu keeps a compact block of its own — profile, fit, transparency and
/// Sensitivity, with no stepping or INI files.)
enum VisClassicMenu {
    struct Actions {
        let loadProfile: Selector  // the item's `representedObject` is the profile name
        let nextProfile: Selector
        let previousProfile: Selector
        let toggleFitToWidth: Selector
        let toggleTransparentBackground: Selector
        let importProfile: Selector
        let exportProfile: Selector
    }

    /// Appends the block, opening with a separator; the host closes its own section after it.
    static func addItems(to menu: NSMenu, profileNames: [String], currentProfile: String?,
                         fitToWidth: Bool, transparentBackground: Bool,
                         target: AnyObject, actions: Actions) {
        func item(_ title: String, _ action: Selector?, on: Bool = false) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = target
            item.state = on ? .on : .off
            return item
        }

        menu.addItem(.separator())
        let profiles = NSMenu()
        profiles.autoenablesItems = false
        if profileNames.isEmpty {
            let none = item("No Profiles", nil)
            none.isEnabled = false
            profiles.addItem(none)
        }
        for name in profileNames {
            let entry = item(name, actions.loadProfile, on: name == currentProfile)
            entry.representedObject = name
            profiles.addItem(entry)
        }
        let profilesRoot = item("Profiles", nil)
        profilesRoot.submenu = profiles
        menu.addItem(profilesRoot)
        menu.addItem(item("Next Profile", actions.nextProfile))
        menu.addItem(item("Previous Profile", actions.previousProfile))

        menu.addItem(.separator())
        menu.addItem(WinampModernVisSensitivityMenu.shared.menuItem(for: .visClassic))
        menu.addItem(item("Fit to Width", actions.toggleFitToWidth, on: fitToWidth))
        menu.addItem(item("Transparent Background", actions.toggleTransparentBackground,
                          on: transparentBackground))

        menu.addItem(.separator())
        menu.addItem(item("Import INI...", actions.importProfile))
        menu.addItem(item("Export Current INI...", actions.exportProfile))
    }
}
