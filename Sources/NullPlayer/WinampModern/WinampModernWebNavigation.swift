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

/// The `.wal` half of web navigation: searches, the search engine a skin prefers, and where its
/// "Always Allow" lives. The address policy and the consent sheet every skin shares are
/// `SkinExternalLink`'s (B40).
enum WinampModernWebNavigationPolicy {
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
