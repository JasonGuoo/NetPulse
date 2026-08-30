import XCTest
@testable import HopGauge

/// 解析器单元测试（样本取自 macOS 15.6 实机输出）
final class ParserTests: XCTestCase {

    override func setUp() {
        super.setUp()
        L10n.shared.language = .zh
    }

    // MARK: - lsof -F pcPnT

    static let lsofFixture = """
    p450
    crapportd
    f8
    PTCP
    n*:64499
    TST=LISTEN
    TQR=0
    TQS=0
    f9
    PTCP
    n*:64499
    TST=LISTEN
    TQR=0
    TQS=0
    f15
    PTCP
    n192.168.2.106:64499->192.168.2.108:49155
    TST=ESTABLISHED
    TQR=0
    TQS=0
    f16
    PUDP
    n*:3722
    f19
    PTCP
    n192.168.2.106:64499->192.168.2.105:57131
    TST=ESTABLISHED
    TQR=0
    TQS=0
    p489
    cidentityservicesd
    f23
    PTCP
    n[fe80:17::8563:f844:cbb9:8fe6]:1024->[fe80:17::e1da:de53:9c1e:a1cd]:1024
    TST=ESTABLISHED
    """

    func testParseLsof() {
        let rows = ConnectionMonitor.parseLsofF(Self.lsofFixture)
        XCTAssertEqual(rows.count, 6, "应解析出 6 条（5 TCP + 1 UDP，含 IPv6）")

        let established = rows.filter { $0.state == "ESTABLISHED" }
        XCTAssertEqual(established.count, 3)

        let first = rows[0]
        XCTAssertEqual(first.pid, 450)
        XCTAssertEqual(first.command, "rapportd")
        XCTAssertEqual(first.proto, "TCP")
        XCTAssertEqual(first.local, "*:64499")
        XCTAssertEqual(first.state, "LISTEN")

        let est = rows[2]
        XCTAssertEqual(est.local, "192.168.2.106:64499")
        XCTAssertEqual(est.remote, "192.168.2.108:49155")

        let udp = rows.first { $0.proto == "UDP" }!
        XCTAssertEqual(udp.state, "")
        XCTAssertEqual(udp.local, "*:3722")
        XCTAssertEqual(udp.remote, "")

        let v6 = rows.last!
        XCTAssertEqual(v6.family, "IPv6")
        XCTAssertEqual(v6.command, "identityservicesd")
    }

    // MARK: - nettop CSV

    static let nettopFixture = """
    ,bytes_in,bytes_out,
    kernel_task.0,692,1024,
    tcp4 127.0.0.1:59993<->127.0.0.1:51442,692,1024,
    udp4 *:*<->*:*,,,
    rapportd.450,392192,492953,
    tcp4 192.168.2.106:64499<->192.168.2.113:54568,21637,2642,
    tcp4 192.168.2.106:64499<->192.168.2.109:60888,46104,61576,
    Google Chrome H.71157,1836669169,1908214,
    """

    func testParseNettop() {
        let snap = ConnectionMonitor.parseNettop(Self.nettopFixture)

        XCTAssertEqual(snap.processTotals.count, 3)
        XCTAssertEqual(snap.processTotals[450]?.name, "rapportd")
        XCTAssertEqual(snap.processTotals[450]?.bytesIn, 392192)
        XCTAssertEqual(snap.processTotals[450]?.bytesOut, 492953)
        XCTAssertEqual(snap.processTotals[71157]?.bytesIn, 1836669169)

        // 流 key 与 lsof 命名对齐（-> 而非 <->）
        let key = "192.168.2.106:64499->192.168.2.113:54568"
        XCTAssertEqual(snap.flows[key]?.bytesIn, 21637)
        XCTAssertEqual(snap.flows[key]?.bytesOut, 2642)
        XCTAssertEqual(snap.flows[key]?.pid, 450)

        // 空 UDP 行容错
        XCTAssertEqual(snap.flows["*:*->*:*"]?.bytesIn, 0)
    }

