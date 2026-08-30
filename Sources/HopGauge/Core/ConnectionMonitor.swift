import Foundation

/// 连接监控：lsof（连接清单）+ nettop（字节计数差分出速率）
final class ConnectionMonitor {

    struct LsofRow {
        var pid: Int
        var command: String
        var proto: String        // TCP / UDP
        var family: String       // IPv4 / IPv6
        var local: String
        var remote: String
        var state: String
    }

    struct NettopSnapshot {
        var processTotals: [Int: (name: String, bytesIn: Int64, bytesOut: Int64)] = [:]
        var flows: [String: (pid: Int, bytesIn: Int64, bytesOut: Int64)] = [:]   // key: "local->remote"
    }

    // 上一次采样（差分用）
    private var lastFlowCounters: [String: (in: Int64, out: Int64, at: Date)] = [:]
    private var lastProcCounters: [Int: (in: Int64, out: Int64, at: Date)] = [:]
    private var lastRetrans: Int64 = 0
    private var lastRetransAt = Date()
    private var cycle = 0

    func loops(model: AppModel) -> [Task<Void, Never>] {
        [Task { await self.loop(model: model) }]
    }

    private func loop(model: AppModel) async {
        while !Task.isCancelled {
            await sample(model: model)
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    /// 单次采样（刷新按钮也调用）
    func sample(model: AppModel) async {
        do {
            let rows = await sampleLsof()
            let nettop = await sampleNettop()

            let now = Date()

            // 连接级速率
            var connRows: [ConnectionRow] = []
            var listenRows: [ConnectionRow] = []
            for row in rows {
                let key = row.remote.isEmpty ? nil : "\(row.local)->\(row.remote)"
                var rateIn: Double = 0
                var rateOut: Double = 0
                var bIn: Int64 = 0
                var bOut: Int64 = 0
                if let key, let flow = nettop.flows[key] {
                    bIn = flow.bytesIn
                    bOut = flow.bytesOut
                    if let prev = lastFlowCounters[key] {
                        let dt = now.timeIntervalSince(prev.at)
                        if dt > 0.2 {
                            rateIn = flow.bytesIn >= prev.in ? Double(flow.bytesIn - prev.in) / dt : 0
                            rateOut = flow.bytesOut >= prev.out ? Double(flow.bytesOut - prev.out) / dt : 0
                        }
                    }
                    lastFlowCounters[key] = (flow.bytesIn, flow.bytesOut, now)
                }
                let c = ConnectionRow(
                    process: row.command, pid: row.pid, proto: row.proto, family: row.family,
                    local: row.local, remote: row.remote.isEmpty ? "" : row.remote,
                    state: row.state.isEmpty ? "—" : row.state,
                    bytesIn: bIn, bytesOut: bOut, rateIn: rateIn, rateOut: rateOut)
                if c.isListen {
                    listenRows.append(c)
                } else if c.hasRemote {
                    connRows.append(c)
                }
            }
            // 清理已消失连接的计数器
            let activeKeys = Set(connRows.map { "\($0.local)->\($0.remote)" })
            lastFlowCounters = lastFlowCounters.filter { activeKeys.contains($0.key) }

            // 进程级聚合
            var connCountByPid: [Int: Int] = [:]
            for r in connRows where r.proto == "TCP" {
                connCountByPid[r.pid, default: 0] += 1
            }
            var processes: [ProcessTraffic] = []
            var totalIn: Double = 0
            var totalOut: Double = 0
            for (pid, stat) in nettop.processTotals {
                let name = rows.first(where: { $0.pid == pid })?.command ?? stat.name
                var rateIn: Double = 0
                var rateOut: Double = 0
                if let prev = lastProcCounters[pid] {
                    let dt = now.timeIntervalSince(prev.at)
                    if dt > 0.2 {
                        rateIn = stat.bytesIn >= prev.in ? Double(stat.bytesIn - prev.in) / dt : 0
                        rateOut = stat.bytesOut >= prev.out ? Double(stat.bytesOut - prev.out) / dt : 0
                    }
                }
                lastProcCounters[pid] = (stat.bytesIn, stat.bytesOut, now)
                totalIn += rateIn
                totalOut += rateOut
                processes.append(ProcessTraffic(
                    name: name, pid: pid, rateIn: rateIn, rateOut: rateOut,
                    totalIn: stat.bytesIn, totalOut: stat.bytesOut,
                    connections: connCountByPid[pid, default: 0]))
            }
            processes.sort { ($0.rateIn + $0.rateOut) > ($1.rateIn + $1.rateOut) }
            let totalInSnap = totalIn
            let totalOutSnap = totalOut

            // TCP 重传率（每 10 个周期采样一次）
            var retransRate: Double?
            if cycle % 10 == 0 {
                if let out = await Shell.run("/usr/sbin/netstat", ["-s", "-p", "tcp"], timeout: 5),
                   let caps = regexCapture(#"(\d+) data packet.*?retransmitted"#, from: out),
                   let count = Int64(caps[0]) {
                    let dt = lastRetransAt.timeIntervalSince(now) // 负值
                    let elapsed = -dt
                    if elapsed > 5 {
                        retransRate = count >= lastRetrans
                            ? Double(count - lastRetrans) / elapsed * 60 : 0
                    }
                    lastRetrans = count
                    lastRetransAt = now
                }
            }
            cycle += 1

            let connSnapshot = connRows
            let listenSnapshot = listenRows
            let procSnapshot = processes
            let retransSnapshot = retransRate
            await MainActor.run {
                model.connections = connSnapshot
                model.listenRows = listenSnapshot
                model.processTraffic = procSnapshot
                model.recordProcessRates(procSnapshot)
                model.totalRateIn = totalInSnap
                model.totalRateOut = totalOutSnap
                model.rateHistory.append((totalInSnap, totalOutSnap))
                if model.rateHistory.count > 90 { model.rateHistory.removeFirst(model.rateHistory.count - 90) }
                if let rate = retransSnapshot {
                    model.tcpRetransPerMin = rate
                }
            }

        }
    }

    // MARK: - lsof -F 机器可读模式

    private func sampleLsof() async -> [LsofRow] {
        guard let text = await Shell.run("/usr/sbin/lsof", ["-i", "-n", "-P", "-F", "pcPnT"], timeout: 8) else {
            return []
        }
        return Self.parseLsofF(text)
    }

    static func parseLsofF(_ text: String) -> [LsofRow] {
        var rows: [LsofRow] = []
        var pid: Int?
        var command: String?

        var pendingProto: String?
        var pendingName: String?
        var pendingState: String?

        func flush() {
            guard let pid, let command, let proto = pendingProto, let name = pendingName else { return }
            let (local, remote) = splitName(name)
            let family = name.contains("[") ? "IPv6" : "IPv4"
            rows.append(LsofRow(pid: pid, command: command, proto: proto,
                                family: family, local: local, remote: remote,
                                state: pendingState ?? ""))
            pendingProto = nil; pendingName = nil; pendingState = nil
        }

        for lineRaw in text.split(separator: "\n") {
            let line = String(lineRaw)
            guard line.count > 1 else { continue }
            let field = line.first!
            let value = String(line.dropFirst())
            switch field {
            case "p":
                flush()
                pid = Int(value)
                command = nil
            case "f":
                // 新的文件描述符块开始；UDP 没有 TST 行，在这里兜底 flush
                if pendingName != nil { flush() }
            case "c":
                command = value
            case "P":
                pendingProto = value
            case "n":
                pendingName = value
            case "T":
                if value.hasPrefix("ST=") {
                    pendingState = String(value.dropFirst(3))
                    flush()
                }
            default:
                break
            }
        }
        flush()
        return rows
    }

    /// "192.168.2.106:64499->192.168.2.108:49155" → (local, remote)；"*:3722" → ("*:3722", "")
    static func splitName(_ name: String) -> (local: String, remote: String) {
        if let range = name.range(of: "->") {
            return (String(name[..<range.lowerBound]), String(name[range.upperBound...]))
        }
        return (name, "")
    }

    // MARK: - nettop CSV

    private func sampleNettop() async -> NettopSnapshot {
        guard let text = await Shell.run("/usr/bin/nettop", ["-x", "-L", "1", "-J", "bytes_in,bytes_out"], timeout: 8) else {
            return NettopSnapshot()
        }
        return Self.parseNettop(text)
    }

    static func parseNettop(_ text: String) -> NettopSnapshot {
        var snap = NettopSnapshot()
        var currentPid: Int?

        for lineRaw in text.split(separator: "\n") {
            let line = String(lineRaw).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let cols = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard cols.count >= 3 else { continue }
            let first = cols[0]

            // 进程头：name.pid
            if !first.isEmpty, !first.hasPrefix("tcp") && !first.hasPrefix("udp"),
               let dotIdx = first.lastIndex(of: "."),
               let pid = Int(first[first.index(after: dotIdx)...]) {
                let name = String(first[..<dotIdx])
                snap.processTotals[pid] = (name, Int64(cols[1]) ?? 0, Int64(cols[2]) ?? 0)
                currentPid = pid
                continue
            }
            // 流行：tcp4 local<->remote
            if first.hasPrefix("tcp") || first.hasPrefix("udp") {
                guard let arrow = first.range(of: "<->") else { continue }
                let local = String(first[first.startIndex..<arrow.lowerBound])
                    .components(separatedBy: " ").last ?? ""
                let remote = String(first[arrow.upperBound...])
                let key = "\(local)->\(remote)"
                snap.flows[key] = (currentPid ?? 0, Int64(cols[1]) ?? 0, Int64(cols[2]) ?? 0)
            }
        }
        return snap
    }
}
