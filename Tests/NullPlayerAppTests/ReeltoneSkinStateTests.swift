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

    func testPanelStateIsScopedToExactInstallationIdentity() {
        withDefaults { defaults in
            let surface = ReeltoneSurfaceID.panel("playlist")
            let frame = CGRect(x: 10, y: 20, width: 300, height: 200)
            ReeltoneSkinState.setPanelVisibility(true, identity: "skin-a", surfaceID: surface, in: defaults)
            ReeltoneSkinState.setPanelFrame(frame, identity: "skin-a", surfaceID: surface, in: defaults)
            ReeltoneSkinState.setPanelDetached(true, identity: "skin-a", surfaceID: surface, in: defaults)

            XCTAssertEqual(ReeltoneSkinState.panelVisibility(identity: "skin-a", surfaceID: surface, in: defaults), true)
            XCTAssertEqual(ReeltoneSkinState.panelFrame(identity: "skin-a", surfaceID: surface, in: defaults), frame)
            XCTAssertTrue(ReeltoneSkinState.panelIsDetached(identity: "skin-a", surfaceID: surface, in: defaults))
            XCTAssertNil(ReeltoneSkinState.panelVisibility(identity: "skin-b", surfaceID: surface, in: defaults))
            XCTAssertNil(ReeltoneSkinState.panelFrame(identity: "skin-b", surfaceID: surface, in: defaults))
            XCTAssertFalse(ReeltoneSkinState.panelIsDetached(identity: "skin-b", surfaceID: surface, in: defaults))
        }
    }

    func testDedicatedDefaultsMigrationMovesOnlyReeltoneKeys() {
        withDefaults { source in
            let destinationSuite = "ReeltoneSkinStateTests.destination.\(UUID().uuidString)"
            guard let destination = UserDefaults(suiteName: destinationSuite) else {
                return XCTFail("Failed to create destination defaults")
            }
            defer { destination.removePersistentDomain(forName: destinationSuite) }
            source.set("skin-a", forKey: ReeltoneSkinState.selectedSkinIdentityKey)
            source.set(true, forKey: "reeltone.surface.skin-a.panel:queue.visible")
            source.set("Original Skin", forKey: ModernSkinFamily.modern.skinNameKey)
            source.set("Metal Skin", forKey: ModernSkinFamily.metal.skinNameKey)

            ReeltoneDefaults.migrateLegacy(from: source, to: destination)

            XCTAssertEqual(destination.string(forKey: ReeltoneSkinState.selectedSkinIdentityKey), "skin-a")
            XCTAssertTrue(destination.bool(forKey: "reeltone.surface.skin-a.panel:queue.visible"))
            XCTAssertNil(source.object(forKey: ReeltoneSkinState.selectedSkinIdentityKey))
            XCTAssertNil(source.object(forKey: "reeltone.surface.skin-a.panel:queue.visible"))
            XCTAssertEqual(source.string(forKey: ModernSkinFamily.modern.skinNameKey), "Original Skin")
            XCTAssertEqual(source.string(forKey: ModernSkinFamily.metal.skinNameKey), "Metal Skin")
            XCTAssertNil(destination.object(forKey: ModernSkinFamily.modern.skinNameKey))
            XCTAssertNil(destination.object(forKey: ModernSkinFamily.metal.skinNameKey))
        }
    }

    func testEmbeddedOriginalPreferenceModelsCanUseReeltoneDomain() {
        withDefaults { originalDefaults in
            let reeltoneSuite = "ReeltoneSkinStateTests.hosted.\(UUID().uuidString)"
            guard let reeltoneDefaults = UserDefaults(suiteName: reeltoneSuite) else {
                return XCTFail("Failed to create Reeltone defaults")
            }
            defer { reeltoneDefaults.removePersistentDomain(forName: reeltoneSuite) }
            ModernBrowserSource.local.save(to: originalDefaults)
            ModernBrowserSortOption.nameAsc.save(to: originalDefaults)

            ModernBrowserSource.youtube.save(to: reeltoneDefaults)
            ModernBrowserSortOption.yearDesc.save(to: reeltoneDefaults)

            XCTAssertEqual(ModernBrowserSource.load(from: originalDefaults), .local)
            XCTAssertEqual(ModernBrowserSortOption.load(from: originalDefaults), .nameAsc)
            XCTAssertEqual(ModernBrowserSource.load(from: reeltoneDefaults), .youtube)
            XCTAssertEqual(ModernBrowserSortOption.load(from: reeltoneDefaults), .yearDesc)
        }
    }

    func testVersionOneFallbackMainViewUsesOnlyInjectedReeltonePreferences() {
        withDefaults { originalDefaults in
            let reeltoneSuite = "ReeltoneSkinStateTests.mainFallback.\(UUID().uuidString)"
            guard let reeltoneDefaults = UserDefaults(suiteName: reeltoneSuite) else {
                return XCTFail("Failed to create Reeltone defaults")
            }
            defer { reeltoneDefaults.removePersistentDomain(forName: reeltoneSuite) }
            originalDefaults.set(MainWindowVisMode.enhanced.rawValue, forKey: "modernMainWindowVisMode")
            originalDefaults.set(MainWindowVisMode.enhanced.rawValue, forKey: "mainWindowVisMode")
            reeltoneDefaults.set(MainWindowVisMode.cava.rawValue, forKey: "modernMainWindowVisMode")

            let view = ModernMainWindowView(frame: NSRect(x: 0, y: 0, width: 640, height: 256), preferences: reeltoneDefaults)
            defer { view.removeFromSuperview() }

            XCTAssertEqual(
                reeltoneDefaults.string(forKey: "modernMainWindowVisMode"),
                MainWindowVisMode.spectrum.rawValue
            )
            XCTAssertEqual(
                originalDefaults.string(forKey: "modernMainWindowVisMode"),
                MainWindowVisMode.enhanced.rawValue
            )
            XCTAssertEqual(
                originalDefaults.string(forKey: "mainWindowVisMode"),
                MainWindowVisMode.enhanced.rawValue
            )
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
