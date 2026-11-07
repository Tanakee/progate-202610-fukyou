require "net/http"

class WindGrid < ApplicationRecord
  self.table_name = "wind_grid"

  LATITUDES = 20..50
  LONGITUDES = 122..148
  POINTS = LATITUDES.to_a.product(LONGITUDES.to_a)
  # Open-Meteo の無料枠は地点の数で数え、1時間に5,000、1日に10,000まで。
  # 100地点を20分ごとに取ると、一周が約3時間、1日に7,200で収まる
  BATCH_SIZE = 100
  FETCH_INTERVAL = 20.minutes
  FORECAST_URL = "https://api.open-meteo.com/v1/forecast"

  def self.fetch!(points)
    import!(points, request_forecasts(points), fetched_at: Time.current)
  end

  # まだ一度も取得していない格子点があるうちは、一周目を早く埋めるため間隔を待たない
  def self.fetch_due?
    select(:lat, :lng).distinct.count < POINTS.size || maximum(:fetched_at) < FETCH_INTERVAL.ago
  end

  def self.stalest_points
    fetched_at = group(:lat, :lng).maximum(:fetched_at).transform_keys { |lat, lng| [ lat.to_i, lng.to_i ] }
    POINTS.min_by(BATCH_SIZE) { |point| fetched_at[point] || Time.at(0) }
  end

  def self.request_forecasts(points)
    uri = URI(FORECAST_URL)
    uri.query = URI.encode_www_form(
      latitude: points.map(&:first).join(","),
      longitude: points.map(&:last).join(","),
      hourly: "wind_speed_10m,wind_direction_10m",
      wind_speed_unit: "ms",
      timezone: "GMT",
      forecast_days: 2
    )
    response = Net::HTTP.get_response(uri)
    response.value
    JSON.parse(response.body)
  end

  # Open-Meteo は近くのモデルの格子点の座標を返すので、返ってきた座標ではなく頼んだ座標で保存する
  def self.import!(points, forecasts, fetched_at:)
    rows = points.zip(forecasts).flat_map do |(lat, lng), forecast|
      hourly = forecast.fetch("hourly")
      hourly.fetch("time").each_index.filter_map do |i|
        speed = hourly.fetch("wind_speed_10m")[i]
        direction = hourly.fetch("wind_direction_10m")[i]
        next if speed.nil? || direction.nil?

        east, north = to_velocity(speed:, direction:)
        { lat:, lng:, valid_time: Time.find_zone("UTC").parse(hourly["time"][i]), speed_east: east, speed_north: north, fetched_at: }
      end
    end
    upsert_all(rows) if rows.any?
    where(valid_time: ...1.hour.ago).delete_all
  end

  def self.at(time)
    valid_time = where(valid_time: ..time).maximum(:valid_time)
    where(valid_time:).pluck(:lat, :lng, :speed_east, :speed_north).to_h do |lat, lng, east, north|
      [ [ lat.to_i, lng.to_i ], [ east, north ] ]
    end
  end

  # 風向は風が吹いてくる向きなので、風船が進む向きはその逆になる
  def self.to_velocity(speed:, direction:)
    radians = direction * Math::PI / 180
    [ -speed * Math.sin(radians), -speed * Math.cos(radians) ]
  end

  def self.default_velocity
    to_velocity(**Rails.configuration.x.default_wind)
  end

  def self.velocity(wind, lat, lng)
    lat = lat.clamp(LATITUDES.min, LATITUDES.max)
    lng = lng.clamp(LONGITUDES.min, LONGITUDES.max)
    lat0 = [ lat.floor, LATITUDES.max - 1 ].min
    lng0 = [ lng.floor, LONGITUDES.max - 1 ].min
    t = lat - lat0
    u = lng - lng0

    [ [ lat0, lng0, (1 - t) * (1 - u) ], [ lat0 + 1, lng0, t * (1 - u) ], [ lat0, lng0 + 1, (1 - t) * u ], [ lat0 + 1, lng0 + 1, t * u ] ]
      .reduce([ 0.0, 0.0 ]) do |(east, north), (corner_lat, corner_lng, weight)|
        # まだ風を取得していない格子点で無風にすると、起動直後に風船が止まって見えるので、初期値の風を使う
        corner_east, corner_north = wind.fetch([ corner_lat, corner_lng ]) { default_velocity }
        [ east + weight * corner_east, north + weight * corner_north ]
      end
  end
end
