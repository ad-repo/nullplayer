import AppKit
import XCTest
@testable import NullPlayer

/// Default visualization colours follow the skin in `.wal` / `.wmz`: the surface-style ramp, the
/// vis_classic profile matcher and its once-per-skin rule, the profile channel order, and the
/// hosted Waveform playhead.
final class HostedVisSkinColorsTests: XCTestCase {

    private func style(background: NSColor = .black, text: NSColor = .gray,
                       currentText: NSColor = .white, selectionBackground: NSColor = .darkGray,
                       selectionText: NSColor = .white) -> SkinnedSurfaceStyle {
        SkinnedSurfaceStyle(roles: SkinnedSurfaceRoles(
            background: background, text: text, currentText: currentText,
            selectionBackground: selectionBackground, selectionText: selectionText,
            treeText: text, treeSelection: selectionBackground))
    }

    private func assertSameColor(_ a: NSColor, _ b: NSColor, file: StaticString = #filePath, line: UInt = #line) {
        let x = a.usingColorSpace(.deviceRGB)!, y = b.usingColorSpace(.deviceRGB)!
        XCTAssertEqual(x.redComponent, y.redComponent, accuracy: 0.002, file: file, line: line)
        XCTAssertEqual(x.greenComponent, y.greenComponent, accuracy: 0.002, file: file, line: line)
        XCTAssertEqual(x.blueComponent, y.blueComponent, accuracy: 0.002, file: file, line: line)
    }

    private func bundledText(_ name: String) throws -> String {
        let dir = try XCTUnwrap(VisClassicBridge.bundledProfilesDirectory)
        return try String(contentsOf: dir.appendingPathComponent("\(name).ini"), encoding: .isoLatin1)
    }

    // MARK: - Ramp

    func testRampRunsFromDimTextToCurrentText() {
        let s = style(background: .black, text: .systemBlue, currentText: .systemRed)
        let ramp = s.visualizationRamp()
        XCTAssertEqual(ramp.count, 24)
        assertSameColor(ramp.first!, s.dimText)
        assertSameColor(ramp.last!, s.currentText)
    }

    // MARK: - Channel order

    /// Profiles are `R G B` as drawn — the original plugin's `RGB(b, g, r)` is undone by its DIB byte
    /// order. Read as `B G R`, "Default Red & Yellow" drew blue and "Flames" drew blue.
    func testProfileColoursAreReadAsRedGreenBlue() {
        let colours = VisClassicProfileMatcher.barColours(fromINI: "[BarColours]\n0=200 10 30\n")
        let first = colours?[0]
        XCTAssertEqual(first?.r, 200)
        XCTAssertEqual(first?.g, 10)
        XCTAssertEqual(first?.b, 30)
    }

    func testNamedBundledProfilesDrawTheirNamedHues() throws {
        let summaries = VisClassicProfileMatcher.bundledSummaries()
        func high(_ name: String) throws -> VisClassicProfileMatcher.Lab {
            try XCTUnwrap(summaries.first { $0.name == name }, "\(name) is bundled").high
        }
        // a* > 0 is red-ward, b* > 0 is yellow-ward, b* < 0 is blue-ward.
        XCTAssertGreaterThan(try high("Default Red & Yellow").b, 40, "red & yellow reads warm")
        XCTAssertGreaterThan(try high("Flames").b, 40, "flames read orange")
        XCTAssertGreaterThan(try high("Red").a, 60, "red reads red")
        XCTAssertLessThan(try high("Green").a, -40, "green reads green")
        // The Metal profiles were rewritten so they still draw as authored: copper stays warm.
        XCTAssertGreaterThan(try high("Metal Copper").b, 15, "copper reads warm, not blue")
    }

    func testChannelSwapRoundTripsAndPreservesLineEndings() {
        let text = "[Classic Analyzer]\r\nFalloff=12\r\n[BarColours]\r\n0=1 2 3\r\n[VolumeFunction]\r\n0=4 5 6\r\n"
        let swapped = VisClassicBridge.swappingColourChannels(inProfileText: text)
        XCTAssertTrue(swapped.contains("0=3 2 1\r\n"))
        XCTAssertTrue(swapped.contains("0=4 5 6\r\n"), "non-colour sections are untouched")
        XCTAssertEqual(VisClassicBridge.swappingColourChannels(inProfileText: swapped), text)
    }

    // MARK: - Matcher

    func testBundledCandidatesExcludeScratchAndBarlessProfiles() {
        let names = Set(VisClassicProfileMatcher.bundledSummaries().map(\.name))
        XCTAssertFalse(names.contains("Current Settings"))
        XCTAssertFalse(names.contains("LCD"), "LCD's bars are black; it draws only peaks")
        XCTAssertTrue(names.contains("Purple Neon"))
    }

