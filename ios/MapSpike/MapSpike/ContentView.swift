import MapKit
import SwiftUI

struct ContentView: View {
    enum Style: String, CaseIterable, Identifiable {
        case standard = "標準"
        case hybrid = "航空写真+地名"
        case imagery = "航空写真"
        var id: Self { self }

        var mapStyle: MapStyle {
            switch self {
            case .standard: .standard(elevation: .realistic)
            case .hybrid: .hybrid(elevation: .realistic)
            case .imagery: .imagery(elevation: .realistic)
            }
        }
    }

    enum Viewpoint: String, CaseIterable, Identifiable {
        case japan = "日本全体"
        case region = "関東"
        case city = "東京の街"
        var id: Self { self }

        var camera: MapCamera {
            switch self {
            case .japan:
                MapCamera(centerCoordinate: .init(latitude: 36.5, longitude: 137.5), distance: 3_000_000, heading: 0, pitch: 0)
            case .region:
                MapCamera(centerCoordinate: .init(latitude: 35.3, longitude: 139.6), distance: 400_000, heading: 20, pitch: 55)
            case .city:
                MapCamera(centerCoordinate: .init(latitude: 35.681, longitude: 139.767), distance: 1_800, heading: 30, pitch: 65)
            }
        }
    }

    private static let speedScales: [Double] = [1, 60, 600, 3600]

    @State private var simulator = BalloonSimulator()
    @State private var position = MapCameraPosition.camera(Viewpoint.japan.camera)
    @State private var style = Style.standard
    @State private var showsWind = false
    /// 起動引数 `-serverURL ws://...` でも上書きできる
    @AppStorage("serverURL") private var serverURL = "ws://localhost:3000/ws"

    var body: some View {
        MapReader { proxy in
            Map(position: $position) {
                if showsWind {
                    ForEach(simulator.wind.points) { point in
                        Annotation("", coordinate: point.coordinate) {
                            WindArrow(velocity: point.velocity)
                        }
                    }
                }
                ForEach(simulator.balloons) { balloon in
                    Annotation("", coordinate: balloon.coordinate, anchor: .bottom) {
                        BalloonMark(color: balloon.color, isNearest: balloon.id == simulator.nearest?.balloon.id)
                    }
                }
                Annotation("聴いている場所", coordinate: simulator.listener) {
                    Image(systemName: "headphones.circle.fill")
                        .font(.title)
                        .foregroundStyle(.white, .blue)
                        .shadow(radius: 2)
                }
            }
            .mapStyle(style.mapStyle)
            .mapControls {
                MapCompass()
                MapPitchToggle()
                MapScaleView()
            }
            .onTapGesture { point in
                if let coordinate = proxy.convert(point, from: .local) {
                    simulator.listener = coordinate
                }
            }
        }
        .safeAreaInset(edge: .top) { controls }
        .safeAreaInset(edge: .bottom) { nowPlaying }
        .task {
            simulator.start()
            if UserDefaults.standard.string(forKey: "source") == "server" {
                simulator.use(.server, serverURL: serverURL)
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            Picker("風船の位置", selection: Binding(get: { simulator.source }, set: { simulator.use($0, serverURL: serverURL) })) {
                ForEach(BalloonSimulator.Source.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("視点", selection: Binding(get: { Viewpoint?.none }, set: { viewpoint in
                guard let viewpoint else { return }
                withAnimation(.easeInOut(duration: 1.5)) { position = .camera(viewpoint.camera) }
            })) {
                ForEach(Viewpoint.allCases) { Text($0.rawValue).tag(Viewpoint?.some($0)) }
            }
            .pickerStyle(.segmented)
            Picker("地図", selection: $style) {
                ForEach(Style.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            HStack {
                Picker("速さ", selection: $simulator.speedScale) {
                    ForEach(Self.speedScales, id: \.self) { Text("×\(Int($0))").tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(simulator.source == .server)
                Toggle("風", isOn: $showsWind)
                    .toggleStyle(.button)
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
    }

    private var nowPlaying: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let nearest = simulator.nearest {
                Text("🎈 \(nearest.balloon.title)")
                    .font(.headline)
                Text(String(format: "一番近い風船まで %.0f km", nearest.kilometers))
                    .font(.subheadline)
            }
            HStack {
                Text(simulator.windStatus)
                Spacer()
                Text(String(format: "%.0f fps", simulator.framesPerSecond))
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text("地図をタップすると聴いている場所が変わります。風データ: Open-Meteo（CC BY 4.0）")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
    }
}

private struct BalloonMark: View {
    let color: Color
    let isNearest: Bool

    var body: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(color.gradient)
                .overlay(Circle().stroke(.white, lineWidth: isNearest ? 3 : 1))
                .frame(width: isNearest ? 30 : 18, height: isNearest ? 30 : 18)
                .shadow(color: isNearest ? color : .black.opacity(0.3), radius: isNearest ? 8 : 2)
            Rectangle()
                .fill(.secondary)
                .frame(width: 1, height: isNearest ? 14 : 8)
        }
        .animation(.spring, value: isNearest)
    }
}

private struct WindArrow: View {
    let velocity: WindField.Velocity

    var body: some View {
        let speed = hypot(velocity.east, velocity.north)
        Image(systemName: "arrow.up")
            .font(.system(size: 10 + min(speed, 15), weight: .bold))
            .foregroundStyle(.blue.opacity(0.6))
            // 北を0度として、進む向きへ回す
            .rotationEffect(.radians(atan2(velocity.east, velocity.north)))
    }
}
