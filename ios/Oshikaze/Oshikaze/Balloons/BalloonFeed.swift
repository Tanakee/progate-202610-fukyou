import CoreLocation
import Foundation
import Observation
import os

/// BEの `/ws`（Action Cable）で `BalloonsChannel` を購読し、地図に出す風船を保つ。
/// `balloons.snapshot` が地図の状態の正で、届くたびに、今表示している位置から届いた位置へ5秒かけて動かす。
/// 風の速さで先を予測しないのは、船に乗った風船（#30）が航路の曲がり角で陸の上を突っ切り、次の配信でワープして見えるから
@MainActor
@Observable
final class BalloonFeed {
    enum State: Equatable {
        case disconnected
        case connecting
        case subscribed
    }

    private(set) var balloons: [Balloon] = []
    private(set) var state = State.disconnected

    /// 1つの風船の、動き出した位置と行き先
    private struct Leg {
        let id: Int
        let trackID: Int
        let from: CLLocationCoordinate2D
        let to: CLLocationCoordinate2D
    }

    private struct Envelope: Decodable {
        let type: String?
        let message: BalloonsSnapshot?
    }

    private let url: URL
    private let logger = Logger(subsystem: "Oshikaze", category: "BalloonFeed")
    private var task: URLSessionWebSocketTask?
    private var lastMessageAt: Date?
    private var retryCount = 0
    private var shouldRun = false
    private var watchdog: Task<Void, Never>?
    private var ticker: Task<Void, Never>?

    private var legs: [Leg] = []
    private var legStartedAt = Date.now
    private var latestSeq = 0
    /// 回収などで消した風船と、消した時刻。届く途中の古い配信で復活させない
    private var removedAt: [Int: Date] = [:]

    /// 消した風船を無視する時間。配信は5秒ごとなので、その数回分
    private static let removalGrace: TimeInterval = 20

    private static let channelIdentifier = #"{"channel":"BalloonsChannel"}"#
    /// Action Cable は3秒ごとに ping を送るので、これだけ何も届かなければ切断とみなす
    private static let silenceLimit: TimeInterval = 10
    private static let maxBackoff: TimeInterval = 30
    private static let frameInterval: Duration = .milliseconds(50)
    /// 配信の間隔と同じだけかけて、次の位置へ動かす
    static let legDuration: TimeInterval = 5

    init(url: URL = AppConfig.webSocketURL) {
        self.url = url
    }

    /// 起動時と前面に戻ったときに呼ぶ。つながっていれば何もしない
    func start() {
        shouldRun = true
        if task == nil {
            retryCount = 0
            open()
        }
        startTicker()
    }

    func stop() {
        shouldRun = false
        close()
        ticker?.cancel()
        ticker = nil
        state = .disconnected
    }

    // MARK: - 接続

    private func open() {
        close()
        state = .connecting
        lastMessageAt = .now
        var request = URLRequest(url: url)
        request.setValue("actioncable-v1-json", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        let task = URLSession.shared.webSocketTask(with: request)
        self.task = task
        task.resume()
        logger.info("接続を開始: \(self.url.absoluteString, privacy: .public)")
        receive(on: task)
        startWatchdog(for: task)
    }

    private func close() {
        watchdog?.cancel()
        watchdog = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func receive(on task: URLSessionWebSocketTask) {
        Task { [weak self] in
            while true {
                do {
                    let message = try await task.receive()
                    self?.handle(message, on: task)
                } catch {
                    self?.fail(task, reason: error.localizedDescription)
                    return
                }
            }
        }
    }

    private func startWatchdog(for task: URLSessionWebSocketTask) {
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled, self.task === task else { return }
                // つながるまでは URLSession のタイムアウトに任せる。接続中に打ち切ると、
                // 初回のローカルネットワークの許可ダイアログなどで時間がかかったときにつながらなくなる
                guard self.state == .subscribed else { continue }
                if Date.now.timeIntervalSince(self.lastMessageAt ?? .distantPast) > Self.silenceLimit {
                    self.fail(task, reason: "pingが途切れた")
                    return
                }
            }
        }
    }

