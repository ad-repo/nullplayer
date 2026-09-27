import Foundation
import XCTest
@testable import NullPlayer

/// The effects slot's settings are part of the skin, not of the session.
///
/// Picking MilkDrop and a preset in one `.wmz`, then switching to another, must leave the second
/// skin on the app's defaults rather than on the first skin's choices — and coming back must
/// restore what was left. Both halves are what makes the scoping *per skin* rather than merely
/// last-write-wins, and the "no record" half is the one that regresses silently.
final class WMPVisualizationSettingsTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "wmp.vis.settings.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private var store: WMPVisualizationSettingsStore {
        WMPVisualizationSettingsStore(defaults: defaults)
    }

    private var profileKey: String {
        VisClassicBridge.PreferenceScope.wmpEffects.lastProfileNameKey
    }

    private var cavaBarCountKey: String {
        // The scope's own key list is what the store carries, so the test asks for it the same way.
        CavaSettings.preferenceKeys(for: .wmpEffects)[1]
    }

    func testRestoreReturnsTheSelectionAndScopedKeysTheSkinWasLeftOn() {
        defaults.set("Retro", forKey: profileKey)
        defaults.set(48, forKey: cavaBarCountKey)
        XCTAssertTrue(store.capture(skin: "Cerulean", effect: "projectm", preset: 7))

        defaults.set("Other", forKey: profileKey)
        defaults.set(12, forKey: cavaBarCountKey)

        let selection = store.restore(skin: "Cerulean")
        XCTAssertEqual(selection.effect, "projectm")
        XCTAssertEqual(selection.preset, 7)
        XCTAssertEqual(defaults.string(forKey: profileKey), "Retro")
        XCTAssertEqual(defaults.integer(forKey: cavaBarCountKey), 48)
    }

    /// A skin with no record starts from the app's defaults; it does not inherit what the previous
    /// skin was showing.
    func testRestoringASkinWithNoRecordClearsTheScopedKeys() {
        defaults.set("Retro", forKey: profileKey)
        defaults.set(48, forKey: cavaBarCountKey)

        let selection = store.restore(skin: "Asimov Radio")
        XCTAssertNil(selection.effect)
        XCTAssertEqual(selection.preset, 0)
        XCTAssertNil(defaults.object(forKey: profileKey))
        XCTAssertNil(defaults.object(forKey: cavaBarCountKey))
    }

    func testTwoSkinsKeepSeparateRecords() {
        defaults.set(48, forKey: cavaBarCountKey)
        store.capture(skin: "Cerulean", effect: "cava", preset: 0)
        defaults.set(12, forKey: cavaBarCountKey)
        store.capture(skin: "Asimov Radio", effect: "spikes", preset: 0)

        XCTAssertEqual(store.restore(skin: "Cerulean").effect, "cava")
        XCTAssertEqual(defaults.integer(forKey: cavaBarCountKey), 48)
        XCTAssertEqual(store.restore(skin: "Asimov Radio").effect, "spikes")
        XCTAssertEqual(defaults.integer(forKey: cavaBarCountKey), 12)
    }

    /// The capture observer is driven by `UserDefaults.didChangeNotification`, so an unconditional
    /// write would feed itself. An unchanged record must not write at all.
    func testCaptureOfAnUnchangedRecordDoesNotWrite() {
        defaults.set("Retro", forKey: profileKey)
        XCTAssertTrue(store.capture(skin: "Cerulean", effect: "geiss", preset: 2))
        XCTAssertFalse(store.capture(skin: "Cerulean", effect: "geiss", preset: 2))
        XCTAssertTrue(store.capture(skin: "Cerulean", effect: "geiss", preset: 3))
    }

    func testSkinNamesDifferingOnlyByCaseShareOneRecord() {
        store.capture(skin: "Cerulean", effect: "bars", preset: 0)
        XCTAssertEqual(store.restore(skin: "cerulean").effect, "bars")
    }

    func testForgetDropsTheRecord() {
        store.capture(skin: "Cerulean", effect: "tripex", preset: 1)
        store.forget(skin: "Cerulean")
        XCTAssertNil(store.restore(skin: "Cerulean").effect)
    }

    /// `restore` is not `select`: an unknown or missing id means the default effect, or a skin with
    /// no record would keep drawing the previous skin's.
    @MainActor
    func testSelectionRestoreFallsBackToTheDefaultEffect() {
        let selection = WMPEffectSelection.shared
        selection.restore(effect: "geiss", preset: 4)
        XCTAssertEqual(selection.current.id, "geiss")
        XCTAssertEqual(selection.preset, 4)

        selection.restore(effect: nil, preset: 0)
        XCTAssertEqual(selection.current.id, WMPEffectSelection.catalogue[0].id)
        XCTAssertEqual(selection.preset, 0)

        selection.restore(effect: "not-an-effect", preset: 9)
        XCTAssertEqual(selection.current.id, WMPEffectSelection.catalogue[0].id)
    }
}
