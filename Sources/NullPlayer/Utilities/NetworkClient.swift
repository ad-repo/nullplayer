import Foundation

// =============================================================================
// NETWORK CLIENT
// =============================================================================
// Centralized factory for URLSession instances with consistent
// timeout and caching policies.
//
// Previously, each server manager (Plex, Jellyfin, Emby, Subsonic) created
// its own URLSessionConfiguration with inconsistent timeouts. This factory
// provides presets so all network calls share consistent behavior.
// =============================================================================

enum NetworkClient {

    enum SessionType {
        /// For standard API requests (browsing, metadata).
        /// - 30s request timeout
        /// - 5 min resource timeout (for large library fetches)
        case api

        /// For lightweight, non-critical checks (e.g., server ping).
        /// - 5s request timeout
        /// - 10s resource timeout
        case quickCheck

        /// For long-polling connections that need to stay open.
        /// - 90s request timeout
        /// - 5 min resource timeout
        case longPoll
    }

    /// Creates a URLSession configured for a specific use case.
    static func makeSession(type: SessionType) -> URLSession {
        let config = URLSessionConfiguration.default

        switch type {
        case .api:
            config.timeoutIntervalForRequest = 30
            config.timeoutIntervalForResource = 300 // 5 minutes
        case .quickCheck:
            config.timeoutIntervalForRequest = 5
            config.timeoutIntervalForResource = 10
        case .longPoll:
            config.timeoutIntervalForRequest = 90
            config.timeoutIntervalForResource = 300
        }

        config.urlCache = .shared
        return URLSession(configuration: config)
    }
}
