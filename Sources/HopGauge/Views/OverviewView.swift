import SwiftUI

/// Five-second decision page: conclusion → localization → evidence → action.
struct OverviewView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                diagnosticHero

                LazyVGrid(
                    columns: [GridItem(.flexible(minimum: 420), spacing: 12),
                              GridItem(.flexible(minimum: 420))],
                    spacing: 12
                ) {
                    VStack(spacing: 12) {
                        rootCauseCard
                        networkIdentityCard
                    }
                    VStack(spacing: 12) {
                        latencyEvidenceCard
                        wifiEvidenceCard
                    }
                }
            }
            .padding(.top, 13)
            .padding(.bottom, 4)
        }
    }

    // MARK: - Primary conclusion

    private var diagnosticHero: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: summaryIcon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(summaryColor)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(summaryColor.opacity(0.10)))
                    .overlay(Circle().strokeBorder(summaryColor.opacity(0.20), lineWidth: 0.8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(summaryTitle)
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.textPrimary)
                    Text(summaryDetail)
                        .font(.system(size: 11.5))
                        .foregroundColor(Theme.textSecondary)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 2) {
                    MetricValue(value: "\(model.healthScore)", unit: "/ 100", color: summaryColor, size: 25)
                    Text(QualityForScore.label(model.healthScore))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(summaryColor)
                }
            }

            HStack(spacing: 8) {
                pathMetric(
                    title: "Wi-Fi",
                    value: model.wifi.rssi.map(String.init) ?? "—",
                    unit: model.wifi.rssi == nil ? "" : "dBm",
                    score: model.wifiHealthScore,
                    icon: "wifi"
                )
                pathArrow
                pathMetric(
                    title: L10n.t("ov.gateway"),
                    value: pingValue(model.gatewayPing),
                    unit: model.gatewayPing?.avg == nil ? "" : "ms",
                    score: model.gatewayHealthScore,
                    icon: "router"
                )
                pathArrow
                pathMetric(
                    title: "DNS",
                    value: dnsValue,
                    unit: dnsHasValue ? "ms" : "",
                    score: model.dnsHealthScore,
                    icon: "network"
                )
                pathArrow
                pathMetric(
                    title: "Internet",
                    value: pingValue(model.internetPing),
                    unit: model.internetPing?.avg == nil ? "" : "ms",
                    score: model.internetHealthScore,
                    icon: "globe.asia.australia"
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Theme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(summaryColor.opacity(0.22), lineWidth: 0.9)
        )
        .shadow(color: Color.black.opacity(0.20), radius: 18, x: 0, y: 8)
    }

    private func pathMetric(title: String, value: String, unit: String, score: Int, icon: String) -> some View {
        let color = scoreColor(score)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Theme.textFaint)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                Spacer()
                Circle().fill(color).frame(width: 5, height: 5)
            }
            MetricValue(value: value, unit: unit, color: color, size: 17)
            Text(QualityForScore.label(score))
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.panelRaised.opacity(0.70)))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.hairline, lineWidth: 0.8))
    }

    private var pathArrow: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 8, weight: .semibold))
            .foregroundColor(Theme.textFaint.opacity(0.55))
    }

    // MARK: - Root cause and action

    private var rootCauseCard: some View {
        NeonCard(title: L10n.t("ov.rootcause"), systemImage: "scope") {
            VStack(alignment: .leading, spacing: 10) {
                if let primaryVerdict {
                    HStack(alignment: .top, spacing: 9) {
                        VerdictBadge(severity: primaryVerdict.severity)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(primaryVerdict.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Theme.textPrimary)
                            if !primaryVerdict.detail.isEmpty {
                                Text(primaryVerdict.detail)
                                    .font(.system(size: 10.5))
                                    .foregroundColor(Theme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    if let suggestion = primaryVerdict.suggestion {
                        HStack(alignment: .top, spacing: 7) {
                            Image(systemName: "lightbulb")
                                .font(.system(size: 10))
                                .foregroundColor(Theme.cyan)
                            Text(suggestion)
                                .font(.system(size: 10.5))
                                .foregroundColor(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.cyan.opacity(0.045)))
                    }
                } else {
                    Text(L10n.t("ov.verdicts.wait"))
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textFaint)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
                }

                SectionRule()
                Button {
                    NotificationCenter.default.post(name: .openHopGaugeDiagnosis, object: nil)
                } label: {
                    HStack(spacing: 6) {
                        Text(L10n.t("ov.run.diagnosis"))
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.cyan)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var primaryVerdict: Verdict? {
        model.verdicts.first(where: { verdict in
            switch verdict.severity {
            case .bad, .warn: return true
            case .good, .info: return false
            }
        }) ?? model.verdicts.first
    }

    // MARK: - Evidence

    private var latencyEvidenceCard: some View {
        NeonCard(title: L10n.t("ov.latency"), systemImage: "chart.xyaxis.line") {
            VStack(spacing: 6) {
                ForEach(model.pingTargets.filter { !$0.host.isEmpty }) { target in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(target.label)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundColor(Theme.textPrimary)
                            Text(target.host)
                                .font(Theme.mono(8.5))
                                .foregroundColor(Theme.textFaint)
                        }
                        .frame(width: 88, alignment: .leading)
                        Sparkline(values: target.history, color: pingColor(target), lineWidth: 1.3)
                            .frame(height: 28)
                        VStack(alignment: .trailing, spacing: 2) {
                            MetricValue(value: target.last.map { String(format: "%.1f", $0) } ?? "—",
                                        unit: target.last == nil ? "" : "ms",
                                        color: pingColor(target), size: 11)
                            Text("\(L10n.t("ov.loss")) \(Fmt.pct(target.lossPct))")
                                .font(Theme.mono(8.5))
                                .foregroundColor(Theme.textFaint)
                        }
                        .frame(width: 94, alignment: .trailing)
                    }
                    .padding(.vertical, 4)
                    if target.id != model.pingTargets.filter({ !$0.host.isEmpty }).last?.id { SectionRule() }
                }
            }
        }
    }

    private var networkIdentityCard: some View {
        NeonCard(title: L10n.t("ov.network"), systemImage: "network") {
            VStack(spacing: 1) {
                KeyValueRow(key: L10n.t("ov.lanip"), value: model.overview.ipv4 ?? L10n.t("dash"))
                KeyValueRow(key: L10n.t("ov.gateway"), value: model.overview.gateway ?? L10n.t("dash"))
                KeyValueRow(key: L10n.t("ov.dns.active"),
                            value: model.overview.dnsServers.isEmpty ? L10n.t("dash") : model.overview.dnsServers.joined(separator: " · "))
                KeyValueRow(key: L10n.t("ov.vpn"),
                            value: model.overview.vpnActive.isEmpty ? L10n.t("ov.vpn.off") : model.overview.vpnActive.joined(separator: " · "),
                            valueColor: model.overview.vpnActive.isEmpty ? Theme.textSecondary : Theme.green)
                SectionRule().padding(.vertical, 3)
                KeyValueRow(key: L10n.t("ov.publicip"), value: model.overview.publicIP ?? L10n.t("ov.publicip.wait"))
                if let location = model.overview.publicIPLocation {
                    KeyValueRow(key: L10n.t("ov.location"), value: location)
                }
            }
        }
    }

    private var wifiEvidenceCard: some View {
        NeonCard(title: L10n.t("ov.wifi"), systemImage: "wifi") {
            VStack(spacing: 1) {
                KeyValueRow(key: "SSID", value: model.wifi.ssid ?? L10n.t("ssid.privacy"))
                KeyValueRow(key: L10n.t("tile.channel"), value: channelText)
                KeyValueRow(key: "PHY", value: model.wifi.phyMode ?? L10n.t("dash"))
                KeyValueRow(key: L10n.t("tile.txrate"), value: model.wifi.txRate.map(Fmt.mbps) ?? L10n.t("dash"))
                KeyValueRow(key: L10n.t("tile.snr"), value: model.wifi.rssi == nil ? L10n.t("dash") : "\(model.wifi.snr) dB")
                KeyValueRow(key: L10n.t("tile.security"), value: model.wifi.security ?? L10n.t("dash"))
                KeyValueRow(key: L10n.t("tile.cochannel"), value: "\(model.coChannelNeighbors)",
                            valueColor: model.coChannelNeighbors >= 4 ? Theme.yellow : Theme.textPrimary)
            }
        }
    }

    // MARK: - Summary logic

    private var summarySeverity: VerdictSeverity {
        if !model.wifi.connected { return .bad }
        if model.wifiHealthScore < 60 || model.gatewayHealthScore < 60 { return .bad }
        if model.dnsHealthScore < 80 || model.internetHealthScore < 85 { return .warn }
        if model.healthScore < 80 { return .info }
        return .good
    }

    private var summaryTitle: String {
        if !model.wifi.connected { return L10n.t("ov.hero.offline") }
        if model.wifiHealthScore < 60 { return L10n.t("ov.hero.wifi") }
        if model.gatewayHealthScore < 60 { return L10n.t("ov.hero.gateway") }
        if model.dnsHealthScore < 80 { return L10n.t("ov.hero.dns") }
        if model.internetHealthScore < 85 { return L10n.t("ov.hero.internet") }
        return L10n.t("ov.hero.good")
    }

    private var summaryDetail: String {
        if !model.wifi.connected { return L10n.t("ov.hero.offline.detail") }
        if model.wifiHealthScore < 60 { return L10n.t("ov.hero.wifi.detail") }
        if model.gatewayHealthScore < 60 { return L10n.t("ov.hero.gateway.detail") }
        if model.dnsHealthScore < 80 { return L10n.t("ov.hero.dns.detail") }
        if model.internetHealthScore < 85 { return L10n.t("ov.hero.internet.detail") }
        return L10n.t("ov.hero.good.detail")
    }

    private var summaryColor: Color { Theme.statusColor(summarySeverity) }

    private var summaryIcon: String {
        switch summarySeverity {
        case .good: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .bad: return "xmark.octagon.fill"
        }
    }

    private var dnsHasValue: Bool {
        model.dnsResults.first(where: { $0.server.hasPrefix(L10n.t("dns.system")) })?.ms != nil || model.dnsPing?.avg != nil
    }

    private var dnsValue: String {
        if let ms = model.dnsResults.first(where: { $0.server.hasPrefix(L10n.t("dns.system")) })?.ms {
            return String(format: "%.1f", ms)
        }
        return pingValue(model.dnsPing)
    }

    private func pingValue(_ target: PingTargetState?) -> String {
        target?.avg.map { String(format: "%.1f", $0) } ?? "—"
    }

    private func scoreColor(_ score: Int) -> Color {
        if score >= 85 { return Theme.green }
        if score >= 70 { return Theme.cyan }
        if score >= 50 { return Theme.yellow }
        return Theme.red
    }

    private func pingColor(_ target: PingTargetState) -> Color {
        if target.lossPct > 5 { return Theme.red }
        if let average = target.avg, average > 150 { return Theme.yellow }
        return Theme.green
    }

    private var channelText: String {
        [model.wifi.channel.map { "Ch \($0)" },
         model.wifi.band,
         model.wifi.channelWidthMHz.map { "\($0) MHz" }]
            .compactMap { $0 }
            .joined(separator: " · ")
            .nilIfEmpty ?? L10n.t("dash")
    }

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
