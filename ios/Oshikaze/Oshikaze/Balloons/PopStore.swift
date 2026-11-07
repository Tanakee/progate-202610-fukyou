import Foundation
import Observation

/// 割った風船。割った風船は自分の世界からだけ消え、二度と流れない
@MainActor
@Observable
final class PopStore {
    private(set) var poppedIDs: Set<Int> = []

    func refresh(with auth: AuthStore) async {
        guard auth.isSignedIn else {
            poppedIDs = []
            return
        }
        do {
            let ids: [Int] = try await auth.client.send(.get, "me/popped")
            // 送信中の割った風船を消さないよう、足し合わせる
            poppedIDs.formUnion(ids)
        } catch {
            auth.handle(error)
        }
    }

    /// 先に手元から消し、BEには後から送る。送れなくても、この起動の間は消えたままにする
    func pop(_ balloonID: Int, with auth: AuthStore) async {
        poppedIDs.insert(balloonID)
        guard auth.isSignedIn else { return }
        do {
            // 応答は `{balloon_id}` だが使わない。再送しても成功になる
            try await auth.client.send(.post, "balloons/\(balloonID)/pop")
        } catch {
            auth.handle(error)
        }
    }

    func clear() {
        poppedIDs = []
    }
}
