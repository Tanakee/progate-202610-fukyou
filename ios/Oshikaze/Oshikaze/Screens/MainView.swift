import MapKit
import SwiftUI

/// 3D地図の全画面と、下部の再生バー
struct MainView: View {
    @Environment(ListeningSession.self) private var session
    @Environment(AuthStore.self) private var auth
    @Environment(MyBalloonStore.self) private var myBalloon
    @Environment(ArtworkColors.self) private var artworkColors
    @State private var position = MapCameraPosition.userLocation(
        fallback: .camera(MapCamera(centerCoordinate: .init(latitude: 36.5, longitude: 137.5), distance: 3_000_000))
    )
    @AppStorage("isListening") private var isListening = false
    @State private var hasCentered = false
    @State private var showsAccount = false
    @State private var showsLaunch = false
    @State private var collectTarget: CollectTarget?
    @State private var showsSky = false
    /// 地図を動かし終えたときの視点。右上のボタンで傾きや向きを変えるときの基準にする
    @State private var camera: MapCamera?

    /// 設計書の「前面にある間は30秒ごとに /me/balloons を読む」
    private static let myBalloonRefreshInterval: Duration = .seconds(30)

    var body: some View {
        Map(position: $position) {
            UserAnnotation()
            // 港は風船より下に描く
            ForEach(visiblePorts) { port in
                Annotation(port.name, coordinate: port.coordinate, anchor: .center) {
                    PortMark(port: port)
                }
                .annotationTitles(.hidden)
            }
            ForEach(session.feed.balloons) { balloon in
                Annotation("", coordinate: balloon.coordinate, anchor: .bottom) {
                    BalloonMark(id: balloon.id,
                                isPlaying: balloon.id == session.currentBalloonID && isListening,
                                isMine: balloon.id == myBalloon.balloon?.id)
                }
            }
        }
        // 風船が主役なので、地図は色を落とし、お店などの印も消す
        .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))
        // 標準の地図ボタンは見た目がそろわないので出さず、右上に同じ丸ボタンで作る
        .mapControls {}
        .onMapCameraChange(frequency: .onEnd) { context in
            camera = context.camera
        }
        .overlay(alignment: .topTrailing) {
            MapButtons(camera: camera, userLocation: session.location.coordinate) { newCamera in
                withAnimation(.easeInOut(duration: 0.8)) { position = .camera(newCamera) }
            }
            .padding(.trailing)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .trailing, spacing: 12) {
                HStack(spacing: 10) {
                    Button {
                        showsSky = true
                    } label: {
                        PillLabel(title: "空を見上げる", systemImage: "binoculars.fill")
                    }
                    .buttonStyle(.bouncy)
                    .accessibilityHint("カメラで空を見て、気に入った曲の風船を割るとお気に入りにできます。スマホを振っても開きます")
                    LaunchButton(balloon: myBalloon.balloon) {
                        if let balloon = myBalloon.balloon {
                            showMyBalloon(balloon)
                        } else {
                            showsLaunch = true
                        }
                    }
                }
                PlaybackBar(isListening: $isListening) {
                    if auth.isSignedIn {
                        confirmCollect()
                    } else {
                        showsAccount = true
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 4)
        }
        .sheet(item: $collectTarget) { target in
            CollectSheet(target: target)
        }
        .sheet(isPresented: $showsLaunch) {
            LaunchSheet()
                .presentationCornerRadius(32)
        }
        .fullScreenCover(isPresented: $showsSky) {
            SlingshotView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
            // スマホを振っても、空を見上げて気に入った曲を選ぶ画面を開く
            guard !showsLaunch, !showsAccount else { return }
            showsSky = true
        }
        .task(id: auth.token) {
            // ログインとログアウトのたびに読み直し、その後は30秒ごとに回数を更新する。
            // 先に空にするのは、別の人でログインし直したときに、前の人の風船が消えたと通知しないため
            myBalloon.clear()
            while !Task.isCancelled {
                await myBalloon.refresh(with: auth)
                try? await Task.sleep(for: Self.myBalloonRefreshInterval)
            }
        }
        .overlay(alignment: .topLeading) {
            Button {
                showsAccount = true
            } label: {
                RoundIcon(systemName: "person.fill", size: 48)
            }
            .buttonStyle(.bouncy)
            .accessibilityLabel("マイページ")
            .padding(.leading)
        }
        .sheet(isPresented: $showsAccount) {
            AccountSheet()
                .presentationCornerRadius(32)
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
            if listening {
                Task { await Notifier.requestAuthorization() }
            }
        }
        .onChange(of: session.playback.isListening) { _, listening in
            // イヤホンが外れたときやロック画面の操作を、ボタンの表示にも反映する
            isListening = listening
        }
    }

    /// 回収の確認を出す。確認を出している間に流す風船が切り替わっても、このときの風船を回収する
    private func confirmCollect() {
        guard let balloonID = session.currentBalloonID, let track = session.currentTrack else { return }
        let color = artworkColors.color(for: track.thumbnailURL) ?? Theme.balloonColor(for: balloonID)
        collectTarget = CollectTarget(balloonID: balloonID, track: track, color: color)
    }

    /// 自分の風船へ地図を寄せる。地図の主役は利用者なので、ボタンを押したときだけ寄せる。
    /// 配信の位置があればそちらを使う（/me/balloons より新しい）
    private func showMyBalloon(_ balloon: MyBalloon) {
        let coordinate = session.feed.balloons.first { $0.id == balloon.id }?.coordinate ?? balloon.coordinate
        withAnimation(.easeInOut(duration: 1.5)) {
            position = .camera(MapCamera(centerCoordinate: coordinate, distance: 80_000, heading: 0, pitch: 55))
        }
    }

    /// 地図を寄せているときだけ、見えている辺りの港を出す。
    /// 日本全体を見ているときに229港すべてを出すと、風船が埋もれ、毎秒の描き直しも重くなる
    private var visiblePorts: [Port] {
        guard let camera, camera.distance < Self.portVisibleDistance else { return [] }
        // 傾けると遠くまで見えるので、視点の高さの1.5倍までを「見えている辺り」とする
        let radius = camera.distance * 1.5
        return Port.all.filter { Geo.distance($0.coordinate, camera.centerCoordinate) < radius }
    }

    /// これより寄せたら港を出す（視点の高さ、m）
    private static let portVisibleDistance: Double = 1_200_000
}

