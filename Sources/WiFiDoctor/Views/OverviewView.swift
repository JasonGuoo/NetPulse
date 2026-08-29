import SwiftUI

/// 概况页：网络身份（网关/DNS/代理/VPN/出口IP）+ WiFi 速览 + 丢包延迟
struct OverviewView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(minimum: 380), spacing: 14), GridItem(.flexible(minimum: 380))],
                      spacing: 14) {
                VStack(spacing: 14) {
                    networkIdentityCard
                    healthVerdictCard
                }
                VStack(spacing: 14) {
                    wifiQuickCard
                    latencyCard
                }
            }
            .padding(.top, 16)
        }
    }

    // MARK: 网络概况

    private var networkIdentityCard: some View {
        NeonCard(title: L10n.t("ov.network"), systemImage: "network", live: true) {
            VStack(spacing: 2) {
                KeyValueRow(key: L10n.t("ov.interface"), value: model.wifi.interface ?? L10n.t("dash"))
                KeyValueRow(key: L10n.t("ov.lanip"), value: [model.overview.ipv4, model.overview.mask]
                    .compactMap { $0 }.joined(separator: "  /  ").nilIfEmpty ?? L10n.t("dash"))
                KeyValueRow(key: L10n.t("ov.gateway"), value: model.overview.gateway ?? L10n.t("dash"),
                            valueColor: Theme.cyan)
                Divider().overlay(Color.white.opacity(0.06)).padding(.vertical, 2)
                // DNS 区块：当前生效的是谁、哪来的、快不快
                KeyValueRow(
                    key: L10n.t("ov.dns.active"),
                    value: model.overview.dnsServers.isEmpty ? L10n.t("dash") : model.overview.dnsServers.joined(separator: " · "),
                    valueColor: Theme.purple)
                KeyValueRow(
                    key: L10n.t("ov.dns.source"),
                    value: dnsSourceText,
                    valueColor: Theme.textSecondary)
                if let dnsPing = model.pingTargets.first(where: { $0.label.hasPrefix("DNS") }), !dnsPing.host.isEmpty {
                    KeyValueRow(
                        key: L10n.t("ov.dns.latency"),
                        value: "\(dnsPing.last.map { Fmt.ms($0) } ?? L10n.t("ov.measuring")) · \(L10n.t("ov.loss")) \(Fmt.pct(dnsPing.lossPct)) · \(L10n.t("ov.avg")) \(dnsPing.avg.map { Fmt.ms($0) } ?? L10n.t("dash"))",
                        valueColor: dnsPing.lossPct > 5 ? Theme.red : ((dnsPing.avg ?? 0) > 100 ? Theme.yellow : Theme.green))
                }
                KeyValueRow(
                    key: L10n.t("ov.proxy"),
                    value: model.overview.proxies.isEmpty ? L10n.t("none")
                        : model.overview.proxies.map { "\($0.kind) \($0.server):\($0.port)" }.joined(separator: " · "),
                    valueColor: model.overview.proxies.isEmpty ? Theme.textSecondary : Theme.yellow)
                KeyValueRow(
                    key: L10n.t("ov.vpn"),
                    value: model.overview.vpnActive.isEmpty ? L10n.t("ov.vpn.off")
                        : model.overview.vpnActive.joined(separator: " · "),
                    valueColor: model.overview.vpnActive.isEmpty ? Theme.textSecondary : Theme.green)
                Divider().overlay(Color.white.opacity(0.06)).padding(.vertical, 4)
                KeyValueRow(
                    key: L10n.t("ov.publicip"),
                    value: model.overview.publicIP.map { ip in
                        ip + (model.overview.publicIPLocation.map { "  ·  \($0)" } ?? "")
                    } ?? L10n.t("ov.publicip.wait"),
                    valueColor: Theme.magenta)
                if let colo = model.overview.colo {
                    KeyValueRow(key: L10n.t("ov.edgenode"), value: colo)
                }
                if let updated = model.overview.publicIPUpdated {
                    KeyValueRow(key: L10n.t("ov.updated"),
                                value: Self.timeFormatter.string(from: updated))
                }
            }
        }
    }

    /// DNS 来源说明：手动设置时附路由器原本下发的值
    private var dnsSourceText: String {
        guard !model.overview.dnsServers.isEmpty else { return L10n.t("dash") }
        if model.overview.dnsSource == "manual" {
            let dhcp = model.overview.dhcpDNS.isEmpty ? L10n.t("none") : model.overview.dhcpDNS.joined(separator: " · ")
            return L10n.tf("ov.dns.manual", dhcp)
        }
        if model.overview.dnsSource == "dhcp" { return L10n.t("ov.dns.dhcp") }
        return L10n.t("dash")
    }

    // MARK: WiFi 速览

    private var wifiQuickCard: some View {
        NeonCard(title: L10n.t("ov.wifi"), systemImage: "wifi", live: true) {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    StatTile(title: L10n.t("tile.signal"), value: model.wifi.rssi.map { "\($0) dBm" } ?? L10n.t("dash"),
                             sub: model.wifi.rssi.map { Quality.rssi($0).label } ?? L10n.t("tile.nodata"),
                             color: model.wifi.rssi.map { Quality.rssi($0).color } ?? Theme.textFaint)
                    StatTile(title: L10n.t("tile.snr"), value: model.wifi.rssi != nil ? "\(model.wifi.snr) dB" : L10n.t("dash"),
                             sub: model.wifi.rssi != nil ? Quality.snr(model.wifi.snr).label : L10n.t("tile.nodata"),
                             color: Quality.snr(model.wifi.snr).color)
                    StatTile(title: L10n.t("tile.txrate"), value: model.wifi.txRate.map { Fmt.mbps($0) } ?? L10n.t("dash"),
                             sub: [model.wifi.phyMode, model.wifi.band].compactMap { $0 }.joined(separator: " · "),
                             color: Theme.purple)
                }
                HStack(spacing: 10) {
                    StatTile(title: L10n.t("tile.channel"), value: model.wifi.channel.map(String.init) ?? L10n.t("dash"),
                             sub: [model.wifi.band, model.wifi.channelWidthMHz.map { "\($0)MHz" }]
                                 .compactMap { $0 }.joined(separator: " · "),
                             color: Theme.blue)
                    StatTile(title: L10n.t("tile.security"), value: model.wifi.security ?? L10n.t("dash"),
                             sub: model.wifi.country.map { "\($0)" } ?? nil,
                             color: Theme.green)
                    StatTile(title: L10n.t("tile.cochannel"), value: "\(model.coChannelNeighbors)",
                             sub: L10n.t("tile.cochannel.sub"),
                             color: model.coChannelNeighbors >= 4 ? Theme.yellow : Theme.cyan)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t("ov.rssi.trend"))
                        .font(.system(size: 9, weight: .semibold))
                        .kerning(1)
                        .foregroundColor(Theme.textFaint)
                    Sparkline(values: model.wifi.rssiHistory,
                              color: Quality.rssi(model.wifi.rssi ?? -100).color)
                        .frame(height: 44)
                }
            }
        }
    }

    // MARK: 丢包延迟

    private var latencyCard: some View {
        NeonCard(title: L10n.t("ov.latency"), systemImage: "waveform.path.ecg", live: true) {
            VStack(spacing: 10) {
                ForEach(model.pingTargets.filter { !$0.host.isEmpty }) { target in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(target.label)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundColor(Theme.textPrimary)
                            Text(target.host)
                                .font(Theme.mono(9))
                                .foregroundColor(Theme.textFaint)
                        }
                        .frame(width: 96, alignment: .leading)
                        Sparkline(values: target.history, color: pingColor(target))
                            .frame(height: 26)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(target.last.map { Fmt.ms($0) } ?? L10n.t("dash"))
                                .font(Theme.mono(11, .bold))
                                .foregroundColor(pingColor(target))
                            Text("\(L10n.t("ov.loss")) \(Fmt.pct(target.lossPct)) · \(L10n.t("lk.jitter")) \(Fmt.ms(target.jitter))")
                                .font(Theme.mono(8.5))
                                .foregroundColor(Theme.textFaint)
                        }
                        .frame(width: 132, alignment: .trailing)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.03)))
                }
            }
        }
    }

    // MARK: 健康结论

    private var healthVerdictCard: some View {
        NeonCard(title: L10n.t("ov.verdicts"), systemImage: "sparkles") {
            if model.verdicts.isEmpty {
                Text(L10n.t("ov.verdicts.wait"))
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textFaint)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
            } else {
                VStack(spacing: 8) {
                    ForEach(model.verdicts) { v in
                        HStack(alignment: .top, spacing: 8) {
                            VerdictBadge(severity: v.severity)
                                .padding(.top, 1)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(v.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(Theme.textPrimary)
                                if !v.detail.isEmpty {
                                    Text(v.detail)
                                        .font(.system(size: 10.5))
                                        .foregroundColor(Theme.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                if let s = v.suggestion {
                                    Text(L10n.tf("suggestion", s))
                                        .font(.system(size: 10.5))
                                        .foregroundColor(Theme.cyan.opacity(0.9))
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.03)))
                    }
                }
            }
        }
    }

    private func pingColor(_ t: PingTargetState) -> Color {
        if t.lossPct > 5 { return Theme.red }
        if let last = t.last, last > 100 { return Theme.yellow }
        return Theme.green
    }

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
