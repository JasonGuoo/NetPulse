import Foundation
import Darwin

// MARK: - 正则捕获辅助

func regexCapture(_ pattern: String, from text: String) -> [String]? {
    guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
    let ns = text as NSString
    guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
    return (1..<m.numberOfRanges).map { ns.substring(with: m.range(at: $0)) }
}

// MARK: - getifaddrs 封装

enum IfAddrs {

    static func ipv4AndMask(of interface: String) -> (ip: String, mask: String)? {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return nil }
        defer { freeifaddrs(ifap) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            defer { ptr = p.pointee.ifa_next }
            let ifa = p.pointee
            guard let nameP = ifa.ifa_name, String(cString: nameP) == interface else { continue }
            guard let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }

            var addr = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &addr.sin_addr, &buf, socklen_t(INET_ADDRSTRLEN)) != nil else { continue }
            let ip = String(cString: buf)

            var mask: String = "—"
            if let nmSa = ifa.ifa_netmask {
                var nm = nmSa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                var mbuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                if inet_ntop(AF_INET, &nm.sin_addr, &mbuf, socklen_t(INET_ADDRSTRLEN)) != nil {
                    mask = String(cString: mbuf)
                }
            }
            return (ip, mask)
        }
        return nil
    }

    static func ipv6(of interface: String) -> String? {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return nil }
        defer { freeifaddrs(ifap) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            defer { ptr = p.pointee.ifa_next }
            let ifa = p.pointee
            guard let nameP = ifa.ifa_name, String(cString: nameP) == interface else { continue }
            guard let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET6) else { continue }
            // 只取全局地址，跳过 link-local fe80
            var addr = sa.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee }
            let b0 = addr.sin6_addr.__u6_addr.__u6_addr8.0
            let b1 = addr.sin6_addr.__u6_addr.__u6_addr8.1
            if b0 == 0xfe && (b1 & 0xc0) == 0x80 {
                continue
            }
            var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            guard inet_ntop(AF_INET6, &addr.sin6_addr, &buf, socklen_t(INET6_ADDRSTRLEN)) != nil else { continue }
            return String(cString: buf)
        }
        return nil
    }

    static func interfaceNames(prefix: String) -> [String] {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return [] }
        defer { freeifaddrs(ifap) }

        var names = Set<String>()
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            defer { ptr = p.pointee.ifa_next }
            if let nameP = p.pointee.ifa_name {
                let n = String(cString: nameP)
                if n.hasPrefix(prefix) { names.insert(n) }
            }
        }
        return names.sorted()
    }
}
