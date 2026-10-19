import XCTest
@testable import NullPlayer

final class SoniqueSkinSettingsTests: XCTestCase {
    private func settings(_ text: String) -> SoniqueSkinSettings {
        SoniqueSkinSettings(SoniqueSkinINI(text))
    }

    func testAnOmittedKeyIsTheDefault() {
        let s = settings("")
        XCTAssertEqual(s.colour(.systemColor2), 0xFFFF00)
        XCTAssertEqual(s.int("misc values", "MISC_VOLUME_KNOB_width"), 18)
        XCTAssertEqual(s.int("skin", "version"), 100)
        XCTAssertEqual(s.findings, [])
    }

    /// A default written as a name follows the skin's value of that name.
    func testADefaultNamingAKeyFollowsTheSkin() {
        let s = settings("[misc locations]\nPREV_y=7\nBIGUP_y=10\n[sonique colors]\nSystemColor_2=0x123456\n")
        XCTAssertEqual(s.int("misc locations", "NAV_PREV_y"), 7)
        XCTAssertEqual(s.int("misc locations", "BIGON_DOWN_y"), 45)
        XCTAssertEqual(s.colour(.logoColor), 0x123456)
    }

    /// corrosion's `NAV_CYANON_x=CYANON_x` draws from CYANON's position in the oracle, and Barrels
    /// writes `BIGON_DOWN_y=BIGUP_y + 51`.
    func testASkinValueMayNameAnotherKey() {
        let s = settings("[misc locations]\nCYANON_x=26\nNAV_CYANON_x=CYANON_x \nBIGON_DOWN_y=BIGUP_y + 51\nNAV_PREV_y = PREV_y-4\n")
        XCTAssertEqual(s.int("misc locations", "NAV_CYANON_x"), 26)
        XCTAssertEqual(s.int("misc locations", "BIGON_DOWN_y"), 51)
        XCTAssertEqual(s.int("misc locations", "NAV_PREV_y"), 36)
        XCTAssertEqual(s.findings, [])
    }

    /// ChromeTech's `MISC_DRAWER_POS_x=33.5` puts the oracle's drawer at 33, not 34 or the default.
    func testANumberReadsAsItsLeadingInteger() {
        let s = settings("[misc values]\nMISC_DRAWER_POS_x=33.5\n[misc locations]\nNAV_CYANON_x=69 (Repeat Green)\nREDON_y=0v\nPREV_x=-3\n")
        XCTAssertEqual(s.int("misc values", "MISC_DRAWER_POS_x"), 33)
        XCTAssertEqual(s.int("misc locations", "NAV_CYANON_x"), 69)
        XCTAssertEqual(s.int("misc locations", "REDON_y"), 0)
        XCTAssertEqual(s.int("misc locations", "PREV_x"), -3)
        XCTAssertEqual(s.findings, [])
    }

    func testAColourDropsItsAlphaAndTakesSixDigits() {
        let s = settings("[sonique colors]\nSystemColor_1=0x00FFFFAA\nSystemColor_2=0xc0c0c0\n")
        XCTAssertEqual(s.colour(.systemColor1), 0xFFFFAA)
        XCTAssertEqual(s.colour(.systemColor2), 0xC0C0C0)
    }

    func testAnUnreadableValueIsSQ0011AndTheDefault() {
        let s = settings("[sonique colors]\nSystemColor_1=verde\nSystemColor_2=&H00FFFFFF&\n[misc locations]\nPREV_x=NEXT_x * 2\n")
        XCTAssertEqual(s.colour(.systemColor1), 0x00FFFF)
        XCTAssertEqual(s.colour(.systemColor2), 0xFFFF00)
        XCTAssertEqual(s.int("misc locations", "PREV_x"), 0)
        XCTAssertEqual(s.findings.map(\.code), [.iniValueMalformed, .iniValueMalformed, .iniValueMalformed])
    }

    func testAnEmptyValueIsUnwritten() {
        let s = settings("[misc locations]\nDRAWER_POS_x=\nDRAWER_POS_y=\n[misc values]\nMISC_DRAWER_POS_x=5\nMISC_DRAWER_POS_y=6\n")
        XCTAssertTrue(s.drawerPosition == (5, 6))
        XCTAssertEqual(s.int("misc locations", "DRAWER_POS_x"), 29)
        XCTAssertEqual(s.findings, [])
    }

    func testACycleIsOneSQ0011() {
        let s = settings("[misc locations]\nPREV_x=NEXT_x\nNEXT_x=PREV_x\n")
        XCTAssertEqual(s.findings.map(\.code), [.iniValueMalformed])
        XCTAssertEqual(s.int("misc locations", "PREV_x"), s.int("misc locations", "NEXT_x"))
    }

    /// The oracle draws BlueEyes's drawer at `DRAWER_POS` though it is version 105 and writes
    /// `MISC_DRAWER_POS` too; Trigun, writing only `MISC_DRAWER_POS`, gets that.
    func testDrawerPositionPrefersDrawerPos() {
        let both = settings("[skin]\nversion=105\n[misc locations]\nDRAWER_POS_x=76\nDRAWER_POS_y=247\n[misc values]\nMISC_DRAWER_POS_x=0\nMISC_DRAWER_POS_y=168\n")
        XCTAssertTrue(both.drawerPosition == (76, 247))
        let misc = settings("[misc values]\nMISC_DRAWER_POS_x=104\nMISC_DRAWER_POS_y=71\n")
        XCTAssertTrue(misc.drawerPosition == (104, 71))
        XCTAssertTrue(settings("").drawerPosition == (29, 229))
    }

    /// Barrels and winson99 write `MISC_DRAWER_POS` 0,0 and the oracle draws their drawers at the
    /// default; QTOSX's 0,230 and blou_aple's 499,0 are honoured.
    func testDrawerPositionZeroZeroIsUnwritten() {
        XCTAssertTrue(settings("[misc values]\nMISC_DRAWER_POS_x=0\nMISC_DRAWER_POS_y=0\n").drawerPosition == (29, 229))
        XCTAssertTrue(settings("[misc values]\nMISC_DRAWER_POS_x=0\nMISC_DRAWER_POS_y=230\n").drawerPosition == (0, 230))
    }

    func testAnOmittedEntryAndADefaultModeComeFromTheDefaultSkin() throws {
        var entries = SoniqueSkinFixture.complete
        entries[0] = ("/skin.ini", Data("[skin]\r\nTouchMidMode = 0\r\n".utf8))
        let skin = try SoniqueSkinLoader.load(data: SoniqueSkinFixture.sgf(entries))
        XCTAssertNotNil(skin.region("/rgn/nav/play"))
        XCTAssertEqual(skin.region("/rgn/nav/drawer"), SoniqueSkin.defaultSkin.regions["/rgn/nav/drawer"])
        XCTAssertNotNil(skin.region("/rgn/nav/drawer"), "the bundled default skin supplies the drawer")
        XCTAssertEqual(skin.source(for: .navigator).regions.count, skin.regions.count)
        XCTAssertEqual(skin.source(for: .mid).regions, SoniqueSkin.defaultSkin.regions)
    }
}
