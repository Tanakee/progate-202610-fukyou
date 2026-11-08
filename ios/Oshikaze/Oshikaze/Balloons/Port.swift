import CoreLocation
import Foundation

/// 風船が船に乗る港（#30）。BEの `backend/config/sea_routes.json` をビルド時にそのまま同梱して読む
struct Port: Decodable, Identifiable {
    enum Side: String, Decodable {
        case japanSea = "japan_sea"
        case pacific
    }

    let name: String
    let prefecture: String
    let lat: Double
    let lng: Double
    let side: Side

    var id: String { "\(name)-\(lat)-\(lng)" }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }

    static let all: [Port] = {
        struct SeaRoutes: Decodable {
            let ports: [Port]
        }
        guard let url = Bundle.main.url(forResource: "sea_routes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let routes = try? JSONDecoder().decode(SeaRoutes.self, from: data) else { return [] }
        return routes.ports
    }()
}
