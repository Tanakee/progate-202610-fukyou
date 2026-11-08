import CoreLocation

/// 流す風船を決める。曲が頻繁に切り替わらないよう、今の風船より十分に近いときだけ乗り換える
enum NearestBalloonPicker {
    /// 今の風船の距離の9割より近ければ乗り換える（設計書の「1割以上近いとき」）
    static let switchRatio = 0.9

    /// - Parameters:
    ///   - current: 今流している風船のID。消えていれば一番近い風船にすぐ乗り換える
    ///   - excluded: 自分の風船と割った風船のID
    static func pick(from balloons: [Balloon],
                     at location: CLLocationCoordinate2D,
                     current: Int?,
                     excluded: Set<Int> = []) -> Int? {
        let candidates = balloons
            .filter { !excluded.contains($0.id) }
            .map { (id: $0.id, distance: Geo.distance(location, $0.coordinate)) }
        guard let nearest = candidates.min(by: { $0.distance < $1.distance }) else { return nil }
        guard let current, let currentDistance = candidates.first(where: { $0.id == current })?.distance else {
            return nearest.id
        }
        return nearest.distance < currentDistance * switchRatio ? nearest.id : current
    }
}
