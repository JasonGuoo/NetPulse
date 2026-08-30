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
            case .overview: return "rectangle.grid.2x2"
            case .connections: return "point.3.connected.trianglepath.dotted"
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
                AppToolbar(selected: $tab)
                SectionRule()
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
            .padding(.top, 22)
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 1060, minHeight: 700)
        .onReceive(NotificationCenter.default.publisher(for: .openHopGaugeDiagnosis)) { _ in
            withAnimation(.easeOut(duration: 0.18)) { tab = .diagnose }
        }
    }
}

extension Notification.Name {
    static let openHopGaugeDiagnosis = Notification.Name("HopGauge.openDiagnosis")
}

// MARK: - Compact application toolbar

struct AppToolbar: View {
    @EnvironmentObject var model: AppModel
    @Binding var selected: ContentView.Tab
    @State private var showHealth = false

    private var statusText: String {
        if let ssid = model.wifi.ssid { return ssid }
        if model.wifi.connected { return L10n.t("ssid.protected") }
        return L10n.t("status.offline")
    }

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(nsImage: AppDelegate.renderIcon(size: 32))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text("HopGauge")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.textPrimary)
            }

            TabStrip(selected: $selected)

            Spacer(minLength: 8)

            LiveBadge()

            if let rssi = model.wifi.rssi {
                HStack(spacing: 6) {
                    SignalBars(rssi: rssi)
                    MetricValue(value: "\(rssi)", unit: "dBm", color: Quality.rssi(rssi).color, size: 11)
                }
            }

            StatusPill(online: model.wifi.connected, text: statusText)
                .frame(maxWidth: 150)

            RefreshButton()
            LanguageMenu()
            AppSettingsMenu()

            Button {
                showHealth.toggle()
            } label: {
                HealthRing(score: model.healthScore, size: 40, lineWidth: 3.5)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(L10n.t("health.explain"))
            .popover(isPresented: $showHealth, arrowEdge: .bottom) {
                HealthBreakdownPopover()
                    .environmentObject(model)
            }
        }
        .frame(height: 52)
        .padding(.horizontal, 4)
        .padding(.bottom, 7)
    }
}

struct HealthBreakdownPopover: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("health.breakdown"))
                        .font(.system(size: 14, weight: .semibold))
                    Text(L10n.t("health.explain"))
                        .font(.system(size: 10.5))
                        .foregroundColor(Theme.textSecondary)
                }
                Spacer()
                MetricValue(value: "\(model.healthScore)", unit: "/ 100", color: scoreColor(model.healthScore), size: 22)
            }
            SectionRule()
            scoreRow("Wi-Fi", score: model.wifiHealthScore)
            scoreRow(L10n.t("ov.gateway"), score: model.gatewayHealthScore)
            scoreRow("DNS", score: model.dnsHealthScore)
            scoreRow("Internet", score: model.internetHealthScore)
            scoreRow(L10n.t("health.stability"), score: model.stabilityHealthScore)
        }
        .padding(16)
        .frame(width: 300)
        .background(Theme.panel)
    }

    private func scoreRow(_ title: String, score: Int) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(Theme.textSecondary)
            Spacer()
            Text(QualityForScore.label(score))
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(scoreColor(score))
            Text("\(score)")
                .font(Theme.mono(11.5, .semibold))
                .monospacedDigit()
                .foregroundColor(Theme.textPrimary)
                .frame(width: 30, alignment: .trailing)
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        if score >= 85 { return Theme.green }
        if score >= 70 { return Theme.cyan }
        if score >= 50 { return Theme.yellow }
        return Theme.red
    }
}

// MARK: - Refresh button

struct RefreshButton: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Button {
            guard !model.isRefreshing else { return }
            Task { await model.coordinator?.refreshAll() }
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(model.isRefreshing ? Theme.textFaint : Theme.textSecondary)
                .rotationEffect(.degrees(model.isRefreshing ? 360 : 0))
                .animation(model.isRefreshing ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default,
                           value: model.isRefreshing)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.white.opacity(0.04)))
                .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 0.8))
        }
        .buttonStyle(.plain)
        .disabled(model.isRefreshing)
        .help(L10n.t("refresh"))
    }
}

// MARK: - Language menu

struct LanguageMenu: View {
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        Menu {
            ForEach(AppLanguage.allCases) { language in
                Button {
                    L10n.shared.language = language
                } label: {
                    if language == l10n.language {
                        Label(language.displayName, systemImage: "checkmark")
                    } else {
                        Text(language.displayName)
                    }
                }
            }
        } label: {
            Image(systemName: "globe.asia.australia")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.textSecondary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.white.opacity(0.04)))
                .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 0.8))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Navigation

struct TabStrip: View {
    @Binding var selected: ContentView.Tab

    var body: some View {
        HStack(spacing: 3) {
            ForEach(ContentView.Tab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { selected = tab }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 10, weight: .medium))
                        Text(tab.title)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(selected == tab ? Theme.cyan : Theme.textSecondary)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(selected == tab ? Theme.cyan.opacity(0.10) : Color.clear)
                    )
                    .overlay(alignment: .bottom) {
                        if selected == tab {
                            Capsule().fill(Theme.cyan).frame(width: 22, height: 1.5)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Subtle background grid

struct GridOverlay: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 52
            var x: CGFloat = 0
            while x < size.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(Color.white.opacity(0.012)), lineWidth: 0.5)
                x += step
            }
            var y: CGFloat = 0
            while y < size.height {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(Color.white.opacity(0.012)), lineWidth: 0.5)
                y += step
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}