    // MARK: - system_profiler

    func testParseChannel() {
        let c1 = WifiInfoCollector.parseChannel("6 (2GHz, 20MHz)")
        XCTAssertEqual(c1?.channel, 6)
        XCTAssertEqual(c1?.band, "2.4GHz")
        XCTAssertEqual(c1?.width, 20)

        let c2 = WifiInfoCollector.parseChannel("48 (5GHz, 160MHz)")
        XCTAssertEqual(c2?.channel, 48)
        XCTAssertEqual(c2?.band, "5GHz")
        XCTAssertEqual(c2?.width, 160)

        XCTAssertNil(WifiInfoCollector.parseChannel("invalid"))
    }

    func testParseSignal() {
        XCTAssertEqual(WifiInfoCollector.parseSignal("-45 dBm / -92 dBm"), -45)
        XCTAssertEqual(WifiInfoCollector.parseSignal("-100 dBm / -110 dBm"), -100)
        XCTAssertNil(WifiInfoCollector.parseSignal("n/a"))
    }

    func testParseProfilerJSON() {
        let json = """
        {"SPAirPortDataType":[{"spairport_airport_interfaces":[{"_name":"en0","spairport_airport_other_local_wireless_networks":[
          {"_name":"Apartment-2G","spairport_network_channel":"6 (2GHz, 20MHz)","spairport_network_phymode":"802.11b/g/n/ac/ax","spairport_security_mode":"spairport_security_mode_wpa2_personal"},
          {"_name":"HomeLab","spairport_network_channel":"48 (5GHz, 160MHz)","spairport_network_phymode":"802.11a/n/ac/ax","spairport_signal_noise":"-45 dBm / -92 dBm","spairport_security_mode":"spairport_security_mode_wpa2_personal"}
        ],"spairport_current_network_information":{"_name":"HomeLab","spairport_network_channel":"48 (5GHz, 160MHz)","spairport_network_country_code":"CN","spairport_network_mcs":6,"spairport_network_phymode":"802.11ax","spairport_security_mode":"spairport_security_mode_wpa2_personal"}}]}]}
        """
        let result = WifiInfoCollector.parseProfilerJSON(json)!
        XCTAssertEqual(result.current?.ssid, "HomeLab")
        XCTAssertEqual(result.current?.channel, 48)
        XCTAssertEqual(result.current?.widthMHz, 160)
        XCTAssertEqual(result.current?.mcs, 6)
        XCTAssertEqual(result.current?.country, "CN")
        XCTAssertEqual(result.current?.security, "WPA2 个人")
        // 当前 AP（同 SSID 同信道）被过滤，只剩外部邻居 Apartment-2G
        XCTAssertEqual(result.neighbors.count, 1)
        XCTAssertEqual(result.neighbors[0].ssid, "Apartment-2G")
        XCTAssertEqual(result.neighbors[0].band, "2.4GHz")
    }

    // MARK: - scutil / route / netstat

    func testParsePrimaryNameservers() {
        let dns = """
        DNS configuration

        resolver #1
          nameserver[0] : 1.1.1.1
          nameserver[1] : 8.8.8.8
          flags    : Request A records
          reach    : 0x00000002 (Reachable)

        resolver #2
          domain   : local
          nameserver[0] : 192.168.2.1
        """
        XCTAssertEqual(NetOverviewCollector.parsePrimaryNameservers(dns), ["1.1.1.1", "8.8.8.8"])
    }

