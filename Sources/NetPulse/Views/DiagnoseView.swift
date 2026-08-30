import SwiftUI

/// 诊断页：输入网址（回车即测、记住最近地址）→ 五段耗时分解 + DNS 对比 + 综合结论
struct DiagnoseView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var l10n = L10n.shared
    @State private var urlText = ""
    @AppStorage("netpulse.lastDiagURL") private var lastDiagURL = "https://www.apple.com"
    @AppStorage("netpulse.recentDiagURLs") private var recentDiagURLs = ""

    private let quickPicks = ["https://www.apple.com", "https://www.baidu.com", "https://www.github.com"]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                inputCard
                if let timing = model.lastTiming {
                    resultCards(timing)
                } else if !model.diagnosing {
                    placeholder
                }
                if model.tracingRoute || model.routeTrace != nil {
                    routeCard
                }
                footnoteCard
            }
            .padding(.top, 16)
        }
        .onAppear {
            if urlText.isEmpty { urlText = lastDiagURL }
        }
    }

    // MARK: 最近地址列表

    private var recentList: [String] {
        recentDiagURLs.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    private func remember(_ url: String) {
        lastDiagURL = url
        var list = recentList.filter { $0 != url }
        list.insert(url, at: 0)
        if list.count > 5 { list = Array(list.prefix(5)) }
        recentDiagURLs = list.joined(separator: "\n")
    }

    // MARK: 输入

    private var inputCard: some View {
        NeonCard(title: L10n.t("dg.title"), systemImage: "stethoscope") {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "globe")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.cyan)
                        TextField(L10n.t("dg.placeholder"), text: $urlText)
                            .textFieldStyle(.plain)
                            .font(Theme.mono(12.5))
                            .onSubmit { startIfPossible() }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8))

                    Button {
                        startIfPossible()
                    } label: {
                        HStack(spacing: 7) {
                            if model.diagnosing || model.tracingRoute {
                                ProgressView().controlSize(.small).tint(.black)
                            } else {
                                Image(systemName: "waveform.path.ecg")
                            }
                            Text(L10n.t((model.diagnosing || model.tracingRoute) ? "dg.going" : "dg.go"))
                        }
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(.black.opacity(0.85))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Theme.cyan))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.diagnosing || model.tracingRoute || urlText.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                HStack(spacing: 6) {
                    Text(L10n.t("dg.quick"))
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textFaint)
                    ForEach(quickPicks, id: \.self) { u in
                        chip(u, isHistory: false)
                    }
                    let recents = recentList.filter { !quickPicks.contains($0) }
                    if !recents.isEmpty {
                        Text(L10n.t("dg.history"))
                            .font(.system(size: 10))
                            .foregroundColor(Theme.textFaint)
                            .padding(.leading, 6)
                        ForEach(recents, id: \.self) { u in
                            chip(u, isHistory: true)
                        }
                    }
                    Spacer()
                    Text(L10n.t("dg.enter.hint"))
                        .font(.system(size: 9))
                        .foregroundColor(Theme.textFaint.opacity(0.7))
                }
            }
        }
    }

    private func chip(_ url: String, isHistory: Bool) -> some View {
        Button {
            urlText = url
            startIfPossible()
        } label: {
            HStack(spacing: 3) {
                if isHistory {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 7.5))
                }
                Text(url.replacingOccurrences(of: "https://", with: ""))
            }
            .font(Theme.mono(9.5))
            .foregroundColor(isHistory ? Theme.purple.opacity(0.95) : Theme.cyan.opacity(0.9))
            .lineLimit(1)
        }
        .buttonStyle(.link)
    }

    private func startIfPossible() {
        let trimmed = urlText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !model.diagnosing, !model.tracingRoute else { return }
        remember(trimmed)
        model.lastTiming = nil
        model.dnsResults = []
        model.routeTrace = nil
        Task {
            model.diagnosing = true
            guard let coordinator = model.coordinator else {
                model.diagnosing = false
                return
            }
            async let route: Void = coordinator.runRouteTrace(target: trimmed)
            await coordinator.runDiagnosis(url: trimmed)
            model.diagnosing = false
            await route
        }
    }

    // MARK: 路径探测

    private var routeCard: some View {
        NeonCard(title: L10n.t("dg.route.title"), systemImage: "point.3.connected.trianglepath.dotted") {
            if model.tracingRoute {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Theme.cyan)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.t("dg.route.running"))
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(Theme.textPrimary)
                        Text(L10n.t("dg.route.wait"))
                            .font(.system(size: 10))
                            .foregroundColor(Theme.textFaint)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            } else if let trace = model.routeTrace {
                routeResult(trace)
            }
        }
    }

    private func routeResult(_ trace: RouteTraceResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: routeStatusIcon(trace))
                    .foregroundColor(routeStatusColor(trace))
                Text(routeStatusText(trace))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(routeStatusColor(trace))
                Spacer()
                routeMetaPill(trace.method.rawValue)
                routeMetaPill(L10n.tf("dg.route.hops", trace.hops.count))
                routeMetaPill(String(format: "%.1f s", trace.duration))
            }

            if trace.failure == nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(Array(trace.hops.enumerated()), id: \.element.id) { offset, hop in
                            if offset > 0 {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(Theme.textFaint)
                            }
                            routeHop(hop)
                        }
                    }
                    .padding(.vertical, 2)
                }

                VStack(alignment: .leading, spacing: 5) {
                    if !model.overview.vpnActive.isEmpty && !isLoopback(trace) {
                        routeNote(icon: "lock.shield", text: L10n.t("dg.route.vpn"), color: Theme.purple)
                    }
                    routeNote(icon: "info.circle", text: L10n.t("dg.route.note"), color: Theme.textFaint)
                }
            }
        }
    }

    private func routeHop(_ hop: RouteHop) -> some View {
        let color = routeHopColor(hop)
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(L10n.tf("dg.route.hop", hop.index))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(color)
                Spacer()
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
            }
            Text(hop.address ?? L10n.t("dg.route.no.reply"))
                .font(Theme.mono(10.5, .medium))
                .foregroundColor(hop.responded ? Theme.textPrimary : Theme.textFaint)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 4) {
                Text(hop.latencyMs.map { String(format: "%.1f ms", $0) } ?? L10n.t("dash"))
                    .font(Theme.mono(9.5))
                    .foregroundColor(color.opacity(0.9))
                if let annotation = hop.annotation {
                    Text(annotation)
                        .font(Theme.mono(8.5, .bold))
                        .foregroundColor(Theme.red)
                }
            }
        }
        .padding(9)
        .frame(width: 122, height: 68, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.panelRaised.opacity(0.72)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(color.opacity(0.24), lineWidth: 0.8))
    }

    private func routeMetaPill(_ text: String) -> some View {
        Text(text)
            .font(Theme.mono(9.5, .medium))
            .foregroundColor(Theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.045)))
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.8))
    }

    private func routeNote(icon: String, text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundColor(color)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 9.5))
                .foregroundColor(Theme.textFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func routeHopColor(_ hop: RouteHop) -> Color {
        guard let milliseconds = hop.latencyMs else { return Theme.textFaint }
        if hop.annotation != nil { return Theme.red }
        if milliseconds < 50 { return Theme.green }
        if milliseconds < 150 { return Theme.cyan }
        if milliseconds < 300 { return Theme.yellow }
        return Theme.red
    }

    private func routeStatusText(_ trace: RouteTraceResult) -> String {
        if let failure = trace.failure {
            switch failure {
            case .invalidTarget: return L10n.t("dg.route.invalid")
            case .unavailable: return L10n.t("dg.route.unavailable")
            case .noRoute: return L10n.t("dg.route.failed")
            }
        }
        return L10n.t(trace.reachedDestination ? "dg.route.reached" : "dg.route.partial")
    }

    private func routeStatusIcon(_ trace: RouteTraceResult) -> String {
        if trace.failure != nil { return "exclamationmark.triangle.fill" }
        return trace.reachedDestination ? "checkmark.circle.fill" : "arrow.triangle.branch"
    }

    private func routeStatusColor(_ trace: RouteTraceResult) -> Color {
        if trace.failure != nil { return Theme.red }
        return trace.reachedDestination ? Theme.green : Theme.cyan
    }

    private func isLoopback(_ trace: RouteTraceResult) -> Bool {
        let address = trace.resolvedAddress ?? trace.target
        return address == "::1" || address.hasPrefix("127.")
    }

    private var placeholder: some View {
        NeonCard(title: L10n.t("dg.result"), systemImage: "chart.bar.doc.horizontal") {
            VStack(spacing: 10) {
                Image(systemName: "cross.case")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.accentGradient)
                Text(L10n.t("dg.placeholder.title"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                Text(L10n.t("dg.placeholder.l1"))
                    .font(.system(size: 10.5))
                    .foregroundColor(Theme.textFaint)
                Text(L10n.t("dg.placeholder.l2"))
                    .font(.system(size: 10.5))
                    .foregroundColor(Theme.textFaint)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
        }
    }

    // MARK: 结果

    @ViewBuilder
    private func resultCards(_ timing: HttpTimingResult) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(minimum: 380), spacing: 14), GridItem(.flexible(minimum: 380))],
                  spacing: 14) {
            NeonCard(title: L10n.t("dg.timing"), systemImage: "chart.bar.fill") {
                VStack(spacing: 12) {
                    if let err = timing.error {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(Theme.red)
                            Text(err)
                                .font(.system(size: 11.5))
                                .foregroundColor(Theme.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        SegmentBar(phases: timing.phases)
                        HStack(spacing: 10) {
                            StatTile(title: L10n.t("dg.total"), value: Fmt.ms(timing.total * 1000),
                                     color: timing.total < 1 ? Theme.green : (timing.total < 3 ? Theme.yellow : Theme.red))
                            StatTile(title: L10n.t("dg.http"), value: timing.httpStatus.map(String.init) ?? L10n.t("dash"),
                                     color: (timing.httpStatus ?? 500) < 400 ? Theme.green : Theme.red)
                            StatTile(title: L10n.t("dg.bytes"), value: Fmt.bytes(Double(timing.bytes)),
                                     color: Theme.textPrimary)
                        }
                        phaseRows(timing)
                        bottleneckCard(timing)
                    }
                }
            }

            NeonCard(title: L10n.t("dg.dnscmp"), systemImage: "questionmark.bubble") {
                VStack(spacing: 8) {
                    if model.dnsResults.isEmpty {
                        Text(L10n.t("dg.notmeasured"))
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textFaint)
                            .frame(maxWidth: .infinity, minHeight: 40, alignment: .center)
                    } else {
                        ForEach(model.dnsResults) { r in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 5) {
                                        Text(r.server)
                                            .font(Theme.mono(11, .medium))
                                            .foregroundColor(Theme.textPrimary)
                                        if r.id == fastestDNS?.id {
                                            Image(systemName: "star.fill")
                                                .font(.system(size: 8))
                                                .foregroundColor(Theme.green)
                                        }
                                    }
                                    Text(dnsRole(r))
                                        .font(.system(size: 8.5))
                                        .foregroundColor(Theme.textFaint)
                                }
                                Spacer()
                                if let ms = r.ms {
                                    MetricValue(value: String(format: "%.1f", ms), unit: "ms",
                                                color: ms < 50 ? Theme.green : (ms < 200 ? Theme.yellow : Theme.red),
                                                size: 11)
                                    Text(dnsQuality(ms))
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundColor(ms < 50 ? Theme.green : (ms < 200 ? Theme.yellow : Theme.red))
                                        .frame(width: 68, alignment: .trailing)
                                } else {
                                    Text(r.error ?? L10n.t("dg.failed"))
                                        .font(Theme.mono(10))
                                        .foregroundColor(Theme.red)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Theme.panelRaised.opacity(0.62)))
                        }
                        HStack(alignment: .top, spacing: 7) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(Theme.green)
                            Text(dnsConclusion)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundColor(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.top, 3)
                    }
                }
            }
        }
    }

    private func phaseRows(_ timing: HttpTimingResult) -> some View {
        let total = max(timing.phases.map(\.seconds).reduce(0, +), 0.0001)
        return VStack(spacing: 0) {
            ForEach(timing.phases) { phase in
                let rating = phaseRating(phase, share: phase.seconds / total)
                HStack(spacing: 10) {
                    Text(phase.name)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                        .frame(width: 72, alignment: .leading)
                    GeometryReader { geometry in
                        Capsule()
                            .fill(Theme.hairline)
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(rating.color.opacity(0.72))
                                    .frame(width: max(3, geometry.size.width * CGFloat(phase.seconds / total)))
                            }
                    }
                    .frame(height: 4)
                    MetricValue(value: String(format: "%.0f", phase.seconds * 1000), unit: "ms",
                                color: Theme.textPrimary, size: 10.5)
                        .frame(width: 72, alignment: .trailing)
                    Text(rating.label)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(rating.color)
                        .frame(width: 58, alignment: .trailing)
                }
                .padding(.vertical, 5)
                if phase.id != timing.phases.last?.id { SectionRule() }
            }
        }
    }

    private func phaseRating(_ phase: HttpPhase, share: Double) -> (label: String, color: Color) {
        let milliseconds = phase.seconds * 1000
        let goodLimit: Double
        let warningLimit: Double
        switch phase.name.uppercased() {
        case "DNS", "TCP": goodLimit = 50; warningLimit = 150
        case "TLS": goodLimit = 120; warningLimit = 300
        case "TTFB": goodLimit = 220; warningLimit = 600
        default: goodLimit = 250; warningLimit = 800
        }
        if milliseconds <= goodLimit { return (L10n.t("q.good"), Theme.green) }
        if share >= 0.55 { return (L10n.t("dg.phase.slow"), Theme.yellow) }
        if milliseconds <= warningLimit { return (L10n.t("q.fair"), Theme.cyan) }
        return (L10n.t("dg.phase.slow"), Theme.yellow)
    }

    private var fastestDNS: DnsResult? {
        model.dnsResults.filter { $0.ms != nil }.min { ($0.ms ?? .greatestFiniteMagnitude) < ($1.ms ?? .greatestFiniteMagnitude) }
    }

    private func dnsRole(_ result: DnsResult) -> String {
        if result.server.hasPrefix(L10n.t("dns.system")) { return L10n.t("dg.dns.current") }
        return L10n.t("dg.dns.public")
    }

    private func dnsQuality(_ milliseconds: Double) -> String {
        if milliseconds < 50 { return L10n.t("q.good") }
        if milliseconds < 200 { return L10n.t("q.fair") }
        return L10n.t("q.bad")
    }

    private var dnsConclusion: String {
        guard let fastestDNS else { return L10n.t("dg.notmeasured") }
        if fastestDNS.server.hasPrefix(L10n.t("dns.system")) { return L10n.t("dg.dns.current.fastest") }
        return L10n.tf("dg.dns.switch", fastestDNS.server)
    }

    private func bottleneckCard(_ timing: HttpTimingResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "scope")
                    .foregroundStyle(Theme.accentGradient)
                Text(L10n.t("dg.bottleneck"))
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
            }
            ForEach(timing.verdicts) { v in
                HStack(alignment: .top, spacing: 8) {
                    VerdictBadge(severity: v.severity)
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 1.5) {
                        Text(v.title).font(.system(size: 11.5, weight: .semibold)).foregroundColor(Theme.textPrimary)
                        if !v.detail.isEmpty {
                            Text(v.detail).font(.system(size: 10.5)).foregroundColor(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let s = v.suggestion {
                            Text(L10n.tf("suggestion", s)).font(.system(size: 10.5)).foregroundColor(Theme.cyan.opacity(0.9))
                        }
                    }
                }
                .padding(7)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.03)))
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.cyan.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.cyan.opacity(0.15), lineWidth: 0.8))
    }

    // MARK: 口径

    private var footnoteCard: some View {
        NeonCard(title: L10n.t("dg.caliber"), systemImage: "info.circle") {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.t("dg.f1"))
                Text(L10n.t("dg.f2"))
                Text(L10n.t("dg.f3"))
                Text(L10n.t("dg.f4"))
                Text(L10n.t("dg.f5"))
                Text(L10n.t("dg.f6"))
            }
            .font(.system(size: 10.5))
            .foregroundColor(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
