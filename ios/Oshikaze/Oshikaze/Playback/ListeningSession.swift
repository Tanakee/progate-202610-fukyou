import CoreLocation
import Foundation
import Observation

/// 現在地と配信された風船から流す風船を決め、その曲を鳴らす
@MainActor
@Observable
final class ListeningSession {
    /// 流している風船のID
    private(set) var currentBalloonID: Int?
    /// 流している風船の曲。取得できるまでは nil
    private(set) var currentTrack: Track?

    let feed: BalloonFeed
    let location: LocationProvider
    let playback: PlaybackController
    let tracks: TrackStore
    let auth: AuthStore
    let myBalloon: MyBalloonStore
    let pops: PopStore

    private var loop: Task<Void, Never>?
    private var decidedAt = Date.distantPast
    private var isLoadingTrack = false
    /// 流している風船を実際に再生できた秒数
    private var playedSeconds = 0
    /// 回数を送り終えた風船。同じ人は同じ風船で1回まで
    private var reportedBalloonIDs: Set<Int> = []
    private var isReporting = false

    /// 設計書の「切り替えの判定は30秒に1回」
    private static let decisionInterval: TimeInterval = 30
    /// 設計書の「再生開始から5秒で1回」
    private static let secondsToCountPlay = 5

    init(feed: BalloonFeed, location: LocationProvider, playback: PlaybackController, tracks: TrackStore,
         auth: AuthStore, myBalloon: MyBalloonStore, pops: PopStore) {
        self.feed = feed
        self.location = location
        self.playback = playback
        self.tracks = tracks
        self.auth = auth
        self.myBalloon = myBalloon
        self.pops = pops
    }

    /// 流さない風船。自分の風船と割った風船は流さない
    private var excludedBalloonIDs: Set<Int> {
        pops.poppedIDs.union(myBalloon.balloon.map { [$0.id] } ?? [])
    }

    /// 自分の世界に見えている風船。割った風船は地図にも出さない
    var visibleBalloons: [Balloon] {
        feed.balloons.filter { !pops.poppedIDs.contains($0.id) }
    }

    var currentBalloon: Balloon? {
        feed.balloons.first { $0.id == currentBalloonID }
    }

    /// 流している風船までの距離（m）
    var currentDistance: CLLocationDistance? {
        guard let balloon = currentBalloon, let here = location.coordinate else { return nil }
        return Geo.distance(here, balloon.coordinate)
    }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                self?.decideIfNeeded()
                self?.countPlay()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func decideIfNeeded() {
        retryTrackIfNeeded()
        guard let here = location.coordinate else { return }
        // 流していた風船が消えた、または自分で飛ばした風船だったときは、30秒を待たずに選び直す
        let currentIsGone = currentBalloonID.map { id in currentBalloon == nil || excludedBalloonIDs.contains(id) } ?? false
        let isDue = Date.now.timeIntervalSince(decidedAt) >= Self.decisionInterval
        guard currentBalloonID == nil || currentIsGone || isDue else { return }

        decidedAt = .now
        let picked = NearestBalloonPicker.pick(from: feed.balloons, at: here,
                                               current: currentIsGone ? nil : currentBalloonID,
                                               excluded: excludedBalloonIDs)
        guard picked != currentBalloonID || currentIsGone else { return }
        currentBalloonID = picked
        currentTrack = nil
        playedSeconds = 0
        guard let balloon = currentBalloon else {
            playback.play(nil)
            return
        }
        Task { await loadTrack(for: balloon) }
    }

    /// 曲を取ってから流す。取っている間に別の風船へ乗り換えていたら、何もしない
    private func loadTrack(for balloon: Balloon) async {
        isLoadingTrack = true
        defer { isLoadingTrack = false }
        let track = await tracks.track(id: balloon.trackID)
        guard currentBalloonID == balloon.id else { return }
        currentTrack = track
        playback.play(track)
    }

    /// 流している風船を今日の1曲として回収する。回収した風船はみんなの空から消えるので、すぐ次の風船へ乗り換える
    @discardableResult
    func collectCurrent() async throws -> Favorite? {
        guard let balloonID = currentBalloonID else { return nil }
        do {
            let favorite: Favorite = try await auth.client.send(.post, "balloons/\(balloonID)/collect")
            feed.remove(balloonID)
            decidedAt = .distantPast
            return favorite
        } catch let error as APIError where error.status == 409 {
            // 先に誰かが回収したか、旅が終わっていた。地図からも消しておく
            feed.remove(balloonID)
            decidedAt = .distantPast
            throw error
        } catch {
            auth.handle(error)
            throw error
        }
    }

    /// 曲の取得に失敗していたら、無音で待ちつつ取り直す
    private func retryTrackIfNeeded() {
        guard currentTrack == nil, !isLoadingTrack, let balloon = currentBalloon else { return }
        Task { await loadTrack(for: balloon) }
    }

    /// 実際に鳴っている秒数を数え、5秒になったら回数を送る。失敗したら次の秒に送り直す
    private func countPlay() {
        guard let balloonID = currentBalloonID, let track = currentTrack, playback.isPlaying(track) else { return }
        playedSeconds += 1
        guard playedSeconds >= Self.secondsToCountPlay,
              !reportedBalloonIDs.contains(balloonID), !isReporting, auth.isSignedIn else { return }
        isReporting = true
        Task {
            defer { isReporting = false }
            do {
                // 応答は `{play_count}` だが、聴く側では使わない
                try await auth.client.send(.post, "balloons/\(balloonID)/plays")
                reportedBalloonIDs.insert(balloonID)
            } catch {
                auth.handle(error)
            }
        }
    }
}
