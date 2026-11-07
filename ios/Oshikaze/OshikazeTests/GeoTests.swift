import CoreLocation
import XCTest
@testable import Oshikaze

final class GeoTests: XCTestCase {
    private let tokyo = CLLocationCoordinate2D(latitude: 35.68, longitude: 139.77)

    /// AR の空で風船を置く方角。北を0として時計回り
    func testBearingPointsToEachDirection() {
        XCTAssertEqual(Geo.bearing(from: tokyo, to: Geo.advance(tokyo, east: 0, north: 10_000)), 0, accuracy: 0.01)
        XCTAssertEqual(Geo.bearing(from: tokyo, to: Geo.advance(tokyo, east: 10_000, north: 0)), .pi / 2, accuracy: 0.01)
        XCTAssertEqual(abs(Geo.bearing(from: tokyo, to: Geo.advance(tokyo, east: 0, north: -10_000))), .pi, accuracy: 0.01)
        XCTAssertEqual(Geo.bearing(from: tokyo, to: Geo.advance(tokyo, east: -10_000, north: 0)), -.pi / 2, accuracy: 0.01)
    }
}
