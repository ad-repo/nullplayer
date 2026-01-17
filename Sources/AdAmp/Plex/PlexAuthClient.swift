import Foundation
import AppKit

/// Handles PIN-based authentication with plex.tv
class PlexAuthClient {
    
    // MARK: - Constants
    
    private static let plexTVBaseURL = "https://plex.tv"
    private static let pinEndpoint = "/api/v2/pins"
    private static let resourcesEndpoint = "/api/v2/resources"
    private static let userEndpoint = "/api/v2/user"
    
    /// The link page URL for users to enter their PIN
    static let linkURL = URL(string: "https://plex.tv/link")!
    
    // MARK: - Properties
    
    private let session: URLSession
    private let clientIdentifier: String
    
    // MARK: - Initialization
    
    init(clientIdentifier: String? = nil) {
        self.clientIdentifier = clientIdentifier ?? KeychainHelper.shared.getOrCreateClientIdentifier()
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Standard Headers
    
    /// Headers required for all plex.tv API requests
    private var standardHeaders: [String: String] {
        [
            "X-Plex-Client-Identifier": clientIdentifier,
            "X-Plex-Product": "AdAmp",
            "X-Plex-Version": "1.0",
            "X-Plex-Platform": "macOS",
            "X-Plex-Platform-Version": ProcessInfo.processInfo.operatingSystemVersionString,
            "X-Plex-Device": "Mac",
            "X-Plex-Device-Name": Host.current().localizedName ?? "Mac",
            "Accept": "application/json",
            "Content-Type": "application/x-www-form-urlencoded"
        ]
    }
    
    /// Headers with authentication token
    private func authenticatedHeaders(token: String) -> [String: String] {
        var headers = standardHeaders
        headers["X-Plex-Token"] = token
        return headers
    }
    
    // MARK: - PIN Authentication Flow
    
    /// Create a new PIN for account linking
    /// - Returns: A PlexPIN containing the code to display to the user
    func createPIN() async throws -> PlexPIN {
        let url = URL(string: Self.plexTVBaseURL + Self.pinEndpoint)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        // Add headers
        for (key, value) in standardHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        // No body needed for standard 4-character PIN
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlexAuthError.invalidResponse
        }
        
        guard httpResponse.statusCode == 201 || httpResponse.statusCode == 200 else {
            throw PlexAuthError.httpError(statusCode: httpResponse.statusCode)
        }
        
        let pinResponse = try JSONDecoder().decode(PlexPINResponse.self, from: data)
        return pinResponse.toPIN()
    }
    
    /// Check the status of a PIN to see if it has been authorized
    /// - Parameter id: The PIN ID returned from createPIN()
    /// - Returns: Updated PlexPIN with authToken if authorized
    func checkPIN(id: Int) async throws -> PlexPIN {
        let url = URL(string: Self.plexTVBaseURL + Self.pinEndpoint + "/\(id)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        for (key, value) in standardHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlexAuthError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw PlexAuthError.httpError(statusCode: httpResponse.statusCode)
        }
        
        let pinResponse = try JSONDecoder().decode(PlexPINResponse.self, from: data)
        return pinResponse.toPIN()
    }
    
    /// Poll for PIN authorization until success, expiration, or cancellation
    /// - Parameters:
    ///   - pin: The PIN to poll
    ///   - interval: Polling interval in seconds (default 2)
    ///   - onUpdate: Optional callback for status updates
    /// - Returns: The authorized PIN with auth token
    func pollForAuthorization(
        pin: PlexPIN,
        interval: TimeInterval = 2.0,
        onUpdate: ((PlexPIN) -> Void)? = nil
    ) async throws -> PlexPIN {
        var currentPIN = pin
        
        while true {
            // Check if PIN expired
            if currentPIN.isExpired {
                throw PlexAuthError.pinExpired
            }
            
            // Check if cancelled
            try Task.checkCancellation()
            
            // Wait before polling
            try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            
            // Check PIN status
            currentPIN = try await checkPIN(id: pin.id)
            onUpdate?(currentPIN)
            
            // If we got an auth token, we're done
            if let token = currentPIN.authToken, !token.isEmpty {
                return currentPIN
            }
        }
    }
    
    // MARK: - Resource Discovery
    
    /// Fetch all servers/resources linked to the account
    /// - Parameter token: The auth token from PIN authorization
    /// - Returns: List of Plex servers the user has access to
    func fetchResources(token: String) async throws -> [PlexServer] {
        let url = URL(string: Self.plexTVBaseURL + Self.resourcesEndpoint)!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        for (key, value) in authenticatedHeaders(token: token) {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlexAuthError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 {
                throw PlexAuthError.unauthorized
            }
            throw PlexAuthError.httpError(statusCode: httpResponse.statusCode)
        }
        
        let resources = try JSONDecoder().decode([PlexResourceDTO].self, from: data)
        return resources.compactMap { $0.toServer() }
    }
    
    // MARK: - User Info
    
    /// Fetch the authenticated user's account info
    /// - Parameter token: The auth token
    /// - Returns: PlexAccount with user details
    func fetchUser(token: String) async throws -> PlexAccount {
        let url = URL(string: Self.plexTVBaseURL + Self.userEndpoint)!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        for (key, value) in authenticatedHeaders(token: token) {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlexAuthError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 {
                throw PlexAuthError.unauthorized
            }
            throw PlexAuthError.httpError(statusCode: httpResponse.statusCode)
        }
        
        let userResponse = try JSONDecoder().decode(PlexUserResponse.self, from: data)
        return userResponse.toAccount()
    }
    
    // MARK: - Browser Launch
    
    /// Open the plex.tv/link page in the user's default browser
    func openLinkPage() {
        NSWorkspace.shared.open(Self.linkURL)
    }
}

// MARK: - Errors

enum PlexAuthError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int)
    case pinExpired
    case unauthorized
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from Plex server"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .pinExpired:
            return "PIN has expired. Please try again."
        case .unauthorized:
            return "Authorization failed. Please link your account again."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
