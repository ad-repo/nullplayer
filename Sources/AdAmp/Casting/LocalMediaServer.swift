import Foundation
import FlyingFox
import FlyingSocks

/// Embedded HTTP server for serving local audio files to cast devices.
///
/// Cast protocols (UPnP, Chromecast) require HTTP-accessible media URLs.
/// This server registers local files and provides HTTP URLs that cast devices
/// can fetch directly, with support for Range requests (for seeking).
///
/// Usage:
/// 1. Start the server (automatically done on first file registration)
/// 2. Register a local file to get an HTTP URL
/// 3. Send the HTTP URL to the cast device
/// 4. Cast device fetches audio directly from this server
class LocalMediaServer {
    
    // MARK: - Singleton
    
    static let shared = LocalMediaServer()
    
    // MARK: - Properties
    
    private var server: HTTPServer?
    private var serverTask: Task<Void, Never>?
    private var registeredFiles: [String: URL] = [:]  // token -> file URL
    private var registeredStreams: [String: URL] = [:]  // token -> stream URL (for Subsonic proxy)
    private let port: UInt16 = 8765
    private(set) var isRunning: Bool = false
    private var _localIPAddress: String?
    
    /// Get the local network IP address (cached or freshly discovered)
    /// This can be called even when the server isn't running
    var localIPAddress: String? {
        if let ip = _localIPAddress {
            return ip
        }
        // Discover and cache the IP
        _localIPAddress = discoverLocalIPAddress()
        return _localIPAddress
    }
    
    private let queue = DispatchQueue(label: "com.adamp.localmediaserver", attributes: .concurrent)
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Start the HTTP server
    func start() async throws {
        guard !isRunning else {
            NSLog("LocalMediaServer: Already running")
            return
        }
        
        // Get local IP address
        guard let ip = discoverLocalIPAddress() else {
            throw LocalServerError.noNetworkInterface
        }
        _localIPAddress = ip
        NSLog("LocalMediaServer: Local IP address: %@", ip)
        
        // Create server bound to all interfaces (0.0.0.0) so network devices can reach it
        let address = try sockaddr_in.inet(ip4: "0.0.0.0", port: port)
        let server = HTTPServer(address: address)
        self.server = server
        
        // Add route handler for media files (local files)
        await server.appendRoute("GET /media/*") { [weak self] request in
            guard let self = self else {
                return HTTPResponse(statusCode: .internalServerError)
            }
            return await self.handleMediaRequest(request)
        }
        
        // Add route handler for stream proxy (Subsonic/remote URLs)
        await server.appendRoute("GET /stream/*") { [weak self] request in
            guard let self = self else {
                return HTTPResponse(statusCode: .internalServerError)
            }
            return await self.handleStreamRequest(request)
        }
        
        // Start server in background task
        serverTask = Task {
            do {
                NSLog("LocalMediaServer: Starting on port %d", port)
                try await server.start()
            } catch {
                NSLog("LocalMediaServer: Failed to start - %@", error.localizedDescription)
            }
        }
        
        // Give the server a moment to start
        try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
        
        isRunning = true
        NSLog("LocalMediaServer: Started successfully on http://%@:%d", ip, port)
    }
    
    /// Stop the HTTP server
    func stop() {
        NSLog("LocalMediaServer: Stopping...")
        
        serverTask?.cancel()
        serverTask = nil
        server = nil
        isRunning = false
        
        queue.async(flags: .barrier) { [weak self] in
            self?.registeredFiles.removeAll()
        }
        
        NSLog("LocalMediaServer: Stopped")
    }
    
    /// Register a local file for serving.
    /// Returns the HTTP URL that cast devices can use.
    /// Note: Prefer calling start() explicitly before this method in async contexts.
    func registerFile(_ url: URL) -> URL? {
        guard url.isFileURL else {
            NSLog("LocalMediaServer: Cannot register non-file URL: %@", url.absoluteString)
            return nil
        }
        
        // Ensure server is running
        if !isRunning {
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                do {
                    try await start()
                } catch {
                    NSLog("LocalMediaServer: Failed to start server: %@", error.localizedDescription)
                }
                semaphore.signal()
            }
            // Wait for server startup with timeout
            let result = semaphore.wait(timeout: .now() + 2.0)
            if result == .timedOut {
                NSLog("LocalMediaServer: Server startup timed out")
            }
            
            // Verify server actually started
            if !isRunning {
                NSLog("LocalMediaServer: Server failed to start, cannot register file")
                return nil
            }
        }
        
