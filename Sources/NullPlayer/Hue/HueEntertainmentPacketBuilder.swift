import Foundation

enum HueEntertainmentColorSpace: UInt8 {
    case rgb = 0x00
    case xyb = 0x01
}

struct HueEntertainmentPacketBuilder {
    private let protocolName = Array("HueStream".utf8)
    private let streamVersion: (major: UInt8, minor: UInt8) = (0x02, 0x00)
    private let reserved2: (UInt8, UInt8) = (0x00, 0x00)
    private let reserved1: UInt8 = 0x00
    private let maxChannelsPerPacket = 20
    private let expectedAreaIDLength = 36

    func encode(
        _ frame: HueLightshowFrame,
        entertainmentAreaID: String,
        channelByLightID: [String: UInt8],
        colorSpace: HueEntertainmentColorSpace,
        sequenceNumber: UInt8
    ) -> Data? {
        guard let areaBytes = entertainmentAreaID.data(using: .utf8),
              areaBytes.count == expectedAreaIDLength else {
            return nil
        }

        let mappedChannels: [(UInt8, HueEntertainmentChannelFrame)] = frame.channels.compactMap { channel in
            guard let channelID = channelByLightID[channel.lightID] else { return nil }
            return (channelID, channel)
        }.sorted { lhs, rhs in
            lhs.0 < rhs.0
        }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(52 + min(maxChannelsPerPacket, mappedChannels.count) * 7)
        bytes.append(contentsOf: protocolName)
        bytes.append(streamVersion.major)
        bytes.append(streamVersion.minor)
        bytes.append(sequenceNumber)
        bytes.append(reserved2.0)
        bytes.append(reserved2.1)
        bytes.append(colorSpace.rawValue)
        bytes.append(reserved1)
        bytes.append(contentsOf: areaBytes)

        for (channelID, channel) in mappedChannels.prefix(maxChannelsPerPacket) {
            bytes.append(channelID)

            let c1: UInt16
            let c2: UInt16
            let c3: UInt16

            switch colorSpace {
            case .xyb:
                c1 = quantizeNormalized(channel.xy.x)
                c2 = quantizeNormalized(channel.xy.y)
                c3 = quantizeNormalized(channel.brightness)
            case .rgb:
                c1 = quantizeNormalized(channel.xy.x)
                c2 = quantizeNormalized(channel.xy.y)
                c3 = quantizeNormalized(channel.brightness)
            }

            appendBigEndian(c1, to: &bytes)
            appendBigEndian(c2, to: &bytes)
            appendBigEndian(c3, to: &bytes)
        }

        return Data(bytes)
    }

    private func quantizeNormalized(_ value: Double) -> UInt16 {
        let scaled = Int((max(0.0, min(1.0, value)) * 65535.0).rounded())
        return UInt16(max(0, min(65535, scaled)))
    }

    private func appendBigEndian(_ value: UInt16, to bytes: inout [UInt8]) {
        let bigEndian = value.bigEndian
        withUnsafeBytes(of: bigEndian) { bytes.append(contentsOf: $0) }
    }
}
