import UserNotifications

/// 端末内のローカル通知。APNs は使わない（無料の開発者アカウントのため）
enum Notifier {
    /// 設計書どおり、流すをONにしたときに許可を求める
    static func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    static func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    /// 自分の風船の旅が終わったとき。旅の記録があれば終わり方に合わせて文言を変える
    static func postJourneyEnded(_ balloon: MyBalloon, journey: Journey?) {
        let plays = journey?.playCount ?? balloon.playCount
        if journey?.wasCollected == true {
            post(title: "あなたの風船が回収されました", body: "誰かの今日の1曲になりました。\(plays)回聴かれた旅でした。")
        } else if let journey {
            post(title: "あなたの風船の旅が終わりました", body: "\(journey.endDescription)。\(plays)回聴かれました。")
        } else {
            // 旅の記録がないと、回収されたのか海や国外へ出たのかを見分けられない。
            // BEが記録を作るまでは、空の旅の記録へは案内しない
            post(title: "あなたの風船の旅が終わりました", body: "\(plays)回聴かれた旅でした。")
        }
    }
}

/// アプリを開いている間も通知を出す（設計書の決定）
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
