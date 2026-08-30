import SwiftUI

// MARK: - HopGauge design tokens

enum Theme {
    static let bgTop = Color(hex: 0x07101C)
    static let bgBottom = Color(hex: 0x0A1422)
    static let panel = Color(hex: 0x101B2A)
    static let panelRaised = Color(hex: 0x142133)
    static let panelMuted = Color(hex: 0x0D1724)

    static let cyan = Color(hex: 0x2FD8F3)
    static let purple = Color(hex: 0x8B7CFF)
    static let magenta = Color(hex: 0xC778E8)
    static let green = Color(hex: 0x35D39B)
    static let yellow = Color(hex: 0xF5B94C)
    static let red = Color(hex: 0xFF6B78)
    static let blue = Color(hex: 0x5AA7FF)
    static let orange = Color(hex: 0xF39B55)

    static let textPrimary = Color.white.opacity(0.94)
    static let textSecondary = Color.white.opacity(0.62)
    static let textFaint = Color.white.opacity(0.38)

    static let cardFill = panel.opacity(0.94)
    static let hairline = Color.white.opacity(0.075)
    static let strongHairline = Color.white.opacity(0.12)

    static var bgGradient: LinearGradient {
        LinearGradient(colors: [bgTop, bgBottom], startPoint: .top, endPoint: .bottom)
    }

    static var accentGradient: LinearGradient {
        LinearGradient(colors: [cyan, purple], startPoint: .leading, endPoint: .trailing)
    }

    static var accentAngular: AngularGradient {
        AngularGradient(colors: [cyan, blue, purple, cyan], center: .center)
    }

    static var cardBorder: LinearGradient {
        LinearGradient(
            colors: [Color.white.opacity(0.10), Color.white.opacity(0.055)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func statusColor(_ severity: VerdictSeverity) -> Color {
        switch severity {
        case .good: return green
        case .info: return cyan
        case .warn: return yellow
        case .bad: return red
        }
    }
}

// MARK: - 信号/质量分级

enum Quality {
    case good, fair, poor, bad

    var color: Color {
        switch self {
        case .good: return Theme.green
        case .fair: return Theme.cyan
        case .poor: return Theme.yellow
        case .bad: return Theme.red
        }
    }

    var label: String {
        switch self {
        case .good: return L10n.t("q.good")
        case .fair: return L10n.t("q.fair")
        case .poor: return L10n.t("q.poor")
        case .bad: return L10n.t("q.bad")
        }
    }

    static func rssi(_ dbm: Int) -> Quality {
        switch dbm {
        case let v where v >= -50: return .good
        case -55...(-50): return .good
        case -60...(-55): return .fair
        case -70...(-60): return .poor
        default: return .bad
        }
    }

    static func snr(_ db: Int) -> Quality {
        switch db {
        case let v where v >= 40: return .good
        case 25...39: return .fair
        case 15...24: return .poor
        default: return .bad
        }
    }
}

// MARK: - Color hex init

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }
}

// MARK: - 数值格式化

enum Fmt {
    static func bytes(_ v: Double) -> String {
        let absV = abs(v)
        if absV >= 1_073_741_824 { return String(format: "%.2f GB", v / 1_073_741_824) }
        if absV >= 1_048_576 { return String(format: "%.1f MB", v / 1_048_576) }
        if absV >= 1024 { return String(format: "%.1f KB", v / 1024) }
        return String(format: "%.0f B", v)
    }

    static func rate(_ bytesPerSec: Double) -> String {
        let absV = abs(bytesPerSec)
        if absV >= 1_048_576 { return String(format: "%.1f MB/s", bytesPerSec / 1_048_576) }
        if absV >= 1024 { return String(format: "%.1f KB/s", bytesPerSec / 1024) }
        return String(format: "%.0f B/s", bytesPerSec)
    }

    static func mbps(_ v: Double) -> String {
        String(format: "%.1f Mbps", v)
    }

    static func ms(_ v: Double) -> String {
        if v >= 1000 { return String(format: "%.2f s", v / 1000) }
        return String(format: "%.1f ms", v)
    }

    static func pct(_ v: Double) -> String {
        String(format: "%.1f%%", v)
    }
}
