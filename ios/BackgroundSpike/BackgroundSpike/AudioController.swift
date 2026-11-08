import AVFoundation
import MediaPlayer
import Observation

/// 2曲の連続再生と無音ループを鳴らし、終了・中断・経路変更をログに残す。
@MainActor
@Observable
final class AudioController {
    private(set) var nowPlaying = "—"
    private(set) var isPlaying = false

    private let log: EventLog
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var observers: [NSObjectProtocol] = []
    private var currentItemObservation: NSKeyValueObservation?
    private var statusObservation: NSKeyValueObservation?

    private static let tracks = ["track1", "track2"]

    init(log: EventLog) {
        self.log = log
        observeSession()
        setUpRemoteCommands()
    }

    /// 1曲目、2曲目と続けて流し、2曲目が終わったら同じ曲をループする（最寄りが変わらない場合の挙動）
    func playTracks() {
        stop()
        guard activateSession() else { return }
        let queue = AVQueuePlayer(items: Self.tracks.compactMap(Self.makeItem))
        start(queue)
        log.add("再生開始: 2曲を連続再生")
    }

    /// 風船が0個のときの無音ループ
    func playSilence() {
        stop()
        guard activateSession(), let item = Self.makeItem("silence") else { return }
        let queue = AVQueuePlayer()
        looper = AVPlayerLooper(player: queue, templateItem: item)
        start(queue)
        log.add("再生開始: 無音ループ")
    }

    func resume() {
        guard let player else { return }
        guard activateSession() else { return }
        player.play()
    }

    func pause() {
        player?.pause()
    }

    func stop() {
        guard let player else { return }
        player.pause()
        looper = nil
        currentItemObservation = nil
        statusObservation = nil
        self.player = nil
        nowPlaying = "—"
        isPlaying = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        log.add("再生停止")
    }

    private func start(_ queue: AVQueuePlayer) {
        player = queue
        currentItemObservation = queue.observe(\.currentItem, options: [.new]) { [weak self] player, _ in
            MainActor.assumeIsolated {
                let name = player.currentItem.map { Self.name(of: $0) } ?? "—"
                self?.currentItemChanged(to: name)
            }
        }
        statusObservation = queue.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            MainActor.assumeIsolated { self?.timeControlStatusChanged(to: status) }
        }
        queue.play()
    }

    private func currentItemChanged(to name: String) {
        nowPlaying = name
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: name,
            MPMediaItemPropertyArtist: "BG検証",
        ]
    }

    private func timeControlStatusChanged(to status: AVPlayer.TimeControlStatus) {
        let playing = status == .playing
        guard playing != isPlaying else { return }
        isPlaying = playing
        log.add(playing ? "状態: 再生中" : "状態: 一時停止")
    }

    private func itemDidPlayToEnd(_ item: AVPlayerItem) {
        guard let player, player.items().contains(item) else { return }
        let name = Self.name(of: item)
        log.add("曲の終了: \(name)")
        if looper == nil, name == Self.tracks.last, let next = Self.makeItem(name) {
            player.insert(next, after: nil)
            log.add("同じ曲をループ: \(name)")
        }
    }

    @discardableResult
    private func activateSession() -> Bool {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            return true
        } catch {
            log.add("⚠️ オーディオセッションを有効にできない: \(error.localizedDescription)")
            return false
        }
    }

    private func observeSession() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] notification in
            guard let item = notification.object as? AVPlayerItem else { return }
            MainActor.assumeIsolated { self?.itemDidPlayToEnd(item) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            let info = notification.userInfo ?? [:]
            let type = (info[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            let options = AVAudioSession.InterruptionOptions(rawValue: info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            MainActor.assumeIsolated { self?.handleInterruption(type, options: options) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
            let reason = AVAudioSession.RouteChangeReason(rawValue: raw)
            MainActor.assumeIsolated { self?.handleRouteChange(reason) }
        })
    }

    private func handleInterruption(_ type: AVAudioSession.InterruptionType?, options: AVAudioSession.InterruptionOptions) {
        switch type {
        case .began:
            log.add("中断の開始（着信など）")
        case .ended:
            if options.contains(.shouldResume) {
                log.add("中断の終了: 再開する")
                resume()
            } else {
                log.add("中断の終了: 再開の指示なし")
            }
        default:
            break
        }
    }

    private func handleRouteChange(_ reason: AVAudioSession.RouteChangeReason?) {
        switch reason {
        case .oldDeviceUnavailable:
            // AVPlayerは自動で止まるが、念のため明示的に止める
            player?.pause()
            log.add("イヤホンが外れた: 一時停止")
        case .newDeviceAvailable:
            log.add("イヤホンがつながった")
        default:
            break
        }
    }

    private func setUpRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                self?.log.add("ロック画面から再開")
                self?.resume()
            }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                self?.log.add("ロック画面から一時停止")
                self?.pause()
            }
            return .success
        }
    }

    private nonisolated static func makeItem(_ name: String) -> AVPlayerItem? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp3") else { return nil }
        return AVPlayerItem(url: url)
    }

    private static func name(of item: AVPlayerItem) -> String {
        ((item.asset as? AVURLAsset)?.url.deletingPathExtension().lastPathComponent) ?? "不明"
    }
}
