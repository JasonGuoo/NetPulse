import SwiftUI

/// 连接页：以"谁在用网"为核心的可视化视图
struct ConnectionsView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var l10n = L10n.shared
    @State private var mode: Mode = .byProcess
    @State private var searchText = ""

    enum Mode: String, CaseIterable {
        case byProcess = "cn.who"
        case byConnection = "cn.all"
        case listening = "cn.listen"

        var title: String { L10n.t(rawValue) }

        var icon: String {
            switch self {
            case .byProcess: return "person.2.fill"
            case .byConnection: return "link"
            case .listening: return "ear"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerStrip
            toolbar
            Rectangle().fill(Color.white.opacity(0.05)).frame(height: 0.8)
            Group {
                switch mode {
                case .byProcess: WhoUsesNetworkView(searchText: searchText)
                case .byConnection: ConnectionTable(rows: filteredConnections)
                case .listening: ListeningView(searchText: searchText)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, 12)
    }

    // MARK: 顶部总览条

    private var headerStrip: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(Theme.cyan)
                VStack(alignment: .leading, spacing: 0) {
                    Text(Fmt.rate(model.totalRateIn))
                        .font(Theme.mono(16, .bold))
                        .foregroundColor(Theme.cyan)
                    Text(L10n.t("cn.totaldown"))
                        .font(.system(size: 9))
                        .foregroundColor(Theme.textFaint)
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundStyle(Theme.purple)
                VStack(alignment: .leading, spacing: 0) {
                    Text(Fmt.rate(model.totalRateOut))
                        .font(Theme.mono(16, .bold))
                        .foregroundColor(Theme.purple)
                    Text(L10n.t("cn.totalup"))
                        .font(.system(size: 9))
                        .foregroundColor(Theme.textFaint)
                }
            }
            Sparkline(values: model.rateHistory.map(\.in), color: Theme.cyan)
                .frame(width: 120, height: 30)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(L10n.tf("cn.apps.online",
                             model.processTraffic.filter { $0.connections > 0 || $0.rateIn + $0.rateOut > 0 }.count))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                Text(L10n.tf("cn.conn.summary", model.connections.count, model.listenRows.count))
                    .font(Theme.mono(9.5))
                    .foregroundColor(Theme.textFaint)
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 10)
    }

    // MARK: 工具栏

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(Mode.allCases, id: \.self) { m in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { mode = m }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: m.icon).font(.system(size: 10, weight: .semibold))
                            Text(m.title).font(.system(size: 11.5, weight: .medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(mode == m ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.white.opacity(0.05)))
                        )
                        .overlay(Capsule().strokeBorder(mode == m ? Color.clear : Color.white.opacity(0.10), lineWidth: 0.8))
                        .foregroundColor(mode == m ? Color.black.opacity(0.85) : Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textFaint)
                TextField(L10n.t("cn.search"), text: $searchText)
                    .textFieldStyle(.plain)
                    .font(Theme.mono(11))
                    .frame(width: 170)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(0.05)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8))

            LiveBadge()
        }
        .padding(.bottom, 10)
    }

    private var filteredConnections: [ConnectionRow] {
        let rows = model.connections.sorted { ($0.rateIn + $0.rateOut) > ($1.rateIn + $1.rateOut) }
        guard !searchText.isEmpty else { return rows }
        return rows.filter {
            $0.process.localizedCaseInsensitiveContains(searchText) ||
            $0.remote.localizedCaseInsensitiveContains(searchText) ||
            IPProvider.describe($0).localizedCaseInsensitiveContains(searchText)
        }
    }
}

// MARK: - 谁在用网（默认视图）