    func testParseProxy() {
        let proxy = """
        <dictionary> {
          HTTPEnable : 1
          HTTPProxy : 127.0.0.1
          HTTPPort : 7890
          HTTPSEnable : 1
          HTTPSProxy : 127.0.0.1
          HTTPSPort : 7890
          SOCKSEnable : 0
        }
        """
        let entries = NetOverviewCollector.parseProxy(proxy)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].kind, "HTTP")
        XCTAssertEqual(entries[0].server, "127.0.0.1")
        XCTAssertEqual(entries[0].port, "7890")
    }

    func testParseVPN() {
        let nc = """
        Available network connection services in the current set (*=enabled):
        * 0  IPSec    "CompanyVPN" 
          1  L2TP     "Old VPN"
        """
        XCTAssertEqual(NetOverviewCollector.parseVPN(nc), ["CompanyVPN"])
    }

    func testParseGateway() {
        let route = """
           route to: default
        destination: default
               mask: default
            gateway: 192.168.2.1
          interface: en0
        """
        XCTAssertEqual(regexCapture(#"gateway: (\S+)"#, from: route)?[0], "192.168.2.1")
        XCTAssertEqual(regexCapture(#"interface: (\S+)"#, from: route)?[0], "en0")
    }

    func testParseRetrans() {
        let netstat = """
        tcp:
                1234567 packets sent
                89 data packets (234567 bytes) retransmitted
                0 retransmit timeout
        """
        let caps = regexCapture(#"(\d+) data packet.*?retransmitted"#, from: netstat)
        XCTAssertEqual(caps?[0], "89")
    }

    // MARK: - ping / dig / URL

    func testParsePing() {
        let out = """
        PING 1.1.1.1 (1.1.1.1): 56 data bytes
        64 bytes from 1.1.1.1: icmp_seq=0 ttl=57 time=12.374 ms

        --- 1.1.1.1 ping statistics ---
        1 packets transmitted, 1 packets received, 0.0% packet loss
        """
        let caps = regexCapture(#"time=([0-9.]+) ms"#, from: out)
        XCTAssertEqual(caps?[0], "12.374")
    }

    func testParseDigQueryTime() {
        let dig = """
        ;; Query time: 220 msec
        ;; SERVER: 1.1.1.1#53(1.1.1.1)
        ;; WHEN: Fri Aug 29 20:00:00 CST 2025
        """
        XCTAssertEqual(regexCapture(#"Query time: (\d+) msec"#, from: dig)?[0], "220")
        XCTAssertEqual(regexCapture(#";; SERVER: (\S+)"#, from: dig)?[0], "1.1.1.1#53(1.1.1.1)")
    }

    func testURLNormalize() {
        XCTAssertEqual(HttpTiming.normalize("www.apple.com")?.absoluteString, "https://www.apple.com")
        XCTAssertEqual(HttpTiming.normalize("http://a.b")?.absoluteString, "http://a.b")
        XCTAssertNil(HttpTiming.normalize("  "))
    }

    // MARK: - Diagnoser

    func testDiagnoserGoodLink() {
        var wifi = WifiLinkState()
        wifi.connected = true
        wifi.rssi = -51
        wifi.noise = -92
        var gw = PingTargetState(label: "网关", host: "192.168.2.1")
        gw.sent = 10; gw.received = 10; gw.history = [2, 2.5, 3, 2.2]; gw.avg = 2.4
        var pub = PingTargetState(label: "CF", host: "1.1.1.1")
        pub.sent = 10; pub.received = 10; pub.history = [12, 13, 12.5]; pub.avg = 12.5
        let verdicts = Diagnoser.overviewVerdicts(wifi: wifi, pings: [gw, pub], coChannel: 1,
                                                 dnsSystemMs: 15, publicIP: "1.2.3.4")
        XCTAssertTrue(verdicts.contains { $0.severity == .good && $0.title.contains("正常") })
        XCTAssertFalse(verdicts.contains { $0.severity == .bad })
    }

    func testDiagnoserBadLink() {
        var wifi = WifiLinkState()
        wifi.connected = true
        wifi.rssi = -76
        wifi.noise = -95
        var gw = PingTargetState(label: "网关", host: "192.168.2.1")
        gw.sent = 20; gw.received = 16; gw.history = [45, 60, 38, 120]; gw.avg = 66
        let verdicts = Diagnoser.overviewVerdicts(wifi: wifi, pings: [gw], coChannel: 6,
                                                 dnsSystemMs: nil, publicIP: nil)
        XCTAssertTrue(verdicts.contains { $0.severity == .bad && $0.title.contains("WiFi 链路") })
    }

    func testDiagnoserGatewayIssueIsNotMisattributedToWiFi() {
        var wifi = WifiLinkState()
        wifi.connected = true
        wifi.rssi = -50
        wifi.noise = -95
        var gw = PingTargetState(label: "网关", host: "192.168.2.1")
        gw.sent = 20; gw.received = 10; gw.history = [42, 55]; gw.avg = 48
        let verdicts = Diagnoser.overviewVerdicts(wifi: wifi, pings: [gw], coChannel: 0,
                                                 dnsSystemMs: nil, publicIP: nil)
        XCTAssertTrue(verdicts.contains { $0.severity == .bad && $0.title.contains("网关") })
        XCTAssertFalse(verdicts.contains { $0.title.contains("WiFi 链路质量差") })
    }

    func testDiagnoserDoesNotTreatDNSPingAsInternetPath() {
        var wifi = WifiLinkState()
        wifi.connected = true
        wifi.rssi = -50
        wifi.noise = -95
        var gw = PingTargetState(label: "网关", host: "192.168.2.1")
        gw.sent = 10; gw.received = 10; gw.history = [3, 4, 3]; gw.avg = 3.3
        var dns = PingTargetState(label: "DNS 1.1.1.1", host: "1.1.1.1")
        dns.sent = 10; dns.received = 0
        var publicTarget = PingTargetState(label: "Google", host: "8.8.8.8")
        publicTarget.sent = 10; publicTarget.received = 10; publicTarget.history = [20, 21, 22]; publicTarget.avg = 21
        let verdicts = Diagnoser.overviewVerdicts(wifi: wifi, pings: [gw, dns, publicTarget], coChannel: 0,
                                                 dnsSystemMs: 18, publicIP: "203.0.113.42")
        XCTAssertFalse(verdicts.contains { $0.title.contains("上游") })
        XCTAssertTrue(verdicts.contains { $0.title == L10n.t("vd.inet.ok") })
    }

    func testDiagnoserURLTTFB() {
        var timing = HttpTimingResult(url: "https://x.com")
        timing.total = 3.2
        timing.phases = [
            HttpPhase(name: "DNS", seconds: 0.02, colorIndex: 0),
            HttpPhase(name: "TCP", seconds: 0.05, colorIndex: 1),
            HttpPhase(name: "TLS", seconds: 0.1, colorIndex: 2),
            HttpPhase(name: "首字节", seconds: 2.8, colorIndex: 3),
            HttpPhase(name: "下载", seconds: 0.2, colorIndex: 4),
        ]
        let verdicts = Diagnoser.urlVerdicts(timing: timing, dnsResults: [], wifi: WifiLinkState(), pings: [])
        XCTAssertTrue(verdicts.contains { $0.title.contains("服务器响应慢") })
    }

    // MARK: - 集成：回环 ping

    func testPingLoopback() async {
        let result = await PingMonitor.pingOnce(host: "127.0.0.1")
        XCTAssertTrue(result.success)
        XCTAssertNotNil(result.ms)
    }

    // MARK: - 本地化完整性

    func testL10nCompleteness() {
        // zh 为基准，en/ja/ko 必须覆盖全部键
        let zhKeys = Set(L10n.zh.keys)
        XCTAssertGreaterThan(zhKeys.count, 150, "翻译表应有足量条目")
        for (lang, dict) in [("en", L10n.en), ("ja", L10n.ja), ("ko", L10n.ko)] {
            let missing = zhKeys.subtracting(dict.keys)
            XCTAssertTrue(missing.isEmpty, "\(lang) 缺少键: \(missing.sorted().prefix(10))")
        }
        // 无空值
        for dict in [L10n.zh, L10n.en, L10n.ja, L10n.ko] {
            for (k, v) in dict {
                XCTAssertFalse(v.isEmpty, "键 \(k) 值为空")
            }
        }
    }

    /// 占位符类型/顺序跨语言必须一致（%@ 传 Int 会直接段错误，曾引发线上崩溃）
    func testL10nPlaceholderConsistency() throws {
        func kinds(_ s: String) -> [String] {
            var out: [String] = []
            var it = s.makeIterator()
            while let ch = it.next() {
                guard ch == "%" else { continue }
                var spec = "%"
                loop: while let c = it.next() {
                    spec.append(c)
                    switch c {
                    case "%": out.append("pct"); break loop   // %% 字面百分号
                    case "@": out.append("obj"); break loop
                    case "d", "u", "x", "X", "o", "D", "U", "i":
                        out.append("int"); break loop
                    case "f", "e", "E", "g", "G", "a", "A":
                        out.append("float"); break loop
                    default: break
                    }
                }
            }
            return out
        }

        for (lang, dict) in [("en", L10n.en), ("ja", L10n.ja), ("ko", L10n.ko)] {
            for (key, zhValue) in L10n.zh {
                let other = try XCTUnwrap(dict[key], "\(lang) 缺键 \(key)")
                XCTAssertEqual(kinds(zhValue), kinds(other),
                               "\(key) 占位符不一致: zh=\(zhValue) \(lang)=\(other)")
            }
        }
    }

    func testL10nSwitch() {
        L10n.shared.language = .en
        XCTAssertEqual(L10n.t("tab.overview"), "Overview")
        XCTAssertEqual(L10n.t("lk.your.channel"), "Your channel")
        L10n.shared.language = .ja
        XCTAssertEqual(L10n.t("tab.overview"), "概要")
        L10n.shared.language = .ko
        XCTAssertEqual(L10n.t("tab.overview"), "개요")
        L10n.shared.language = .zh
        XCTAssertEqual(L10n.t("tab.overview"), "概况")
    }

    func testL10nFormat() {
        L10n.shared.language = .zh
        let s = L10n.tf("ch.current.overlap", "48", "160MHz", 2, "A Ch44")
        XCTAssertTrue(s.contains("48") && s.contains("2 个邻居"))
        XCTAssertEqual(L10n.tf("lk.networks", 7), "7 个网络")
    }

    // MARK: - 格式化

    func testFmt() {
        XCTAssertEqual(Fmt.bytes(1536), "1.5 KB")
        XCTAssertEqual(Fmt.rate(2 * 1_048_576), "2.0 MB/s")
        XCTAssertEqual(Fmt.ms(1500), "1.50 s")
        XCTAssertEqual(Fmt.pct(0.5), "0.5%")
    }

    // MARK: - IP 归属

    func testIPProvider() {
        XCTAssertEqual(IPProvider.name(of: "162.159.61.3"), "Cloudflare")
        XCTAssertEqual(IPProvider.name(of: "1.1.1.1"), "Cloudflare")
        XCTAssertEqual(IPProvider.name(of: "17.253.144.10"), "Apple")
        XCTAssertEqual(IPProvider.name(of: "192.168.2.108"), "局域网")
        XCTAssertEqual(IPProvider.name(of: "127.0.0.1"), "本机回环")
        XCTAssertEqual(IPProvider.name(of: "8.8.8.8"), "Google")
        XCTAssertEqual(IPProvider.name(of: "140.82.115.3"), "GitHub")
        XCTAssertEqual(IPProvider.name(of: "223.5.5.5"), "阿里 DNS")
        XCTAssertEqual(IPProvider.name(of: "43.138.1.2"), "腾讯云")
        XCTAssertNil(IPProvider.name(of: "203.0.113.7"))     // 文档保留段，未映射
        XCTAssertEqual(IPProvider.name(of: "fe80::1"), "链路本地")

        let row = ConnectionRow(process: "x", pid: 1, proto: "TCP", family: "IPv4",
                                local: "192.168.2.106:1", remote: "162.159.61.3:443", state: "ESTABLISHED")
        XCTAssertEqual(IPProvider.describe(row), "Cloudflare")
    }

    func testAppBadge() {
        XCTAssertEqual(AppBadgeInfo.of(process: "Google Chrome Helper").label, "Chrome")
        XCTAssertEqual(AppBadgeInfo.of(process: "WeChat").label, "微信")
        XCTAssertEqual(AppBadgeInfo.of(process: "mDNSResponder").label, "系统 DNS")
        XCTAssertEqual(AppBadgeInfo.of(process: "unknownproc").label, "unknownproc")
    }

    // MARK: - 自身 AP 重复 bug（system_profiler 会把当前 AP 也列进邻居）

    func testParseProfilerFiltersSelfAP() {
        // 场景：当前连 HomeLab ch153/5G，邻居列表里也有同 AP 的 ch153
        // 以及同 SSID 的 2.4G 频段（双频合一）
        let json = """
        {"SPAirPortDataType":[{"spairport_airport_interfaces":[{"_name":"en0",
        "spairport_airport_other_local_wireless_networks":[
          {"_name":"HomeLab","spairport_network_channel":"153 (5GHz, 80MHz)","spairport_network_phymode":"802.11ax","spairport_security_mode":"spairport_security_mode_wpa2_personal"},
          {"_name":"HomeLab","spairport_network_channel":"11 (2GHz, 20MHz)","spairport_network_phymode":"802.11n","spairport_security_mode":"spairport_security_mode_wpa2_personal"},
          {"_name":"Apartment-5G","spairport_network_channel":"40 (5GHz, 160MHz)","spairport_network_phymode":"802.11ax","spairport_security_mode":"spairport_security_mode_wpa2_personal"}
        ],"spairport_current_network_information":{"_name":"HomeLab","spairport_network_channel":"153 (5GHz, 80MHz)","spairport_network_country_code":"CN","spairport_network_mcs":6,"spairport_network_phymode":"802.11ax","spairport_security_mode":"spairport_security_mode_wpa2_personal"}}]}]}
        """
        let result = WifiInfoCollector.parseProfilerJSON(json)!
        XCTAssertEqual(result.current?.ssid, "HomeLab")
        XCTAssertEqual(result.current?.channel, 153)

        // 自身 AP（同 SSID 同信道同频段）必须被剔除：只剩 2 条邻居
        XCTAssertEqual(result.neighbors.count, 2, "自身 AP 不应出现在邻居列表")
        XCTAssertFalse(result.neighbors.contains { $0.ssid == "HomeLab" && $0.channel == 153 })
        // 同 SSID 的 2.4G 频段保留并标记为自己的路由器
        let own24 = result.neighbors.first { $0.ssid == "HomeLab" && $0.channel == 11 }
        XCTAssertNotNil(own24)
        XCTAssertEqual(own24?.isOwnRouter, true)
        // 外部网络不标记
        XCTAssertEqual(result.neighbors.first { $0.ssid == "Apartment-5G" }?.isOwnRouter, false)
    }

    func testChannelPlanIgnoresOwnRouter() {
        let neighbors = [
            // 自己路由器的 2.4G 频段，正好与当前 2.4G 网络重叠 —— 不算冲突
            NeighborNetwork(ssid: "mine", channel: 6, band: "2.4GHz", widthMHz: 20, rssi: -40,
                            security: nil, phyMode: nil, isOwnRouter: true),
            NeighborNetwork(ssid: "A", channel: 6, band: "2.4GHz", widthMHz: 20, rssi: -60,
                            security: nil, phyMode: nil, isOwnRouter: false),
        ]
        let a = ChannelPlan.analyze(band: "2.4GHz", neighbors: neighbors, current: (6, 20, "mine"))
        XCTAssertEqual(a.overlapCount, 1, "只算外部邻居 A，不含自己的路由器")
        XCTAssertFalse(a.bars.contains { $0.isOwnRouter && $0.overlapsCurrent })
        // 拥挤度两两计数：当前网络↔外部 A 算 1 对；自己路由器不参与
        XCTAssertEqual(a.pairOverlapCount, 1)
    }

    // MARK: - 信道分析

    func testChannelOverlap() {
        // 同信道必重叠
        XCTAssertTrue(ChannelPlan.overlaps((48, 160), (48, 80)))
        // 160MHz（覆盖 36-64）与 ch44 80MHz（40-48）重叠
        XCTAssertTrue(ChannelPlan.overlaps((48, 160), (44, 80)))
        // ch36 80MHz（32-40）与 ch48 160MHz（32-64）重叠
        XCTAssertTrue(ChannelPlan.overlaps((36, 80), (48, 160)))
        // ch100 与 ch48 的 160MHz 不重叠（80-120 vs 32-64）
        XCTAssertFalse(ChannelPlan.overlaps((100, 80), (48, 160)))
        // 2.4G：1 与 6 不重叠，1 与 4 重叠
        XCTAssertFalse(ChannelPlan.overlaps((1, 20), (6, 20)))
        XCTAssertTrue(ChannelPlan.overlaps((1, 20), (4, 20)))
    }

    func testChannelPlan5G() {
        let neighbors = [
            NeighborNetwork(ssid: "A", channel: 44, band: "5GHz", widthMHz: 80, rssi: -60, security: nil, phyMode: nil),
            NeighborNetwork(ssid: "B", channel: 157, band: "5GHz", widthMHz: 80, rssi: -58, security: nil, phyMode: nil),
            NeighborNetwork(ssid: "C", channel: 6, band: "2.4GHz", widthMHz: 20, rssi: -70, security: nil, phyMode: nil),
        ]
        let a = ChannelPlan.analyze(band: "5GHz", neighbors: neighbors, current: (48, 160, "我"))
        XCTAssertEqual(a.overlapCount, 1, "ch44/80MHz 与 ch48/160MHz 重叠")
        XCTAssertTrue(a.conflict)
        XCTAssertTrue(a.recommendation.contains("1 个邻居"))
        XCTAssertTrue(a.recommendation.contains("降到 80MHz"))

        let clean = ChannelPlan.analyze(band: "5GHz", neighbors: neighbors, current: (100, 80, "我"))
        XCTAssertEqual(clean.overlapCount, 0)
        XCTAssertFalse(clean.conflict)
        XCTAssertTrue(clean.recommendation.contains("不用动"))
    }

    func testChannelPlan24G() {
        let neighbors = [
            NeighborNetwork(ssid: "A", channel: 6, band: "2.4GHz", widthMHz: 20, rssi: -70, security: nil, phyMode: nil),
            NeighborNetwork(ssid: "B", channel: 6, band: "2.4GHz", widthMHz: 20, rssi: -78, security: nil, phyMode: nil),
            NeighborNetwork(ssid: "C", channel: 1, band: "2.4GHz", widthMHz: 40, rssi: -80, security: nil, phyMode: nil),
        ]
        let a = ChannelPlan.analyze(band: "2.4GHz", neighbors: neighbors, current: (6, 20, "我"))
        // 重叠的三个邻居：A(ch6)、B(ch6)、C(ch1 的 40MHz 压到 ch6 边缘)
        XCTAssertEqual(a.overlapCount, 3)
        XCTAssertTrue(a.recommendation.contains("1/6/11"))

        // 泳道分配：两个 ch6 的 AP 不应压在同一泳道
        let lanes = ChannelPlan.lanes(for: a.bars)
        let laneOf: (String) -> Int = { name in lanes.firstIndex { $0.contains { $0.ssid == name } } ?? -1 }
        XCTAssertNotEqual(laneOf("A"), laneOf("我"), "重叠的 AP 应分到不同泳道")
    }
}
