import Foundation
import Observation

struct User: Decodable, Equatable {
    let id: Int
    let email: String
}

/// ログインの状態。トークンは Keychain に置き、401 が返ったら捨ててログイン画面へ戻す
@MainActor
@Observable
final class AuthStore {
    private(set) var token: String?
    private(set) var user: User?

    private struct Session: Decodable {
        let token: String
        let user: User
    }

    init() {
        token = Keychain.loadToken()
    }

    var isSignedIn: Bool { token != nil }

    /// トークン付きのクライアント。ログインが必要なAPIはこれで呼ぶ
    var client: APIClient { APIClient(token: token) }

    func signUp(email: String, password: String) async throws {
        let session: Session = try await APIClient().send(.post, "auth/signup", body: ["email": email, "password": password])
        store(session)
    }

    func logIn(email: String, password: String) async throws {
        let session: Session = try await APIClient().send(.post, "auth/login", body: ["email": email, "password": password])
        store(session)
    }

    func logOut() async {
        // サーバーで消せなくても、端末からは必ず消す
        try? await client.send(.delete, "auth/session")
        clear()
    }

    /// 起動時に、保存してあるトークンがまだ使えるかを確かめる
    func refresh() async {
        guard isSignedIn else { return }
        do {
            user = try await client.send(.get, "me")
        } catch {
            handle(error)
        }
    }

    /// ログインが必要なAPIで失敗したときに呼ぶ。401ならログアウトする
    func handle(_ error: Error) {
        if (error as? APIError)?.isUnauthorized == true {
            clear()
        }
    }

    private func store(_ session: Session) {
        Keychain.saveToken(session.token)
        token = session.token
        user = session.user
    }

    private func clear() {
        Keychain.deleteToken()
        token = nil
        user = nil
    }
}
