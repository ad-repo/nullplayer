## `<browser>` — embedded WebKit browser

A `<browser>` element in a `.wal` skin hosts a real `WKWebView`. It is a completely separate
lifecycle from the component holder system — `<browser>` is NOT added to `isHolderElement` (doing so
breaks fills and hit tests). Each instance has an ephemeral website data store, so cookies, caches,
and local storage do not persist across a skin session.

The allowed navigation surface is deliberately narrow: HTTP and HTTPS are accepted; skin-local HTML,
CSS, script, image and font resources are served from `WalVirtualFileSystem` through the private
`wal-skin-resource:` scheme; `file:`, `javascript:`, `data:`, downloads, popup windows, and
application URL schemes are rejected. An allowed popup navigation is kept inside the same browser
surface. The browser exposes no JavaScript-to-native message bridge. `command-L` and
the WebKit context menu focus a host-owned search/address field that remains visible above the page;
non-address text searches DuckDuckGo.
The user may explicitly open the current HTTP(S) page in the default browser from that menu.

Initial navigation accepts Wasabi's two markup forms: a non-empty `url=` wins, then `home=` is the
fallback used by ClassicPro's `<Winamp:Browser>`. With neither, the surface opens NullPlayer's local
search/start page. This selection happens before lazy loading, so a hidden or zero-sized browser still
makes no request until it becomes visible. Both provisional and post-commit navigation failures show
the compact *Page unavailable* screen; handling only the former leaves WebKit's default white page
when an old server accepts a connection and then returns no response.

Security policy is centralized and headlessly tested in `WinampModernBrowserTests`: WebKit uses a
nonpersistent data store, media autoplay requires a user gesture, downloads are denied, and camera
and microphone requests are always denied. Only the exact internally-generated
`wal-skin-resource://resource/…` shape is admitted, with each response capped at 16 MiB. A skin cannot
forge that scheme through XML or MAKI; initial addresses accept only HTTP(S), while local paths must
resolve inside the read-only WAL VFS. Host paths, traversal, credentials/ports on the private origin,
and unsafe address-bar schemes are covered by synthetic tests. `System.navigateUrl` and calls on
non-browser objects never reach the surface.

### The typeName trap

The XML element is `<Browser>` in most skins (Defix, Bio-Nid, Itemskin, etc.) but ClassicPro engine
skins (cPro-Bento) use `<Winamp:Browser>`. The object graph stores the typeName as-is from the XML,
so cPro-Bento's browser object has `typeName = "Winamp:Browser"`, not `"Browser"`.
`WasabiSceneRenderer.isBrowserElement()` matches both: `browser` and `winamp:browser`
(case-insensitive). **This was the root cause of six failed attempts** — every approach that checked
only for `typeName == "browser"` silently missed cPro-Bento's browser element, and cPro-Bento was
the primary test skin.

### Why `layoutNodes()`, not `sceneNodes()`

Browser elements are typically inside a tab group that starts `visible="0"` (cPro-Bento's
`centro.browser`, Defix's `wdh.browser`). A MAKI script toggles visibility when the user clicks the
tab button. `sceneNodes()` filters by visibility — so a browser inside a hidden tab never appears in
it until the tab is first shown. If surfaces were only created from `sceneNodes()`, the first tab
switch would find no surface, and the layout would run before any surface existed.

`browserNodes()` uses `layoutNodes()` (which includes hidden elements) to discover ALL browser
elements eagerly and create surfaces for all of them at first layout. Each surface's
`view.isHidden` tracks whether the element is currently visible in `sceneNodes()`, so the surface
is ready the moment the tab becomes visible.

### Independent surfaces and lazy loading

Each `<browser>` gets its own **non-cached** `WinampModernBrowserSurface` via
`componentHost.makeBrowserSurface()`. This is deliberate:

- Browser history and page state belong to the individual browser object, not to the Media Library
  component or another browser tab.
- The view layer owns the surfaces in a
  `browserSurfaces: [WasabiObjectID: WinampModernBrowserSurface]` dictionary and tears them down with
  the skin runtime.
- Browser objects inside hidden tab groups are discovered eagerly so they can receive early MAKI
  navigation, but no page is loaded until the object is visible with a nonzero frame.
- `<browser>.navigateUrl(url)` routes by `WasabiObjectID` to that surface. A request during
  `onScriptLoaded` is buffered until the first layout. The global `System.navigateUrl` methods remain
  denied.

### When a skin draws duplicate browser chrome (BB25)

The four Big Bento Modern variants inherit a reader where `browserpro.browser` begins 38 pixels
below its `centro.browser` parent. The gap contains a Winamp-owned navigation toolbar whose buttons
have no compatible browser backend in NullPlayer. Exposing it above NullPlayer's host-owned address
field produces two toolbars, with the upper one inert.

Do not patch or normalize the skin to remove that row. `WinampModernMainView` recognizes the exact
`centro.browser` / `browserpro.browser` structure and mounts its WebKit surface over the parent's
resolved frame. The host address field therefore occupies the toolbar strip and the web content
stays aligned with the skin's authored browser area. Every other browser surface keeps the frame its
skin authored. `WinampModernBrowserTests` pins both sides of that exception.

### The four routes a skin reaches the web by (B40)

A skin's web-facing buttons do **not** all go through the `<browser>` object, and reading them as one
thing is what left "some buttons do nothing" open for a phase. There are four routes and each needed
its own answer:

| Route | What it means | Where it lands |
|---|---|---|
| `<browser>.navigateUrl(url)` | that object's own surface | `browserNavigationRequested` → `WinampModernMainView.navigateBrowser` |
| `System.navigateUrl(url)` | **the user's default browser** — Winamp's meaning, not a synonym for the next row | policy → confirmation sheet → `NSWorkspace` |
| `System.navigateUrlBrowser(url)` | the *player's* browser | the scene's `<browser>`, visible one preferred |
| `sendAction("browser_navigate"/"browser_search", …)` | a skin's own reader, addressed as an action | the skin's script, and the host only if nothing answered |

Three traps live in that table, all of them measured on Big Bento Modern:

- **A scheme-less address is a web address, not a skin-local path.** Winamp readers write
  `www.google.com/search?q=<terms>` with no scheme and hand it to `<browser>.navigateUrl`. Everything
  after the scheme check in `destination(for:)` treats an address as a path inside the WAL VFS, where
  a hostname can only ever be missing — so the page came back *"The skin-local page could not be
  found"* and the search never reached WebKit. A host-shaped head (dotted labels, plausible TLD, not
  a resource extension — `looksLikeWebAddress`) is repaired to HTTPS through
  `WinampModernWebNavigationPolicy`; `reader_providers.xml` and `backgrounds/start.html` still
  resolve locally.
