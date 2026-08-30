import Foundation
import CoreWLAN

/// WiFi 射频采集：CoreWLAN 实时值（2s）+ system_profiler 补充（20s，含 SSID/带宽/周边扫描）
final class WifiInfoCollector {

    struct LiveSnapshot {
        var interface: String?
        var rssi: Int?
        var noise: Int?
        var txRate: Double?
        var channel: Int?
        var band: String?
        var security: String?
        var phyMode: String?
        var connected: Bool = false
    }

    struct ProfilerInfo {
        var ssid: String?
        var channel: Int?
        var band: String?
        var widthMHz: Int?
        var mcs: Int?
        var country: String?
        var security: String?
        var phyMode: String?
    }

    struct ProfilerResult {
        var current: ProfilerInfo?
        var neighbors: [NeighborNetwork] = []
    }

    func loops(model: AppModel) -> [Task<Void, Never>] {
        [
            Task { await self.liveLoop(model: model) },
            Task { await self.profilerLoop(model: model) },
        ]
    }

    // MARK: - CoreWLAN 实时

    private func liveLoop(model: AppModel) async {
        while !Task.isCancelled {
            await Self.pollLive(model: model)
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    /// 单次 CoreWLAN 快照（刷新按钮也调用）
    static func pollLive(model: AppModel) async {
        let snap = readCoreWLAN()
        await MainActor.run {
            model.applyWifiLive(snap)
        }
    }

    static func readCoreWLAN() -> LiveSnapshot {
        var s = LiveSnapshot()
        guard let iface = CWWiFiClient.shared().interface() else { return s }
        s.interface = iface.interfaceName
        let rssi = Int(iface.rssiValue())
        let noise = Int(iface.noiseMeasurement())
        let txRate = iface.transmitRate()
        // 断开时 rssi 可能为 0 或极大哨兵值
        if rssi < 0 {
            s.rssi = rssi
            s.noise = noise < 0 ? noise : nil
            s.connected = true
        } else {
            s.connected = false
        }
        if txRate > 0 { s.txRate = txRate }
        if let ch = iface.wlanChannel() {
            s.channel = ch.channelNumber
            s.band = Self.bandString(ch)
        }
        s.security = securityString(iface.security())
        s.phyMode = phyString(iface.activePHYMode())
        return s
    }

    static func bandString(_ ch: CWChannel) -> String? {
        switch ch.channelBand.rawValue {
        case 1: return "2.4GHz"
        case 2: return "5GHz"
        case 3: return "6GHz"
        default: return nil
        }
    }

    /// CWSecurity rawValue（该 SDK 的 case 名未被 Swift 规范化，按头文件枚举值映射）
    static func securityString(_ sec: CWSecurity) -> String {
        switch sec.rawValue {
        case 0: return L10n.t("sec.open")
        case 1: return L10n.t("sec.wep")
        case 2: return L10n.t("sec.wpa.psk")
        case 3: return L10n.t("sec.wpa.eap")
        case 4: return L10n.t("sec.wpa2.psk")
        case 5: return L10n.t("sec.wpa2.eap")
        case 6: return L10n.t("sec.wpa2.mixed")
        case 7, 8: return L10n.t("sec.wpa3.psk")
        case 9: return L10n.t("sec.wpa3.eap")
        default: return L10n.tf("sec.unknown.fmt", sec.rawValue)
        }
    }

    /// CWPHYMode rawValue
    static func phyString(_ mode: CWPHYMode) -> String {
        switch mode.rawValue {
        case 1: return "802.11a"
        case 2: return "802.11b"
        case 3: return "802.11g"
        case 4: return "802.11n"
        case 5: return "802.11ac"
        case 6: return "802.11ax"
        case 7: return "802.11be"
        default: return "—"
        }
    }

    // MARK: - system_profiler 补充

    private func profilerLoop(model: AppModel) async {
        while !Task.isCancelled {
            await Self.scanProfiler(model: model)
            try? await Task.sleep(nanoseconds: 20_000_000_000)
        }
    }

    /// 单次周边扫描（SSID/信道宽度/邻居，刷新按钮也调用）
    static func scanProfiler(model: AppModel) async {
        if let text = await Shell.run("/usr/sbin/system_profiler", ["SPAirPortDataType", "-json"], timeout: 25),
           let result = parseProfilerJSON(text) {
            await MainActor.run {
                model.applyWifiProfiler(result.current)
                model.neighbors = result.neighbors
                model.lastScanAt = Date()
            }
        }
    }

    static func parseProfilerJSON(_ text: String) -> ProfilerResult? {
        guard let data = text.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let sections = obj["SPAirPortDataType"] as? [[String: Any]] else { return nil }

        for section in sections {
            guard let ifaces = section["spairport_airport_interfaces"] as? [[String: Any]] else { continue }
            for iface in ifaces {
                var result = ProfilerResult()

                // 先解析当前网络（用于过滤自身 AP）
                if let cur = iface["spairport_current_network_information"] as? [String: Any],
                   let ssid = cur["_name"] as? String {
                    let parsed = (cur["spairport_network_channel"] as? String).flatMap(parseChannel)
                    result.current = ProfilerInfo(
                        ssid: ssid,
                        channel: parsed?.channel,
                        band: parsed?.band,
                        widthMHz: parsed?.width,
                        mcs: cur["spairport_network_mcs"] as? Int,
                        country: cur["spairport_network_country_code"] as? String,
                        security: mapSecurity(cur["spairport_security_mode"] as? String),
                        phyMode: cur["spairport_network_phymode"] as? String)
                }

                if let others = iface["spairport_airport_other_local_wireless_networks"] as? [[String: Any]] {
                    for n in others {
                        guard let name = n["_name"] as? String,
                              let chStr = n["spairport_network_channel"] as? String,
                              let parsed = parseChannel(chStr) else { continue }

                        // 同 SSID 且同频段同信道 = 当前关联的 AP 本身，剔除（否则会"自己和自己冲突"）
                        if let cur = result.current,
                           name == cur.ssid,
                           parsed.channel == cur.channel,
                           parsed.band == cur.band {
                            continue
                        }
                        // 同 SSID 的其他频段/节点 = 自己的路由器，保留显示但不算外部干扰
                        let isOwn = result.current.map { $0.ssid == name } ?? false
                        result.neighbors.append(NeighborNetwork(
                            ssid: name,
                            channel: parsed.channel,
                            band: parsed.band,
                            widthMHz: parsed.width,
                            rssi: (n["spairport_signal_noise"] as? String).flatMap(parseSignal),
                            security: mapSecurity(n["spairport_security_mode"] as? String),
                            phyMode: n["spairport_network_phymode"] as? String,
                            isOwnRouter: isOwn))
                    }
                }
                return result
            }
        }
        return nil
    }

    /// "6 (2GHz, 20MHz)" → (6, "2.4GHz", 20)
    static func parseChannel(_ s: String) -> (channel: Int, band: String, width: Int)? {
        guard let caps = regexCapture(#"^(\d+) \((\d+GHz), (\d+)MHz\)"#, from: s),
              caps.count == 3,
              let ch = Int(caps[0]),
              let width = Int(caps[2]) else { return nil }
        let bandRaw = caps[1]
        let band: String
        switch bandRaw {
        case "2GHz": band = "2.4GHz"
        case "5GHz": band = "5GHz"
        case "6GHz": band = "6GHz"
        default: band = bandRaw
        }
        return (ch, band, width)
    }

    /// "-45 dBm / -92 dBm" → -45
    static func parseSignal(_ s: String) -> Int? {
        guard let caps = regexCapture(#"^(-?\d+) dBm"#, from: s), let v = Int(caps[0]) else { return nil }
        return v
    }

    static func mapSecurity(_ raw: String?) -> String? {
        guard let raw else { return nil }
        switch raw {
        case "spairport_security_mode_none": return L10n.t("sec.open")
        case "spairport_security_mode_wep": return L10n.t("sec.wep")
        case "spairport_security_mode_wpa_personal": return L10n.t("sec.wpa.psk")
        case "spairport_security_mode_wpa2_personal": return L10n.t("sec.wpa2.psk")
        case "spairport_security_mode_wpa2_personal_mixed": return L10n.t("sec.wpa2.mixed")
        case "spairport_security_mode_wpa2_enterprise": return L10n.t("sec.wpa2.eap")
        case "spairport_security_mode_wpa3_personal": return L10n.t("sec.wpa3.psk")
        case "spairport_security_mode_wpa3_enterprise": return L10n.t("sec.wpa3.eap")
        default: return raw.replacingOccurrences(of: "spairport_security_mode_", with: "")
        }
    }
}
