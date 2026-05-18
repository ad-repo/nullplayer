import Foundation

/// Resolves the app's local IPv4 address from active Ethernet-style interfaces.
enum NetworkInterfaceResolver {
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
}
