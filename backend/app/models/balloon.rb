class Balloon < ApplicationRecord
  METERS_PER_DEGREE = 111_320.0

  belongs_to :user
  belongs_to :track

  NotFlying = Class.new(StandardError)

  scope :flying, -> { where(status: "flying") }

  def collect_by!(user)
    transaction do
      # 読んでから更新するまでの間に他の人が回収しても二重に成功しないよう、flying の行だけを更新して先着を決める
      raise NotFlying unless Balloon.flying.where(id:).update_all(status: "collected", ended_at: Time.current) == 1

      # 今日すでに回収していれば (user_id, collected_on) の一意制約で失敗し、風船の更新ごと取り消される
      user.favorites.create!(balloon: self, collected_on: Date.current)
    end
  end

  def self.move_flying!(wind:, speed_scale:, now: Time.current)
    rows = flying.map do |balloon|
      east, north = WindGrid.velocity(wind, balloon.lat, balloon.lng)
      meters = speed_scale * (now - balloon.moved_at)
      lat = balloon.lat + north * meters / METERS_PER_DEGREE
      lng = balloon.lng + east * meters / (METERS_PER_DEGREE * Math.cos(balloon.lat * Math::PI / 180))
      { id: balloon.id, lat:, lng:, speed_east: east, speed_north: north, lost: !JapanEez.cover?(lat, lng) }
    end
    return if rows.empty?

    # 1行ずつ update すると、5秒ごとに風船の数だけ SQL が走るので、JSON で渡してまとめて1文にする。
    # 読んだあとに回収された風船を動かさないよう、更新の時点でも flying に絞る
    connection.exec_update(sanitize_sql_array([ <<~SQL, now, now, rows.to_json ]))
      UPDATE balloons
      SET lat = v.lat, lng = v.lng, speed_east = v.speed_east, speed_north = v.speed_north, moved_at = ?,
          status = CASE WHEN v.lost THEN 'lost' ELSE balloons.status END,
          ended_at = CASE WHEN v.lost THEN ? ELSE balloons.ended_at END
      FROM jsonb_to_recordset(?::jsonb) AS v(id bigint, lat float8, lng float8, speed_east float8, speed_north float8, lost boolean)
      WHERE balloons.id = v.id AND balloons.status = 'flying'
    SQL
  end
end
