#if os(Linux)
import Foundation
import NullPlayerCore
import NullPlayerPlayback

protocol LinuxTransportCommanding: AnyObject {
    var playbackState: PlaybackState { get }
    var currentTrack: Track? { get }
    var currentTime: TimeInterval { get }
    var duration: TimeInterval { get }
    var volume: Float { get set }
    var balance: Float { get set }
    var shuffleEnabled: Bool { get set }
    var repeatEnabled: Bool { get set }

    func play()
    func pause()
    func stop()
    func next()
    func previous()
    func seek(to time: TimeInterval)
    func seekBy(seconds: TimeInterval)
    func loadFiles(_ urls: [URL])
    func loadFolder(_ url: URL)
    func appendFiles(_ urls: [URL])
    func loadTracks(_ tracks: [Track])
    func appendTracks(_ tracks: [Track])
}

protocol LinuxPlaylistCommanding: AnyObject {
    var playlist: [Track] { get }
    var currentIndex: Int { get }

    func playTrack(at index: Int)
    func removeTrack(at index: Int)
    func clearPlaylist()
    func moveTrack(from source: Int, to destination: Int)
    func sort(by criteria: PlaylistSortCriteria, ascending: Bool)
    func shufflePlaylist()
    func reversePlaylist()
}

protocol LinuxEQCommanding: AnyObject {
    var isEQEnabled: Bool { get set }
    var eqPreamp: Float { get set }
    var eqBandCount: Int { get }
    func eqBand(at index: Int) -> Float
    func setEQBand(_ index: Int, gain: Float)
}

protocol LinuxWindowVisibilityCommanding: AnyObject {
    func showMainWindow()
    func showLibraryBrowser()
    func togglePlaylist()
    func toggleEqualizer()
    func toggleLibraryBrowser()
    func toggleSpectrum()
    func toggleWaveform()
    func toggleProjectM()
}

protocol LinuxOutputDeviceCommanding: AnyObject {
    var outputDevices: [AudioOutputDevice] { get }
    var currentOutputDevice: AudioOutputDevice? { get }
    func refreshOutputDevices()
    @discardableResult
    func selectOutputDevice(persistentID: String?) -> Bool
}

final class LinuxCommandHub:
    LinuxTransportCommanding,
    LinuxPlaylistCommanding,
    LinuxEQCommanding,
    LinuxWindowVisibilityCommanding,
    LinuxOutputDeviceCommanding
{
    private let engine: AudioEngineFacade
    private let windows: LinuxWindowCoordinator

    init(engine: AudioEngineFacade, windows: LinuxWindowCoordinator) {
        self.engine = engine
        self.windows = windows
    }

    var playbackState: PlaybackState { engine.state }
    var currentTrack: Track? { engine.currentTrack }
    var currentTime: TimeInterval { engine.currentTime }
    var duration: TimeInterval { engine.duration }

    var volume: Float {
        get { engine.volume }
        set { engine.volume = newValue }
    }

    var balance: Float {
        get { engine.balance }
        set { engine.balance = newValue }
    }

    var shuffleEnabled: Bool {
        get { engine.shuffleEnabled }
        set { engine.shuffleEnabled = newValue }
    }

    var repeatEnabled: Bool {
        get { engine.repeatEnabled }
        set { engine.repeatEnabled = newValue }
    }

    func play() { engine.play() }
    func pause() { engine.pause() }
    func stop() { engine.stop() }
    func next() { engine.next() }
    func previous() { engine.previous() }
    func seek(to time: TimeInterval) { engine.seek(to: time) }
    func seekBy(seconds: TimeInterval) { engine.seekBy(seconds: seconds) }
    func loadFiles(_ urls: [URL]) { engine.loadFiles(urls) }
    func loadFolder(_ url: URL) { engine.loadFolder(url) }
    func appendFiles(_ urls: [URL]) { engine.appendFiles(urls) }
    func loadTracks(_ tracks: [Track]) { engine.loadTracks(tracks) }
    func appendTracks(_ tracks: [Track]) { engine.appendTracks(tracks) }

    var playlist: [Track] { engine.playlist }
    var currentIndex: Int { engine.currentIndex }

    func playTrack(at index: Int) { engine.playTrack(at: index) }
    func removeTrack(at index: Int) { engine.removeTrack(at: index) }
    func clearPlaylist() { engine.clearPlaylist() }
    func moveTrack(from source: Int, to destination: Int) { engine.moveTrack(from: source, to: destination) }
    func sort(by criteria: PlaylistSortCriteria, ascending: Bool) { engine.sortPlaylist(by: criteria, ascending: ascending) }
    func shufflePlaylist() { engine.shufflePlaylist() }
    func reversePlaylist() { engine.reversePlaylist() }

    var isEQEnabled: Bool {
        get { engine.isEQEnabled() }
        set { engine.setEQEnabled(newValue) }
    }

    var eqPreamp: Float {
        get { engine.getPreamp() }
        set { engine.setPreamp(newValue) }
    }

    var eqBandCount: Int { engine.eqConfiguration.bandCount }

    func eqBand(at index: Int) -> Float {
        engine.getEQBand(index)
    }

    func setEQBand(_ index: Int, gain: Float) {
        engine.setEQBand(index, gain: gain)
    }

    func showMainWindow() { windows.showMainWindow() }
    func showLibraryBrowser() { windows.showLibraryBrowser() }
    func togglePlaylist() { windows.togglePlaylist() }
    func toggleEqualizer() { windows.toggleEqualizer() }
    func toggleLibraryBrowser() { windows.togglePlexBrowser() }
    func toggleSpectrum() { windows.toggleSpectrum() }
    func toggleWaveform() { windows.toggleWaveform() }
    func toggleProjectM() { windows.toggleProjectM() }

    var outputDevices: [AudioOutputDevice] { engine.outputDevices }
    var currentOutputDevice: AudioOutputDevice? { engine.currentOutputDevice }
    func refreshOutputDevices() { engine.refreshOutputs() }

    @discardableResult
    func selectOutputDevice(persistentID: String?) -> Bool {
        engine.selectOutputDevice(persistentID: persistentID)
    }
}
#endif
