import Foundation
import XCTest
@testable import NullPlayer

/// W280. `Asimov_Radio`'s volume is two `<BUTTONELEMENT>`s whose `onClick` runs `SetVolume` in
/// `MBay.js`: write `player.settings.volume ± 9`, clamp it by reading it back, then light twelve bar
/// subviews off a third read in `DisplayVolume()`. The setter queued the host command and left the
/// snapshot alone, so every read after the write in that handler saw the old value — the bars
/// trailed the volume by a click and the clamp never fired.
@MainActor
final class WMPSettingsVolumeTests: XCTestCase {

    /// The skin's own handler, reduced: the read after the write is what the bars are drawn from.
    func testAReadAfterAVolumeWriteSeesTheWrite() async throws {
        let output = try await transact("""
        player.settings.volume = player.settings.volume + 9;
        theme.savePreference('read', String(player.settings.volume));
        """, volume: 0.5)
        XCTAssertEqual(output.writes["read"], "59")
        XCTAssertEqual(output.commands.map(\.value), [.number(59)])
    }

    /// `SetVolume(false)` at 5%: the write lands at 0, not -4, and the skin's clamp has nothing
    /// left to correct — so the host is told 0 once rather than an out-of-range value.
    func testAVolumeWriteIsClampedToWMPsRange() async throws {
        let output = try await transact("""
        player.settings.volume = player.settings.volume - 9;
        if (player.settings.volume < 0) { player.settings.volume = 0; }
        theme.savePreference('read', String(player.settings.volume));
        """, volume: 0.05)
        XCTAssertEqual(output.writes["read"], "0")
        XCTAssertEqual(output.commands.map(\.value), [.number(0)])
    }

    func testANonFiniteVolumeWriteKeepsTheVolume() {
        let model = WMPObjectModel()
        model.snapshot.volume = 0.4
        _ = model.set("player.settings", "volume", .number(.nan))
        XCTAssertEqual(model.snapshot.volume, 0.4)
    }

    private func transact(_ handler: String, volume: Double) async throws
        -> (commands: [WMPJScriptHostCommand], writes: [String: String]) {
        let archive = try WMPSkinTestSupport.makeArchive([WMPTestArchiveEntry("skin.wms", data: Data("""
        <THEME><VIEW id="main" width="100" height="100">
          <BUTTON id="go" width="10" height="10"/>
        </VIEW></THEME>
        """.utf8))])
        let skin = try await WMPSkinLoader().load(from: archive)
        let suite = "WMPSettingsVolumeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let runtime = WMPScriptRuntime(preferences: WMPPreferenceStore(skinData: Data(), defaults: defaults))
        var snapshot = WMPHostSnapshot()
        snapshot.volume = volume
        let output = await runtime.transact(
            skin: skin, viewID: "main", size: .init(width: 100, height: 100), snapshot: snapshot,
            event: .init(name: "click", targetID: "go", handlers: [handler]))
        var writes: [String: String] = [:]
        for (name, value) in defaults.dictionaryRepresentation() where name.hasPrefix("wmp.preferences.") {
            if let stored = value as? [String: String] { writes.merge(stored) { _, new in new } }
        }
        return (output.hostCommands.filter { $0.action == "volumePercent" }, writes)
    }
}
