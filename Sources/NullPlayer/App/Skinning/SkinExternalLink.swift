import AppKit

/// **The one route by which a skin opens a link in the user's browser** — `.wal`'s `navigateUrl`
/// and `.wmz`'s `player.launchURL` both end here.
///
/// A skin is untrusted input, so two gates stand between its markup and `NSWorkspace`: the
/// address policy (`resolve`), and a first-use confirmation that shows the user the address. Each
/// family keeps the "Always Allow" answer in its own per-skin store and hands it in as `Consent`,
/// so one skin's answer never speaks for another's.
@MainActor
enum SkinExternalLink {
    enum Resolution: Equatable {
        case allow(URL)
        case blocked(String)
    }

    /// A skin's remembered "Always Allow".
    struct Consent {
        let isGranted: () -> Bool
        let grant: () -> Void
    }

    /// One question at a time. The address is skin-authored and a script may navigate from a
    /// timer, so without this a skin could stack alerts over the player faster than they can be
    /// dismissed. A request that arrives while the sheet is up is dropped, not queued.
    private static var isAsking = false

    /// Opens `url`, asking first unless the skin was always allowed. Presented as a sheet, never
    /// `runModal()` — a modal loop a skin can enter at will is a hang the user cannot escape — so
    /// with no window the request is simply inert.
    static func open(_ url: URL, skinName: String, consent: Consent, over window: NSWindow?) {
        if consent.isGranted() {
            NSWorkspace.shared.open(url)
            return
        }
        guard let window, !isAsking else { return }
        isAsking = true
        let alert = NSAlert()
        alert.messageText = "Open this link in your default browser?"
        alert.informativeText = "The skin “\(skinName)” wants to open:\n\(url.absoluteString)"
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Always Allow")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            isAsking = false
            switch response {
            case .alertFirstButtonReturn:
                NSWorkspace.shared.open(url)
            case .alertSecondButtonReturn:
                consent.grant()
                NSWorkspace.shared.open(url)
            default:
                break
            }
        }
    }

    // MARK: - Address policy (B40)

    /// The characters left alone while the address is repaired. Skins concatenate their query out of
    /// `urlEncode()`d terms and **literal spaces** (`"…/search?q=" + artist + " " + title + " lyrics"`),
    /// so the string that arrives is usually not a legal URL — but it already carries `%XX` escapes,
    /// which is why `%` has to survive the pass. Encoding it again turns Bento's `%20` into `%2520`
    /// and searches for the escape rather than for the song. `[` `]` stay for an IPv6 literal host.
    private nonisolated static let preserved = CharacterSet.urlQueryAllowed.union(CharacterSet(charactersIn: "%#[]"))

    /// Deliberately narrower than the address bar the user types into: HTTP and HTTPS only, a real
    /// host required, and no other scheme accepted — a skin must not be able to reach `file:`,
    /// `javascript:` or an application scheme through a request the host itself performs.
    nonisolated static func resolve(address: String) -> Resolution {
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
              let host = url.host, isHostname(host) else {
            return .blocked("The skin requested a malformed web address.")
        }
        return .allow(url)
    }

    /// A dotted DNS name or IPv4 address, `localhost`, or an IPv6 literal. Winamp-2006 hands
    /// `navigateUrl` a Windows program path (`Plugins\MSPP\rating\getCurrentRating.exe`), which the
    /// bare-host promotion above turned into `https://Plugins%5CMSPP…` and offered to open; no web host
    /// has a backslash, and a bare word that is not `localhost` has no dot.
    private nonisolated static let hostname = try! NSRegularExpression(
        pattern: #"^(localhost|[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+|\[?[0-9A-Fa-f:.]*:[0-9A-Fa-f:.]*\]?)$"#,
        options: [.caseInsensitive])

    private nonisolated static func isHostname(_ host: String) -> Bool {
        hostname.firstMatch(in: host, range: NSRange(host.startIndex..., in: host)) != nil
    }
}
