import Foundation

/// Where a skin's *global* navigation request is meant to end up.
///
/// Winamp's two `System` methods are not two spellings of one thing: `navigateUrl` is "hand this to
/// the user's browser" and `navigateUrlBrowser` is "put this in the player's own browser". Skins
/// that expose the choice as a setting branch on it themselves and then call the matching method —
/// Big Bento Modern's Web Content page offers *Use Default Browser to open links* against a *Web
/// Reader (Internal Browser)*, and `fileinfo_lyrics_finder.maki` reads that attribute and calls
/// `navigateUrl` on one side of the `if` and `sendAction("browser_search", url)` on the other. So the
/// host does not need to read the skin's setting: honouring it *is* answering both routes.
enum WinampModernWebNavigationTarget: Equatable {
    /// `System.navigateUrl` — the user's default browser, behind the confirmation below.
    case defaultBrowser
    /// `System.navigateUrlBrowser` and the `browser_navigate` action — the skin's own embedded
    /// `<browser>` surface, with an address the skin has already assembled in full.
    case internalBrowser
    /// The `browser_search` action, whose parameter is **not an address**: it is the bare search
    /// terms, and the reader is expected to put them through whichever engine the skin's settings
    /// name. Measured, not assumed — `fileinfo_lyrics_finder.maki` sends
    /// `urlEncode(artist) + " " + urlEncode(title) + " lyrics"` here while its `browser_navigate`
    /// call sites (the album-cover and YouTube searches, and a stream's `streamurl`) all send a
    /// complete `https://…` URL. Reading the two the same way turned a search into `https://<terms>`.
    case internalBrowserSearch
}

/// The policy every skin-authored address passes through before anything opens it (B40).
///
/// A `.wal` skin is untrusted input, so this is deliberately narrower than the address bar the user
/// types into: HTTP and HTTPS only, a real host required, and no other scheme accepted — a skin must
/// not be able to reach `file:`, `javascript:` or an application scheme through a request the host
/// itself performs. It is pure and lives beside the engine rather than in the window layer so both
/// routes and their tests share exactly one decision.
enum WinampModernWebNavigationPolicy {
    enum Resolution: Equatable {
        case allow(URL)
        case blocked(String)
    }

    /// The characters left alone while the address is repaired. Skins concatenate their query out of
    /// `urlEncode()`d terms and **literal spaces** (`"…/search?q=" + artist + " " + title + " lyrics"`),
    /// so the string that arrives is usually not a legal URL — but it already carries `%XX` escapes,
    /// which is why `%` has to survive the pass. Encoding it again turns Bento's `%20` into `%2520`
    /// and searches for the escape rather than for the song.
    private static let preserved = CharacterSet.urlQueryAllowed.union(CharacterSet(charactersIn: "%#"))

    static func resolve(address: String) -> Resolution {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .blocked("The skin asked to open an empty address.") }
        let repaired = trimmed.addingPercentEncoding(withAllowedCharacters: preserved) ?? trimmed
        var candidate = repaired
        let lower = repaired.lowercased()
        if !lower.hasPrefix("http://"), !lower.hasPrefix("https://") {
            // A scheme we do not serve is refused rather than rewritten; only a bare host — which is
            // how most skins spell it (`www.google.com/search?q=…`) — is promoted to HTTPS.
            guard !repaired.contains("://"), !lower.hasPrefix("javascript:"), !lower.hasPrefix("data:"),
                  !lower.hasPrefix("about:"), !lower.hasPrefix("file:") else {
                return .blocked("The skin requested an unsupported URL scheme.")
            }
            candidate = "https://" + repaired
        }
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else {
            return .blocked("The skin requested a malformed web address.")
        }
        return .allow(url)
    }

    // MARK: - A search, rather than an address

    enum SearchEngine: String, Equatable {
        case google, bing, duckDuckGo

        var endpoint: String {
            switch self {
            case .google: return "https://www.google.com/search"
            case .bing: return "https://www.bing.com/search"
            case .duckDuckGo: return "https://duckduckgo.com/"
            }
        }
    }

    /// Turn `browser_search`'s terms into a real query URL.
    ///
    /// The terms arrive **already percent-encoded a term at a time** — the skin writes
    /// `urlEncode(artist) + " " + urlEncode(title)` — so they are decoded once before being encoded
    /// again as a whole. Skipping that searches for the escape: Björk comes through as
    /// `Bj%25C3%25B6rk`, and every space between the terms as a literal `%2520`.
    static func searchURL(terms: String, engine: SearchEngine) -> URL? {
        let decoded = terms.removingPercentEncoding ?? terms
        let trimmed = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var components = URLComponents(string: engine.endpoint)
        components?.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        return components?.url
    }

    /// Which engine the *skin* asked for, from the options it registered with `newAttribute`.
    ///
    /// Big Bento's Web Content page offers `Default Search Engine: Google` (default `1`) against
    /// `Default Search Engine: Bing`, so the choice is the user's and it is already stored — the same
    /// shape as the internal/external choice this whole route exists to honour. A skin that registers
    /// no such option gets DuckDuckGo, which is what the internal browser's own start page searches,
    /// so the two never disagree.
    static func preferredSearchEngine(settings: [(name: String, value: String)]) -> SearchEngine {
        let prefix = "default search engine:"
        for setting in settings {
            let name = setting.name.lowercased().trimmingCharacters(in: .whitespaces)
            guard name.hasPrefix(prefix), setting.value.trimmingCharacters(in: .whitespaces) == "1" else {
                continue
            }
            switch name.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces) {
            case "google": return .google
            case "bing": return .bing
            case "duckduckgo", "duck duck go": return .duckDuckGo
            default: continue
            }
        }
        return .duckDuckGo
    }

    // MARK: - Consent for the external route

    /// Where the answer to "yes, this skin may use my browser" is kept. The configuration is already
    /// namespaced per skin, so one skin's answer never speaks for another's.
    static let section = "@nullplayer.web"
    static let defaultBrowserConsentKey = "allowDefaultBrowser"

    static func allowsDefaultBrowser(in configuration: WinampModernConfiguration) -> Bool {
        configuration.integer(section: section, key: defaultBrowserConsentKey) == 1
    }

    static func setAllowsDefaultBrowser(_ allowed: Bool, in configuration: WinampModernConfiguration) {
        configuration.setInteger(allowed ? 1 : 0, section: section, key: defaultBrowserConsentKey)
    }
}
