import AppKit
import Foundation
@preconcurrency import WebKit

/// A real, policy-gated implementation of Winamp's `<Browser>` / `<Winamp:Browser>` control.
///
/// Remote pages run in WebKit's content process with an ephemeral data store. Skin-local pages are
/// served from `WalVirtualFileSystem` through a private URL scheme; neither WebKit nor a skin script
/// ever receives a host filesystem URL.
@MainActor
final class WinampModernBrowserSurfaceView: NSView, WinampModernBrowserSurface,
                                                   WKNavigationDelegate, WKUIDelegate,
                                                   NSTextFieldDelegate {
    static let localScheme = "wal-skin-resource"
    static let maximumLocalResourceBytes = 16 * 1_024 * 1_024

    private let webView: WinampModernBrowserWebView
    private let locationBar = NSView(frame: .zero)
    private let locationField = NSTextField(frame: .zero)
    private var pendingRequest: WinampModernBrowserRequest?
    private var isSurfaceVisible = false
    private var isTornDown = false

    var view: NSView { self }

    init(frame: NSRect, vfs: WalVirtualFileSystem?) {
        let configuration = Self.makeConfiguration(vfs: vfs)
        webView = WinampModernBrowserWebView(frame: frame, configuration: configuration)
        super.init(frame: frame)
        autoresizesSubviews = true
        isHidden = true

        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsLinkPreview = false
        webView.browserOwner = self
        webView.skinVFS = vfs
        addSubview(webView)

        locationBar.wantsLayer = true
        locationBar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        locationBar.layer?.borderColor = NSColor.separatorColor.cgColor
        locationBar.layer?.borderWidth = 1
        locationBar.isHidden = true
        addSubview(locationBar)

        locationField.placeholderString = "Search or enter website"
        locationField.delegate = self
        locationField.font = .systemFont(ofSize: 13)
        locationField.focusRingType = .default
        locationBar.addSubview(locationField)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        webView.frame = bounds
        let barHeight: CGFloat = 34
        locationBar.frame = NSRect(x: 0, y: max(0, bounds.height - barHeight),
                                   width: bounds.width, height: min(barHeight, bounds.height))
        locationField.frame = locationBar.bounds.insetBy(dx: 6, dy: 5)
    }

    func navigate(_ request: WinampModernBrowserRequest) {
        guard !isTornDown else { return }
        pendingRequest = request
        loadPendingRequestIfReady()
    }

    func setVisible(_ visible: Bool) {
        guard !isTornDown else { return }
        isSurfaceVisible = visible
        isHidden = !visible
        if visible { loadPendingRequestIfReady() }
    }

    /// The holder frame is already scaled by `WinampModernMainView`; WebKit content remains at the
    /// platform's normal CSS-pixel scale instead of receiving the skin scale a second time.
    func applySkinScale(_ scale: CGFloat) {}

    func unmountFromHolder() {
        isSurfaceVisible = false
        isHidden = true
        removeFromSuperview()
    }

    func prepareForUITeardown() {
        guard !isTornDown else { return }
        isTornDown = true
        pendingRequest = nil
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.browserOwner = nil
        removeFromSuperview()
    }

    private func loadPendingRequestIfReady() {
        guard isSurfaceVisible, bounds.width > 0, bounds.height > 0,
              let request = pendingRequest else { return }
        pendingRequest = nil
        switch Self.destination(for: request, vfs: webView.skinVFS) {
        case .url(let url):
            webView.load(URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData,
                                    timeoutInterval: 30))
        case .home:
            loadHomePage()
        case .blocked(let message):
            loadMessagePage(title: "Page blocked", message: message)
        }
    }

    // MARK: User navigation and search

    @objc func presentLocationField() {
        guard !isTornDown else { return }
        locationField.stringValue = webView.url?.absoluteString ?? ""
        locationBar.isHidden = false
        needsLayout = true
        window?.makeFirstResponder(locationField)
        locationField.currentEditor()?.selectAll(nil)
    }

    @objc func openCurrentPageInDefaultBrowser() {
        guard let url = webView.url, Self.isAllowed(url: url),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc func goBack() { if webView.canGoBack { webView.goBack() } }
    @objc func goForward() { if webView.canGoForward { webView.goForward() } }
    @objc func reloadPage() { webView.reload() }
    @objc func stopLoadingPage() { webView.stopLoading() }

    func control(_ control: NSControl, textView: NSTextView,
                 doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            submitLocationField()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            dismissLocationField()
            return true
        }
        return false
    }

    private func submitLocationField() {
        let input = locationField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        dismissLocationField()
        guard !input.isEmpty else { return }
        if let url = Self.userURL(for: input) {
            webView.load(URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData,
                                    timeoutInterval: 30))
        }
    }

    private func dismissLocationField() {
        locationBar.isHidden = true
        window?.makeFirstResponder(webView)
    }

    private func loadHomePage() {
        let html = """
        <!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width">
        <style>html,body{height:100%;margin:0}body{display:grid;place-items:center;background:#171717;color:#eee;font:14px -apple-system;padding:24px;box-sizing:border-box}form{width:min(34rem,100%)}input{box-sizing:border-box;width:100%;padding:11px 13px;border:1px solid #666;border-radius:7px;background:#262626;color:white;font:inherit}p{text-align:center;color:#aaa}</style>
        <form action="https://duckduckgo.com/" method="get"><input name="q" autofocus placeholder="Search the web"><p>Search, or press ⌘L to enter an address</p></form>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    private func loadMessagePage(title: String, message: String) {
        let safeTitle = Self.escapeHTML(title)
        let safeMessage = Self.escapeHTML(message)
        let html = """
        <!doctype html><meta charset="utf-8"><style>body{background:#171717;color:#eee;font:14px -apple-system;padding:24px}p{color:#bbb;line-height:1.5}</style><h3>\(safeTitle)</h3><p>\(safeMessage)</p>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    // MARK: Navigation policy

    static func makeConfiguration(vfs: WalVirtualFileSystem?) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        if let vfs {
            configuration.setURLSchemeHandler(WinampModernBrowserSchemeHandler(vfs: vfs),
                                              forURLScheme: localScheme)
        }
        return configuration
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url,
              Self.allowsNavigation(to: url,
                                    shouldPerformDownload: navigationAction.shouldPerformDownload) else {
            decisionHandler(.cancel)
            return
        }
        // A target=_blank link stays in the skin's one browser box; it never creates an unowned
        // WebKit window over the player.
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url,
           Self.allowsNavigation(to: url,
                                 shouldPerformDownload: navigationAction.shouldPerformDownload) {
            webView.load(navigationAction.request)
        }
        return nil
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        // Never let untrusted skin-selected content promote WebKit's default `.prompt` into access
        // to the microphone or camera. There is intentionally no per-skin permission persistence.
        decisionHandler(.deny)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else { return }
        loadMessagePage(title: "Page unavailable", message: error.localizedDescription)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    // MARK: Address resolution

    enum Destination: Equatable {
        case url(URL)
        case home
        case blocked(String)
    }

    static func destination(for request: WinampModernBrowserRequest,
                            vfs: WalVirtualFileSystem?) -> Destination {
        let address = request.address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty, address.lowercased() != "about:blank" else { return .home }

        if let url = URL(string: address), let scheme = url.scheme {
            guard ["http", "https"].contains(scheme.lowercased()) else {
                return .blocked("The skin requested an unsupported URL scheme: \(scheme).")
            }
            return isAllowed(url: url)
                ? .url(url)
                : .blocked("The skin requested a malformed web address.")
        }

        guard let vfs else { return .blocked("This skin-local page is unavailable.") }
        do {
            let resource = try vfs.resolve(address, relativeTo: request.sourceLogicalPath)
            var components = URLComponents()
            components.scheme = localScheme
            components.host = "resource"
            components.path = resource.logicalPath
            guard let url = components.url else { return .blocked("The skin-local URL is malformed.") }
            return .url(url)
        } catch {
            return .blocked("The skin-local page could not be found.")
        }
    }

    static func userURL(for input: String) -> URL? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: value), url.scheme != nil {
            if isAllowed(url: url), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                return url
            }
            return searchURL(for: value)
        }
        if !value.contains(where: { $0.isWhitespace }), value.contains("."),
           let url = URL(string: "https://" + value), isAllowed(url: url) { return url }
        return searchURL(for: value)
    }

    private static func searchURL(for value: String) -> URL? {
        var components = URLComponents(string: "https://duckduckgo.com/")
        components?.queryItems = [URLQueryItem(name: "q", value: value)]
        return components?.url
    }

    static func isAllowed(url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        switch scheme {
        case "http", "https":
            return !(url.host?.isEmpty ?? true)
        case localScheme:
            return url.host?.lowercased() == "resource"
                && url.user == nil && url.password == nil && url.port == nil
                && url.path.hasPrefix("/")
        case "about":
            return url.absoluteString == "about:blank"
        default:
            return false
        }
    }

    static func allowsNavigation(to url: URL, shouldPerformDownload: Bool) -> Bool {
        !shouldPerformDownload && isAllowed(url: url)
    }

    static func allowsLocalResource(byteCount: Int) -> Bool {
        byteCount >= 0 && byteCount <= maximumLocalResourceBytes
    }

    private static func escapeHTML(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

@MainActor
private final class WinampModernBrowserWebView: WKWebView {
    weak var browserOwner: WinampModernBrowserSurfaceView?
    weak var skinVFS: WalVirtualFileSystem?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "l" {
            browserOwner?.presentLocationField()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        menu.addItem(.separator())
        for (title, action, enabled) in [
            ("Back", #selector(WinampModernBrowserSurfaceView.goBack), canGoBack),
            ("Forward", #selector(WinampModernBrowserSurfaceView.goForward), canGoForward),
            ("Reload", #selector(WinampModernBrowserSurfaceView.reloadPage), true),
            ("Stop", #selector(WinampModernBrowserSurfaceView.stopLoadingPage), isLoading),
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = browserOwner
            item.isEnabled = enabled
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let location = NSMenuItem(title: "Search or Enter Address…",
                                  action: #selector(WinampModernBrowserSurfaceView.presentLocationField),
                                  keyEquivalent: "l")
        location.keyEquivalentModifierMask = [.command]
        location.target = browserOwner
        menu.addItem(location)
        if let url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            let external = NSMenuItem(title: "Open Page in Default Browser",
                                      action: #selector(WinampModernBrowserSurfaceView.openCurrentPageInDefaultBrowser),
                                      keyEquivalent: "")
            external.target = browserOwner
            menu.addItem(external)
        }
        return menu
    }
}

/// Read-only WebKit adapter for resources already admitted to the WAL VFS.
@MainActor
private final class WinampModernBrowserSchemeHandler: NSObject, WKURLSchemeHandler {
    private let vfs: WalVirtualFileSystem

    init(vfs: WalVirtualFileSystem) { self.vfs = vfs }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              WinampModernBrowserSurfaceView.isAllowed(url: url),
              url.scheme?.lowercased() == WinampModernBrowserSurfaceView.localScheme else {
            urlSchemeTask.didFailWithError(URLError(.unsupportedURL))
            return
        }
        do {
            let data = try vfs.data(at: url.path)
            guard WinampModernBrowserSurfaceView.allowsLocalResource(byteCount: data.count) else {
                urlSchemeTask.didFailWithError(URLError(.dataLengthExceedsMaximum))
                return
            }
            let response = URLResponse(url: url, mimeType: Self.mimeType(for: url.path),
                                       expectedContentLength: data.count,
                                       textEncodingName: Self.isText(path: url.path) ? "utf-8" : nil)
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private static func mimeType(for path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "html", "htm": return "text/html"
        case "css": return "text/css"
        case "js", "mjs": return "text/javascript"
        case "json": return "application/json"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "webp": return "image/webp"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "ttf": return "font/ttf"
        default: return "application/octet-stream"
        }
    }

    private static func isText(path: String) -> Bool {
        ["html", "htm", "css", "js", "mjs", "json", "svg"]
            .contains((path as NSString).pathExtension.lowercased())
    }
}
