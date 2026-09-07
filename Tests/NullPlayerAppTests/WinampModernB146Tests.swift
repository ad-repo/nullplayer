import XCTest
@testable import NullPlayer

/// B146 — a user colour override outranks whatever the skin (or its colour theme) resolved.
///
/// The report was winampmodern566's Media Library being unreadable under one of its themes, and the
/// engine was **right**: the skin ships 88 `<gammaset>`s, most of them re-tint the list roles, and
/// some of those tints simply pair badly. B48 and B122 only rescue *selected* and *current* rows, and
/// B113 records why a plain row on its own plate is deliberately left alone — so this is a whole
/// class of bad-but-authored colour nothing automatic will ever fix. These tests pin the escape
/// hatch: the override wins over the id chain, it is scoped to one skin **and one theme**, clearing
/// it genuinely unsets rather than storing a sentinel, the legibility guards step aside for a colour
/// the user chose on purpose, and a skin with no overrides resolves byte-identically to before.
final class WinampModernB146Tests: XCTestCase {

    private func makeConfiguration(_ name: String = #function) -> WinampModernConfiguration {
        let suite = "WinampModernB146.\(name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return WinampModernConfiguration(namespace: "TestSkin", defaults: defaults)
    }

    /// A stand-in for a skin that declares its whole list palette — the case where the chain answers
    /// and an override therefore has something to beat.
    private func declaredSkin(_ identifier: String) -> NSColor? {
        switch identifier {
        case "wasabi.list.text": return NSColor(deviceRed: 0.2, green: 0.2, blue: 0.1, alpha: 1)
        case "wasabi.list.background": return NSColor(deviceRed: 0.24, green: 0.22, blue: 0.1, alpha: 1)
        case "studio.list.item.selected": return NSColor(deviceRed: 0.9, green: 0.5, blue: 0, alpha: 1)
        case "wasabi.list.text.selected": return NSColor(deviceRed: 0.88, green: 0.52, blue: 0.05, alpha: 1)
        default: return nil
        }
    }

