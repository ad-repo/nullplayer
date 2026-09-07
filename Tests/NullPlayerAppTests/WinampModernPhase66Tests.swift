import XCTest
import ZIPFoundation
@testable import NullPlayer

/// Phase 66 (backlog B40) — a skin's web-facing buttons reach the web.
///
/// `System.navigateUrl` and `System.navigateUrlBrowser` were null-returning no-ops, so part of a
/// skin's feature set presented as dead controls — Big Bento Modern alone has 92 `navigateUrl` call
/// sites, two of them its lyrics finder and its YouTube search. Opening the routes was the small
/// part. Four separate faults sat on the same buttons, and each one alone was enough to make them
/// look broken, which is why they are all pinned here:
///
/// 1. **`urlEncode` did not exist.** It sits *inside* the expression that builds the address
///    (`"…/search?q=" + urlEncode(artist) + " " + urlEncode(title) + " lyrics"`), so the unsupported
///    method aborted the whole handler one layer before any navigation.
/// 2. **`browser_search` carries *terms*, `browser_navigate` carries a *URL***. Measured off the
///    bytecode of `fileinfo_lyrics_finder.maki` and the `info.component.infodisplay` script: the
///    lyrics button sends bare terms while YouTube, album cover and `streamurl` send a complete
///    `https://…`. Read alike, a search becomes `https://<terms>`.
/// 3. **A scheme-less address is a web address, not a skin-local path.** Winamp readers write
///    `www.google.com/search?q=…`, and everything past the scheme check in `destination(for:)`
///    treats the address as a path inside the WAL VFS — where a hostname can only ever be missing.
///    The page came back "The skin-local page could not be found" and nothing reached WebKit.
/// 4. **`getText`/`setText` did not follow `embed_xui`.** The lyrics search is built from the
///    *display lines*, not from metadata: `getText()` on the `Bento:InfoLine` **wrapper**, whose
///    string lives on the inner `<Text id="text">` that `fileinfo.maki` fills. The wrapper answered
///    `""`, so the button searched the web for the bare word "lyrics" — a text bug wearing a
///    browser bug's clothes, and the one the live QA actually saw.
///
/// The policy the addresses pass through is deliberately narrower than the user's own address bar:
/// HTTP/HTTPS with a real host, nothing else. The external route additionally asks the user, once
/// per skin — that consent lives in the skin's own namespaced configuration and is asserted here.
final class WinampModernPhase66Tests: XCTestCase {
    private final class Host: WinampModernHost {
        var playbackState: PlaybackState = .playing
        var currentTime: TimeInterval = 0
        var duration: TimeInterval = 240
        var volume: Double = 0.5
        var shuffleEnabled = false
        var repeatEnabled = false
        var trackTitle = "Creep"
        var trackArtist = "Radiohead"
        var trackInfo = "Radiohead - Pablo Honey"
        var trackDisplayTitle = "Radiohead - Creep"
        var bitrateKbps = 320
        var sampleRateHz = 44_100
        var channelCount = 2
        var spectrumLevels: [Float] = [0.2, 0.9]

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

    // MARK: - The address policy

    /// The shape every skin in the corpus actually writes: no scheme, and the query still carrying
    /// the literal spaces the skin joined its terms with.
    func testASchemelessAddressIsRepairedRatherThanRefused() {
        guard case .allow(let url) = WinampModernWebNavigationPolicy.resolve(
            address: "www.google.com/search?q=Radiohead Creep lyrics") else {
            return XCTFail("a bare host is a web address")
        }
        XCTAssertEqual(url.absoluteString, "https://www.google.com/search?q=Radiohead%20Creep%20lyrics")
    }

    /// The escapes a skin has already written must survive the repair. Encoding them again searches
    /// for the escape: Björk would arrive as `Bj%25C3%25B6rk`.
    func testExistingPercentEscapesAreNotEncodedTwice() {
        guard case .allow(let url) = WinampModernWebNavigationPolicy.resolve(
            address: "https://www.google.com/search?q=Bj%C3%B6rk Human Behaviour") else {
            return XCTFail("expected an allowed address")
        }
        XCTAssertEqual(url.absoluteString,
                       "https://www.google.com/search?q=Bj%C3%B6rk%20Human%20Behaviour")
    }

