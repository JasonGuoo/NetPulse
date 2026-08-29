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
                    mbps: model.lastSpeed.downloadMbps,
                    reference: model.wifi.txRate ?? 0,
                    untestedText: L10n.t("sp.notested"))
                    .frame(height: 190)

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
                    .foregroundStyle(AnyShapeStyle(
                        LinearGradient(colors: [Theme.cyan, Theme.purple], startPoint: .leading, endPoint: .trailing)))
                    .padding(.horizontal, 26)
                    .padding(.vertical, 9)
                    .background(
                        Capsule().fill(.ultraThinMaterial.opacity(0.5))
                            .overlay(Capsule().strokeBorder(Theme.accentGradient, lineWidth: 1.2))
                    )
                    .shadow(color: Theme.cyan.opacity(0.35), radius: 10)
                }
                .buttonStyle(.plain)
                .disabled(model.speedTesting)

                if let at = model.lastSpeed.measuredAt {
                    Text(L10n.tf("sp.last.at",
                                 OverviewView.timeFormatter.string(from: at),
                                 Fmt.bytes(Double(model.lastSpeed.bytes)),
                                 model.lastSpeed.seconds))
                        .font(Theme.mono(9.5))
                        .foregroundColor(Theme.textFaint)
                } else {
                    Text(L10n.t("sp.note"))
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textFaint)
                }
            }
            .frame(maxWidth: .infinity)
        }
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
                           value: model.lastSpeed.downloadMbps,
                           maxV: maxValue,
                           color: Theme.cyan,
                           suffix: model.lastSpeed.downloadMbps > 0 ? Fmt.mbps(model.lastSpeed.downloadMbps) : L10n.t("sp.notested"))
                compareRow(label: L10n.t("sp.cmp.now"),
                           value: (model.totalRateIn + model.totalRateOut) * 8 / 1_000_000,
                           maxV: maxValue,
                           color: Theme.green,
                           suffix: Fmt.mbps((model.totalRateIn + model.totalRateOut) * 8 / 1_000_000))
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
            max(model.lastSpeed.downloadMbps,
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
                        .shadow(color: color.opacity(0.5), radius: 4)
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
        model.speedTesting = true
        await coordinator.runSpeedTest()
        model.speedTesting = false
    }
}
