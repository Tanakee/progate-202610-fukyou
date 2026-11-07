import Foundation

/// 回収した曲（`POST /balloons/:id/collect`、`GET /me/favorites`）
struct Favorite: Decodable, Equatable, Identifiable {
    let id: Int
    let balloonID: Int
    /// 回収した日（日本時間）。"2026-11-08" の形
    let collectedOn: String
    let track: Track

    enum CodingKeys: String, CodingKey {
        case id, track
        case balloonID = "balloon_id"
        case collectedOn = "collected_on"
    }
}
