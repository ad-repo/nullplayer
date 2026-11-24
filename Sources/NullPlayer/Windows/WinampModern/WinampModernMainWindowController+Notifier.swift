import AppKit

/// The track-change toast (`<container id="notifier">`): shown here on every track change, unless
/// the skin's own notifier script shows it — see
/// `skills/winamp-modern-skin-guide/reference/components/notifier.md`.
extension WinampModernMainWindowController {
    func showNotifier(for track: Track) {
        guard let container = auxiliaryContainers.first(where: { $0.isNotifier }),
              let scripts = skinView?.scripts,
              scripts.announceNotification(title: track.title, artist: track.artist ?? "",
                                           album: track.album ?? "")
        else { return }
        container.window.alphaValue = 1
        setAuxiliaryWindow(id: container.containerID, visible: true, activate: false)
        container.view.needsDisplay = true
        notifierDismissTimer?.invalidate()
        notifierDismissTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) {
            [weak self] _ in
            guard let self else { return }
            self.setAuxiliaryWindow(id: container.containerID, visible: false, activate: false)
        }
    }
}
