import MapKit
import SwiftUI

/// 3D地図の全画面と、下部の再生バー
struct MainView: View {
    @Environment(ListeningSession.self) private var session
    @Environment(AuthStore.self) private var auth
    @Environment(MyBalloonStore.self) private var myBalloon
    @State private var position = MapCameraPosition.userLocation(
        fallback: .camera(MapCamera(centerCoordinate: .init(latitude: 36.5, longitude: 137.5), distance: 3_000_000))
    )
    @AppStorage("isListening") private var isListening = false
    @State private var hasCentered = false
    @State private var showsAccount = false
    @State private var showsLaunch = false
    @State private var confirmsCollect = false
    @State private var collectMessage: String?

    /// 設計書の「前面にある間は30秒ごとに /me/balloons を読む」
    private static let myBalloonRefreshInterval: Duration = .seconds(30)

    var body: some View {
        Map(position: $position) {
            UserAnnotation()
            ForEach(session.feed.balloons) { balloon in
                Annotation("", coordinate: balloon.coordinate, anchor: .bottom) {
                    BalloonMark(id: balloon.id,
                                isPlaying: balloon.id == session.currentBalloonID,
                                isMine: balloon.id == myBalloon.balloon?.id)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapPitchToggle()
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .trailing, spacing: 12) {
                LaunchButton(balloon: myBalloon.balloon) {
                    if let balloon = myBalloon.balloon {
                        showMyBalloon(balloon)
                    } else {
                        showsLaunch = true
                    }
                }
                PlaybackBar(isListening: $isListening) {
                    if auth.isSignedIn {
                        confirmsCollect = true
                    } else {
                        showsAccount = true
                    }
                }
            }
            .padding(.horizontal)
        }
        .confirmationDialog("この曲を今日の1曲として回収しますか？", isPresented: $confirmsCollect, titleVisibility: .visible) {
            Button("回収する") {
                Task { await collect() }
            }
        } message: {
            Text("回収は1日1回です。回収した風船はみんなの空から消え、お気に入りに残ります。")
        }
        .alert(collectMessage ?? "", isPresented: Binding(get: { collectMessage != nil }, set: { if !$0 { collectMessage = nil } })) {
            Button("OK") {}
        }
        .sheet(isPresented: $showsLaunch) {
            LaunchSheet()
        }
        .task(id: auth.token) {
            // ログインとログアウトのたびに読み直し、その後は30秒ごとに回数を更新する
            while !Task.isCancelled {
                await myBalloon.refresh(with: auth)
                try? await Task.sleep(for: Self.myBalloonRefreshInterval)
            }
        }
        .overlay(alignment: .topLeading) {
            Button {
                showsAccount = true
            } label: {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 36))
                    .symbolRenderingMode(.hierarchical)
                    .padding(8)
                    .background(.regularMaterial, in: Circle())
            }
            .accessibilityLabel("自分の曲")
            .padding(.leading)
        }
        .sheet(isPresented: $showsAccount) {
            AccountSheet()
        }
        .overlay {
            if session.location.isDenied {
                LocationDeniedView()
            }
        }
        .onChange(of: session.location.coordinate == nil) { _, _ in
            // 最初に現在地が取れたら、周りの風船が入るくらいまで引いて傾ける。
            // userLocation のままだと街の中まで寄ってしまい、数十km先の風船が見えない
            guard !hasCentered, let here = session.location.coordinate else { return }
            hasCentered = true
            withAnimation(.easeInOut(duration: 1.5)) {
                position = .camera(MapCamera(centerCoordinate: here, distance: 400_000, heading: 0, pitch: 50))
            }
        }
        .onChange(of: isListening, initial: true) { _, listening in
            session.playback.setListening(listening)
        }
        .onChange(of: session.playback.isListening) { _, listening in
            // イヤホンが外れたときやロック画面の操作を、ボタンの表示にも反映する
            isListening = listening
        }
    }

    private func collect() async {
        do {
            if let favorite = try await session.collectCurrent() {
                collectMessage = "「\(favorite.track.title)」を回収しました"
            }
        } catch {
            collectMessage = error.localizedDescription
        }
    }

    /// 自分の風船へ地図を寄せる。地図の主役は利用者なので、ボタンを押したときだけ寄せる。
    /// 配信の位置があればそちらを使う（/me/balloons より新しい）
    private func showMyBalloon(_ balloon: MyBalloon) {
        let coordinate = session.feed.balloons.first { $0.id == balloon.id }?.coordinate ?? balloon.coordinate
        withAnimation(.easeInOut(duration: 1.5)) {
            position = .camera(MapCamera(centerCoordinate: coordinate, distance: 80_000, heading: 0, pitch: 55))
        }
    }
}

