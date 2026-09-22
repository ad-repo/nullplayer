import AppKit
import Foundation
import XCTest
@testable import NullPlayer

/// W39. The row ranked `eq.speakerSize` at 18 skins and called the class an `inert()` candidate,
/// and by the time it came up both halves of that were false: `speakerSize`, `enhancedAudio`,
/// `wowLevel`, `truBassLevel` and `currentSpeakerName` were all implemented by the WOW/TruBass
/// work, and the largest member left is a feature this player has.
///
/// **Re-measured 2026-09-22 over 184 archives**, decoding each `.wms`/`.js` the way
/// `WMPTextDecoder` does and matching `\beq\s*\.\s*(member)` — the script-text scan
/// `harness.md` § *Grepping the corpus's script text* describes. The census cannot answer this: it
/// matches a *tag*, never a member read.
///
/// | Member | uses | archives | before | now |
/// |---|---:|---:|---|---|
/// | `crossFade` | 123 | 38 | **unrecognised** | Sweet Fades |
/// | `enableSplineTension` | 68 | 51 | **unrecognised** | inert, stored |
/// | `splineTension` | 56 | 48 | **unrecognised** | inert, stored |
/// | `crossFadeWindow` | 40 | 35 | **unrecognised** | Sweet Fades duration |
/// | `normalization` | 1 | 1 | **unrecognised** | volume levelling |
///
/// **Crossfade is not an `inert()` candidate, because WMP's crossfade is this player's Sweet
/// Fades** — the same feature under another name. The corpus authors it as one sticky button whose
/// handler is `eq.crossFade = !eq.crossFade;eq.crossFadeWindow=7000` with
/// `down="wmpprop:eq.crossFade"`, so both resolution paths have to answer or the button fades
/// tracks and never lights. Six of the 38 spellings put `checkSoundPref('click.wav')` *in front*
/// of the write, so the unrecognised member cost the click sound too.
///
/// Spline tension is the honest inert half: it is whether WMP's ten sliders drag each other, and
/// this equaliser's move independently. `false`/`0` is what this player does, and it is the pair
/// `inertEqualizerSettingsProperties` already answers on the `<EQUALIZERSETTINGS>` element.
@MainActor
final class WMPEqualizerMemberTests: XCTestCase {

    /// **The assertion that matters is not the value — it is that the statement after the read
    /// still runs.** `ALXMorph`, `Batman Begins`, `Constantine`, `Disney_Mix_Central`,
    /// `Dreamcatcher` and `KungFuChaos` all write the crossfade pair from one handler, and
    /// `Alienware Invader` follows it with a second statement; an unrecognised member aborted the
    /// lot.
    func testCrossfadeMembersDoNotAbortTheHandlerAndReachTheHost() async throws {
        let output = try await transact("""
        eq.crossFade = !eq.crossFade;
        eq.crossFadeWindow = 7000;
        eq.normalization = true;
        theme.savePreference('after','yes');
        """)
        XCTAssertEqual(output.hostCommands.map(\.action),
                       ["setCrossFade", "setCrossFadeWindow", "setNormalization"])
        XCTAssertEqual(output.hostCommands[1].value, .number(7_000),
                       "the skin states milliseconds; the conversion belongs at the host boundary")
        XCTAssertFalse(output.calls.contains { !$0.recognised },
                       "an unrecognised eq member aborts the whole handler")
    }

    /// **A window of zero is a cut and one of an hour is a stuck fade**, so the bound is in the
    /// object model rather than left to the engine. Non-finite is ignored the way every other
    /// numeric `eq` write ignores it, which is what keeps the authored cycle idiom working.
    func testCrossfadeWindowIsBoundedAndNonFiniteIsIgnored() {
        let model = WMPObjectModel()
        _ = model.set("eq", "crossFadeWindow", .number(7_000))
        XCTAssertEqual(model.snapshot.equalizer.crossFadeWindow, 7_000)
        _ = model.set("eq", "crossFadeWindow", .number(3_600_000))
        XCTAssertEqual(model.snapshot.equalizer.crossFadeWindow, 20_000)
        _ = model.set("eq", "crossFadeWindow", .number(-500))
        XCTAssertEqual(model.snapshot.equalizer.crossFadeWindow, 0)
        _ = model.set("eq", "crossFadeWindow", .number(.nan))
        XCTAssertEqual(model.snapshot.equalizer.crossFadeWindow, 0,
                       "a non-finite write keeps the committed window")
    }

