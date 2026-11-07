class Balloon < ApplicationRecord
  METERS_PER_DEGREE = 111_320.0

  belongs_to :user
  belongs_to :track
  has_one :journey

  class NotFlying < StandardError; end

  scope :flying, -> { where(status: "flying") }

  validates :origin_label, presence: true
  validates :origin_lat, :origin_lng, numericality: true
  # 緯度・経度の範囲で決めないのは、範囲の中でも排他的経済水域の外なら、次の定期処理ですぐ割れてしまうから
  validate do
    errors.add(:origin, :out_of_range) unless errors.any? || JapanEez.cover?(origin_lat, origin_lng)
  end

  before_validation on: :create do
    self.lat = origin_lat
    self.lng = origin_lng
    self.launched_at = self.moved_at = Time.current
  end

  def collect_by!(user)
    transaction do
      # 先に flying か読んで確かめないのは、読んでから更新するまでに他の人が回収すると、二人とも成功してしまうから
      raise NotFlying unless Balloon.flying.where(id:).update_all(status: "collected", ended_at: Time.current) == 1

      # 今日の回収済みを先に exists? で確かめないのは、同じ人が同時に回収すると両方通してしまうから。一意制約に任せる
      user.favorites.create!(balloon: self, collected_on: Date.current)
    end
  end

  def self.move_flying!(wind:, speed_scale:, now: Time.current)
    rows = flying.map { |balloon| balloon.sea_route ? balloon.sail(now:, speed_scale:) : balloon.drift(wind:, speed_scale:, now:) }
    return if rows.empty?

    # 1行ずつ update すると、5秒ごとに風船の数だけ SQL が走るので、JSON で渡してまとめて1文にする。
    # 読んだあとに回収された風船を動かさないよう、更新の時点でも flying に絞る
    connection.exec_update(sanitize_sql_array([ <<~SQL, now, now, rows.to_json ]))
      UPDATE balloons
      SET lat = v.lat, lng = v.lng, speed_east = v.speed_east, speed_north = v.speed_north, moved_at = ?,
          status = CASE WHEN v.lost THEN 'lost' ELSE balloons.status END,
          ended_at = CASE WHEN v.lost THEN ? ELSE balloons.ended_at END,
          sea_route = v.sea_route, boarded_at = v.boarded_at, last_port = v.last_port
      FROM jsonb_to_recordset(?::jsonb) AS v(id bigint, lat float8, lng float8, speed_east float8, speed_north float8, lost boolean,
                                             sea_route integer, boarded_at timestamp, last_port integer)
      WHERE balloons.id = v.id AND balloons.status = 'flying'
    SQL
  end

  def drift(wind:, speed_scale:, now:)
    east, north = WindGrid.velocity(wind, lat, lng)
    meters = speed_scale * (now - moved_at)
    to = [ lat + north * meters / METERS_PER_DEGREE, lng + east * meters / (METERS_PER_DEGREE * Math.cos(lat * Math::PI / 180)) ]

    port = SeaRoutes.port_near([ lat, lng ], to, except: last_port)
    return board(SeaRoutes.pick(port), boarded_at: now, speed_scale:) if port

    row(*to, east, north, lost: !JapanEez.cover?(*to))
  end

  def sail(now:, speed_scale:)
    fraction = (now - boarded_at) / SeaRoutes::VOYAGE.to_f
    return land if fraction >= 1

    board(sea_route, boarded_at:, speed_scale:, fraction:)
  end

  private
    def board(route, boarded_at:, speed_scale:, fraction: 0)
      lat, lng, east, north = SeaRoutes.at(route, fraction)
      # 端末は ve・vn に speed_scale をかけて位置を補うので、船の実際の速さを倍率で割って渡す。
      # jsonb_to_recordset の timestamp は時差を読み捨てるので、DB と同じ UTC にして渡す
      row(lat, lng, east / speed_scale, north / speed_scale, sea_route: route, boarded_at: boarded_at.utc)
    end

    def land
      port = SeaRoutes::PORTS[SeaRoutes::ROUTES[sea_route]["to"]]
      row(port["lat"], port["lng"], 0.0, 0.0, last_port: SeaRoutes::ROUTES[sea_route]["to"])
    end

    def row(lat, lng, east, north, lost: false, sea_route: nil, boarded_at: nil, last_port: self.last_port)
      { id:, lat:, lng:, speed_east: east, speed_north: north, lost:, sea_route:, boarded_at:, last_port: }
    end
end
