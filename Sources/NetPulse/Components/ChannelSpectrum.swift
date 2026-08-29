import SwiftUI

/// 信道频谱图：每个 WiFi 按真实信道宽度画成横条，当前网络高亮，重叠标红
struct ChannelSpectrumView: View {
    let analysis: ChannelPlan.BandAnalysis

    private var axis: [Int] { ChannelPlan.axisChannels(band: analysis.band) }
    private var minCh: Double { Double(axis.first ?? 1) }
    private var maxCh: Double { Double(axis.last ?? 14) }

    private var lanes: [[ChannelPlan.APBar]] { ChannelPlan.lanes(for: analysis.bars) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let laneHeight: CGFloat = 16
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(lanes.enumerated()), id: \.offset) { _, lane in
                        ZStack(alignment: .topLeading) {
                            ForEach(lane) { bar in
                                barView(bar, width: geo.size.width)
                            }
                        }
                        .frame(height: laneHeight - 3)
                    }
                    Spacer(minLength: 0)
                }
                .animation(.spring(response: 0.5, dampingFraction: 0.9), value: analysis.bars.map(\.channel))
            }
            .frame(height: max(CGFloat(lanes.count) * 16 + 18, 52))

            // 信道号刻度
            HStack(spacing: 0) {
                ForEach(axis, id: \.self) { ch in
                    Text(label(ch))
                        .font(Theme.mono(7.5))
                        .foregroundColor(Theme.textFaint)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func label(_ ch: Int) -> String {
        analysis.band == "2.4GHz" ? "\(ch)" : (ch % 8 == 4 || ch == axis.first ? "\(ch)" : "")
    }

    @ViewBuilder
    private func barView(_ bar: ChannelPlan.APBar, width: CGFloat) -> some View {
        let span = maxCh - minCh + 4
        let barWidth = max(CGFloat(bar.spanChannels / span) * width, 14)
        let offset = CGFloat((bar.left - minCh + 2) / span) * width

        // 信号越强越不透明
        let strength = bar.rssi.map { Double(max(0, min(100, $0 + 100))) / 100 } ?? 0.5

        Group {
            if bar.isCurrent {
                Text("\(bar.ssid) · \(L10n.t("lk.legend.current"))")
                    .font(Theme.mono(9, .bold))
                    .foregroundColor(.black.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .padding(.horizontal, 6)
                    .frame(width: barWidth, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.accentGradient)
                            .shadow(color: Theme.cyan.opacity(0.55), radius: 4)
                    )
            } else if bar.isOwnRouter {
                HStack(spacing: 3) {
                    Image(systemName: "house.fill")
                        .font(.system(size: 7))
                    Text("\(bar.ssid) · \(L10n.t("lk.own.router"))")
                        .font(Theme.mono(8))
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                }
                .foregroundColor(Theme.purple)
                .padding(.horizontal, 5)
                .frame(width: barWidth, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.purple.opacity(0.13))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Theme.purple.opacity(0.55),
                                      style: StrokeStyle(lineWidth: 0.9, dash: [3, 2]))
                )
            } else {
                HStack(spacing: 3) {
                    if bar.overlapsCurrent {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 7))
                            .foregroundColor(Theme.red)
                    }
                    Text(bar.ssid)
                        .font(Theme.mono(8))
                        .foregroundColor(bar.overlapsCurrent ? Theme.red : Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                }
                .padding(.horizontal, 5)
                .frame(width: barWidth, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(bar.overlapsCurrent
                              ? Theme.red.opacity(0.16)
                              : Color.white.opacity(0.06 + 0.10 * strength))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(bar.overlapsCurrent ? Theme.red.opacity(0.55) : Color.white.opacity(0.08),
                                      lineWidth: 0.8)
                )
            }
        }
        .frame(width: barWidth, alignment: .leading)
        .offset(x: max(0, offset))
    }
}
