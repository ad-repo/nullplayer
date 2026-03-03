import AppKit

/// NSOpenPanel delegate that prevents the user from drilling into subdirectories.
/// Only folders at the level the panel is currently showing can be selected.
final class TopLevelFolderPickerDelegate: NSObject, NSOpenSavePanelDelegate {
    private var lastDirectory: URL?

    func panelCurrentDirectoryDidChange(_ sender: Any) {
        guard let panel = sender as? NSOpenPanel,
              let current = panel.directoryURL else { return }

        if let last = lastDirectory {
            let lastPath = last.standardized.path
            let currentPath = current.standardized.path
            // Navigated INTO a subdirectory of the last location → bounce back
            if currentPath.hasPrefix(lastPath + "/") {
                panel.directoryURL = last
                return
            }
        }
        lastDirectory = current
    }
}
