import XCTest
import ZIPFoundation
@testable import NullPlayer

/// B128 — cPro2 Dark Aluminum's Web Reader tab came up empty, two faults deep.
///
/// Reported 2026-09-05 as *"in cpro2_dark the browser tab does not load the browser"*. The reader's
/// own `xui/CentroSUI/_v2/Reader/main.m` answers `myGroup.onSetVisible(1)` with
/// `initLoadFiles(); if (continueLoad) surfSelected(); else { myGroup.hide(); }` — a reader that
/// cannot read its provider list takes the whole tab down with it, so there is nothing on screen to
/// say why. Neither fault was in the skin:
///
/// 1. `Application.GetApplicationPath()` answered the **host** directory the bundle sits in. The
///    provider file is addressed only as
///    `getApplicationPath() + "\Plugins\ClassicPro\engine\xui\CentroSUI\_v2\Reader\source\_en-us.xml"`
///    and `XmlDoc.load` resolves inside the WAL VFS, where the engine is mounted at
///    `/Plugins/classicPro/engine` and `/Applications/…` can never name anything. `exists()` came
///    back false and `initLoadFiles` returned with `continueLoad` still false.
/// 2. Behind it, `Color.getRedWithGamma()` was unimplemented. With the providers loaded,
///    `surfSelected()` builds its URL through `convert_address.mi`, whose `%COLOR:LBG%` token calls
///    `getColorHex()` — and that aborted one statement before `myBrowser.navigateUrl(…)`. The
///    default provider carries the token, so the tab was still dead.
final class WinampModernB128Tests: XCTestCase {

    // MARK: - getApplicationPath is the VFS root

    /// The host path is the honest answer to "where is the binary" and the wrong answer to every
    /// question a skin asks with it, because every route onward resolves in the VFS.
    func testApplicationPathIsTheVFSRootRatherThanTheHostBundle() throws {
        let (runtime, _) = try makeRuntime()
        let path = try runtime.invoke(method: "getapplicationpath", on: MakiObjectReference(.system),
                                      arguments: [], program: program()).stringValue
        XCTAssertEqual(path, "/")
        XCTAssertFalse(path.hasPrefix(Bundle.main.bundleURL.deletingLastPathComponent().path + "/"),
                       "a host path can never name a file the VFS holds")
    }

