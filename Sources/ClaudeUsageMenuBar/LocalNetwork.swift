import Foundation

enum LocalNetwork {
    /// The Mac's LAN IPv4 address on the Wi-Fi interface (`en0`), so an iPhone
    /// on the same network can type `http://<address>:<port>` into Safari.
    /// Returns nil when Wi-Fi is off or has no IPv4 address (e.g. Ethernet-only setups).
    static func currentIPv4Address() -> String? {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let firstAddr = ifaddrPtr else { return nil }
        defer { freeifaddrs(ifaddrPtr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            guard let ifaAddr = interface.ifa_addr, ifaAddr.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }
            guard String(cString: interface.ifa_name) == "en0" else {
                continue
            }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                ifaAddr,
                socklen_t(ifaAddr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else { continue }
            return String(cString: hostname)
        }
        return nil
    }
}
