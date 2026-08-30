import SwiftUI

/// 速率页：测速表盘 + 实时聚合流量 + 对比
struct ThroughputView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(minimum: 360), spacing: 14),
                                GridItem(.flexible(minimum: 360))],
                      spacing: 14) {
                VStack(spacing: 14) {
                    gaugeCard
                    liveTrafficCard
                }
                VStack(spacing: 14) {
                    compareCard
                    methodCard
                }
            }
            .padding(.top, 16)
        }
    }

    // MARK: 测速表盘

    private var gaugeCard: some View {
        NeonCard(title: L10n.t("sp.gauge"), systemImage: "speedometer") {
            VStack(spacing: 14) {
                SpeedGauge(
                    mbps: displayedMbps,
                    averageMbps: displayedAverageMbps,
                    peakMbps: model.speedProgress.peakMbps,
                    reference: model.wifi.txRate ?? 0,
                    testing: model.speedTesting,
                    stageText: speedStageText,
                    untestedText: L10n.t("sp.ready"))
                    .frame(height: 212)

                if model.speedTesting || !model.speedProgress.samples.isEmpty {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            resultMetric(L10n.t("sp.live.current"),
                                         String(format: "%.1f", displayedMbps), "Mbps", Theme.cyan)
                            resultMetric(L10n.t("sp.live.average"),
                                         String(format: "%.1f", displayedAverageMbps), "Mbps", Theme.green)
                            resultMetric(L10n.t("sp.live.peak"),
                                         String(format: "%.1f", model.speedProgress.peakMbps), "Mbps", Theme.purple)
                        }

                        HStack {
                            Text(speedStageText)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundColor(model.speedTesting ? Theme.cyan : Theme.green)
                            Spacer()
                            Text(L10n.tf(
                                "sp.progress",
                                Int((model.speedProgress.fraction * 100).rounded()),
                                Fmt.bytes(Double(model.speedProgress.receivedBytes))
                            ))
                            .font(Theme.mono(9.5, .medium))
                            .foregroundColor(Theme.textFaint)
                        }

                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.055))
                                Capsule()
                                    .fill(Theme.accentGradient)
                                    .frame(width: geometry.size.width * CGFloat(min(max(model.speedProgress.fraction, 0), 1)))
                            }
                        }
                        .frame(height: 5)
                        .animation(.easeOut(duration: 0.18), value: model.speedProgress.fraction)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.t("sp.live.chart"))
                                .font(.system(size: 9, weight: .semibold))
                                .kerning(0.8)
                                .foregroundColor(Theme.textFaint)
                            LiveSpeedChart(values: model.speedProgress.samples)
                                .frame(height: 66)
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Theme.panelMuted.opacity(0.62)))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.hairline, lineWidth: 0.8))
                }

                Button {
                    Task { await runSpeedTest() }
                } label: {
                    HStack(spacing: 8) {
                        if model.speedTesting {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.black)
                            Text(L10n.t("sp.testing"))
                        } else {
                            Image(systemName: "bolt.fill")
                            Text(model.lastSpeed.measuredAt == nil ? L10n.t("sp.start") : L10n.t("sp.retest"))
                        }
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(hex: 0x07101C))
                    .padding(.horizontal, 26)
                    .padding(.vertical, 9)
                    .background(
                        Capsule().fill(Theme.cyan)
                    )
                }
                .buttonStyle(.plain)
                .disabled(model.speedTesting)

                if let at = model.lastSpeed.measuredAt, !model.speedTesting {
                    HStack(spacing: 8) {
                        resultMetric(L10n.t("sp.result.download"),
                                     String(format: "%.1f", model.lastSpeed.downloadMbps), "Mbps", Theme.cyan)
                        resultMetric(L10n.t("sp.live.peak"),
                                     String(format: "%.1f", model.speedProgress.peakMbps), "Mbps", Theme.purple)
                        resultMetric(L10n.t("sp.result.latency"),
                                     model.internetPing?.avg.map { String(format: "%.1f", $0) } ?? "—",
                                     model.internetPing?.avg == nil ? "" : "ms",
                                     model.internetHealthScore >= 70 ? Theme.green : Theme.yellow)
                    }
                    Text(L10n.tf("sp.last.at",
                                 OverviewView.timeFormatter.string(from: at),
                                 Fmt.bytes(Double(model.lastSpeed.bytes)),
                                 model.lastSpeed.seconds))
                        .font(Theme.mono(9.5))
                        .foregroundColor(Theme.textFaint)
                } else if !model.speedTesting {
                    Text(L10n.t("sp.note"))
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textFaint)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var displayedMbps: Double {
        model.speedTesting ? model.speedProgress.instantaneousMbps : model.lastSpeed.downloadMbps
    }

    private var displayedAverageMbps: Double {
        if model.speedTesting { return model.speedProgress.averageMbps }
        return model.lastSpeed.downloadMbps
    }

    private var speedStageText: String {
        switch model.speedProgress.phase {
        case .idle: return L10n.t("sp.stage.ready")
        case .warmingUp: return L10n.t("sp.stage.warmup")
        case .preparing: return L10n.t("sp.stage.preparing")
        case .measuring: return L10n.t("sp.stage.measuring")
        case .retrying: return L10n.t("sp.stage.retrying")
        case .completed: return L10n.t("sp.stage.complete")
        case .failed: return L10n.t("sp.stage.failed")
        }
    }

    private func resultMetric(_ title: String, _ value: String, _ unit: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(Theme.textFaint)
            MetricValue(value: value, unit: unit, color: color, size: 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.panelRaised.opacity(0.72)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairline, lineWidth: 0.8))
    }

    // MARK: 实时聚合流量

    private var liveTrafficCard: some View {
        NeonCard(title: L10n.t("sp.live.traffic"), systemImage: "arrow.left.arrow.right", live: true) {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    StatTile(title: L10n.t("sp.down.now"), value: Fmt.rate(model.totalRateIn), color: Theme.cyan)
                    StatTile(title: L10n.t("sp.up.now"), value: Fmt.rate(model.totalRateOut), color: Theme.purple)
                }
                trendRow(title: L10n.t("sp.down.trend"), values: model.rateHistory.map(\.in), color: Theme.cyan)
                trendRow(title: L10n.t("sp.up.trend"), values: model.rateHistory.map(\.out), color: Theme.purple)
            }
        }
    }

    private func trendRow(title: String, values: [Double], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .semibold)).kerning(1).foregroundColor(Theme.textFaint)
            Sparkline(values: values, color: color)
                .frame(height: 52)
        }
    }

    // MARK: 对比

    private var compareCard: some View {
        NeonCard(title: L10n.t("sp.compare"), systemImage: "square.stack.3d.up") {
            VStack(spacing: 10) {
                compareRow(label: L10n.t("sp.cmp.phy"),
                           value: model.wifi.txRate ?? 0,
                           maxV: maxValue,
                           color: Theme.purple,
                           suffix: model.wifi.txRate.map { Fmt.mbps($0) } ?? L10n.t("dash"))
                compareRow(label: L10n.t("sp.cmp.real"),
                           value: displayedAverageMbps,
                           maxV: maxValue,
                           color: Theme.cyan,
                           suffix: displayedAverageMbps > 0 ? Fmt.mbps(displayedAverageMbps) : L10n.t("sp.notested"))
                compareRow(label: L10n.t("sp.cmp.now"),
                           value: (model.totalRateIn + model.totalRateOut) * 8 / 1_000_000,
                           maxV: maxValue,
                           color: Theme.green,
                           suffix: Fmt.mbps((model.totalRateIn + model.totalRateOut) * 8 / 1_000_000))
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 9))
                        .foregroundColor(Theme.textFaint)
                    Text(L10n.t("sp.phy.note"))
                        .font(.system(size: 9.5))
                        .foregroundColor(Theme.textFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if model.lastSpeed.downloadMbps > 0, let phy = model.wifi.txRate, phy > 0 {
                    let ratio = model.lastSpeed.downloadMbps / phy
                    Text(ratio > 0.4
                         ? L10n.tf("sp.ratio.good", ratio * 100)
                         : L10n.tf("sp.ratio.bad", ratio * 100))
                        .font(.system(size: 10.5))
                        .foregroundColor(ratio > 0.4 ? Theme.green : Theme.yellow)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                }
            }
        }
    }

    private var maxValue: Double {
        max(model.wifi.txRate ?? 0,
            max(displayedAverageMbps,
                (model.totalRateIn + model.totalRateOut) * 8 / 1_000_000) * 1.15, 10)
    }

    private func compareRow(label: String, value: Double, maxV: Double, color: Color, suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                Spacer()
                Text(suffix)
                    .font(Theme.mono(11, .bold))
                    .foregroundColor(value > 0 ? color : Theme.textFaint)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.06))
                    Capsule()
                        .fill(LinearGradient(colors: [color.opacity(0.7), color],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(4, CGFloat(value / maxV) * geo.size.width))
                }
            }
            .frame(height: 8)
        }
    }

    // MARK: 方法说明

    private var methodCard: some View {
        NeonCard(title: L10n.t("sp.method"), systemImage: "info.circle") {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.t("sp.m1"))
                Text(L10n.t("sp.m2"))
                Text(L10n.t("sp.m3"))
                Text(L10n.t("sp.m4"))
            }
            .font(.system(size: 10.5))
            .foregroundColor(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func runSpeedTest() async {
        guard let coordinator = model.coordinator else { return }
        await coordinator.runSpeedTest()
    }
}
