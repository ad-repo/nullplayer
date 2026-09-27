import AppKit
import Foundation
import XCTest
@testable import NullPlayer

/// W104. `<NETWORK>` is the smallest surface in the corpus — 6 elements across 4 archives — but the
/// *members* a skin reads off `player.network` are not that small, and two of them were resolving
/// `.unrecognised`, which aborts the whole enclosing handler.
///
/// **Measured 2026-09-21 over 184 archives and 400 script/markup files**, decoding each the way
/// `WMPTextDecoder` does (156 UTF-16-BOM / 146 cp1252 / 89 UTF-8 / 9 UTF-8-BOM), matching
/// `\bnetwork\s*\.\s*(member)`. The census cannot answer this — it matches a *tag*, never a member
/// read — so this needed the script-text scan `harness/corpus.md` § *Grepping the corpus's script text*
/// describes:
///
/// | Member | uses | archives | before |
/// |---|---:|---:|---|
/// | `downloadProgress` | 58 | 42 | **unrecognised** |
/// | `bufferingProgress` | 26 | 11 | answered |
/// | `receptionQuality` | 9 | 4 | answered |
/// | `bitRate` | 9 | 8 | answered |
/// | `bandWidth` | 9 | 7 | inert |
/// | `sourceProtocol` | 6 | 3 | inert |
/// | `maxBitRate` | 3 | 3 | **unrecognised** |
/// | `framesSkipped` / `lostPackets` / `receivedPackets` | 0 | 0 | inert |
///
/// **The 58 is not the blast radius, and splitting it is what found the real case**: 55 of those
/// uses are `wmpprop:` bindings, which `WMPPropertyRegistry` has resolved since W93 — a separate
/// resolution of the same path. Only **3 script reads, all in `tubeframe.wmz`**, ever reached
/// `readNetwork`. A count that had not been split by resolution path would have ranked this at 42
/// archives when it is one.
@MainActor
final class WMPNetworkMemberTests: XCTestCase {

    private func waitUntil(timeout: Duration = .seconds(5),
                           _ condition: @MainActor @escaping () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            if clock.now >= deadline { XCTFail("Timed out waiting for WMP controller state"); return }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func controller(wms: String, filename: String) async throws
        -> (WMPMainWindowController, UserDefaults, () -> Void) {
        let root = try WMPSkinTestSupport.temporaryDirectory()
        let suite = "WMPNetworkMemberTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let importer = WMPSkinImporter(directoryURL: root, defaults: defaults)
        let source = try WMPSkinTestSupport.makeArchive(
            [WMPTestArchiveEntry("skin.wms", data: Data(wms.utf8))], filename: filename)
        _ = try await importer.importSkin(from: source)
        let controller = WMPMainWindowController(importer: importer)
        return (controller, defaults, { defaults.removePersistentDomain(forName: suite) })
    }

    private func preference(_ key: String, in defaults: UserDefaults) -> String? {
        for (name, value) in defaults.dictionaryRepresentation()
        where name.hasPrefix("wmp.preferences.") {
            if let values = value as? [String: String], let stored = values[key] { return stored }
        }
        return nil
    }

    /// The assertion that matters is not the value — it is that the **statement after the read
    /// still runs**. `tubeframe.wmz`'s `GetMetaData` reads `downloadProgress` in its first `case`,
    /// so the unrecognised member cost every branch behind it and the rotating metadata readout
    /// drew nothing at all. Both spellings are exercised because they are one field: WMP scales
    /// each 0-100 and a skin picks whichever it prefers to drive its buffer bar.
    func testNetworkMembersTheCorpusReadsDoNotAbortTheHandler() async throws {
        let (controller, defaults, cleanup) = try await controller(wms: """
        <THEME>
          <VIEW id="main" width="120" height="80">
            <SUBVIEW id="probe" left="0" top="0" width="120" height="80" backgroundColor="#224466"
                     onClick="JScript:var a=player.network.downloadProgress;\
        var b=player.network.bufferingProgress;var c=player.network.maxBitRate;\
        var d=player.network.sourceProtocol;var e=player.network.bandWidth;\
        theme.savePreference('after','yes');theme.savePreference('same',(a==b)?'yes':'no');"/>
          </VIEW>
        </THEME>
        """, filename: "NetworkMembers.wmz")
        defer { cleanup() }
        try await waitUntil { controller.window?.contentView is WMPMainView }
        let view = try XCTUnwrap(controller.window?.contentView as? WMPMainView)

        view.onScriptEvent?("click", "probe", nil)
        try await waitUntil { self.preference("after", in: defaults) == "yes" }
        XCTAssertEqual(preference("same", in: defaults), "yes",
                       "downloadProgress and bufferingProgress are one field, not two")
        controller.prepareForUITeardown()
        controller.window?.close()
    }

    /// **A member the engine answers must never stay in the demand tally** — the `alphaBlendTo`
    /// trap, which had that member ranked as the largest open row in the backlog while it worked.
    /// `sourceProtocol` was drifting exactly that way: answered in `readNetwork` since W101's
    /// `Corona` case and absent from `WMPJScriptCompatibility` ever since, so the census went on
    /// counting demand for it. The list's own doc comment claims it "is derived from the one object
    /// model rather than restated"; it is in fact restated, which is how the drift happened, and
    /// this test is the check that comment implies.
    func testEveryNetworkMemberTheCorpusReadsIsCountedAsImplemented() {
        for member in ["downloadProgress", "bufferingProgress", "receptionQuality", "bitRate",
                       "bandWidth", "sourceProtocol", "maxBitRate"] {
            XCTAssertTrue(WMPJScriptCompatibility.supports(object: "network", member: member),
                          "\(member) is answered and the census still counts it as unknown")
        }
        // No reader in the corpus, answered only so a handler cannot abort on one. They stay
        // listed: the tally ranks what is *unanswered*, and these are answered.
        for member in ["framesSkipped", "lostPackets", "receivedPackets"] {
            XCTAssertTrue(WMPJScriptCompatibility.supports(object: "network", member: member))
        }
        // The surface stays closed. `downloadControl` and `encodedFrameRate` are real WMP SDK
        // members this engine does not answer, and no archive reads either — an unrecognised
        // resolution is what lets the census rank one if a new archive ever does.
        for absent in ["downloadControl", "encodedFrameRate", "frameRate", "bufferingCount"] {
            XCTAssertFalse(WMPJScriptCompatibility.supports(object: "network", member: absent),
                           "\(absent) is unanswered, so the census must keep counting it")
        }
    }
}
