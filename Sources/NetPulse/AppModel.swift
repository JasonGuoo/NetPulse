import Foundation
import Combine

/// 全局状态中枢：Core 采集模块写入，UI 读取
final class AppModel: ObservableObject {

    // MARK: - 发布状态

    @Published var wifi = WifiLinkState()
    @Published var overview = NetOverviewState()
    @Published var connections: [ConnectionRow] = []
    @Published var processTraffic: [ProcessTraffic] = []
    @Published var listenRows: [ConnectionRow] = []
    @Published var totalRateIn: Double = 0
    @Published var totalRateOut: Double = 0
    @Published var rateHistory: [(in: Double, out: Double)] = []
    @Published var processRateHistory: [String: [Double]] = [:]

    @Published var pingTargets: [PingTargetState] = [
        PingTargetState(label: "网关", host: ""),
        PingTargetState(label: "DNS", host: "1.1.1.1"),
        PingTargetState(label: "Cloudflare", host: "1.1.1.1"),
        PingTargetState(label: "Google", host: "8.8.8.8"),
    ]

    @Published var neighbors: [NeighborNetwork] = []
    @Published var verdicts: [Verdict] = []
    @Published var lastSpeed = SpeedResult()
    @Published var speedTesting = false

    @Published var lastTiming: HttpTimingResult?
    @Published var diagnosing = false
    @Published var dnsResults: [DnsResult] = []

    @Published var running = false
    @Published var tcpRetransPerMin: Double = 0   // TCP 重传包/分钟（系统级）
    @Published var lastScanAt: Date?              // 上次周边 WiFi 扫描时间
    @Published var isRefreshing = false           // 手动刷新进行中

    // MARK: - 派生

    /// 综合健康度 0-100
    var healthScore: Int {
        guard wifi.connected else { return 20 }
        let weighted = Double(wifiHealthScore) * 0.24
            + Double(gatewayHealthScore) * 0.22
            + Double(dnsHealthScore) * 0.16
            + Double(internetHealthScore) * 0.28
            + Double(stabilityHealthScore) * 0.10
        var score = Int(weighted.rounded())
        let weakest = min(wifiHealthScore, gatewayHealthScore, dnsHealthScore, internetHealthScore)
        // A visibly degraded path must be reflected in the headline score; averaging must not hide it.
        if weakest < 85 { score = min(score, 84) }
        if weakest < 50 { score = min(score, 69) }
        return max(0, min(100, score))
    }

    var wifiHealthScore: Int {
        guard wifi.connected, let rssi = wifi.rssi else { return 20 }
        var score = 100
        switch Quality.rssi(rssi) {
        case .good: break
        case .fair: score -= 8
        case .poor: score -= 24
        case .bad: score -= 45
        }
        if wifi.snr < 20 { score -= 22 }
        else if wifi.snr < 30 { score -= 10 }
        if coChannelNeighbors >= 4 { score -= 10 }
        return max(0, min(100, score))
    }

    var gatewayHealthScore: Int { score(for: gatewayPing, warningMs: 30, badMs: 80) }
    var dnsHealthScore: Int {
        if let system = dnsResults.first(where: { $0.server.hasPrefix(L10n.t("dns.system")) }),
           let ms = system.ms {
            if ms > 400 { return 35 }
            if ms > 200 { return 58 }
            if ms > 80 { return 82 }
            return 100
        }
        return score(for: dnsPing, warningMs: 80, badMs: 200)
    }
    var internetHealthScore: Int { score(for: internetPing, warningMs: 100, badMs: 250) }
    var stabilityHealthScore: Int {
        let targets = pingTargets.filter { !$0.host.isEmpty && $0.sent > 0 }
        guard !targets.isEmpty else { return 88 }
        let worstLoss = targets.map(\.lossPct).max() ?? 0
        let worstJitter = targets.map(\.jitter).max() ?? 0
        var score = 100
        score -= Int(min(worstLoss * 5, 45))
        score -= Int(min(worstJitter * 1.5, 35))
        if tcpRetransPerMin > 10 { score -= 12 }
        return max(0, min(100, score))
    }

    var gatewayPing: PingTargetState? {
        pingTargets.first(where: { $0.label == L10n.t("pk.gateway") || $0.label == "网关" || $0.label.lowercased() == "gateway" })
            ?? pingTargets.first
    }

