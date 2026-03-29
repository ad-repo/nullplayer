import Foundation

// This file intentionally mirrors OpenAPI-generated model structure shape used by OpenHue.

struct OpenHueEnvelope<T: Decodable>: Decodable {
    let errors: [OpenHueAPIError]?
    let data: [T]
}

struct OpenHueAPIError: Decodable {
    let description: String?
}

struct OpenHueResourceIdentifier: Decodable {
    let rid: String
    let rtype: String
}

struct OpenHueMetadata: Decodable {
    let name: String?
}

struct OpenHueOnState: Decodable {
    let on: Bool
}

struct OpenHueDimmingState: Decodable {
    let brightness: Double?
}

struct OpenHueColorTemperatureState: Decodable {
    let mirek: Int?
}

struct OpenHueXYColorState: Decodable {
    let x: Double?
    let y: Double?
}

struct OpenHueColorState: Decodable {
    let xy: OpenHueXYColorState?
}

struct OpenHueLightResource: Decodable {
    let id: String
    let metadata: OpenHueMetadata?
    let on: OpenHueOnState?
    let dimming: OpenHueDimmingState?
    let colorTemperature: OpenHueColorTemperatureState?
    let color: OpenHueColorState?

    enum CodingKeys: String, CodingKey {
        case id
        case metadata
        case on
        case dimming
        case color
        case colorTemperature = "color_temperature"
    }
}

struct OpenHueGroupedLightResource: Decodable {
    let id: String
    let on: OpenHueOnState?
    let dimming: OpenHueDimmingState?
}

struct OpenHueRoomResource: Decodable {
    let id: String
    let metadata: OpenHueMetadata?
    let services: [OpenHueResourceIdentifier]?
    let children: [OpenHueResourceIdentifier]?
}

struct OpenHueZoneResource: Decodable {
    let id: String
    let metadata: OpenHueMetadata?
    let services: [OpenHueResourceIdentifier]?
    let children: [OpenHueResourceIdentifier]?
}

struct OpenHueDeviceResource: Decodable {
    let id: String
    let services: [OpenHueResourceIdentifier]?
}

struct OpenHueSceneGroup: Decodable {
    let rid: String?
    let rtype: String?
}

struct OpenHueSceneResource: Decodable {
    let id: String
    let metadata: OpenHueMetadata?
    let group: OpenHueSceneGroup?
    let actions: [OpenHueSceneAction]?
}

struct OpenHueEntertainmentChannelMember: Decodable {
    let service: OpenHueResourceIdentifier?
    let index: Int?
}

struct OpenHueEntertainmentChannel: Decodable {
    let channelID: Int
    let members: [OpenHueEntertainmentChannelMember]?

    enum CodingKeys: String, CodingKey {
        case channelID = "channel_id"
        case members
    }
}

struct OpenHueEntertainmentConfigurationResource: Decodable {
    let id: String
    let metadata: OpenHueMetadata?
    let status: String?
    let channels: [OpenHueEntertainmentChannel]?
    let lightServices: [OpenHueResourceIdentifier]?
    let activeStreamer: OpenHueResourceIdentifier?

    enum CodingKeys: String, CodingKey {
        case id
        case metadata
        case status
        case channels
        case lightServices = "light_services"
        case activeStreamer = "active_streamer"
    }
}

struct OpenHueEntertainmentResource: Decodable {
    let id: String
    let owner: OpenHueResourceIdentifier?
}

struct OpenHueSceneAction: Decodable {
    let target: OpenHueResourceIdentifier?
    let action: OpenHueLightAction?
}

struct OpenHueLightAction: Decodable {
    let on: OpenHueOnState?
    let dimming: OpenHueDimmingState?
    let colorTemperature: OpenHueColorTemperatureState?
    let color: OpenHueColorState?

    enum CodingKeys: String, CodingKey {
        case on
        case dimming
        case color
        case colorTemperature = "color_temperature"
    }
}

struct OpenHueDiscoveryBridge: Decodable {
    let id: String
    let internalipaddress: String
    let port: Int?
}

struct OpenHueLinkSuccessPayload: Decodable {
    let username: String?
    let clientkey: String?
}

struct OpenHueLinkErrorPayload: Decodable {
    let type: Int?
    let description: String?
}

struct OpenHueLinkResponseElement: Decodable {
    let success: OpenHueLinkSuccessPayload?
    let error: OpenHueLinkErrorPayload?
}
