import Foundation

/// What the player is doing, as a Sonique skin shows it. The scene reads only this.
struct SoniqueSkinHostState: Equatable {
    enum PlayState { case stopped, playing, paused }

    var playState: PlayState = .stopped
    var shuffle = false
    var repeatAll = false
    /// 0–1.
    var volume = 1.0
    /// 0–1 through the track, and through the playlist.
    var songProgress = 0.0
    var listProgress = 0.0
    /// 1-based; 0 with nothing loaded.
    var trackNumber = 0
    var elapsedSeconds = 0
    /// The hundredths past `elapsedSeconds`, which the visual mode screen's clock shows.
    var elapsedHundredths = 0
    var title = ""
    /// The playing file's name, for the visual mode screen's file panel.
    var fileName = ""
    /// Loud enough to light small mode's blinkers.
    var blinkersLit = false
    /// The navigator drawer's dials, 0–1: its knobs (0.5 is centre) and its 20 EQ sliders.
    var amp = 0.5
    var balance = 0.5
    var pitch = 0.5
    var eq = Array(repeating: 0.5, count: SoniqueSkinScene.eqSliders)
    /// NullPlayer's version, which the menu screen shows where Sonique's own sat.
    var version = ""

    /// A knob's or slider's value; nil for a control that is pressed, not turned.
    func dial(_ control: SoniqueSkinControl) -> Double? {
        switch control {
        case .volume: return volume
        case .amp: return amp
        case .balance: return balance
        case .pitch: return pitch
        case .eqSlider(let index): return eq.indices.contains(index) ? eq[index] : nil
        default: return nil
        }
    }
}

/// Everything a mode can be clicked on: a skin region, or one of the controls Sonique draws itself
/// (the window balls and small mode's drawer icons).
enum SoniqueSkinControl: Hashable {
    case play, pause, prev, next, eject, repeatButton, shuffle, volume
    /// The navigator's menu rocker.
    case up, down
    /// Mid mode's "nav" button (`/rgn/mid/eq`), and its vis and song windows (`top`, `bottom`).
    case navButton, vis, songInfo
    case shuttle, drawerTab, songRing, listRing
    /// The navigator drawer's knobs and EQ sliders, 0-based.
    case amp, balance, pitch, eqSlider(Int)
    case ball(Ball)
    /// An item of the navigator's menu screen.
    case menu(SoniqueSkinMenu.Item)

    /// Sonique's navigation balls: the mode jumps, help, minimise and close
    /// (help `02.htm` § *The Navigation Buttons*), and the navigator's back to the menu screen.
    enum Ball: CaseIterable {
        case back, modeUp, modeUpTwice, modeDown, modeDownTwice, help, minimize, close
    }

    /// A press that does something; a region with no action (the display, the rings) is chassis.
    /// The drawer's amp, balance and pitch knobs are disabled (decision record Amendment 4): they
    /// set the preamp, balance and playback speed with nothing on screen saying so, and a skin can
    /// draw them as anything (Pokemon's are numbered buttons), so a stray drag leaves a bad setting
    /// the user never notices. They still draw the engine's values.
    var isActionable: Bool {
        switch self {
        case .songRing, .listRing, .amp, .balance, .pitch: return false
        default: return true
        }
    }
}

/// Which way small mode's drawer slid out, or nil while it is closed.
enum SoniqueSmallDrawer: Equatable { case top, bottom }

/// Which screen the navigator's display shows. Sonique has seven; NullPlayer keeps two in the
/// display and opens its own windows for the rest (decision record § *Decisions*).
enum SoniqueSkinNavScreen: Equatable {
    case menu, visualMode
    /// A screen with nothing on it but the back ball: what the render probe draws against the
    /// oracle's *setup › skins* screen, which NullPlayer does not have.
    case blank
}

extension SoniqueSkinScene {
    /// Everything a scene shows but its skin. The window keeps one and draws a scene from it.
    struct State: Equatable {
        var mode: SoniqueSkin.Mode = .navigator
        var host = SoniqueSkinHostState()
        var pressed: SoniqueSkinControl?
        var smallDrawer: SoniqueSmallDrawer?
        /// The navigator's drawer, slid out.
        var navDrawerOpen = false
        /// What the navigator's display shows.
        var navScreen: SoniqueSkinNavScreen = .menu
        /// The effect the visual mode screen's panel names.
        var visualModeTitle = ""
        /// How far a title too long for its line has scrolled, in skin pixels: the status line, mid
        /// mode's song window and small mode's drawer all scroll the same title together.
        var marqueeOffset = 0

        /// Lets go of the press and closes small mode's drawer, as a new mode or skin does.
        mutating func letGo() {
            pressed = nil
            smallDrawer = nil
        }

        /// What follows from a change from `old`: a new mode lets go of the press and closes small
        /// mode's drawer, and a new title scrolls from its start.
        mutating func settle(after old: Self) {
            if mode != old.mode { letGo() }
            if host.title != old.host.title { marqueeOffset = 0 }
        }

        /// Whether this is `old` with only the marquee moved on.
        func isScrolled(from old: Self) -> Bool {
            var scrolled = old
            scrolled.marqueeOffset = marqueeOffset
            return scrolled == self
        }
    }
}
