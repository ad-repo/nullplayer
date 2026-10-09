import CoreGraphics
import XCTest
@testable import NullPlayer

/// `AudionFaceScene`'s state rules and `AudionFaceRenderer`'s compositing, over synthesized faces.
/// The corpus-wide check of both is the oracle comparison (`skills/audion-face-guide/reference/harness.md`).
final class AudionFaceSceneTests: XCTestCase {
    private let red: [UInt8] = [255, 0, 0, 255], green: [UInt8] = [0, 255, 0, 255]
    private let blue: [UInt8] = [0, 0, 255, 255], clear: [UInt8] = [0, 0, 0, 0]

    /// FaceKit's layers: digits and indicators sit above the buttons (zPosition 2 over 1), an
    /// animation clears the base under it, and the mask, anchored bottom-left, cuts everything.
    func testLayersCompositeInFaceKitsOrder() async throws {
        let fixture = try AudionFaceFixture(json: [
            "stopButtonRect": AudionFaceFixture.rect(top: 0, left: 0, bottom: 2, right: 2),
            "timeDigit1Rect": AudionFaceFixture.rect(top: 1, left: 1, bottom: 2, right: 2),
            "timeDigit1FirstPICTID": 100,
            "connectingAnimRect": AudionFaceFixture.rect(top: 3, left: 3, bottom: 4, right: 4),
            "connectingFirstPICTID": 200, "connectingNumPICTs": 1, "connectingFrameDelay": 1,
        ])
        try fixture.png("base.png", width: 4, height: 4, fill: green)
        try fixture.png("stop.png", width: 2, height: 2, fill: red)
        for id in 100..<110 { try fixture.png("\(id).png", fill: blue) }
        try fixture.png("200.png", fill: clear)
        // A 4×3 mask: the base's top row is outside it and must come out transparent.
        try fixture.png("base-alpha.png", width: 4, height: 3, fill: [0, 0, 0, 255])
        let face = try await fixture.load()

        var host = AudionFaceHostState()
        host.streamPhase = .connecting
        let image = try XCTUnwrap(AudionFaceRenderer.render(AudionFaceScene(face: face, host: host)))
        XCTAssertEqual(Self.pixel(image, 0, 0), clear, "the mask's missing top row")
        XCTAssertEqual(Self.pixel(image, 0, 1), red, "the button over the base")
        XCTAssertEqual(Self.pixel(image, 1, 1), blue, "the digit over the button")
        XCTAssertEqual(Self.pixel(image, 2, 2), green, "the base")
        XCTAssertEqual(Self.pixel(image, 3, 3), clear, "the transparent animation frame cleared the base")
    }

    func testButtonStatesFollowFaceKitsPrecedence() async throws {
        let fixture = try AudionFaceFixture(json: [
            "playButtonRect": AudionFaceFixture.rect(top: 0, left: 0, bottom: 1, right: 1),
            "stopButtonRect": AudionFaceFixture.rect(top: 0, left: 2, bottom: 1, right: 3),
        ])
        for name in ["play", "play-active", "play-hover", "pause", "stop", "stop-disabled"] { try fixture.png("\(name).png") }
        let face = try await fixture.load()
        func image(_ role: AudionFace.ButtonRole, _ scene: AudionFaceScene) -> CGImage? {
            scene.ops.first { $0.element == .button(role) }?.image
        }

        var host = AudionFaceHostState()
        XCTAssertTrue(image(.stop, AudionFaceScene(face: face, host: host)) === face.buttons[.stop]?.disabledImage,
                      "stop is disabled with no duration")
        var interaction = AudionFaceInteractionState(hovered: .play, pressed: .play)
        XCTAssertTrue(image(.play, AudionFaceScene(face: face, host: host, interaction: interaction))
                      === face.buttons[.play]?.pressedImage, "pressed beats hover")
        interaction.pressed = nil
        XCTAssertTrue(image(.play, AudionFaceScene(face: face, host: host, interaction: interaction))
                      === face.buttons[.play]?.hoverImage)
        XCTAssertEqual(AudionFaceScene.button(atX: 0, y: 0, face: face, host: host), .play)

        host.playState = .playing
        host.durationSeconds = 10
        let playing = AudionFaceScene(face: face, host: host)
        XCTAssertNil(image(.play, playing), "play hides while playing")
        XCTAssertNotNil(image(.pause, playing))
        XCTAssertTrue(image(.stop, playing) === face.buttons[.stop]?.image)
        XCTAssertEqual(AudionFaceScene.button(atX: 0, y: 0, face: face, host: host), .pause)
    }

