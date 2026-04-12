import Foundation

public protocol AudioPlaybackProviding: AnyObject {
    associatedtype PlaybackTrack

    // MARK: - State (read-only)

    var state: PlaybackState { get }
    var currentTrack: PlaybackTrack? { get }
    var currentTime: TimeInterval { get }
    var duration: TimeInterval { get }
    var playlist: [PlaybackTrack] { get }
    var currentIndex: Int { get }

    // MARK: - Options (read-write)

    var volume: Float { get set }
    var balance: Float { get set }
    var shuffleEnabled: Bool { get set }
    var repeatEnabled: Bool { get set }
    var gaplessPlaybackEnabled: Bool { get set }
    var volumeNormalizationEnabled: Bool { get set }
    var sweetFadeEnabled: Bool { get set }
    var sweetFadeDuration: TimeInterval { get set }

    // MARK: - Playback control

    func play()
    func pause()
    func stop()
    func next()
    func previous()
    func seek(to time: TimeInterval)
    func seekBy(seconds: TimeInterval)
    func skipTracks(count: Int)

    // MARK: - Playlist management

    func loadFiles(_ urls: [URL])
    func loadTracks(_ tracks: [PlaybackTrack])
    func appendFiles(_ urls: [URL])
    func appendTracks(_ tracks: [PlaybackTrack])
    func loadFolder(_ url: URL)
    func clearPlaylist()
    func removeTrack(at index: Int)
    func moveTrack(from sourceIndex: Int, to destinationIndex: Int)
    func playTrack(at index: Int)
    func sortPlaylist(by criteria: PlaylistSortCriteria, ascending: Bool)
    func shufflePlaylist()
    func reversePlaylist()
    func replaceTrack(at index: Int, with track: PlaybackTrack)
    func insertTracksAfterCurrent(_ tracks: [PlaybackTrack], startPlaybackIfEmpty: Bool)
    func playNow(_ tracks: [PlaybackTrack])
    func setPlaylistTracks(_ tracks: [PlaybackTrack])
    func setPlaylistFiles(_ urls: [URL])
    func selectTrackForDisplay(at index: Int)

    // MARK: - EQ

    func setEQBand(_ band: Int, gain: Float)
    func getEQBand(_ band: Int) -> Float
    func setPreamp(_ gain: Float)
    func getPreamp() -> Float
    func setEQEnabled(_ enabled: Bool)
    func isEQEnabled() -> Bool
    var eqConfiguration: EQConfiguration { get }

    // MARK: - Spectrum

    func addSpectrumConsumer(_ id: String)
    func removeSpectrumConsumer(_ id: String)
    func addWaveformConsumer(_ id: String)
    func removeWaveformConsumer(_ id: String)
    var spectrumData: [Float] { get }
    var pcmData: [Float] { get }

    // MARK: - Delegate

    var delegate: AudioEngineDelegate? { get set }
}

public extension AudioPlaybackProviding {
    func insertTracksAfterCurrent(_ tracks: [PlaybackTrack]) {
        insertTracksAfterCurrent(tracks, startPlaybackIfEmpty: true)
    }

    func sortPlaylist(by criteria: PlaylistSortCriteria) {
        sortPlaylist(by: criteria, ascending: true)
    }
}
