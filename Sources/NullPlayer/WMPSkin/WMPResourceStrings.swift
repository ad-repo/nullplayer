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
/// **The table holds only ids whose text the markup itself gives away, and every other id resolves
/// to the empty string.** `wmploc.dll` is not here and never will be, so the alternative to blank
/// is invention. A row is earned one of two ways, and nothing else counts:
///
/// 1. **The corpus states the wording.** The same control, or its twin in another archive, authors
///    the literal string beside the resource URL. `Revert`'s close button carries
///    `upToolTip="res://-/RT_STRING/#1812"` and five other archives author `upToolTip="Close"` on
///    the button whose `onClick` is also `view.close()`.
/// 2. **The element's own binding names the action and nothing else fits.** A `<slider>` with
///    `min="0"`, `max="wmpprop:player.currentmedia.duration"` and
///    `value="wmpprop:player.controls.currentposition"` is the seek bar; its `toolTip` is `#1809`.
///
/// Where the corpus states wording it is copied **verbatim**, including its capitalisation — that
/// is why `3906`/`3907` read "Turn Equalizer On"/"Turn Equalizer Off" and `1814`-`1817` read
/// lowercase: each matches the authored tooltip nearest that control.
///
/// | id | what names it |
/// |---|---|
/// | `217` | `cmdPL`, `onClick="TogglePlaylist();"`; `netgen.wms` also paints it as the playlist pane's own `<TEXT>` title, exactly as it paints `#1848` over the equaliser pane |
/// | `1800`/`1801` | `transport.js` sets them as the play button's `upToolTip` either side of the play/pause image swap, and `Compact`'s own markup authors `upToolTip="Play"` on that button |
/// | `2115`/`2116` | the `accName` set beside those two, one per state |
/// | `1807`/`1808` | `cmdMute`'s up and down tooltips, with `down="wmpprop:player.settings.mute"` — up is the unmuted state, so up asks to mute. Four archives author `upToolTip="Mute"` on it |
/// | `2130` | the `accName` on that same `cmdMute` |
/// | `1809`/`2109` | the `toolTip` and `accName` of the seek slider described above |
/// | `1810`/`3905` | `ShowVolumeButton`, `onclick="SetVolumeVisible(!VolumeSlider.visible);"`, and its `accName` |
/// | `1811` | `onClick="view.minimize();"` — and the *same element* authors `accName="Minimize"` in plain text, so the corpus answers this one outright |
/// | `1812` | `onClick="view.close();"`, used for both `upToolTip` and `accName`; five archives author `upToolTip="Close"` |
/// | `1813`/`3904` | `onClick="view.returnToMediaCenter();"` — the skin-mode button that hands the user back to the full player |
/// | `1814`/`1815` | `cmdShuffle`, `sticky="true"`, `onclick="player.settings.setMode('shuffle', down);"` |
/// | `1816`/`1817` | `cmdRepeat`, same shape, `setMode('loop', down)` |
/// | `1827` | `ChangeSettingsTab` case 0, the pane holding the SRS controls, whose logo button authors `upToolTip="SRS WOW Effects"` |
/// | `1845` | the `toolTip`, `accName` and printed `<TEXT>` label of a slider bound `value="wmpprop:player.settings.balance"`, `min="-100" max="100"` |
/// | `1848` | case 1, the pane of ten gain sliders with "Turn equalizer off" and "Next preset" |
/// | `1849` | case 2, the pane of brightness/contrast/hue/saturation with "Reset video settings" |
/// | `1846`/`1851` | `UpdateEQOnOff`/`UpdateSRSOnOff` write them on the enabled and disabled branch of a label the markup authors as `value="On"` |
/// | `1998`/`1999` | `circle07.wms` sets them as `<theme author=… copyright=…>`, directly under a comment reading `©2000 Microsoft Corporation. All rights reserved.` |
/// | `2063` | the only argument `OnDisconnectTransport()` ever hands `ShowStatus()` |
/// | `2098` | `CheckForHDCD()` — set on the branch where `IS_HDCD` is true and cleared to `""` on the other, so it labels the HDCD indicator and nothing else |
/// | `3906`/`3907` | `cmdEQ` in `vwEQ`, `onClick="eq.bypass=!eq.bypass;"` with `down="jscript:!eq.bypass"`, so down is the *on* state |
/// | `3908` | the `accName` on that toggle |
/// | `3909` | `onClick="EQSelectMenu();"`; three archives author `upToolTip="Presets"` on the button that opens the preset menu |
///
/// **What is deliberately still blank, and why.** 136 uses of 51 distinct ids across 6 archives
/// (`grep -rioa 'RT_STRING/#[0-9]*'` over the decoded corpus, 2026-09-19), so roughly a third of
/// the ids now answer. The rest divide into three kinds, none of which a table of English can fix:
///
/// - **Format strings a skin builds a sentence from** — `#2099` (buffering percentage), `#2086`
///   (DVD chapter and title), `#2066` (bitrate), `#2077`/`#2078` (DRM signature). Each is fed to
///   the skin's own `sprintf`, so a wrong guess produces a wrong *sentence*, not a wrong word.
/// - **Wording with no anchor** — the reception-quality tooltips `#2079`-`#2081`, `#2092`, chosen
///   off `nReceptionQuality` thresholds that say what is *measured*, never what is printed; the
///   quick-access menu's `#1273`/`#2150`; and `#2097`, the second HDCD mode beside `#2098`.
/// - **Not user-visible text at all** — `#1888` is read as a `fontFace` and `#1910` as a
///   `scrollingDirection`; `#2108`/`#2114` are `accKeyboardShortcut` key names. These are
///   localisation plumbing, and answering them with a label would be worse than answering blank.
///   **Blank is still not the same as an answer, and W236 is where the difference was paid.**
///   A face this table cannot resolve does not fall back to the engine's `"Arial"` — CoreText
///   substitutes Helvetica for any name it cannot match — so `WMPTextMetrics.face(_:)` reads an
///   unresolved `res://` face as an *unstated* one. The resolution still runs first: the moment a
///   family is earned for `#1888` it is used rather than skipped.
///
/// **Some rows here are correct and still invisible, which is not the same as blank.** The scene
/// builder reads `toolTip`/`upToolTip`/`downToolTip`, `value` and — since W236, through
/// `WMPTextMetrics.face(_:)` — `fontFace`/`fontType`, and the object model answers
/// `theme.loadString`; it does not read `accName`, `accKeyboardShortcut`,
/// `scrollingDirection`, or `<theme author=… copyright=…>`. So of the 133 literal uses, 90 sit in
/// an attribute that reaches the screen today and **58 of those now resolve, against 13 before**
/// — while `2109`, `2130`, `3904`, `3905`, `3908` (`accName` only) and `1998`/`1999` (theme
/// metadata) are right but show nothing until those attributes are wired. They are kept because
/// the evidence for them is the same evidence as for the rows beside them, not weaker.
///
/// **Blank stays the deliberate answer for those** — `theme.loadString` has returned the empty
/// string since Phase 0 and this agrees with it. Add a row only when the markup names the text.
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
        // ── Transport and window chrome ──────────────────────────────────────
        217: "Playlist",
        1800: "Play",
        1801: "Pause",
        1807: "Mute",
        1808: "Unmute",
        1809: "Seek",
        1810: "Volume",
        1811: "Minimize",
        1812: "Close",
        1813: "Return to Full Mode",
        1814: "Turn shuffle on",
        1815: "Turn shuffle off",
        1816: "Turn repeat on",
        1817: "Turn repeat off",
        1827: "SRS WOW Effects",
        1845: "Balance",
        1846: "On",
        1848: "Graphic Equalizer",
        1849: "Video Settings",
        1851: "Off",

        // ── Theme metadata ───────────────────────────────────────────────────
        1998: "Microsoft Corporation",
        1999: "\u{00A9} 2000 Microsoft Corporation. All rights reserved.",

        // ── Player status ────────────────────────────────────────────────────
        2063: "Disconnected",
        2098: "HDCD",

        // ── Accessible names, set beside the tooltips above ──────────────────
        2109: "Seek",
        2115: "Play",
        2116: "Pause",
        2130: "Mute",
        3904: "Return to Full Mode",
        3905: "Volume",
        3906: "Turn Equalizer On",
        3907: "Turn Equalizer Off",
        3908: "Equalizer",
        3909: "Presets"
    ]
}

