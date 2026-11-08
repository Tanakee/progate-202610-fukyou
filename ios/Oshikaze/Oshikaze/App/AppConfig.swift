import Foundation

/// BEの接続先。ビルド設定（xcconfig の API_BASE_URL）で決まり、開発中は起動引数で上書きできる
enum AppConfig {
    /// 起動引数 `-apiBaseURL http://...` で渡すと、次の起動からも使う。
    /// テザリングをつなぎ直すとMacのアドレスが変わるので、ビルドし直さずに済むようにする
    private static let overrideKey = "apiBaseURL"

    static let apiBaseURL: URL = {
        let defaults = UserDefaults.standard
        if let override = defaults.string(forKey: overrideKey) {
            // 起動引数の値は今回の起動にしか効かないので、アプリの設定として保存し直す
            defaults.set(override, forKey: overrideKey)
        }
        let value = defaults.string(forKey: overrideKey)
            ?? Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String ?? ""
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
