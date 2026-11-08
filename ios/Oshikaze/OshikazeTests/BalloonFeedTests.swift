import CoreLocation
import XCTest
@testable import Oshikaze

@MainActor
final class BalloonFeedTests: XCTestCase {
    private let tokyo = CLLocationCoordinate2D(latitude: 35.68, longitude: 139.77)
    private let niigata = CLLocationCoordinate2D(latitude: 37.92, longitude: 139.04)

    func testInterpolateMovesProportionally() {
        let half = BalloonFeed.interpolate(from: tokyo, to: niigata, fraction: 0.5)
        XCTAssertEqual(half.latitude, (tokyo.latitude + niigata.latitude) / 2, accuracy: 1e-9)
        XCTAssertEqual(half.longitude, (tokyo.longitude + niigata.longitude) / 2, accuracy: 1e-9)
    }

    /// 次の配信が遅れても、届いた位置より先へは進めない
    func testInterpolateStopsAtDestination() {
        let late = BalloonFeed.interpolate(from: tokyo, to: niigata, fraction: 3)
        XCTAssertEqual(late.latitude, niigata.latitude, accuracy: 1e-9)
        XCTAssertEqual(late.longitude, niigata.longitude, accuracy: 1e-9)
    }

    func testInterpolateStartsAtOrigin() {
        let start = BalloonFeed.interpolate(from: tokyo, to: niigata, fraction: 0)
        XCTAssertEqual(start.latitude, tokyo.latitude, accuracy: 1e-9)
        XCTAssertEqual(start.longitude, tokyo.longitude, accuracy: 1e-9)
    }
}
