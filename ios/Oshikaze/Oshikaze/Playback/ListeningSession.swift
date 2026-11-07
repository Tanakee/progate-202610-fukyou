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

    private var loop: Task<Void, Never>?
    private var decidedAt = Date.distantPast
    private var isLoadingTrack = false

    /// 設計書の「切り替えの判定は30秒に1回」
    private static let decisionInterval: TimeInterval = 30

    init(feed: BalloonFeed, location: LocationProvider, playback: PlaybackController, tracks: TrackStore) {
        self.feed = feed
        self.location = location
        self.playback = playback
        self.tracks = tracks
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
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func decideIfNeeded() {
        retryTrackIfNeeded()
        guard let here = location.coordinate else { return }
        let currentIsGone = currentBalloonID != nil && currentBalloon == nil
        let isDue = Date.now.timeIntervalSince(decidedAt) >= Self.decisionInterval
        // 何も流していない、または流していた風船が消えたときは、30秒を待たずに選び直す
        guard currentBalloonID == nil || currentIsGone || isDue else { return }

        decidedAt = .now
        let picked = NearestBalloonPicker.pick(from: feed.balloons, at: here, current: currentIsGone ? nil : currentBalloonID)
        guard picked != currentBalloonID || currentIsGone else { return }
        currentBalloonID = picked
        currentTrack = nil
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

    /// 曲の取得に失敗していたら、無音で待ちつつ取り直す
    private func retryTrackIfNeeded() {
        guard currentTrack == nil, !isLoadingTrack, let balloon = currentBalloon else { return }
        Task { await loadTrack(for: balloon) }
    }
}