    func testIndicatorsAndDigitsFollowTheHostState() async throws {
        var json: [String: Any] = [
            "timeDigit4Rect": AudionFaceFixture.rect(top: 0, left: 0, bottom: 1, right: 1), "timeDigit4FirstPICTID": 100,
            "trackDigit2Rect": AudionFaceFixture.rect(top: 0, left: 1, bottom: 1, right: 2), "trackDigit2FirstPICTID": 200,
        ]
        for (index, key) in ["MP3IndicatorRect", "netIndicatorRect", "pauseIndicatorRect"].enumerated() {
            json[key] = AudionFaceFixture.rect(top: 1, left: index, bottom: 2, right: index + 1)
        }
        let fixture = try AudionFaceFixture(json: json)
        try fixture.picts(100, count: 10)
        try fixture.picts(200, count: 11)
        for name in ["mp3", "net", "pause-indicator"] {
            try fixture.png("\(name).png")
            try fixture.png("\(name)-on.png")
        }
        let face = try await fixture.load()
        func image(_ element: AudionFaceDrawOp.Element, _ host: AudionFaceHostState) -> CGImage? {
            AudionFaceScene(face: face, host: host).ops.first { $0.element == element }?.image
        }

        var host = AudionFaceHostState()
        host.elapsedSeconds = 83
        XCTAssertTrue(image(.digit(.timeDigit4), host) === face.digits[.timeDigit4]?.images[3])
        XCTAssertTrue(image(.digit(.trackDigit2), host) === face.digits[.trackDigit2]?.images[10], "blank without a track")
        host.trackIndex = 7
        XCTAssertTrue(image(.digit(.trackDigit2), host) === face.digits[.trackDigit2]?.images[7])
        XCTAssertTrue(image(.indicator(.mp3), host) === face.indicators[.mp3]?.image, "off with no duration")

        host.durationSeconds = 100
        host.playState = .paused
        XCTAssertTrue(image(.indicator(.mp3), host) === face.indicators[.mp3]?.onImage)
        XCTAssertTrue(image(.indicator(.pause), host) === face.indicators[.pause]?.onImage)
        host.streamPhase = .streaming
        XCTAssertTrue(image(.indicator(.net), host) === face.indicators[.net]?.onImage)
        XCTAssertTrue(image(.indicator(.mp3), host) === face.indicators[.mp3]?.image)
    }

    /// FaceKit `LabelView.frameNum`, worked by hand for a 40 px string in a 100 px box.
    func testMarqueeHoldsThenScrollsAndReentersFromTheRight() {
        let offset = { AudionFaceScene.marqueeOffset(frame: $0, textWidth: 40, boxWidth: 100) }
        XCTAssertEqual(offset(79), 0)
        XCTAssertEqual(offset(84), -2)
        XCTAssertEqual(offset(80 + 2 * 100), -100, "the last step before the gap is spent")
        XCTAssertEqual(offset(80 + 2 * 101), 99, "re-entering at the box's right edge")
        XCTAssertEqual(offset(80 + 2 * 200), 0, "one full cycle of 200 steps")
    }

    /// The window's clock runs only while `frame` moves something: a multi-frame animation that
    /// advances, or an album line that scrolls (never under Reduce Motion).
    func testTheClockRunsOnlyWhileSomethingMoves() async throws {
        let fixture = try AudionFaceFixture(json: [
            "timeDigit2Rect": AudionFaceFixture.rect(top: 0, left: 1, bottom: 1, right: 2), "timeDigit2FirstPICTID": 100,
            "streamingAnimRect": AudionFaceFixture.rect(top: 1, left: 0, bottom: 2, right: 1),
            "streamingFirstPICTID": 200, "streamingNumPICTs": 2, "streamingFrameDelay": 3,
            "connectingAnimRect": AudionFaceFixture.rect(top: 1, left: 1, bottom: 2, right: 2),
            "connectingFirstPICTID": 300, "connectingNumPICTs": 1, "connectingFrameDelay": 3,
            "albumDisplayRect": AudionFaceFixture.rect(top: 2, left: 0, bottom: 4, right: 20), "albumTextMode": 1,
            "albumDisplayTextFaceColorFromFace": ["red": 0, "green": 0, "blue": 0],
        ])
        try fixture.png("base.png", width: 20, height: 4)
        try fixture.picts(100, count: 10)
        try fixture.picts(200, count: 2)
        try fixture.png("300.png")
        let face = try await fixture.load()

        var host = AudionFaceHostState()
        XCTAssertFalse(AudionFaceScene.isAnimated(face, host), "nothing to scroll and no animation")
        host.streamPhase = .connecting
        XCTAssertFalse(AudionFaceScene.isAnimated(face, host), "a one-frame animation never steps")
        host.streamPhase = .streaming
        XCTAssertTrue(AudionFaceScene.isAnimated(face, host))
        host.streamPhase = .none
        host.artist = "Someone"
        XCTAssertTrue(AudionFaceScene.isAnimated(face, host), "the album line scrolls")
        host.reduceMotion = true
        XCTAssertFalse(AudionFaceScene.isAnimated(face, host))

        XCTAssertEqual(AudionFaceScene.timeDigitRects(face), [AudionFaceRect(x: 1, y: 0, width: 1, height: 1)])
    }

    /// The pixel at `x`, `y`, top-left origin, as RGBA.
    static func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        return bytes
    }
}
