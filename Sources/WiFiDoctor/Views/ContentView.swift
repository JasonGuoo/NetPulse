import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var l10n = L10n.shared
    @State private var tab: Tab

    init(initialTab: Tab = .overview) {
        _tab = State(initialValue: initialTab)
    }

    enum Tab: String, CaseIterable {
        case overview = "tab.overview"
        case connections = "tab.connections"
        case link = "tab.link"
        case speed = "tab.speed"
        case diagnose = "tab.diagnose"

        var title: String { L10n.t(rawValue) }

        var icon: String {
            switch self {
            case .overview: return "gauge"
            case .connections: return "antenna.radiowaves.left.and.right"
            case .link: return "wifi"
            case .speed: return "speedometer"
            case .diagnose: return "stethoscope"
            }
        }
    }

    var body: some View {
        ZStack {
            Theme.bgGradient.ignoresSafeArea()
            GridOverlay()
            VStack(spacing: 0) {
                HeaderView()
                TabStrip(selected: $tab)
                Rectangle()
                    .fill(Theme.cyan.opacity(0.14))
                    .frame(height: 0.8)
                Group {
                    switch tab {
                    case .overview: OverviewView()
                    case .connections: ConnectionsView()
                    case .link: WifiLinkView()
                    case .speed: ThroughputView()
                    case .diagnose: DiagnoseView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.top, 26)
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 1020, minHeight: 660)
    }
}

// MARK: - 顶栏

struct HeaderView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var l10n = L10n.shared

    var statusText: String {
        if let ssid = model.wifi.ssid { return ssid }
        if model.wifi.connected { return L10n.t("ssid.protected") }
        return L10n.t("status.offline")
    }

    var body: some View {
        HStack(spacing: 14) {
            // 徽标
            ZStack {
                HexagonShape()
                    .fill(
                        LinearGradient(colors: [Theme.cyan.opacity(0.24), Theme.purple.opacity(0.24)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(HexagonShape().stroke(Theme.accentGradient, lineWidth: 1.2))
                    .frame(width: 40, height: 40)
                    .shadow(color: Theme.cyan.opacity(0.4), radius: 7)
                Image(systemName: "wifi")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.accentGradient)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("WIFI·DOCTOR")
                    .font(.system(size: 16, weight: .heavy))
                    .kerning(2.4)
                    .foregroundStyle(Theme.accentGradient)
                Text(L10n.t("app.subtitle"))
                    .font(.system(size: 9.5))
                    .kerning(1.2)
                    .foregroundColor(Theme.textFaint)
            }

            Spacer()

            HStack(spacing: 10) {
                if let v = model.wifi.rssi {
                    HStack(spacing: 5) {
                        SignalBars(rssi: v)
                        Text("\(v) dBm")
                            .font(Theme.mono(11, .semibold))
                            .foregroundColor(Quality.rssi(v).color)
                    }
                }
                StatusPill(online: model.wifi.connected, text: statusText)

                RefreshButton()

                LanguageMenu()

                HealthRing(score: model.healthScore, size: 56, lineWidth: 5)
            }
        }
        .padding(.bottom, 12)
    }
}

// MARK: - 刷新按钮（全页面可见）

struct RefreshButton: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var l10n = L10n.shared
    @State private var spinning = false

    var body: some View {
        Button {
            guard !model.isRefreshing else { return }
            Task { await model.coordinator?.refreshAll() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 10, weight: .bold))
                    .rotationEffect(.degrees(spinning ? 360 : 0))
                Text(L10n.t(model.isRefreshing ? "refreshing" : "refresh"))
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundColor(Theme.cyan)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(Theme.cyan.opacity(0.08))
                    .overlay(Capsule().strokeBorder(Theme.cyan.opacity(0.35), lineWidth: 0.8))
            )
            .shadow(color: Theme.cyan.opacity(0.25), radius: 5)
        }
        .buttonStyle(.plain)
        .onChange(of: model.isRefreshing) { active in
            if active {
                spinning = true
            } else {
                withAnimation(.easeOut(duration: 0.3)) { spinning = false }
            }
        }
        .help(L10n.t("refresh"))
    }
}

// MARK: - 语言菜单

struct LanguageMenu: View {
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        Menu {
            ForEach(AppLanguage.allCases) { lang in
                Button {
                    L10n.shared.language = lang
                } label: {
                    if lang == l10n.language {
                        Label(lang.displayName, systemImage: "checkmark")
                    } else {
                        Text(lang.displayName)
                    }
                }
            }
        } label: {
            Image(systemName: "globe.asia.australia")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accentGradient)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.white.opacity(0.06)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onAppear { _ = l10n.language }
    }
}

struct HexagonShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        for i in 0..<6 {
            let angle = Double(i) / 6 * 2 * Double.pi - Double.pi / 2
            let pt = CGPoint(x: c.x + r * CGFloat(Foundation.cos(angle)),
                             y: c.y + r * CGFloat(Foundation.sin(angle)))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - Tab 条

struct TabStrip: View {
    @Binding var selected: ContentView.Tab
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ContentView.Tab.allCases, id: \.self) { t in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        selected = t
                    }
                } label: {
                    VStack(spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: t.icon)
                                .font(.system(size: 11, weight: .semibold))
                            Text(t.title)
                                .font(.system(size: 12.5, weight: .medium))
                                .kerning(1)
                        }
                        .foregroundColor(selected == t ? Theme.cyan : Theme.textSecondary)
                        Capsule()
                            .fill(selected == t ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.clear))
                            .frame(width: 44, height: 2.4)
                            .shadow(color: selected == t ? Theme.cyan.opacity(0.7) : .clear, radius: 3)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.bottom, 8)
    }
}

// MARK: - 背景网格

struct GridOverlay: View {
    var body: some View {
        Canvas { ctx, size in
            let step: CGFloat = 46
            var x: CGFloat = 0
            while x < size.width {
                var p = Path()
                p.move(to: CGPoint(x: x, y: 0))
                p.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(p, with: .color(Color.white.opacity(0.022)), lineWidth: 0.6)
                x += step
            }
            var y: CGFloat = 0
            while y < size.height {
                var p = Path()
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(p, with: .color(Color.white.opacity(0.022)), lineWidth: 0.6)
                y += step
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}
