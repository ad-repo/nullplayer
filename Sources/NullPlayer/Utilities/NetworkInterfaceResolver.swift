import Darwin
import Foundation

/// Resolves the app's local IPv4 address from active Ethernet-style interfaces.
enum NetworkInterfaceResolver {
    struct InterfaceInfo: Equatable {
        let name: String
        let ipv4Address: String?
        let flags: UInt32
        let hasCounters: Bool

        var isUp: Bool { flags & UInt32(IFF_UP) != 0 }
        var isLoopback: Bool { flags & UInt32(IFF_LOOPBACK) != 0 }

        var displayName: String {
            if let ipv4Address, !ipv4Address.isEmpty {
                return "\(name) \(ipv4Address)"
            }
            return name
        }
    }

    /// Returns the preferred active non-loopback IPv4 address, favoring en0/en1 before other en* adapters.
    static func discoverLocalIPv4Address() -> String? {
        var preferredAddress: String?
        var ethernetAddress: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }

            guard let interface = ptr?.pointee,
                  let socketAddress = interface.ifa_addr,
                  socketAddress.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }

            let flags = Int32(interface.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }

            let name = String(cString: interface.ifa_name)
            guard name.hasPrefix("en") else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(socketAddress, socklen_t(socketAddress.pointee.sa_len),
                                     &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
            guard result == 0 else { continue }

            let address = String(cString: hostname)
            guard !address.isEmpty else { continue }

            if name == "en0" || name == "en1" {
                preferredAddress = address
                break
            }

            if ethernetAddress == nil {
                ethernetAddress = address
            }
        }

        return preferredAddress ?? ethernetAddress
    }

    /// Returns active interfaces by BSD name, including whether AF_LINK byte counters are present.
    static func discoverInterfaces() -> [InterfaceInfo] {
        var ipv4ByName: [String: String] = [:]
        var flagsByName: [String: UInt32] = [:]
        var counterNames = Set<String>()
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0 else { return [] }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }

            guard let interface = ptr?.pointee,
                  let socketAddress = interface.ifa_addr else {
                continue
            }

            let name = String(cString: interface.ifa_name)
            flagsByName[name] = interface.ifa_flags

            switch Int32(socketAddress.pointee.sa_family) {
            case AF_INET:
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let result = getnameinfo(
                    socketAddress,
                    socklen_t(socketAddress.pointee.sa_len),
                    &hostname,
                    socklen_t(hostname.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )
                if result == 0 {
                    let address = String(cString: hostname)
                    if !address.isEmpty {
                        ipv4ByName[name] = address
                    }
                }
            case AF_LINK:
                if interface.ifa_data != nil {
                    counterNames.insert(name)
                }
            default:
                continue
            }
        }

        return flagsByName.map { name, flags in
            InterfaceInfo(
                name: name,
                ipv4Address: ipv4ByName[name],
                flags: flags,
                hasCounters: counterNames.contains(name)
            )
        }
        .filter { $0.isUp && !$0.isLoopback && $0.hasCounters }
        .sorted { lhs, rhs in
            preferredInterfaceRank(lhs.name) < preferredInterfaceRank(rhs.name)
        }
    }

    static func preferredInterfaceName(from interfaces: [InterfaceInfo] = discoverInterfaces()) -> String? {
        interfaces.first?.name
    }

    private static func preferredInterfaceRank(_ name: String) -> (Int, String) {
        if name == "en0" { return (0, name) }
        if name == "en1" { return (1, name) }
        if name.hasPrefix("en") { return (2, name) }
        return (3, name)
    }
}
