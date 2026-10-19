import CoreGraphics
import Foundation

/// The navigator's menu screen: Sonique's layout and colours (`format.md` § *The navigator's menu
/// screen*), measured from the oracle's k2 capture in skin pixels from the display's top-left, with
/// NullPlayer's items in Sonique's places (decision record § *Control mapping*). Lycos's logo, icons
/// and quick links are not copied: NullPlayer's wordmark takes the logo's place and colours, and the
/// icons are NullPlayer's own marks in Sonique's boxes.
enum SoniqueSkinMenu {
    enum Item: Hashable, CaseIterable {
        case visualMode, playlist, library, setup, audio
        case spectrum, peppyMeter, art, waveform
        case skins, history, about
    }

    struct Entry {
        let item: Item
        /// The boxed icon beside a left-column item; nil for a link.
        let icon: SoniqueSkinRegion.Rect?
        let lines: [SoniqueSkinText]
        /// What a press on the entry hits.
        let hit: SoniqueSkinRegion.Rect
    }

    /// The right column's headings, where Sonique's read *quick links* and *my sonique*.
    /// "my nullplayer" is three letters longer than Sonique's "my sonique": spaced as "windows" it
    /// runs past the display's edge, so it is spaced a quarter pixel, and the column sits 8 px left of
    /// Sonique's x 214 (it still ran to 302, past 365 of 516 skins' displays at its height; at 294,
    /// 20 are left, displays too narrow for any shift that clears the left column).
    static let columnX = 206
    static let headings = [SoniqueSkinText(string: "windows", x: columnX, baseline: 38, size: 11, colour: .systemColor2, spacing: 1),
                           SoniqueSkinText(string: "my nullplayer", x: columnX, baseline: 110, size: 11, colour: .systemColor2,
                                spacing: 0.25)]

    static let entries: [Entry] = {
        func large(_ item: Item, _ title: String, _ subtitle: String, top: Int) -> Entry {
            Entry(item: item, icon: .init(left: 45, top: top, right: 66, bottom: top + 21),
                  lines: [SoniqueSkinText(string: title, x: 75, baseline: top + 11, size: 14, colour: .systemColor3),
                          SoniqueSkinText(string: subtitle, x: 76, baseline: top + 20, size: 8, colour: .systemColor3)],
                  hit: .init(left: 45, top: top, right: 205, bottom: top + 21))
        }
        func small(_ item: Item, _ first: String, _ second: String, icon x: Int, right: Int) -> Entry {
            Entry(item: item, icon: .init(left: x, top: 169, right: x + 19, bottom: 188),
                  lines: [SoniqueSkinText(string: first, x: x + 25, baseline: 177, size: 11, colour: .systemColor3),
                          SoniqueSkinText(string: second, x: x + 25, baseline: 186, size: 11, colour: .systemColor3)],
                  hit: .init(left: x, top: 168, right: right, bottom: 189))
        }
        func links(_ items: [(Item, String)], first baseline: Int) -> [Entry] {
            items.enumerated().map { i, link in
                let y = baseline + i * 11
                return Entry(item: link.0, icon: nil,
                             lines: [SoniqueSkinText(string: link.1, x: columnX + 4, baseline: y, size: 9, colour: .systemColor3, spacing: 1)],
                             hit: .init(left: columnX, top: y - 9, right: 300, bottom: y + 2))
            }
        }
        return [large(.visualMode, "visual mode", "visuals & spectrum", top: 74),
                large(.playlist, "playlist editor", "create & edit playlists", top: 104),
                large(.library, "find music", "library browser", top: 134),
                small(.setup, "setup", "options", icon: 21, right: 110),
                small(.audio, "audio", "controls", icon: 117, right: 205)]
            + links([(.spectrum, "spectrum"), (.peppyMeter, "peppymeter"), (.art, "art"), (.waveform, "waveform")], first: 51)
            + links([(.skins, "skins"), (.history, "play history"), (.about, "about")], first: 124)
    }()

    /// NullPlayer's wordmark where Sonique's *LYCOS sonique* sits (x 27–190, y 22–63 on k2): a small
    /// label where *LYCOS* is, a heavy word outlined in `LogoColor`, widened and leaning as Sonique's
    /// is (its x-height, 17 px on baseline 48, and its letters' 23 px pitch), over its swoosh in
    /// `LogoRingColor`.
    enum Logo {
        /// Raised clear of the word's *l*, which *LYCOS* never had to be: *sonique* starts low.
        static let label = SoniqueSkinText(string: "null", x: 27, baseline: 25, size: 12, colour: .logoColor)
        static let word = SoniqueSkinText(string: "player", x: 27, baseline: 48, size: 31, colour: .logoColor,
                                          font: "Arial-Black", matrix: CGAffineTransform(a: 1.35, b: 0, c: 0.21, d: 1, tx: 0, ty: 0))
        /// Sonique's swoosh, fitted to k2's menu capture (2026-10-19): `swoosh` less `swooshHole`, both
        /// leaning 13° clockwise, the hole raised so the ring is a line across the top that swells to
        /// 4 px under the word. The hole stays 1.2 px inside at the top and 2 px at the ends: Sonique's
        /// thinner ends broke up when drawn.
        static let swoosh = Ellipse(cx: 104.9, cy: 42.5, rx: 52.9, ry: 17.6, degrees: 13.3)
        static let swooshHole = Ellipse(cx: 105.1, cy: 41.1, rx: 50.8, ry: 14.9, degrees: 13.3)

        /// An ellipse about (`cx`, `cy`), turned `degrees` clockwise (skin pixels run top-down).
        struct Ellipse {
            let cx, cy, rx, ry, degrees: CGFloat

            func path(dx: Int, dy: Int) -> CGPath {
                var turn = CGAffineTransform(translationX: cx + CGFloat(dx), y: cy + CGFloat(dy))
                    .rotated(by: degrees * .pi / 180)
                return CGPath(ellipseIn: CGRect(x: -rx, y: -ry, width: 2 * rx, height: 2 * ry), transform: &turn)
            }
        }
    }

    /// NullPlayer's version where Sonique's own sits, bottom centre above the status line.
    static func version(_ string: String) -> SoniqueSkinText {
        SoniqueSkinText(string: string, x: 191, baseline: 209, size: 10, colour: .systemColor2)
    }
}