    private func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
        NSColor(deviceRed: red, green: green, blue: blue, alpha: 1)
    }

    // MARK: - The override beats the chain

    func testAnOverrideWinsBeforeTheIdChainIsWalked() {
        let chosen = rgb(1, 1, 1)
        let palette = WasabiPalette.make(overrides: [.listText: chosen], resolve: declaredSkin)
        XCTAssertEqual(palette.listText, chosen,
                       "an overridden role must not consult its identifiers at all — the whole point "
                       + "is that the chain resolved something the user rejected")
        XCTAssertTrue(palette.isOverridden(.listText))
        XCTAssertEqual(palette.contentBackground, declaredSkin("wasabi.list.background"),
                       "overriding one role must leave every other role resolving exactly as before")
        XCTAssertFalse(palette.isOverridden(.contentBackground))
    }

    /// The derived roles cascade from the *overridden* list text, the same way they cascade from a
    /// resolved one. A skin that names no current-row colour has always taken its list colour; that
    /// stays true when the list colour is the user's.
    func testDerivedRolesFollowAnOverriddenListText() {
        let chosen = rgb(0, 0.5, 1)
        let palette = WasabiPalette.make(overrides: [.listText: chosen], resolve: declaredSkin)
        XCTAssertEqual(palette.currentText, chosen,
                       "currentText is declared by no id in this fixture, so it derives from listText")
        XCTAssertFalse(palette.isOverridden(.currentText),
                       "deriving from an override is not the same as being one — the guards and the "
                       + "panel's Reset both key on who actually set the role")
    }

    func testAPaletteWithNoOverridesIsUnchanged() {
        let withoutArgument = WasabiPalette.make(resolve: declaredSkin)
        let withEmpty = WasabiPalette.make(overrides: [:], resolve: declaredSkin)
        XCTAssertEqual(withoutArgument, withEmpty)
        XCTAssertTrue(withoutArgument.overriddenRoles.isEmpty)
        XCTAssertEqual(withoutArgument.listText, declaredSkin("wasabi.list.text"),
                       "the no-regression assertion: an untouched skin resolves as it always did")
    }

    // MARK: - Storage: per skin, per theme, genuinely unset

    func testOverridesAreScopedToOneColourTheme() {
        let configuration = makeConfiguration()
        WinampModernSkinState.setPaletteOverride(rgb(1, 0, 0), role: .listText,
                                                 theme: "Blue", in: configuration)
        WinampModernSkinState.setPaletteOverride(rgb(0, 1, 0), role: .listText,
                                                 theme: "Amber", in: configuration)

        XCTAssertEqual(WinampModernSkinState.paletteOverride(role: .listText, theme: "Blue",
                                                             in: configuration),
                       rgb(1, 0, 0))
        XCTAssertEqual(WinampModernSkinState.paletteOverride(role: .listText, theme: "Amber",
                                                             in: configuration),
                       rgb(0, 1, 0),
                       "566's gammasets re-tint the same roles differently, so a fix for one theme is "
                       + "the wrong colour under the next — the two must not share a slot")
        XCTAssertNil(WinampModernSkinState.paletteOverride(role: .listText, theme: "Untouched",
                                                           in: configuration))
    }

    /// The reason `WinampModernConfiguration.removeValue` had to exist: every `#rrggbb` is a colour a
    /// user could legitimately have picked, so there is no value left over to mean "never set".
    func testClearingOneRoleGenuinelyUnsetsIt() {
        let configuration = makeConfiguration()
        WinampModernSkinState.setPaletteOverride(rgb(0, 0, 0), role: .contentBackground,
                                                 theme: "Default", in: configuration)
        XCTAssertNotNil(WinampModernSkinState.paletteOverride(role: .contentBackground,
                                                              theme: "Default", in: configuration),
                        "black is a legal choice and must round-trip, not read back as unset")

        WinampModernSkinState.setPaletteOverride(nil, role: .contentBackground,
                                                 theme: "Default", in: configuration)
        XCTAssertNil(WinampModernSkinState.paletteOverride(role: .contentBackground,
                                                           theme: "Default", in: configuration))

        let palette = WasabiPalette.make(
            overrides: WinampModernSkinState.paletteOverrides(theme: "Default", in: configuration),
            resolve: declaredSkin)
        XCTAssertEqual(palette.contentBackground, declaredSkin("wasabi.list.background"),
                       "a cleared role falls back to the skin's own chain")
    }

    func testResetThisSkinClearsEveryTheme() {
        let configuration = makeConfiguration()
        WinampModernSkinState.setPaletteOverride(rgb(1, 0, 0), role: .listText,
                                                 theme: "Blue", in: configuration)
        WinampModernSkinState.setPaletteOverride(rgb(0, 1, 0), role: .selectionText,
                                                 theme: "Amber", in: configuration)

        WinampModernSkinState.clearPaletteOverrides(in: configuration)

        XCTAssertTrue(WinampModernSkinState.paletteOverrides(theme: "Blue", in: configuration).isEmpty)
        XCTAssertTrue(WinampModernSkinState.paletteOverrides(theme: "Amber", in: configuration).isEmpty,
                      "the whole-skin reset is the only control that can reach a theme the user is "
                      + "not looking at, which is why it exists")
    }

    /// The section sweep must not reach a neighbouring skin, or a neighbouring section of its own.
    func testResetIsConfinedToOneSkinAndOneSection() {
        let suite = "WinampModernB146.confinement.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let mine = WinampModernConfiguration(namespace: "winampmodern566", defaults: defaults)
        let other = WinampModernConfiguration(namespace: "Big Bento Modern", defaults: defaults)

        WinampModernSkinState.setPaletteOverride(rgb(1, 0, 0), role: .listText,
                                                 theme: "Default", in: mine)
        WinampModernSkinState.setPaletteOverride(rgb(0, 0, 1), role: .listText,
                                                 theme: "Default", in: other)
        WinampModernSkinState.setTextScale(.p150, in: mine)

        WinampModernSkinState.clearPaletteOverrides(in: mine)

        XCTAssertNil(WinampModernSkinState.paletteOverride(role: .listText, theme: "Default", in: mine))
        XCTAssertEqual(WinampModernSkinState.paletteOverride(role: .listText, theme: "Default",
                                                             in: other),
                       rgb(0, 0, 1),
                       "one skin's reset must not touch another's colours")
        XCTAssertEqual(WinampModernSkinState.textScale(in: mine), .p150,
                       "nor another section of the same skin")
    }

    func testHexRoundTripAndStrictParsing() {
        let color = rgb(0.2, 0.4, 0.6)
        let hex = WinampModernSkinState.hexString(color)
        XCTAssertEqual(hex, "#336699")
        XCTAssertEqual(WinampModernSkinState.color(fromHex: hex), color)
        // A hand-edited or corrupted preference falls back to the skin, never to an invented colour.
        for bad in ["336699", "#33669", "#gg6699", "", "#3366990"] {
            XCTAssertNil(WinampModernSkinState.color(fromHex: bad), "\(bad) must not parse")
        }
    }

    // MARK: - The guards step aside

    /// Big Bento's measured pairing: `selectionText` 1.06:1 on `selectionBackground`, which B48
    /// replaces. A user who set that colour deliberately gets it, or the panel's preview would be
    /// showing a colour the app then refuses to draw.
    func testAnOverriddenSelectionTextSurvivesTheB48Guard() {
        let bar = rgb(0.9, 0.5, 0)
        let chosen = rgb(0.88, 0.52, 0.05)

        let resolved = WasabiPalette.make { identifier in
            switch identifier {
            case "studio.list.item.selected": return bar
            case "wasabi.list.text.selected": return chosen
            default: return nil
            }
        }
        XCTAssertNotEqual(WinampModernSurfaceStyle(palette: resolved).selectedText, chosen,
                          "fixture check: without an override this pairing is exactly what B48 replaces")

        let overridden = WasabiPalette.make(overrides: [.selectionText: chosen]) { identifier in
            identifier == "studio.list.item.selected" ? bar : nil
        }
        XCTAssertEqual(WinampModernSurfaceStyle(palette: overridden).selectedText, chosen,
                       "a colour the user chose is taken verbatim, even at 1.06:1")
    }

    func testIsUserChosenOnlyAnswersForRolesTheUserSet() {
        let chosen = rgb(1, 1, 1)
        let palette = WasabiPalette.make(overrides: [.selectionText: chosen], resolve: declaredSkin)
        XCTAssertTrue(palette.isUserChosen(chosen))
        XCTAssertFalse(palette.isUserChosen(palette.contentBackground),
                       "a role the skin resolved is still the skin's, and the guards still judge it")
        XCTAssertFalse(WasabiPalette.make(resolve: declaredSkin).isUserChosen(chosen))
    }
}
