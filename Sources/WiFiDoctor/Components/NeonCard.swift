import SwiftUI

// MARK: - 玻璃霓虹卡片

struct NeonCard<Content: View>: View {
    let title: String
    var systemImage: String? = nil
    var live: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                if let si = systemImage {
                    Image(systemName: si)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accentGradient)
                }
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(1.8)
                    .textCase(.uppercase)
                    .foregroundColor(Theme.cyan.opacity(0.85))
                Spacer()
                if live { LiveBadge() }
            }

            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.28))
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.cardFill)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.cardBorder, lineWidth: 1)
        )
        .shadow(color: Theme.cyan.opacity(0.10), radius: 16, x: 0, y: 5)
        .shadow(color: Theme.purple.opacity(0.07), radius: 22, x: 0, y: 10)
    }
}

// MARK: - LIVE 呼吸灯

struct LiveBadge: View {
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Theme.green)
                .frame(width: 6, height: 6)
                .shadow(color: Theme.green.opacity(0.9), radius: pulse ? 5 : 2)
                .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)
            Text("LIVE")
                .font(Theme.mono(8, .bold))
                .kerning(1.2)
                .foregroundColor(Theme.green.opacity(0.85))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Theme.green.opacity(0.08)))
        .overlay(Capsule().strokeBorder(Theme.green.opacity(0.25), lineWidth: 0.8))
        .onAppear { pulse = true }
    }
}

// MARK: - 状态胶囊

struct StatusPill: View {
    var online: Bool
    var text: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(online ? Theme.green : Theme.red)
                .frame(width: 7, height: 7)
                .shadow(color: (online ? Theme.green : Theme.red).opacity(0.9), radius: 4)
            Text(text)
                .font(Theme.mono(10, .medium))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8))
    }
}

// MARK: - 数据磁贴

struct StatTile: View {
    let title: String
    let value: String
    var sub: String? = nil
    var color: Color = Theme.cyan
    var trendUp: Bool? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .kerning(1.0)
                .foregroundColor(Theme.textFaint)
                .textCase(.uppercase)
            Text(value)
                .font(Theme.mono(19, .bold))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let sub {
                Text(sub)
                    .font(Theme.mono(9.5))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [color.opacity(0.35), Color.white.opacity(0.05)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 0.8
                )
        )
        .shadow(color: color.opacity(0.10), radius: 8, x: 0, y: 3)
    }
}

// MARK: - 行式键值对

struct KeyValueRow: View {
    let key: String
    let value: String
    var valueColor: Color = Theme.textPrimary

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(Theme.textSecondary)
            Spacer(minLength: 12)
            Text(value)
                .font(Theme.mono(11.5, .medium))
                .foregroundColor(valueColor)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 3.5)
    }
}

// MARK: - 信号强度条

struct SignalBars: View {
    let rssi: Int?
    private let thresholds: [Int] = [-70, -63, -56, -49]

    var body: some View {
        let level: Int = {
            guard let r = rssi else { return 0 }
            return thresholds.filter { r >= $0 }.count
        }()
        HStack(spacing: 3) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(i < level ? Quality.rssi(rssi ?? -100).color : Color.white.opacity(0.12))
                    .frame(width: 5, height: CGFloat(7 + i * 4))
            }
        }
    }
}

// MARK: - 结论徽章

struct VerdictBadge: View {
    let severity: VerdictSeverity

    var color: Color {
        switch severity {
        case .good: return Theme.green
        case .info: return Theme.cyan
        case .warn: return Theme.yellow
        case .bad: return Theme.red
        }
    }

    var body: some View {
        Text(severity.label)
            .font(.system(size: 9.5, weight: .bold))
            .kerning(0.8)
            .foregroundColor(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(Capsule().fill(color.opacity(0.12)))
            .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 0.8))
    }
}
