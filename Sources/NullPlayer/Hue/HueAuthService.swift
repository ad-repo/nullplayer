import Foundation

enum HueAuthError: LocalizedError {
    case missingCredentials
    case linkButtonNotPressed
    case pairingFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Hue bridge credentials are missing"
        case .linkButtonNotPressed:
            return "Press the link button on your Hue Bridge, then try pairing again"
        case .pairingFailed(let reason):
            return reason
        }
    }
}

final class HueAuthService {
    private enum Keys {
        static let appKey = "hue_app_key"
        static let bridgeID = "hue_bridge_id"
        static let bridgeIP = "hue_bridge_ip"
    }

    private let keychain = KeychainHelper.shared

    func pairedBridgeID() -> String? {
        keychain.getString(forKey: Keys.bridgeID)
    }

    func pairedBridgeIP() -> String? {
        keychain.getString(forKey: Keys.bridgeIP)
    }

    func appKey() -> String? {
        keychain.getString(forKey: Keys.appKey)
    }

    func saveCredentials(appKey: String, bridge: HueBridge) {
        _ = keychain.setString(appKey, forKey: Keys.appKey)
        _ = keychain.setString(bridge.id.lowercased(), forKey: Keys.bridgeID)
        _ = keychain.setString(bridge.ipAddress, forKey: Keys.bridgeIP)
    }

    func clearCredentials() {
        keychain.deleteString(forKey: Keys.appKey)
        keychain.deleteString(forKey: Keys.bridgeID)
        keychain.deleteString(forKey: Keys.bridgeIP)
    }

    func pair(bridge: HueBridge, session: URLSession) async throws -> String {
        let client = OpenHueGeneratedClient(bridge: bridge, appKey: nil, session: session)
        do {
            return try await client.createLinkToken(deviceType: "nullplayer#mac")
        } catch let error as HueClientError {
            NSLog(
                "HueAuthService: pairing failed for bridge %@ (%@): %@",
                bridge.id,
                bridge.baseURLString,
                error.localizedDescription
            )
            switch error {
            case .apiError(let message):
                if message.lowercased().contains("link") {
                    throw HueAuthError.linkButtonNotPressed
                }
                throw HueAuthError.pairingFailed(message)
            default:
                throw HueAuthError.pairingFailed(error.localizedDescription)
            }
        } catch {
            NSLog(
                "HueAuthService: pairing transport failure for bridge %@ (%@): %@",
                bridge.id,
                bridge.baseURLString,
                error.localizedDescription
            )
            throw HueAuthError.pairingFailed(error.localizedDescription)
        }
    }
}
