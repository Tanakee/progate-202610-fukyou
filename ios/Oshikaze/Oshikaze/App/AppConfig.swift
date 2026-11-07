import Foundation

/// ビルド設定（xcconfig の API_BASE_URL）から決まる接続先
enum AppConfig {
    static let apiBaseURL: URL = {
        let value = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String ?? ""
        guard let url = URL(string: value), url.scheme != nil else {
            fatalError("Info.plist の APIBaseURL が不正です: \(value)")
        }
        return url
    }()

    /// Action Cable の接続先。http を ws に、https を wss に替えて /ws を付ける
    static var webSocketURL: URL {
        var components = URLComponents(url: apiBaseURL, resolvingAgainstBaseURL: false)!
        components.scheme = apiBaseURL.scheme == "https" ? "wss" : "ws"
        components.path = "/ws"
        return components.url!
    }
}
