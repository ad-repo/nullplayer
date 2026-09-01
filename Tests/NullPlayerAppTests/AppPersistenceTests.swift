import Foundation
import XCTest
@testable import NullPlayer

final class AppPersistenceTests: XCTestCase {
    func testSkinFamilyDisplayNamesUseOriginalBranding() {
        XCTAssertEqual(PlayerUIMode.modern.displayName, "Original")
        XCTAssertEqual(PlayerUIMode.metal.displayName, "Original-Metal")
        XCTAssertEqual(PlayerUIMode.wmp.displayName, "Windows Media Player")
        XCTAssertEqual(ModernSkinFamily.modern.displayName, "Original")
        XCTAssertEqual(ModernSkinFamily.metal.displayName, "Original-Metal")
    }

    func testOriginalBrandingPreservesCompatibilityIdentifiers() {
        XCTAssertEqual(PlayerUIMode.modern.rawValue, "modern")
        XCTAssertEqual(PlayerUIMode.metal.rawValue, "metal")
        XCTAssertEqual(PlayerUIMode.wmp.rawValue, "wmp")
        XCTAssertEqual(ModernSkinFamily.modern.skinNameKey, "modernSkinName")
        XCTAssertEqual(ModernSkinFamily.metal.skinNameKey, "metalSkinName")
    }

    func testControllerFamiliesAndEQLayoutsAreExplicit() {
        XCTAssertEqual(PlayerUIMode.classic.controllerFamily, .classic)
        XCTAssertEqual(PlayerUIMode.modern.controllerFamily, .nullPlayerModern)
        XCTAssertEqual(PlayerUIMode.metal.controllerFamily, .nullPlayerModern)
        XCTAssertEqual(PlayerUIMode.wmp.controllerFamily, .wmp)
        XCTAssertFalse(PlayerUIMode.wmp.usesModernControllers)
        XCTAssertFalse(PlayerUIMode.wmp.usesModernEQLayout)
        XCTAssertNil(PlayerUIMode.wmp.modernSkinFamily)
    }

    func testFullEditionUsesExistingKeysAndHasNoForcedMode() {
        XCTAssertEqual(AppPersistence.key("savedAppState"), "savedAppState")
        XCTAssertEqual(AppPersistence.key("MainWindowFrame"), "MainWindowFrame")
        XCTAssertNil(AppPersistence.forcedUIMode)
    }

    func testScopedEditionKeyAddsNamespace() {
        XCTAssertEqual(
            AppPersistence.key("savedAppState", namespace: "Astral"),
            "Astral.savedAppState"
        )
        XCTAssertEqual(
            AppPersistence.key("PlexBrowserWindowFrame", namespace: "Astral"),
            "Astral.PlexBrowserWindowFrame"
        )
    }

    func testForcedModeIgnoresConflictingDefaultsValue() {
        withDefaults { defaults in
            defaults.set(PlayerUIMode.metal.rawValue, forKey: PlayerUIMode.userDefaultsKey)

            XCTAssertEqual(
                PlayerUIMode.stored(in: defaults, forcedMode: .classic),
                .classic
            )
        }
    }

    func testForcedModeShortCircuitsBeforeReadingAnyDefaultsDomain() {
        let defaults = ModeReadSpyDefaults()

        XCTAssertEqual(
            PlayerUIMode.stored(in: defaults, forcedMode: .classic),
            .classic
        )
        XCTAssertFalse(
            defaults.didReadMode,
            "Forced mode must return before an NSArgumentDomain -uiMode value can be read"
        )
    }

    func testForcedModePersistLeavesSharedPreferencesUntouched() {
        withDefaults { defaults in
            defaults.set(PlayerUIMode.metal.rawValue, forKey: PlayerUIMode.userDefaultsKey)
            defaults.set(true, forKey: "modernUIEnabled")

            PlayerUIMode.classic.persist(in: defaults, forcedMode: .classic)

            XCTAssertEqual(
                defaults.string(forKey: PlayerUIMode.userDefaultsKey),
                PlayerUIMode.metal.rawValue
            )
            XCTAssertTrue(defaults.bool(forKey: "modernUIEnabled"))
        }
    }

    func testFullEditionStillReadsAndPersistsModePreferences() {
        withDefaults { defaults in
            defaults.set(PlayerUIMode.modern.rawValue, forKey: PlayerUIMode.userDefaultsKey)
            XCTAssertEqual(PlayerUIMode.stored(in: defaults, forcedMode: nil), .modern)

            PlayerUIMode.classic.persist(in: defaults, forcedMode: nil)
            XCTAssertEqual(
                defaults.string(forKey: PlayerUIMode.userDefaultsKey),
                PlayerUIMode.classic.rawValue
            )
            XCTAssertFalse(defaults.bool(forKey: "modernUIEnabled"))
        }
    }

    func testFreshFullEditionDefaultsToWMPWithoutPersistingAMode() {
        withDefaults { defaults in
            XCTAssertNil(defaults.object(forKey: PlayerUIMode.userDefaultsKey))
            XCTAssertEqual(PlayerUIMode.stored(in: defaults, forcedMode: nil), .wmp)
            XCTAssertNil(defaults.object(forKey: PlayerUIMode.userDefaultsKey),
                         "Resolving the first-launch default must not overwrite a future user choice")
        }
    }

    func testUpgradePreservesEveryPersistedModeAndLegacyBoolean() {
        for mode in PlayerUIMode.allCases {
            withDefaults { defaults in
                defaults.set(mode.rawValue, forKey: PlayerUIMode.userDefaultsKey)
                XCTAssertEqual(PlayerUIMode.stored(in: defaults, forcedMode: nil), mode)
            }
        }
        withDefaults { defaults in
            defaults.set(false, forKey: "modernUIEnabled")
            XCTAssertEqual(PlayerUIMode.stored(in: defaults, forcedMode: nil), .classic)
        }
        withDefaults { defaults in
            defaults.set(true, forKey: "modernUIEnabled")
            XCTAssertEqual(PlayerUIMode.stored(in: defaults, forcedMode: nil), .modern)
        }
    }

    func testForcedModeAllowsOnlyMatchingAssignments() {
        XCTAssertTrue(PlayerUIMode.allowsAssignment(.metal, forcedMode: .metal))
        XCTAssertFalse(PlayerUIMode.allowsAssignment(.modern, forcedMode: .metal))
        XCTAssertFalse(PlayerUIMode.allowsAssignment(.classic, forcedMode: .metal))
        XCTAssertTrue(PlayerUIMode.allowsAssignment(.classic, forcedMode: nil))
    }

    func testEQLayoutFollowsResolvedModeInsteadOfSharedMirror() {
        withDefaults { defaults in
            defaults.set(PlayerUIMode.classic.rawValue, forKey: PlayerUIMode.userDefaultsKey)
            defaults.set(false, forKey: "modernUIEnabled")

            let resolved = PlayerUIMode.stored(in: defaults, forcedMode: .modern)

            XCTAssertTrue(resolved.usesModernEQLayout)
            XCTAssertFalse(PlayerUIMode.classic.usesModernEQLayout)
            XCTAssertTrue(PlayerUIMode.metal.usesModernEQLayout)
        }
    }

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suiteName = "AppPersistenceTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(defaults)
    }
}

private final class ModeReadSpyDefaults: UserDefaults {
    var didReadMode = false

    override func string(forKey defaultName: String) -> String? {
        if defaultName == PlayerUIMode.userDefaultsKey {
            didReadMode = true
            return PlayerUIMode.metal.rawValue
        }
        return super.string(forKey: defaultName)
    }
}