struct WhoUsesNetworkView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var l10n = L10n.shared
    let searchText: String
    @State private var expanded: Set<String> = []

    private var visible: [ProcessTraffic] {
        let active = model.processTraffic
            .filter { $0.rateIn + $0.rateOut > 8 || $0.connections > 0 }
            .sorted { ($0.rateIn + $0.rateOut) > ($1.rateIn + $1.rateOut) }
        guard !searchText.isEmpty else { return Array(active.prefix(30)) }
        return active.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var maxRate: Double {
        max(visible.map { $0.rateIn + $0.rateOut }.max() ?? 1, 1024)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                if visible.isEmpty {
                    EmptyStateView(text: L10n.t("cn.empty.traffic"))
                } else {
                    ForEach(visible) { proc in
                        ProcessCardRow(
                            proc: proc,
                            connections: model.connections.filter { $0.pid == proc.pid && $0.hasRemote },
                            maxRate: maxRate,
                            expanded: expanded.contains(proc.id),
                            onToggle: { toggle(proc.id) })
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
    }

    private func toggle(_ id: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
        }
    }
}

// MARK: - 进程卡片

struct ProcessCardRow: View {
    @ObservedObject private var l10n = L10n.shared
    let proc: ProcessTraffic
    let connections: [ConnectionRow]
    let maxRate: Double
    let expanded: Bool
    let onToggle: () -> Void

    private var share: Double {
        min((proc.rateIn + proc.rateOut) / maxRate, 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    AppBadge(process: proc.name)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(AppBadgeInfo.of(process: proc.name).label)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundColor(Theme.textPrimary)
                                .lineLimit(1)
                            Text(L10n.tf("cn.pid", "\(proc.pid)"))
                                .font(Theme.mono(9))
                                .foregroundColor(Theme.textFaint)
                            if proc.connections > 0 {
                                Text(L10n.tf("cn.conns", proc.connections))
                                    .font(.system(size: 9.5))
                                    .foregroundColor(Theme.textFaint)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.white.opacity(0.06)))
                            }
                        }
                        // 带宽占比条
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.06))
                                Capsule()
                                    .fill(Theme.accentGradient.opacity(0.85))
                                    .frame(width: max(3, CGFloat(share) * geo.size.width))
                                    .shadow(color: Theme.cyan.opacity(0.4), radius: 3)
                            }
                        }
                        .frame(height: 6)
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 3) {
                        HStack(spacing: 10) {
                            rateLabel(value: proc.rateIn, color: Theme.cyan, arrow: "arrow.down")
                            rateLabel(value: proc.rateOut, color: Theme.purple, arrow: "arrow.up")
                        }
                        Text(L10n.tf("cn.accum", Fmt.bytes(Double(proc.totalIn)), Fmt.bytes(Double(proc.totalOut))))
                            .font(Theme.mono(8.5))
                            .foregroundColor(Theme.textFaint)
                    }

                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.textFaint)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.035))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            LinearGradient(colors: [Theme.cyan.opacity(0.25), Theme.purple.opacity(0.15)],
                                           startPoint: .leading, endPoint: .trailing),
                            lineWidth: 0.8)
                )
            }
            .buttonStyle(.plain)
            .help(L10n.t("cn.expand.hint"))

            if expanded {
                VStack(alignment: .leading, spacing: 4) {
                    if connections.isEmpty {
                        Text(L10n.t("cn.no.conns.detail"))
                            .font(.system(size: 10))
                            .foregroundColor(Theme.textFaint)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(Array(connections.sorted { ($0.rateIn + $0.rateOut) > ($1.rateIn + $1.rateOut) }.prefix(12))) { c in
                            ConnectionDetailRow(row: c)
                        }
                        if connections.count > 12 {
                            Text(L10n.tf("cn.more", connections.count - 12))
                                .font(Theme.mono(9))
                                .foregroundColor(Theme.textFaint)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.02))
                )
                .padding(.top, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func rateLabel(value: Double, color: Color, arrow: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: arrow)
                .font(.system(size: 8, weight: .bold))
            Text(Fmt.rate(value))
                .font(Theme.mono(11, .bold))
        }
        .foregroundColor(value > 8 ? color : Theme.textFaint)
    }
}

