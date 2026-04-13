#if os(Linux)
import Foundation
import CGTK4

final class LinuxWindowCoordinator {
    private(set) var mainWindow: MainWindowProviding
    private(set) var playlistWindow: PlaylistWindowProviding
    private(set) var libraryBrowserWindow: LibraryBrowserWindowProviding
    private(set) var eqWindow: EQWindowProviding
    private(set) var spectrumWindow: SpectrumWindowProviding
    private(set) var waveformWindow: WaveformWindowProviding
    private(set) var projectMWindow: ProjectMWindowProviding

    // Initial hook points for later state/frame persistence work.
    private(set) var lastKnownVisibility: [LinuxWindowKind: Bool] = [:]
    private(set) var lastKnownFrameHints: [LinuxWindowKind: LinuxWindowFrameHint] = [:]

    init(
        mainWindow: MainWindowProviding = LinuxMainWindowController(),
        playlistWindow: PlaylistWindowProviding = LinuxPlaylistWindowController(),
        libraryBrowserWindow: LibraryBrowserWindowProviding = LinuxLibraryBrowserWindowController(),
        eqWindow: EQWindowProviding = LinuxEQWindowController(),
        spectrumWindow: SpectrumWindowProviding = LinuxSpectrumWindowController(),
        waveformWindow: WaveformWindowProviding = LinuxWaveformWindowController(),
        projectMWindow: ProjectMWindowProviding = LinuxProjectMWindowController()
    ) {
        self.mainWindow = mainWindow
        self.playlistWindow = playlistWindow
        self.libraryBrowserWindow = libraryBrowserWindow
        self.eqWindow = eqWindow
        self.spectrumWindow = spectrumWindow
        self.waveformWindow = waveformWindow
        self.projectMWindow = projectMWindow
        refreshVisibilityState()
    }

    func showMainWindow() {
        mainWindow.showWindow(nil)
        bringAllVisibleWindowsToFront()
        refreshVisibilityState()
    }

    func showLibraryBrowser() {
        libraryBrowserWindow.showWindow(nil)
        bringAllVisibleWindowsToFront()
        refreshVisibilityState()
    }

    func togglePlaylist() {
        toggle(.playlist, window: playlistWindow.window) { [weak self] in
            self?.playlistWindow.showWindow(nil)
        }
    }

    func toggleEqualizer() {
        toggle(.equalizer, window: eqWindow.window) { [weak self] in
            self?.eqWindow.showWindow(nil)
        }
    }

    func togglePlexBrowser() {
        toggle(.libraryBrowser, window: libraryBrowserWindow.window) { [weak self] in
            self?.libraryBrowserWindow.showWindow(nil)
        }
    }

    func toggleSpectrum() {
        toggle(.spectrum, window: spectrumWindow.window) { [weak self] in
            self?.spectrumWindow.showWindow(nil)
        }
    }

    func toggleWaveform() {
        toggle(.waveform, window: waveformWindow.window) { [weak self] in
            self?.waveformWindow.showWindow(nil)
        }
    }

    func toggleProjectM() {
        toggle(.projectM, window: projectMWindow.window) { [weak self] in
            self?.projectMWindow.showWindow(nil)
        }
    }

    func isWindowVisible(_ kind: LinuxWindowKind) -> Bool {
        lastKnownVisibility[kind] ?? false
    }

    func setWindowVisible(_ kind: LinuxWindowKind, visible: Bool) {
        let currentlyVisible = isWindowVisible(kind)
        guard currentlyVisible != visible else { return }

        switch kind {
        case .main:
            showMainWindow()
        case .playlist:
            togglePlaylist()
        case .equalizer:
            toggleEqualizer()
        case .libraryBrowser:
            togglePlexBrowser()
        case .spectrum:
            toggleSpectrum()
        case .waveform:
            toggleWaveform()
        case .projectM:
            toggleProjectM()
        }
    }

