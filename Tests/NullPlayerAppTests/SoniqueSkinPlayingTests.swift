import CoreGraphics
import XCTest
@testable import NullPlayer

/// What Sonique draws only while a track is loaded, which the oracle sweep (a stopped, empty
/// player) cannot see: the mid rings and top window, the wrapped title, the visual screen's dots
/// (issues #729, #731, #732, #734). Drawn on NullPlayer's default skin, in its default colours.
@MainActor
final class SoniqueSkinPlayingTests: XCTestCase {
    private let skin = SoniqueSkin.defaultSkin

    /// A rendered scene's pixels, read in skin pixels.
    private struct Pixels {
        let canvas: SoniqueSkinRegion.Rect, width: Int, bytes: [UInt8]

        init(_ scene: SoniqueSkinScene) throws {
            let image = try XCTUnwrap(SoniqueSkinRenderer.render(scene))
            canvas = scene.canvas
            width = image.width
            var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let context = try XCTUnwrap(CGContext(data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8,
                                                  bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            self.bytes = bytes
        }

        func rgb(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
            let i = ((y - canvas.top) * width + (x - canvas.left)) * 4
            return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]))
        }
    }

    private func scene(_ mode: SoniqueSkin.Mode, _ host: SoniqueSkinHostState,
                       screen: SoniqueSkinNavScreen = .menu) -> SoniqueSkinScene {
        SoniqueSkinScene(skin: skin, state: .init(mode: mode, host: host, navScreen: screen))
    }

    private func loaded(song: Double = 0, list: Double = 0, title: String = "") -> SoniqueSkinHostState {
        SoniqueSkinHostState(playState: .playing, songProgress: song, listProgress: list, trackNumber: 1, title: title)
    }

    /// #731: the song ring lights clockwise from 12:00, the part come so far tinted along
    /// `ProgressColor_1`–`_3` (green first), the rest by `ProgressBkColor`.
    func testTheSongRingTintsItsDotsClockwiseFromTwelve() throws {
        let ring = try XCTUnwrap(scene(.mid, .init()).region(for: .songRing))
        let picture = try Pixels(scene(.mid, .init())), playing = try Pixels(scene(.mid, loaded(song: 0.25)))
        let b = ring.bounds, cx = Double(b.left + b.right) / 2, cy = Double(b.top + b.bottom) / 2
        var lit = 0, unlit = 0
        for rect in ring.rects {
            for y in rect.top..<rect.bottom {
                for x in rect.left..<rect.right {
                    let p = picture.rgb(x, y)
                    guard p.b > 10 else { continue }
                    // Clockwise from 12:00, as a fraction of the turn.
                    let turn = (atan2(Double(x) + 0.5 - cx, cy - Double(y) - 0.5) / (2 * .pi) + 1).truncatingRemainder(dividingBy: 1)
                    let q = playing.rgb(x, y)
                    if turn > 0.01 && turn < 0.08 {
                        // The picture times the gradient's start: no blue, a sixth of the red at most.
                        lit += 1
                        XCTAssertLessThanOrEqual(q.b, 2, "lit \(x),\(y)")
                        XCTAssertLessThanOrEqual(q.r, p.r / 6 + 2, "lit \(x),\(y)")
                    } else if turn > 0.3 && turn < 0.98 {
                        unlit += 1
                        XCTAssertLessThanOrEqual(q.b, p.b * 0x60 / 255 + 2, "unlit \(x),\(y)")
                    }
                }
            }
        }
        XCTAssertGreaterThan(lit, 0)
        XCTAssertGreaterThan(unlit, 0)

        // Filled, half way round is `ProgressColor_2` and the end `_3`, each times the picture.
        let full = try Pixels(scene(.mid, loaded(song: 1)))
        for (stop, range) in [(SoniqueColour.progressColor2, 0.49...0.51), (.progressColor3, 0.97...0.99)] {
            let c = skin.settings.colour(stop)
            let tint = (r: Int(c >> 16 & 0xFF), g: Int(c >> 8 & 0xFF), b: Int(c & 0xFF))
            var seen = 0
            for rect in ring.rects {
                for y in rect.top..<rect.bottom {
                    for x in rect.left..<rect.right {
                        let p = picture.rgb(x, y)
                        let turn = (atan2(Double(x) + 0.5 - cx, cy - Double(y) - 0.5) / (2 * .pi) + 1).truncatingRemainder(dividingBy: 1)
                        guard p.b > 10, range.contains(turn) else { continue }
                        seen += 1
                        let q = full.rgb(x, y)
                        for (got, want) in [(q.r, p.r * tint.r / 255), (q.g, p.g * tint.g / 255), (q.b, p.b * tint.b / 255)] {
                            XCTAssertEqual(got, want, accuracy: 12, "\(stop) \(x),\(y)")
                        }
                    }
                }
            }
            XCTAssertGreaterThan(seen, 0, "\(stop)")
        }
    }

    /// #729: with a track loaded mid mode's top window is black under the effects surface, which
    /// sits over it less the window balls; with nothing loaded it stays the picture.
    func testTheTopWindowIsTheVisWhileATrackIsLoaded() throws {
        let playing = scene(.mid, loaded())
        let top = try XCTUnwrap(playing.region(for: .vis))
        let area = try XCTUnwrap(playing.effectsArea)
        XCTAssertEqual(area.rect, top.bounds)
        XCTAssertEqual(area.holes, playing.ballRects.map(\.1))
        XCTAssertNil(scene(.mid, .init()).effectsArea)
        XCTAssertNil(scene(.navigator, loaded()).effectsArea)
        XCTAssertNotNil(scene(.navigator, loaded(), screen: .visualMode).effectsArea)

        let drawn = try Pixels(playing), idle = try Pixels(scene(.mid, .init()))
        let balls = playing.ballRects.map(\.1)
        var lit = 0, painted = 0
        for rect in top.rects {
            for y in rect.top..<rect.bottom {
                for x in rect.left..<rect.right where !balls.contains(where: { x >= $0.left && x < $0.right && y >= $0.top && y < $0.bottom }) {
                    let p = drawn.rgb(x, y), q = idle.rgb(x, y)
                    if p.r + p.g + p.b > 0 { lit += 1 }
                    if q.r + q.g + q.b > 0 { painted += 1 }
                }
            }
        }
        XCTAssertGreaterThan(painted, 0)
        XCTAssertEqual(lit, 0)
    }

    /// #732: a title too long for one line wraps onto the next, 11 px down, rather than scrolling.
    func testALongTitleWrapsInTheSongWindow() throws {
        let window = try XCTUnwrap(scene(.mid, .init()).region(for: .songInfo)).bounds
        let wrapped = try Pixels(scene(.mid, loaded(title: "05 - Bella Ciao.mp3")))
        let short = try Pixels(scene(.mid, loaded(title: "Ciao")))
        // The second line's band: baseline 41 + 11, its letters 7 rows high.
        let differs = (window.top + 45..<window.top + 53).contains { y in
            (window.left..<window.right).contains { x in wrapped.rgb(x, y) != short.rgb(x, y) }
        }
        XCTAssertTrue(differs)
    }

    /// #734: a row's lit dots run along its gradient by place, the playlist's from `PlayListColor_1`
    /// (cyan) at the left to `_2` (magenta) at the right.
    func testTheVisualScreenDotsRunAlongTheirGradient() throws {
        let screen = scene(.navigator, loaded(list: 1), screen: .visualMode)
        let display = try XCTUnwrap(screen.visualScreenDisplay).bounds
        let dots = try Pixels(screen)
        typealias Screen = SoniqueSkinScene.VisualScreen
        let y = display.bottom + Screen.progressRows[0].top + Screen.dotSize / 2
        let centre = { (dot: Int) in display.left + Screen.dotLeft + dot * Screen.dotSize + Screen.dotSize / 2 }
        let first = dots.rgb(centre(0), y), last = dots.rgb(centre(Screen.dots - 1), y)
        XCTAssertLessThan(first.r, 40)
        XCTAssertGreaterThan(first.g, 200)
        XCTAssertGreaterThan(last.r, 200)
        XCTAssertLessThan(last.g, 40)
    }
}
