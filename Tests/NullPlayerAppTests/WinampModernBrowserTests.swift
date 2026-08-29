import XCTest
@preconcurrency import WebKit
@testable import NullPlayer

@MainActor
final class WinampModernBrowserTests: XCTestCase {
    func testInitialMarkupAddressPrefersURLThenClassicProHome() {
        let source = "/Plugins/classicPro/engine/xui/CentroSUI/_v1/CentroSUI.xml"

        XCTAssertEqual(WinampModernBrowserRequest.initial(
            attributes: ["url": "https://current.example/", "home": "https://home.example/"],
            sourceLogicalPath: source
        ), WinampModernBrowserRequest(address: "https://current.example/",
                                      sourceLogicalPath: source))

        XCTAssertEqual(WinampModernBrowserRequest.initial(
            attributes: ["url": "  ", "home": "http://www.skinconsortium.com/"],
            sourceLogicalPath: source
        ), WinampModernBrowserRequest(address: "http://www.skinconsortium.com/",
                                      sourceLogicalPath: source))
    }

    func testAddresslessMarkupGetsTheBuiltInBrowserHome() {
        let request = WinampModernBrowserRequest.initial(
            attributes: [:], sourceLogicalPath: "/Skins/Test/skin.xml")

        XCTAssertEqual(request.address, "about:blank")
        XCTAssertEqual(WinampModernBrowserSurfaceView.destination(for: request, vfs: nil), .home)
    }

    func testBrowserAlwaysShowsSearchFieldAboveWebContent() throws {
        let surface = WinampModernBrowserSurfaceView(
            frame: NSRect(x: 0, y: 0, width: 320, height: 200), vfs: nil)
        surface.layoutSubtreeIfNeeded()

        let webView = try XCTUnwrap(surface.subviews.compactMap { $0 as? WKWebView }.first)
        let bar = try XCTUnwrap(surface.subviews.first { view in
            view.subviews.contains(where: { $0 is NSSearchField })
        })
        let field = try XCTUnwrap(bar.subviews.compactMap { $0 as? NSSearchField }.first)

        XCTAssertFalse(bar.isHidden)
        XCTAssertEqual(field.placeholderString, "Search or enter website")
        XCTAssertEqual(bar.frame.height, WinampModernBrowserSurfaceView.locationBarHeight)
        XCTAssertEqual(webView.frame.maxY, bar.frame.minY)
        XCTAssertEqual(webView.frame.height,
                       surface.bounds.height - WinampModernBrowserSurfaceView.locationBarHeight)
    }

    /// The shipped default: `usesSkinAuthoredReaderToolbar` is off, so BB25 still stands — the
    /// surface fills Bento's reader parent and covers the skin's toolbar row, and the host keeps its
    /// own chrome. Three of that row's four controls are still dead (`back`, `forward`, and Refresh
    /// via `getColor`), which is why the switch has not been flipped.
    func testBentoReaderStaysCoveredWhileItsToolbarIsUnfinished() {
        let authored = CGRect(x: 20, y: 43, width: 500, height: 300)
        let parent = CGRect(x: 20, y: 5, width: 500, height: 338)

        XCTAssertFalse(WinampModernMainView.usesSkinAuthoredReaderToolbar)
        XCTAssertEqual(WinampModernMainView.browserSurfaceFrame(
            browserFrame: authored, browserID: "browserpro.browser",
            parentID: "centro.browser", parentFrame: parent), parent)
        XCTAssertFalse(WinampModernMainView.suppressesHostLocationBar(
            browserID: "browserpro.browser", parentID: "centro.browser"))
    }

    /// What the switch flips to, so the parked code cannot rot unnoticed: the browser keeps the
    /// rectangle the skin authored and the *host's* bar is the one that goes.
    func testSwitchedOnTheSkinKeepsItsOwnToolbarAndTheHostDropsIts() {
        let authored = CGRect(x: 20, y: 43, width: 500, height: 300)
        let parent = CGRect(x: 20, y: 5, width: 500, height: 338)

        XCTAssertEqual(WinampModernMainView.browserSurfaceFrame(
            browserFrame: authored, browserID: "browserpro.browser", parentID: "centro.browser",
            parentFrame: parent, usesSkinToolbar: true), authored)
        XCTAssertTrue(WinampModernMainView.suppressesHostLocationBar(
            browserID: "browserpro.browser", parentID: "centro.browser", usesSkinToolbar: true))
    }

