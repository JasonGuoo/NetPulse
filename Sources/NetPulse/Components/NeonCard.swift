import SwiftUI

// MARK: - Quiet professional surface

struct NeonCard<Content: View>: View {
    let title: String
    var systemImage: String? = nil
    var live: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.cyan.opacity(0.9))
                }
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(0.6)
                    .foregroundColor(Theme.textSecondary)
                Spacer()
            }
            content()
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.cardBorder, lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.22), radius: 16, x: 0, y: 8)
    }
}

// MARK: - Single global monitoring state

struct LiveBadge: View {
    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Theme.green)
                .frame(width: 6, height: 6)
            Text(L10n.t("monitoring"))
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(Theme.textSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.white.opacity(0.045)))
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.8))
    }
}

// MARK: - Status pill

struct StatusPill: View {
    var online: Bool
    var text: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(online ? Theme.green : Theme.red)
                .frame(width: 7, height: 7)
            Text(text)
                .font(Theme.mono(10, .medium))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.white.opacity(0.045)))
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.8))
    }
}

// MARK: - Data tile

struct StatTile: View {
    let title: String
    let value: String
    var sub: String? = nil
    var color: Color = Theme.textPrimary
    var trendUp: Bool? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .kerning(0.7)
                .foregroundColor(Theme.textFaint)
                .textCase(.uppercase)
            Text(value)
                .font(Theme.mono(18, .semibold))
                .monospacedDigit()
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let sub {
                Text(sub)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.panelRaised.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 0.8)
        )
    }
}

// MARK: - Instrument-style number

struct MetricValue: View {
    let value: String
    var unit: String = ""
    var color: Color = Theme.textPrimary
    var size: CGFloat = 24

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(Theme.mono(size, .semibold))
                .monospacedDigit()
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            if !unit.isEmpty {
                Text(unit)
                    .font(Theme.mono(size * 0.58, .medium))
                    .foregroundColor(color.opacity(0.72))
            }
        }
    }
}

struct QuietMetricRow: View {
    let title: String
    let value: String
    var unit: String = ""
    var status: String? = nil
    var color: Color = Theme.textPrimary

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.textSecondary)
            Spacer(minLength: 10)
            MetricValue(value: value, unit: unit, color: color, size: 12)
            if let status {
                Text(status)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundColor(color)
                    .frame(width: 58, alignment: .trailing)
            }
        }
        .padding(.vertical, 5)
    }
}

// MARK: - Key/value row

struct KeyValueRow: View {
    let key: String
    let value: String
    var valueColor: Color = Theme.textPrimary

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.textSecondary)
            Spacer(minLength: 12)
            Text(value)
                .font(Theme.mono(11, .medium))
                .monospacedDigit()
                .foregroundColor(valueColor)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 3.5)
    }
}

struct SectionRule: View {
    var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: 0.8)
    }
}

// MARK: - Signal strength bars

struct SignalBars: View {
    let rssi: Int?
    private let thresholds: [Int] = [-70, -63, -56, -49]

    var body: some View {
        let level: Int = {
            guard let rssi else { return 0 }
            return thresholds.filter { rssi >= $0 }.count
        }()
        HStack(spacing: 3) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(index < level ? Quality.rssi(rssi ?? -100).color : Color.white.opacity(0.12))
                    .frame(width: 5, height: CGFloat(7 + index * 4))
            }
        }
    }
}

// MARK: - Verdict badge

struct VerdictBadge: View {
    let severity: VerdictSeverity

    private var color: Color { Theme.statusColor(severity) }

    var body: some View {
        Text(severity.label)
            .font(.system(size: 9.5, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(Capsule().fill(color.opacity(0.10)))
            .overlay(Capsule().strokeBorder(color.opacity(0.24), lineWidth: 0.8))
    }
}
