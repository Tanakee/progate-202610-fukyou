import AVFoundation
import RealityKit
import SwiftUI

/// 空を見上げて、浮かぶ風船をパチンコで割る画面
struct SlingshotView: View {
    @Environment(ListeningSession.self) private var session
    @Environment(MyBalloonStore.self) private var myBalloon
    @Environment(PopStore.self) private var pops
    @Environment(AuthStore.self) private var auth
    @Environment(TrackStore.self) private var tracks
    @Environment(\.dismiss) private var dismiss

    /// 画面を開いたときに1回だけ作る。地図は毎秒何度も描き直されるので、
    /// ここで `= SkyScene()` と書くと、描き直しのたびに AR の部品を作っては捨ててしまう
    @State private var scene: SkyScene?
    @State private var aimedTitle: String?
    @State private var message: String?
    @State private var sounds = Sounds()

    /// 一度に浮かべる風船の数。多すぎると空が埋まって狙いにくい
    private static let targetCount = 8

    var body: some View {
        ZStack {
            if SkyScene.isSupported {
                if let scene {
                    SkyContainer(scene: scene)
                        .ignoresSafeArea()
                }
                crosshair
                VStack {
                    header
                    Spacer()
                    if let message {
                        Text(message)
                            .font(Theme.font(16, .bold, relativeTo: .headline))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 11)
                            .softCard(tint: Theme.heart, cornerRadius: 22)
                            .transition(.scale.combined(with: .opacity))
                    }
                    slingshot
                }
            } else {
                ContentUnavailableView("この端末ではARが使えません", systemImage: "arkit",
                                       description: Text("カメラのあるiPhoneで試してください。"))
                    .overlay(alignment: .topTrailing) { closeButton.padding() }
            }
        }
        .task { await run() }
        .onDisappear { scene?.stop() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                if let playing = listeningTrack {
                    Label("今聴いている：\(playing.title)", systemImage: "music.note")
                        .font(Theme.font(16, .bold, relativeTo: .headline))
                        .lineLimit(1)
                    Text("♪ の付いた、光っている風船です")
                        .font(Theme.font(13, relativeTo: .subheadline))
                        .foregroundStyle(Theme.ink.opacity(0.6))
                } else {
                    Text("空を見上げて、風船を探そう")
                        .font(Theme.font(16, .bold, relativeTo: .headline))
                }
                Text(aimedTitle.map { "狙っている風船：\($0)" } ?? "風船は、実際にある方角に浮かんでいます")
                    .font(Theme.font(13, relativeTo: .subheadline))
                    .foregroundStyle(Theme.ink.opacity(0.6))
            }
            .foregroundStyle(Theme.ink)
            .padding(14)
            .softCard(cornerRadius: 22)
            Spacer()
            closeButton
        }
        .padding()
    }

    /// 実際に流している曲。止めている間は、どの風船も「今聴いている」にしない
    private var listeningTrack: Track? {
        session.playback.isListening ? session.currentTrack : nil
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            RoundIcon(systemName: "xmark", size: 44, color: Theme.ink)
        }
        .buttonStyle(.bouncy)
        .accessibilityLabel("閉じる")
    }

    private var crosshair: some View {
        Image(systemName: "plus.circle")
            .font(.system(size: 44, weight: .thin))
            .foregroundStyle(.white.opacity(aimedTitle == nil ? 0.5 : 1))
            .shadow(radius: 2)
            .allowsHitTesting(false)
    }

    /// 画面下のパチンコ。放すと弾が飛ぶ
    private var slingshot: some View {
        SlingshotPad { pull in
            scene?.fire(pull: pull)
            if hypot(pull.width, pull.height) > 20 {
                sounds.play(.shot)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
        .padding(.bottom, 16)
    }

    // MARK: - 風船の入れ替えと当たり

    private func run() async {
        guard SkyScene.isSupported else { return }
        let scene = SkyScene()
        scene.onHit = { id in Task { await hit(id) } }
        scene.onAim = { id in Task { await aim(at: id) } }
        scene.start()
        self.scene = scene
        // 風船は動き続けるので、2秒ごとに浮かべる風船と方角を更新する
        while !Task.isCancelled {
            refreshTargets(in: scene)
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func refreshTargets(in scene: SkyScene) {
        guard let here = session.location.coordinate else { return }
        let ownID = myBalloon.balloon?.id
        let playingID = listeningTrack == nil ? nil : session.currentBalloonID
        var balloons = session.visibleBalloons
            .filter { $0.id != ownID }
            .sorted { Geo.distance(here, $0.coordinate) < Geo.distance(here, $1.coordinate) }
        // 今聴いている風船は、近い8個に入っていなくても必ず浮かべる
        var nearest = Array(balloons.prefix(Self.targetCount))
        if let playingID, !nearest.contains(where: { $0.id == playingID }),
           let playing = balloons.first(where: { $0.id == playingID }) {
            nearest[nearest.count - 1] = playing
        }
        balloons = nearest
        let targets = balloons.map { SkyTarget(id: $0.id, trackID: $0.trackID, coordinate: $0.coordinate) }
        scene.show(targets, from: here, playingID: playingID)
    }

    private func hit(_ id: Int) async {
        sounds.play(.pop)
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        let title = await trackTitle(of: id)
        withAnimation(.spring) { message = title.map { "「\($0)」の風船を割りました" } ?? "風船を割りました" }
        await pops.pop(id, with: auth)
        try? await Task.sleep(for: .seconds(2))
        withAnimation { message = nil }
    }

    private func aim(at id: Int?) async {
        guard let id else {
            aimedTitle = nil
            return
        }
        aimedTitle = await trackTitle(of: id) ?? "曲を読み込んでいます"
    }

    private func trackTitle(of balloonID: Int) async -> String? {
        guard let balloon = session.feed.balloons.first(where: { $0.id == balloonID }) else { return nil }
        return await tracks.track(id: balloon.trackID)?.title
    }
}

/// ARView を SwiftUI に置く
private struct SkyContainer: UIViewRepresentable {
    let scene: SkyScene

    func makeUIView(context: Context) -> ARView { scene.arView }
    func updateUIView(_ uiView: ARView, context: Context) {}
}

/// パチンコの効果音。地図の曲と重なっても鳴るよう、別のプレイヤーで鳴らす
@MainActor
private final class Sounds {
    enum Effect: String {
        case shot, pop
    }

    private var players: [Effect: AVAudioPlayer] = [:]

    func play(_ effect: Effect) {
        if players[effect] == nil, let url = Bundle.main.url(forResource: effect.rawValue, withExtension: "mp3") {
            players[effect] = try? AVAudioPlayer(contentsOf: url)
        }
        players[effect]?.currentTime = 0
        players[effect]?.play()
    }
}
