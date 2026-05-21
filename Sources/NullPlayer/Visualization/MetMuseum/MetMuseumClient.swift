import Foundation
import AppKit

/// Met Museum Department model
struct MetDepartment: Codable, Hashable {
    let id: Int
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case id = "departmentId"
        case displayName
    }
}

/// Met Museum object/artwork model
struct MetObject: Codable {
    let objectID: Int
    let title: String
    let isPublicDomain: Bool
    let primaryImage: String
    let artistDisplayName: String?
    let objectDate: String?
}

/// Network client for The Metropolitan Museum of Art API
///
/// Provides async access to museum collections with public domain filtering.
/// Uses an actor-based semaphore to limit concurrent requests (max 5 concurrent).
/// Handles timeouts gracefully and filters results to public domain objects only.
actor MetMuseumClient {

    // MARK: - Configuration

    private let urlSession: URLSession
    private let semaphore: AsyncSemaphore
    // Met collection API is restricted; published guidance is 80 req/s but the
    // edge throttles much more aggressively in practice. Keep this small.
    private let maxConcurrent: Int = 2
    // Minimum spacing between requests serialised through the same client.
    private let minRequestSpacing: TimeInterval = 0.25
    private var lastRequestTime: Date = .distantPast

    // MARK: - Timeouts

    private let shortTimeout: TimeInterval = 60.0
    private let longTimeout: TimeInterval = 600.0

    // MARK: - API Constants

    private let baseURL = "https://collectionapi.metmuseum.org/public/collection/v1"

    // MARK: - Types

    struct ObjectsListResult: Codable {
        let objectIDs: [Int]
    }

    // MARK: - Init

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60.0
        config.timeoutIntervalForResource = 600.0
        // Identify ourselves; the Met's CDN throttles requests with no/default
        // User-Agent and frequently returns 403 to them.
        config.httpAdditionalHeaders = [
            "User-Agent": "NullPlayer/1.0 (Met Museum visualization; +https://github.com/billytimmy666/nullplayer)",
            "Accept": "application/json, image/*"
        ]
        self.urlSession = URLSession(configuration: config)
        self.semaphore = AsyncSemaphore(value: maxConcurrent)
    }

    // MARK: - Public API

    /// Fetch list of all departments
    func fetchDepartments() async throws -> [MetDepartment] {
        return try await withPermit {
            let urlString = "\(baseURL)/departments"
            guard let url = URL(string: urlString) else {
                throw NetworkError.invalidURL
            }

            var request = URLRequest(url: url)
            request.timeoutInterval = shortTimeout

            let (data, response) = try await urlSession.data(for: request)

            let httpResponse = response as? HTTPURLResponse
            let status = httpResponse?.statusCode ?? -1
            guard (200..<300).contains(status) else {
                let retryAfter = Self.parseRetryAfter(httpResponse?.value(forHTTPHeaderField: "Retry-After"))
                throw NetworkError.httpError(status: status, url: urlString, retryAfter: retryAfter)
            }

            struct DepartmentsResponse: Codable {
                let departments: [MetDepartment]
            }

            let decoder = JSONDecoder()
            let departmentsResp = try decoder.decode(DepartmentsResponse.self, from: data)
            return departmentsResp.departments
        }
    }

    /// Fetch object IDs for a department (nil = all departments)
    func fetchObjectIDs(departmentID: Int?) async throws -> [Int] {
        return try await withPermit {
            var urlString = "\(baseURL)/objects"
            if let deptID = departmentID {
                urlString += "?departmentIds=\(deptID)"
            }

            guard let url = URL(string: urlString) else {
                throw NetworkError.invalidURL
            }

            var request = URLRequest(url: url)
            request.timeoutInterval = shortTimeout

            let (data, response) = try await urlSession.data(for: request)

            let httpResponse = response as? HTTPURLResponse
            let status = httpResponse?.statusCode ?? -1
            guard (200..<300).contains(status) else {
                let retryAfter = Self.parseRetryAfter(httpResponse?.value(forHTTPHeaderField: "Retry-After"))
                throw NetworkError.httpError(status: status, url: urlString, retryAfter: retryAfter)
            }

            let decoder = JSONDecoder()
            let result = try decoder.decode(ObjectsListResult.self, from: data)
            return result.objectIDs
        }
    }

    /// Fetch detailed information for a specific object
    /// Returns nil if object is not public domain or has no primary image
    func fetchObject(id: Int) async throws -> MetObject? {
        return try await withPermit {
            let urlString = "\(baseURL)/objects/\(id)"
            guard let url = URL(string: urlString) else {
                throw NetworkError.invalidURL
            }

            var request = URLRequest(url: url)
            request.timeoutInterval = shortTimeout

            let (data, response) = try await urlSession.data(for: request)

            let httpResponse = response as? HTTPURLResponse
            let status = httpResponse?.statusCode ?? -1
            guard (200..<300).contains(status) else {
                let retryAfter = Self.parseRetryAfter(httpResponse?.value(forHTTPHeaderField: "Retry-After"))
                throw NetworkError.httpError(status: status, url: urlString, retryAfter: retryAfter)
            }

            let decoder = JSONDecoder()
            let object = try decoder.decode(MetObject.self, from: data)

            // Return nil for non-public-domain or missing image
            guard object.isPublicDomain, !object.primaryImage.isEmpty else {
                return nil
            }

            return object
        }
    }

    /// Download image from URL
    func downloadImage(url: URL) async throws -> Data {
        return try await withPermit {
            var request = URLRequest(url: url)
            request.timeoutInterval = longTimeout

            let (data, response) = try await urlSession.data(for: request)

            let httpResponse = response as? HTTPURLResponse
            let status = httpResponse?.statusCode ?? -1
            guard (200..<300).contains(status) else {
                let retryAfter = Self.parseRetryAfter(httpResponse?.value(forHTTPHeaderField: "Retry-After"))
                throw NetworkError.httpError(status: status, url: url.absoluteString, retryAfter: retryAfter)
            }

            return data
        }
    }

    /// Helper to acquire permit, enforce minimum request spacing, run closure, then release
    private func withPermit<T>(_ body: () async throws -> T) async rethrows -> T {
        await semaphore.acquire()
        // Enforce minimum spacing between requests to stay under the API's
        // throttle. Without this, two concurrent permits can fire back-to-back
        // and trigger 429s under load.
        let now = Date()
        let delta = now.timeIntervalSince(lastRequestTime)
        if delta < minRequestSpacing {
            let wait = minRequestSpacing - delta
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }
        lastRequestTime = Date()
        do {
            let result = try await body()
            await semaphore.release()
            return result
        } catch {
            await semaphore.release()
            throw error
        }
    }

    /// Parse a Retry-After header value (RFC 7231 — either a delta-seconds
    /// integer or an HTTP-date). Returns seconds to wait, or nil if missing/malformed.
    private static func parseRetryAfter(_ header: String?) -> TimeInterval? {
        guard let header = header?.trimmingCharacters(in: .whitespaces), !header.isEmpty else {
            return nil
        }
        if let seconds = TimeInterval(header) {
            return max(0, seconds)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = formatter.date(from: header) {
            return max(0, date.timeIntervalSinceNow)
        }
        return nil
    }

    // MARK: - Error Types

    enum NetworkError: LocalizedError {
        case invalidURL
        case httpError(status: Int, url: String, retryAfter: TimeInterval?)
        case notPublicDomain
        case invalidImage
        case decodingError

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid URL constructed"
            case .httpError(let status, let url, let retryAfter):
                if let r = retryAfter {
                    return "HTTP \(status) for \(url) (retry-after \(Int(r))s)"
                }
                return "HTTP \(status) for \(url)"
            case .notPublicDomain:
                return "Object is not public domain"
            case .invalidImage:
                return "Could not decode image data"
            case .decodingError:
                return "Failed to decode JSON response"
            }
        }

        /// True for transient errors (rate limit, server unavailable) — callers
        /// should back off rather than retry quickly. The Met's CDN returns 403
        /// for rate-limited clients (not 429), so 403 is treated as a throttle here.
        var isThrottle: Bool {
            if case .httpError(let status, _, _) = self {
                return status == 403 || status == 429 || status == 503
            }
            return false
        }

        var retryAfter: TimeInterval? {
            if case .httpError(_, _, let r) = self { return r }
            return nil
        }
    }
}

// MARK: - AsyncSemaphore Helper

/// Simple actor-based semaphore for limiting concurrent requests
private actor AsyncSemaphore {
    private var inFlight: Int = 0
    private let maxConcurrent: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(value: Int) {
        self.maxConcurrent = value
        self.inFlight = 0
    }

    func acquire() async {
        while inFlight >= maxConcurrent {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
        inFlight += 1
    }

    func release() {
        inFlight -= 1
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
        }
    }
}
