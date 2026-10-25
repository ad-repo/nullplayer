import CoreGraphics
import Foundation

extension SoniqueSkinScene {
    /// Sonique's visual mode screen, the same on every skin but for its colours (screen 3 of
    /// sonique, k2 and BlueEyes, 2026-10-18), as three rounded panels in `SystemBkColor_2` — none
    /// where that is pure black, the colour that is transparent everywhere in a skin (BlueEyes).
    /// The vis panel's top is a title bar naming the effect, over the black the effects surface
    /// fills; the song panel holds the track number and time over their labels and the playlist's
    /// and the track's progress as 32 dots each; the file panel names the file. The vis and file
    /// panels hang from the display's top-left, the song panel stands on its bottom (BlueEyes's
    /// display is 11 px shorter than sonique's, and its song panel 11 px higher). Cut to the display
    /// like every screen, so a skin's art outside it stays over the panels (BlueEyes).
    enum VisualScreen {
        typealias Rect = SoniqueSkinRegion.Rect
        // From the display's top-left.
        static let visFrame = Rect(left: 6, top: 0, right: 216, bottom: 126)
        static let well = Rect(left: 11, top: 11, right: 211, bottom: 122)
        static let effects = Rect(left: 15, top: 16, right: 207, bottom: 117)
        /// Black whatever the panels: with none drawn it runs up under the title.
        static let visBlack = Rect(left: 15, top: 0, right: 207, bottom: 117)
        static let titleCentre = 101, titleBaseline = 9
        static let fileFrame = Rect(left: 243, top: 39, right: 301, bottom: 131)
        static let fileLeft = 246, fileBaseline = 50, fileLineHeight = 10
        /// The labels' lettering: Verdana Bold 9 spaced half a pixel; the digits are Tahoma Bold 21
        /// (each the closest of six faces, sizes and spacings to the oracle's own pixels).
        static let labelSpacing: CGFloat = 0.5
        static let digitFont = "Tahoma-Bold", digitSize: CGFloat = 21
        static let panelRadius: CGFloat = 5
        // From the display's bottom-left.
        static let songFrame = Rect(left: 6, top: -92, right: 216, bottom: -13)
        /// The track number at x 18 and the time at x 75; each label centred under its digits.
        static let digitsBaseline = -70, trackX = 17, timeX = 74
        static let labels = [("track", 37), ("hour", 87), ("min", 121), ("sec", 155), ("hun", 189)]
        static let labelBaseline = -61
        /// Each progress row: 32 dots 6 px across from x 14, its label under it at x 17.
        static let dots = 32, dotLeft = 14, dotSize = 6
        static let progressRows = [(top: -56, label: "playlist progress", baseline: -41),
                                   (top: -37, label: "track progress", baseline: -23)]
    }

    /// The display while the navigator shows the visual mode screen, nil otherwise.
    var visualScreenDisplay: SoniqueSkinRegion? {
        guard state.mode == .navigator, state.navScreen == .visualMode else { return nil }
        return skin.display
    }
}