    func showAllPlaceholderWindows() {
        showMainWindow()
        showLibraryBrowser()
        playlistWindow.showWindow(nil)
        eqWindow.showWindow(nil)
        spectrumWindow.showWindow(nil)
        waveformWindow.showWindow(nil)
        projectMWindow.showWindow(nil)
        bringAllVisibleWindowsToFront()
        refreshVisibilityState()
    }

    func hideAllSecondaryWindows() {
        hideWindowIfVisible(playlistWindow.window)
        hideWindowIfVisible(eqWindow.window)
        hideWindowIfVisible(libraryBrowserWindow.window)
        hideWindowIfVisible(spectrumWindow.window)
        hideWindowIfVisible(waveformWindow.window)
        hideWindowIfVisible(projectMWindow.window)
        refreshVisibilityState()
    }

    func refreshVisibilityState() {
        lastKnownVisibility = [
            .main: isVisible(mainWindow.window),
            .playlist: isVisible(playlistWindow.window),
            .equalizer: isVisible(eqWindow.window),
            .libraryBrowser: isVisible(libraryBrowserWindow.window),
            .spectrum: isVisible(spectrumWindow.window),
            .waveform: isVisible(waveformWindow.window),
            .projectM: isVisible(projectMWindow.window),
        ]
        captureFrameHints()
        mainWindow.windowVisibilityDidChange()
    }

    private func toggle(
        _ kind: LinuxWindowKind,
        window: LinuxWindowHandle?,
        show: () -> Void
    ) {
        guard let window else { return }
        if isVisible(window) {
            hideWindowIfVisible(window)
        } else {
            show()
            bringAllVisibleWindowsToFront()
        }
        lastKnownVisibility[kind] = isVisible(window)
        mainWindow.windowVisibilityDidChange()
    }

    private func hideWindowIfVisible(_ window: LinuxWindowHandle?) {
        guard let window, isVisible(window) else { return }
        np_linux_ui_window_hide(window)
    }

    private func isVisible(_ window: LinuxWindowHandle?) -> Bool {
        guard let window else { return false }
        return np_linux_ui_window_is_visible(window) != 0
    }

    private func captureFrameHints() {
        for kind in LinuxWindowKind.allCases {
            if let frameHint = frameHintFor(kind: kind) {
                lastKnownFrameHints[kind] = frameHint
            }
        }
    }

    func bringAllVisibleWindowsToFront() {
        let orderedWindows: [LinuxWindowHandle?] = [
            mainWindow.window,
            eqWindow.window,
            playlistWindow.window,
            spectrumWindow.window,
            waveformWindow.window,
            libraryBrowserWindow.window,
            projectMWindow.window,
        ]

        for window in orderedWindows {
            guard let window, isVisible(window) else { continue }
            np_linux_ui_window_present(window)
        }
    }

    private func frameHintFor(kind: LinuxWindowKind) -> LinuxWindowFrameHint? {
        let window: LinuxWindowHandle?
        switch kind {
        case .main:
            window = mainWindow.window
        case .playlist:
            window = playlistWindow.window
        case .equalizer:
            window = eqWindow.window
        case .libraryBrowser:
            window = libraryBrowserWindow.window
        case .spectrum:
            window = spectrumWindow.window
        case .waveform:
            window = waveformWindow.window
        case .projectM:
            window = projectMWindow.window
        }
        guard let window else { return nil }

        var width: Int32 = 0
        var height: Int32 = 0
        np_linux_ui_window_get_default_size(window, &width, &height)
        return LinuxWindowFrameHint(width: width, height: height)
    }
}

enum LinuxWindowKind: String, CaseIterable {
    case main
    case playlist
    case equalizer
    case libraryBrowser
    case spectrum
    case waveform
    case projectM
}

struct LinuxWindowFrameHint: Sendable, Equatable {
    let width: Int32
    let height: Int32
}
#endif
