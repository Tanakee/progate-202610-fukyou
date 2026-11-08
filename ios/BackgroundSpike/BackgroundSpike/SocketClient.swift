import Foundation
import Observation

/// 検証用サーバーにつなぎ、受信の間隔をログに残す。切れたら指数バックオフで再接続する。
@MainActor
@Observable
final class SocketClient {
    enum State: String {
        case disconnected = "未接続"
        case connecting = "接続中"
        case connected = "接続済み"
    }

    private struct Message: Decodable {
        let seq: Int
        let notify: Bool?
        let text: String?
    }

    private(set) var state = State.disconnected
    private(set) var receivedCount = 0
    var onNotify: ((String) -> Void)?

    private let log: EventLog
    private var task: URLSessionWebSocketTask?
    private var watchdog: Task<Void, Never>?
    private var shouldRun = false
    private var retryCount = 0
    private var lastReceivedAt: Date?

    /// 5秒ごとに届くはずなので、これを超えたら遅れとして目立たせる
    private static let lateThreshold: TimeInterval = 7
    /// これだけ届かなければ切断とみなす
    private static let silenceLimit: TimeInterval = 15
    private static let maxBackoff: TimeInterval = 30

    init(log: EventLog) {
        self.log = log
    }

    func connect(to urlString: String) {
        guard let url = URL(string: urlString), url.scheme == "ws" || url.scheme == "wss" else {
            log.add("⚠️ URLが不正: \(urlString)")
            return
        }
        shouldRun = true
        retryCount = 0
        open(url)
    }

    func disconnect() {
        shouldRun = false
        close()
        state = .disconnected
        log.add("切断（手動）")
    }

    private func open(_ url: URL) {
        close()
        state = .connecting
        lastReceivedAt = nil
        let task = URLSession.shared.webSocketTask(with: url)
        self.task = task
        task.resume()
        log.add("接続を開始: \(url.absoluteString)")
        receive(on: task, url: url)
        startWatchdog(for: task, url: url)
    }

    private func close() {
        watchdog?.cancel()
        watchdog = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func receive(on task: URLSessionWebSocketTask, url: URL) {
        Task { [weak self] in
            while true {
                do {
                    let message = try await task.receive()
                    self?.handle(message)
                } catch {
                    self?.fail(task, url: url, reason: error.localizedDescription)
                    return
                }
            }
        }
    }

    /// pingを送りつつ、受信が途切れていないかを見張る
    private func startWatchdog(for task: URLSessionWebSocketTask, url: URL) {
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self, !Task.isCancelled, self.task === task else { return }
                let since = self.lastReceivedAt ?? .distantPast
                if self.state == .connected, Date.now.timeIntervalSince(since) > Self.silenceLimit {
                    self.fail(task, url: url, reason: "\(Int(Self.silenceLimit))秒以上受信がない")
                    return
                }
                task.sendPing { [weak self] error in
                    guard let error else { return }
                    Task { @MainActor in self?.fail(task, url: url, reason: "pingの失敗: \(error.localizedDescription)") }
                }
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let now = Date.now
        if state != .connected {
            state = .connected
            retryCount = 0
            log.add("接続済み")
        }
        let gap = lastReceivedAt.map { now.timeIntervalSince($0) }
        lastReceivedAt = now
        receivedCount += 1

        guard case .string(let text) = message,
              let decoded = try? JSONDecoder().decode(Message.self, from: Data(text.utf8)) else {
            log.add("受信（形式が不明）")
            return
        }
        let gapText = gap.map { String(format: " 間隔 %.1f秒", $0) } ?? ""
        let mark = (gap ?? 0) > Self.lateThreshold ? "⚠️ " : ""
        log.add("\(mark)受信 #\(decoded.seq)\(gapText)")
        if decoded.notify == true {
            onNotify?(decoded.text ?? "#\(decoded.seq)")
        }
    }

    private func fail(_ failedTask: URLSessionWebSocketTask, url: URL, reason: String) {
        // 古い接続からの遅れた失敗は無視する
        guard failedTask === task else { return }
        close()
        state = .disconnected
        guard shouldRun else { return }
        let delay = min(pow(2, Double(retryCount)), Self.maxBackoff)
        retryCount += 1
        log.add("⚠️ 切断: \(reason)。\(Int(delay))秒後に再接続")
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, self.shouldRun, self.task == nil else { return }
            self.open(url)
        }
    }
}
