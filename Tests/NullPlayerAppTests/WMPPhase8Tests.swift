import AppKit
import Foundation
import XCTest
@testable import NullPlayer

@MainActor
final class WMPPhase8Tests: XCTestCase {
    func testCleanFirstLaunchResolvesToDedicatedUnskinnedWMPWithoutOriginalPreferenceReads() {
        let defaults = FirstLaunchDefaults()

        let mode = PlayerUIMode.stored(in: defaults, forcedMode: nil)
        let controller = WindowManager.makeMainWindowController(for: mode)

        XCTAssertEqual(mode, .wmp)
        XCTAssertTrue(controller is WMPMainWindowController)
        XCTAssertTrue(controller.window?.contentView is WMPUnskinnedMainView)
        XCTAssertFalse(controller is MainWindowController)
        XCTAssertFalse(controller is ModernMainWindowController)
        XCTAssertTrue(defaults.originalPreferenceReads.isEmpty,
                      "A clean WMP launch must not inspect Original or Original-Metal preferences")
        controller.prepareForUITeardown()
        controller.window?.close()
    }

    func testPreviousReleaseStateDecodingAndAllPersistedModesRemainStable() {
        XCTAssertEqual(AppStateManager.restoredUIMode(rawValue: nil, savedInModernMode: false), .classic)
        XCTAssertEqual(AppStateManager.restoredUIMode(rawValue: nil, savedInModernMode: true), .modern)
        for mode in PlayerUIMode.allCases {
            XCTAssertEqual(
                AppStateManager.restoredUIMode(rawValue: mode.rawValue, savedInModernMode: false),
                mode
            )
        }
    }

    func testPublicCompatibilityReportIsBoundedJSONWithoutLocalArchivePath() async throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/WMPSkin/widgets.wmz")
        let loaded = try await WMPSkinLoader().load(from: fixture)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(loaded.compatibilityReport)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertLessThan(data.count, WMPPhase0Limits.scriptMessageBytes)
        XCTAssertFalse(json.contains(fixture.deletingLastPathComponent().path))
        XCTAssertTrue(json.contains("\"tags\""))
        XCTAssertTrue(json.contains("\"diagnostics\""))
    }
}

private final class FirstLaunchDefaults: UserDefaults {
    private(set) var originalPreferenceReads: [String] = []
    private let originalKeys: Set<String> = [
        ModernSkinFamily.modern.skinNameKey,
        ModernSkinFamily.metal.skinNameKey,
        "modernSkinPath",
        "metalSkinPath"
    ]

    override func string(forKey defaultName: String) -> String? {
        record(defaultName)
        return nil
    }

    override func object(forKey defaultName: String) -> Any? {
        record(defaultName)
        return nil
    }

    override func bool(forKey defaultName: String) -> Bool {
        record(defaultName)
        return false
    }

    private func record(_ key: String) {
        if originalKeys.contains(key) { originalPreferenceReads.append(key) }
    }
}
