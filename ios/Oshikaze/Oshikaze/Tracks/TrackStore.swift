import Foundation
import Observation

struct Track: Decodable, Equatable, Identifiable {
    let id: Int
    let title: String
    let artist: String
    /// ストレージのmp3を直接指す署名付きURL。ここから直接流す。BEが返してから1日で使えなくなる
    let mp3URL: URL

    enum CodingKeys: String, CodingKey {
        case id, title, artist
        case mp3URL = "mp3_url"
    }
}

/// 曲の取得と追加。風船の曲は `GET /tracks/:id` で読み、曲IDごとに覚えておく
@MainActor
@Observable
final class TrackStore {
    /// 自分が追加した曲（新しい順）
    private(set) var myTracks: [Track] = []

    private var cache: [Int: Track] = [:]
    private var loading: [Int: Task<Track?, Never>] = [:]

    /// YouTube からの変換に時間がかかるので、追加だけは長めに待つ
    private static let importTimeout: TimeInterval = 300

    /// 曲を取得する。取得に失敗したら nil を返し、次に聞かれたときに取り直す
    func track(id: Int) async -> Track? {
        if let track = cache[id] { return track }
        if let task = loading[id] { return await task.value }
        let task = Task<Track?, Never> {
            try? await APIClient().send(.get, "tracks/\(id)")
        }
        loading[id] = task
        let track = await task.value
        loading[id] = nil
        cache[id] = track
        return track
    }

    func loadMyTracks(with auth: AuthStore) async throws {
        do {
            myTracks = try await auth.client.send(.get, "me/tracks")
            myTracks.forEach { cache[$0.id] = $0 }
        } catch {
            auth.handle(error)
            throw error
        }
    }

    /// YouTube の URL から曲を追加する。サーバーが音声をmp3にして保存する
    func addTrack(youtubeURL: String, with auth: AuthStore) async throws -> Track {
        do {
            let track: Track = try await auth.client.send(.post, "tracks", body: ["youtube_url": youtubeURL], timeout: Self.importTimeout)
            cache[track.id] = track
            myTracks.insert(track, at: 0)
            return track
        } catch {
            auth.handle(error)
            throw error
        }
    }

    func clearMyTracks() {
        myTracks = []
    }
}
