import XCTest
@testable import NullPlayer
@testable import NullPlayerCore

/// **The transport the WMP skin drives while a film is on a television.**
///
/// The branch is only reachable with a real Chromecast on the network, and it shipped two defects
/// because of it (both reported 2026-09-20): a seek that handed seconds to a call taking a
/// fraction, which sent the receiver past EOF and tore the session down; and a volume the snapshot
/// read back off the idle audio queue, so the slider snapped back and re-sent that stale level.
/// `WMPAudioEngineHost.videoCast` is the seam those two live behind.
@MainActor
final class WMPVideoCastTransportTests: XCTestCase {
    /// Records what the host asks the cast to do, and answers what a playing film would.
    final class FakeCast: WMPVideoCastTransport {
        var isCasting = true
        var isPlaying = true
        var currentTime: TimeInterval = 12
        var duration: TimeInterval = 200
        var title: String? = "A Film"
        private(set) var seeks: [Double] = []
        private(set) var volumes: [Float] = []
        private(set) var toggles = 0
        private(set) var stops = 0
        func togglePlayPause() { toggles += 1 }
        func stop() { stops += 1 }
        func seek(fraction: Double) { seeks.append(fraction) }
        func setVolume(_ level: Float) { volumes.append(level) }
    }

    private var cast = FakeCast()

    override func setUp() {
        super.setUp()
        cast = FakeCast()
        WMPAudioEngineHost.videoCast = cast
    }

    override func tearDown() {
        WMPAudioEngineHost.videoCast = WMPWindowManagerVideoCast()
        super.tearDown()
    }

    /// A seek is a **fraction of the film**. Multiplying by the duration here made the target
    /// `fraction × duration²`: the receiver hit EOF, answered IDLE, and `CastManager` read that as
    /// media-ended and stopped the cast.
    func testSeekSendsTheSliderFractionAndNeverATime() {
        let host = WMPAudioEngineHost(audioEngine: AudioEngine())
        host.perform(.seek, value: .number(0.25))
        XCTAssertEqual(cast.seeks, [0.25])
        host.perform(.seek, value: .number(1.4))
        host.perform(.seek, value: .number(-3))
        XCTAssertEqual(cast.seeks, [0.25, 1, 0], "the fraction is clamped, not scaled")
        // A film with no duration yet has nothing to seek into.
        cast.duration = 0
        host.perform(.seek, value: .number(0.5))
        XCTAssertEqual(cast.seeks.count, 3)
    }

    /// The readout follows the level last commanded to the device, not `AudioEngine`'s.
    func testVolumeReadsBackWhatWasCommandedRatherThanTheAudioQueue() {
        let engine = AudioEngine()
        engine.volume = 0.2
        let host = WMPAudioEngineHost(audioEngine: engine)
        XCTAssertEqual(host.snapshot.volume, 1, accuracy: 0.001, "a cast starts at the device's full volume")

        host.perform(.volume, value: .number(0.8))
        XCTAssertEqual(cast.volumes, [0.8])
        XCTAssertEqual(host.snapshot.volume, 0.8, accuracy: 0.001)
        XCTAssertFalse(host.snapshot.muted)
        XCTAssertEqual(engine.volume, 0.2, "the audio queue behind the film is left alone")
    }

    /// Mute is the television's, not the audio queue's — it used to fall through to `AudioEngine`.
    func testMuteTogglesTheCastAndRestoresTheLevelItSilenced() {
        let engine = AudioEngine()
        engine.volume = 0.2
        let host = WMPAudioEngineHost(audioEngine: engine)
        host.perform(.volume, value: .number(0.6))
        host.perform(.toggleMute, value: nil)
        XCTAssertEqual(cast.volumes.last, 0)
        XCTAssertTrue(host.snapshot.muted)
        XCTAssertEqual(host.snapshot.volume, 0.6, accuracy: 0.001,
                       "a skin reads the level it was muted from, not zero (W265)")
        host.perform(.toggleMute, value: nil)
        XCTAssertEqual(cast.volumes.last, 0.6)
        XCTAssertFalse(host.snapshot.muted)
        XCTAssertEqual(engine.volume, 0.2, "the queue's own volume never moved")
    }

    /// The remembered level belongs to one cast session: the next film starts at the device's own
    /// volume again rather than inheriting the last one's.
    func testTheRememberedLevelIsDroppedWhenTheCastEnds() {
        let host = WMPAudioEngineHost(audioEngine: AudioEngine())
        host.perform(.volume, value: .number(0.3))
        XCTAssertEqual(host.snapshot.volume, 0.3, accuracy: 0.001)
        cast.isCasting = false
        _ = host.snapshot
        cast.isCasting = true
        XCTAssertEqual(host.snapshot.volume, 1, accuracy: 0.001)
    }

    /// Separate play and pause buttons must ask what the television is doing first, and the film's
    /// own readouts are the cast's.
    func testTransportAsksTheCastWhatItIsDoingAndTheSnapshotFollowsIt() {
        let host = WMPAudioEngineHost(audioEngine: AudioEngine())
        host.perform(.play, value: nil)
        XCTAssertEqual(cast.toggles, 0, "play on a playing cast must not pause the television")
        host.perform(.pause, value: nil)
        XCTAssertEqual(cast.toggles, 1)
        cast.isPlaying = false
        host.perform(.pause, value: nil)
        XCTAssertEqual(cast.toggles, 1)
        host.perform(.play, value: nil)
        XCTAssertEqual(cast.toggles, 2)
        host.perform(.stop, value: nil)
        XCTAssertEqual(cast.stops, 1)

        cast.isPlaying = true
        let snapshot = host.snapshot
        XCTAssertEqual(snapshot.state, .playing)
        XCTAssertEqual(snapshot.currentTime, 12, accuracy: 0.001)
        XCTAssertEqual(snapshot.duration, 200, accuracy: 0.001)
        XCTAssertEqual(snapshot.metadata.title, "A Film")
    }

    /// A cast film is one item with nowhere to skip to: `next`/`previous` must not fall through and
    /// start the audio queue behind it.
    func testNextAndPreviousDoNotReachTheAudioQueueDuringACast() {
        let engine = AudioEngine()
        let host = WMPAudioEngineHost(audioEngine: engine)
        host.perform(.next, value: nil)
        host.perform(.previous, value: nil)
        XCTAssertEqual(cast.toggles, 0)
        XCTAssertNil(engine.currentTrack)
    }
}