    /// Every other browser keeps its authored box and our chrome in **both** states: a skin that
    /// merely puts a button near a browser has not built an address bar, and losing ours would leave
    /// it with no way to navigate at all.
    func testOtherBrowsersAreUnaffectedInEitherState() {
        let authored = CGRect(x: 20, y: 43, width: 500, height: 300)
        let parent = CGRect(x: 20, y: 5, width: 500, height: 338)

        for uses in [false, true] {
            XCTAssertEqual(WinampModernMainView.browserSurfaceFrame(
                browserFrame: authored, browserID: "some.browser", parentID: "some.group",
                parentFrame: parent, usesSkinToolbar: uses), authored)
            XCTAssertFalse(WinampModernMainView.suppressesHostLocationBar(
                browserID: "browserpro.browser", parentID: "some.group", usesSkinToolbar: uses))
            XCTAssertFalse(WinampModernMainView.suppressesHostLocationBar(
                browserID: "some.browser", parentID: "centro.browser", usesSkinToolbar: uses))
            XCTAssertFalse(WinampModernMainView.suppressesHostLocationBar(
                browserID: nil, parentID: nil, usesSkinToolbar: uses))
        }
    }

    func testSuppressedLocationBarGivesTheWebViewTheWholeBox() {
        let surface = WinampModernBrowserSurfaceView(
            frame: NSRect(x: 0, y: 0, width: 600, height: 400), vfs: nil)
        surface.setShowsLocationBar(false)
        surface.layoutSubtreeIfNeeded()

        let webView = surface.subviews.compactMap { $0 as? WKWebView }.first
        XCTAssertEqual(webView?.frame.height, surface.bounds.height)
        let bar = surface.subviews.first { $0.subviews.contains(where: { $0 is NSSearchField }) }
        XCTAssertEqual(bar?.isHidden, true)
    }

    func testRemoteHTTPAndHTTPSAreAllowed() {
        for address in ["https://example.com/path", "http://example.com/legacy"] {
            let request = WinampModernBrowserRequest(address: address,
                                                     sourceLogicalPath: "/Skins/Test/xml/player.xml")
            guard case .url(let url) = WinampModernBrowserSurfaceView.destination(for: request, vfs: nil)
            else { return XCTFail("expected a remote URL") }
            XCTAssertEqual(url.absoluteString, address)
        }
    }

    func testDangerousSchemesAreBlocked() {
        for address in ["file:///etc/passwd", "javascript:alert(1)", "data:text/html,nope",
                        "nullplayer://open", "https:relative-without-a-host"] {
            let request = WinampModernBrowserRequest(address: address,
                                                     sourceLogicalPath: "/Skins/Test/xml/player.xml")
            guard case .blocked = WinampModernBrowserSurfaceView.destination(for: request, vfs: nil)
            else { return XCTFail("expected \(address) to be blocked") }
        }
    }

    func testNavigationPolicyRejectsDownloadsAndForgedInternalURLs() throws {
        XCTAssertTrue(WinampModernBrowserSurfaceView.allowsNavigation(
            to: try XCTUnwrap(URL(string: "https://example.com/page")),
            shouldPerformDownload: false
        ))
        XCTAssertFalse(WinampModernBrowserSurfaceView.allowsNavigation(
            to: try XCTUnwrap(URL(string: "https://example.com/archive.zip")),
            shouldPerformDownload: true
        ))

        for address in [
            "wal-skin-resource://attacker/Skins/Test/html/home.htm",
            "wal-skin-resource://user:password@resource/Skins/Test/html/home.htm",
            "wal-skin-resource://resource:443/Skins/Test/html/home.htm",
            "about:config",
            "https:relative-without-a-host",
            "file:///etc/passwd",
        ] {
            let url = try XCTUnwrap(URL(string: address))
            XCTAssertFalse(WinampModernBrowserSurfaceView.isAllowed(url: url), address)
        }

        let admitted = try XCTUnwrap(URL(
            string: "wal-skin-resource://resource/Skins/Test/html/home.htm?theme=dark#section"
        ))
        XCTAssertTrue(WinampModernBrowserSurfaceView.isAllowed(url: admitted))
        XCTAssertTrue(WinampModernBrowserSurfaceView.isAllowed(
            url: try XCTUnwrap(URL(string: "about:blank"))
        ))
    }

