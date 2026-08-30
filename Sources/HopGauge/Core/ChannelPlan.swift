import Foundation

/// 信道占用分析：带宽条布局、重叠判定、路由器调整建议
enum ChannelPlan {

    enum CongestionLevel: Equatable {
        case low, medium, high

        var localizationKey: String {
            switch self {
            case .low: return "lk.congestion.low"
            case .medium: return "lk.congestion.medium"
            case .high: return "lk.congestion.high"
            }
        }
    }

    struct APBar: Identifiable {
        let id = UUID()
        let ssid: String
        let channel: Int
        let widthMHz: Int
        let rssi: Int?
        let isCurrent: Bool
        let overlapsCurrent: Bool
        var isOwnRouter: Bool = false

        /// 信道号跨度（每个信道号 = 5MHz）
        var spanChannels: Double { Double(widthMHz) / 5.0 }
        var left: Double { Double(channel) - spanChannels / 2 }
        var right: Double { Double(channel) + spanChannels / 2 }
    }

    struct BandAnalysis {
        var band: String
        var bars: [APBar] = []
        var current: APBar?
        var overlapCount: Int = 0          // 与当前网络重叠的邻居数
        var pairOverlapCount: Int = 0      // 该频段内任意两两重叠对数（拥挤度）
        var recommendation: String = ""    // 中文建议
        var conflict: Bool { overlapCount > 0 && current != nil }
    }

    /// 两个 AP 频谱是否重叠（信道号单位：1 号 = 5MHz）
    static func overlaps(_ a: (channel: Int, width: Int), _ b: (channel: Int, width: Int)) -> Bool {
        let aL = Double(a.channel) - Double(a.width) / 10.0
        let aR = Double(a.channel) + Double(a.width) / 10.0
        let bL = Double(b.channel) - Double(b.width) / 10.0
        let bR = Double(b.channel) + Double(b.width) / 10.0
        return aL < bR && bL < aR
    }

    static func congestionLevel(for overlapCount: Int) -> CongestionLevel {
        if overlapCount <= 2 { return .low }
        if overlapCount <= 4 { return .medium }
        return .high
    }

    static func analyze(band: String,
                        neighbors: [NeighborNetwork],
                        current: (channel: Int, width: Int, ssid: String)?) -> BandAnalysis {
        var result = BandAnalysis(band: band)

        for n in neighbors where n.band == band {
            let width = n.widthMHz ?? 20
            // 自己的路由器（同 SSID 另一频段等）不算外部冲突
            let ol = (!n.isOwnRouter)
                && current.map { overlaps((n.channel, width), ($0.channel, $0.width)) } == true
            result.bars.append(APBar(ssid: n.ssid, channel: n.channel, widthMHz: width,
                                     rssi: n.rssi, isCurrent: false, overlapsCurrent: ol,
                                     isOwnRouter: n.isOwnRouter))
        }
        if let cur = current {
            let ol = neighbors.filter {
                $0.band == band && !$0.isOwnRouter &&
                overlaps(($0.channel, $0.widthMHz ?? 20), (cur.channel, cur.width))
            }
            let bar = APBar(ssid: cur.ssid, channel: cur.channel, widthMHz: cur.width,
                            rssi: nil, isCurrent: true, overlapsCurrent: false)
            result.current = bar
            result.bars.append(bar)
            result.overlapCount = ol.count
        }

        // 两两重叠对数（拥挤度指标，仅统计外部网络之间）
        let list = result.bars.filter { !$0.isOwnRouter }
        var pairs = 0
        for i in 0..<list.count {
            for j in (i + 1)..<list.count {
                if overlaps((list[i].channel, list[i].widthMHz), (list[j].channel, list[j].widthMHz)) {
                    pairs += 1
                }
            }
        }
        result.pairOverlapCount = pairs

        // 建议
        if band == "2.4GHz" {
            let nonOverlap = [1, 6, 11]
            let load: [Int: Int] = {
                var d: [Int: Int] = [:]
                for b in result.bars {
                    for base in nonOverlap where overlaps((b.channel, b.widthMHz), (base, 20)) {
                        d[base, default: 0] += 1
                    }
                }
                return d
            }()
            let best = nonOverlap.min { (load[$0] ?? 0) < (load[$1] ?? 0) } ?? 1
            if result.bars.isEmpty {
                result.recommendation = L10n.t("ch.24.clean")
            } else {
                let desc = nonOverlap.map { "Ch\($0): \(load[$0, default: 0])" }.joined(separator: " · ")
                let mine = current != nil && current!.channel <= 14
                result.recommendation = mine
                    ? L10n.tf("ch.24.pick", desc, current!.channel, best)
                    : L10n.tf("ch.24.noise", result.bars.count, desc)
            }
        } else {
            if result.current == nil {
                result.recommendation = result.bars.isEmpty
                    ? L10n.t("ch.5.empty")
                    : L10n.tf("ch.5.noncurrent", result.bars.count)
            } else {
                let cur = result.current!
                if result.overlapCount == 0 {
                    result.recommendation = L10n.tf("ch.current.noconflict", "\(cur.channel)", "\(cur.widthMHz)MHz")
                } else {
                    let width = cur.widthMHz >= 160
                        ? L10n.tf("ch.width.160", "\(cur.widthMHz)MHz")
                        : L10n.t("ch.width.move")
                    result.recommendation = L10n.tf("ch.current.overlap", "\(cur.channel)", "\(cur.widthMHz)MHz",
                                                    result.overlapCount,
                                                    listBars(result.bars, overlapping: cur)) + "。" + width
                }
            }
        }
        return result
    }

    private static func listBars(_ bars: [APBar], overlapping current: APBar) -> String {
        bars.filter { !$0.isCurrent && $0.overlapsCurrent }
            .prefix(4)
            .map { "\($0.ssid) Ch\($0.channel)" }
            .joined(separator: "、")
    }

    /// 该频段上"最拥挤"的信道（重叠 AP 数最多的 20MHz 槽位，只统计外部网络）
    static func busiestChannel(_ bars: [APBar]) -> (channel: Int, count: Int)? {
        var count: [Int: Int] = [:]
        for b in bars where !b.isOwnRouter {
            // 每个 AP 覆盖的 20MHz 槽位（信道号步进 4）
            let slots = Int((b.spanChannels / 4).rounded())
            for i in 0..<max(slots, 1) {
                let slotChannel = b.channel - (b.channel % 4) + i * 4
                count[slotChannel, default: 0] += 1
            }
        }
        guard let best = count.max(by: { $0.value < $1.value }) else { return nil }
        return (best.key, best.value)
    }

    /// 2.4GHz 轴：1...14；5GHz 轴：36...165（步进 4 的 20MHz 槽位）
    static func axisChannels(band: String) -> [Int] {
        band == "2.4GHz" ? Array(1...14) : Array(stride(from: 36, through: 165, by: 4))
    }

    /// 把 AP 分配到不互相压盖的"泳道"，用于频谱图分层绘制
    static func lanes(for bars: [APBar]) -> [[APBar]] {
        let sorted = bars.sorted { $0.left < $1.left }
        var lanes: [[APBar]] = []
        for bar in sorted {
            var placed = false
            for i in 0..<lanes.count {
                if let last = lanes[i].last, bar.left >= last.right {
                    lanes[i].append(bar)
                    placed = true
                    break
                }
            }
            if !placed {
                lanes.append([bar])
            }
        }
        return lanes
    }

    /// 路由器调整步骤（通用指引文本）
    static func routerHowTo(gateway: String?) -> String {
        let gw = gateway ?? "192.168.1.1"
        return L10n.tf("ch.router.howto", gw)
    }
}
