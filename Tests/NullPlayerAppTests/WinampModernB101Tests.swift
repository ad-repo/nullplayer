import XCTest
@testable import NullPlayer

/// B101 — the two containers that only fake a Windows desktop effect never reach the screen.
///
/// Reported 2026-09-04 on **cPro2 Dark Aluminum** as "large outlines of windows only that launch
/// alongside the main window — these are just rectangles made from lines". Measured through the
/// accessibility API: `main.shadow` at 830×630 (the player plus `shadow.maki`'s `-15,-15,+30,+30`,
/// unplaced in a screen corner) and `main.aerosnap` at 950×1060 (`layout.m`'s LEFT SNAP rect on a
/// 1920×1080 display). Neither draws any of the skin's own UI — one is a nine-slice with no centre,
/// the other a 4px border grid — and macOS supplies both effects itself.
///
/// The entry recorded the decision to leave them inert; B110 then gave dynamic containers real
/// windows and both scripts got what they had always asked for. This pins the classification the
/// window layer now gates `setAuxiliaryWindow` on, including the corpus measurement behind it: across
/// all 69 archives `aerosnap` occurs twice and nothing else ends in `shadow`.
final class WinampModernB101Tests: XCTestCase {
    func testClassicProGlueContainersAreClassifiedAsDesktopEffects() {
        for id in ["main.shadow", "main.aerosnap", "MAIN.SHADOW", "shadow", "aerosnap"] {
            XCTAssertTrue(WinampModernContainerTopology.isHostProvidedDesktopEffect(id: id),
                          "\(id) draws a Windows desktop effect and must never open")
        }
    }

    func testOrdinarySkinWindowsAreNotDesktopEffects() {
        // Every other container id cPro2 declares, plus the ones the corpus's other skins use for
        // real windows. A false positive here is a window the user can never open.
        for id in ["main", "main.tooltip", "notifier", "browserpro", "searchresults",
                   "widgets.manager", "Pledit", "MLibrary", "AVS", "Video", "eq",
                   "sc.alphaframe", "shadowbox", "drop.shadow.editor"] {
            XCTAssertFalse(WinampModernContainerTopology.isHostProvidedDesktopEffect(id: id),
                           "\(id) is an ordinary skin window")
        }
    }
}
