import CoreLocation
import XCTest
@testable import Oshikaze

final class NearestBalloonPickerTests: XCTestCase {
    private let tokyo = CLLocationCoordinate2D(latitude: 35.68, longitude: 139.77)

    /// 東京から真北へ km だけ離れた風船
    private func balloon(_ id: Int, kilometersNorth km: Double) -> Balloon {
        Balloon(id: id, trackID: id, coordinate: Geo.advance(tokyo, east: 0, north: km * 1000))
    }

    func testPicksNearestWhenNothingIsPlaying() {
        let balloons = [balloon(1, kilometersNorth: 50), balloon(2, kilometersNorth: 10)]
        XCTAssertEqual(NearestBalloonPicker.pick(from: balloons, at: tokyo, current: nil), 2)
    }

    func testKeepsCurrentWhenOtherIsLessThanTenPercentCloser() {
        let balloons = [balloon(1, kilometersNorth: 10), balloon(2, kilometersNorth: 9.5)]
        XCTAssertEqual(NearestBalloonPicker.pick(from: balloons, at: tokyo, current: 1), 1)
    }

    func testSwitchesWhenOtherIsMoreThanTenPercentCloser() {
        let balloons = [balloon(1, kilometersNorth: 10), balloon(2, kilometersNorth: 8)]
        XCTAssertEqual(NearestBalloonPicker.pick(from: balloons, at: tokyo, current: 1), 2)
    }

    func testPicksNearestWhenCurrentIsGone() {
        let balloons = [balloon(2, kilometersNorth: 30), balloon(3, kilometersNorth: 20)]
        XCTAssertEqual(NearestBalloonPicker.pick(from: balloons, at: tokyo, current: 1), 3)
    }

    func testSkipsExcludedBalloons() {
        let balloons = [balloon(1, kilometersNorth: 1), balloon(2, kilometersNorth: 20)]
        XCTAssertEqual(NearestBalloonPicker.pick(from: balloons, at: tokyo, current: nil, excluded: [1]), 2)
    }

    func testReturnsNilWhenNoBalloons() {
        XCTAssertNil(NearestBalloonPicker.pick(from: [], at: tokyo, current: 1))
    }
}
