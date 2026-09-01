import XCTest
import ZIPFoundation
@testable import NullPlayer

/// B92 — `@DEFAULTSKINPATH@`, two bugs stacked.
///
/// The variable was a bare assignment while `@SKINPATH@` and `@COLORTHEMESPATH@` go through
/// `setVariable(…, trailingSeparator: true)`, so canum's `<include file="@DEFAULTSKINPATH@xml/eq.xml"/>`
/// fused into `/Skins/Defaultxml/eq.xml` — and the fused name came back out verbatim in
/// `[missingRequiredMount] This skin requires the skin 'Defaultxml' to be installed.`
///
/// Adding the separator alone only renamed the failure to `'Default'`, because nothing is ever
/// mounted there: `@DEFAULTSKINPATH@` means Winamp's *stock* Modern skin and NullPlayer ships none.
/// The corpus copy that comes closest, `winampmodern566.wal`, is the Winamp5 Base Skin and contains
/// neither `xml/eq.xml` nor `xml/thinger.xml` — two of the three files canum asks it for — so
/// aliasing that archive onto `Default` would have fixed one include in three, and only for users
/// who happen to own it.
///
/// So `/Skins/Default` is the one root a skin may name with nothing behind it. An unanswered path
/// there fails as an ordinary `resourceMissing`, the include expander skips it with a warning, and
/// `WasabiSurfaceSynthesizer` covers the surface with the skin's *own* frame — which is nearer to
/// what the author asked for than refusing the whole skin. A `Default` that really is installed is
/// still mounted and still resolves.
final class WinampModernB92Tests: XCTestCase {

    // MARK: - The separator

    /// The fused name, in one assertion. Every other variable in this family carries the separator
    /// because skins concatenate a filename straight onto it.
    func testDefaultSkinPathCarriesATrailingSeparator() throws {
        let vfs = try WalVirtualFileSystem(skinName: "Canum",
                                           skin: WalMemoryResourceProvider(resources: ["skin.xml": Data()]))
        let resolved = try vfs.resolve("@DEFAULTSKINPATH@xml/eq.xml", relativeTo: "/Skins/Canum/skin.xml",
                                       mustExist: false)
        XCTAssertEqual(resolved.logicalPath, "/Skins/Default/xml/eq.xml")
        XCTAssertFalse(resolved.logicalPath.contains("Defaultxml"), "the concatenation that named the bug")
    }

    /// `@SKINPATH@` and `@COLORTHEMESPATH@` are what the separator is copied from; pinned together so
    /// the three cannot drift apart again.
    func testTheOtherPathVariablesStillConcatenateTheSameWay() throws {
        let vfs = try WalVirtualFileSystem(skinName: "Canum",
                                           skin: WalMemoryResourceProvider(resources: ["skin.xml": Data()]))
        for variable in ["@SKINPATH@", "@COLORTHEMESPATH@"] {
            let resolved = try vfs.resolve("\(variable)xml/player.xml", relativeTo: "/Skins/Canum/skin.xml",
                                           mustExist: false)
            XCTAssertEqual(resolved.logicalPath, "/Skins/Canum/xml/player.xml", "for \(variable)")
        }
    }

    // MARK: - The absent mount

    /// canum's shape: three includes into a stock skin that is not there. Before the fix this was a
    /// hard `missingRequiredMount` and the skin did not load at all.
    func testIncludesIntoAnUninstalledDefaultSkinAreSkippedRatherThanFatal() throws {
        let loaded = try load(files: [
            "skin.xml": Data("""
            <WasabiXML>
              <include file="@DEFAULTSKINPATH@xml/eq.xml"/>
              <include file="@DEFAULTSKINPATH@xml/pledit.xml"/>
            \(Self.container(id: "main", name: "Main Window", width: 20, height: 10))
            </WasabiXML>
            """.utf8),
        ])

        let ids = WinampModernContainerTopology.windowContainers(graph: loaded.runtime.graph).map(\.id)
        XCTAssertTrue(ids.contains("main"), "everything beside the skipped includes still loads")

        let skipped = loaded.runtime.diagnostics.filter {
            $0.code == .resourceMissing && $0.message.contains("DEFAULTSKINPATH")
        }
        XCTAssertEqual(skipped.count, 2, "one warning per skipped include")
        XCTAssertTrue(skipped.allSatisfy { $0.severity == .warning })
        XCTAssertFalse(loaded.runtime.diagnostics.contains { $0.code == .missingRequiredMount },
                       "no skin named 'Default' is being demanded of the user")
    }

    /// The other half of the decision: when a skin called `Default` *is* installed beside the archive,
    /// the lazy sibling mount still answers and the include resolves for real.
    func testAnInstalledDefaultSkinIsStillMountedAndResolved() throws {
        let directory = try makeDirectory()
        _ = try makeArchive(in: directory, named: "Default", files: [
            "skin.xml": Data("<WasabiXML/>".utf8),
            "xml/eq.xml": Data("""
            <WasabiXML>
            \(Self.container(id: "Equalizer", name: "Equalizer", width: 24, height: 12))
            </WasabiXML>
            """.utf8),
        ])
        let skin = try makeArchive(in: directory, named: "Canum", files: [
            "skin.xml": Data("""
            <WasabiXML>
              <include file="@DEFAULTSKINPATH@xml/eq.xml"/>
            \(Self.container(id: "main", name: "Main Window", width: 20, height: 10))
            </WasabiXML>
            """.utf8),
        ])

        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: skin)
        addTeardownBlock { loaded.teardown() }