    /// **Stored, not constant, because the corpus reads it back to decide which button is lit.**
    /// `Back to the Future Trilogy`'s `checkSplineTension()` clears all three of its grouping
    /// buttons and then tests `eq.enableSplineTension && eq.splineTension==2` to light one; with a
    /// constant the same button would light whichever the user pressed, and with the member
    /// unrecognised the handler aborted *after* the three clears, so none of them lit at all.
    func testSplineTensionIsInertAndRoundTripsWithinTheSession() async throws {
        let output = try await transact("""
        var first = eq.enableSplineTension;
        eq.enableSplineTension = true; eq.splineTension = 2;
        var lit = (eq.enableSplineTension && eq.splineTension == 2) ? 'two' : 'none';
        theme.savePreference('first', first ? 'on' : 'off');
        theme.savePreference('lit', lit);
        """)
        XCTAssertEqual(output.preferenceWrites["first"], "off",
                       "independent sliders is what this player does, so off is the honest default")
        XCTAssertEqual(output.preferenceWrites["lit"], "two",
                       "a constant would light the same grouping button whichever was pressed")
        XCTAssertTrue(output.hostCommands.isEmpty, "spline tension applies nothing")
        XCTAssertTrue(output.calls.contains {
            $0.path == "eq.enablesplinetension" && $0.resolution == .inert
        }, "answered, applied nothing, and counted as inert")
    }

    /// **The read half of the corpus idiom is a separate resolution of the same path.** The button
    /// carries `down="wmpprop:eq.crossFade"` on the node whose `onClick` writes it, and that
    /// resolves through `WMPObservablePropertyRegistry`, not the object model — a binding the
    /// registry cannot answer is a button that toggles the fade and never lights.
    func testBoundPathsAndRegistryResolveTheCrossfadeMembers() async throws {
        XCTAssertEqual(WMPTransportAction.boundAction(for: "eq.crossFade"), .setCrossFade)
        XCTAssertEqual(WMPTransportAction.boundAction(for: "eq.crossFadeWindow"), .setCrossFadeWindow)
        XCTAssertEqual(WMPTransportAction.boundAction(for: "eq.normalization"), .setNormalization)

        // `Plus! Professional`'s own button, and the shape all 35 of them share.
        let skin = try await WMPSkinLoader().load(from: try WMPSkinTestSupport.makeArchive([
            WMPTestArchiveEntry("skin.wms", data: Data("""
            <THEME><VIEW id="main" width="200" height="60">
                <BUTTON id="xfade" left="5" top="4" width="28" height="12" sticky="true"
                        onClick="eq.crossFade=!eq.crossFade" down="wmpprop:eq.crossFade"/>
            </VIEW></THEME>
            """.utf8))
        ]))
        let address = WMPScenePropertyAddress(
            stableID: try XCTUnwrap(skin.graph.allNodes.first { $0.xmlID == "xfade" }?.stableID),
            property: "down")

        var registry = WMPObservablePropertyRegistry(graph: skin.graph)
        var snapshot = WMPHostSnapshot()
        snapshot.equalizer.crossFade = true
        XCTAssertEqual(registry.changes(for: snapshot).first { $0.address == address }?.value,
                       .bool(true), "the button has to light when crossfade is on")
        snapshot.equalizer.crossFade = false
        XCTAssertEqual(registry.changes(for: snapshot).first { $0.address == address }?.value,
                       .bool(false), "and settle again rather than stick where it opened")
    }

