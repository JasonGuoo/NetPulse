import Foundation
import Darwin

/// 远端 IP → 服务商/归属 的友好名称映射
/// 让"连到 162.159.61.3:443"变成"连到 Cloudflare"
enum IPProvider {

    struct CIDR {
        let network: in_addr_t   // host byte order
        let mask: in_addr_t
        let name: String
    }

    static let table: [CIDR] = {
        func cidr(_ cidrString: String, _ name: String) -> CIDR? {
            let parts = cidrString.split(separator: "/")
            guard parts.count == 2,
                  let addr = ipv4(String(parts[0])),
                  let prefix = Int(parts[1]), prefix >= 0, prefix <= 32 else { return nil }
            // 掩码按主机数值序（与 ipv4() 的转换一致），不做字节序翻转
            let mask: in_addr_t = prefix == 0 ? 0 : UInt32.max << (32 - prefix)
            return CIDR(network: addr & mask, mask: mask, name: name)
        }
        func ipv4(_ s: String) -> in_addr_t? {
            var a = in_addr()
            guard s.withCString({ inet_pton(AF_INET, $0, &a) }) == 1 else { return nil }
            return UInt32(bigEndian: a.s_addr)
        }
        let raw: [(String, String)] = [
            // 本机 / 局域网（文案经 L10n 渲染，见 nameKey）
            ("127.0.0.0/8", "ip.loopback"), ("10.0.0.0/8", "ip.lan"),
            ("172.16.0.0/12", "ip.lan"), ("192.168.0.0/16", "ip.lan"),
            ("169.254.0.0/16", "ip.linklocal"), ("224.0.0.0/4", "ip.multicast"), ("255.255.255.255/32", "ip.broadcast"),
            // 大厂常用段
            ("17.0.0.0/8", "Apple"),
            ("1.1.1.0/24", "Cloudflare"), ("104.16.0.0/13", "Cloudflare"),
            ("162.158.0.0/15", "Cloudflare"), ("172.64.0.0/13", "Cloudflare"),
            ("188.114.96.0/20", "Cloudflare"), ("190.93.240.0/20", "Cloudflare"),
            ("198.41.128.0/17", "Cloudflare"),
            ("8.8.4.0/22", "Google"), ("8.8.8.0/24", "Google"), ("34.64.0.0/10", "Google"),
            ("35.184.0.0/13", "Google"), ("142.250.0.0/15", "Google"), ("172.217.0.0/16", "Google"),
            ("216.58.192.0/19", "Google"), ("74.125.0.0/16", "Google"), ("64.233.160.0/19", "Google"),
            ("20.0.0.0/8", "Microsoft"), ("13.64.0.0/11", "Microsoft"), ("13.96.0.0/13", "Microsoft"),
            ("40.64.0.0/10", "Microsoft"), ("52.96.0.0/12", "Microsoft"), ("13.107.0.0/16", "Microsoft"),
            ("31.13.0.0/16", "Meta"), ("157.240.0.0/16", "Meta"), ("69.171.224.0/19", "Meta"),
            ("173.252.64.0/18", "Meta"),
            ("140.82.112.0/20", "GitHub"), ("192.30.252.0/22", "GitHub"),
            ("3.0.0.0/8", "AWS"), ("18.0.0.0/8", "AWS"), ("52.0.0.0/8", "AWS"), ("54.0.0.0/8", "AWS"),
            ("99.84.0.0/16", "AWS CloudFront"), ("13.32.0.0/15", "AWS CloudFront"),
            ("129.226.0.0/16", "ip.tencent"), ("162.62.0.0/16", "ip.tencent"), ("43.138.0.0/16", "ip.tencent"),
            ("101.32.0.0/16", "ip.tencent"), ("43.136.0.0/16", "ip.tencent"),
            ("8.208.0.0/12", "ip.ali"), ("47.88.0.0/14", "ip.ali"), ("47.240.0.0/16", "ip.ali"),
            ("39.98.0.0/15", "ip.ali"), ("47.92.0.0/14", "ip.ali"),
            ("110.242.68.0/24", "ip.baidu"), ("39.156.66.0/24", "ip.baidu"), ("182.61.0.0/16", "ip.baidu"),
            ("180.76.0.0/16", "ip.baidu"),
            ("119.29.29.29/32", "腾讯 DNSPod"), ("223.5.5.0/24", "阿里 DNS"),
            ("114.114.114.0/24", "114DNS"),
        ]
        return raw.compactMap { cidr($0.0, $0.1) }
    }()