// MARK: - 应用徽标

struct AppBadge: View {
    let process: String

    private var info: AppBadgeInfo.Info { AppBadgeInfo.of(process: process) }

    private var badgeColor: Color {
        // 按名字稳定散列到主题色
        let palette: [Color] = [Theme.cyan, Theme.purple, Theme.magenta, Theme.blue, Theme.green, Theme.orange]
        var hash = 5381
        for b in process.utf8 { hash = (hash << 5) &+ Int(b) &+ hash }
        return palette[abs(hash) % palette.count]
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(colors: [badgeColor.opacity(0.32), badgeColor.opacity(0.12)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(badgeColor.opacity(0.4), lineWidth: 0.8))
                .frame(width: 34, height: 34)
                .shadow(color: badgeColor.opacity(0.25), radius: 5)
            if !info.symbol.isEmpty {
                Image(systemName: info.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(badgeColor)
            } else {
                Text(String(process.prefix(1)).uppercased())
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(badgeColor)
            }
        }
    }
}

// MARK: - 单条连接明细

struct ConnectionDetailRow: View {
    let row: ConnectionRow

    var body: some View {
        HStack(spacing: 8) {
            Text(IPProvider.describe(row))
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(providerColor)
                .frame(width: 92, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(row.remote)
                .font(Theme.mono(10))
                .foregroundColor(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            HStack(spacing: 6) {
                Text("↓\(Fmt.rate(row.rateIn))")
                    .font(Theme.mono(9.5, row.rateIn > 8 ? .bold : .regular))
                    .foregroundColor(row.rateIn > 8 ? Theme.cyan : Theme.textFaint)
                Text("↑\(Fmt.rate(row.rateOut))")
                    .font(Theme.mono(9.5, row.rateOut > 8 ? .bold : .regular))
                    .foregroundColor(row.rateOut > 8 ? Theme.purple : Theme.textFaint)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.025)))
    }

    private var providerColor: Color {
        let name = IPProvider.describe(row)
        switch name {
        case L10n.t("ip.loopback"), L10n.t("ip.lan"), L10n.t("ip.linklocal"): return Theme.green
        case L10n.t("ip.external"), "IPv6": return Theme.textSecondary
        default: return Theme.cyan
        }
    }
}

// MARK: - 全部连接表

struct ConnectionTable: View {
    @ObservedObject private var l10n = L10n.shared
    let rows: [ConnectionRow]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                TableRowHeader(columns: [L10n.t("cn.who"), L10n.t("cn.provider"), L10n.t("cn.remote"),
                                         L10n.t("cn.proto"), L10n.t("cn.state"),
                                         L10n.t("cn.rate.down"), L10n.t("cn.rate.up")],
                               widths: [nil, 84, 200, 48, 92, 96, 96])
                if rows.isEmpty {
                    EmptyStateView(text: L10n.t("cn.empty.conns"))
                } else {
                    ForEach(rows) { row in
                        HStack(spacing: 0) {
                            tableCell(label: AppBadgeInfo.of(process: row.process).label, color: Theme.textPrimary, weight: .medium)
                            tableCell(label: IPProvider.describe(row), color: providerColor(row), width: 84)
                            tableCell(label: row.remote, color: Theme.textSecondary, width: 200)
                            protoPill(row.proto)
                                .frame(width: 48, alignment: .leading)
                            statePill(row.state)
                                .frame(width: 92, alignment: .leading)
                            tableCell(label: Fmt.rate(row.rateIn), color: row.rateIn > 1024 ? Theme.cyan : Theme.textSecondary, width: 96)
                            tableCell(label: Fmt.rate(row.rateOut), color: row.rateOut > 1024 ? Theme.purple : Theme.textSecondary, width: 96)
                            Spacer(minLength: 0)
                        }
                        .modifier(TableRowBackground())
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
        }
    }

