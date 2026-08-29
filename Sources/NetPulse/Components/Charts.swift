import SwiftUI

// MARK: - 健康度环

struct HealthRing: View {
    let score: Int
    var size: CGFloat = 64
    var lineWidth: CGFloat = 6
    @State private var animated = false

    private var scoreColor: Color {
        switch score {
        case let s where s >= 85: return Theme.green
        case 70...84: return Theme.cyan
        case 50...69: return Theme.yellow
        default: return Theme.red
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 1)
                .stroke(Theme.purple.opacity(0.16),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            Circle()
                .trim(from: 0, to: animated ? Double(score) / 100 : 0)
                .stroke(Theme.accentAngular,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: scoreColor.opacity(0.28), radius: 3)
            VStack(spacing: 0) {
                Text("\(score)")
                    .font(Theme.rounded(size / 3.1, .bold))
                    .monospacedDigit()
                    .foregroundColor(Theme.textPrimary)
                if size >= 52 {
                    Text(L10n.t("health"))
                        .font(.system(size: size / 7.2))
                        .foregroundColor(Theme.textFaint)
                }
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.easeOut(duration: 0.9)) { animated = true }
        }
        .onChange(of: score) {
            // 分数变化时轻微重放动画
            animated = false
            withAnimation(.easeOut(duration: 0.6)) { animated = true }
        }
    }
}

// MARK: - 迷你波形图

struct Sparkline: View {
    var values: [Double]
    var color: Color = Theme.cyan
    var lineWidth: CGFloat = 1.6
    var inverted: Bool = false   // RSSI 越大越好但为负，直接按值绘制即可

    var body: some View {
        Canvas { ctx, size in
            guard values.count > 1 else {
                var p = Path()
                p.move(to: CGPoint(x: 0, y: size.height * 0.5))
                p.addLine(to: CGPoint(x: size.width, y: size.height * 0.5))
                ctx.stroke(p, with: .color(color.opacity(0.22)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                return
            }
            let minV = values.min() ?? 0
            let maxV = values.max() ?? 1
            let span = max(maxV - minV, 0.0001)
            let inset: CGFloat = 3

            func point(_ i: Int) -> CGPoint {
                CGPoint(
                    x: CGFloat(i) / CGFloat(values.count - 1) * size.width,
                    y: inset + (1 - CGFloat((values[i] - minV) / span)) * (size.height - inset * 2)
                )
            }

            var path = Path()
            path.move(to: point(0))
            for i in 1..<values.count { path.addLine(to: point(i)) }

            var area = path
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.addLine(to: CGPoint(x: 0, y: size.height))
            area.closeSubpath()
            ctx.fill(area, with: .linearGradient(
                Gradient(colors: [color.opacity(0.26), color.opacity(0.02)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))

            ctx.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

            let last = point(values.count - 1)
            ctx.fill(Path(ellipseIn: CGRect(x: last.x - 2.4, y: last.y - 2.4, width: 4.8, height: 4.8)),
                     with: .color(color))
        }
    }
}

// MARK: - 五段耗时条（DNS/TCP/TLS/TTFB/下载）

struct SegmentBar: View {
    let phases: [HttpPhase]

    private var phaseColors: [Color] {
        [Theme.cyan, Theme.blue, Theme.purple, Theme.magenta, Theme.green]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let total = max(phases.map(\.seconds).reduce(0, +), 0.0001)
                HStack(spacing: 2) {
                    ForEach(Array(phases.enumerated()), id: \.element.id) { _, phase in
                        let w = max(6, CGFloat(phase.seconds / total) * max(geo.size.width - CGFloat(phases.count - 1) * 2, 0))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(phaseColors[min(phase.colorIndex, 4)].opacity(0.85))
                            .frame(width: w)
                    }
                }
            }
            .frame(height: 18)

            HStack(spacing: 12) {
                ForEach(Array(phases.enumerated()), id: \.element.id) { _, phase in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(phaseColors[min(phase.colorIndex, 4)])
                            .frame(width: 5, height: 5)
                        Text("\(phase.name) \(Fmt.ms(phase.seconds * 1000))")
                            .font(Theme.mono(9.5))
                            .foregroundColor(Theme.textSecondary)
                    }
                }
            }
        }
    }
}

// MARK: - 信道频谱占用

struct SpectrumChart: View {
    let entries: [(channel: Int, count: Int)]
    let band: String
    var currentChannel: Int?

    private var channels: [Int] {
        band == "2.4GHz" ? Array(1...14) : Array(stride(from: 36, through: 165, by: 4))
    }

    private var maxCount: Int {
        max(1, entries.map(\.count).max() ?? 1)
    }

