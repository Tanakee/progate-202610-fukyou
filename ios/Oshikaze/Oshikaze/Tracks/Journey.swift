import Foundation

/// 飛ばした風船の旅の記録（`GET /me/journeys`）
struct Journey: Decodable, Equatable, Identifiable {
    let id: Int
    let balloonID: Int
    /// "collected"（回収された）または "lost"（海や国外へ出た）
    let endReason: String
    let endLabel: String?
    let durationSeconds: Int
    let playCount: Int
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case balloonID = "balloon_id"
        case endReason = "end_reason"
        case endLabel = "end_label"
        case durationSeconds = "duration_seconds"
        case playCount = "play_count"
        case createdAt = "created_at"
    }

    var wasCollected: Bool { endReason == "collected" }

    /// 「誰かに回収された」「海へ出た」のような旅の終わり方
    var endDescription: String {
        wasCollected ? "誰かの今日の1曲になりました" : "\(endLabel ?? "遠く")へ旅立ちました"
    }

    /// 「3時間12分」のような旅の時間
    var durationText: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = durationSeconds >= 3600 ? [.day, .hour, .minute] : [.minute, .second]
        formatter.unitsStyle = .short
        formatter.calendar?.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: TimeInterval(durationSeconds)) ?? "\(durationSeconds)秒"
    }
}
