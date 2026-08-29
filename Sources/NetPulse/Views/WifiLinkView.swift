import SwiftUI

/// 链路页：射频细节 + 信道占用（含你的信道徽章/图例/拥挤标记）+ ping 走势
struct WifiLinkView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var l10n = L10n.shared
    @State private var showChannelDetails = false

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(minimum: 400), spacing: 14),
                                GridItem(.flexible(minimum: 400))],
                      spacing: 14) {
                VStack(spacing: 14) {
                    radioCard
                    pingCard
                }
                VStack(spacing: 14) {
                    channelCard
                    historyCard
                }
            }
            .padding(.top, 16)
        }
    }

    // MARK: 射频状态

    private var radioCard: some View {
        NeonCard(title: L10n.t("lk.radio"), systemImage: "waveform", live: true) {
            VStack(spacing: 2) {
                KeyValueRow(key: L10n.t("lk.ssid"), value: model.wifi.ssid ?? L10n.t("ssid.privacy"),
                            valueColor: model.wifi.ssid != nil ? Theme.textPrimary : Theme.textFaint)
                KeyValueRow(key: L10n.t("ov.interface"), value: model.wifi.interface ?? L10n.t("dash"))
                KeyValueRow(key: L10n.t("tile.channel"), value: channelText)
                KeyValueRow(key: "PHY", value: model.wifi.phyMode ?? L10n.t("dash"))
                KeyValueRow(key: L10n.t("lk.mcs"), value: model.wifi.mcs.map(String.init) ?? L10n.t("dash"))
                KeyValueRow(key: L10n.t("tile.security"), value: model.wifi.security ?? L10n.t("dash"))
                KeyValueRow(key: L10n.t("lk.country"), value: model.wifi.country ?? L10n.t("dash"))
                Divider().overlay(Color.white.opacity(0.06)).padding(.vertical, 4)
                HStack(spacing: 10) {
                    StatTile(title: L10n.t("lk.rssi"), value: model.wifi.rssi.map { "\($0) dBm" } ?? L10n.t("dash"),
                             sub: model.wifi.rssi.map { Quality.rssi($0).label } ?? nil,
                             color: model.wifi.rssi.map { Quality.rssi($0).color } ?? Theme.textFaint)
                    StatTile(title: L10n.t("lk.noise"), value: model.wifi.noise.map { "\($0) dBm" } ?? L10n.t("dash"),
                             color: Theme.blue)
                    StatTile(title: L10n.t("tile.snr"), value: model.wifi.rssi != nil ? "\(model.wifi.snr) dB" : L10n.t("dash"),
                             sub: model.wifi.rssi != nil ? Quality.snr(model.wifi.snr).label : nil,
                             color: Quality.snr(model.wifi.snr).color)
                }
                HStack(spacing: 10) {
                    StatTile(title: L10n.t("tile.txrate"), value: model.wifi.txRate.map { Fmt.mbps($0) } ?? L10n.t("dash"),
                             color: Theme.purple)
                    StatTile(title: L10n.t("lk.width"), value: model.wifi.channelWidthMHz.map { "\($0) MHz" } ?? L10n.t("dash"),
                             color: Theme.cyan)
                    StatTile(title: L10n.t("lk.coap"), value: "\(model.coChannelNeighbors)",
                             sub: L10n.t("lk.coap.sub"),
                             color: model.coChannelNeighbors >= 4 ? Theme.yellow : Theme.green)
                }
            }
        }
    }

    private var channelText: String {
        var parts: [String] = []
        if let ch = model.wifi.channel { parts.append("Ch \(ch)") }
        if let band = model.wifi.band { parts.append(band) }
        if let w = model.wifi.channelWidthMHz { parts.append("\(w)MHz") }
        return parts.isEmpty ? L10n.t("dash") : parts.joined(separator: " · ")
    }

    // MARK: 信道占用（可读版）

    private var currentTuple: (channel: Int, width: Int, ssid: String)? {
        guard let ch = model.wifi.channel else { return nil }
        return (ch, model.wifi.channelWidthMHz ?? 20, model.wifi.ssid ?? L10n.t("lk.legend.current"))
    }

    private var band24: ChannelPlan.BandAnalysis {
        ChannelPlan.analyze(band: "2.4GHz", neighbors: model.neighbors,
                            current: model.wifi.band == "2.4GHz" ? currentTuple : nil)
    }

    private var band5: ChannelPlan.BandAnalysis {
        ChannelPlan.analyze(band: "5GHz", neighbors: model.neighbors,
                            current: model.wifi.band == "5GHz" ? currentTuple : nil)
    }

    private var currentBandAnalysis: ChannelPlan.BandAnalysis {
        model.wifi.band == "2.4GHz" ? band24 : band5
    }

    private var channelCard: some View {
        NeonCard(title: L10n.t("lk.channel.title"), systemImage: "wifi.exclamationmark") {
            VStack(alignment: .leading, spacing: 14) {
                channelDecisionSummary
                channelConclusionRow
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { showChannelDetails.toggle() }
                } label: {
                    HStack(spacing: 5) {
                        Text(L10n.t(showChannelDetails ? "lk.hide.details" : "lk.view.details"))
                        Image(systemName: showChannelDetails ? "chevron.up" : "chevron.down")
                    }
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(Theme.cyan)
                }
                .buttonStyle(.plain)

                if showChannelDetails {
                    SectionRule()
                    channelHeroRow
                    channelSection(analysis: band5)
                    SectionRule()
                    channelSection(analysis: band24)
                    routerHowToRow
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private var channelDecisionSummary: some View {
        let analysis = currentBandAnalysis
        let overlap = analysis.overlapCount
        let color: Color = overlap == 0 ? Theme.green : (overlap <= 2 ? Theme.cyan : (overlap <= 4 ? Theme.yellow : Theme.red))
        let congestion = overlap == 0 ? L10n.t("lk.congestion.low")
            : (overlap <= 2 ? L10n.t("lk.congestion.low")
               : (overlap <= 4 ? L10n.t("lk.congestion.medium") : L10n.t("lk.congestion.high")))
        return VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(channelText)
                        .font(Theme.rounded(21, .semibold))
                        .monospacedDigit()
                        .foregroundColor(Theme.textPrimary)
                    Text(L10n.tf("lk.overlap.summary", overlap))
                        .font(.system(size: 10.5))
                        .foregroundColor(Theme.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(L10n.t("lk.congestion"))
                        .font(.system(size: 9.5))
                        .foregroundColor(Theme.textFaint)
                    Text(congestion)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(color)
                }
            }
            HStack(spacing: 7) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Theme.textFaint)
                Text(analysis.recommendation)
                    .font(.system(size: 10.5))
                    .foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.045)))
        }
    }

    // 你的信道徽章行：一眼看清"我"在哪、哪里最挤
    private var heroChannelText: String {
        if currentBandAnalysis.current != nil, let ch = model.wifi.channel {
            return "Ch \(ch)"
        }
        return L10n.t("dash")
    }

    private var heroWidthText: String {
        var s = L10n.t("lk.your.channel")
        if let w = model.wifi.channelWidthMHz { s += " · \(w)MHz" }
        return s
    }

    private var scanAtText: String? {
        model.lastScanAt.map { L10n.tf("lk.scan.at", OverviewView.timeFormatter.string(from: $0)) }
    }

    private var channelHeroRow: some View {
        HStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(heroChannelText)
                    .font(Theme.rounded(26, .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.accentGradient)
                Text(heroWidthText)
                    .font(Theme.mono(9))
                    .foregroundColor(Theme.textFaint)
            }
            .frame(width: 108)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.panelRaised.opacity(0.72))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Theme.accentGradient.opacity(0.5), lineWidth: 1))
            )

            VStack(alignment: .leading, spacing: 4) {
                busiestRow
                HStack(spacing: 10) {
                    legendDot(Theme.accentGradient.opacity(0.9), label: L10n.t("lk.legend.current"))
                    legendDot(Theme.red, label: L10n.t("lk.legend.overlap"))
                    legendDot(Color.white.opacity(0.18), label: L10n.t("lk.legend.other"))
                }
                Text(L10n.t("lk.legend.hint"))
                    .font(.system(size: 8.5))
                    .foregroundColor(Theme.textFaint.opacity(0.8))
            }
            Spacer()
            if let scanText = scanAtText {
                Text(scanText)
                    .font(Theme.mono(8.5))
                    .foregroundColor(Theme.textFaint)
            }
        }
    }

    @ViewBuilder
    private var busiestRow: some View {
        let analysis = currentBandAnalysis.band == model.wifi.band ? currentBandAnalysis : band5
        if let busy = ChannelPlan.busiestChannel(analysis.bars) {
            HStack(spacing: 5) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 9))
                    .foregroundColor(Theme.orange)
                Text("\(L10n.t("lk.crowded.channel")): Ch \(busy.channel)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.orange)
                Text(L10n.tf("lk.networks", busy.count))
                    .font(Theme.mono(9.5))
                    .foregroundColor(Theme.textFaint)
            }
        }
    }

    private var channelConclusionRow: some View {
        let current = currentBandAnalysis
        let impact = current.overlapCount <= 2 ? L10n.t("lk.impact.low")
            : (current.overlapCount <= 4 ? L10n.t("lk.impact.medium") : L10n.t("lk.impact.high"))
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: current.conflict ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                .foregroundColor(current.conflict ? Theme.yellow : Theme.green)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(current.conflict ? L10n.t("lk.possible.interference") : L10n.t("lk.conflict.no"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(current.conflict ? Theme.yellow : Theme.green)
                Text(current.conflict
                     ? L10n.tf("lk.interference.detail", current.overlapCount, impact)
                     : L10n.t("lk.keep.channel"))
                    .font(.system(size: 10.5))
                    .foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(current.conflict ? Theme.yellow.opacity(0.06) : Theme.green.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(current.conflict ? Theme.yellow.opacity(0.25) : Theme.green.opacity(0.2), lineWidth: 0.8)
        )
    }

    private var routerHowToRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "wrench.and.screwdriver")
                .foregroundStyle(Theme.accentGradient)
                .padding(.top, 1)
            Text(ChannelPlan.routerHowTo(gateway: model.overview.gateway))
                .font(.system(size: 10))
                .foregroundColor(Theme.textFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func legendDot<S: ShapeStyle>(_ style: S, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(style)
                .frame(width: 12, height: 7)
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(Theme.textSecondary)
        }
    }

    private func channelSection(analysis: ChannelPlan.BandAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(analysis.band)
                    .font(.system(size: 10, weight: .bold))
                    .kerning(1)
                    .foregroundColor(analysis.band == "2.4GHz" ? Theme.orange.opacity(0.9) : Theme.cyan.opacity(0.9))
                Text(L10n.tf("lk.networks", analysis.bars.count) +
                     (analysis.pairOverlapCount > 0 ? " · " + L10n.tf("lk.overlaps.n", analysis.pairOverlapCount) : ""))
                    .font(Theme.mono(9))
                    .foregroundColor(analysis.pairOverlapCount > 3 ? Theme.yellow : Theme.textFaint)
                Spacer()
                if analysis.current == nil {
                    Text(L10n.t("lk.not.on.band"))
                        .font(Theme.mono(8.5))
                        .foregroundColor(Theme.textFaint.opacity(0.7))
                }
            }
            if analysis.bars.isEmpty {
                Text(L10n.t("lk.band.clean"))
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textFaint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.02)))
            } else {
                ChannelSpectrumView(analysis: analysis)
            }
        }
    }

    // MARK: 历史走势

    private var historyCard: some View {
        NeonCard(title: L10n.t("lk.signal.history"), systemImage: "chart.xyaxis.line") {
            VStack(spacing: 12) {
                historyRow(title: "RSSI (dBm)", values: model.wifi.rssiHistory, color: Theme.cyan)
                historyRow(title: "SNR (dB)", values: model.wifi.snrHistory, color: Theme.green)
                historyRow(title: "Mbps", values: model.wifi.txRateHistory, color: Theme.purple)
            }
        }
    }

    private func historyRow(title: String, values: [Double], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 9.5, weight: .semibold))
                    .kerning(1)
                    .foregroundColor(Theme.textFaint)
                Spacer()
                if let last = values.last {
                    Text(String(format: last.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f", last))
                        .font(Theme.mono(10, .bold))
                        .foregroundColor(color)
                }
            }
            Sparkline(values: values, color: color)
                .frame(height: 38)
        }
    }

    // MARK: Ping 走势

    private var pingCard: some View {
        NeonCard(title: L10n.t("lk.ping.trend"), systemImage: "dot.radiowaves.left.and.right", live: true) {
            VStack(spacing: 10) {
                ForEach(model.pingTargets.filter { !$0.host.isEmpty }) { t in
                    VStack(spacing: 4) {
                        HStack {
                            Text("\(t.label) (\(t.host))")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundColor(Theme.textSecondary)
                            Spacer()
                            Text("\(L10n.t("ov.avg")) \(t.avg.map { Fmt.ms($0) } ?? L10n.t("dash")) · \(L10n.t("lk.jitter")) \(Fmt.ms(t.jitter)) · \(L10n.t("ov.loss")) \(Fmt.pct(t.lossPct))")
                                .font(Theme.mono(9))
                                .foregroundColor(t.lossPct > 5 ? Theme.red : Theme.textFaint)
                        }
                        Sparkline(values: t.history, color: t.lossPct > 5 ? Theme.red : (t.label.hasPrefix(L10n.t("pk.gateway")) ? Theme.cyan : Theme.green))
                            .frame(height: 40)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.03)))
                }
            }
        }
    }
}
