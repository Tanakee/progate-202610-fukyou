import CoreLocation
import Foundation
import Observation

/// `GET /me/balloons` と `POST /balloons` の風船
struct MyBalloon: Decodable, Equatable {
    let id: Int
    let trackID: Int
    let originLabel: String
    let lat: Double
    let lng: Double
    let playCount: Int

    enum CodingKeys: String, CodingKey {
        case id, lat, lng
        case trackID = "track_id"
        case originLabel = "origin_label"
        case playCount = "play_count"
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

/// 飛行中の自分の風船。飛ばせるのは1人1個まで
@MainActor
@Observable
final class MyBalloonStore {
    private(set) var balloon: MyBalloon?

    /// 出発地点をぼかす単位（度）。0.01度は約1km
    private static let blurStep = 0.01

    func refresh(with auth: AuthStore) async {
        guard auth.isSignedIn else {
            balloon = nil
            return
        }
        do {
            let balloons: [MyBalloon] = try await auth.client.send(.get, "me/balloons")
            let previous = balloon
            balloon = balloons.first
            // 飛んでいた風船が一覧から消えたら、回収されたか旅が終わった。
            // 本人用チャンネル（balloon.collected / balloon.ended）ができるまでは、この差で気づく
            if let previous, balloon?.id != previous.id {
                await notifyEnded(previous, with: auth)
            }
        } catch {
            auth.handle(error)
        }
    }

    private func notifyEnded(_ balloon: MyBalloon, with auth: AuthStore) async {
        let journeys: [Journey] = (try? await auth.client.send(.get, "me/journeys")) ?? []
        Notifier.postJourneyEnded(balloon, journey: journeys.first { $0.balloonID == balloon.id })
    }

    /// 現在地をぼかし、地名を付けて飛ばす。生の現在地はサーバーへ送らない
    func launch(_ track: Track, from location: CLLocationCoordinate2D, with auth: AuthStore) async throws {
        let origin = Self.blur(location)
        let label = await Self.placeName(of: location)
        do {
            balloon = try await auth.client.send(.post, "balloons", body: [
                "track_id": String(track.id),
                "origin_lat": String(origin.latitude),
                "origin_lng": String(origin.longitude),
                "origin_label": label,
            ])
        } catch let error as APIError where error.status == 409 {
            // 別の端末などで飛ばしていた。地図の状態に合わせて読み直す
            await refresh(with: auth)
            throw error
        } catch {
            auth.handle(error)
            throw error
        }
    }

    /// 先に手元から消すのは、次の読み直しで「旅が終わった」と通知しないため
    func land(with auth: AuthStore) async throws {
        guard let balloon else { return }
        do {
            try await auth.client.send(.post, "balloons/\(balloon.id)/land")
            self.balloon = nil
        } catch let error as APIError where error.status == 409 {
            // 下ろす前に回収されたか、旅が終わっていた
            await refresh(with: auth)
            throw error
        } catch {
            auth.handle(error)
            throw error
        }
    }

    func clear() {
        balloon = nil
    }

    static func blur(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: (coordinate.latitude / blurStep).rounded() * blurStep,
                               longitude: (coordinate.longitude / blurStep).rounded() * blurStep)
    }

    /// 「千代田区」のような市区町村の名前。取れなければ都道府県、それも取れなければ「どこか」
    private static func placeName(of coordinate: CLLocationCoordinate2D) async -> String {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "ja_JP")).first
        return placemark?.locality ?? placemark?.administrativeArea ?? "どこか"
    }
}
