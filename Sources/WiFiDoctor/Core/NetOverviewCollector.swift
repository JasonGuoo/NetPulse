import Foundation

/// 网络概况采集：网关/DNS/代理/VPN/本机 IP/公网出口
final class NetOverviewCollector {

    func loops(model: AppModel) -> [Task<Void, Never>] {
        [
            Task { await self.mainLoop(model: model) },
            Task { await self.publicIPLoop(model: model) },
        ]
    }

    // MARK: - 主循环（10s）

    private func mainLoop(model: AppModel) async {
        while !Task.isCancelled {
            await Self.pollMain(model: model)
            try? await Task.sleep(nanoseconds: 10_000_000_000)
        }
    }

    /// 单次网络概况采集（刷新按钮也调用）
    static func pollMain(model: AppModel) async {
        var gateway: String?
            var iface: String?

            if let out = await Shell.run("/sbin/route", ["-n", "get", "default"], timeout: 5) {
                gateway = regexCapture(#"gateway: (\S+)"#, from: out)?[0]
                iface = regexCapture(#"interface: (\S+)"#, from: out)?[0]
            }

            var dns: [String] = []
            var dhcpDNS: [String] = []
            if let out = await Shell.run("/usr/sbin/scutil", ["--dns"], timeout: 5) {
                dns = Self.parsePrimaryNameservers(out)
            }
            if let ifName = iface ?? model.wifi.interface,
               let out = await Shell.run("/usr/sbin/ipconfig", ["getoption", ifName, "domain_name_server"], timeout: 5) {
                dhcpDNS = out.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            }
            // dnsSource 存原始值（manual/dhcp），显示层负责本地化
            let dnsSource: String?
            if dns.isEmpty {
                dnsSource = nil
            } else if Set(dns) == Set(dhcpDNS), !dhcpDNS.isEmpty {
                dnsSource = "dhcp"
            } else if !dhcpDNS.isEmpty {
                dnsSource = "manual"
            } else {
                dnsSource = nil
            }

            var proxies: [ProxyEntry] = []
            if let out = await Shell.run("/usr/sbin/scutil", ["--proxy"], timeout: 5) {
                proxies = Self.parseProxy(out)
            }

            var vpn: [String] = []
            if let out = await Shell.run("/usr/sbin/scutil", ["--nc", "list"], timeout: 5) {
                vpn = Self.parseVPN(out)
            }
            let utuns = IfAddrs.interfaceNames(prefix: "utun")
            if !utuns.isEmpty {
                let label = L10n.tf("ip.tunnel.fmt", utuns.count, utuns.prefix(3).joined(separator: "、"))
                if vpn.isEmpty { vpn = [label] } else { vpn.append("utun×\(utuns.count)") }
            }

            var ipv4: String?
            var mask: String?
            var ipv6: String?
            if let ifName = iface ?? model.wifi.interface {
                let addr = IfAddrs.ipv4AndMask(of: ifName)
                ipv4 = addr?.ip
                mask = addr?.mask
                ipv6 = IfAddrs.ipv6(of: ifName)
            }

            await MainActor.run {
                var o = model.overview
                o.gateway = gateway
                o.dnsServers = dns
                o.dnsSource = dnsSource
                o.dhcpDNS = dhcpDNS
                o.proxies = proxies
                o.vpnActive = vpn
                o.ipv4 = ipv4
                o.mask = mask
                o.ipv6 = ipv6
                o.updated = Date()
                model.overview = o

                // 网关 / 当前 DNS 变化时更新 ping 目标（保留未变化项的历史）
                Self.syncPingTargets(model: model, gateway: gateway, dns: dns.first)
            }
    }

    /// 同步 ping 目标：[0] 网关、[1] 当前生效 DNS、[2][3] 公共对照（与 DNS 重复则置空跳过）
    static func syncPingTargets(model: AppModel, gateway: String?, dns: String?) {
        guard model.pingTargets.count >= 4 else { return }

        if model.pingTargets[0].host != (gateway ?? "") || model.pingTargets[0].label != L10n.t("pk.gateway") {
            model.pingTargets[0] = PingTargetState(label: L10n.t("pk.gateway"), host: gateway ?? "")
        }
        if let dns, !dns.isEmpty {
            let label = "DNS \(dns)"
            if model.pingTargets[1].host != dns {
                model.pingTargets[1] = PingTargetState(label: label, host: dns)
            } else if model.pingTargets[1].label != label {
                model.pingTargets[1].label = label
            }
        }
        // 与当前 DNS 相同的公共对照目标停用（host 置空即跳过）
        let refs: [(Int, String)] = [(2, "1.1.1.1"), (3, "8.8.8.8")]
        for (idx, host) in refs {
            let dup = (dns == host)
            if dup && !model.pingTargets[idx].host.isEmpty {
                model.pingTargets[idx] = PingTargetState(label: model.pingTargets[idx].label, host: "")
            } else if !dup && model.pingTargets[idx].host.isEmpty {
                model.pingTargets[idx] = PingTargetState(
                    label: idx == 2 ? "Cloudflare" : "Google", host: host)
            }
        }
    }

    // MARK: - 公网出口（5 分钟）

    private func publicIPLoop(model: AppModel) async {
        while !Task.isCancelled {
            var ip: String?
            var loc: String?
            var org: String?
            var colo: String?
            var warp: String?

            if let trace = await fetchText("https://www.cloudflare.com/cdn-cgi/trace", timeout: 6) {
                for line in trace.split(separator: "\n") {
                    let parts = line.split(separator: "=", maxSplits: 1)
                    guard parts.count == 2 else { continue }
                    let k = String(parts[0]), v = String(parts[1])
                    switch k {
                    case "ip": ip = v
                    case "loc": loc = v
                    case "colo": colo = v
                    case "warp": warp = v
                    default: break
                    }
                }
            }
            if let info = await fetchText("https://ipinfo.io/json", timeout: 6),
               let data = info.data(using: .utf8),
               let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                if ip == nil { ip = obj["ip"] as? String }
                let city = obj["city"] as? String
                let region = obj["region"] as? String
                let country = obj["country"] as? String
                var parts = [city, region, country].compactMap { $0 }
                if parts.isEmpty, let l = loc { parts = [l] }
                loc = parts.joined(separator: " · ").nilIfEmpty
                org = (obj["org"] as? String)?.nilIfEmpty
            }

            if let ip {
                await MainActor.run {
                    var o = model.overview
                    o.publicIP = ip
                    o.publicIPLocation = loc
                    o.publicIPOrg = org
                    o.colo = colo
                    o.warp = warp
                    o.publicIPUpdated = Date()
                    model.overview = o
                }
            }

            try? await Task.sleep(nanoseconds: 300_000_000_000)
        }
    }

    private func fetchText(_ urlString: String, timeout: TimeInterval) async -> String? {
        guard let url = URL(string: urlString) else { return nil }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (data, resp) = try await session.data(from: url)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    // MARK: - 解析

    /// 取 resolver #1 块中的 nameserver 列表
    static func parsePrimaryNameservers(_ text: String) -> [String] {
        var servers: [String] = []
        var inFirst = false
        for lineRaw in text.split(separator: "\n") {
            let line = lineRaw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("resolver #") {
                if inFirst { break }
                if line.hasPrefix("resolver #1") { inFirst = true }
                continue
            }
            guard inFirst else { continue }
            if let caps = regexCapture(#"^nameserver\[\d+\] : (\S+)$"#, from: line) {
                servers.append(caps[0])
            }
        }
        return servers
    }

    static func parseProxy(_ text: String) -> [ProxyEntry] {
        var dict: [String: String] = [:]
        for lineRaw in text.split(separator: "\n") {
            let line = lineRaw.trimmingCharacters(in: .whitespaces)
            if let caps = regexCapture(#"^(\w+)Enable : 1"#, from: line) {
                dict["\(caps[0])Enabled"] = "1"
            }
            if let caps = regexCapture(#"^(\w+)Proxy : (\S+)$"#, from: line) {
                dict["\(caps[0])Proxy"] = caps[1]
            }
            if let caps = regexCapture(#"^(\w+)Port : (\d+)$"#, from: line) {
                dict["\(caps[0])Port"] = caps[1]
            }
        }
        var entries: [ProxyEntry] = []
        for kind in ["HTTP", "HTTPS", "SOCKS"] {
            if dict["\(kind)Enabled"] == "1",
               let server = dict["\(kind)Proxy"],
               let port = dict["\(kind)Port"] {
                entries.append(ProxyEntry(kind: kind, server: server, port: port))
            }
        }
        return entries
    }

    static func parseVPN(_ text: String) -> [String] {
        text.split(separator: "\n").compactMap { line in
            let s = String(line)
            guard s.contains("*") else { return nil }
            // "* 1  IPSec    ..."
            guard let caps = regexCapture(#"^\*.*?"([^"]+)"#, from: s) else { return nil }
            return caps[0]
        }
    }
}