    private func count(for ch: Int) -> Int {
        entries.first(where: { $0.channel == ch })?.count ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(channels, id: \.self) { ch in
                        SpectrumBar(
                            fraction: Double(count(for: ch)) / Double(maxCount),
                            hasCount: count(for: ch) > 0,
                            isCurrent: ch == currentChannel,
                            heightLimit: geo.size.height)
                    }
                }
                .animation(.spring(response: 0.5, dampingFraction: 0.9), value: entries.map(\.count))
            }
            HStack(spacing: 2) {
                ForEach(channels, id: \.self) { ch in
                    Text(label(for: ch))
                        .font(Theme.mono(7.5))
                        .foregroundColor(Theme.textFaint)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func label(for ch: Int) -> String {
        let step = band == "2.4GHz" ? 2 : 8
        return (ch % step == 0 || ch == channels.first) ? "\(ch)" : ""
    }
}

private struct SpectrumBar: View {
    let fraction: Double
    let hasCount: Bool
    let isCurrent: Bool
    let heightLimit: CGFloat

    private var barHeight: CGFloat {
        if !hasCount { return 2 }
        return max(5, CGFloat(fraction) * heightLimit)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(fillStyle)
            .frame(height: barHeight)
            .overlay(alignment: .top) {
                if isCurrent {
                    TriangleShape()
                        .fill(Theme.cyan)
                        .frame(width: 8, height: 5)
                        .offset(y: -8)
                        .shadow(color: Theme.cyan.opacity(0.8), radius: 3)
                }
            }
    }

    private var fillStyle: AnyShapeStyle {
        if isCurrent { return AnyShapeStyle(Theme.accentGradient) }
        let opacity = hasCount ? 0.16 + 0.12 * fraction : 0.06
        return AnyShapeStyle(Color.white.opacity(opacity))
    }
}

struct TriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - 雷达扫描（信道/邻居装饰视图）

struct RadarSweep: View {
    /// angle: 0-2π，radius: 0-1（外缘=1），strength: 0-1
    var blips: [(angle: Double, radius: Double, strength: Double)] = []
    var size: CGFloat = 148

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 3.6) / 3.6   // 3.6s 一圈
            ZStack {
                ForEach(1...3, id: \.self) { i in
                    Circle()
                        .stroke(Theme.cyan.opacity(0.16), lineWidth: 0.7)
                        .frame(width: size * CGFloat(i) / 3, height: size * CGFloat(i) / 3)
                }
                Circle()
                    .stroke(Theme.cyan.opacity(0.10), lineWidth: 0.7)
                    .frame(width: size, height: size)
                ForEach(0..<8, id: \.self) { i in
                    Line()
                        .stroke(Theme.cyan.opacity(0.07), lineWidth: 0.6)
                        .frame(width: size, height: size)
                        .rotationEffect(.degrees(Double(i) * 45))
                }
                // 扫描扇形
                Circle()
                    .fill(AngularGradient(
                        colors: [Theme.cyan.opacity(0.30), Theme.cyan.opacity(0.04), .clear],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(64)))
                    .frame(width: size - 2, height: size - 2)
                    .rotationEffect(.degrees(t * 360))
                // 目标点
                ForEach(Array(blips.enumerated()), id: \.offset) { _, blip in
                    let r = size / 2 * CGFloat(min(max(blip.radius, 0.05), 1))
                    let x = size / 2 + r * CGFloat(Foundation.cos(blip.angle))
                    let y = size / 2 + r * CGFloat(Foundation.sin(blip.angle))
                    // 扫描线掠过时点亮
                    let blipDeg = blip.angle * 180 / .pi
                    let sweepDeg = t * 360
                    let delta = abs((sweepDeg - blipDeg).truncatingRemainder(dividingBy: 360))
                    let glow = delta < 60 ? 1 - delta / 60 : 0.15
                    Circle()
                        .fill(blip.strength > 0.66 ? Theme.red :
                              blip.strength > 0.33 ? Theme.yellow : Theme.cyan)
                        .frame(width: 4 + CGFloat(blip.strength * 3), height: 4 + CGFloat(blip.strength * 3))
                        .position(x: x, y: y)
                        .shadow(color: Theme.cyan.opacity(0.8 * glow), radius: 2 + 4 * glow)
                        .opacity(0.35 + 0.65 * glow)
                }
                Circle()
                    .fill(Theme.cyan)
                    .frame(width: 3, height: 3)
                    .shadow(color: Theme.cyan, radius: 4)
            }
            .frame(width: size, height: size)
        }
    }
}

struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return p
    }
}

// MARK: - 速度表盘

struct SpeedGauge: View {
    let mbps: Double
    var reference: Double = 0    // 协商速率参考线
    var untestedText: String = "—"

    private var fraction: Double { min(mbps / max(reference * 1.1, 100), 1) }

    var body: some View {
        ZStack {
            // 轨道
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(Theme.purple.opacity(0.16),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(135))
            // 参考线（协商速率）
            if reference > 0 {
                Circle()
                    .trim(from: min(reference / max(reference * 1.1, 100) * 0.75, 0.749),
                          to: min(reference / max(reference * 1.1, 100) * 0.75 + 0.006, 0.75))
                    .stroke(Theme.yellow.opacity(0.8), lineWidth: 10)
                    .rotationEffect(.degrees(135))
            }
            // 实测
            Circle()
                .trim(from: 0, to: 0.75 * fraction)
                .stroke(Theme.accentAngular,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(135))
                .shadow(color: Theme.cyan.opacity(0.22), radius: 4)
            VStack(spacing: 3) {
                Text(mbps > 0 ? Fmt.mbps(mbps) : untestedText)
                    .font(Theme.mono(mbps > 0 ? 26 : 19, .semibold))
                    .foregroundColor(mbps > 0 ? Theme.cyan : Theme.textPrimary)
                Text(reference > 0 ? L10n.tf("sp.negotiated", Fmt.mbps(reference)) : "")
                    .font(Theme.mono(9.5))
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .animation(.spring(response: 0.7, dampingFraction: 0.85), value: mbps)
    }
}
