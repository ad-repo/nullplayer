import Foundation

enum HueClientError: LocalizedError {
    case invalidBridgeURL
    case invalidResponse
    case httpStatus(Int)
    case apiError(String)
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .invalidBridgeURL:
            return "Invalid Hue bridge URL"
        case .invalidResponse:
            return "Invalid response from Hue bridge"
        case .httpStatus(let code):
            return "Hue bridge returned HTTP \(code)"
        case .apiError(let message):
            return message
        case .invalidPayload:
            return "Invalid request payload"
        }
    }
}

final class OpenHueGeneratedClient {
    private let bridge: HueBridge
    private let appKey: String?
    private let session: URLSession

    init(bridge: HueBridge, appKey: String?, session: URLSession) {
        self.bridge = bridge
        self.appKey = appKey
        self.session = session
    }

    func getLights() async throws -> [OpenHueLightResource] {
        try await getResource(path: "/clip/v2/resource/light")
    }

    func getGroupedLights() async throws -> [OpenHueGroupedLightResource] {
        try await getResource(path: "/clip/v2/resource/grouped_light")
    }

    func getRooms() async throws -> [OpenHueRoomResource] {
        try await getResource(path: "/clip/v2/resource/room")
    }

    func getZones() async throws -> [OpenHueZoneResource] {
        try await getResource(path: "/clip/v2/resource/zone")
    }

    func getDevices() async throws -> [OpenHueDeviceResource] {
        try await getResource(path: "/clip/v2/resource/device")
    }

    func getScenes() async throws -> [OpenHueSceneResource] {
        try await getResource(path: "/clip/v2/resource/scene")
    }

    func setGroupedLight(id: String, payload: [String: Any]) async throws {
        try await put(path: "/clip/v2/resource/grouped_light/\(id)", payload: payload)
    }

    func setLight(id: String, payload: [String: Any]) async throws {
        try await put(path: "/clip/v2/resource/light/\(id)", payload: payload)
    }

    func activateScene(id: String) async throws {
        try await put(path: "/clip/v2/resource/scene/\(id)", payload: [
            "recall": ["action": "active"]
        ])
    }

    func createScene(payload: [String: Any]) async throws {
        _ = try await request(path: "/clip/v2/resource/scene", method: "POST", payload: payload)
    }

    func deleteScene(id: String) async throws {
        _ = try await request(path: "/clip/v2/resource/scene/\(id)", method: "DELETE")
    }

    func createLinkToken(deviceType: String) async throws -> String {
        guard let url = URL(string: "\(bridge.baseURLString)/api") else {
            throw HueClientError.invalidBridgeURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "devicetype": deviceType,
            "generateclientkey": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            NSLog("OpenHueGeneratedClient: POST /api transport error: %@", error.localizedDescription)
            throw error
        }
        guard let http = response as? HTTPURLResponse else {
            throw HueClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            logHTTPFailure(method: "POST", path: "/api", statusCode: http.statusCode, data: data)
            throw HueClientError.httpStatus(http.statusCode)
        }

        let items: [OpenHueLinkResponseElement]
        do {
            items = try JSONDecoder().decode([OpenHueLinkResponseElement].self, from: data)
        } catch {
            let bodySnippet = String((String(data: data, encoding: .utf8) ?? "<non-utf8 body>").prefix(300))
            NSLog("OpenHueGeneratedClient: POST /api decode error: %@ body=%@", error.localizedDescription, bodySnippet)
            throw error
        }
        if let success = items.first?.success,
           let username = success.username,
           !username.isEmpty {
            return username
        }

        if let error = items.first?.error {
            let description = error.description ?? "Hue link button not pressed"
            throw HueClientError.apiError(description)
        }

        throw HueClientError.invalidResponse
    }

    private func getResource<T: Decodable>(path: String) async throws -> [T] {
        let (data, response) = try await request(path: path, method: "GET")
        guard let http = response as? HTTPURLResponse else {
            throw HueClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw HueClientError.httpStatus(http.statusCode)
        }

        let envelope = try JSONDecoder().decode(OpenHueEnvelope<T>.self, from: data)
        if let error = envelope.errors?.first?.description {
            throw HueClientError.apiError(error)
        }
        return envelope.data
    }

    private func put(path: String, payload: [String: Any]) async throws {
        _ = try await request(path: path, method: "PUT", payload: payload)
    }

    @discardableResult
    private func request(path: String, method: String, payload: [String: Any]? = nil) async throws -> (Data, URLResponse) {
        guard let url = URL(string: "\(bridge.baseURLString)\(path)") else {
            throw HueClientError.invalidBridgeURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 8
        if let appKey, !appKey.isEmpty {
            request.setValue(appKey, forHTTPHeaderField: "hue-application-key")
        }

        if let payload {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            guard JSONSerialization.isValidJSONObject(payload) else {
                throw HueClientError.invalidPayload
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            NSLog("OpenHueGeneratedClient: %@ %@ transport error: %@", method, path, error.localizedDescription)
            throw error
        }
        guard let http = response as? HTTPURLResponse else {
            throw HueClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            logHTTPFailure(method: method, path: path, statusCode: http.statusCode, data: data)
            throw HueClientError.httpStatus(http.statusCode)
        }

        if !data.isEmpty,
           let envelope = try? JSONDecoder().decode(OpenHueEnvelope<EmptyHuePayload>.self, from: data),
           let error = envelope.errors?.first?.description {
            throw HueClientError.apiError(error)
        }

        return (data, response)
    }

    private func logHTTPFailure(method: String, path: String, statusCode: Int, data: Data) {
        let bodySnippet: String
        if data.isEmpty {
            bodySnippet = "<empty>"
        } else {
            let text = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            bodySnippet = String(text.prefix(300))
        }
        NSLog(
            "OpenHueGeneratedClient: %@ %@ failed with HTTP %d. body=%@",
            method,
            path,
            statusCode,
            bodySnippet
        )
    }
}

private struct EmptyHuePayload: Decodable {}
