import Foundation

/// Ping 监测：网关 / Cloudflare / Google，每秒一发 ICMP
final class PingMonitor {

    func loops(model: AppModel) -> [Task<Void, Never>] {
        (0..<4).map { i in
            Task { await self.loop(targetIndex: i, model: model) }
        }
    }

    private func loop(targetIndex: Int, model: AppModel) async {
        // 等网关地址就绪
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        while !Task.isCancelled {
            let host = await MainActor.run {
                targetIndex < model.pingTargets.count ? model.pingTargets[targetIndex].host : ""
            }
            if !host.isEmpty {
                let result = await Self.pingOnce(host: host)
                await MainActor.run {
                    model.updatePing(index: targetIndex, ms: result.ms, success: result.success)
                }
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    static func pingOnce(host: String) async -> (ms: Double?, success: Bool) {
        let out = await Shell.run("/sbin/ping", ["-c", "1", "-W", "2000", host], timeout: 4)
        guard let out else { return (nil, false) }
        guard let caps = regexCapture(#"time=([0-9.]+) ms"#, from: out), let ms = Double(caps[0]) else {
            return (nil, false)
        }
        return (ms, true)
    }
}
