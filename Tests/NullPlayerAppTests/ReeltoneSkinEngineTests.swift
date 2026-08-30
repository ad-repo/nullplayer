import Foundation
import XCTest
import ZIPFoundation
@testable import NullPlayer

final class ReeltoneSkinEngineTests: XCTestCase {
    func testInstallSelectAndRemoveOwnSelectionLifecycle() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReeltoneEngineTests-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        let archiveURL = temporaryRoot.appendingPathComponent("skin.reeltone")
        let manifest = Data(#"{"formatVersion":1,"id":"com.example.engine","name":"Engine"}"#.utf8)
        let archive = try Archive(url: archiveURL, accessMode: .create)
        try archive.addEntry(with: "skin.json", type: .file, uncompressedSize: Int64(manifest.count)) { position, size in
            manifest.subdata(in: Int(position)..<Int(position) + size)
        }

        let suiteName = "ReeltoneEngineTests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let notifications = NotificationCenter()
        let engine = ReeltoneSkinEngine(
            store: ReeltoneSkinStore(rootURL: temporaryRoot.appendingPathComponent("store")),
            defaults: defaults,
            notificationCenter: notifications
        )
        var notificationCount = 0
        let token = notifications.addObserver(forName: .reeltoneSkinDidChange, object: engine, queue: nil) { _ in
            notificationCount += 1
        }
        defer { notifications.removeObserver(token) }

        let loaded = try engine.installAndSelect(archiveAt: archiveURL)
        let identity = try XCTUnwrap(engine.currentInstallation?.record.identity)
        XCTAssertEqual(loaded.manifest.name, "Engine")
        XCTAssertEqual(ReeltoneSkinState.selectedSkinIdentity(in: defaults), identity)

        try engine.remove(identity: identity)
        XCTAssertNil(engine.currentSkin)
        XCTAssertNil(ReeltoneSkinState.selectedSkinIdentity(in: defaults))
        XCTAssertEqual(notificationCount, 2)
    }

    func testInvalidPreferredIdentityFallsBackWithoutChangingOriginalPreference() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReeltoneEngineFallbackTests-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let suiteName = "ReeltoneEngineFallbackTests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("Original Fixture", forKey: ModernSkinFamily.modern.skinNameKey)
        defaults.set(UUID().uuidString.lowercased(), forKey: ReeltoneSkinState.selectedSkinIdentityKey)
        let engine = ReeltoneSkinEngine(
            store: ReeltoneSkinStore(rootURL: temporaryRoot.appendingPathComponent("store")),
            defaults: defaults,
            notificationCenter: NotificationCenter()
        )

        let theme = engine.activatePreferredTheme()

        XCTAssertNil(engine.currentSkin)
        XCTAssertNil(engine.currentInstallation)
        XCTAssertEqual(theme.name, "Default Reeltone")
        XCTAssertEqual(theme.palette, ReeltoneThemeAdapter.defaultPalette)
        XCTAssertEqual(defaults.string(forKey: ModernSkinFamily.modern.skinNameKey), "Original Fixture")
    }
}
