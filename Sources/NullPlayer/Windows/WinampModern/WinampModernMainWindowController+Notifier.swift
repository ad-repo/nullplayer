import AppKit

/// The track-change toast (`<container id="notifier">`): shown here on every track change, unless
/// the skin's own notifier script shows it — see
/// `skills/winamp-modern-skin-guide/reference/components/notifier.md`.
extension WinampModernMainWindowController {
    func showNotifier(for track: Track) {
        guard auxiliaryContainers.contains(where: { $0.isNotifier }),
              let scripts = skinView?.scripts,
              let toast = scripts.announceNotification(title: track.title, artist: track.artist ?? "",
                                                       album: track.album ?? ""),
              let container = auxiliaryContainers.first(where: { $0.info.object === toast })
        else { return }
        container.window.alphaValue = 1
        setAuxiliaryWindow(id: container.containerID, visible: true, activate: false)
        container.view.needsDisplay = true
        notifierDismissTimer?.invalidate()
        notifierDismissTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) {
            [weak self] _ in
            // A script that claimed the toast since (B479) dismisses it itself.
            guard let self, self.skinView?.scripts.notifierShowsItself(container.info.object) == false
            else { return }
            self.setAuxiliaryWindow(id: container.containerID, visible: false, activate: false)
        }
    }
}
