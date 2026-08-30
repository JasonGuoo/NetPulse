import Foundation

/// Runs a bounded, on-demand traceroute and converts macOS output into display-ready hops.
enum RouteTracer {
    private static let maximumHops = 20

    static func trace(rawTarget: String) async -> RouteTraceResult {
        guard let host = HttpTiming.normalize(rawTarget)?.host, !host.isEmpty else {
            return RouteTraceResult(target: rawTarget, failure: .invalidTarget)
        }

        let startedAt = Date()
        let executable = host.contains(":") ? "/usr/sbin/traceroute6" : "/usr/sbin/traceroute"
        let arguments = ["-n", "-q", "1", "-w", "1", "-m", String(maximumHops), "-z", "50", host]

        guard let output = await Shell.run(executable, arguments, timeout: 24, mergeStderr: true) else {
            return RouteTraceResult(
                target: host,
                duration: Date().timeIntervalSince(startedAt),
                failure: .unavailable
            )
        }

        var result = parse(output, target: host, method: .udp)
        result.duration = Date().timeIntervalSince(startedAt)
        result.measuredAt = Date()
        if result.hops.isEmpty {
            result.failure = .noRoute
        }
        return result
    }

    static func parse(_ output: String, target: String, method: RouteTraceMethod = .udp) -> RouteTraceResult {
        var result = RouteTraceResult(target: target, method: method)

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.lowercased().hasPrefix("traceroute") {
                result.resolvedAddress = resolvedAddress(in: line)
                continue
            }

            let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let first = tokens.first, let index = Int(first), index > 0 else { continue }

            let address = tokens.dropFirst().first(where: { token in
                token != "*"
                    && !token.hasPrefix("!")
                    && Double(token.replacingOccurrences(of: "<", with: "")) == nil
                    && token != "ms"
            })
            let latency = latencyValue(in: tokens)
            let annotation = tokens.first(where: { $0.hasPrefix("!") })
            result.hops.append(RouteHop(
                index: index,
                address: address,
                latencyMs: latency,
                annotation: annotation
            ))
        }

        let destination = result.resolvedAddress ?? target
        result.reachedDestination = result.hops.contains { $0.address == destination }
        return result
    }

    private static func resolvedAddress(in header: String) -> String? {
        if let open = header.lastIndex(of: "("),
           let close = header[open...].firstIndex(of: ")"),
           open < close {
            return String(header[header.index(after: open)..<close])
        }

        let tokens = header.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let toIndex = tokens.firstIndex(of: "to"), tokens.indices.contains(toIndex + 1) else { return nil }
        return tokens[toIndex + 1].trimmingCharacters(in: CharacterSet(charactersIn: ","))
    }

    private static func latencyValue(in tokens: [String]) -> Double? {
        guard let msIndex = tokens.firstIndex(of: "ms"), msIndex > 0 else { return nil }
        return Double(tokens[msIndex - 1].replacingOccurrences(of: "<", with: ""))
    }
}
