require "net/http"

class WindGrid < ApplicationRecord
  self.table_name = "wind_grid"

  LATITUDES = 20..50
  LONGITUDES = 122..148
  POINTS = LATITUDES.to_a.product(LONGITUDES.to_a)
  # Open-Meteo の無料枠は1分あたりの地点数に上限があるので、全地点を一度に頼まず300地点ずつ時間をあけて取る
  BATCHES = POINTS.each_slice(300).to_a
  FETCH_INTERVAL = 3.hours
  FORECAST_URL = "https://api.open-meteo.com/v1/forecast"

  def self.fetch!(points)
    import!(points, request_forecasts(points), fetched_at: Time.current)
    where(valid_time: ...FETCH_INTERVAL.ago).delete_all
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

        # 風向は風が吹いてくる向きなので、風船が進む向きはその逆になる
        radians = direction * Math::PI / 180
        {
          lat:, lng:, valid_time: Time.find_zone("UTC").parse(hourly["time"][i]),
          speed_east: -speed * Math.sin(radians), speed_north: -speed * Math.cos(radians), fetched_at:
        }
      end
    end
    upsert_all(rows) if rows.any?
  end

  def self.at(time)
    valid_time = where(valid_time: ..time).maximum(:valid_time)
    where(valid_time:).pluck(:lat, :lng, :speed_east, :speed_north).to_h do |lat, lng, east, north|
      [ [ lat.to_i, lng.to_i ], [ east, north ] ]
    end
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
        # 初めての取得の途中で、まだ風のない格子点は無風として扱う
        corner_east, corner_north = wind.fetch([ corner_lat, corner_lng ], [ 0.0, 0.0 ])
        [ east + weight * corner_east, north + weight * corner_north ]
      end
  end
end