/// 港のアイコン。日本海側は青緑、太平洋側は青。タップすると港の名前を出す
private struct PortMark: View {
    let port: Port
    @State private var showsName = false

    private var color: Color {
        port.side == .japanSea ? Color(red: 0.25, green: 0.70, blue: 0.68) : Color(red: 0.30, green: 0.52, blue: 0.90)
    }

    var body: some View {
        Image(systemName: "ferry.fill")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(Circle().fill(color.gradient))
            .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
            .shadow(color: color.opacity(0.35), radius: 3, y: 1)
            .overlay(alignment: .bottom) {
                if showsName {
                    Text(port.name + "港")
                        .font(Theme.font(11, .bold, relativeTo: .caption))
                        .foregroundStyle(Theme.ink)
                        .fixedSize()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.white))
                        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                        .offset(y: 24)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { showsName.toggle() }
            }
            .accessibilityLabel("\(port.name)港（\(port.side == .japanSea ? "日本海側" : "太平洋側")）")
    }
}

/// 右上の地図のボタン。現在地へ戻る、2D と 3D を切り替える、北を上に戻す（回したときだけ出す）
private struct MapButtons: View {
    let camera: MapCamera?
    let userLocation: CLLocationCoordinate2D?
    let move: (MapCamera) -> Void

    private var isTilted: Bool { (camera?.pitch ?? 0) > 5 }
    private var isRotated: Bool {
        let heading = camera?.heading ?? 0
        return min(heading, 360 - heading) > 3
    }

