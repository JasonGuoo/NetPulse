import Foundation

/// 诊断规则引擎：把采集快照归因为本地化结论
enum Diagnoser {

    // MARK: - 总览结论（概况页）

    static func overviewVerdicts(wifi: WifiLinkState,
                                 pings: [PingTargetState],
                                 coChannel: Int,
                                 dnsSystemMs: Double?,
                                 publicIP: String?) -> [Verdict] {
        var verdicts: [Verdict] = []
        guard !pings.isEmpty else { return verdicts }

        let gateway = pings.first
        // The second monitor is the configured DNS resolver. Keep it out of the
        // public-Internet verdict so an ICMP-blocking DNS server cannot look like
        // an ISP outage.
        let internet = pings.dropFirst().filter {
            !$0.label.localizedCaseInsensitiveContains("dns")
        }

        // 1. WiFi 链路
        if !wifi.connected {
            verdicts.append(Verdict(
                severity: .bad, title: L10n.t("vd.wifi.off"),
                detail: L10n.t("vd.wifi.off.detail"),
                suggestion: L10n.t("vd.wifi.off.tip")))
            return verdicts
        }

        var localPathIssue: Verdict?
        if let gw = gateway, gw.sent > 3 {
            if gw.lossPct > 2 || (gw.avg ?? 0) > 30 || gw.jitter > 15 {
                var detail = L10n.tf("vd.wifi.bad.fmt",
                                     Fmt.pct(gw.lossPct),
                                     gw.avg.map { Fmt.ms($0) } ?? L10n.t("dash"),
                                     Fmt.ms(gw.jitter))
                var suggestion: String?
                var title = L10n.t("vd.gateway.bad")
                if let rssi = wifi.rssi, rssi < -70 {
                    detail += L10n.tf("vd.wifi.bad.weak", "\(rssi)")
                    title = L10n.t("vd.wifi.bad")
                    suggestion = L10n.t("vd.wifi.tip.move")
                } else if coChannel >= 4 {
                    detail += L10n.tf("vd.wifi.bad.crowd", coChannel)
                    title = L10n.t("vd.wifi.bad")
                    suggestion = L10n.t("vd.wifi.tip.channel")
                } else {
                    suggestion = L10n.t("vd.gateway.bad.tip")
                }
                localPathIssue = Verdict(severity: .bad, title: title,
                                         detail: detail, suggestion: suggestion)
            }
        }
        if localPathIssue == nil, let rssi = wifi.rssi {
            let q = Quality.rssi(rssi)
            if q == .bad {
                localPathIssue = Verdict(severity: .warn,
                                         title: L10n.tf("vd.wifi.weak", "\(rssi)"),
                                         detail: L10n.tf("vd.wifi.weak.detail", wifi.snr),
                                         suggestion: L10n.t("vd.wifi.weak.tip"))
            } else if coChannel >= 4 {
                localPathIssue = Verdict(severity: .warn, title: L10n.t("vd.wifi.crowd"),
                                         detail: L10n.tf("vd.wifi.crowd.detail",
                                                         wifi.channel.map(String.init) ?? L10n.t("dash"), coChannel),
                                         suggestion: L10n.t("vd.wifi.crowd.tip"))
            }
        }
        if let issue = localPathIssue {
            verdicts.append(issue)
        } else {
            verdicts.append(Verdict(
                severity: .good, title: L10n.t("vd.wifi.ok"),
                detail: L10n.tf("vd.wifi.ok.detail",
                                wifi.rssi.map { "\($0) dBm" } ?? L10n.t("dash"),
                                wifi.snr,
                                gateway.map { Fmt.pct($0.lossPct) } ?? L10n.t("dash"))))
        }

        // 2. 运营商/外网
        let badInternet = internet.filter { $0.sent > 3 && ($0.lossPct > 5 || ($0.avg ?? 0) > 80) }
        if let gw = gateway, gw.lossPct <= 2, (gw.avg ?? 99) < 30, !badInternet.isEmpty {
            verdicts.append(Verdict(
                severity: .warn, title: L10n.t("vd.isp"),
                detail: badInternet.map {
                    L10n.tf("vd.isp.detail", $0.label, Fmt.pct($0.lossPct),
                            $0.avg.map { Fmt.ms($0) } ?? L10n.t("dash"))
                }.joined(separator: "；"),
                suggestion: L10n.t("vd.isp.tip")))
        } else if badInternet.isEmpty, internet.contains(where: { $0.avg != nil }) {
            let avgAll = internet.compactMap(\.avg)
            if !avgAll.isEmpty {
                verdicts.append(Verdict(
                    severity: .good, title: L10n.t("vd.inet.ok"),
                    detail: L10n.tf("vd.inet.ok.detail", Fmt.ms(avgAll.reduce(0, +) / Double(avgAll.count)))))
            }
        }

        // 3. DNS
        if let ms = dnsSystemMs {
            if ms > 200 {
                verdicts.append(Verdict(
                    severity: .warn, title: L10n.tf("vd.dns.slow", Fmt.ms(ms)),
                    detail: L10n.t("vd.dns.slow.detail"),
                    suggestion: L10n.t("vd.dns.slow.tip")))
            } else {
                verdicts.append(Verdict(
                    severity: .good, title: L10n.tf("vd.dns.ok", Fmt.ms(ms)), detail: ""))
            }
        }

        // 4. 出口
        if publicIP == nil {
            verdicts.append(Verdict(
                severity: .info, title: L10n.t("vd.publicip.pending"),
                detail: L10n.t("vd.publicip.pending.detail")))
        }

        return verdicts
    }

