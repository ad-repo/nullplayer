import AppKit
import XCTest
@testable import NullPlayer

final class ArtWindowTests: XCTestCase {
    /// The default height is the content cut to the cover's aspect ratio, plus the chrome.
    func testDefaultHeightFollowsTheCoverAspectRatio() {
        // Classic spectrum-family chrome: 12 + 12 sides, 20 title + 7 bottom.
        XCTAssertEqual(WindowManager.artWindowHeight(width: 275, horizontalChrome: 24, verticalChrome: 27,
                                                     aspectRatio: 1), 278)
        XCTAssertEqual(WindowManager.artWindowHeight(width: 275, horizontalChrome: 24, verticalChrome: 27,
                                                     aspectRatio: 0.5), 153)
        XCTAssertEqual(WindowManager.artWindowHeight(width: 10, horizontalChrome: 24, verticalChrome: 27,
                                                     aspectRatio: 1), 27, "chrome wider than the window")
    }

    func testEffectStepsWrapBothWays() {
        let all = ArtVisEffect.allCases
        XCTAssertEqual(all.last?.advanced(by: 1), all.first)
        XCTAssertEqual(all.first?.advanced(by: -1), all.last)
        XCTAssertEqual(all.first?.advanced(by: all.count), all.first)
    }

    /// Every effect is in exactly one menu group, so none is unreachable from the menu.
    func testEveryEffectIsInExactlyOneGroup() {
        let grouped = ArtVisEffect.groups.flatMap(\.effects)
        XCTAssertEqual(grouped.count, ArtVisEffect.allCases.count)
        XCTAssertEqual(Set(grouped), Set(ArtVisEffect.allCases))
    }

    func testEveryEffectRendersAFrame() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.orange.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        let image = try XCTUnwrap(context.makeImage())
        let renderer = ArtVisRenderer()
        let spectrum = [Float](repeating: 0.6, count: 75)
        for effect in ArtVisEffect.allCases {
            XCTAssertNotNil(renderer.render(image, effect: effect, spectrum: spectrum, time: 1.5, intensity: 1),
                            effect.rawValue)
        }
    }

    func testOpenArtWindowSurvivesASavedState() throws {
        var state = AppStateManager.AppState.fixture()
        state.isArtVisible = true
        state.artWindowFrame = NSStringFromRect(NSRect(x: 10, y: 20, width: 344, height: 354))
        let decoded = try JSONDecoder().decode(AppStateManager.AppState.self, from: JSONEncoder().encode(state))
        XCTAssertTrue(decoded.isArtVisible)
        XCTAssertEqual(decoded.artWindowFrame, state.artWindowFrame)

        // A state saved before the Art window existed restores it closed.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        json.removeValue(forKey: "isArtVisible")
        let legacy = try JSONDecoder().decode(AppStateManager.AppState.self,
                                              from: JSONSerialization.data(withJSONObject: json))
        XCTAssertFalse(legacy.isArtVisible)
    }

    func testRadioStreamsAreNotRateable() {
        let station = RadioStation(name: "Test FM", url: URL(string: "https://example.com/stream")!)
        XCTAssertFalse(TrackRatingService.isRateable(station.toTrack()))
        XCTAssertTrue(TrackRatingService.isRateable(Track(lightweightURL: URL(fileURLWithPath: "/tmp/a.mp3"))))
    }
}
