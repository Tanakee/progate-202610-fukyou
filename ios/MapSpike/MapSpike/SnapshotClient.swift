import Foundation

/// BEの `/ws`（Action Cable）に匿名で接続し、`balloons.snapshot` を受け取る。
/// 形式は docs/api.md の WebSocket の節（PR #15 の時点）に合わせている
@MainActor
final class SnapshotClient {
    struct Snapshot: Decodable {
        struct Balloon: Decodable {
            let id: Int
            let track_id: Int
            let lat: Double
            let lng: Double
            let ve: Double
            let vn: Double
        }

        let event: String
        let seq: Int
        let speed_scale: Double
        let balloons: [Balloon]
    }

    private struct Envelope: Decodable {
        let type: String?
        let message: Snapshot?
    }

    var onSnapshot: ((Snapshot) -> Void)?
    var onStatus: ((String) -> Void)?

    private var task: URLSessionWebSocketTask?
    private var url: URL?
    private var retryCount = 0
    private static let identifier = #"{"channel":"BalloonsChannel"}"#

    func connect(to url: URL) {
        self.url = url
        retryCount = 0
        open()
    }

    func disconnect() {
        url = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func open() {
        guard let url else { return }
        var request = URLRequest(url: url)
        request.setValue("actioncable-v1-json", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        let task = URLSession.shared.webSocketTask(with: request)
        self.task = task
        task.resume()
        onStatus?("接続中…")
        Task { [weak self] in
            while true {
                do {
                    let message = try await task.receive()
                    self?.handle(message, on: task)
                } catch {
                    self?.reconnect(after: task, reason: error.localizedDescription)
                    return
                }
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message, on task: URLSessionWebSocketTask) {
        guard case .string(let text) = message,
              let envelope = try? JSONDecoder().decode(Envelope.self, from: Data(text.utf8)) else { return }
        switch envelope.type {
        case "welcome":
            let subscribe = ["command": "subscribe", "identifier": Self.identifier]
            if let data = try? JSONEncoder().encode(subscribe), let text = String(data: data, encoding: .utf8) {
                task.send(.string(text)) { _ in }
            }
        case "confirm_subscription":
            retryCount = 0
            onStatus?("購読済み")
        default:
            if let snapshot = envelope.message, snapshot.event == "balloons.snapshot" {
                onSnapshot?(snapshot)
            }
        }
    }

    private func reconnect(after failedTask: URLSessionWebSocketTask, reason: String) {
        guard failedTask === task, url != nil else { return }
        task = nil
        let delay = min(pow(2, Double(retryCount)), 30)
        retryCount += 1
        onStatus?("切断: \(reason)。\(Int(delay))秒後に再接続")
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, self.task == nil else { return }
            self.open()
        }
    }
}
