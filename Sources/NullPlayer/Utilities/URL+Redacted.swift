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
        let sensitiveParams: Set<String> = ["u", "t", "s", "X-Plex-Token"]
        components.queryItems = components.queryItems?.map {
            sensitiveParams.contains($0.name)
                ? URLQueryItem(name: $0.name, value: "<redacted>")
                : $0
        }
        return components.url?.absoluteString ?? absoluteString
    }
}
