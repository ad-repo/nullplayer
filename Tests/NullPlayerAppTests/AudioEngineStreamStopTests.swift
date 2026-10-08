import XCTest
@testable import NullPlayer

final class AudioEngineStreamStopTests: XCTestCase {
    /// Stopping a stream reports `.stopped` on a later main-queue turn than the `stop()`. Leaving a
    /// stream for a local file, that report lands after the file has started; it must not stop the
    /// engine while the file plays (measured: the engine read stopped, clock at 0:00).
    func testLateStreamStopDoesNotStopALocalFile() throws {
        let url = try TestAudioFile.temporaryWAV(seconds: 2, tone: true)
        defer { try? FileManager.default.removeItem(at: url) }

        let engine = AudioEngine()
        defer { engine.stop() }
        engine.playNow([Track(url: url, title: "Tone")])
        XCTAssertEqual(engine.state, .playing)

        engine.streamingPlayerDidChangeState(.stopped)
        XCTAssertEqual(engine.state, .playing)
    }
}
