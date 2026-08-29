import Foundation

/// 下载吞吐测速：Cloudflare __down 端点，流式统计字节/时间
/// 端点限制：过大请求（>25MB）与短时密集请求会返回 403，
/// 因此按预热带宽自适应 5~25MB，且失败时降档重试
enum SpeedTest {

    static func run(onUpdate: @escaping (Double, Double) -> Void) async -> SpeedResult {
        // 预热：小文件（建立连接 + 粗测带宽）
        let warm = await download(bytes: 3_000_000, capSeconds: 4) { _, _ in }

        // 给端点留出节奏，避免连续请求触发风控
        try? await Task.sleep(nanoseconds: 1_800_000_000)

        // 按预热速率选择正式测速体积：目标约 8 秒跑完，夹在 5~25MB
        let warmBps = warm.seconds > 0 ? Double(warm.bytes) / warm.seconds : 500_000
        var size: Int64 = Int64(warmBps * 8.0)
        size = max(5_000_000, min(size, 25_000_000))

        // 最多两轮：失败（字节异常少）则降档重来
        var result = await download(bytes: size, capSeconds: 14) { mbps, _ in
            Task { @MainActor in
                onUpdate(mbps, 0)
            }
        }
        if result.bytes < 10_000 {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            result = await download(bytes: max(5_000_000, size / 4), capSeconds: 14) { mbps, _ in
                Task { @MainActor in
                    onUpdate(mbps, 0)
                }
            }
        }
        return result
    }

    private static func download(bytes: Int64, capSeconds: Double,
                                 onProgress: @escaping (Double, Double) -> Void) async -> SpeedResult {
        await withCheckedContinuation { (cont: CheckedContinuation<SpeedResult, Never>) in
            let counter = ByteCounter(capSeconds: capSeconds) { result, liveMbps in
                cont.resume(returning: result)
            }
            counter.onProgress = onProgress

            let config = URLSessionConfiguration.ephemeral
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.timeoutIntervalForRequest = 8
            config.timeoutIntervalForResource = capSeconds + 5
            let session = URLSession(configuration: config, delegate: counter, delegateQueue: nil)

            let url = URL(string: "https://speed.cloudflare.com/__down?bytes=\(bytes)")!
            var req = URLRequest(url: url)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            req.setValue("Mozilla/5.0 (Macintosh) WiFiDoctor/1.0", forHTTPHeaderField: "User-Agent")
            let task = session.dataTask(with: req)
            counter.task = task
            task.resume()
        }
    }
}

final class ByteCounter: NSObject, URLSessionDataDelegate {
    private let capSeconds: Double
    private let completion: (SpeedResult, Double) -> Void
    private var bytes: Int64 = 0
    private var started: Date?
    private var finished = false
    var onProgress: ((Double, Double) -> Void)?
    var task: URLSessionDataTask?
    private var lastReport = Date.distantPast
    private var debugLog: [String] = []

    init(capSeconds: Double, completion: @escaping (SpeedResult, Double) -> Void) {
        self.capSeconds = capSeconds
        self.completion = completion
        super.init()
    }

    private var elapsed: Double {
        started.map { Date().timeIntervalSince($0) } ?? 0
    }

    private var liveMbps: Double {
        guard elapsed > 0.3 else { return 0 }
        return Double(bytes) * 8 / elapsed / 1_000_000
    }

    private func report() {
        guard Date().timeIntervalSince(lastReport) > 0.25, elapsed > 0.3 else { return }
        lastReport = Date()
        onProgress?(liveMbps, elapsed)
    }

    private func finish(cancel: Bool) {
        guard !finished else { return }
        finished = true
        if cancel { task?.cancel() }
        let secs = max(elapsed, 0.001)
        var r = SpeedResult()
        r.bytes = bytes
        r.seconds = secs
        r.downloadMbps = Double(bytes) * 8 / secs / 1_000_000
        r.measuredAt = Date()
        if bytes < 10_000 {
            r.errorNote = debugLog.joined(separator: " | ")
        }
        completion(r, liveMbps)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        debugLog.append("resp \((response as? HTTPURLResponse)?.statusCode ?? -1) len=\(response.expectedContentLength)")
        if started == nil { started = Date() }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if started == nil { started = Date() }
        bytes += Int64(data.count)
        report()
        if elapsed > capSeconds {
            finish(cancel: true)
            session.finishTasksAndInvalidate()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            debugLog.append("err \((error as NSError).code): \((error as NSError).localizedFailureReason ?? (error as NSError).localizedDescription)")
        }
        finish(cancel: false)
        session.finishTasksAndInvalidate()
    }
}
