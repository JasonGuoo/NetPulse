import Foundation

// MARK: - WiFi 链路状态（CoreWLAN 实时 + system_profiler 补充）

struct WifiLinkState {
    var interface: String?
    var ssid: String?
    var channel: Int?
    var band: String?            // "2.4GHz" / "5GHz" / "6GHz"
    var channelWidthMHz: Int?
    var rssi: Int?               // dBm
    var noise: Int?              // dBm
    var snr: Int { rssi != nil && noise != nil ? rssi! - noise! : 0 }
    var txRate: Double?          // Mbps 协商速率
    var security: String?
    var phyMode: String?
    var mcs: Int?
    var country: String?
    var connected: Bool = false
    var ssidHiddenByPrivacy = false

    var rssiHistory: [Double] = []
    var snrHistory: [Double] = []
    var txRateHistory: [Double] = []
}

// MARK: - 网络概况

struct ProxyEntry: Identifiable, Equatable {
    var id: String { "\(kind)-\(server)-\(port)" }
    let kind: String      // HTTP / HTTPS / SOCKS
    let server: String
    let port: String
}

struct NetOverviewState {
    var gateway: String?
    var dnsServers: [String] = []   // 当前生效（scutil resolver #1）
    var dnsSource: String?          // "DHCP 下发" / "手动设置"
    var dhcpDNS: [String] = []      // 路由器 DHCP 原本下发的 DNS（手动设置时的对照）
    var ipv4: String?
    var ipv6: String?
    var mask: String?
    var proxies: [ProxyEntry] = []
    var vpnActive: [String] = []  // 启用的 VPN/utun 描述
    var publicIP: String?
    var publicIPLocation: String?
    var publicIPOrg: String?
    var colo: String?
    var warp: String?
    var publicIPUpdated: Date?
    var updated: Date?

    var online: Bool { gateway != nil }
}

// MARK: - 连接监控

struct ConnectionRow: Identifiable {
    var id: String { "\(pid)-\(proto)-\(local)-\(remote)" }
    let process: String
    let pid: Int
    let proto: String           // TCP / UDP
    let family: String          // IPv4 / IPv6
    let local: String
    let remote: String
    let state: String           // ESTABLISHED / LISTEN / ...
    var bytesIn: Int64 = 0
    var bytesOut: Int64 = 0
    var rateIn: Double = 0      // B/s
    var rateOut: Double = 0     // B/s
    var rttMs: Double?          // 点选实测
    var rttLoss: Double?

    var isListen: Bool { state == "LISTEN" }
    var hasRemote: Bool { !remote.isEmpty && remote != "*" }
}

struct ProcessTraffic: Identifiable {
    var id: String { "\(pid)-\(name)" }
    let name: String
    let pid: Int
    var rateIn: Double = 0
    var rateOut: Double = 0
    var totalIn: Int64 = 0
    var totalOut: Int64 = 0
    var connections: Int = 0
}

// MARK: - Ping 监测

struct PingTargetState: Identifiable {
    var id: String { label }
    var label: String
    var host: String
    var history: [Double] = []       // ms
    var sent: Int = 0
    var received: Int = 0
    var last: Double?
    var avg: Double?

    var lossPct: Double {
        sent > 0 ? Double(sent - received) / Double(sent) * 100 : 0
    }
    var jitter: Double {
        guard history.count > 2 else { return 0 }
        let recent = Array(history.suffix(20))   // ArraySlice 保留原索引，转 Array 归零
        var diffs: [Double] = []
        for i in 1..<recent.count {
            diffs.append(abs(recent[i] - recent[i - 1]))
        }
        return diffs.reduce(0, +) / Double(diffs.count)
    }
}

// MARK: - 网页诊断

struct HttpPhase: Identifiable {
    var id: String { name }
    let name: String
    let seconds: Double
    let colorIndex: Int
}

struct HttpTimingResult {
    var url: String
    var phases: [HttpPhase] = []
    var total: Double = 0
    var httpStatus: Int?
    var bytes: Int64 = 0
    var error: String?
    var verdicts: [Verdict] = []
    var measuredAt: Date = Date()
}

struct DnsResult: Identifiable {
    var id: String { server }
    let server: String       // "系统" / "1.1.1.1" / ...
    var ms: Double?
    var error: String?
}

enum RouteTraceMethod: String, Equatable {
    case udp = "UDP"
    case icmp = "ICMP"
}

enum RouteTraceFailure: Equatable {
    case invalidTarget
    case unavailable
    case noRoute
}

struct RouteHop: Identifiable, Equatable {
    var id: Int { index }
    let index: Int
    let address: String?
    let latencyMs: Double?
    let annotation: String?

    var responded: Bool { address != nil }
}

struct RouteTraceResult: Equatable {
    let target: String
    var resolvedAddress: String?
    var hops: [RouteHop] = []
    var reachedDestination = false
    var method: RouteTraceMethod = .udp
    var duration: TimeInterval = 0
    var failure: RouteTraceFailure?
    var measuredAt = Date()
}

struct SpeedResult {
    var downloadMbps: Double = 0
    var uploadMbps: Double = 0
    var bytes: Int64 = 0
    var seconds: Double = 0
    var measuredAt: Date?
    var errorNote: String?   // 诊断信息（字节数异常小时记录）
}

// MARK: - 信道占用

struct NeighborNetwork: Identifiable {
    var id: String { "\(ssid)-\(channel)-\(band)" }
    let ssid: String
    let channel: Int
    let band: String           // "2.4GHz" / "5GHz"
    let widthMHz: Int?
    let rssi: Int?             // 部分 AP 可见
    let security: String?
    let phyMode: String?
    var isOwnRouter: Bool = false   // 与当前网络同 SSID（路由器自身/另一频段/mesh 节点）
}

// MARK: - 诊断结论

enum VerdictSeverity {
    case good, info, warn, bad

    var colorIdx: Int {
        switch self {
        case .good: return 0   // green
        case .info: return 1   // cyan
        case .warn: return 2   // yellow
        case .bad: return 3    // red
        }
    }

    var label: String {
        switch self {
        case .good: return L10n.t("sev.good")
        case .info: return L10n.t("sev.info")
        case .warn: return L10n.t("sev.warn")
        case .bad: return L10n.t("sev.bad")
        }
    }
}

struct Verdict: Identifiable {
    var id = UUID()
    let severity: VerdictSeverity
    let title: String
    let detail: String
    var suggestion: String?
}
