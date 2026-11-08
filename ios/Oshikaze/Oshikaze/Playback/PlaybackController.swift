import AVFoundation
import MediaPlayer
import Observation
import os

/// 流す曲をフェードで切り替え、同じ曲が終わればループする。
/// 流す風船がないときは無音ループを鳴らし、バックグラウンドでもアプリと通信を止めない（#9 で確認済み）
@MainActor
@Observable
final class PlaybackController {
    /// 利用者が「流す」をONにしているか
    private(set) var isListening = false
    /// 鳴らしている曲。nil なら無音ループ
    private(set) var nowPlaying: Track?

    private struct Channel {
        let player: AVQueuePlayer
        let looper: AVPlayerLooper
        let track: Track?
    }

    private var channel: Channel?
    /// 次に流しそうな曲。先に読み始めておき、乗り換えたときにそのまま使う
    private var preloaded: AVURLAsset?
    /// 流したい曲。流すがOFFの間も覚えておき、ONにしたら鳴らす
    private var desired: Track?
    private var hasDesired = false
    private var observers: [NSObjectProtocol] = []
    private let logger = Logger(subsystem: "Oshikaze", category: "Playback")

    private static let fadeDuration = 1.5
    private static let fadeSteps = 15
    private static let silenceURL = Bundle.main.url(forResource: "silence", withExtension: "mp3")!

    init() {
        observeSession()
        setUpRemoteCommands()
    }

    func setListening(_ listening: Bool) {
        guard listening != isListening else { return }
        isListening = listening
        if listening {
            guard activateSession() else {
                isListening = false
                return
            }
            if let channel {
                channel.player.play()
            } else {
                switchTo(desired)
            }
        } else {
            channel?.player.pause()
        }
    }

    /// その曲が実際に鳴っているか。流すがOFFのときや、読み込み中は false
    func isPlaying(_ track: Track) -> Bool {
        guard isListening, let channel, channel.track == track else { return false }
        return channel.player.timeControlStatus == .playing
    }

    /// 流す曲を変える。nil を渡すと無音ループにする
    func play(_ track: Track?) {
        guard !hasDesired || track != desired else { return }
        desired = track
        hasDesired = true
        guard isListening else { return }
        switchTo(track)
    }

    /// 次に流しそうな曲の先頭を読んでおく。乗り換えたとき、つなぐところから始めずに済む
    func preload(_ track: Track) {
        guard preloaded?.url != track.mp3URL, channel?.track != track else { return }
        let asset = AVURLAsset(url: track.mp3URL)
        preloaded = asset
        Task { _ = try? await asset.load(.isPlayable, .duration) }
    }

    private func switchTo(_ track: Track?) {
        guard let item = makeItem(track) else { return }
        let player = AVQueuePlayer()
        // 既定の true にしないのは、途切れないだけ溜まるまで待つので、鳴り始めが遅れるから。
        // mp3 は先頭の数十KBで鳴らせるので、届いた分からすぐ鳴らす
        player.automaticallyWaitsToMinimizeStalling = false
        player.volume = 0
        let next = Channel(player: player, looper: AVPlayerLooper(player: player, templateItem: item), track: track)
        let previous = channel
        channel = next
        nowPlaying = track
        player.play()
        updateNowPlayingInfo()
        fade(next.player, to: 1)
        if let previous {
            fade(previous.player, to: 0) { previous.player.pause() }
        }
    }

    private func makeItem(_ track: Track?) -> AVPlayerItem? {
        guard let track else { return AVPlayerItem(url: Self.silenceURL) }
        if let preloaded, preloaded.url == track.mp3URL {
            self.preloaded = nil
            return AVPlayerItem(asset: preloaded)
        }
        return AVPlayerItem(url: track.mp3URL)
    }

    private func fade(_ player: AVPlayer, to target: Float, completion: (() -> Void)? = nil) {
        let start = player.volume
        Task {
            for step in 1...Self.fadeSteps {
                try? await Task.sleep(for: .seconds(Self.fadeDuration / Double(Self.fadeSteps)))
                player.volume = start + (target - start) * Float(step) / Float(Self.fadeSteps)
            }
            completion?()
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
            logger.error("オーディオセッションを有効にできない: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - 中断と経路の変化

    private func observeSession() {
        let center = NotificationCenter.default
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

    /// 着信などの割り込みは、終わったら再開する
    private func handleInterruption(_ type: AVAudioSession.InterruptionType?, options: AVAudioSession.InterruptionOptions) {
        guard type == .ended, options.contains(.shouldResume), isListening else { return }
        activateSession()
        channel?.player.play()
    }

    /// イヤホンが外れたら一時停止する。再開はアプリかロック画面の操作で行う
    private func handleRouteChange(_ reason: AVAudioSession.RouteChangeReason?) {
        guard reason == .oldDeviceUnavailable else { return }
        setListening(false)
    }

    private func setUpRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.setListening(true) }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.setListening(false) }
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: nowPlaying?.title ?? "近くに風船がありません",
            MPMediaItemPropertyArtist: nowPlaying?.artist ?? "推し風",
        ]
    }
}