    private func providerColor(_ row: ConnectionRow) -> Color {
        let name = IPProvider.describe(row)
        if name == L10n.t("ip.lan") || name == L10n.t("ip.loopback") { return Theme.green }
        if name == L10n.t("ip.external") || name == "IPv6" { return Theme.textFaint }
        return Theme.cyan
    }
}

@ViewBuilder
private func protoPill(_ proto: String) -> some View {
    Text(proto)
        .font(Theme.mono(8.5, .bold))
        .foregroundColor(proto == "TCP" ? Theme.blue : Theme.magenta)
        .padding(.horizontal, 5)
        .padding(.vertical, 1.5)
        .background(Capsule().fill((proto == "TCP" ? Theme.blue : Theme.magenta).opacity(0.12)))
}

@ViewBuilder
private func statePill(_ state: String) -> some View {
    let color: Color = {
        switch state {
        case "ESTABLISHED": return Theme.green
        case "LISTEN": return Theme.cyan
        case "CLOSE_WAIT", "TIME_WAIT": return Theme.yellow
        default: return Theme.textFaint
        }
    }()
    Text(state)
        .font(Theme.mono(8.5))
        .foregroundColor(color)
        .padding(.horizontal, 5)
        .padding(.vertical, 1.5)
        .background(Capsule().fill(color.opacity(0.10)))
}

// MARK: - 监听端口（按软件分组）

struct ListeningView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var l10n = L10n.shared
    let searchText: String

    private var grouped: [(name: String, pid: Int, ports: [ConnectionRow])] {
        let filtered = model.listenRows.filter { row in
            searchText.isEmpty ||
            row.process.localizedCaseInsensitiveContains(searchText) ||
            row.local.localizedCaseInsensitiveContains(searchText)
        }
        let dict = Dictionary(grouping: filtered, by: { (row) in "\(row.pid)-\(row.process)" })
        return dict.map { key, rows in
            let pid = Int(key.split(separator: "-").first ?? "") ?? 0
            let name = rows.first?.process ?? key
            return (name, pid, rows.sorted { $0.local < $1.local })
        }
        .sorted { $0.ports.count > $1.ports.count }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(Theme.accentGradient)
                    Text(L10n.t("cn.listen.explain"))
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 2)

                if grouped.isEmpty {
                    EmptyStateView(text: L10n.t("cn.empty.listen"))
                } else {
                    ForEach(grouped, id: \.name) { group in
                        NeonCard(title: group.name, systemImage: "ear") {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 6)],
                                      alignment: .leading, spacing: 6) {
                                ForEach(group.ports) { port in
                                    HStack(spacing: 4) {
                                        Text(port.proto)
                                            .font(Theme.mono(8, .bold))
                                            .foregroundColor(port.proto == "TCP" ? Theme.blue : Theme.magenta)
                                        Text(port.local.replacingOccurrences(of: "*:", with: "#"))
                                            .font(Theme.mono(10.5, .medium))
                                            .foregroundColor(Theme.textPrimary)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.white.opacity(0.05)))
                                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.7))
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - 表格基础件

struct TableRowHeader: View {
    let columns: [String]
    let widths: [CGFloat?]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.offset) { i, c in
                Text(c)
                    .font(.system(size: 9.5, weight: .bold))
                    .kerning(0.8)
                    .foregroundColor(Theme.textFaint)
                    .frame(width: widths[i], alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.03))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.cyan.opacity(0.15)).frame(height: 0.8)
        }
    }
}

struct TableRowBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.025))
            )
    }
}

func tableCell(label: String, color: Color, weight: Font.Weight = .regular, width: CGFloat? = nil) -> some View {
    Text(label)
        .font(Theme.mono(10.5, weight))
        .foregroundColor(color)
        .lineLimit(1)
        .truncationMode(.middle)
        .frame(width: width, alignment: .leading)
}

struct EmptyStateView: View {
    let text: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 22))
                .foregroundStyle(Theme.accentGradient)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(Theme.textFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
