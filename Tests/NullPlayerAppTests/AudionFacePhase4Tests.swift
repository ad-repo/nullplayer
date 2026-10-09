import XCTest
@testable import NullPlayer

/// Phase 4's face behaviour that runs without a window: the mode button's cycle. The keys are the
/// Modern main window's (`MainWindowKeys`); the popups, the clock and accessibility are checked
/// live (`skills/audion-face-guide/reference/windows.md`).
@MainActor
final class AudionFacePhase4Tests: XCTestCase {

    func testTheModeButtonCyclesShuffleAndRepeat() {
        let engine = AudioEngine()
        var seen: [[Bool]] = []
        for _ in 0..<4 {
            AudionFaceAudioEngineHost.perform(.button(.mode), engine: engine)
            seen.append([engine.shuffleEnabled, engine.repeatEnabled])
        }
        XCTAssertEqual(seen, [[true, false], [false, true], [true, true], [false, false]])
    }
}
