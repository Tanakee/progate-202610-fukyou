import MapKit
import SwiftUI

/// 3D地図の全画面と、下部の再生バー
struct MainView: View {
    @Environment(ListeningSession.self) private var session
    @State private var position = MapCameraPosition.userLocation(
        fallback: .camera(MapCamera(centerCoordinate: .init(latitude: 36.5, longitude: 137.5), distance: 3_000_000))
    )
    @AppStorage("isListening") private var isListening = false
    @State private var hasCentered = false

    var body: some View {
        Map(position: $position) {
            UserAnnotation()
            ForEach(session.feed.balloons) { balloon in
                Annotation("", coordinate: balloon.coordinate, anchor: .bottom) {
                    BalloonMark(id: balloon.id, isPlaying: balloon.id == session.currentBalloonID)
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
            PlaybackBar(isListening: $isListening)
                .padding(.horizontal)
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
}

private struct BalloonMark: View {
    let id: Int
    let isPlaying: Bool

    private static let colors: [Color] = [.red, .orange, .yellow, .green, .mint, .teal, .cyan, .blue, .indigo, .purple, .pink]

    var body: some View {
        let color = Self.colors[id % Self.colors.count]
        VStack(spacing: 0) {
            Circle()
                .fill(color.gradient)
                .overlay(Circle().stroke(.white, lineWidth: isPlaying ? 3 : 1))
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
