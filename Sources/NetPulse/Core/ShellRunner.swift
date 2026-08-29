import Foundation

/// 异步子进程执行器：所有系统命令采集的统一入口
enum Shell {

    static func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval = 10) async -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: launchPath)
        task.arguments = arguments
        task.environment = ProcessInfo.processInfo.environment

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()   // 丢弃 stderr

        do {
            try task.run()
        } catch {
            return nil
        }

        final class Box: @unchecked Sendable {
            let lock = NSLock()
            var resumed = false
            var buf = Data()
            func resumeOnce(_ c: CheckedContinuation<Data, Never>) {
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                c.resume(returning: buf)
            }
        }
        let box = Box()

        let data: Data = await withCheckedContinuation { (cont: CheckedContinuation<Data, Never>) in
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    box.resumeOnce(cont)
                } else {
                    box.lock.lock()
                    box.buf.append(chunk)
                    box.lock.unlock()
                }
            }
            // 超时保护：终止进程触发 EOF；再延迟兜底 resume（Box 保证只 resume 一次）
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak task] in
                if task?.isRunning == true {
                    task?.terminate()
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
                    box.resumeOnce(cont)
                }
            }
        }

        if task.isRunning { task.terminate() }
        return String(data: data, encoding: .utf8)
    }
}
