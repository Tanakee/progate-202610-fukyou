import Observation

/// ログ、再生、通信をまとめ、受信した合図を通知へつなぐ。
@MainActor
@Observable
final class SpikeModel {
    let log = EventLog()
    let audio: AudioController
    let socket: SocketClient

    init() {
        audio = AudioController(log: log)
        socket = SocketClient(log: log)
        socket.onNotify = { [weak self] text in
            self?.postNotification(text)
        }
    }

    private func postNotification(_ text: String) {
        Task {
            do {
                try await Notifier.post(title: "推し風 BG検証", body: text)
                log.add("通知を出した: \(text)")
            } catch {
                log.add("⚠️ 通知を出せない: \(error.localizedDescription)")
            }
        }
    }
}