    var body: some View {
        VStack(spacing: 10) {
            Button {
                guard let userLocation else { return }
                move(MapCamera(centerCoordinate: userLocation, distance: camera?.distance ?? 400_000,
                               heading: camera?.heading ?? 0, pitch: camera?.pitch ?? 50))
            } label: {
                RoundIcon(systemName: "location.fill", size: 44)
            }
            .accessibilityLabel("現在地へ戻る")

            Button {
                guard let camera else { return }
                move(MapCamera(centerCoordinate: camera.centerCoordinate, distance: camera.distance,
                               heading: camera.heading, pitch: isTilted ? 0 : 50))
            } label: {
                Text(isTilted ? "2D" : "3D")
                    .font(Theme.font(15, .bold))
                    .foregroundStyle(Theme.sky)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(.white))
                    .shadow(color: Theme.sky.opacity(0.35), radius: 8, y: 4)
            }
            .accessibilityLabel(isTilted ? "真上から見る" : "傾けて見る")

            if isRotated, let camera {
                Button {
                    move(MapCamera(centerCoordinate: camera.centerCoordinate, distance: camera.distance,
                                   heading: 0, pitch: camera.pitch))
                } label: {
                    // 針は北を指すように、地図の向きと逆に回す
                    RoundIcon(systemName: "location.north.fill", size: 44, color: Theme.heart)
                        .rotationEffect(.degrees(-camera.heading))
                }
                .accessibilityLabel("北を上にする")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .buttonStyle(.bouncy)
        .animation(.spring, value: isRotated)
    }
}

/// 飛ばすボタン。飛行中は「🎈 12回」のように聴かれた回数を出し、押すと自分の風船へ移動する
private struct LaunchButton: View {
    let balloon: MyBalloon?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PillLabel(title: balloon.map { "\($0.playCount)回" } ?? "飛ばす", systemImage: "balloon.fill", color: Theme.heart)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.spring, value: balloon?.playCount)
        }
        .buttonStyle(.bouncy)
        .accessibilityLabel(balloon.map { "自分の風船。\($0.playCount)回聴かれました" } ?? "風船を飛ばす")
    }
}

/// 地図の上の風船。つやと結び目とひもがあり、風に揺れる。今聴いている風船は大きく光り、♪ が浮かぶ
private struct BalloonMark: View {
    let id: Int
    let isPlaying: Bool
    let isMine: Bool

    @State private var swaying = false

    var body: some View {
        let color = Theme.balloonColor(for: id)
        let size: CGFloat = isPlaying ? 40 : 24
        VStack(spacing: 0) {
            ZStack {
                Ellipse()
                    .fill(RadialGradient(colors: [color.mix(with: .white, by: 0.45), color],
                                         center: UnitPoint(x: 0.35, y: 0.3), startRadius: 1, endRadius: size * 0.7))
                // 左上のつや
                Ellipse()
                    .fill(.white.opacity(0.75))
                    .frame(width: size * 0.22, height: size * 0.32)
                    .rotationEffect(.degrees(-25))
                    .offset(x: -size * 0.18, y: -size * 0.2)
                if isMine {
                    Image(systemName: "star.fill")
                        .font(.system(size: size * 0.35))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: size, height: size * 1.18)
            .overlay {
                if isMine {
                    Ellipse().strokeBorder(.white, lineWidth: 2.5)
                }
            }
            .shadow(color: isPlaying ? color : .black.opacity(0.18), radius: isPlaying ? 12 : 3, y: isPlaying ? 0 : 2)
            // 結び目
            Triangle()
                .fill(color)
                .frame(width: size * 0.22, height: size * 0.14)
            // ゆるく曲がったひも
            BalloonString()
                .stroke(Theme.ink.opacity(0.35), lineWidth: 1)
                .frame(width: 6, height: isPlaying ? 22 : 14)
        }
        .overlay(alignment: .top) {
            if isPlaying {
                FloatingNotes(color: color)
                    .offset(y: -18)
            }
        }
        .rotationEffect(.degrees(swaying ? 5 : -5), anchor: .bottom)
        .animation(.spring(response: 0.5, dampingFraction: 0.6), value: isPlaying)
        .onAppear {
            // 風船ごとに少しずつ周期をずらし、そろって揺れないようにする
            withAnimation(.easeInOut(duration: 1.8 + Double(id % 5) * 0.25).repeatForever(autoreverses: true)) {
                swaying = true
            }
        }
    }

    private struct Triangle: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.closeSubpath()
            }
        }
    }

    private struct BalloonString: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                path.addCurve(to: CGPoint(x: rect.midX, y: rect.maxY),
                              control1: CGPoint(x: rect.maxX, y: rect.height * 0.35),
                              control2: CGPoint(x: rect.minX, y: rect.height * 0.65))
            }
        }
    }
}