    /// The whole chain the reader walks, in one test: the answer, a caller's own `\` concatenated
    /// onto it, and `XmlDoc.load`/`exists` at the far end. The doubled separator that produces is
    /// dropped by canonicalization — which is why the root may carry a trailing one.
    func testAConcatenatedWindowsPathReachesAFileInTheVFS() throws {
        let (runtime, _) = try makeRuntime()
        let root = try runtime.invoke(method: "getapplicationpath", on: MakiObjectReference(.system),
                                      arguments: [], program: program()).stringValue
        let xmlDoc = try makeXmlDocument(runtime)
        _ = try runtime.invoke(method: "load", on: xmlDoc,
                               arguments: [.string(root + #"\data\providers.xml"#)],
                               program: program())
        XCTAssertTrue(try runtime.invoke(method: "exists", on: xmlDoc, arguments: [],
                                         program: program()).truthy,
                      "the file is in the skin's mount; only the host path could not reach it")
    }

    func testAPathThatIsInNoMountStillAnswersFalse() throws {
        let (runtime, _) = try makeRuntime()
        let xmlDoc = try makeXmlDocument(runtime)
        _ = try runtime.invoke(method: "load", on: xmlDoc,
                               arguments: [.string(#"/\Plugins\ClassicPro\engine\nothing.xml"#)],
                               program: program())
        XCTAssertFalse(try runtime.invoke(method: "exists", on: xmlDoc, arguments: [],
                                          program: program()).truthy,
                       "a miss is the ordinary case — a skin branches on it rather than failing")
    }

    // MARK: - Color's gamma channels

    /// They answer the *same* numbers as the plain getters, and that is the reading rather than a
    /// stub: `ColorMgr.getColor` resolves through `WasabiSceneRenderer.resolvedColor`, which has
    /// already applied the gammagroup and the live colour theme, so there is no un-gamma'd form left
    /// to distinguish.
    func testGammaChannelsAnswerTheResolvedColour() throws {
        let (runtime, _) = try makeRuntime()
        let colour = try runtime.invoke(method: "getcolor", on: MakiObjectReference(.colorManager),
                                        arguments: [.string("test.reader.background")],
                                        program: program())
        guard case .object(let reference) = colour else {
            return XCTFail("getColor must answer a Color object")
        }
        func channel(_ method: String) throws -> Int32 {
            try runtime.invoke(method: method, on: reference, arguments: [], program: program())
                .integerValue
        }
        XCTAssertEqual(try channel("getred"), 18)
        XCTAssertEqual(try channel("getgreen"), 24)
        XCTAssertEqual(try channel("getblue"), 38)
        XCTAssertEqual(try channel("getredwithgamma"), try channel("getred"))
        XCTAssertEqual(try channel("getgreenwithgamma"), try channel("getgreen"))
        XCTAssertEqual(try channel("getbluewithgamma"), try channel("getblue"))
    }

    /// A missing *signature* fails closed before the trace, which is what made this one so quiet —
    /// `surfSelected()` simply stopped, with no `UNSUPPORTED` line to say where.
    func testTheGammaChannelsHaveDispatchableSignatures() throws {
        let (runtime, _) = try makeRuntime()
        for method in ["getredwithgamma", "getgreenwithgamma", "getbluewithgamma"] {
            let signature = try XCTUnwrap(runtime.signature(for: method, classGUID: nil),
                                          "\(method) has no signature, so no call to it can unwind")
            XCTAssertEqual(signature.argumentCount, 0)
            XCTAssertEqual(signature.returnKind, .integer)
        }
    }

    // MARK: - Helpers

    /// What `new XmlDoc` reaches: `makeObject` answers a generic dynamic shell for any class it does
    /// not special-case, and `load` is what gives that shell its `.xmlDocument` role.
    private func makeXmlDocument(_ runtime: WinampModernScriptRuntime) throws -> MakiObjectReference {
        try runtime.makeObject(classGUID: "b3c0f0e14a1d4f5e9a2b6c7d8e9f0a1b", program: program())
    }

    private func makeRuntime() throws -> (WinampModernScriptRuntime, WinampModernLoadedSkin) {
        let loaded = try load(files: [
            "skin.xml": """
            <WinampAbstractionLayer version="1.34">
              <skininfo><name>B128</name></skininfo>
              <elements>
                <color id="test.reader.background" value="18,24,38"/>
              </elements>
              <container id="main" name="B128">
                <layout id="normal" w="120" h="60"/>
              </container>
            </WinampAbstractionLayer>
            """,
            "data/providers.xml": """
            <WasabiXML><BrowserPro>
              <sourceitem name="Example" url="https://example.invalid/?q=%ARTIST%"/>
            </BrowserPro></WasabiXML>
            """,
        ])
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: Host())
        addTeardownBlock { runtime.teardown() }
        return (runtime, loaded)
    }

    private func load(files: [String: String]) throws -> WinampModernLoadedSkin {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernB128Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("B128-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        for (path, contents) in files.sorted(by: { $0.key < $1.key }) {
            let payload = Data(contents.utf8)
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(payload.count),
                                 compressionMethod: .none) { position, size in
                let start = Int(position)
                guard start < payload.count else { return Data() }
                return payload.subdata(in: start..<min(payload.count, start + size))
            }
        }
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: url)
        addTeardownBlock { loaded.teardown() }
        return loaded
    }

    private func program() -> MakiProgram {
        MakiProgram(version: 0x0403, classes: [], methods: [], variables: [], bindings: [],
                    instructions: [], source: WalSourceLocation(path: "/Skins/B128/test.maki"),
                    ownerID: nil, parameter: nil)
    }

    private final class Host: WinampModernHost {
        var playbackState: PlaybackState = .stopped
        var currentTime: TimeInterval = 0
        var duration: TimeInterval = 0
        var volume: Double = 0.5
        var shuffleEnabled = false
        var repeatEnabled = false
        var trackTitle = ""
        var trackArtist = ""
        var trackAlbum = ""
        var trackInfo = ""
        var bitrateKbps = 0
        var sampleRateHz = 0
        var spectrumLevels: [Float] = []
        var trackDisplayTitle: String { trackTitle }
        func play() {}
        func pause() {}
        func stop() {}
        func previous() {}
        func next() {}
        func seek(to seconds: TimeInterval) {}
        func openFiles() {}
        func beginVisualizationConsumption() {}
        func endVisualizationConsumption() {}
    }
}
