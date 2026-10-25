import XCTest
@testable import NullPlayer

final class SoniqueSkinSceneTests: XCTestCase {
    /// A 40×30 navigator frame whose 120×60 drawer sits under it at 0,30 and slides 50 px down, with a knob
    /// at 100,5 and sliders 4×20 at 2,2, 5 apart (all in the drawer's own pixels).
    private func navigator(open: Bool) throws -> SoniqueSkinScene {
        var entries = SoniqueSkinFixture.complete
        entries[0] = ("/skin.ini", Data("""
            [misc locations]\r\nDRAWER_POS_x=0\r\nDRAWER_POS_y=30\r\n[misc values]\r\nMISC_DRAWER_DISTANCE_TOSLIDE=50\r
            MISC_DRAWER_SLIDER_ARRAY_POS_x=2\r\nMISC_DRAWER_SLIDER_ARRAY_POS_y=2\r\nMISC_DRAWER_SLIDER_SIZE_x=4\r
            MISC_DRAWER_SLIDER_SIZE_y=20\r\nMISC_DRAWER_SLIDER_PITCH=5\r\n
            """.utf8))
        // Nav regions are cut to the nav picture (`SQ0010`), so it is as large as the drawer.
        entries[1] = ("/jpeg/navigator", SoniqueSkinFixture.jpeg(width: 120, height: 60))
        entries += [("/rgn/nav/drawer", SoniqueSkinFixture.region([(0, 0, 120, 60)])),
                    ("/rgn/nav/dknobamp", SoniqueSkinFixture.region([(100, 5, 110, 15)]))]
        let skin = try SoniqueSkinLoader.load(data: SoniqueSkinFixture.sgf(entries))
        return SoniqueSkinScene(skin: skin, state: .init(mode: .navigator, navDrawerOpen: open))
    }

    /// A point in skin pixels, as the scene hits canvas pixels.
    private func hit(_ scene: SoniqueSkinScene, _ x: Int, _ y: Int) -> SoniqueSkinControl? {
        scene.hit(x: x - scene.canvas.left, y: y - scene.canvas.top).control
    }

    func testTheOpenDrawerSlidesAndItsDialsAreHit() throws {
        let open = try navigator(open: true)
        XCTAssertEqual(hit(open, 4, 30 + 50 + 12), .eqSlider(0))
        XCTAssertEqual(hit(open, 2 + 3 * 5 + 1, 30 + 50 + 12), .eqSlider(3))
        XCTAssertEqual(hit(open, 105, 30 + 50 + 10), .amp)
        // The tab is a press the window acts on (it toggles the drawer), not chassis; the amp,
        // balance and pitch knobs are chassis (decision record Amendment 4).
        XCTAssertTrue(SoniqueSkinControl.drawerTab.isActionable)
        XCTAssertFalse(SoniqueSkinControl.amp.isActionable)
        XCTAssertFalse(SoniqueSkinControl.pitch.isActionable)
    }

    /// A navigator whose 301×228 display sits at 10,20.
    private func console(_ screen: SoniqueSkinNavScreen) throws -> SoniqueSkinScene {
        var entries = SoniqueSkinFixture.complete
        entries[1] = ("/jpeg/navigator", SoniqueSkinFixture.jpeg(width: 320, height: 260))
        entries[2] = ("/rgn/nav/frame", SoniqueSkinFixture.region([(0, 0, 320, 260)]))
        entries.append(("/rgn/nav/display", SoniqueSkinFixture.region([(10, 20, 311, 248)])))
        let skin = try SoniqueSkinLoader.load(data: SoniqueSkinFixture.sgf(entries))
        return SoniqueSkinScene(skin: skin, state: .init(mode: .navigator, navScreen: screen))
    }

    func testTheMenuScreenHitsItsItemsFromTheDisplayCorner() throws {
        let menu = try console(.menu)
        XCTAssertEqual(hit(menu, 10 + 50, 20 + 80), .menu(.visualMode))
        XCTAssertEqual(hit(menu, 10 + 30, 20 + 178), .menu(.setup))
        XCTAssertEqual(hit(menu, 10 + 230, 20 + 47), .menu(.spectrum))
        XCTAssertEqual(hit(menu, 10 + 230, 20 + 142), .menu(.about))
        XCTAssertFalse(menu.balls.contains(.back))
    }

    func testAnotherScreenHasNoMenuItemsAndABackBall() throws {
        let screen = try console(.visualMode)
        XCTAssertNil(hit(screen, 10 + 50, 20 + 80))
        XCTAssertEqual(screen.balls.first, .back)
        let back = try XCTUnwrap(screen.ballRects.first?.1), next = try XCTUnwrap(screen.ballRects.dropFirst().first?.1)
        XCTAssertEqual(next.left - back.left, 12)
    }

    func testTheClosedDrawerHasNoDialsAndTheWindowKeepsRoomToOpen() throws {
        let closed = try navigator(open: false), open = try navigator(open: true)
        XCTAssertNil(hit(closed, 4, 30 + 12))
        XCTAssertNil(hit(closed, 105, 30 + 10))
        XCTAssertEqual(closed.canvas, open.canvas)
        XCTAssertEqual(closed.canvas.bottom, 30 + 50 + 60)
    }

    /// Every key the renderer builds at run time (`NAV_` + a lit state, a knob's `_width`, a ball's
    /// `MSM_` position) is read through `SoniqueSkinSettings.int`, which traps on an unknown one. The
    /// oracle sweep draws only the stopped state, so this draws every press in every play state.
    func testEveryPressInEveryStateRenders() {
        let skin = SoniqueSkin.defaultSkin
        let controls: [SoniqueSkinControl] = [.play, .pause, .prev, .next, .eject, .repeatButton, .shuffle, .volume,
                                              .up, .down, .navButton, .vis, .songInfo, .shuttle, .drawerTab,
                                              .amp, .balance, .pitch, .eqSlider(0)]
            + SoniqueSkinControl.Ball.allCases.map { .ball($0) } + SoniqueSkinMenu.Item.allCases.map { .menu($0) }
        for mode in SoniqueSkin.Mode.allCases {
            for state in [SoniqueSkinHostState.PlayState.stopped, .playing, .paused] {
                let host = SoniqueSkinHostState(playState: state, shuffle: true, repeatAll: true, title: "title",
                                                blinkersLit: true)
                for pressed in controls {
                    for screen in [SoniqueSkinNavScreen.menu, .visualMode] {
                        let scene = SoniqueSkinScene(skin: skin, state: .init(mode: mode, host: host, pressed: pressed, smallDrawer: .top,
                                                                                   navDrawerOpen: true, navScreen: screen))
                        XCTAssertNotNil(SoniqueSkinRenderer.render(scene), "\(mode) \(state) \(pressed)")
                    }
                }
            }
        }
    }

    func testEveryColourKeyHasADefault() {
        let settings = SoniqueSkin.defaultSkin.settings
        for key in SoniqueColour.allCases { _ = settings.colour(key) }
    }

    /// The scene and renderer read these with no fallback, so a key without a default traps.
    func testEveryTypedKeyHasADefault() {
        let settings = SoniqueSkinSettings(SoniqueSkinINI(""))
        for state in SoniqueLitState.allCases {
            _ = settings.origin(state)
            _ = settings.origin(state, navigator: true)
        }
        for strip in SoniqueKnobStrip.allCases { _ = settings.frames(strip) }
        _ = (settings.drawerSliders, settings.midBallOrigins, settings.navBallInset, settings.midRingsFillFromTop)
    }
}