    var dnsPing: PingTargetState? {
        pingTargets.first(where: { $0.label.hasPrefix("DNS") || $0.label.localizedCaseInsensitiveContains("dns") })
    }

    var internetPing: PingTargetState? {
        pingTargets.filter { !$0.host.isEmpty }.dropFirst(2).first(where: { $0.avg != nil })
            ?? pingTargets.filter { !$0.host.isEmpty }.dropFirst().first(where: { $0.avg != nil })
    }

    /// 当前信道同频邻居数（排除自己的路由器）
    var coChannelNeighbors: Int {
        guard let ch = wifi.channel else { return 0 }
        return neighbors.filter { $0.channel == ch && !$0.isOwnRouter }.count
    }

    func recordProcessRates(_ processes: [ProcessTraffic]) {
        let activeIDs = Set(processes.map(\.id))
        for process in processes {
            var history = processRateHistory[process.id] ?? []
            history.append(process.rateIn + process.rateOut)
            if history.count > 48 { history.removeFirst(history.count - 48) }
            processRateHistory[process.id] = history
        }
        processRateHistory = processRateHistory.filter { activeIDs.contains($0.key) }
    }

    private func score(for target: PingTargetState?, warningMs: Double, badMs: Double) -> Int {
        guard let target else { return 82 }
        var score = 100
        if let avg = target.avg {
            if avg >= badMs { score -= 42 }
            else if avg >= warningMs { score -= 18 }
        }
        score -= Int(min(target.lossPct * 6, 50))
        score -= Int(min(target.jitter, 20))
        return max(0, min(100, score))
    }

    // MARK: - 生命周期（Core 接入后启动采集循环）

    func start() {
        guard !running else { return }
        running = true
        coordinator?.startAll()
    }

    func stop() {
        running = false
        coordinator?.stopAll()
    }

    // Core 协调器（避免 UI 层直接持有子系统的细节）
    var coordinator: CoreCoordinator?

    // MARK: - 采集写入

    func applyWifiLive(_ snap: WifiInfoCollector.LiveSnapshot) {
        var w = wifi
        w.interface = snap.interface ?? w.interface
        w.rssi = snap.rssi
        w.noise = snap.noise
        w.txRate = snap.txRate
        if snap.channel != nil { w.channel = snap.channel }
        if snap.band != nil { w.band = snap.band }
        if snap.security != nil { w.security = snap.security }
        if snap.phyMode != nil { w.phyMode = snap.phyMode }
        w.connected = snap.connected
        wifi = w
        pushWifiHistory()
    }

    func applyWifiProfiler(_ info: WifiInfoCollector.ProfilerInfo?) {
        guard let info else { return }
        var w = wifi
        w.ssid = info.ssid ?? w.ssid
        if info.channel != nil { w.channel = info.channel }
        if info.band != nil { w.band = info.band }
        w.channelWidthMHz = info.widthMHz ?? w.channelWidthMHz
        w.mcs = info.mcs ?? w.mcs
        w.country = info.country ?? w.country
        if info.security != nil { w.security = info.security }
        if info.phyMode != nil { w.phyMode = info.phyMode }
        wifi = w
    }

    private func pushWifiHistory() {
        if let r = wifi.rssi {
            wifi.rssiHistory.append(Double(r))
            if wifi.rssiHistory.count > 90 { wifi.rssiHistory.removeFirst(wifi.rssiHistory.count - 90) }
            wifi.snrHistory.append(Double(wifi.snr))
            if wifi.snrHistory.count > 90 { wifi.snrHistory.removeFirst(wifi.snrHistory.count - 90) }
        }
        if let t = wifi.txRate {
            wifi.txRateHistory.append(t)
            if wifi.txRateHistory.count > 90 { wifi.txRateHistory.removeFirst(wifi.txRateHistory.count - 90) }
        }
    }

    func updatePing(index: Int, ms: Double?, success: Bool) {
        guard index < pingTargets.count else { return }
        var t = pingTargets[index]
        t.sent += 1
        if success {
            t.received += 1
            t.last = ms
            if let ms {
                t.history.append(ms)
                if t.history.count > 60 { t.history.removeFirst(t.history.count - 60) }
                let recent = t.history.suffix(20)
                t.avg = recent.reduce(0, +) / Double(recent.count)
            }
        } else {
            t.last = nil
        }
        pingTargets[index] = t
    }
}
