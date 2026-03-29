import Foundation

extension Notification.Name {
    static let hueStateDidChange = Notification.Name("HueStateDidChange")
    static let hueConnectionStateDidChange = Notification.Name("HueConnectionStateDidChange")
}

enum HueConnectionState: String {
    case disconnected
    case discovering
    case awaitingLinkButton
    case connected
    case error
}

enum HueReactiveMode: String, CaseIterable {
    case off
    case entertainment
    case groupFallback
}

enum HueLightshowPreset: String, CaseIterable {
    case auto
    case pulse
    case ambientWave
    case strobeSafe
}

enum HueControlTarget: String, CaseIterable {
    case room
    case zone
    case groupedLight
    case light
}

struct HueCapabilityFlags: Equatable {
    let supportsColor: Bool
    let supportsColorTemperature: Bool
    let supportsDimming: Bool

    static let empty = HueCapabilityFlags(
        supportsColor: false,
        supportsColorTemperature: false,
        supportsDimming: false
    )
}

struct HueBridge: Equatable, Hashable {
    let id: String
    let ipAddress: String
    let name: String
    let port: Int

    private var urlHost: String {
        if ipAddress.contains(":") {
            // IPv6 host literals require brackets, and zone IDs must encode '%' as '%25'.
            let escaped = ipAddress.replacingOccurrences(of: "%", with: "%25")
            return "[\(escaped)]"
        }
        return ipAddress
    }

    var baseURLString: String {
        if port == 443 {
            return "https://\(urlHost)"
        }
        return "https://\(urlHost):\(port)"
    }
}

struct HueTarget: Equatable {
    let id: String
    let name: String
    let targetType: HueControlTarget
    let groupedLightID: String?
    let lightID: String?
    let capabilities: HueCapabilityFlags
}

struct HueScene: Equatable {
    let id: String
    let name: String
    let groupID: String?
    let groupType: String?
}

struct HueLightState {
    var isOn: Bool
    var brightness: Double?
    var mirek: Int?
    var colorXY: (x: Double, y: Double)?
}

struct HueMultiRoomSceneRecord: Codable, Equatable {
    let sceneID: String
    let zoneID: String
    let name: String
    let lightIDs: [String]
}

struct HueReactiveSettings: Equatable {
    var mode: HueReactiveMode
    var intensity: Double
    var speed: Double
}
