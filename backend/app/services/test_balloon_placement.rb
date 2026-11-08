class TestBalloonPlacement
  # 矩形内の乱数では海上にも配置されるため、日本列島の陸上の地点へ順に置く。
  POINTS = [
    [ 43.0618, 141.3545 ], # 札幌
    [ 38.2682, 140.8694 ], # 仙台
    [ 35.6812, 139.7671 ], # 東京
    [ 34.6937, 135.5023 ], # 大阪
    [ 33.5902, 130.4017 ], # 福岡
    [ 26.2124, 127.6809 ]  # 那覇
  ].map(&:freeze).freeze

  def self.call
    Balloon.transaction do
      # 定期移動と同じ順番でロックし、古い位置からの移動結果に上書きされるのを防ぐ。
      balloons = Balloon.flying.order(:id).lock.to_a
      now = Time.current

      balloons.each_with_index do |balloon, index|
        lat, lng = POINTS[index % POINTS.length]
        balloon.update!(lat: lat, lng: lng, moved_at: now,
          speed_east: 0.0, speed_north: 0.0,
          last_port: nil, bound_for: nil, boarded_at: nil)
      end

      balloons.length
    end
  end
end