    func testPrimaryHuesLandOnProfilesOfThatHue() {
        let summaries = VisClassicProfileMatcher.bundledSummaries()
        func match(_ low: NSColor, _ high: NSColor) -> String? {
            VisClassicProfileMatcher.bestMatch(low: low, high: high, among: summaries)?.name
        }
        XCTAssertEqual(match(NSColor(srgbRed: 0.35, green: 0.04, blue: 0.04, alpha: 1),
                             NSColor(srgbRed: 0.9, green: 0.16, blue: 0.16, alpha: 1)), "Red")
        XCTAssertEqual(match(NSColor(srgbRed: 0, green: 0.27, blue: 0, alpha: 1),
                             NSColor(srgbRed: 0.47, green: 1, blue: 0.31, alpha: 1)), "Green")
        let blue = match(NSColor(srgbRed: 0.08, green: 0.12, blue: 0.35, alpha: 1),
                         NSColor(srgbRed: 0.43, green: 0.67, blue: 1, alpha: 1))
        XCTAssertTrue(["Lightning", "Northern Lights"].contains(blue ?? ""), "blue matched \(blue ?? "nil")")
    }

    func testTiesBreakByName() {
        let lab = VisClassicProfileMatcher.Lab(l: 50, a: 0, b: 0)
        let summaries = [VisClassicProfileMatcher.Summary(name: "Zeta", low: lab, high: lab),
                         VisClassicProfileMatcher.Summary(name: "Alpha", low: lab, high: lab)]
        XCTAssertEqual(VisClassicProfileMatcher.bestMatch(low: .gray, high: .gray, among: summaries)?.name,
                       "Alpha")
    }

    func testShadingBandsAreDegenerate() {
        XCTAssertTrue(VisClassicProfileMatcher.isDegenerateTarget(low: .black, high: .black),
                      "Rika's black colorallbands are shading, not bar colour")
        XCTAssertTrue(VisClassicProfileMatcher.isDegenerateTarget(low: .white, high: .white),
                      "undeclared bands default to white")
        XCTAssertFalse(VisClassicProfileMatcher.isDegenerateTarget(low: .black, high: .systemGreen))
    }

    func testSkinDefaultAppliesOncePerSkin() throws {
        let suite = "HostedVisSkinColorsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let scope = VisClassicBridge.PreferenceScope.wmpEffects
        let red = (NSColor(srgbRed: 0.35, green: 0.04, blue: 0.04, alpha: 1),
                   NSColor(srgbRed: 0.9, green: 0.16, blue: 0.16, alpha: 1))

        let first = VisClassicProfileMatcher.applySkinDefault(
            for: scope, skinIdentity: "/skins/a.wmz", low: red.0, high: red.1, defaults: defaults)
        XCTAssertEqual(first?.name, "Red")
        XCTAssertEqual(defaults.string(forKey: scope.lastProfileNameKey), "Red")

        // The user picks something else; a relaunch on the same skin keeps it.
        defaults.set("Trippy", forKey: scope.lastProfileNameKey)
        XCTAssertNil(VisClassicProfileMatcher.applySkinDefault(
            for: scope, skinIdentity: "/skins/a.wmz", low: red.0, high: red.1, defaults: defaults))
        XCTAssertEqual(defaults.string(forKey: scope.lastProfileNameKey), "Trippy")

        // A reset (or a family switch) forgets the skin, so it re-picks.
        VisClassicProfileMatcher.forgetAppliedSkin(for: [scope], defaults: defaults)
        XCTAssertNotNil(VisClassicProfileMatcher.applySkinDefault(
            for: scope, skinIdentity: "/skins/a.wmz", low: red.0, high: red.1, defaults: defaults))
        XCTAssertEqual(defaults.string(forKey: scope.lastProfileNameKey), "Red")

        // Another skin re-picks too, and leaves the other scopes alone.
        XCTAssertNotNil(VisClassicProfileMatcher.applySkinDefault(
            for: scope, skinIdentity: "/skins/b.wmz", low: .black, high: .systemGreen, defaults: defaults))
        XCTAssertNil(defaults.string(forKey: VisClassicBridge.PreferenceScope.spectrumWindow.lastProfileNameKey))
    }

    // MARK: - Waveform playhead

    func testPlayheadKeepsSelectionTextWhenItStandsOut() {
        let blue = NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1)
        let s = style(background: .black, text: NSColor(white: 0.75, alpha: 1), currentText: .white,
                      selectionText: blue)
        assertSameColor(WaveformView.playheadColor(for: s), blue)
    }

    /// BLAKK: played and selection text are both white, which hid the playhead in the played part.
    func testPlayheadAvoidsThePlayedColour() {
        let s = style(background: .black, text: NSColor(white: 0.59, alpha: 1), currentText: .white,
                      selectionText: .white)
        let playhead = WaveformView.playheadColor(for: s)
        XCTAssertGreaterThan(SkinnedSurfaceStyle.contrastRatio(playhead, s.currentText), 3)
        XCTAssertGreaterThan(SkinnedSurfaceStyle.contrastRatio(playhead, s.text), 3)
    }
}
