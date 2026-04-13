import XCTest
@testable import NullPlayerPlayback
import NullPlayerCore

final class AudioEngineFacadeTests: XCTestCase {
    func testStaleTokenEventsAreDroppedAfterNewLoad() {
        let backend = MockAudioBackend()
        let facade = AudioEngineFacade(backend: backend)

        let tracks = makeTracks(["one.mp3", "two.mp3"])
        facade.loadTracks(tracks)

        let staleToken = backend.lastLoadedToken
        facade.playTrack(at: 1)
        let currentToken = backend.lastLoadedToken

        XCTAssertNotEqual(staleToken, currentToken)
        XCTAssertEqual(facade.currentIndex, 1)

        backend.emit(.stateChanged(.playing, token: staleToken))
        backend.emit(.timeUpdated(current: 9, duration: 99, token: staleToken))
        backend.emit(.endOfStream(token: staleToken))

        XCTAssertEqual(facade.currentIndex, 1)
        XCTAssertNotEqual(facade.loadToken, staleToken)
    }

    func testDelegateLoadOrderingTrackThenTimeThenState() {
        let backend = MockAudioBackend()
        let facade = AudioEngineFacade(backend: backend)
        let delegate = DelegateSpy()
        facade.delegate = delegate

        facade.loadTracks(makeTracks(["track.mp3"]))
        let token = backend.lastLoadedToken

        backend.emit(.timeUpdated(current: 1.5, duration: 180, token: token))
        backend.emit(.stateChanged(.playing, token: token))

        XCTAssertEqual(delegate.firstThreeEventKindsExcludingPlaylist(), ["track", "time", "state"])
    }

    func testSeekProducesImmediateTimeUpdate() {
        let backend = MockAudioBackend()
        let facade = AudioEngineFacade(backend: backend)
        let delegate = DelegateSpy()
        facade.delegate = delegate

        facade.loadTracks(makeTracks(["track.mp3"]))
        let token = backend.lastLoadedToken
        backend.emit(.stateChanged(.playing, token: token))

        delegate.events.removeAll()
        facade.seek(to: 42)
        backend.emit(.timeUpdated(current: 42, duration: 180, token: token))

        XCTAssertEqual(delegate.events.first?.kind, "time")
        XCTAssertEqual(delegate.events.first?.current ?? -1, 42, accuracy: 0.001)
    }

    func testEndOfStreamAdvancesPlaylist() {
        let backend = MockAudioBackend()
        let facade = AudioEngineFacade(backend: backend)

        let tracks = makeTracks(["a.mp3", "b.mp3"])
        facade.loadTracks(tracks)
        let firstToken = backend.lastLoadedToken
        backend.emit(.stateChanged(.playing, token: firstToken))

        backend.emit(.endOfStream(token: firstToken))

        XCTAssertEqual(facade.currentIndex, 1)
        XCTAssertNotEqual(facade.loadToken, firstToken)
    }

    func testLoadFailureNotifiesThenAdvances() {
        let backend = MockAudioBackend()
        let facade = AudioEngineFacade(backend: backend)
        let delegate = DelegateSpy()
        facade.delegate = delegate

        let tracks = makeTracks(["broken.mp3", "next.mp3"])
        facade.loadTracks(tracks)

        let firstToken = backend.lastLoadedToken
        backend.emit(
            .loadFailed(
                track: tracks[0],
                failure: PlaybackFailure(code: "decode", message: "bad frame"),
                token: firstToken
            )
        )

        XCTAssertTrue(delegate.events.contains(where: { $0.kind == "loadFailed" }))
        XCTAssertEqual(facade.currentIndex, 1)
    }

    private func makeTracks(_ names: [String]) -> [Track] {
        names.map { name in
            Track(url: URL(fileURLWithPath: "/tmp/\(name)"))
        }
    }
}

private final class MockAudioBackend: AudioBackend {
    var capabilities = AudioBackendCapabilities(
        supportsOutputSelection: true,
        supportsGaplessPlayback: false,
        supportsSweetFade: false,
        supportsEQ: true,
        supportsWaveformFrames: false,
        eqBandCount: 10
    )

    var eventHandler: (@Sendable (AudioBackendEvent) -> Void)?

    var outputDevices: [AudioOutputDevice] = []
    var currentOutputDevice: AudioOutputDevice?

    private(set) var loadCalls: [(track: Track, token: UInt64, startPaused: Bool)] = []

    var lastLoadedToken: UInt64 {
        loadCalls.last?.token ?? 0
    }

    func prepare() {}
    func shutdown() {}

    func load(track: Track, token: UInt64, startPaused: Bool) {
        loadCalls.append((track, token, startPaused))
    }

    func play(token: UInt64) {}
    func pause(token: UInt64) {}
    func stop(token: UInt64) {}
    func seek(to time: TimeInterval, token: UInt64) { _ = time }
    func setVolume(_ value: Float, token: UInt64) { _ = value }
    func setBalance(_ value: Float, token: UInt64) { _ = value }
    func setEQ(enabled: Bool, preamp: Float, bands: [Float], token: UInt64) {
        _ = enabled
        _ = preamp
        _ = bands
    }
    func setNextTrackHint(_ track: Track?, token: UInt64) { _ = track }

    func refreshOutputs() {}
    @discardableResult
    func selectOutputDevice(persistentID: String?) -> Bool {
        _ = persistentID
        return true
    }

    func emit(_ event: AudioBackendEvent) {
        eventHandler?(event)
    }
}

private final class DelegateSpy: AudioEngineDelegate {
    struct Event {
        let kind: String
        let current: TimeInterval?
    }

    var events: [Event] = []

    func audioEngineDidChangeState(_ state: PlaybackState) {
        _ = state
        events.append(Event(kind: "state", current: nil))
    }

    func audioEngineDidUpdateTime(current: TimeInterval, duration: TimeInterval) {
        _ = duration
        events.append(Event(kind: "time", current: current))
    }

    func audioEngineDidChangeTrack(_ track: Track?) {
        _ = track
        events.append(Event(kind: "track", current: nil))
    }

    func audioEngineDidUpdateSpectrum(_ levels: [Float]) {
        _ = levels
    }

    func audioEngineDidChangePlaylist() {
        events.append(Event(kind: "playlist", current: nil))
    }

    func audioEngineDidFailToLoadTrack(_ track: Track, error: Error) {
        _ = track
        _ = error
        events.append(Event(kind: "loadFailed", current: nil))
    }

    func firstThreeEventKindsExcludingPlaylist() -> [String] {
        Array(events.filter { $0.kind != "playlist" }.prefix(3).map(\.kind))
    }
}
