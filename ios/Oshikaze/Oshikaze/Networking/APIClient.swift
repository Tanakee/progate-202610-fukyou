import Foundation

/// BEが返すエラー。形は `{code, message}`（docs/api.md）
struct APIError: Error, LocalizedError, Decodable {
    let code: String
    let message: String
    var status = 0

    enum CodingKeys: String, CodingKey {
        case code, message
    }

    var errorDescription: String? { message }

    var isUnauthorized: Bool { status == 401 }

    static func unexpected(status: Int) -> APIError {
        APIError(code: "unexpected", message: "サーバーから想定外の応答がありました（\(status)）", status: status)
    }
}

/// REST API を呼ぶ。JSONは平たい形で送り、`Authorization: Bearer <token>` を付ける
struct APIClient {
    var baseURL = AppConfig.apiBaseURL
    var token: String?

    enum Method: String {
        case get = "GET"
        case post = "POST"
        case delete = "DELETE"
    }

    func send<Response: Decodable>(_ method: Method,
                                   _ path: String,
                                   body: [String: String]? = nil,
                                   timeout: TimeInterval = 30) async throws -> Response {
        let data = try await perform(method, path, body: body, timeout: timeout)
        return try JSONDecoder().decode(Response.self, from: data)
    }

    /// 応答の本文を使わないとき（204 など）
    func send(_ method: Method, _ path: String, body: [String: String]? = nil) async throws {
        _ = try await perform(method, path, body: body, timeout: 30)
    }

    private func perform(_ method: Method, _ path: String, body: [String: String]?, timeout: TimeInterval) async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: path), timeoutInterval: timeout)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            var error = (try? JSONDecoder().decode(APIError.self, from: data)) ?? .unexpected(status: status)
            error.status = status
            throw error
        }
        return data
    }
}
