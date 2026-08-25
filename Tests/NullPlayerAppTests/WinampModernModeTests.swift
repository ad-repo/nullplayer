import Foundation
import XCTest
@testable import NullPlayer

/// Phase 1 coverage for the fourth persisted UI mode (`.winampModern`) and the de-binarized
/// controller-family policy that replaced the old "modern vs. classic" boolean.
final class WinampModernModeTests: XCTestCase {

    // MARK: - Controller family (the single source of truth)

    func testControllerFamilyMappingForAllModes() {
        XCTAssertEqual(PlayerUIMode.classic.controllerFamily, .classic)
        XCTAssertEqual(PlayerUIMode.modern.controllerFamily, .nullPlayerModern)
        XCTAssertEqual(PlayerUIMode.metal.controllerFamily, .nullPlayerModern)
        XCTAssertEqual(PlayerUIMode.winampModern.controllerFamily, .winampModern)
    }

    /// `usesModernControllers` must be narrow: true only for the NullPlayer-modern family.
    /// Folding `.winampModern` into it would select the wrong window controllers.
    func testUsesModernControllersExcludesWinampModern() {
        XCTAssertFalse(PlayerUIMode.classic.usesModernControllers)
        XCTAssertTrue(PlayerUIMode.modern.usesModernControllers)
        XCTAssertTrue(PlayerUIMode.metal.usesModernControllers)
        XCTAssertFalse(PlayerUIMode.winampModern.usesModernControllers)
    }

    // MARK: - EQ layout and skin family policies

    func testWinampModernUsesClassicTenBandEQLayout() {
        XCTAssertFalse(PlayerUIMode.winampModern.usesModernEQLayout,
                       "cPro-Bento embeds a classic 10-band EQ; winampModern must not use the 21-band layout")
        XCTAssertFalse(PlayerUIMode.classic.usesModernEQLayout)
        XCTAssertTrue(PlayerUIMode.modern.usesModernEQLayout)
        XCTAssertTrue(PlayerUIMode.metal.usesModernEQLayout)
    }

    func testWinampModernHasNoNullPlayerSkinFamily() {
        XCTAssertNil(PlayerUIMode.winampModern.modernSkinFamily,
                     "winampModern must not touch the NullPlayer Skin/ModernSkin engine")
        XCTAssertNil(PlayerUIMode.classic.modernSkinFamily)
        XCTAssertEqual(PlayerUIMode.modern.modernSkinFamily, .modern)
        XCTAssertEqual(PlayerUIMode.metal.modernSkinFamily, .metal)
    }

    /// The `.wal` family is the user-facing **Modern** skin family; NullPlayer's own former
    /// "Modern"/"Metal" families are shown as Original/Original-Metal. The raw value stays
    /// `winampModern` for persistence compatibility.
    func testWinampModernHasDisplayName() {
        XCTAssertEqual(PlayerUIMode.winampModern.displayName, "Modern")
        XCTAssertEqual(PlayerUIMode.winampModern.rawValue, "winampModern")
        XCTAssertEqual(PlayerUIMode.modern.displayName, "Original")
        XCTAssertEqual(PlayerUIMode.metal.displayName, "Original-Metal")
    }

    // MARK: - Persistence round-trips

    func testWinampModernPersistsAndRestoresViaRawValue() {
        withDefaults { defaults in
            PlayerUIMode.winampModern.persist(in: defaults, forcedMode: nil)

            XCTAssertEqual(
                defaults.string(forKey: PlayerUIMode.userDefaultsKey),
                PlayerUIMode.winampModern.rawValue
            )
            XCTAssertEqual(PlayerUIMode.stored(in: defaults, forcedMode: nil), .winampModern)
        }
    }

    /// Old clients that do not know the `winampModern` rawValue fall back on the legacy
    /// `modernUIEnabled` bool. It must be written `false` so they degrade to classic (a real,
    /// renderable UI) rather than mis-selecting the NullPlayer modern controllers.
    func testWinampModernLeavesLegacyBoolFalseForOldClients() {
        withDefaults { defaults in
            PlayerUIMode.winampModern.persist(in: defaults, forcedMode: nil)
            XCTAssertFalse(defaults.bool(forKey: "modernUIEnabled"))
        }
    }

    // MARK: - AppStateManager decode (old + new persisted values)

    func testRestoredUIModeDecodesNewWinampModernRawValue() {
        XCTAssertEqual(
            AppStateManager.restoredUIMode(rawValue: PlayerUIMode.winampModern.rawValue, savedInModernMode: false),
            .winampModern
        )
    }

    func testRestoredUIModeStillDecodesLegacyBoolWithoutRawValue() {
        XCTAssertEqual(
            AppStateManager.restoredUIMode(rawValue: nil, savedInModernMode: true),
            .modern
        )
        XCTAssertEqual(
            AppStateManager.restoredUIMode(rawValue: nil, savedInModernMode: false),
            .classic
        )
    }

    /// Geometry is only restored when the saved and running modes match exactly. winampModern
    /// must not adopt classic's saved frames despite sharing classic geometry.
    func testGeometryRestoreRequiresExactWinampModernMatch() {
        XCTAssertTrue(AppStateManager.shouldRestoreGeometry(savedMode: .winampModern, runningMode: .winampModern))
        XCTAssertFalse(AppStateManager.shouldRestoreGeometry(savedMode: .classic, runningMode: .winampModern))
        XCTAssertFalse(AppStateManager.shouldRestoreGeometry(savedMode: .winampModern, runningMode: .classic))
    }

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suiteName = "WinampModernModeTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(defaults)
    }
}
