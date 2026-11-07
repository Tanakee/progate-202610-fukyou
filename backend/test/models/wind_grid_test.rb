require "test_helper"

class WindGridTest < ActiveSupport::TestCase
  test "風向は吹いてくる向きなので、西風は東向きの速さとして保存する" do
    import_forecast(speed: 10, direction: 270)

    wind = WindGrid.find_by!(lat: 35, lng: 140)
    assert_in_delta 10, wind.speed_east, 0.001
    assert_in_delta 0, wind.speed_north, 0.001
  end

  test "Open-Meteo が返す座標ではなく、頼んだ格子点の座標で保存する" do
    import_forecast(speed: 10, direction: 270, returned_lat: 34.97, returned_lng: 139.98)

    assert WindGrid.exists?(lat: 35, lng: 140)
  end

  test "値が欠けている時刻は保存しない" do
    import_forecast(speed: nil, direction: 270)

    assert_equal 0, WindGrid.count
  end

  test "その時刻に有効な、最新の予報を返す" do
    import_forecast(speed: 10, direction: 270, time: "2026-11-07T00:00")
    import_forecast(speed: 10, direction: 0, time: "2026-11-07T01:00")

    assert_equal({ [ 35, 140 ] => [ 10.0, 0.0 ] }, WindGrid.at(Time.utc(2026, 11, 7, 0, 30)).transform_values { |v| v.map { _1.round(3) } })
  end

  test "格子点の間では、周りの4点の風を距離で重み付けして求める" do
    wind = { [ 35, 140 ] => [ 0.0, 0.0 ], [ 36, 140 ] => [ 4.0, 0.0 ], [ 35, 141 ] => [ 0.0, 8.0 ], [ 36, 141 ] => [ 4.0, 8.0 ] }

    assert_equal [ 2.0, 2.0 ], WindGrid.velocity(wind, 35.5, 140.25)
  end

  test "まだ風を取得していない格子点は無風として扱う" do
    wind = { [ 35, 140 ] => [ 4.0, 4.0 ] }

    assert_equal [ 1.0, 1.0 ], WindGrid.velocity(wind, 35.5, 140.5)
  end

  test "格子の外では、いちばん近い端の風を使う" do
    wind = WindGrid::LATITUDES.to_a.product(WindGrid::LONGITUDES.to_a).to_h { [ _1, [ 1.0, 2.0 ] ] }

    assert_equal [ 1.0, 2.0 ], WindGrid.velocity(wind, 10.0, 160.0)
  end

  private
    def import_forecast(speed:, direction:, time: "2026-11-07T00:00", returned_lat: 35.0, returned_lng: 140.0)
      forecast = {
        "latitude" => returned_lat, "longitude" => returned_lng,
        "hourly" => { "time" => [ time ], "wind_speed_10m" => [ speed ], "wind_direction_10m" => [ direction ] }
      }
      WindGrid.import!([ [ 35, 140 ] ], [ forecast ], fetched_at: Time.current)
    end
end
