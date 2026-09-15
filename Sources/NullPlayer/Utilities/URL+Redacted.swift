import Foundation

extension URL {
    /// Returns the URL string with known auth query parameters replaced by "<redacted>".
    /// Covers media-server auth, URL user info, and local casting capability paths.
    /// For logging only; never use the result for requests or persistence.
    var redacted: String {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return "<invalid URL>"
        }
        if components.user != nil { components.user = "<redacted>" }
        if components.password != nil { components.password = "<redacted>" }
        components.queryItems = components.queryItems?.map {
            Self.sensitiveQueryItemNames.contains($0.name.lowercased())
                ? URLQueryItem(name: $0.name, value: "<redacted>")
                : $0
        }
        guard let value = components.url?.absoluteString else { return "<invalid URL>" }
        // Re-encode the replacement markers to retain a valid URL-shaped log value.
        return URL(string: value.redactingSensitiveURLQueryItems)?.absoluteString ?? "<invalid URL>"
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
        "api_key",
        "x-emby-token",
        "p",
        "password",
        "auth",
        "signature",
        "sig"
    ]
}

extension String {
    private static let sensitiveQueryItemNames: Set<String> = [
        "u", "t", "s", "p", "password", "x-plex-token", "x-emby-token",
        "token", "access_token", "auth_token", "apikey", "api_key", "auth",
        "signature", "sig"
    ]

    /// Matches query-like values while retaining the encoded query-name capture.
    private static let encodedSensitiveQueryNamePattern = try? NSRegularExpression(
        pattern: #"(?i)((?:[?&]|&amp;|%3f|%26)((?:%[0-9a-f]{2}|[a-z0-9_-])+)(?:=|%3d))[^&\s"'<>\\]+"#
    )

    /// Compiled once and reused across log and error presentation calls.
    private static let sensitiveURLRedactionPatterns: [(NSRegularExpression?, String)] = {
        // Also match XML-escaped separators and percent-encoded nested URLs.
        // Stop at a log/XML/JSON delimiter so surrounding diagnostics survive.
        let patterns: [(String, String)] = [
            (#"(?i)((?:[?&]|&amp;|%3f|%26)(?:u|t|s|p|password|x-plex-token|x-emby-token|token|access_token|auth_token|apikey|api_key|auth|signature|sig)(?:=|%3d))[^&\s"'<>\\]+"#, "$1<redacted>"),
            // Error descriptions may embed JSON credential fields or auth headers.
            (#"(?i)("(?:AccessToken|access_token|auth_token|api_key|apikey|X-Plex-Token|X-Emby-Token|token|password)"\s*:\s*")(?:\\.|[^"\\])*"#, "$1<redacted>"),
            (#"(?im)((?:Authorization|X-Plex-Token|X-Emby-Token):[ \t]*)[^\r\n]+"#, "$1<redacted>"),
            // User info can carry a basic-auth password, including in radio URLs.
            (#"(?i)([a-z][a-z0-9+.-]*://)[^/?#\s<>"]+@(?=[^/?#\s<>"]+)"#, "$1<redacted>@"),
            // LocalMediaServer issues 16-hex capability tokens in these paths.
            (#"(?i)(/(?:stream|media|artwork)/)[a-f0-9]{16}(?=[./?&#\s"'<>\\]|$)"#, "$1<redacted>")
        ]
        return patterns.map { pattern, template in
            (try? NSRegularExpression(pattern: pattern), template)
        }
    }()

    /// Redacts known credentials from log/error strings that may contain URLs.
    var redactingSensitiveURLQueryItems: String {
        // JSON may escape the slashes in URLs embedded in error descriptions.
        let message = replacingOccurrences(of: #"\/"#, with: "/")
        let encodedNameRedacted = Self.redactingPercentEncodedSensitiveQueryNames(in: message)
        return Self.sensitiveURLRedactionPatterns.reduce(encodedNameRedacted) { message, rule in
            guard let regex = rule.0 else {
                return "<redacted>"
            }
            return regex.stringByReplacingMatches(
                in: message,
                range: NSRange(message.startIndex..<message.endIndex, in: message),
                withTemplate: rule.1
            )
        }
    }

    /// Redacts query values whose percent-decoded names are credentials.
    private static func redactingPercentEncodedSensitiveQueryNames(in message: String) -> String {
        guard let regex = encodedSensitiveQueryNamePattern else { return "<redacted>" }
        let range = NSRange(message.startIndex..<message.endIndex, in: message)
        let replacements = regex.matches(in: message, range: range).compactMap { match -> (Range<String.Index>, String)? in
            guard
                let nameRange = Range(match.range(at: 2), in: message),
                let matchRange = Range(match.range, in: message),
                let prefixRange = Range(match.range(at: 1), in: message),
                let decodedName = String(message[nameRange]).removingPercentEncoding?.lowercased(),
                sensitiveQueryItemNames.contains(decodedName)
            else {
                return nil
            }
            return (matchRange, String(message[prefixRange]) + "<redacted>")
        }

        return replacements.reversed().reduce(message) { result, replacement in
            var redacted = result
            redacted.replaceSubrange(replacement.0, with: replacement.1)
            return redacted
        }
    }
}
