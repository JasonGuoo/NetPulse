import SwiftUI

final class MenuBarSnapshot: ObservableObject {
    @Published private(set) var wifiConnected = false
    @Published private(set) var rssi: Int?
    @Published private(set) var linkRateMbps: Double?
    @Published private(set) var gatewayLatencyMs: Double?
    @Published private(set) var dnsLatencyMs: Double?
    @Published private(set) var channelOverlapCount: Int?
    @Published private(set) var healthScore = 20

    func update(from model: AppModel) {
        wifiConnected = model.wifi.connected
        rssi = model.wifi.rssi
        linkRateMbps = model.wifi.txRate
        gatewayLatencyMs = model.gatewayPing?.last
        dnsLatencyMs = model.dnsPing?.last
        channelOverlapCount = model.currentChannelOverlapCount
        healthScore = model.healthScore
    }
}

struct MenuBarPanelView: View {
    @ObservedObject var snapshot: MenuBarSnapshot
    @ObservedObject private var l10n = L10n.shared

    let onOpen: () -> Void
    let onRefresh: () -> Void
    let onQuit: () -> Void

    private var signal: String {
        snapshot.rssi.map { "\($0) dBm" } ?? "—"
    }

    private var signalColor: Color {
        snapshot.rssi.map { Quality.rssi($0).color } ?? Theme.textFaint
    }

    private var linkRate: String {
        snapshot.linkRateMbps.map(Fmt.mbps) ?? "—"
    }

    private var gatewayLatency: String {
        snapshot.gatewayLatencyMs.map(Fmt.ms) ?? "—"
    }

    private var dnsLatency: String {
        snapshot.dnsLatencyMs.map(Fmt.ms) ?? "—"
    }

    private var channelCongestion: String {
        guard let overlapCount = snapshot.channelOverlapCount else { return "—" }
        let level = ChannelPlan.congestionLevel(for: overlapCount)
        return L10n.tf(
            "menu.channel.overlap.short",
            L10n.t(level.localizationKey),
            overlapCount
        )
    }

    private var channelCongestionColor: Color {
        guard let overlapCount = snapshot.channelOverlapCount else { return Theme.textFaint }
        if overlapCount == 0 { return Theme.green }
        if overlapCount <= 2 { return Theme.cyan }
        if overlapCount <= 4 { return Theme.yellow }
        return Theme.red
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            MenuBarDivider()

            VStack(spacing: 2) {
                MenuBarMetricRow(
                    symbol: "waveform.path.ecg",
                    title: L10n.t("tile.signal"),
                    value: signal,
                    color: signalColor
                )
                MenuBarMetricRow(
                    symbol: "wifi",
                    title: L10n.t("tile.txrate"),
                    value: linkRate,
                    color: Theme.blue
                )
                MenuBarMetricRow(
                    symbol: "wifi.exclamationmark",
                    title: L10n.t("lk.congestion"),
                    value: channelCongestion,
                    color: channelCongestionColor
                )
                MenuBarMetricRow(
                    symbol: "clock",
                    title: L10n.t("menu.gateway.latency"),
                    value: gatewayLatency,
                    color: latencyColor(snapshot.gatewayLatencyMs, warning: 30, bad: 80)
                )
                MenuBarMetricRow(
                    symbol: "network",
                    title: L10n.t("menu.dns.latency"),
                    value: dnsLatency,
                    color: latencyColor(snapshot.dnsLatencyMs, warning: 80, bad: 200)
                )
                MenuBarMetricRow(
                    symbol: "checkmark.shield",
                    title: L10n.t("menu.network.status"),
                    value: QualityForScore.label(snapshot.healthScore),
                    color: scoreColor(snapshot.healthScore)
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            MenuBarDivider()

            VStack(spacing: 2) {
                MenuBarActionRow(symbol: "macwindow", title: L10n.t("menu.open"), action: onOpen)
                MenuBarActionRow(symbol: "arrow.triangle.2.circlepath", title: L10n.t("refresh"), action: onRefresh)
                MenuBarActionRow(symbol: "rectangle.portrait.and.arrow.right", title: L10n.t("menu.quit"), action: onQuit)
            }
            .padding(8)
        }
        .frame(width: 320)
        .background(Theme.bgGradient)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(nsImage: AppDelegate.renderIcon(size: 28))
                .resizable()
                .interpolation(.high)
                .frame(width: 26, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("HopGauge \(L10n.t("menu.running"))")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.textPrimary)
                Text(L10n.t("menu.refresh.interval"))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(Theme.textFaint)
            }

            Spacer()

            Image(nsImage: AppDelegate.renderStatusItemIcon(
                score: snapshot.healthScore,
                connected: snapshot.wifiConnected,
                phase: 0.48
            ))
            .interpolation(.high)
            .frame(width: 22, height: 18)
        }
        .padding(.horizontal, 14)
        .frame(height: 58)
    }

    private func latencyColor(_ milliseconds: Double?, warning: Double, bad: Double) -> Color {
        guard let milliseconds else { return Theme.textFaint }
        if milliseconds >= bad { return Theme.red }
        if milliseconds >= warning { return Theme.yellow }
        return Theme.green
    }

    private func scoreColor(_ score: Int) -> Color {
        if score >= 85 { return Theme.green }
        if score >= 70 { return Theme.cyan }
        if score >= 50 { return Theme.yellow }
        return Theme.red
    }
}

private struct MenuBarMetricRow: View {
    let symbol: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(color)
                .frame(width: 22)

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer(minLength: 8)

            Text(value)
                .font(Theme.mono(12, .semibold))
                .monospacedDigit()
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(height: 34)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.025))
        )
    }
}

private struct MenuBarActionRow: View {
    let symbol: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(0.025))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct MenuBarDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: 1)
    }
}