    /// The sandbox rule, unchanged by any of this: a skin may reach the web and nothing else.
    func testOnlyHTTPAndHTTPSAreAccepted() {
        for address in ["javascript:alert(1)", "file:///etc/passwd", "data:text/html,<b>x",
                        "ftp://example.com/x", "about:config", "  "] {
            guard case .blocked = WinampModernWebNavigationPolicy.resolve(address: address) else {
                return XCTFail("\(address) must not be navigable")
            }
        }
    }

    func testAnAddressWithNoHostIsRefused() {
        guard case .blocked = WinampModernWebNavigationPolicy.resolve(address: "https:///search") else {
            return XCTFail("a hostless URL is malformed")
        }
    }

    // MARK: - A search is terms, not an address

    /// The terms arrive already encoded a term at a time and joined with literal spaces, so they are
    /// decoded once before being encoded again as a whole.
    func testSearchTermsAreDecodedOnceBeforeBeingEncodedAgain() {
        let url = WinampModernWebNavigationPolicy.searchURL(
            terms: "Bj%C3%B6rk Human%20Behaviour lyrics", engine: .google)
        XCTAssertEqual(url?.absoluteString,
                       "https://www.google.com/search?q=Bj%C3%B6rk%20Human%20Behaviour%20lyrics")
    }

    func testEachEngineHasItsOwnEndpoint() {
        XCTAssertEqual(WinampModernWebNavigationPolicy.searchURL(terms: "creep", engine: .bing)?.host,
                       "www.bing.com")
        XCTAssertEqual(WinampModernWebNavigationPolicy.searchURL(terms: "creep",
                                                                engine: .duckDuckGo)?.host,
                       "duckduckgo.com")
    }

    func testEmptyTermsProduceNoSearch() {
        XCTAssertNil(WinampModernWebNavigationPolicy.searchURL(terms: "   ", engine: .google))
        XCTAssertNil(WinampModernWebNavigationPolicy.searchURL(terms: "%20", engine: .google))
    }

    /// The engine is the skin's own registered choice — the same "honour what the skin already
    /// asked for" rule the internal/external split follows. Big Bento's two options, verbatim.
    func testTheSearchEngineIsTheOneTheSkinRegistered() {
        XCTAssertEqual(WinampModernWebNavigationPolicy.preferredSearchEngine(settings: [
            ("Default Search Engine: Google", "1"), ("Default Search Engine: Bing", "0"),
        ]), .google)
        XCTAssertEqual(WinampModernWebNavigationPolicy.preferredSearchEngine(settings: [
            ("Default Search Engine: Google", "0"), ("Default Search Engine: Bing", "1"),
        ]), .bing)
    }

    /// A skin that registers no engine gets the one the internal browser's own start page uses, so
    /// the two surfaces cannot disagree.
    func testASkinThatNamesNoEngineFallsBackToTheStartPageSearch() {
        XCTAssertEqual(WinampModernWebNavigationPolicy.preferredSearchEngine(settings: []), .duckDuckGo)
        XCTAssertEqual(WinampModernWebNavigationPolicy.preferredSearchEngine(settings: [
            ("Use Default Browser to open links", "1"), ("Default Search Engine: Google", "0"),
        ]), .duckDuckGo)
    }

    // MARK: - Consent for the external route

    func testTheExternalRouteIsClosedUntilTheUserOpensItForThisSkin() throws {
        let suite = try XCTUnwrap(UserDefaults(suiteName: "phase66-\(UUID().uuidString)"))
        let skin = WinampModernConfiguration(namespace: "Big Bento Modern", defaults: suite)
        let other = WinampModernConfiguration(namespace: "Another Skin", defaults: suite)

        XCTAssertFalse(WinampModernWebNavigationPolicy.allowsDefaultBrowser(in: skin))
        WinampModernWebNavigationPolicy.setAllowsDefaultBrowser(true, in: skin)
        XCTAssertTrue(WinampModernWebNavigationPolicy.allowsDefaultBrowser(in: skin))
        // One skin's answer never speaks for another's.
        XCTAssertFalse(WinampModernWebNavigationPolicy.allowsDefaultBrowser(in: other))
    }

    // MARK: - What the browser surface is handed

    /// The live defect: the reader's own `<browser>.navigateUrl` writes no scheme, and the VFS
    /// branch below it could only ever answer "not found".
    @MainActor
    func testASchemelessAddressReachesTheWebRatherThanTheVFS() throws {
        let loaded = try makeSkin().0
        let request = WinampModernBrowserRequest(address: "www.google.com/search?q=Radiohead Creep lyrics",
                                                 sourceLogicalPath: "/Skins/Synthetic/skin.xml")
        guard case .url(let url) = WinampModernBrowserSurfaceView.destination(for: request,
                                                                             vfs: loaded.vfs) else {
            return XCTFail("expected a web destination")
        }
        XCTAssertEqual(url.absoluteString,
                       "https://www.google.com/search?q=Radiohead%20Creep%20lyrics")
    }

