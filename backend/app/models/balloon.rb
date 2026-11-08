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
    user.with_lock do
      # 先に flying か読んで確かめないのは、読んでから更新するまでに他の人が回収すると、二人とも成功してしまうから
      raise NotFlying unless Balloon.flying.where(id:).update_all(status: "collected", ended_at: Time.current) == 1

      # 今日の回収済みを先に exists? で確かめないのは、同じ人が同時に回収すると両方通してしまうから。一意制約に任せる
      user.favorites.create!(balloon: self, collected_on: Date.current)
    end
  end

  def self.move_flying!(wind:, speed_scale:, now: Time.current)
    transaction do
      balloons = flying.order(:id).lock.to_a
      next if balloons.empty?

      # ロック待ち中に再配置された場合、更新時刻より前から移動を計算しない。
      now = [ now, balloons.map(&:moved_at).max ].max
      rows = balloons.map { |balloon| balloon.bound_for ? balloon.sail(now:, speed_scale:) : balloon.drift(wind:, speed_scale:, now:) }

      # 1行ずつ update すると、5秒ごとに風船の数だけ SQL が走るので、JSON で渡してまとめて1文にする。
      # 読んだあとに回収された風船を動かさないよう、更新の時点でも flying に絞る
      connection.exec_update(sanitize_sql_array([ <<~SQL, now, now, rows.to_json ]))
        UPDATE balloons
        SET lat = v.lat, lng = v.lng, speed_east = v.speed_east, speed_north = v.speed_north, moved_at = ?,
            status = CASE WHEN v.lost THEN 'lost' ELSE balloons.status END,
            ended_at = CASE WHEN v.lost THEN ? ELSE balloons.ended_at END,
            last_port = v.last_port, bound_for = v.bound_for, boarded_at = v.boarded_at
        FROM jsonb_to_recordset(?::jsonb) AS v(id bigint, lat float8, lng float8, speed_east float8, speed_north float8, lost boolean,
                                               last_port integer, bound_for integer, boarded_at timestamp)
        WHERE balloons.id = v.id AND balloons.status = 'flying'
      SQL
    end
  end

  def drift(wind:, speed_scale:, now:)
    east, north = WindGrid.velocity(wind, lat, lng)
    meters = speed_scale * (now - moved_at)
    to = [ lat + north * meters / METERS_PER_DEGREE, lng + east * meters / (METERS_PER_DEGREE * Math.cos(lat * Math::PI / 180)) ]

    port = SeaRoutes.port_near([ lat, lng ], to, origin: [ origin_lat, origin_lng ], except: last_port)
    return board(port, SeaRoutes.pick(port), boarded_at: now, speed_scale:) if port

    row(*to, east, north, lost: !JapanEez.cover?(*to))
  end

  def sail(now:, speed_scale:)
    fraction = (now - boarded_at) / SeaRoutes::VOYAGE.to_f
    return land if fraction >= 1

    board(last_port, bound_for, boarded_at:, speed_scale:, fraction:)
  end

  private
    def board(from, to, boarded_at:, speed_scale:, fraction: 0)
      lat, lng, east, north = SeaRoutes.at(from, to, fraction)
      # 端末は ve・vn に speed_scale をかけて位置を補うので、船の実際の速さを倍率で割って渡す。
      # jsonb_to_recordset の timestamp は時差を読み捨てるので、DB と同じ UTC にして渡す
      row(lat, lng, east / speed_scale, north / speed_scale, last_port: from, bound_for: to, boarded_at: boarded_at.utc)
    end

    def land
      row(*SeaRoutes::POINTS[bound_for], 0.0, 0.0, last_port: bound_for)
    end

    def row(lat, lng, east, north, lost: false, last_port: self.last_port, bound_for: nil, boarded_at: nil)
      { id:, lat:, lng:, speed_east: east, speed_north: north, lost:, last_port:, bound_for:, boarded_at: }
    end
end