- **`browser_search` carries *terms*; `browser_navigate` carries a *URL*.** Bento's lyrics button
  sends `urlEncode(artist) + " " + urlEncode(title) + " lyrics"`, while its YouTube, album-cover and
  stream buttons send a complete `https://…`. Reading both as addresses turns a search into
  `https://<terms>`. Terms are **decoded once** before being re-encoded (the skin encodes each term
  itself, so encoding again searches for `%2520`), and the engine comes from the skin's own
  `Default Search Engine: Google` / `Bing` registration, DuckDuckGo when it registers neither.
- **A skin with a reader answers those two actions itself**, building the URL from its own engine
  setting and navigating its `<browser>`. The host route is therefore a **fallback**, taken only when
  no script handled the action — otherwise the same surface is loaded twice, the second time with a
  URL the skin did not choose.

The **external** route is the only place a `.wal` skin reaches `NSWorkspace`, and it is gated: the
address is untrusted markup, so the first request raises a sheet (Open / Always Allow / Cancel)
naming the URL, "always" is stored per skin in its own namespaced configuration, and one question is
outstanding at a time so a script on a timer cannot stack alerts. Never `runModal()` — a modal loop a
skin can enter at will is a hang the user cannot escape.

**Whose setting decides internal vs external?** The skin's, and it does not need asking: Bento's Web
Content page offers *Use Default Browser to open links* (its own default, `1`) against *Use internal
Web Reader*, and its scripts read that attribute and call `navigateUrl` on one branch and
`sendAction` on the other. Honouring the setting **is** answering both routes.

One thing the internal route deliberately does not do: it navigates the browser but does not open the
tab the browser sits in. A request for a browser in a closed tab waits in that surface (the same
buffering an early `onScriptLoaded` navigation gets) rather than driving the skin's own tab
bookkeeping from outside.

### The `SC:UpdateSystem` browser

cPro-Bento also has `<browser id="brw">` inside an `SC:UpdateSystem` XUI widget in the main
container. This is Winamp's update-check widget, not a content tab. It creates a browser surface but
does not load while it remains offscreen, hidden, or zero-sized.

### Files

- `WasabiRenderer.swift` — `isBrowserElement()`, `browserNodes()`, `isBrowserVisible()`
- `WinampModernComponents.swift` — `makeBrowserSurface()` protocol method
- `WinampModernComponentBridge.swift` — `makeBrowserSurface()` implementation (non-cached)
- `WinampModernBrowserSurfaceView.swift` — WebKit policy, search/address UI, VFS scheme handler,
  `looksLikeWebAddress` (the scheme-less repair)
- `WinampModernWebNavigation.swift` — the shared address policy, the search-URL builder, the engine
  the skin asked for, and where the external-route consent is stored (B40)
- `WinampModernMainView.swift` — `browserSurfaces`, `reconcileBrowserSurfaces()`,
  `layoutHostedSubviews(browsers:)`, `globalBrowserTarget()`, the `BROWSER_*` actions
- `WinampModernMainWindowController.swift` — `routeWebNavigation`, `navigateInternalBrowser`,
  `openInDefaultBrowser` (the confirmation sheet)
- `WinampModernScriptRuntime.swift` — object-scoped `navigateUrl`, the two global forms, `urlEncode`,
  and the `sendAction` fallback rule

