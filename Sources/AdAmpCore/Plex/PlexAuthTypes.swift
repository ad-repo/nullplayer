import Foundation

/// Constants for Plex authentication
public enum PlexAuthClient {
    /// The link page URL for users to enter their PIN
    public static let linkURL = URL(string: "https://plex.tv/link")!
}

/// Errors that can occur during Plex authentication
public enum PlexAuthError: LocalizedError, Sendable {
    case invalidResponse
    case httpError(statusCode: Int)
    case pinExpired
    case unauthorized
    
    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from Plex"
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        case .pinExpired:
            return "PIN has expired"
        case .unauthorized:
            return "Unauthorized - invalid token"
        }
    }
}
