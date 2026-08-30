import Foundation
import XCTest
@testable import NullPlayer

final class ReeltoneSkinStateTests: XCTestCase {
    func testSelectedSkinIdentityPersistsIndependentlyFromOtherSkinFamilies() {
        withDefaults { defaults in
            defaults.set("Original Fixture", forKey: ModernSkinFamily.modern.skinNameKey)
            defaults.set("Metal Fixture", forKey: ModernSkinFamily.metal.skinNameKey)

            ReeltoneSkinState.selectSkin(identity: "fixture.aqua-glass", in: defaults)

            XCTAssertEqual(
                ReeltoneSkinState.selectedSkinIdentity(in: defaults),
                "fixture.aqua-glass"
            )
            XCTAssertEqual(defaults.string(forKey: ModernSkinFamily.modern.skinNameKey), "Original Fixture")
            XCTAssertEqual(defaults.string(forKey: ModernSkinFamily.metal.skinNameKey), "Metal Fixture")
        }
    }

    func testClearingSelectedSkinIdentityDoesNotAffectOtherModes() {
        withDefaults { defaults in
            defaults.set("fixture.aqua-glass", forKey: ReeltoneSkinState.selectedSkinIdentityKey)
            defaults.set(PlayerUIMode.reeltone.rawValue, forKey: PlayerUIMode.userDefaultsKey)

            ReeltoneSkinState.selectSkin(identity: nil, in: defaults)

            XCTAssertNil(ReeltoneSkinState.selectedSkinIdentity(in: defaults))
            XCTAssertEqual(defaults.string(forKey: PlayerUIMode.userDefaultsKey), PlayerUIMode.reeltone.rawValue)
        }
    }

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suiteName = "ReeltoneSkinStateTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(defaults)
    }
}
