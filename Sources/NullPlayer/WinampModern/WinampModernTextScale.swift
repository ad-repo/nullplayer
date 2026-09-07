import CoreGraphics
import Foundation

/// How large NullPlayer draws its **own** text inside a `.wal` skin — the embedded playlist's rows
/// and the embedded Media Library, which move together and cannot drift apart.
///
/// Both surfaces are the *host's*, not the skin's: a `<windowholder hold="guid:{45F3F7C1-…}">` is
/// filled by the player, so there is no `fontsize` on it to read, and in Winamp the playlist font is
/// a Winamp preference rather than something the skin states. So the size has to be decided here.
///
/// The first attempt (`b2980d3a`) read the **median `fontsize` declared near the holder**, and it
/// does not work: Big Bento Modern's playlist pane declares 22 and wants the large rows, Defix
/// Hi-END 200's declares 19/20 and does not — the two skins are indistinguishable by their fonts.
/// **Window size separates them cleanly**, which is why `auto` is keyed on the hosting layout's
/// canvas height instead of on anything the skin says about text.
///
/// ```
/// auto cell (px) = clamp(canvasHeight / autoDivisor, 11, autoMaximumPixelHeight)
/// explicit cell  = 11 * percent / 100      // an explicit choice is not capped at 18
/// content scale  = cell / 11               // what the library multiplies its own scale by
/// ```
///
/// Stored per skin (`WinampModernSkinState`, section `@nullplayer.text`), because the right answer is
/// a property of the skin's layout and a user who sizes Bento's text has said nothing about Defix.
enum WinampModernTextScale: Int, CaseIterable {
    /// Keyed on the hosting window's size — see `cellPixelHeight(canvasHeight:)`.
    case auto = 0
    case p100 = 100
    case p125 = 125
    case p150 = 150
    case p175 = 175
    case p200 = 200

    /// The raw percent as stored, `0` for `auto`.
    var storedValue: Int { rawValue }

    static func from(storedValue: Int) -> WinampModernTextScale {
        WinampModernTextScale(rawValue: storedValue) ?? .auto
    }

    var menuTitle: String {
        self == .auto ? "Auto" : "\(rawValue)%"
    }

    // MARK: - The auto rule

    /// Canvas height per pixel of cell height. 48 keeps anything under a 528px-tall window at the
    /// 11px default, which is where every small skin belongs: Defix's 355px playlist window clamps to
    /// 11, its 600px SUI comes out at 12.5, and Big Bento's 878px window reaches the cap.
    static let autoDivisor = 48.0

    /// How far `auto` may raise the cell.
    ///
    /// 18, not the window's own arithmetic: judged on screen, a host-drawn *list* has to stay quieter
    /// than the labels around it, and Big Bento at 878/48 lands exactly here. An **explicit** choice
    /// is deliberately not capped — a user who asks for 200% is not guessing.
    static let autoMaximumPixelHeight = 18.0

    /// The cell height this setting draws at, in skin pixels, inside a canvas of the given height.
    func cellPixelHeight(canvasHeight: CGFloat) -> Double {
        let base = WasabiTextMetrics.defaultPixelHeight
        switch self {
        case .auto:
            let height = canvasHeight.isFinite ? Double(canvasHeight) : 0
            return min(max(height / Self.autoDivisor, base), Self.autoMaximumPixelHeight)
        default:
            return base * Double(rawValue) / 100
        }
    }

    /// What the embedded library multiplies its own content scale by, so its rows, column headers and
    /// fonts land in the same proportion as the playlist's. The library keeps every internal
    /// proportion it has: this moves the single number they are all derived from.
    func contentScale(canvasHeight: CGFloat) -> CGFloat {
        CGFloat(cellPixelHeight(canvasHeight: canvasHeight) / WasabiTextMetrics.defaultPixelHeight)
    }

    /// What `auto` currently amounts to, as a percent, for the menu entry that shows it.
    static func resolvedPercent(canvasHeight: CGFloat) -> Int {
        let cell = WinampModernTextScale.auto.cellPixelHeight(canvasHeight: canvasHeight)
        return Int((cell / WasabiTextMetrics.defaultPixelHeight * 100).rounded())
    }
}
