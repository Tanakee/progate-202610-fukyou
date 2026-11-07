import CoreLocation
import Foundation

/// 日本周辺の格子点の風。格子の間は双線形補間する。
struct WindField {
    /// 東向きと北向きの風速（m/s）
    struct Velocity {
        let east: Double
        let north: Double
    }

    struct Point: Identifiable {
        let id: Int
        let coordinate: CLLocationCoordinate2D
        let velocity: Velocity
    }

    static let latitudes = Array(stride(from: 24.0, through: 46.0, by: 2.0))
    static let longitudes = Array(stride(from: 122.0, through: 148.0, by: 2.0))

    /// [緯度の添字][経度の添字]
    private let grid: [[Velocity]]
    let fetchedAt: Date
    let isFallback: Bool

    init(grid: [[Velocity]], fetchedAt: Date = .now, isFallback: Bool = false) {
        self.grid = grid
        self.fetchedAt = fetchedAt
        self.isFallback = isFallback
    }

    /// 取得に失敗したときの代わり。一様な西風（偏西風のつもり）
    static let fallback = WindField(
        grid: latitudes.map { _ in longitudes.map { _ in Velocity(east: 10, north: 0) } },
        isFallback: true
    )

    var points: [Point] {
        var points: [Point] = []
        for (i, lat) in Self.latitudes.enumerated() {
            for (j, lon) in Self.longitudes.enumerated() {
                points.append(Point(id: i * Self.longitudes.count + j,
                                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                    velocity: grid[i][j]))
            }
        }
        return points
    }

    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        (Self.latitudes.first!...Self.latitudes.last!).contains(coordinate.latitude)
            && (Self.longitudes.first!...Self.longitudes.last!).contains(coordinate.longitude)
    }

    func velocity(at coordinate: CLLocationCoordinate2D) -> Velocity? {
        guard contains(coordinate) else { return nil }
        let (i, ty) = Self.cell(coordinate.latitude, in: Self.latitudes)
        let (j, tx) = Self.cell(coordinate.longitude, in: Self.longitudes)
        func blend(_ value: (Velocity) -> Double) -> Double {
            let bottom = value(grid[i][j]) * (1 - tx) + value(grid[i][j + 1]) * tx
            let top = value(grid[i + 1][j]) * (1 - tx) + value(grid[i + 1][j + 1]) * tx
            return bottom * (1 - ty) + top * ty
        }
        return Velocity(east: blend(\.east), north: blend(\.north))
    }

    /// 値を含むマスの左下の添字と、マス内の位置（0〜1）
    private static func cell(_ value: Double, in axis: [Double]) -> (Int, Double) {
        let step = axis[1] - axis[0]
        let index = min(Int((value - axis[0]) / step), axis.count - 2)
        return (index, (value - axis[index]) / step)
    }
}

/// Open-Meteoから格子点の現在の風（地上10m）をまとめて取得する
enum WindService {
    private struct Response: Decodable {
        struct Current: Decodable {
            let wind_speed_10m: Double
            let wind_direction_10m: Double
        }
        let current: Current
    }

    static func fetch() async throws -> WindField {
        let coordinates = WindField.latitudes.flatMap { lat in WindField.longitudes.map { lon in (lat, lon) } }
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: coordinates.map { String($0.0) }.joined(separator: ",")),
            URLQueryItem(name: "longitude", value: coordinates.map { String($0.1) }.joined(separator: ",")),
            URLQueryItem(name: "current", value: "wind_speed_10m,wind_direction_10m"),
            URLQueryItem(name: "wind_speed_unit", value: "ms"),
        ]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        // 応答は要求した地点の順に並ぶ
        let responses = try JSONDecoder().decode([Response].self, from: data)
        let velocities = responses.map { response in
            // 風向は「吹いてくる方角」なので、進む向きは反対になる
            let radians = response.current.wind_direction_10m * .pi / 180
            let speed = response.current.wind_speed_10m
            return WindField.Velocity(east: -speed * sin(radians), north: -speed * cos(radians))
        }
        let columns = WindField.longitudes.count
        let grid = WindField.latitudes.indices.map { i in Array(velocities[(i * columns)..<((i + 1) * columns)]) }
        return WindField(grid: grid)
    }
}