        let ids = WinampModernContainerTopology.windowContainers(graph: loaded.runtime.graph).map(\.id)
        XCTAssertTrue(ids.contains("Equalizer"), "the stock skin's declarations reach the graph")
        XCTAssertFalse(loaded.runtime.diagnostics.contains { $0.code == .resourceMissing },
                       "nothing was skipped — the file was found")
    }

    /// A file the mounted `Default` does not contain is a skipped include, not a failure: the same
    /// tolerance the skin's own mount gets, for the same reason. `winampmodern566` is short of two of
    /// canum's three files, so a real installation lands here.
    func testAMissingFileInsideAMountedDefaultSkinIsStillSkipped() throws {
        let directory = try makeDirectory()
        _ = try makeArchive(in: directory, named: "Default", files: ["skin.xml": Data("<WasabiXML/>".utf8)])
        let skin = try makeArchive(in: directory, named: "Canum", files: [
            "skin.xml": Data("""
            <WasabiXML>
              <include file="@DEFAULTSKINPATH@xml/thinger.xml"/>
            \(Self.container(id: "main", name: "Main Window", width: 20, height: 10))
            </WasabiXML>
            """.utf8),
        ])

        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: skin)
        addTeardownBlock { loaded.teardown() }
        XCTAssertTrue(loaded.runtime.diagnostics.contains { $0.code == .resourceMissing })
        XCTAssertTrue(WinampModernContainerTopology.windowContainers(graph: loaded.runtime.graph)
            .map(\.id).contains("main"))
    }

    // MARK: - Containment

    /// `Default` is the *only* optional root. A skin that names some other collection member it does
    /// not ship still fails hard and still names what to install — that message is the whole point of
    /// `missingRequiredMount`, and the Big Bento Light editions depend on the mount actually happening.
    /// The name here has to be one nobody could have installed: the resolver searches the user's real
    /// skins directory too, so `Big Bento Modern` passed on this machine and would not on a clean one.
    func testAnotherUninstalledSiblingSkinIsStillAHardNamedFailure() throws {
        XCTAssertThrowsError(try load(files: [
            "skin.xml": Data("""
            <WasabiXML>
              <include file="@SKINSPATH@/NullPlayer B92 Absent Skin/xml/player.xml"/>
            \(Self.container(id: "main", name: "Main Window", width: 20, height: 10))
            </WasabiXML>
            """.utf8),
        ])) { error in
            guard let failure = error as? WalFailure else { return XCTFail("expected a WalFailure") }
            XCTAssertTrue(failure.diagnostics.contains { $0.code == .missingRequiredMount })
            XCTAssertTrue(failure.diagnostics.contains { $0.message.contains("NullPlayer B92 Absent Skin") },
                          "the message names the skin to install")
        }
    }

    /// And an include climbing out of the skins collection entirely — the ClassicPro engine line — is
    /// untouched by any of this: a cPro skin whose engine is missing must still say so rather than
    /// load and draw almost nothing.
    func testAnIncludeIntoAnUninstalledEngineIsStillFatal() throws {
        XCTAssertThrowsError(try load(files: [
            "skin.xml": Data("""
            <WasabiXML>
              <include file="@COLORTHEMESPATH@../../Plugins/classicPro/engine/load.xml"/>
            \(Self.container(id: "main", name: "Main Window", width: 20, height: 10))
            </WasabiXML>
            """.utf8),
        ]))
    }

    // MARK: - Fixtures

    private static func container(id: String, name: String, width: Int, height: Int) -> String {
        """
        <container id="\(id)" name="\(name)">
          <layout id="normal" w="\(width)" h="\(height)">
            <layer id="\(id).body" x="0" y="0" w="\(width)" h="\(height)"/>
          </layout>
        </container>
        """
    }

    private func load(files: [String: Data]) throws -> WinampModernLoadedSkin {
        let url = try makeArchive(in: try makeDirectory(), named: "Canum", files: files)
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: url)
        addTeardownBlock { loaded.teardown() }
        return loaded
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernB92Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func makeArchive(in directory: URL, named name: String, files: [String: Data]) throws -> URL {
        let url = directory.appendingPathComponent("\(name).wal")
        let archive = try Archive(url: url, accessMode: .create)
        for (entry, payload) in files.sorted(by: { $0.key < $1.key }) {
            try archive.addEntry(with: entry, type: .file, uncompressedSize: Int64(payload.count),
                                 compressionMethod: .none) { position, size in
                let start = Int(position)
                guard start < payload.count else { return Data() }
                return payload.subdata(in: start..<min(payload.count, start + size))
            }
        }
        return url
    }
}