/// 今聴いている風船から、♪ がふわふわ浮かんでは消える
private struct FloatingNotes: View {
    let color: Color
    @State private var rising = false

    var body: some View {
        ZStack {
            note("music.note", x: -10, delay: 0)
            note("music.note.list", x: 12, delay: 0.7)
        }
        .onAppear { rising = true }
    }

    private func note(_ name: String, x: CGFloat, delay: Double) -> some View {
        Image(systemName: name)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(color.mix(with: .black, by: 0.15))
            .offset(x: x, y: rising ? -20 : 0)
            .opacity(rising ? 0 : 1)
            .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false).delay(delay), value: rising)
    }
}

/// 下部の再生バー。曲ごとに色が変わる（サムネイルがあればそこから、なければ風船の色）
private struct PlaybackBar: View {
    @Environment(ListeningSession.self) private var session
    @Environment(ArtworkColors.self) private var artworkColors
    @Binding var isListening: Bool
    let onCollect: () -> Void

    private var accent: Color {
        artworkColors.color(for: session.currentTrack?.thumbnailURL)
            ?? session.currentBalloonID.map(Theme.balloonColor(for:))
            ?? Theme.sky
    }

    var body: some View {
        HStack(spacing: 12) {
            Artwork(url: session.currentTrack?.thumbnailURL, color: accent, isPlaying: isListening && session.currentTrack != nil)
            VStack(alignment: .leading, spacing: 3) {
                MarqueeText(text: title, font: Theme.font(17, .bold, relativeTo: .headline))
                    .foregroundStyle(Theme.ink)
                Text(subtitle)
                    .font(Theme.font(13, .medium, relativeTo: .subheadline))
                    .foregroundStyle(Theme.ink.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button(action: onCollect) {
                RoundIcon(systemName: "heart.fill", size: 42, color: Theme.heart)
            }
            .buttonStyle(.bouncy)
            .disabled(session.currentTrack == nil)
            .opacity(session.currentTrack == nil ? 0.5 : 1)
            .accessibilityLabel("この曲を回収する")
            Button {
                isListening.toggle()
            } label: {
                RoundIcon(systemName: isListening ? "pause.fill" : "play.fill", size: 50, color: accent, filled: true)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.bouncy)
            .accessibilityLabel(isListening ? "止める" : "流す")
        }
        .padding(12)
        .softCard(tint: accent)
        .animation(.easeInOut(duration: 0.6), value: accent)
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
        return "\(track.artist)・\(Self.formatDistance(meters))先から"
    }

    private static func formatDistance(_ meters: Double) -> String {
        meters < 1000 ? "\(Int(meters))m" : String(format: "%.0fkm", meters / 1000)
    }
}

/// 再生バーの左の丸い絵。サムネイルがあれば出し、なければ風船の色に 🎈 を置く。流れている間はゆっくり回る
private struct Artwork: View {
    let url: URL?
    let color: Color
    let isPlaying: Bool
    @State private var angle: Double = 0

    var body: some View {
        ZStack {
            Circle().fill(color.gradient)
            if let url {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "balloon.fill").font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                }
            } else {
                Image(systemName: "balloon.fill").font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white, lineWidth: 3))
        .shadow(color: color.opacity(0.4), radius: 6, y: 3)
        .rotationEffect(.degrees(angle))
        .onChange(of: isPlaying, initial: true) { _, playing in
            if playing {
                withAnimation(.linear(duration: 12).repeatForever(autoreverses: false)) { angle = 360 }
            } else {
                withAnimation(.easeOut(duration: 0.4)) { angle = 0 }
            }
        }
    }
}

private struct LocationDeniedView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "location.circle.fill").font(.system(size: 60)).foregroundStyle(Theme.sky)
            Text("位置情報をオンにしてください")
                .font(Theme.font(20, .bold, relativeTo: .title3))
            Text("近くを漂う風船の曲を流すために、現在地を使います。現在地はサーバーへ送りません。")
                .font(Theme.font(15))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.ink.opacity(0.7))
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                PillLabel(title: "設定を開く", systemImage: "gearshape.fill")
            }
            .buttonStyle(.bouncy)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient(colors: Theme.skyColors(), startPoint: .top, endPoint: .bottom))
    }
}
