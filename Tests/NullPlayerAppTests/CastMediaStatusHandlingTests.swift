import XCTest
@testable import NullPlayer

final class CastMediaStatusHandlingTests: XCTestCase {
    func testMediaStatusParsingSynthesizesIdleOnlyForExplicitlyEmptyArray() {
        let result = CastSessionController.parseMediaStatus(from: ["status": [Any]()])

        switch result {
        case .idleCompletion:
            break
        default:
            XCTFail("Expected idleCompletion for explicit empty status array")
        }
    }

    func testMediaStatusParsingIgnoresMalformedPayloads() {
        let nonArrayResult = CastSessionController.parseMediaStatus(from: [
            "status": ["mediaSessionId": 123]
        ])

        switch nonArrayResult {
        case .ignore:
            break
        default:
            XCTFail("Expected ignore for non-array MEDIA_STATUS payload")
        }

        let malformedArrayResult = CastSessionController.parseMediaStatus(from: [
            "status": [123, 456]
        ])

        switch malformedArrayResult {
        case .ignore:
            break
        default:
            XCTFail("Expected ignore for malformed MEDIA_STATUS array entries")
        }
    }

    func testMediaStatusParsingBuildsStatusFromValidPayload() {
        let result = CastSessionController.parseMediaStatus(from: [
            "status": [[
                "mediaSessionId": 321,
                "currentTime": 42.5,
                "playerState": "PLAYING",
                "media": ["duration": 180.0]
            ]]
        ])

        switch result {
        case .status(let status):
            XCTAssertEqual(status.mediaSessionId, 321)
            XCTAssertEqual(status.currentTime, 42.5, accuracy: 0.001)
            XCTAssertEqual(status.playerState, .playing)
            XCTAssertEqual(status.duration ?? 0, 180.0, accuracy: 0.001)
        default:
            XCTFail("Expected parsed media status for valid payload")
        }
    }

    func testCastFinishGuardBlocksReentryUntilPlayingStatusResetsIt() {
        var finishHandled = false

        XCTAssertFalse(AudioEngine.shouldHandleCastFinish(
            isCastingActive: false,
            hasHandledFinishForCurrentTrack: finishHandled
        ))

        XCTAssertTrue(AudioEngine.shouldHandleCastFinish(
            isCastingActive: true,
            hasHandledFinishForCurrentTrack: finishHandled
        ))

        finishHandled = true

        XCTAssertFalse(AudioEngine.shouldHandleCastFinish(
            isCastingActive: true,
            hasHandledFinishForCurrentTrack: finishHandled
        ))

        finishHandled = AudioEngine.nextCastFinishHandledStateAfterStatusUpdate(
            currentValue: finishHandled,
            isPlaying: false
        )
        XCTAssertTrue(finishHandled)

        finishHandled = AudioEngine.nextCastFinishHandledStateAfterStatusUpdate(
            currentValue: finishHandled,
            isPlaying: true
        )
        XCTAssertFalse(finishHandled)

        XCTAssertTrue(AudioEngine.shouldHandleCastFinish(
            isCastingActive: true,
            hasHandledFinishForCurrentTrack: finishHandled
        ))
    }
}
