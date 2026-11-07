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

    @State private var scene = SkyScene()
    @State private var pull = CGSize.zero
    @State private var aimedTitle: String?
    @State private var message: String?
    @State private var sounds = Sounds()

    /// 一度に浮かべる風船の数。多すぎると空が埋まって狙いにくい
    private static let targetCount = 8

    var body: some View {
        ZStack {
            if SkyScene.isSupported {
                SkyContainer(scene: scene)
                    .ignoresSafeArea()
                crosshair
                VStack {
                    header
                    Spacer()
                    if let message {
                        Text(message)
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.regularMaterial, in: Capsule())
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
        .onDisappear { scene.stop() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("空を見上げて、風船を探そう")
                    .font(.headline)
                Text(aimedTitle.map { "狙っている風船：\($0)" } ?? "風船は、実際にある方角に浮かんでいます")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            Spacer()
            closeButton
        }
        .padding()
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 34))
                .symbolRenderingMode(.hierarchical)
        }
        .accessibilityLabel("閉じる")
    }

    private var crosshair: some View {
        Image(systemName: "plus.circle")
            .font(.system(size: 44, weight: .thin))
            .foregroundStyle(.white.opacity(aimedTitle == nil ? 0.5 : 1))
            .shadow(radius: 2)
            .allowsHitTesting(false)
    }

    /// 二股のフォークとゴム。石をつかんで引き、放すと飛ぶ
    private var slingshot: some View {
        let stone = CGPoint(x: 100 + pull.width, y: 60 + pull.height)
        return ZStack {
            Path { path in
                path.move(to: CGPoint(x: 50, y: 60))
                path.addLine(to: stone)
                path.addLine(to: CGPoint(x: 150, y: 60))
            }
            .stroke(Color.orange, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            Path { path in
                path.move(to: CGPoint(x: 100, y: 200))
                path.addLine(to: CGPoint(x: 100, y: 120))
                path.addLine(to: CGPoint(x: 50, y: 60))
                path.move(to: CGPoint(x: 100, y: 120))
                path.addLine(to: CGPoint(x: 150, y: 60))
            }
            .stroke(Color.brown, style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))
            Circle()
                .fill(.white)
                .frame(width: 30, height: 30)
                .shadow(radius: 3)
                .position(stone)
        }
        .frame(width: 200, height: 200)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    pull = Self.limited(value.translation)
                }
                .onEnded { _ in
                    scene.fire(pull: pull)
                    if hypot(pull.width, pull.height) > 20 {
                        sounds.play(.shot)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                    withAnimation(.interpolatingSpring(stiffness: 300, damping: 8)) { pull = .zero }
                }
        )
        .padding(.bottom, 8)
        .accessibilityLabel("パチンコ。下に引いて放すと、狙った方向に飛びます")
    }

    /// ゴムが伸びすぎないようにする
    private static func limited(_ translation: CGSize) -> CGSize {
        let length = hypot(translation.width, translation.height)
        let maxLength: CGFloat = 130
        guard length > maxLength else { return translation }
        return CGSize(width: translation.width / length * maxLength, height: translation.height / length * maxLength)
    }

    // MARK: - 風船の入れ替えと当たり

    private func run() async {
        guard SkyScene.isSupported else { return }
        scene.onHit = { id in Task { await hit(id) } }
        scene.onAim = { id in Task { await aim(at: id) } }
        scene.start()
        // 風船は動き続けるので、2秒ごとに浮かべる風船と方角を更新する
        while !Task.isCancelled {
            refreshTargets()
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func refreshTargets() {
        guard let here = session.location.coordinate else { return }
        let ownID = myBalloon.balloon?.id
        let targets = session.visibleBalloons
            .filter { $0.id != ownID }
            .sorted { Geo.distance(here, $0.coordinate) < Geo.distance(here, $1.coordinate) }
            .prefix(Self.targetCount)
            .map { SkyTarget(id: $0.id, trackID: $0.trackID, coordinate: $0.coordinate) }
        scene.show(Array(targets), from: here)
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
