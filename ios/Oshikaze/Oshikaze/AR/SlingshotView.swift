import AVFoundation
import RealityKit
import SwiftUI

/// 空を見上げて、気に入った曲の風船をパチンコで割り、お気に入りにする画面
struct SlingshotView: View {
    @Environment(ListeningSession.self) private var session
    @Environment(MyBalloonStore.self) private var myBalloon
    @Environment(AuthStore.self) private var auth
    @Environment(TrackStore.self) private var tracks
    @Environment(\.dismiss) private var dismiss

    /// 画面を開いたときに1回だけ作る。地図は毎秒何度も描き直されるので、
    /// ここで `= SkyScene()` と書くと、描き直しのたびに AR の部品を作っては捨ててしまう
    @State private var scene: SkyScene?
    @State private var aimedTitle: String?
    @State private var message: String?
    @State private var sounds = Sounds()
    /// 命中してからAPIの結果が返るまで、2秒ごとの更新で同じ風船を作り直さない
    @State private var hiddenTargetIDs: Set<Int> = []
    @State private var todaysFavorite: Favorite?

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
        // パチンコを引く操作を、下の端のiOSの操作（簡易アクセスやホームへ戻る）より先に受け付ける
        .defersSystemGestures(on: .bottom)
        .persistentSystemOverlays(.hidden)
        .task { await run() }
        .task { await loadTodaysFavorite() }
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
                    Text("気に入った曲の風船を狙おう")
                        .font(Theme.font(16, .bold, relativeTo: .headline))
                }
                Text(todaysFavorite.map { "今日はもう「\($0.track.title)」をお気に入りにしています" }
                     ?? "割ると今日のお気に入りになります（1日1回）")
                    .font(Theme.font(13, .bold, relativeTo: .subheadline))
                    .foregroundStyle(Theme.heart)
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
        // 画面の下の端から離して、簡易アクセス（下の端を下になぞると画面全体が降りる）と重ならないようにする
        .padding(.bottom, 56)
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
        var balloons = session.feed.balloons
            .filter { $0.id != ownID && !hiddenTargetIDs.contains($0.id) }
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
        guard hiddenTargetIDs.insert(id).inserted else { return }
        sounds.play(.pop)
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        let title = await trackTitle(of: id)
        do {
            todaysFavorite = try await session.collect(balloonID: id)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.spring) {
                message = title.map { "「\($0)」をお気に入りにしました！" } ?? "お気に入りにしました！"
            }
        } catch {
            // 1日1回の制限や未ログインなら、風船を空へ戻してもう一度見られるようにする
            hiddenTargetIDs.remove(id)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            withAnimation(.spring) { message = error.localizedDescription }
        }
        try? await Task.sleep(for: .seconds(2))
        withAnimation { message = nil }
    }

    private func loadTodaysFavorite() async {
        guard auth.isSignedIn else { return }
        do {
            let favorites: [Favorite] = try await auth.client.send(.get, "me/favorites")
            // 端末のタイムゾーンで今日を決めないのは、1日1回の区切りがサーバーの日本時間の0時だから
            let today = Date.now.formatted(Date.ISO8601FormatStyle(timeZone: TimeZone(identifier: "Asia/Tokyo")!).year().month().day())
            todaysFavorite = favorites.first { $0.collectedOn == today }
        } catch {
            auth.handle(error)
        }
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