    private func fail(_ failedTask: URLSessionWebSocketTask, reason: String) {
        // 古い接続からの遅れた失敗は無視する
        guard failedTask === task else { return }
        close()
        state = .disconnected
        guard shouldRun else { return }
        let delay = min(pow(2, Double(retryCount)), Self.maxBackoff)
        retryCount += 1
        logger.info("切断: \(reason, privacy: .public)。\(delay)秒後に再接続")
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, self.shouldRun, self.task == nil else { return }
            self.open()
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message, on task: URLSessionWebSocketTask) {
        lastMessageAt = .now
        guard case .string(let text) = message else { return }
        let data = Data(text.utf8)
        // ping の message は数値なので、まず type だけを見る
        let type = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["type"] as? String
        switch type {
        case "welcome":
            logger.info("welcome を受信。購読する")
            subscribe(on: task)
        case "confirm_subscription":
            logger.info("購読済み")
            retryCount = 0
            state = .subscribed
        case "ping", "disconnect", "reject_subscription":
            break
        default:
            guard let snapshot = try? JSONDecoder().decode(Envelope.self, from: data).message,
                  snapshot.event == "balloons.snapshot" else { return }
            apply(snapshot)
        }
    }

    private func subscribe(on task: URLSessionWebSocketTask) {
        let command = ["command": "subscribe", "identifier": Self.channelIdentifier]
        guard let data = try? JSONEncoder().encode(command), let text = String(data: data, encoding: .utf8) else { return }
        task.send(.string(text)) { [weak self] error in
            guard let error else { return }
            Task { @MainActor in self?.fail(task, reason: "購読の送信に失敗: \(error.localizedDescription)") }
        }
    }

    // MARK: - 位置

    /// 回収した風船を、次の配信を待たずに地図から消す
    func remove(_ id: Int) {
        removedAt[id] = .now
        legs.removeAll { $0.id == id }
        updatePositions()
    }

    private func apply(_ snapshot: BalloonsSnapshot) {
        // 届く順が入れ替わっても、古い配信で巻き戻さない
        guard snapshot.seq >= latestSeq else { return }
        latestSeq = snapshot.seq
        removedAt = removedAt.filter { Date.now.timeIntervalSince($0.value) < Self.removalGrace }
        // 今表示している位置から動き出す。前の移動の途中で届いても、その場から向きを変える
        let shown = Dictionary(uniqueKeysWithValues: balloons.map { ($0.id, $0.coordinate) })
        legs = snapshot.balloons.compactMap { item in
            let coordinate = CLLocationCoordinate2D(latitude: item.lat, longitude: item.lng)
            guard CLLocationCoordinate2DIsValid(coordinate), removedAt[item.id] == nil else { return nil }
            // 初めて届いた風船は、届いた位置にそのまま出す
            return Leg(id: item.id, trackID: item.trackID, from: shown[item.id] ?? coordinate, to: coordinate)
        }
        legStartedAt = .now
        updatePositions()
    }

    /// from から to へ、fraction（0〜1）だけ進んだ位置。1を超えたら to で止める
    static func interpolate(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, fraction: Double) -> CLLocationCoordinate2D {
        let t = min(max(fraction, 0), 1)
        return CLLocationCoordinate2D(latitude: from.latitude + (to.latitude - from.latitude) * t,
                                      longitude: from.longitude + (to.longitude - from.longitude) * t)
    }

    private func startTicker() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.frameInterval)
                self?.updatePositions()
            }
        }
    }

    /// 届いた位置まで動いたら止めて、次の配信を待つ。配信が途切れても、BEにない場所へ流れていかない
    private func updatePositions() {
        let fraction = Date.now.timeIntervalSince(legStartedAt) / Self.legDuration
        balloons = legs.map { leg in
            Balloon(id: leg.id, trackID: leg.trackID, coordinate: Self.interpolate(from: leg.from, to: leg.to, fraction: fraction))
        }
    }
}