    // MARK: - 单 URL 诊断（诊断页）

    static func urlVerdicts(timing: HttpTimingResult,
                            dnsResults: [DnsResult],
                            wifi: WifiLinkState,
                            pings: [PingTargetState]) -> [Verdict] {
        var verdicts: [Verdict] = []

        if let error = timing.error {
            verdicts.append(Verdict(
                severity: .bad, title: L10n.t("dg.failed"), detail: error,
                suggestion: error.contains("DNS") ? L10n.t("vd.bn.dns.tip") : nil))
            return verdicts
        }

        func phase(_ idx: Int) -> Double {
            // 相位名已本地化，按 colorIndex 定位更稳
            timing.phases.first(where: { $0.colorIndex == idx })?.seconds ?? 0
        }
        let dns = phase(0), tcp = phase(1), tls = phase(2), ttfb = phase(3), download = phase(4)

        // 先看本地链路（交叉验证）
        if let gw = pings.first, gw.sent > 3, gw.lossPct > 5 {
            verdicts.append(Verdict(
                severity: .warn, title: L10n.tf("vd.url.gwloss", Fmt.pct(gw.lossPct)),
                detail: L10n.t("vd.url.gwloss.detail"),
                suggestion: L10n.t("vd.url.gwloss.tip")))
        }

        let total = timing.total

        if total < 1.0 {
            verdicts.append(Verdict(
                severity: .good, title: L10n.tf("vd.url.fast", Fmt.ms(total * 1000)),
                detail: L10n.t("vd.url.fast.detail")))
            return verdicts
        }

        let slowest = max(dns, tcp, tls, ttfb, download)
        if dns > 0.3, dns >= slowest * 0.4 {
            var detail = L10n.tf("vd.bn.dns.detail", Fmt.ms(dns * 1000))
            var suggestion: String?
            if let sys = dnsResults.first(where: { $0.server.hasPrefix(L10n.t("dns.system")) }),
               let sysMs = sys.ms,
               let fast = dnsResults.dropFirst().compactMap(\.ms).min(),
               fast * 2 < sysMs {
                detail += L10n.tf("vd.bn.dns.detail2", Fmt.ms(sysMs), Fmt.ms(fast))
                suggestion = L10n.t("vd.bn.dns.tip")
            }
            verdicts.append(Verdict(severity: dns > 1 ? .bad : .warn,
                                    title: L10n.t("vd.bn.dns"), detail: detail, suggestion: suggestion))
        }
        if tcp > 0.5, tcp >= slowest * 0.4 {
            var detail = L10n.tf("vd.bn.tcp.detail", Fmt.ms(tcp * 1000))
            if let gw = pings.first, (gw.avg ?? 0) < 30 {
                detail += L10n.tf("vd.bn.tcp.detail2", Fmt.ms(gw.avg ?? 0))
            } else if let gw = pings.first, (gw.avg ?? 0) >= 30 {
                detail += L10n.tf("vd.bn.tcp.detail3", Fmt.ms(gw.avg ?? 0))
            }
            verdicts.append(Verdict(severity: tcp > 1.5 ? .bad : .warn,
                                    title: L10n.t("vd.bn.tcp"), detail: detail))
        }
        if tls > 0.8, tls >= slowest * 0.4 {
            verdicts.append(Verdict(severity: tls > 1.5 ? .warn : .info,
                                    title: L10n.tf("vd.bn.tls", Fmt.ms(tls * 1000)),
                                    detail: L10n.t("vd.bn.tls.detail"),
                                    suggestion: tls > 1.5 ? L10n.t("vd.bn.tls.tip") : nil))
        }
        if ttfb > 1.0, ttfb >= slowest * 0.35 {
            verdicts.append(Verdict(
                severity: .warn, title: L10n.tf("vd.bn.ttfb", Fmt.ms(ttfb * 1000)),
                detail: L10n.t("vd.bn.ttfb.detail"),
                suggestion: L10n.t("vd.bn.ttfb.tip")))
        }
        if download > 1.0, timing.bytes > 300_000 {
            let dlMbps = Double(timing.bytes) * 8 / max(download, 0.01) / 1_000_000
            if dlMbps < 5 {
                verdicts.append(Verdict(
                    severity: .warn, title: L10n.tf("vd.bn.dl", Fmt.mbps(dlMbps)),
                    detail: L10n.tf("vd.bn.dl.detail", Fmt.bytes(Double(timing.bytes)), Fmt.ms(download * 1000)),
                    suggestion: L10n.t("vd.bn.dl.tip")))
            }
        }

        if verdicts.isEmpty {
            verdicts.append(Verdict(
                severity: .info, title: L10n.tf("vd.url.total", Fmt.ms(total * 1000)),
                detail: L10n.t("vd.url.total.detail")))
        }
        return verdicts
    }
}