    /// …and the half that must not regress: a skin-local page is still served from the WAL VFS.
    @MainActor
    func testASkinLocalPageStillResolvesThroughTheVFS() throws {
        let loaded = try makeSkin().0
        // Addressed relative to the markup that declares it, the way a `<browser url="…">` is — the
        // skin's mount name is its archive's, so it cannot be spelled out here.
        let source = try XCTUnwrap(loaded.runtime.graph.roots.first?.source.path)
        let request = WinampModernBrowserRequest(address: "pages/start.html",
                                                 sourceLogicalPath: source)
        guard case .url(let url) = WinampModernBrowserSurfaceView.destination(for: request,
                                                                             vfs: loaded.vfs) else {
            return XCTFail("expected the skin-local page")
        }
        XCTAssertEqual(url.scheme, WinampModernBrowserSurfaceView.localScheme)
        XCTAssertTrue(url.path.hasSuffix("/pages/start.html"))
    }

    /// The rule that keeps the two apart. A dotted *resource* name is not a hostname, which is what
    /// makes `reader/source/_en-us.xml` — a real WAL resource — safe from the repair above.
    @MainActor
    func testOnlyAHostShapedAddressIsTreatedAsWeb() {
        for web in ["www.google.com/search?q=a b", "duckduckgo.com", "example.co.uk/x#frag"] {
            XCTAssertTrue(WinampModernBrowserSurfaceView.looksLikeWebAddress(web), web)
        }
        for local in ["reader_providers.xml", "source/_en-us.xml", "backgrounds/start.html",
                      "..\\reader\\page.htm", "index", "logo.png"] {
            XCTAssertFalse(WinampModernBrowserSurfaceView.looksLikeWebAddress(local), local)
        }
    }

    // MARK: - `embed_xui` carries the text, both ways

