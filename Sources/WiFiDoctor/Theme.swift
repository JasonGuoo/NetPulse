import SwiftUI

// MARK: - 霓虹 HUD 设计令牌

enum Theme {
    static let bgTop = Color(hex: 0x0A0E1A)
    static let bgBottom = Color(hex: 0x0D1220)

    static let cyan = Color(hex: 0x22D3EE)
    static let purple = Color(hex: 0xA78BFA)
    static let magenta = Color(hex: 0xF472B6)
    static let green = Color(hex: 0x34D399)
    static let yellow = Color(hex: 0xFBBF24)
    static let red = Color(hex: 0xF87171)
    static let blue = Color(hex: 0x60A5FA)
    static let orange = Color(hex: 0xFB923C)

    static let textPrimary = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.55)
    static let textFaint = Color.white.opacity(0.32)

    static let cardFill = Color.white.opacity(0.045)

    static var bgGradient: LinearGradient {
        LinearGradient(colors: [bgTop, bgBottom], startPoint: .top, endPoint: .bottom)
    }

    static var accentGradient: LinearGradient {
        LinearGradient(colors: [cyan, purple], startPoint: .leading, endPoint: .trailing)
    }

    static var accentAngular: AngularGradient {
        AngularGradient(colors: [cyan, purple, magenta, cyan], center: .center)
    }

    static var cardBorder: LinearGradient {
        LinearGradient(
            colors: [cyan.opacity(0.45), purple.opacity(0.28)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
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
