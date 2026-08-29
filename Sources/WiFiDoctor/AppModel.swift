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
        var score = 100.0
        if let rssi = wifi.rssi {
            let q = Quality.rssi(rssi)
            switch q {
            case .good: score -= 0
            case .fair: score -= 6
            case .poor: score -= 18
            case .bad: score -= 32
            }
        } else {
            score -= 40
        }
        if !wifi.connected { score -= 30 }
        for (i, p) in pingTargets.enumerated() {
            let weight = i == 0 ? 0.5 : 0.25
            score -= min(p.lossPct * 1.2, 20) * weight
            if let avg = p.avg {
                if avg > 100 { score -= 10 * weight }
                else if avg > 40 { score -= 5 * weight }
            }
            if p.jitter > 15 { score -= 6 * weight }
        }
        if let dns = dnsResults.first(where: { $0.server == "系统" }), let ms = dns.ms, ms > 200 {
            score -= 8
        }
        return max(0, min(100, Int(score.rounded())))
    }

    /// 当前信道同频邻居数（排除自己的路由器）
    var coChannelNeighbors: Int {
        guard let ch = wifi.channel else { return 0 }
        return neighbors.filter { $0.channel == ch && !$0.isOwnRouter }.count
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
