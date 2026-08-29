import Foundation

/// DNS 解析对比：系统 resolver vs 公共 DNS
enum DnsBench {

    static func run(host: String) async -> [DnsResult] {
        async let sys = measure(host: host, server: nil)
        async let cf = measure(host: host, server: "1.1.1.1")
        async let gg = measure(host: host, server: "8.8.8.8")
        let a = await sys
        let b = await cf
        let c = await gg
        return [a, b, c]
    }

    static func measure(host: String, server: String?) async -> DnsResult {
        var args = ["+time=2", "+tries=1", "+noall", "+answer", "+stats"]
        if let server {
            args.append("@" + server)
        }
        args.append(host)

        let start = Date()
        let out = await Shell.run("/usr/bin/dig", args, timeout: 6)
        let elapsed = (Date().timeIntervalSince(start)) * 1000
        let text = out ?? ""

        guard out != nil else {
            return DnsResult(server: server ?? L10n.t("dns.system"), ms: nil, error: L10n.t("err.dig"))
        }
        guard text.contains("ANSWER") || text.contains("ANSWER SECTION") || elapsed > 0 else {
            return DnsResult(server: server ?? L10n.t("dns.system"), ms: nil, error: L10n.t("err.noanswer"))
        }

        let serverLabel: String
        if let server {
            serverLabel = server
        } else if let caps = regexCapture(#";; SERVER: (\S+)"#, from: text) {
            serverLabel = L10n.tf("dns.server.fmt", caps[0].components(separatedBy: "#").first ?? caps[0])
        } else {
            serverLabel = L10n.t("dns.system")
        }

        if let caps = regexCapture(#"Query time: (\d+) msec"#, from: text), let ms = Double(caps[0]) {
            return DnsResult(server: serverLabel, ms: ms, error: nil)
        }
        // dig 无 Query time 时退化为墙钟时间
        if text.contains("ANSWER") {
            return DnsResult(server: serverLabel, ms: max(elapsed - 15, 1), error: nil)
        }
        return DnsResult(server: serverLabel, ms: nil, error: L10n.t("err.dnsfail"))
    }
}
