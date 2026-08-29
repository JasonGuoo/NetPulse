import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var window: NSWindow?
    let model = AppModel()
    private var statusItem: NSStatusItem?
    private var statusTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let lang = ProcessInfo.processInfo.environment["NETPULSE_LANG"],
           let language = AppLanguage(rawValue: lang) {
            L10n.shared.language = language
        }

        // Render a deterministic view to PNG without screen-recording permission.
        if let idx = CommandLine.arguments.firstIndex(of: "--selftest-png"),
           CommandLine.arguments.count > idx + 1 {
            let path = CommandLine.arguments[idx + 1]
            let tabName = CommandLine.arguments.count > idx + 2
                ? CommandLine.arguments[idx + 2]
                : ContentView.Tab.overview.rawValue
            let tab = ContentView.Tab.allCases.first { $0.rawValue == tabName || $0.title == tabName } ?? .overview
            Self.renderSelftestPNG(to: path, tab: tab)
            exit(0)
        }

        // 开发用：真实采集链路自检（无 UI）
        if CommandLine.arguments.contains("--probe") {
            Task {
                await Self.runProbe()
                exit(0)
            }
            return
        }

        // 打包用：生成 iconset（make-app.sh 调用 iconutil 转 icns）
        if let idx = CommandLine.arguments.firstIndex(of: "--make-icon"),
           CommandLine.arguments.count > idx + 1 {
            Self.makeIconset(at: CommandLine.arguments[idx + 1])
            exit(0)
        }

        installAppIcon()
        installStatusItem()

        let contentView = ContentView().environmentObject(model)
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.title = "NetPulse"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.backgroundColor = NSColor(Theme.bgTop)
        w.isOpaque = false
        w.hasShadow = true
        w.center()
        w.minSize = NSSize(width: 1060, height: 700)
        w.contentView = NSHostingView(rootView: contentView)
        w.makeKeyAndOrderFront(nil)
        window = w

        NSApp.activate(ignoringOtherApps: true)
        model.coordinator = CoreCoordinator(model: model)
        model.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { openMainWindow() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusTimer?.invalidate()
        model.stop()
    }

    // MARK: - Menu bar

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: "NetPulse")
        item.button?.imagePosition = .imageLeading
        item.menu = NSMenu()
        item.menu?.delegate = self
        statusItem = item
        refreshStatusMenu()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refreshStatusMenu()
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshStatusMenu()
    }

    private func refreshStatusMenu() {
        guard let statusItem, let menu = statusItem.menu else { return }
        let signal = model.wifi.rssi.map { "\($0) dBm" } ?? "—"
        statusItem.button?.title = "  \(signal)"
        statusItem.button?.contentTintColor = model.wifi.connected ? NSColor(Theme.green) : NSColor.secondaryLabelColor

        menu.removeAllItems()
        let running = NSMenuItem(title: "NetPulse \(L10n.t("menu.running"))", action: nil, keyEquivalent: "")
        running.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)
        running.isEnabled = false
        menu.addItem(running)
        menu.addItem(.separator())
        addMetricItem(menu, symbol: "wifi", title: L10n.t("tile.signal"), value: signal)
        addMetricItem(menu, symbol: "arrow.left.and.right", title: L10n.t("tile.txrate"), value: model.wifi.txRate.map { Fmt.mbps($0) } ?? "—")
        addMetricItem(menu, symbol: "clock", title: L10n.t("ov.gateway"), value: model.gatewayPing?.last.map(Fmt.ms) ?? "—")
        addMetricItem(menu, symbol: "network", title: "DNS", value: model.dnsPing?.last.map(Fmt.ms) ?? "—")
        addMetricItem(menu, symbol: "checkmark.shield", title: L10n.t("menu.network.status"), value: QualityForScore.label(model.healthScore))
        menu.addItem(.separator())

        let open = NSMenuItem(title: L10n.t("menu.open"), action: #selector(openMainWindow), keyEquivalent: "")
        open.target = self
        open.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        menu.addItem(open)
        let refresh = NSMenuItem(title: L10n.t("refresh"), action: #selector(refreshNow), keyEquivalent: "r")
        refresh.target = self
        refresh.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
        menu.addItem(refresh)
        let quit = NSMenuItem(title: L10n.t("menu.quit"), action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        quit.image = NSImage(systemSymbolName: "rectangle.portrait.and.arrow.right", accessibilityDescription: nil)
        menu.addItem(quit)
    }

    private func addMetricItem(_ menu: NSMenu, symbol: String, title: String, value: String) {
        let item = NSMenuItem(title: "\(title)    \(value)", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        item.isEnabled = false
        menu.addItem(item)
    }

    @objc private func openMainWindow() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func refreshNow() {
        Task { await model.coordinator?.refreshAll() }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - App icon

    private func installAppIcon() {
        NSApplication.shared.applicationIconImage = Self.renderIcon(size: 512)
    }

    private static func sourceIcon() -> NSImage? {
        if let url = Bundle.main.url(forResource: "NetPulseIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        if let url = Bundle.module.url(forResource: "NetPulseIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return nil
    }

    static func renderIcon(size: CGFloat) -> NSImage {
        if let source = sourceIcon() {
            let image = NSImage(size: NSSize(width: size, height: size))
            image.lockFocus()
            NSGraphicsContext.current?.imageInterpolation = .high
            source.draw(
                in: NSRect(x: 0, y: 0, width: size, height: size),
                from: NSRect(origin: .zero, size: source.size),
                operation: .copy,
                fraction: 1
            )
            image.unlockFocus()
            return image
        }

        // 资源缺失时使用程序化图标，保证开发构建仍能启动。
        let s = size / 512.0   // 归一化：绘制逻辑按 512 设计
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return image
        }

        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        // 底：深空渐变圆角方块
        ctx.saveGState()
        let bgPath = CGPath(roundedRect: rect.insetBy(dx: 16 * s, dy: 16 * s),
                            cornerWidth: 110 * s, cornerHeight: 110 * s, transform: nil)
        ctx.addPath(bgPath)
        ctx.clip()
        let bgGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                colors: [NSColor(Theme.bgTop).cgColor, NSColor(Theme.bgBottom).cgColor] as CFArray,
                                locations: [0, 1])!
        ctx.drawLinearGradient(bgGrad, start: .zero, end: CGPoint(x: size, y: size), options: [])
        // 微光网格
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.04).cgColor)
        ctx.setLineWidth(2 * s)
        var i = 64.0 * s
        while i < size {
            ctx.move(to: CGPoint(x: i, y: 0)); ctx.addLine(to: CGPoint(x: i, y: size))
            ctx.move(to: CGPoint(x: 0, y: i)); ctx.addLine(to: CGPoint(x: size, y: i))
            i += 64.0 * s
        }
        ctx.strokePath()
        ctx.restoreGState()

        // 三道霓虹 WiFi 弧线
        let center = CGPoint(x: size / 2, y: size / 2 - 50 * s)
        let colors = [NSColor(Theme.cyan).cgColor, NSColor(Theme.purple).cgColor]
        for radius in [70.0, 130.0, 190.0] {
            let r = CGFloat(radius) * s
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: colors as CFArray, locations: [0, 1])!
            ctx.saveGState()
            let arc = CGMutablePath()
            arc.addArc(center: center, radius: r,
                       startAngle: .pi * 0.25, endAngle: .pi * 0.75, clockwise: false)
            ctx.addPath(arc)
            // 辉光
            ctx.setLineCap(.round)
            ctx.setLineWidth(22 * s)
            ctx.replacePathWithStrokedPath()
            ctx.clip()
            ctx.drawLinearGradient(grad,
                                   start: CGPoint(x: center.x - r, y: 0),
                                   end: CGPoint(x: center.x + r, y: 0), options: [])
            ctx.restoreGState()
            // 主线
            ctx.saveGState()
            ctx.addPath(arc)
            ctx.setLineCap(.round)
            ctx.setLineWidth(11 * s)
            ctx.replacePathWithStrokedPath()
            ctx.clip()
            ctx.drawLinearGradient(grad,
                                   start: CGPoint(x: center.x - r, y: 0),
                                   end: CGPoint(x: center.x + r, y: 0), options: [])
            ctx.restoreGState()
        }
        // 中心点
        let dotRect = CGRect(x: center.x - 13 * s, y: center.y - 13 * s, width: 26 * s, height: 26 * s)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 26 * s,
                      color: NSColor(Theme.cyan).withAlphaComponent(0.9).cgColor)
        ctx.setFillColor(NSColor(Theme.cyan).cgColor)
        ctx.fillEllipse(in: dotRect)
        ctx.restoreGState()

        image.unlockFocus()
        return image
    }

    /// 生成标准 iconset 目录（16/32/.../1024 及 @2x），供 iconutil 转 icns
    static func makeIconset(at dirPath: String) {
        let dir = URL(fileURLWithPath: dirPath)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let specs: [(name: String, px: Int)] = [
            ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
        ]
        for spec in specs {
            let img = renderIcon(size: CGFloat(spec.px))
            guard let tiff = img.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { continue }
            try? png.write(to: dir.appendingPathComponent(spec.name))
        }
    }

    // MARK: - 自检渲染

    static func renderSelftestPNG(to path: String, tab: ContentView.Tab = .overview) {
        let model = AppModel()
        model.wifi = Self.demoWifi
        model.overview = Self.demoOverview
        model.pingTargets = Self.demoPings
        model.neighbors = Self.demoNeighbors
        model.processTraffic = Self.demoProcesses
        model.connections = Self.demoConnections
        model.rateHistory = (0..<40).map { index in
            let wave = 0.55 + 0.32 * sin(Double(index) * 0.72) + 0.12 * cos(Double(index) * 1.51)
            return (in: max(25_000, 780_000 * wave), out: max(3_000, 58_000 * (0.72 + 0.24 * cos(Double(index) * 0.83))))
        }
        model.totalRateIn = Self.demoProcesses.map(\.rateIn).reduce(0, +)
        model.totalRateOut = Self.demoProcesses.map(\.rateOut).reduce(0, +)
        model.wifi.rssiHistory = (0..<40).map { -51.5 + 1.7 * sin(Double($0) * 0.58) }
        model.wifi.snrHistory = model.wifi.rssiHistory.map { $0 + 92 }
        model.wifi.txRateHistory = (0..<40).map { 1330 + 78 * sin(Double($0) * 0.42) }
        for (processIndex, process) in Self.demoProcesses.enumerated() {
            model.processRateHistory[process.id] = (0..<36).map { sample in
                let factor = 0.62 + 0.25 * sin(Double(sample) * (0.44 + Double(processIndex) * 0.08))
                return max(0, (process.rateIn + process.rateOut) * factor)
            }
        }
        model.dnsResults = [
            DnsResult(server: L10n.t("dns.system"), ms: 19),
            DnsResult(server: "1.1.1.1", ms: 24),
            DnsResult(server: "8.8.8.8", ms: 26),
        ]
        model.verdicts = [
            Verdict(
                severity: .good,
                title: L10n.t("vd.wifi.ok"),
                detail: L10n.tf("vd.wifi.ok.detail", "-51 dBm", 41, "0.0%")
            ),
            Verdict(
                severity: .warn,
                title: L10n.t("vd.isp"),
                detail: L10n.tf("vd.isp.detail", "Google", "0.0%", "196.6 ms"),
                suggestion: L10n.t("vd.isp.tip")
            ),
        ]
        if ProcessInfo.processInfo.environment["NETPULSE_EMPTY_STATE"] != "1" {
            model.lastSpeed = SpeedResult(
                downloadMbps: 423.6,
                uploadMbps: 0,
                bytes: 52_428_800,
                seconds: 1.0,
                measuredAt: Date(),
                errorNote: nil
            )
            model.lastTiming = HttpTimingResult(
                url: "https://www.apple.com",
                phases: [
                    HttpPhase(name: L10n.t("phase.dns"), seconds: 0.025, colorIndex: 0),
                    HttpPhase(name: L10n.t("phase.tcp"), seconds: 0.010, colorIndex: 1),
                    HttpPhase(name: L10n.t("phase.tls"), seconds: 0.148, colorIndex: 2),
                    HttpPhase(name: L10n.t("phase.ttfb"), seconds: 0.018, colorIndex: 3),
                    HttpPhase(name: L10n.t("phase.download"), seconds: 0.0068, colorIndex: 4),
                ],
                total: 0.2078,
                httpStatus: 200,
                bytes: 186_240,
                verdicts: [
                    Verdict(
                        severity: .warn,
                        title: L10n.tf("vd.bn.tls", "148 ms"),
                        detail: L10n.t("vd.bn.tls.detail"),
                        suggestion: L10n.t("vd.bn.tls.tip")
                    )
                ]
            )
        }
        let host = NSHostingView(rootView: ContentView(initialTab: tab).environmentObject(model))
        host.setFrameSize(NSSize(width: 1180, height: 760))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }

    static let demoPings: [PingTargetState] = {
        var gw = PingTargetState(label: L10n.t("pk.gateway"), host: "192.168.50.1")
        gw.history = [3.9, 4.2, 4.0, 4.4, 4.1, 4.3, 4.0, 4.2]
        gw.sent = 30; gw.received = 30; gw.last = 4.2; gw.avg = 4.15
        var dns = PingTargetState(label: "DNS 1.1.1.1", host: "1.1.1.1")
        dns.history = [11, 12, 10, 13, 12, 11, 12, 12]
        dns.sent = 30; dns.received = 29; dns.last = 12; dns.avg = 11.6
        var google = PingTargetState(label: "Google", host: "8.8.8.8")
        google.history = [190, 210, 195, 188, 205, 192, 199, 194]
        google.sent = 30; google.received = 30; google.last = 194; google.avg = 196.6
        return [gw, dns, PingTargetState(label: "Cloudflare", host: ""), google]
    }()

    static let demoNeighbors: [NeighborNetwork] = [
        NeighborNetwork(ssid: "Apartment-2G", channel: 6, band: "2.4GHz", widthMHz: 20, rssi: -70, security: "WPA2 Personal", phyMode: "802.11n"),
        NeighborNetwork(ssid: "Guest-WiFi", channel: 6, band: "2.4GHz", widthMHz: 20, rssi: -78, security: "WPA2 Personal", phyMode: "802.11n"),
        NeighborNetwork(ssid: "Coffee-Shop", channel: 1, band: "2.4GHz", widthMHz: 40, rssi: -80, security: "WPA2 Personal", phyMode: "802.11n"),
        NeighborNetwork(ssid: "HomeLab", channel: 157, band: "5GHz", widthMHz: 80, rssi: -58, security: "WPA2 Personal", phyMode: "802.11ax", isOwnRouter: true),
        NeighborNetwork(ssid: "Office-5G", channel: 44, band: "5GHz", widthMHz: 80, rssi: -62, security: "WPA2 Personal", phyMode: "802.11ax"),
    ]

    static let demoProcesses: [ProcessTraffic] = [
        ProcessTraffic(name: "Google Chrome Helper", pid: 71157, rateIn: 620_000, rateOut: 42_000, totalIn: 1_836_669_169, totalOut: 1_908_214, connections: 43),
        ProcessTraffic(name: "WeChat", pid: 88471, rateIn: 96_000, rateOut: 31_000, totalIn: 2_303_543, totalOut: 2_245_321, connections: 8),
        ProcessTraffic(name: "cloudflared", pid: 416, rateIn: 41_000, rateOut: 63_000, totalIn: 5_102_563, totalOut: 16_321_298, connections: 5),
        ProcessTraffic(name: "GitHub Desktop", pid: 26482, rateIn: 12_000, rateOut: 3_100, totalIn: 4_095, totalOut: 3_070, connections: 3),
    ]

    static let demoConnections: [ConnectionRow] = [
        ConnectionRow(process: "Google Chrome Helper", pid: 71157, proto: "TCP", family: "IPv4",
                      local: "192.168.50.42:64017", remote: "162.159.61.3:443", state: "ESTABLISHED",
                      bytesIn: 812_345, bytesOut: 42_000, rateIn: 310_000, rateOut: 12_000),
        ConnectionRow(process: "Google Chrome Helper", pid: 71157, proto: "TCP", family: "IPv4",
                      local: "192.168.50.42:58112", remote: "17.253.144.10:443", state: "ESTABLISHED",
                      bytesIn: 120_000, bytesOut: 9_000, rateIn: 64_000, rateOut: 2_100),
        ConnectionRow(process: "WeChat", pid: 88471, proto: "TCP", family: "IPv4",
                      local: "192.168.50.42:52301", remote: "43.138.12.66:443", state: "ESTABLISHED",
                      bytesIn: 96_000, bytesOut: 31_000, rateIn: 96_000, rateOut: 31_000),
        ConnectionRow(process: "cloudflared", pid: 416, proto: "TCP", family: "IPv4",
                      local: "192.168.50.42:51988", remote: "198.41.200.13:7844", state: "ESTABLISHED",
                      bytesIn: 41_000, bytesOut: 63_000, rateIn: 41_000, rateOut: 63_000),
    ]

    // MARK: - 采集链路自检

    static func runProbe() async {
        let model = AppModel()
        let coordinator = CoreCoordinator(model: model)
        model.coordinator = coordinator
        model.start()

        let deadline = Date().addingTimeInterval(14)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        // 可选：端到端诊断 + 测速
        if CommandLine.arguments.contains("--with-diagnosis") {
            await coordinator.runDiagnosis(url: "https://www.apple.com")
        }
        if CommandLine.arguments.contains("--with-speed") {
            await coordinator.runSpeedTest()
        }

        var lines: [String] = []
        lines.append("=== WiFi 链路 ===")
        lines.append("connected=\(model.wifi.connected) iface=\(model.wifi.interface ?? "-") ssid=\(model.wifi.ssid ?? "nil")")
        lines.append("rssi=\(model.wifi.rssi.map(String.init) ?? "-") noise=\(model.wifi.noise.map(String.init) ?? "-") snr=\(model.wifi.snr)")
        lines.append("channel=\(model.wifi.channel.map(String.init) ?? "-") band=\(model.wifi.band ?? "-") width=\(model.wifi.channelWidthMHz.map(String.init) ?? "-")")
        lines.append("txRate=\(model.wifi.txRate.map { String(format: "%.0f", $0) } ?? "-") phy=\(model.wifi.phyMode ?? "-") mcs=\(model.wifi.mcs.map(String.init) ?? "-") country=\(model.wifi.country ?? "-")")
        lines.append("rssiHistory=\(model.wifi.rssiHistory.count) samples")
        lines.append("=== 网络概况 ===")
        lines.append("gateway=\(model.overview.gateway ?? "-") ip=\(model.overview.ipv4 ?? "-")/\(model.overview.mask ?? "-")")
        lines.append("dns=\(model.overview.dnsServers) source=\(model.overview.dnsSource ?? "-")")
        lines.append("proxy=\(model.overview.proxies.count) vpn=\(model.overview.vpnActive)")
        lines.append("publicIP=\(model.overview.publicIP ?? "-") loc=\(model.overview.publicIPLocation ?? "-") org=\(model.overview.publicIPOrg ?? "-") colo=\(model.overview.colo ?? "-")")
        lines.append("=== 连接 ===")
        lines.append("connections=\(model.connections.count) listening=\(model.listenRows.count) processes=\(model.processTraffic.count)")
        lines.append("totalRate ↓\(Fmt.rate(model.totalRateIn)) ↑\(Fmt.rate(model.totalRateOut)) history=\(model.rateHistory.count)")
        if let top = model.processTraffic.first {
            lines.append("topProcess=\(top.name) ↓\(Fmt.rate(top.rateIn)) ↑\(Fmt.rate(top.rateOut)) conns=\(top.connections)")
        }
        if let c = model.connections.first(where: { $0.rateIn + $0.rateOut > 0 }) {
            lines.append("activeFlow=\(c.process) \(c.local)->\(c.remote) ↓\(Fmt.rate(c.rateIn)) ↑\(Fmt.rate(c.rateOut))")
        }
        lines.append("=== Ping ===")
        for p in model.pingTargets {
            lines.append("\(p.label)(\(p.host)): sent=\(p.sent) recv=\(p.received) loss=\(String(format: "%.1f%%", p.lossPct)) avg=\(p.avg.map { String(format: "%.1fms", $0) } ?? "-") jitter=\(String(format: "%.1f", p.jitter))")
        }
        lines.append("retrans/min=\(String(format: "%.1f", model.tcpRetransPerMin))")
        lines.append("=== 邻居/结论 ===")
        lines.append("neighbors=\(model.neighbors.count) coChannel=\(model.coChannelNeighbors)")
        for v in model.verdicts {
            lines.append("[\(v.severity.label)] \(v.title)")
        }
        if let t = model.lastTiming {
            lines.append("=== 诊断（\(t.url)）===")
            if let err = t.error {
                lines.append("error=\(err)")
            } else {
                lines.append("status=\(t.httpStatus.map(String.init) ?? "-") total=\(String(format: "%.2fs", t.total)) bytes=\(t.bytes)")
                for p in t.phases {
                    lines.append("  \(p.name): \(String(format: "%.0fms", p.seconds * 1000))")
                }
                for d in model.dnsResults {
                    lines.append("  DNS \(d.server): \(d.ms.map { String(format: "%.0fms", $0) } ?? d.error ?? "fail")")
                }
                for v in t.verdicts {
                    lines.append("  [\(v.severity.label)] \(v.title)")
                }
            }
        }
        if model.lastSpeed.measuredAt != nil {
            lines.append("=== 测速 ===")
            lines.append("download=\(String(format: "%.1f Mbps", model.lastSpeed.downloadMbps)) bytes=\(Fmt.bytes(Double(model.lastSpeed.bytes))) secs=\(String(format: "%.1f", model.lastSpeed.seconds))")
            if let note = model.lastSpeed.errorNote {
                lines.append("note=\(note)")
            }
        }
        lines.append("healthScore=\(model.healthScore)")
        print(lines.joined(separator: "\n"))
    }

    static let demoWifi: WifiLinkState = {
        var w = WifiLinkState()
        w.interface = "en0"
        w.ssid = "HomeLab"
        w.channel = 48
        w.band = "5GHz"
        w.channelWidthMHz = 160
        w.rssi = -51
        w.noise = -92
        w.txRate = 1441
        w.security = "WPA2 Personal"
        w.phyMode = "802.11ax"
        w.mcs = 6
        w.country = "CN"
        w.connected = true
        return w
    }()

    static let demoOverview: NetOverviewState = {
        var o = NetOverviewState()
        o.gateway = "192.168.50.1"
        o.dnsServers = ["1.1.1.1"]
        o.dnsSource = "manual"
        o.ipv4 = "192.168.50.42"
        o.mask = "255.255.255.0"
        o.publicIP = "203.0.113.42"
        o.publicIPLocation = "Sample Region"
        o.colo = "HKG"
        o.updated = Date()
        return o
    }()
}

enum QualityForScore {
    static func label(_ score: Int) -> String {
        if score >= 85 { return L10n.t("q.good") }
        if score >= 70 { return L10n.t("q.fair") }
        if score >= 50 { return L10n.t("q.poor") }
        return L10n.t("q.bad")
    }
}

@main
struct NetPulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