    static func name(of host: String) -> String? {
        // IPv6 前缀粗判
        let lower = host.lowercased()
        if lower.hasPrefix("fe80:") { return L10n.t("ip.linklocal") }
        if lower.hasPrefix("fd") || lower.hasPrefix("fc") { return L10n.t("ip.lan") }
        if lower.contains(":") { return "IPv6" }

        var a = in_addr()
        guard host.withCString({ inet_pton(AF_INET, $0, &a) }) == 1 else { return nil }
        let addr = UInt32(bigEndian: a.s_addr)
        for c in table where (addr & c.mask) == c.network {
            return c.name.hasPrefix("ip.") ? L10n.t(c.name) : c.name
        }
        return nil
    }

    static func describe(_ row: ConnectionRow) -> String {
        if !row.hasRemote { return row.isListen ? L10n.t("cn.listen") : L10n.t("dash") }
        let ip = row.remote.split(separator: ":").first.map(String.init) ?? row.remote
        return name(of: ip) ?? L10n.t("ip.external")
    }
}

/// 已知进程的图标与配色
enum AppBadgeInfo {
    struct Info { let symbol: String; let label: String }

    static func of(process: String) -> Info {
        let p = process.lowercased()
        let table: [(contains: String, info: Info)] = [
            ("safari", Info(symbol: "safari", label: "Safari")),
            ("chrome", Info(symbol: "globe", label: "Chrome")),
            ("firefox", Info(symbol: "flame", label: "Firefox")),
            ("edge", Info(symbol: "compass", label: "Edge")),
            ("wechat", Info(symbol: "message.fill", label: "app.wechat")),
            ("wetype", Info(symbol: "keyboard", label: "app.wetype")),
            ("qq", Info(symbol: "bubble.left.and.bubble.right", label: "QQ")),
            ("music", Info(symbol: "music.note", label: "app.music")),
            ("spotify", Info(symbol: "music.quarternote.3", label: "Spotify")),
            ("docker", Info(symbol: "cubes", label: "Docker")),
            ("orbstack", Info(symbol: "cube", label: "OrbStack")),
            ("ssh", Info(symbol: "terminal", label: "SSH")),
            ("terminal", Info(symbol: "terminal", label: "app.terminal")),
            ("zcode", Info(symbol: "chevron.left.forwardslash.chevron.right", label: "ZCode")),
            ("xcode", Info(symbol: "hammer", label: "Xcode")),
            ("github", Info(symbol: "chevron.left.forwardslash.chevron.right", label: "GitHub")),
            ("cloudflared", Info(symbol: "cloud", label: "Cloudflare")),
            ("mdnsresponder", Info(symbol: "arrow.triangle.2.circlepath", label: "app.sysdns")),
            ("identitys", Info(symbol: "person.crop.circle", label: "app.syssvc")),
            ("rapportd", Info(symbol: "airplayaudio", label: "app.airdrop")),
            ("searchparty", Info(symbol: "location", label: "app.findmy")),
            ("assistantd", Info(symbol: "sparkles", label: "Siri")),
            ("node", Info(symbol: "bolt", label: "app.node")),
            ("python", Info(symbol: "bolt", label: "app.python")),
        ]
        for entry in table where p.contains(entry.contains) {
            let label = entry.info.label.hasPrefix("app.") ? L10n.t(entry.info.label) : entry.info.label
            return Info(symbol: entry.info.symbol, label: label)
        }
        return Info(symbol: "", label: process)
    }
}
