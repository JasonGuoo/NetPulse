import Foundation

/// 采集协调器：持有各 Core 子系统，统一启停采集循环与按需动作
final class CoreCoordinator {

    private let model: AppModel
    private var loops: [Task<Void, Never>] = []
    private var verdictLoop: Task<Void, Never>?

    private let wifiCollector = WifiInfoCollector()
    private let netCollector = NetOverviewCollector()
    private let connectionMonitor = ConnectionMonitor()
    private let pingMonitor = PingMonitor()

    init(model: AppModel) {
        self.model = model
    }

    func startAll() {
        guard loops.isEmpty else { return }
        loops += wifiCollector.loops(model: model)
        loops += netCollector.loops(model: model)
        loops += connectionMonitor.loops(model: model)
        loops += pingMonitor.loops(model: model)
        verdictLoop = Task { await verdictLoopBody() }
    }

    func stopAll() {
        loops.forEach { $0.cancel() }
        loops.removeAll()
        verdictLoop?.cancel()
        verdictLoop = nil
    }

    /// 手动刷新：全部子系统立即重采一轮（含周边 WiFi 扫描）
    func refreshAll() async {
        await MainActor.run { model.isRefreshing = true }
        defer { Task { await MainActor.run { model.isRefreshing = false } } }

        async let live: Void = WifiInfoCollector.pollLive(model: model)
        async let scan: Void = WifiInfoCollector.scanProfiler(model: model)
        async let net: Void = NetOverviewCollector.pollMain(model: model)
        async let conn: Void = connectionMonitor.sample(model: model)

        // 立即补一轮 ping
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<4 {
                group.addTask { [weak self] in
                    guard let self else { return }
                    let host = await MainActor.run {
                        index < self.model.pingTargets.count ? self.model.pingTargets[index].host : ""
                    }
                    guard !host.isEmpty else { return }
                    let result = await PingMonitor.pingOnce(host: host)
                    await MainActor.run {
                        self.model.updatePing(index: index, ms: result.ms, success: result.success)
                    }
                }
            }
        }

        _ = await (live, scan, net, conn)
    }

    /// 周期性刷新总览结论（跟随采集节奏，5s 一次）
    private func verdictLoopBody() async {
        // 等首批数据
        try? await Task.sleep(nanoseconds: 6_000_000_000)
        while !Task.isCancelled {
            let wifi = model.wifi
            let pings = model.pingTargets
            let coChannel = model.coChannelNeighbors
            let dnsMs = model.dnsResults.first(where: { $0.server.hasPrefix(L10n.t("dns.system")) })?.ms
            let publicIP = model.overview.publicIP

            let verdicts = Diagnoser.overviewVerdicts(
                wifi: wifi, pings: pings, coChannel: coChannel,
                dnsSystemMs: dnsMs, publicIP: publicIP)

            await MainActor.run {
                model.verdicts = verdicts
            }
            try? await Task.sleep(nanoseconds: 5_000_000_000)
        }
    }

    // MARK: - 按需动作（UI 触发）

    func runSpeedTest() async {
        let result = await SpeedTest.run { [weak self] liveMbps, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                var s = self.model.lastSpeed
                s.downloadMbps = liveMbps
                s.measuredAt = Date()
                self.model.lastSpeed = s
            }
        }
        await MainActor.run {
            model.lastSpeed = result
        }
    }

    func runDiagnosis(url rawURL: String) async {
        // 1. HTTP 五段分解
        let timing = await HttpTiming.measure(url: rawURL)
        // 2. DNS 对比（用目标域名）
        let host = HttpTiming.normalize(rawURL)?.host ?? rawURL
        let dns = await DnsBench.run(host: host)
        // 3. 归因
        let verdicts = Diagnoser.urlVerdicts(
            timing: timing, dnsResults: dns,
            wifi: model.wifi, pings: model.pingTargets)

        await MainActor.run {
            var t = timing
            t.verdicts = verdicts
            model.lastTiming = t
            model.dnsResults = dns
        }
    }
}
