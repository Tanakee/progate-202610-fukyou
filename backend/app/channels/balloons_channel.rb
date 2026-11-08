class BalloonsChannel < ApplicationCable::Channel
  def self.broadcast_snapshot
    ActionCable.server.broadcast("balloons", snapshot)
  end

  def self.snapshot
    now = Time.current
    {
      event: "balloons.snapshot",
      # 連番にしないのは、接続時に送る Web と5秒ごとに送る定期処理が別のプロセスで、番号を共有できないから
      seq: (now.to_f * 1000).to_i,
      server_time: now,
      speed_scale: Rails.configuration.x.speed_scale,
      balloons: Balloon.flying.pluck(:id, :track_id, :lat, :lng, :speed_east, :speed_north, :bound_for).map do |id, track_id, lat, lng, ve, vn, bound_for|
        { id:, track_id:, lat:, lng:, ve:, vn:, on_ship: !bound_for.nil? }
      end
    }
  end

  def subscribed
    stream_from "balloons"
    transmit self.class.snapshot
  end
end
