#if os(Linux)
import Foundation
import Glibc
import NullPlayerCore
import NullPlayerPlayback
import CGTK4

final class LinuxAppLifecycle {
    private let backend: LinuxGStreamerAudioBackend
    private let facade: AudioEngineFacade
    private let coordinator: LinuxWindowCoordinator
    private let commands: LinuxCommandHub
    private let menuDialogs: LinuxMenuDialogService
    private let artworkLoader: LinuxArtworkLoader
    private let graphicsCapabilities: LinuxGraphicsCapabilityService
    private let stateManager: LinuxAppStateManager

    init() {
        // GTK and GStreamer must be initialized before any widgets or pipelines are created.
        // np_linux_ui_init() creates a GtkApplication and registers it, which fires the
        // GTK startup signal (opening the default GdkDisplay) before any widgets are created.
        np_linux_ui_init()
        LinuxGStreamerAudioBackend.initializeGStreamerEarly()
        let backend = LinuxGStreamerAudioBackend()
        self.backend = backend
        self.facade = AudioEngineFacade(backend: backend)
        let coordinator = LinuxWindowCoordinator()
        self.coordinator = coordinator
        self.commands = LinuxCommandHub(engine: facade, windows: coordinator)
        self.menuDialogs = LinuxMenuDialogService()
        self.artworkLoader = LinuxArtworkLoader()
        self.graphicsCapabilities = LinuxGraphicsCapabilityService(backendCapabilities: backend.capabilities)
        self.stateManager = LinuxAppStateManager(backendCapabilities: backend.capabilities)

        if let main = coordinator.mainWindow as? LinuxMainWindowController {
            main.transportCommands = commands
            main.windowCommands = commands
            main.outputCommands = commands
            main.dialogPresenter = menuDialogs
            main.windowVisibilityProvider = { [weak coordinator] kind in
                coordinator?.isWindowVisible(kind) ?? false
            }
            main.setWindowVisibility = { [weak coordinator] kind, visible in
                coordinator?.setWindowVisible(kind, visible: visible)
            }
        }

        if let playlist = coordinator.playlistWindow as? LinuxPlaylistWindowController {
            playlist.playlistCommands = commands
            playlist.transportCommands = commands
            playlist.dialogPresenter = menuDialogs
        }

        if let library = coordinator.libraryBrowserWindow as? LinuxLibraryBrowserWindowController {
            library.transportCommands = commands
        }

        facade.delegate = self
        facade.addSpectrumConsumer("linuxMainWindowSpectrum")
    }

    func run() {
        BrowserPreferences.store = LinuxPreferencesStore.shared
        _ = facade.state
        _ = commands.playbackState
        _ = graphicsCapabilities.currentCapabilities()
        menuDialogs.updateMainMenu(actions: [])
        artworkLoader.clearCache()

        stateManager.restoreSettingsState(engine: facade, windows: coordinator)
        stateManager.restorePlaylistState(engine: facade)
        if !coordinator.isWindowVisible(.main) {
            coordinator.showAllPlaceholderWindows()
        }

        coordinator.mainWindow.updateTrackInfo(facade.currentTrack)
        coordinator.mainWindow.updatePlaybackState()
        coordinator.mainWindow.updateTime(current: facade.currentTime, duration: facade.duration)
        coordinator.playlistWindow.reloadPlaylist()

        LinuxSignalHandlers.install { [weak self] code in
            self?.shutdown(exitCode: code)
        }

        np_linux_ui_run_until_all_windows_close()
        shutdown(exitCode: 0)
    }

    private func shutdown(exitCode: Int32) {
        facade.removeSpectrumConsumer("linuxMainWindowSpectrum")
        stateManager.saveState(engine: facade, windows: coordinator)
        backend.shutdown()
        exit(exitCode)
    }
}

extension LinuxAppLifecycle: AudioEngineDelegate {
    func audioEngineDidChangeState(_ state: PlaybackState) {
        _ = state
        coordinator.mainWindow.updatePlaybackState()
    }

    func audioEngineDidUpdateTime(current: TimeInterval, duration: TimeInterval) {
        coordinator.mainWindow.updateTime(current: current, duration: duration)
        coordinator.waveformWindow.updateTime(current: current, duration: duration)
        if let playlist = coordinator.playlistWindow as? LinuxPlaylistWindowController {
            playlist.updateCurrentTrackMarquee(currentTime: current)
        }
    }

    func audioEngineDidChangeTrack(_ track: Track?) {
        coordinator.mainWindow.updateTrackInfo(track)
        coordinator.waveformWindow.updateTrack(track)
    }

    func audioEngineDidUpdateSpectrum(_ levels: [Float]) {
        coordinator.mainWindow.updateSpectrum(levels)
    }

    func audioEngineDidChangePlaylist() {
        coordinator.playlistWindow.reloadPlaylist()
    }

    func audioEngineDidFailToLoadTrack(_ track: Track, error: Error) {
        menuDialogs.showError(
            title: "Track Load Failed",
            message: "Failed to load '\(track.title)': \(error.localizedDescription)"
        )
    }
}
#endif