        guard let ip = localIPAddress else {
            NSLog("LocalMediaServer: No local IP address available")
            return nil
        }
        
        // Generate unique token for this file
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16)
        let tokenString = String(token)
        
        queue.async(flags: .barrier) { [weak self] in
            self?.registeredFiles[tokenString] = url
        }
        
        // Return HTTP URL: http://192.168.x.x:8765/media/token.mp3
        let ext = url.pathExtension.lowercased()
        let httpURL = URL(string: "http://\(ip):\(port)/media/\(tokenString).\(ext)")
        
        NSLog("LocalMediaServer: Registered file '%@' as %@", url.lastPathComponent, httpURL?.absoluteString ?? "nil")
        
        return httpURL
    }
    
    /// Unregister a file (called when casting stops)
    func unregisterFile(_ url: URL) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            let tokenToRemove = self.registeredFiles.first { $0.value == url }?.key
            if let token = tokenToRemove {
                self.registeredFiles.removeValue(forKey: token)
                NSLog("LocalMediaServer: Unregistered file '%@'", url.lastPathComponent)
            }
        }
    }
    
    /// Unregister all files
    func unregisterAll() {
        queue.async(flags: .barrier) { [weak self] in
            self?.registeredFiles.removeAll()
            self?.registeredStreams.removeAll()
            NSLog("LocalMediaServer: Unregistered all files and streams")
        }
    }
    
    /// Register a remote stream URL for proxying (e.g., Subsonic streams).
    /// Returns an HTTP URL that cast devices can use.
    /// The proxy fetches from the original URL and serves to the cast device.
    /// Note: Prefer calling start() explicitly before this method in async contexts.
    func registerStreamURL(_ url: URL) -> URL? {
        // Ensure server is running
        if !isRunning {
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                do {
                    try await start()
                } catch {
                    NSLog("LocalMediaServer: Failed to start server: %@", error.localizedDescription)
                }
                semaphore.signal()
            }
            // Wait for server startup with timeout
            let result = semaphore.wait(timeout: .now() + 2.0)
            if result == .timedOut {
                NSLog("LocalMediaServer: Server startup timed out")
            }
            
            // Verify server actually started
            if !isRunning {
                NSLog("LocalMediaServer: Server failed to start, cannot register stream")
                return nil
            }
        }
        
        guard let ip = localIPAddress else {
            NSLog("LocalMediaServer: No local IP address available")
            return nil
        }
        
        // Generate unique token for this stream
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16)
        let tokenString = String(token)
        
        queue.async(flags: .barrier) { [weak self] in
            self?.registeredStreams[tokenString] = url
        }
        
        // Return simple HTTP URL without query strings: http://192.168.x.x:8765/stream/token
        // Don't use file extension - let Content-Type header indicate format
        let httpURL = URL(string: "http://\(ip):\(port)/stream/\(tokenString)")
        
        NSLog("LocalMediaServer: Registered stream proxy '%@' as %@", url.host ?? "unknown", httpURL?.absoluteString ?? "nil")
        
        return httpURL
    }
    
    /// Unregister a stream URL
    func unregisterStreamURL(_ url: URL) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            let tokenToRemove = self.registeredStreams.first { $0.value == url }?.key
            if let token = tokenToRemove {
                self.registeredStreams.removeValue(forKey: token)
                NSLog("LocalMediaServer: Unregistered stream '%@'", url.host ?? "unknown")
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// Discover the local network IP address from network interfaces
    private func discoverLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }
        
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            
            let interface = ptr!.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            
            // Check for IPv4 (AF_INET)
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                // Skip loopback, prefer en0 (Wi-Fi) or en1 (Ethernet)
                if name == "en0" || name == "en1" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                               &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                    address = String(cString: hostname)
                    break
                }
            }
        }
        return address
    }
    
    /// Handle incoming HTTP requests for local media files
    private func handleMediaRequest(_ request: HTTPRequest) async -> HTTPResponse {
        let path = request.path
        NSLog("LocalMediaServer: Received media request for %@", path)
        
        // Parse path: /media/{token}.{ext}
        guard path.hasPrefix("/media/") else {
            NSLog("LocalMediaServer: Invalid path - not /media/")
            return HTTPResponse(statusCode: .notFound)
        }
        
        let filename = String(path.dropFirst(7)) // Remove "/media/"
        let token = filename.components(separatedBy: ".").first ?? filename
        
        // Thread-safe lookup
        var fileURL: URL?
        queue.sync {
            fileURL = registeredFiles[token]
        }
        
        guard let url = fileURL else {
            NSLog("LocalMediaServer: Token not found: %@", token)
            return HTTPResponse(statusCode: .notFound)
        }
        
        // Get file attributes
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attrs[.size] as? Int64 else {
            NSLog("LocalMediaServer: Failed to get file attributes for %@", url.path)
            return HTTPResponse(statusCode: .internalServerError)
        }
        
        let contentType = self.contentType(for: url)
        
        // Handle Range requests (for seeking)
        if let rangeHeader = request.headers[HTTPHeader("Range")] {
            return handleRangeRequest(rangeHeader, fileURL: url, fileSize: fileSize, contentType: contentType)
        }
        
        // Full file response
        guard let data = try? Data(contentsOf: url) else {
            NSLog("LocalMediaServer: Failed to read file data for %@", url.path)
            return HTTPResponse(statusCode: .internalServerError)
        }
        
        NSLog("LocalMediaServer: Serving full file %@ (%lld bytes)", url.lastPathComponent, fileSize)
        
        return HTTPResponse(
            statusCode: .ok,
            headers: [
                HTTPHeader("Content-Type"): contentType,
                HTTPHeader("Content-Length"): String(fileSize),
                HTTPHeader("Accept-Ranges"): "bytes"
            ],
            body: data
        )
    }
    
    /// Handle Range request (critical for seeking)
    private func handleRangeRequest(_ rangeHeader: String, fileURL: URL, fileSize: Int64, contentType: String) -> HTTPResponse {
        // Parse "bytes=start-end" or "bytes=start-"
        guard rangeHeader.hasPrefix("bytes=") else {
            NSLog("LocalMediaServer: Invalid Range header: %@", rangeHeader)
            return HTTPResponse(statusCode: .badRequest)
        }
        
        let rangeSpec = String(rangeHeader.dropFirst(6))
        let parts = rangeSpec.split(separator: "-", omittingEmptySubsequences: false)
        
        let start = Int64(parts[0]) ?? 0
        let end: Int64
        if parts.count > 1 && !parts[1].isEmpty {
            end = Int64(parts[1]) ?? (fileSize - 1)
        } else {
            end = fileSize - 1
        }
        
        guard start < fileSize else {
            NSLog("LocalMediaServer: Range start %lld >= file size %lld", start, fileSize)
            return HTTPResponse(
                statusCode: .rangeNotSatisfiable,
                headers: [HTTPHeader("Content-Range"): "bytes */\(fileSize)"]
            )
        }
        
        let clampedEnd = min(end, fileSize - 1)
        let length = clampedEnd - start + 1
        
        // Read the requested range
        guard let fileHandle = try? FileHandle(forReadingFrom: fileURL) else {
            NSLog("LocalMediaServer: Failed to open file handle for %@", fileURL.path)
            return HTTPResponse(statusCode: .internalServerError)
        }
        defer { try? fileHandle.close() }
        
        do {
            try fileHandle.seek(toOffset: UInt64(start))
        } catch {
            NSLog("LocalMediaServer: Failed to seek to offset %lld: %@", start, error.localizedDescription)
            return HTTPResponse(statusCode: .internalServerError)
        }
        
        let data = fileHandle.readData(ofLength: Int(length))
        
        NSLog("LocalMediaServer: Serving range %lld-%lld/%lld (%lld bytes) for %@",
              start, clampedEnd, fileSize, length, fileURL.lastPathComponent)
        
        return HTTPResponse(
            statusCode: .partialContent,
            headers: [
                HTTPHeader("Content-Type"): contentType,
                HTTPHeader("Content-Length"): String(length),
                HTTPHeader("Content-Range"): "bytes \(start)-\(clampedEnd)/\(fileSize)",
                HTTPHeader("Accept-Ranges"): "bytes"
            ],
            body: data
        )
    }
    
    /// Handle incoming HTTP requests for proxied streams (Subsonic, etc.)
    private func handleStreamRequest(_ request: HTTPRequest) async -> HTTPResponse {
        let path = request.path
        NSLog("LocalMediaServer: Received stream proxy request for %@", path)
        
        // Parse path: /stream/{token}.{ext}
        guard path.hasPrefix("/stream/") else {
            NSLog("LocalMediaServer: Invalid path - not /stream/")
            return HTTPResponse(statusCode: .notFound)
        }
        
        // Token is the path after /stream/ (may or may not have extension)
        let filename = String(path.dropFirst(8)) // Remove "/stream/"
        // Handle both /stream/TOKEN and /stream/TOKEN.ext
        let token = filename.components(separatedBy: ".").first ?? filename
        
        // Thread-safe lookup
        var streamURL: URL?
        queue.sync {
            streamURL = registeredStreams[token]
        }
        
        guard let originalURL = streamURL else {
            NSLog("LocalMediaServer: Stream token not found: %@", token)
            return HTTPResponse(statusCode: .notFound)
        }
        
        NSLog("LocalMediaServer: Proxying stream from %@", originalURL.host ?? "unknown")
        
        // Build the request to the original server
        var urlRequest = URLRequest(url: originalURL)
        urlRequest.httpMethod = "GET"
        urlRequest.timeoutInterval = 30
        
        // Pass through Range header if present (for seeking)
        if let rangeHeader = request.headers[HTTPHeader("Range")] {
            urlRequest.setValue(rangeHeader, forHTTPHeaderField: "Range")
            NSLog("LocalMediaServer: Passing through Range header: %@", rangeHeader)
        }
        
        // Fetch from the original server
        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                NSLog("LocalMediaServer: Invalid response from upstream server")
                return HTTPResponse(statusCode: .badGateway)
            }
            
            let upstreamContentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "audio/mpeg"
            let upstreamContentLength = httpResponse.value(forHTTPHeaderField: "Content-Length")
            NSLog("LocalMediaServer: Upstream returned status %d, %d bytes, type=%@, length=%@", 
                  httpResponse.statusCode, data.count, upstreamContentType, upstreamContentLength ?? "nil")
            
            // Build response headers
            var headers: [HTTPHeader: String] = [:]
            
            // Pass through actual content type - Sonos supports FLAC, MP3, etc. natively
            headers[HTTPHeader("Content-Type")] = upstreamContentType
            
            // Always set Content-Length from actual data size (critical for Sonos)
            headers[HTTPHeader("Content-Length")] = String(data.count)
            
            if let contentRange = httpResponse.value(forHTTPHeaderField: "Content-Range") {
                headers[HTTPHeader("Content-Range")] = contentRange
            }
            
            // Always advertise range support
            headers[HTTPHeader("Accept-Ranges")] = "bytes"
            
            // Map HTTP status code
            let statusCode: HTTPStatusCode
            switch httpResponse.statusCode {
            case 200:
                statusCode = .ok
            case 206:
                statusCode = .partialContent
            case 404:
                statusCode = .notFound
            case 401, 403:
                statusCode = .forbidden
            default:
                statusCode = httpResponse.statusCode >= 400 ? .badGateway : .ok
            }
            
            return HTTPResponse(statusCode: statusCode, headers: headers, body: data)
            
        } catch {
            NSLog("LocalMediaServer: Failed to fetch from upstream: %@", error.localizedDescription)
            return HTTPResponse(statusCode: .badGateway)
        }
    }
    
    /// Detect content type from file extension
    private func contentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        // Audio formats
        case "mp3":
            return "audio/mpeg"
        case "m4a", "aac":
            return "audio/mp4"
        case "flac":
            return "audio/flac"
        case "wav":
            return "audio/wav"
        case "aiff", "aif":
            return "audio/aiff"
        case "ogg":
            return "audio/ogg"
        case "opus":
            return "audio/opus"
        case "wma":
            return "audio/x-ms-wma"
        // Video formats
        case "mp4", "m4v":
            return "video/mp4"
        case "mkv":
            return "video/x-matroska"
        case "webm":
            return "video/webm"
        case "avi":
            return "video/x-msvideo"
        case "mov":
            return "video/quicktime"
        case "ts", "m2ts", "mts":
            return "video/mp2t"
        case "wmv":
            return "video/x-ms-wmv"
        case "flv":
            return "video/x-flv"
        default:
            return "application/octet-stream"
        }
    }
}

// MARK: - Errors

/// Errors that can occur with the local media server
enum LocalServerError: Error, LocalizedError {
    case noNetworkInterface
    case serverStartFailed(String)
    case fileNotRegistered
    
    var errorDescription: String? {
        switch self {
        case .noNetworkInterface:
            return "No network interface found. Ensure you're connected to a local network."
        case .serverStartFailed(let reason):
            return "Failed to start local media server: \(reason)"
        case .fileNotRegistered:
            return "File is not registered with the local media server"
        }
    }
}
