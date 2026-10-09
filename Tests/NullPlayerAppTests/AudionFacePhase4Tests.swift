import AppKit
import XCTest
@testable import NullPlayer

/// Phase 4's face behaviour that runs without a window: the keys and the mode button's cycle.
/// The popups, the clock and accessibility are checked live (`skills/audion-face-guide/reference/windows.md`).
@MainActor
final class AudionFacePhase4Tests: XCTestCase {

    func testKeysMapToTheMainWindowsCommands() throws {
        var host = AudionFaceHostState()
        host.elapsedSeconds = 3
        host.durationSeconds = 100
        host.volume = 0.5
        func command(_ keyCode: UInt16, _ characters: String = "") -> AudionFaceCommand? {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                         windowNumber: 0, context: nil, characters: characters,
                                         charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)
            return event.flatMap { AudionFaceCommand(key: $0, host: host) }
        }

        XCTAssertEqual(command(49, " "), .button(.play))
        host.playState = .playing
        XCTAssertEqual(command(49, " "), .button(.pause), "space toggles")
        XCTAssertEqual(command(123), .seek(0), "never before the start")
        XCTAssertEqual(command(124), .seek(8))
        XCTAssertEqual(command(126), .volume(0.55))
        XCTAssertEqual(command(6, "z"), .button(.rewind))
        XCTAssertEqual(command(11, "B"), .button(.fastForward))
        XCTAssertNil(command(0, "a"))
    }

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
