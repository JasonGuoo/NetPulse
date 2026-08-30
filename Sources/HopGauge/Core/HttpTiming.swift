import Foundation

/// 网页访问耗时分解：URLSession TaskMetrics → DNS/TCP/TLS/TTFB/下载
enum HttpTiming {

    static func measure(url rawURL: String) async -> HttpTimingResult {
        var result = HttpTimingResult(url: rawURL)
        guard let url = normalize(rawURL) else {
            result.error = L10n.t("dg.invalid.url")
            return result
        }
        result.url = url.absoluteString

        return await withCheckedContinuation { (cont: CheckedContinuation<HttpTimingResult, Never>) in
            let collector = MetricsCollector { r in
                cont.resume(returning: r)
            }
            let config = URLSessionConfiguration.ephemeral
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.timeoutIntervalForRequest = 20
            config.timeoutIntervalForResource = 30
            let session = URLSession(configuration: config, delegate: collector, delegateQueue: nil)
            collector.session = session

            var req = URLRequest(url: url)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            let task = session.dataTask(with: req)
            task.resume()
        }
    }

    static func normalize(_ s: String) -> URL? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.contains(".") else { return nil }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return URL(string: trimmed)
        }
        return URL(string: "https://" + trimmed)
    }

    static func buildPhases(from metrics: URLSessionTaskMetrics,
                            status: Int?, bytes: Int64, url: String) -> HttpTimingResult {
        var result = HttpTimingResult(url: url)
        result.httpStatus = status
        result.bytes = bytes
        result.total = metrics.taskInterval.duration

        var dns: Double = 0, tcp: Double = 0, tls: Double = 0, ttfb: Double = 0, download: Double = 0
        for tm in metrics.transactionMetrics {
            // 多次事务（重定向等）按段累加
            if let dStart = tm.domainLookupStartDate, let dEnd = tm.domainLookupEndDate {
                dns += dEnd.timeIntervalSince(dStart)
            }
            if let cStart = tm.connectStartDate {
                let cEndRaw = tm.connectEndDate
                let secureStart = tm.secureConnectionStartDate
                let tcpEnd = secureStart ?? cEndRaw
                if let tcpEnd, tcpEnd > cStart {
                    tcp += tcpEnd.timeIntervalSince(cStart)
                }
                if let sStart = secureStart, let sEnd = tm.secureConnectionEndDate {
                    tls += sEnd.timeIntervalSince(sStart)
                }
            }
            if let reqStart = tm.requestStartDate, let respStart = tm.responseStartDate {
                ttfb += respStart.timeIntervalSince(reqStart)
            }
            if let respStart = tm.responseStartDate, let respEnd = tm.responseEndDate {
                download += respEnd.timeIntervalSince(respStart)
            }
        }

        result.phases = [
            HttpPhase(name: L10n.t("phase.dns"), seconds: dns, colorIndex: 0),
            HttpPhase(name: L10n.t("phase.tcp"), seconds: tcp, colorIndex: 1),
            HttpPhase(name: L10n.t("phase.tls"), seconds: tls, colorIndex: 2),
            HttpPhase(name: L10n.t("phase.ttfb"), seconds: ttfb, colorIndex: 3),
            HttpPhase(name: L10n.t("phase.download"), seconds: download, colorIndex: 4),
        ]
        return result
    }
}

final class MetricsCollector: NSObject, URLSessionDataDelegate {
    private let completion: (HttpTimingResult) -> Void
    private var received: Int64 = 0
    private var status: Int?
    private var metrics: URLSessionTaskMetrics?
    private var completed = false
    private var finished = false
    private var requestURL: String = ""
    weak var session: URLSession?

    init(completion: @escaping (HttpTimingResult) -> Void) {
        self.completion = completion
        super.init()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        received += Int64(data.count)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didFinishCollecting metrics: URLSessionTaskMetrics) {
        self.metrics = metrics
        maybeFinish(task: task, error: nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        completed = true
        status = (task.response as? HTTPURLResponse)?.statusCode
        requestURL = task.currentRequest?.url?.absoluteString ?? task.originalRequest?.url?.absoluteString ?? ""
        maybeFinish(task: task, error: error)
        // didFinishCollecting 有时晚于 didComplete，稍后兜底
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.maybeFinish(task: task, error: error)
        }
    }

    private func maybeFinish(task: URLSessionTask, error: Error?) {
        guard !finished else { return }
        guard completed, metrics != nil || error != nil else { return }
        finished = true

        var result: HttpTimingResult
        if let metrics {
            result = HttpTiming.buildPhases(from: metrics, status: status, bytes: received, url: requestURL)
            if let error, (result.httpStatus == nil) {
                result.error = Self.describe(error)
            }
        } else {
            result = HttpTimingResult(url: requestURL)
            result.error = error.map(Self.describe) ?? L10n.t("err.nometrics")
        }
        completion(result)
        session?.finishTasksAndInvalidate()
    }

    static func describe(_ error: Error) -> String {
        let ns = error as NSError
        switch ns.code {
        case NSURLErrorTimedOut:
            return L10n.t("err.timeout")
        case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost:
            return L10n.tf("err.nohost", ns.localizedDescription)
        case NSURLErrorDNSLookupFailed:
            return L10n.t("err.dns")
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted:
            return L10n.tf("err.tls", ns.localizedDescription)
        case NSURLErrorNetworkConnectionLost:
            return L10n.t("err.lost")
        case NSURLErrorNotConnectedToInternet:
            return L10n.t("err.offline")
        default:
            return ns.localizedDescription
        }
    }
}
