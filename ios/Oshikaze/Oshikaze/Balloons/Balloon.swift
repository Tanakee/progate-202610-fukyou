import CoreLocation

/// 地図に表示する時点の風船。位置は最後の配信から補間したもの
struct Balloon: Identifiable, Equatable {
    let id: Int
    let trackID: Int
    let coordinate: CLLocationCoordinate2D

    static func == (lhs: Balloon, rhs: Balloon) -> Bool {
        lhs.id == rhs.id && lhs.trackID == rhs.trackID
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
    }
}

/// `balloons.snapshot` の形式（docs/api.md の WebSocket の節）
struct BalloonsSnapshot: Decodable {
    struct Item: Decodable {
        let id: Int
        let trackID: Int
        let lat: Double
        let lng: Double
        /// 東向き・北向きの風の速さ（m/s、speed_scale を掛ける前）
        let ve: Double
        let vn: Double

        enum CodingKeys: String, CodingKey {
            case id, lat, lng, ve, vn
            case trackID = "track_id"
        }
    }

    let event: String
    let seq: Int
    let speedScale: Double
    let balloons: [Item]

    enum CodingKeys: String, CodingKey {
        case event, seq, balloons
        case speedScale = "speed_scale"
    }
}

enum Geo {
    static let metersPerDegree = 111_320.0

    /// 東向き・北向きに進んだ地点。数km程度の移動を想定した近似
    static func advance(_ coordinate: CLLocationCoordinate2D, east: Double, north: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: coordinate.latitude + north / metersPerDegree,
            longitude: coordinate.longitude + east / (metersPerDegree * cos(coordinate.latitude * .pi / 180))
        )
    }

    /// a から見た b の方角。北を0として時計回りのラジアン
    static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let deltaLng = (b.longitude - a.longitude) * .pi / 180
        let y = sin(deltaLng) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLng)
        return atan2(y, x)
    }

    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
}