    func testWebKitConfigurationIsEphemeralAndMediaPlaybackRequiresUserAction() {
        let configuration = WinampModernBrowserSurfaceView.makeConfiguration(vfs: nil)

        XCTAssertFalse(configuration.websiteDataStore.isPersistent)
        XCTAssertEqual(configuration.mediaTypesRequiringUserActionForPlayback, .all)
        XCTAssertTrue(configuration.defaultWebpagePreferences.allowsContentJavaScript)
    }

    func testSkinLocalPageResolvesThroughVFS() throws {
        let provider = try WalMemoryResourceProvider(resources: [
            "xml/player.xml": Data(),
            "html/home.htm": Data("hello".utf8),
        ])
        let vfs = try WalVirtualFileSystem(skinName: "Test", skin: provider)
        let request = WinampModernBrowserRequest(address: "../html/home.htm",
                                                 sourceLogicalPath: "/Skins/Test/xml/player.xml")
        guard case .url(let url) = WinampModernBrowserSurfaceView.destination(for: request, vfs: vfs)
        else { return XCTFail("expected a VFS URL") }
        XCTAssertEqual(url.scheme, WinampModernBrowserSurfaceView.localScheme)
        XCTAssertEqual(url.host, "resource")
        XCTAssertEqual(url.path, "/Skins/Test/html/home.htm")
    }

    func testSkinLocalResolutionCannotEscapeTheVFSOrForgeThePrivateScheme() throws {
        let provider = try WalMemoryResourceProvider(resources: [
            "xml/player.xml": Data(),
            "html/home.htm": Data("hello".utf8),
        ])
        let vfs = try WalVirtualFileSystem(skinName: "Test", skin: provider)

        for address in [
            "../../../../etc/passwd",
            "/etc/passwd",
            "~/Library/Preferences/secret.plist",
            "file:///etc/passwd",
            "wal-skin-resource://resource/Skins/Test/html/home.htm",
        ] {
            let request = WinampModernBrowserRequest(
                address: address,
                sourceLogicalPath: "/Skins/Test/xml/player.xml"
            )
            guard case .blocked = WinampModernBrowserSurfaceView.destination(for: request, vfs: vfs)
            else { return XCTFail("expected \(address) to be blocked") }
        }
    }

    func testLocalResourceLimitIsStrictlyBounded() {
        XCTAssertEqual(WinampModernBrowserSurfaceView.maximumLocalResourceBytes, 16 * 1_024 * 1_024)
        XCTAssertTrue(WinampModernBrowserSurfaceView.allowsLocalResource(byteCount: 0))
        XCTAssertTrue(WinampModernBrowserSurfaceView.allowsLocalResource(
            byteCount: WinampModernBrowserSurfaceView.maximumLocalResourceBytes
        ))
        XCTAssertFalse(WinampModernBrowserSurfaceView.allowsLocalResource(
            byteCount: WinampModernBrowserSurfaceView.maximumLocalResourceBytes + 1
        ))
        XCTAssertFalse(WinampModernBrowserSurfaceView.allowsLocalResource(byteCount: -1))
    }

    func testBlankAddressGetsBrowserHome() {
        let request = WinampModernBrowserRequest(address: "about:blank",
                                                 sourceLogicalPath: "/Skins/Test/skin.xml")
        XCTAssertEqual(WinampModernBrowserSurfaceView.destination(for: request, vfs: nil), .home)
    }

    func testUserInputRecognizesAddressAndSearch() {
        XCTAssertEqual(WinampModernBrowserSurfaceView.userURL(for: "example.com")?.absoluteString,
                       "https://example.com")
        let search = WinampModernBrowserSurfaceView.userURL(for: "internet radio stations")
        XCTAssertEqual(search?.host, "duckduckgo.com")
        XCTAssertEqual(URLComponents(url: search!, resolvingAgainstBaseURL: false)?.queryItems,
                       [URLQueryItem(name: "q", value: "internet radio stations")])
    }

    func testUnsafeUserInputBecomesHTTPSearchInsteadOfExecutableNavigation() throws {
        for input in ["javascript:alert(1)", "file:///tmp/private.txt", "data:text/html,owned",
                      "nullplayer://open/settings"] {
            let url = try XCTUnwrap(WinampModernBrowserSurfaceView.userURL(for: input))
            XCTAssertEqual(url.scheme, "https", input)
            XCTAssertEqual(url.host, "duckduckgo.com", input)
            XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "q" })?.value, input)
        }
    }
}
