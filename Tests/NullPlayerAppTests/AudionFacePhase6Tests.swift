import CoreGraphics
import XCTest
@testable import NullPlayer

/// Phase 6: the face window redraws only what changed, and what it holds is still the full render.
final class AudionFacePhase6Tests: XCTestCase {
    /// Every kind of change the window sees, in a row: after each, the canvas equals a full render of
    /// the same scene, byte for byte, and redrew only the rects that change touches.
    func testTheCanvasMatchesAFullRenderThroughEveryChange() async throws {
        let face = try await AudionFaceFuzzTests.everyElementFixture().load()
        var host = AudionFaceHostState()
        var interaction = AudionFaceInteractionState()
        let canvas = AudionFaceCanvas()
        let whole = AudionFaceRect(x: 0, y: 0, width: face.base.width, height: face.base.height)
        let albumBox = try XCTUnwrap(face.album?.rect.intersection(whole))

        func step(_ what: String, frame: Int = 0, scale: Int = 2,
                  rects expected: [AudionFaceRect]? = nil, outline: Bool? = nil) throws {
            let scene = AudionFaceScene(face: face, host: host, interaction: interaction, frame: frame, scale: scale)
            let change = canvas.draw(scene)
            let full = try XCTUnwrap(AudionFaceRenderer.render(scene))
            XCTAssertEqual(Self.bytes(try XCTUnwrap(canvas.image)), Self.bytes(full), what)
            if let expected { XCTAssertEqual(change.rects, expected, what) }
            if let outline { XCTAssertEqual(change.outlineChanged, outline, what) }
        }

        try step("first draw", rects: [whole], outline: true)
        try step("nothing changed", rects: [])
        host.playState = .playing
        host.durationSeconds = 300
        host.trackIndex = 4
        host.title = "A title long enough to need cutting from the middle"
        host.artist = "An artist with a long name"
        host.album = "An album"
        try step("a track starts")
        try step("the marquee holds", frame: 40, rects: [])
        try step("the marquee moves only the album box", frame: 200, rects: [albumBox], outline: false)
        host.elapsedSeconds = 61
        try step("the clock ticks", frame: 200)
        interaction.hovered = .stop
        try step("hover", frame: 200)
        interaction.pressed = .stop
        try step("press", frame: 200)
        interaction = .init()
        host.streamPhase = .streaming
        for frame in [201, 202, 203, 204] { try step("the stream animation at \(frame)", frame: frame) }
        host.isWindowActive = false
        try step("the inactive mask", frame: 204, rects: [whole], outline: true)
        host.isWindowActive = true
        try step("the active mask", frame: 204, rects: [whole], outline: true)
        try step("a new scale", frame: 204, scale: 3, rects: [whole])
    }

    func testALineIsRasterizedOnce() async throws {
        let face = try await AudionFaceFuzzTests.everyElementFixture().load()
        let line = try XCTUnwrap(face.album)
        let first = AudionFaceText.image("text", line: line, justify: false, scale: 2, reduceMotion: false)
        let again = AudionFaceText.image("text", line: line, justify: false, scale: 2, reduceMotion: false)
        let other = AudionFaceText.image("text", line: line, justify: false, scale: 3, reduceMotion: false)
        XCTAssertTrue(first === again)
        XCTAssertFalse(first === other)
    }

    /// Premultiplied RGBA, top row first.
    private static func bytes(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                      bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?
                .draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }
}
