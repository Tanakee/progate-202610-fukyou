import CoreLocation
import XCTest
@testable import Oshikaze

@MainActor
final class MyBalloonStoreTests: XCTestCase {
    func testBlurRoundsToAboutOneKilometer() {
        let blurred = MyBalloonStore.blur(CLLocationCoordinate2D(latitude: 35.681236, longitude: 139.767125))
        XCTAssertEqual(blurred.latitude, 35.68, accuracy: 1e-9)
        XCTAssertEqual(blurred.longitude, 139.77, accuracy: 1e-9)
    }

    func testBlurredPointStaysWithinOneKilometer() {
        let original = CLLocationCoordinate2D(latitude: 43.0642, longitude: 141.3469)
        XCTAssertLessThan(Geo.distance(original, MyBalloonStore.blur(original)), 1000)
    }
}