    /// The bug the live QA actually hit: `fileinfo.maki` fills the inner text, the lyrics finder
    /// reads the wrapper, and the two must be one value.
    func testGetTextOnAWrapperAnswersTheEmbeddedControl() throws {
        let (loaded, runtime) = try makeSkin()
        let inner = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "text").first)
        let wrapper = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "infodisplay.line.artist").first)

        try setText("Radiohead", on: inner, runtime: runtime)
        XCTAssertEqual(try text(of: wrapper, runtime: runtime), "Radiohead")
    }

    /// And the other direction, so the wrapper never becomes a second copy: a script that writes the
    /// wrapper writes the control that draws.
    func testSetTextOnAWrapperWritesTheEmbeddedControl() throws {
        let (loaded, runtime) = try makeSkin()
        let inner = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "text").first)
        let wrapper = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "infodisplay.line.artist").first)

        try setText("Portishead", on: wrapper, runtime: runtime)
        XCTAssertEqual(WasabiTextMetrics.content(of: inner, host: Host()), "Portishead")
        XCTAssertEqual(try text(of: wrapper, runtime: runtime), "Portishead")
    }

    // MARK: - The two global routes

    func testNavigateUrlAsksForTheUsersBrowserAndNavigateUrlBrowserForOurs() throws {
        let (_, runtime) = try makeSkin()
        var requests: [(WinampModernWebNavigationTarget, String)] = []
        runtime.globalNavigationRequested = { requests.append(($0, $1)) }

        let system = MakiObjectReference(.system)
        _ = try runtime.invoke(method: "navigateurl", on: system,
                               arguments: [.string("https://example.com/a")],
                               program: Self.makeProgram())
        _ = try runtime.invoke(method: "navigateurlbrowser", on: system,
                               arguments: [.string("https://example.com/b")],
                               program: Self.makeProgram())

        XCTAssertEqual(requests.map(\.0), [.defaultBrowser, .internalBrowser])
        XCTAssertEqual(requests.map(\.1), ["https://example.com/a", "https://example.com/b"])
    }

    /// `urlEncode` escapes everything outside RFC 3986's unreserved set — stricter than a query
    /// encoding, because the argument is one term being pasted into a query the skin assembles: an
    /// `&` in an album title must not survive as syntax.
    func testUrlEncodeEscapesEverythingOutsideTheUnreservedSet() throws {
        let (_, runtime) = try makeSkin()
        let encoded = try runtime.invoke(method: "urlencode", on: MakiObjectReference(.system),
                                         arguments: [.string("Simon & Garfunkel/Bookends?")],
                                         program: Self.makeProgram()).stringValue
        XCTAssertEqual(encoded, "Simon%20%26%20Garfunkel%2FBookends%3F")
    }

    /// A skin that sends one of the browser actions and ships no reader still reaches the host: the
    /// fallback only stands down when a script handled the action. (The handled side is measured on
    /// the real skin — `RENDER_CLICK` on Big Bento's lyrics button, where the reader answers and the
    /// host route correctly stays silent.)
    func testAnUnhandledBrowserActionStillReachesTheHost() throws {
        let (loaded, runtime) = try makeSkin()
        let target = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "sui.content").first)
        var actions: [(String, String?)] = []
        runtime.actionRequested = { actions.append(($0, $1)) }

        _ = try runtime.invoke(method: "sendaction", on: MakiObjectReference(.gui(target.stableID)),
                               arguments: [.string("browser_search"), .string("radiohead creep lyrics"),
                                           .integer(0), .integer(0), .integer(0), .integer(0)],
                               program: Self.makeProgram())

        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions.first?.0, "browser_search")
        XCTAssertEqual(actions.first?.1, "radiohead creep lyrics")
    }

    // MARK: - `ML_SendTo`

    /// Winamp's Send To menu is built from installed plugins; NullPlayer publishes no targets, so the
    /// action is accepted and inert **with a reason** — recorded demand rather than a silent default.
    func testSendToIsInertWithARecordedReason() {
        guard case .inert(let action, let reason) = WinampModernHostAction(action: "ML_SendTo") else {
            return XCTFail("ML_SendTo must decode")
        }
        XCTAssertEqual(action, "ML_SENDTO")
        XCTAssertFalse(reason.isEmpty)
    }

    // MARK: - Fixture

    /// Big Bento's info line reduced to the part that matters: a wrapper that speaks for an inner
    /// text, declared exactly as the skin declares it.
    private static let skinXML = """
    <WasabiXML>
      <groupdef id="bento.infodisplay.line" embed_xui="text" xuitag="Bento:InfoLine">
        <text id="text" display="SONGNAME" ticker="1" x="0" y="0" w="112" h="8"/>
      </groupdef>
      <container id="main">
        <layout id="normal" w="120" h="64">
          <group id="sui.content" x="0" y="0" w="120" h="32"/>
          <Bento:InfoLine id="infodisplay.line.artist" x="0" y="32" w="112" h="8"/>
        </layout>
      </container>
    </WasabiXML>
    """

    private func text(of object: WasabiObject, runtime: WinampModernScriptRuntime) throws -> String {
        try runtime.invoke(method: "gettext", on: MakiObjectReference(.gui(object.stableID)),
                           arguments: [], program: Self.makeProgram()).stringValue
    }

    private func setText(_ value: String, on object: WasabiObject,
                         runtime: WinampModernScriptRuntime) throws {
        _ = try runtime.invoke(method: "settext", on: MakiObjectReference(.gui(object.stableID)),
                               arguments: [.string(value)], program: Self.makeProgram())
    }

    private func makeSkin() throws -> (WinampModernLoadedSkin, WinampModernScriptRuntime) {
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive())
        addTeardownBlock { loaded.teardown() }
        let runtime = try WinampModernScriptRuntime(loadedSkin: loaded, host: Host())
        addTeardownBlock { runtime.teardown() }
        return (loaded, runtime)
    }

    private static func makeProgram() -> MakiProgram {
        MakiProgram(version: 0x0403, classes: [], methods: [], variables: [], bindings: [],
                    instructions: [], source: WalSourceLocation(path: "/Skins/Synthetic/test.maki"),
                    ownerID: nil, parameter: nil)
    }

    private func makeArchive() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase66Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Synthetic-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        for (path, contents) in [("skin.xml", Self.skinXML),
                                 ("pages/start.html", "<!doctype html><p>local")] {
            let payload = Data(contents.utf8)
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(payload.count),
                                 compressionMethod: .none) { position, size in
                let start = Int(position)
                guard start < payload.count else { return Data() }
                return payload.subdata(in: start..<min(payload.count, start + size))
            }
        }
        return url
    }
}
