import AppKit

/// **EQ Cast ▸** in both Output menus: the toggle, the cache's size, its folder, and clearing it.
/// Built each time the menu opens, so the size is current.
@MainActor
enum EQCastMenu {
    static func item() -> NSMenuItem {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let folder = EQCastCache.folder
        if folder != nil, EQCast.usageBytes == nil { EQCast.measureUsage() }

        func add(_ title: String, _ action: Selector?, enabled: Bool = true) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = Target.shared
            item.isEnabled = enabled
            menu.addItem(item)
            return item
        }
        add("Enabled", #selector(Target.toggle)).state = EQCastCache.isEnabled ? .on : .off
        let size = folder == nil ? "—" : EQCast.usageBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "Calculating…"
        _ = add("Cache Size: \(size)", nil, enabled: false)
        menu.addItem(.separator())
        _ = add("Choose Cache Folder…", #selector(Target.chooseFolder))
        _ = add("Show in Finder", #selector(Target.showInFinder), enabled: folder != nil)
        _ = add("Delete Cache…", #selector(Target.deleteCache), enabled: folder != nil)

        let item = NSMenuItem(title: "EQ Cast", action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    /// The panel; false when cancelled. Warns when the folder is scanned by the library, which would
    /// import every render as a duplicate track.
    private static func chooseFolder() -> Bool {
        let panel = NSOpenPanel()
        panel.title = "Choose EQ Cast Cache Folder"
        panel.prompt = "Select"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = EQCastCache.folder
        guard panel.runModal() == .OK, let url = panel.url else { return false }

        let path = url.standardizedFileURL.path
        let inLibrary = MediaLibrary.shared.watchFoldersSnapshot.contains {
            let library = $0.standardizedFileURL.path
            return path == library || path.hasPrefix(library + "/")
        }
        if inLibrary {
            let alert = NSAlert()
            alert.messageText = "This folder is in your library"
            alert.informativeText = "The library scans it, so rendered tracks would be imported as duplicates."
            alert.addButton(withTitle: "Use Anyway")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return false }
        }
        EQCast.setFolder(url)
        return true
    }

    /// `NSMenuItem.target` is weak, so the items share one long-lived target.
    @MainActor private final class Target: NSObject {
        static let shared = Target()

        @objc func toggle(_ sender: NSMenuItem) {
            let enable = !EQCastCache.isEnabled
            if enable, EQCastCache.folder == nil, !EQCastMenu.chooseFolder() { return }
            EQCast.setEnabled(enable)
        }

        @objc func chooseFolder(_ sender: NSMenuItem) {
            _ = EQCastMenu.chooseFolder()
        }

        @objc func showInFinder(_ sender: NSMenuItem) {
            guard let folder = EQCastCache.folder else { return }
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        }

        @objc func deleteCache(_ sender: NSMenuItem) {
            let alert = NSAlert()
            alert.messageText = "Delete the EQ Cast cache?"
            let size = EQCast.usageBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) + " of " } ?? ""
            alert.informativeText = "This removes \(size)rendered tracks. The track being cast is kept."
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            let activityID = "eqcast-delete"
            ActivityCenter.shared.show(id: activityID, message: "EQ Cast: deleting cache…")
            Task {
                await EQCastCache.shared.deleteCache(keeping: EQCast.castingFile)
                ActivityCenter.shared.hide(id: activityID)
            }
        }
    }
}
