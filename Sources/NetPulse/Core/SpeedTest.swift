import Foundation

/// Download throughput test using Cloudflare's public __down endpoint.
/// A small warm-up sizes a longer 10-100 MB measurement, while a rolling byte
/// window produces real instantaneous readings for the native speedometer.
enum SpeedTest {

    static func run(onUpdate: @escaping (SpeedTestProgress) -> Void) async -> SpeedResult {
        onUpdate(SpeedTestProgress(phase: .warmingUp, targetBytes: 1_000_000))
        let warm = await download(bytes: 1_000_000, capSeconds: 3) { sample in
            onUpdate(progress(from: sample, phase: .warmingUp, overallFraction: sample.fraction * 0.16))
        }

        onUpdate(SpeedTestProgress(
            phase: .preparing,
            averageMbps: warm.downloadMbps,
            peakMbps: warm.downloadMbps,
            fraction: 0.18,
            elapsed: warm.seconds,
            receivedBytes: warm.bytes,
            targetBytes: warm.bytes
        ))
        try? await Task.sleep(nanoseconds: 1_200_000_000)

        // Aim for roughly six seconds and cap data use at 100 MB.
        let warmBps = warm.seconds > 0 ? Double(warm.bytes) / warm.seconds : 500_000
        var size = Int64(warmBps * 6.0)
        size = max(10_000_000, min(size, 100_000_000))

        onUpdate(SpeedTestProgress(phase: .measuring, fraction: 0.2, targetBytes: size))
        var result = await download(bytes: size, capSeconds: 14) { sample in
            onUpdate(progress(
                from: sample,
                phase: .measuring,
                overallFraction: 0.2 + sample.fraction * 0.8
            ))
        }
        if result.bytes < 10_000 {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            let retrySize = max(10_000_000, size / 4)
            onUpdate(SpeedTestProgress(phase: .retrying, fraction: 0.2, targetBytes: retrySize))
            result = await download(bytes: retrySize, capSeconds: 14) { sample in
                onUpdate(progress(
                    from: sample,
                    phase: .retrying,
                    overallFraction: 0.2 + sample.fraction * 0.8
                ))
            }
        }
        return result
    }

    private static func progress(
        from sample: SpeedTransferSample,
        phase: SpeedTestPhase,
        overallFraction: Double
    ) -> SpeedTestProgress {
        SpeedTestProgress(
            phase: phase,
            instantaneousMbps: sample.instantaneousMbps,
            averageMbps: sample.averageMbps,
            peakMbps: sample.peakMbps,
            fraction: min(max(overallFraction, 0), 1),
            elapsed: sample.elapsed,
            receivedBytes: sample.bytes,
            targetBytes: sample.targetBytes
        )
    }

    private static func download(bytes: Int64, capSeconds: Double,
                                 onProgress: @escaping (SpeedTransferSample) -> Void) async -> SpeedResult {
        await withCheckedContinuation { (cont: CheckedContinuation<SpeedResult, Never>) in
            let counter = ByteCounter(targetBytes: bytes, capSeconds: capSeconds) { result in
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
            req.setValue("Mozilla/5.0 (Macintosh) NetPulse/1.0", forHTTPHeaderField: "User-Agent")
            let task = session.dataTask(with: req)
            counter.task = task
            task.resume()
        }
    }
}

struct SpeedTransferSample: Equatable {
    let instantaneousMbps: Double
    let averageMbps: Double
    let peakMbps: Double
    let elapsed: Double
    let bytes: Int64
    let targetBytes: Int64

    var fraction: Double {
        guard targetBytes > 0 else { return 0 }
        return min(Double(bytes) / Double(targetBytes), 1)
    }
}

struct SpeedWindowEstimator {
    private(set) var lastElapsed: Double = 0
    private(set) var lastBytes: Int64 = 0
    private(set) var smoothedMbps: Double = 0
    private(set) var peakMbps: Double = 0

    mutating func sample(
        totalBytes: Int64,
        targetBytes: Int64,
        elapsed: Double,
        force: Bool = false
    ) -> SpeedTransferSample? {
        let interval = elapsed - lastElapsed
        guard force || interval >= 0.12 else { return nil }

        let byteDelta = totalBytes - lastBytes
        let averageMbps = elapsed > 0.05 ? Double(totalBytes) * 8 / elapsed / 1_000_000 : 0
        let rawMbps = interval >= 0.08 ? Double(byteDelta) * 8 / interval / 1_000_000 : 0
        if smoothedMbps == 0 {
            smoothedMbps = rawMbps > 0 ? rawMbps : averageMbps
        } else if rawMbps > 0 {
            smoothedMbps = smoothedMbps * 0.62 + rawMbps * 0.38
        }
        peakMbps = max(peakMbps, smoothedMbps)
        lastElapsed = elapsed
        lastBytes = totalBytes

        return SpeedTransferSample(
            instantaneousMbps: smoothedMbps,
            averageMbps: averageMbps,
            peakMbps: peakMbps,
            elapsed: elapsed,
            bytes: totalBytes,
            targetBytes: targetBytes
        )
    }
}

final class ByteCounter: NSObject, URLSessionDataDelegate {
    private let targetBytes: Int64
    private let capSeconds: Double
    private let completion: (SpeedResult) -> Void
    private var bytes: Int64 = 0
    private var started: Date?
    private var finished = false
    var onProgress: ((SpeedTransferSample) -> Void)?
    var task: URLSessionDataTask?
    private var estimator = SpeedWindowEstimator()
    private var debugLog: [String] = []

    init(targetBytes: Int64, capSeconds: Double, completion: @escaping (SpeedResult) -> Void) {
        self.targetBytes = targetBytes
        self.capSeconds = capSeconds
        self.completion = completion
        super.init()
    }

    private var elapsed: Double {
        started.map { Date().timeIntervalSince($0) } ?? 0
    }

    private func report(force: Bool = false) {
        guard started != nil,
              let sample = estimator.sample(
                totalBytes: bytes,
                targetBytes: targetBytes,
                elapsed: elapsed,
                force: force
              ) else { return }
        onProgress?(sample)
    }

    private func finish(cancel: Bool) {
        guard !finished else { return }
        finished = true
        if cancel { task?.cancel() }
        report(force: true)
        let secs = max(elapsed, 0.001)
        var r = SpeedResult()
        r.bytes = bytes
        r.seconds = secs
        r.downloadMbps = Double(bytes) * 8 / secs / 1_000_000
        r.measuredAt = Date()
        if bytes < 10_000 {
            r.errorNote = debugLog.joined(separator: " | ")
        }
        completion(r)
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
