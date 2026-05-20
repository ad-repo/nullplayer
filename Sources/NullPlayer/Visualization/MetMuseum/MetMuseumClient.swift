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
    private let maxConcurrent: Int = 5

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

            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                throw NetworkError.httpError
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

            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                throw NetworkError.httpError
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

            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                throw NetworkError.httpError
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

            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                throw NetworkError.httpError
            }

            return data
        }
    }

    /// Helper to acquire permit, run closure, then release
    private func withPermit<T>(_ body: () async throws -> T) async rethrows -> T {
        await semaphore.acquire()
        do {
            let result = try await body()
            await semaphore.release()
            return result
        } catch {
            await semaphore.release()
            throw error
        }
    }

    // MARK: - Error Types

    enum NetworkError: LocalizedError {
        case invalidURL
        case httpError
        case notPublicDomain
        case invalidImage
        case decodingError

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid URL constructed"
            case .httpError:
                return "HTTP request failed"
            case .notPublicDomain:
                return "Object is not public domain"
            case .invalidImage:
                return "Could not decode image data"
            case .decodingError:
                return "Failed to decode JSON response"
            }
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
