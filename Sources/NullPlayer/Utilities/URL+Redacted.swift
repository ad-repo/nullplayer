import Foundation

extension URL {
    /// Returns the URL string with known auth query parameters replaced by "<redacted>".
    /// Covers:
    ///   - Subsonic: u (username), t (token), s (salt)
    ///   - Plex: X-Plex-Token
    var redacted: String {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return "<invalid URL>"
        }
        components.queryItems = components.queryItems?.map {
            Self.sensitiveQueryItemNames.contains($0.name.lowercased())
                ? URLQueryItem(name: $0.name, value: "<redacted>")
                : $0
        }
        return components.url?.absoluteString ?? absoluteString
    }

    private static let sensitiveQueryItemNames: Set<String> = [
        "u",
        "t",
        "s",
        "x-plex-token",
        "token",
        "access_token",
        "auth_token",
        "apikey",
        "api_key"
    ]
}

extension String {
    /// Redacts known auth query parameters from log/error strings that may contain URLs.
    var redactingSensitiveURLQueryItems: String {
        let pattern = #"(?i)([?&](?:u|t|s|x-plex-token|token|access_token|auth_token|apikey|api_key)=)[^&\s]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return self }

        let range = NSRange(startIndex..<endIndex, in: self)
        return regex.stringByReplacingMatches(
            in: self,
            range: range,
            withTemplate: "$1<redacted>"
        )
    }
}
