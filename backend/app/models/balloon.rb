class Balloon < ApplicationRecord
  METERS_PER_DEGREE = 111_320.0

  belongs_to :user
  belongs_to :track

  scope :flying, -> { where(status: "flying") }

  def self.move_flying!(wind:, speed_scale:, now: Time.current)
    return if wind.empty?

    rows = flying.map do |balloon|
      east, north = WindGrid.velocity(wind, balloon.lat, balloon.lng)
      meters = speed_scale * (now - balloon.moved_at)
      lat = balloon.lat + north * meters / METERS_PER_DEGREE
      lng = balloon.lng + east * meters / (METERS_PER_DEGREE * Math.cos(balloon.lat * Math::PI / 180))
      sanitize_sql_array([ "(?::bigint, ?::float8, ?::float8, ?::float8, ?::float8, ?::timestamp)", balloon.id, lat, lng, east, north, now ])
    end
    return if rows.empty?

    # 1行ずつ update すると、5秒ごとに風船の数だけ SQL が走るので、VALUES でまとめて1文にする。
    # 読んだあとに回収された風船を動かさないよう、更新の時点でも flying に絞る
    connection.exec_update(<<~SQL)
      UPDATE balloons
      SET lat = v.lat, lng = v.lng, speed_east = v.speed_east, speed_north = v.speed_north, moved_at = v.moved_at
      FROM (VALUES #{rows.join(", ")}) AS v(id, lat, lng, speed_east, speed_north, moved_at)
      WHERE balloons.id = v.id AND balloons.status = 'flying'
    SQL
  end
end
