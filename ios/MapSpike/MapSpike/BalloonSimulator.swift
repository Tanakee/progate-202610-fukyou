import CoreLocation
import Observation
import SwiftUI

struct Balloon: Identifiable {
    let id: Int
    let title: String
    let color: Color
    var coordinate: CLLocationCoordinate2D
    /// BEから届いた風。配信の間はこれで位置を進める
    var velocity: WindField.Velocity?
}

/// 風で風船を動かし、聴いている地点から一番近い風船を決める。
/// 端末で計算するモードと、BEの配信を受けて5秒の間だけ補間するモード（本番と同じ）を切り替えられる
@MainActor
@Observable
final class BalloonSimulator {
    enum Source: String, CaseIterable, Identifiable {
        case device = "端末で計算"
        case server = "BEの配信"
        var id: Self { self }
    }

    private(set) var balloons: [Balloon] = []
    private(set) var wind = WindField.fallback
    private(set) var windStatus = "取得中…"
    private(set) var framesPerSecond = 0.0
    private(set) var source = Source.device
    var listener = CLLocationCoordinate2D(latitude: 35.681, longitude: 139.767)
    /// 実際の風に対する倍率。設計書の「デモでは早送りする」に当たる。BEの配信中はBEの値を使う
    var speedScale = 600.0

    private let snapshotClient = SnapshotClient()
    private var serverStatus = ""
    private var lastSnapshotAt: Date?

    private static let frameInterval: Duration = .milliseconds(50)
    private static let metersPerDegree = 111_320.0
    private static let titles = ["夜明けのメロディ", "君と見た星", "サイダー", "雨上がりの坂道", "ネオンライト", "春風ステップ",
                                 "眠れない夜に", "放課後のリズム", "海辺のワルツ", "群青", "スピカ", "流れ星ダイアリー"]
    private static let colors: [Color] = [.red, .orange, .yellow, .green, .mint, .teal, .cyan, .blue, .indigo, .purple, .pink]
    private static let cities = [
        (43.06, 141.35), (38.27, 140.87), (37.92, 139.04), (36.56, 136.65), (35.68, 139.77), (35.18, 136.91),
        (34.69, 135.50), (34.40, 132.46), (33.59, 130.40), (31.60, 130.56), (26.21, 127.68), (39.72, 140.10),
    ]

    private var loop: Task<Void, Never>?
    private var frameCount = 0
    private var frameWindowStart = Date.now

    init(count: Int = 30) {
        balloons = Self.localBalloons(count: count)
        snapshotClient.onSnapshot = { [weak self] snapshot in self?.apply(snapshot) }
        snapshotClient.onStatus = { [weak self] status in
            self?.serverStatus = status
            self?.updateServerStatus()
        }
    }

    func use(_ source: Source, serverURL: String) {
        guard source != self.source else { return }
        self.source = source
        switch source {
        case .device:
            snapshotClient.disconnect()
            balloons = Self.localBalloons(count: 30)
            reloadWind()
        case .server:
            balloons = []
            lastSnapshotAt = nil
            guard let url = URL(string: serverURL) else {
                windStatus = "URLが不正: \(serverURL)"
                return
            }
            snapshotClient.connect(to: url)
        }
    }

    private func apply(_ snapshot: SnapshotClient.Snapshot) {
        speedScale = snapshot.speed_scale
        lastSnapshotAt = .now
        // 届いた位置を正として置き換える。次の配信までは ve / vn で進める。
        // 地球上にない座標は地図に置けないので捨てる（BEで旅の終わりを作る前は、日本の外へ流れ続ける）
        balloons = snapshot.balloons.compactMap { balloon in
            guard CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: balloon.lat, longitude: balloon.lng)) else { return nil }
            return Balloon(id: balloon.id,
                    title: Self.titles[balloon.track_id % Self.titles.count],
                    color: Self.colors[balloon.id % Self.colors.count],
                    coordinate: CLLocationCoordinate2D(latitude: balloon.lat, longitude: balloon.lng),
                    velocity: WindField.Velocity(east: balloon.ve, north: balloon.vn))
        }
        updateServerStatus()
    }

    private func updateServerStatus() {
        guard source == .server else { return }
        let received = lastSnapshotAt.map { "\(balloons.count)個を受信 \($0.formatted(date: .omitted, time: .standard))" } ?? "未受信"
        windStatus = "BE: \(serverStatus) / \(received)"
    }

    private static func localBalloons(count: Int) -> [Balloon] {
        (0..<count).map { id in
            Balloon(id: id,
                    title: titles[id % titles.count],
                    color: colors[id % colors.count],
                    coordinate: randomStart())
        }
    }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            await self?.loadWind()
            var last = ContinuousClock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.frameInterval)
                let now = ContinuousClock.now
                let elapsed = now - last
                last = now
                self?.step(seconds: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18)
            }
        }
    }

    func reloadWind() {
        Task { await loadWind() }
    }

    var nearest: (balloon: Balloon, kilometers: Double)? {
        let here = CLLocation(latitude: listener.latitude, longitude: listener.longitude)
        return balloons
            .map { ($0, here.distance(from: CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)) / 1000) }
            .min { $0.1 < $1.1 }
    }

    private func loadWind() async {
        guard source == .device else { return }
        windStatus = "取得中…"
        let fetched: WindField
        let status: String
        do {
            fetched = try await WindService.fetch()
            status = "Open-Meteo \(fetched.fetchedAt.formatted(date: .omitted, time: .shortened)) 取得"
        } catch {
            fetched = .fallback
            status = "取得に失敗。一様な西風で代用"
        }
        // 取得の間にBEの配信へ切り替わっていたら、表示を上書きしない
        wind = fetched
        guard source == .device else { return }
        windStatus = status
    }

    private func step(seconds: Double) {
        let dt = seconds * speedScale
        for index in balloons.indices {
            let coordinate = balloons[index].coordinate
            if source == .server {
                // 範囲外の判定と飛ばし直しはBEの仕事なので、届いた風で進めるだけにする
                if let velocity = balloons[index].velocity {
                    balloons[index].coordinate = Self.advance(coordinate, by: velocity, seconds: dt)
                }
                continue
            }
            guard let velocity = wind.velocity(at: coordinate) else {
                // 格子の外へ出たら、どこかの街から飛ばし直す（本番では割れて旅が終わる）
                balloons[index].coordinate = Self.randomStart()
                continue
            }
            balloons[index].coordinate = Self.advance(coordinate, by: velocity, seconds: dt)
        }
        countFrame()
    }

    private static func advance(_ coordinate: CLLocationCoordinate2D, by velocity: WindField.Velocity, seconds: Double) -> CLLocationCoordinate2D {
        let latitude = coordinate.latitude + velocity.north * seconds / metersPerDegree
        let longitude = coordinate.longitude
            + velocity.east * seconds / (metersPerDegree * cos(coordinate.latitude * .pi / 180))
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private func countFrame() {
        frameCount += 1
        let elapsed = Date.now.timeIntervalSince(frameWindowStart)
        if elapsed >= 1 {
            framesPerSecond = Double(frameCount) / elapsed
            frameCount = 0
            frameWindowStart = .now
        }
    }

    private static func randomStart() -> CLLocationCoordinate2D {
        let city = cities.randomElement()!
        return CLLocationCoordinate2D(latitude: city.0 + .random(in: -0.8...0.8),
                                      longitude: city.1 + .random(in: -0.8...0.8))
    }
}