/// 飛ばすボタン。飛行中は「🎈 12回」のように聴かれた回数を出し、押すと自分の風船へ移動する
private struct LaunchButton: View {
    let balloon: MyBalloon?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(balloon.map { "\($0.playCount)回" } ?? "飛ばす")
                    .font(.headline)
                    .monospacedDigit()
            } icon: {
                Text("🎈")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
        }
        .accessibilityLabel(balloon.map { "自分の風船。\($0.playCount)回聴かれました" } ?? "風船を飛ばす")
    }
}

private struct BalloonMark: View {
    let id: Int
    let isPlaying: Bool
    let isMine: Bool

    private static let colors: [Color] = [.red, .orange, .yellow, .green, .mint, .teal, .cyan, .blue, .indigo, .purple, .pink]

    var body: some View {
        let color = Self.colors[id % Self.colors.count]
        VStack(spacing: 0) {
            Circle()
                .fill(color.gradient)
                .overlay(Circle().stroke(isMine ? .yellow : .white, lineWidth: isPlaying || isMine ? 3 : 1))
                .overlay { if isMine { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.white) } }
                .frame(width: isPlaying ? 32 : 18, height: isPlaying ? 32 : 18)
                .shadow(color: isPlaying ? color : .black.opacity(0.3), radius: isPlaying ? 8 : 2)
            Rectangle()
                .fill(.secondary)
                .frame(width: 1, height: isPlaying ? 14 : 8)
        }
        .animation(.spring, value: isPlaying)
    }
}

private struct PlaybackBar: View {
    @Environment(ListeningSession.self) private var session
    @Binding var isListening: Bool
    let onCollect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(action: onCollect) {
                Image(systemName: "heart.circle")
                    .font(.system(size: 36))
            }
            .disabled(session.currentTrack == nil)
            .accessibilityLabel("この曲を回収する")
            Button {
                isListening.toggle()
            } label: {
                Image(systemName: isListening ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 44))
            }
            .accessibilityLabel(isListening ? "止める" : "流す")
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var title: String {
        if let track = session.currentTrack { return track.title }
        if session.currentBalloonID != nil { return "曲を読み込んでいます" }
        return session.feed.balloons.isEmpty ? "近くに風船がありません" : "風船を探しています"
    }

    private var subtitle: String {
        switch session.feed.state {
        case .disconnected: return "サーバーに再接続しています"
        case .connecting: return "サーバーに接続しています"
        case .subscribed: break
        }
        guard let track = session.currentTrack else { return "\(session.feed.balloons.count)個の風船が飛んでいます" }
        guard let meters = session.currentDistance else { return track.artist }
        return "\(track.artist)・\(Self.formatDistance(meters))先の風船"
    }

    private static func formatDistance(_ meters: Double) -> String {
        meters < 1000 ? "\(Int(meters))m" : String(format: "%.0fkm", meters / 1000)
    }
}

private struct LocationDeniedView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "location.slash.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("位置情報をオンにしてください")
                .font(.title3.bold())
            Text("近くを漂う風船の曲を流すために、現在地を使います。現在地はサーバーへ送りません。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("設定を開く") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }
}
