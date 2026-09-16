import Foundation

/// **A `res://wmploc.dll/RT_STRING/#<id>` is a string out of Windows Media Player's own resource
/// library, and this is everything that can honestly be said about one on macOS.**
///
/// A skin writes these straight into what the user reads — `Compact`'s settings drawer sets
/// `tabTitle.value = "res://wmploc.dll/RT_STRING/#1827"` and its two switches label themselves
/// `#1846`/`#1851` — so with no resolution at all the URL itself was drawn: a 200 px string in a
/// box authored 110 wide for the word *On*, running out under the SRS logo beside it. Reported as
/// "the srs text is misaligned" (W189), and the misalignment was the string, not the layout.
///
/// **The table holds only ids whose text the corpus itself gives away, and every other id resolves
/// to the empty string.** `wmploc.dll` is not here and never will be, so the alternative to blank
/// is invention:
///
/// | id | what names it |
/// |---|---|
/// | `1800`/`1801` | `transport.js` sets them as the play button's `upToolTip` either side of the play/pause image swap, and `Compact`'s own markup authors `upToolTip="Play"` on that button |
/// | `2115`/`2116` | the `accName` set beside those two, one per state |
/// | `1827` | `ChangeSettingsTab` case 0, the pane holding the SRS controls, whose logo button authors `upToolTip="SRS WOW Effects"` |
/// | `1848` | case 1, the pane of ten gain sliders with "Turn equalizer off" and "Next preset" |
/// | `1849` | case 2, the pane of brightness/contrast/hue/saturation with "Reset video settings" |
/// | `1846`/`1851` | `UpdateEQOnOff`/`UpdateSRSOnOff` write them on the enabled and disabled branch of a label the markup authors as `value="On"` |
///
/// 133 uses of 50 distinct ids across 6 archives, so most of what a skin asks for is still blank.
/// **Blank is the deliberate answer and not a gap to be filled by recollection** — `theme.loadString`
/// has answered the empty string for these since Phase 0 and this agrees with it, so a format
/// string a skin builds a sentence out of stays empty rather than becoming a plausible-looking
/// invention. Add a row only when something in the corpus states the text.
enum WMPResourceStrings {
    /// The resolved text for a `res://…/RT_STRING/#<id>`, or nil when this is not one — a caller
    /// passes any value through and keeps what it had when the answer is nil.
    static func resolved(_ value: String?) -> String? {
        guard let value else { return nil }
        guard let id = identifier(in: value) else { return value }
        return table[id] ?? ""
    }

    /// The numeric id, for a value that is a `RT_STRING` resource URL and nothing else. `wmploc`
    /// and `wmploc.dll` are both spelled in the corpus — `transport.js` uses each within ten
    /// lines — so the library name is not matched, only the resource type and the id.
    static func identifier(in value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("res://"),
              let range = trimmed.range(of: "/RT_STRING/#", options: .caseInsensitive) else {
            return nil
        }
        return Int(trimmed[range.upperBound...])
    }

    private static let table: [Int: String] = [
        1800: "Play",
        1801: "Pause",
        1827: "SRS WOW Effects",
        1846: "On",
        1848: "Graphic Equalizer",
        1849: "Video Settings",
        1851: "Off",
        2115: "Play",
        2116: "Pause"
    ]
}