    /// **The skin states milliseconds and `sweetFadeDuration` is seconds**, so the one place that
    /// conversion may live is here. `setCrossFade` and `setNormalization` carry **no `.wmp` gate**,
    /// unlike the WOW group beside them: WOW is WMP-only DSP that must never activate in another
    /// family, while crossfade is the same app-wide Sweet Fades every family drives from its own
    /// menu. `.setEQEnabled` is the existing precedent on that switch.
    func testHostAppliesCrossfadeAsSweetFadesInSecondsAndReadsItBack() {
        let engine = AudioEngine()
        let host = WMPAudioEngineHost(audioEngine: engine)
        let priorEnabled = engine.sweetFadeEnabled
        let priorDuration = engine.sweetFadeDuration
        let priorNormalization = engine.volumeNormalizationEnabled
        defer {
            engine.sweetFadeEnabled = priorEnabled
            engine.sweetFadeDuration = priorDuration
            engine.volumeNormalizationEnabled = priorNormalization
        }

        host.perform(.setCrossFade, value: .number(1))
        host.perform(.setCrossFadeWindow, value: .number(7_000))
        host.perform(.setNormalization, value: .number(1))
        XCTAssertTrue(engine.sweetFadeEnabled)
        XCTAssertEqual(engine.sweetFadeDuration, 7, accuracy: 0.0001)
        XCTAssertTrue(engine.volumeNormalizationEnabled)
        XCTAssertTrue(host.snapshot.equalizer.crossFade)
        XCTAssertEqual(host.snapshot.equalizer.crossFadeWindow, 7_000, accuracy: 0.0001,
                       "the snapshot answers the skin in the units the skin wrote")
        XCTAssertTrue(host.snapshot.equalizer.normalization)

        host.perform(.setCrossFadeWindow, value: .number(.nan))
        XCTAssertEqual(engine.sweetFadeDuration, 7, accuracy: 0.0001)
        host.perform(.setCrossFadeWindow, value: .number(-1))
        XCTAssertEqual(engine.sweetFadeDuration, 7, accuracy: 0.0001)
        host.perform(.setCrossFade, value: .number(0))
        XCTAssertFalse(engine.sweetFadeEnabled)
    }

    /// **A member the engine answers must never stay in the demand tally** — the `alphaBlendTo`
    /// trap, which had a working member ranked as the largest open row in the backlog. The list's
    /// own doc comment claims it is derived from the object model; it is restated, so this is the
    /// check that comment implies.
    func testEveryEqualizerMemberTheCorpusReadsIsCountedAsImplemented() {
        for member in ["crossFade", "crossFadeWindow", "normalization",
                       "enableSplineTension", "splineTension",
                       "enhancedAudio", "wowLevel", "truBassLevel", "speakerSize",
                       "currentSpeakerName", "bypass"] {
            XCTAssertTrue(WMPJScriptCompatibility.supports(object: "eq", member: member),
                          "\(member) is answered and the census still counts it as unknown")
        }
        // The surface stays closed. `eq.gainLevels(band) = value` is `Compact`'s and
        // `Charlies_Angels_Full_Throttle`'s, and it is not valid JScript — assignment to the result
        // of a call — so answering it would be answering a typo. The rest are real WMP SDK members
        // no archive reads; an unrecognised resolution is what lets the census rank one that does.
        for absent in ["gainLevels", "enhancedAudioType", "presetTitleCount", "speakerType"] {
            XCTAssertFalse(WMPJScriptCompatibility.supports(object: "eq", member: absent),
                           "\(absent) is unanswered, so the census must keep counting it")
        }
    }

    // MARK: - Support

    private struct TransactionResult {
        let hostCommands: [WMPJScriptHostCommand]
        let calls: [WMPJScriptCall]
        let preferenceWrites: [String: String]
    }

    private func transact(_ handler: String) async throws -> TransactionResult {
        let archive = try WMPSkinTestSupport.makeArchive([WMPTestArchiveEntry("skin.wms", data: Data("""
        <THEME><VIEW id="main" width="100" height="100">
          <EQUALIZERSETTINGS id="eq"/>
          <BUTTON id="go" width="10" height="10"/>
        </VIEW></THEME>
        """.utf8))])
        let skin = try await WMPSkinLoader().load(from: archive)
        let suite = "WMPEqualizerMemberTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WMPPreferenceStore(skinData: Data(), defaults: defaults)
        let runtime = WMPScriptRuntime(preferences: store)
        let output = await runtime.transact(
            skin: skin, viewID: "main", size: .init(width: 100, height: 100),
            snapshot: WMPHostSnapshot(),
            event: .init(name: "click", targetID: "go", handlers: [handler]))
        var writes: [String: String] = [:]
        for (name, value) in defaults.dictionaryRepresentation()
        where name.hasPrefix("wmp.preferences.") {
            if let stored = value as? [String: String] { writes.merge(stored) { _, new in new } }
        }
        return TransactionResult(hostCommands: output.hostCommands, calls: output.calls,
                                 preferenceWrites: writes)
    }
}
