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

  test "1時間より前の予報は消す" do
    import_forecast(speed: 10, direction: 270, valid_time: 2.hours.ago)

    assert_equal 0, WindGrid.count
  end

  test "その時刻に有効な、最新の予報を返す" do
    this_hour = Time.current.beginning_of_hour
    import_forecast(speed: 10, direction: 270, valid_time: this_hour)
    import_forecast(speed: 10, direction: 0, valid_time: this_hour + 1.hour)

    wind = WindGrid.at(this_hour + 30.minutes)

    assert_equal [ [ 35, 140 ] ], wind.keys
    assert_equal [ 10.0, 0.0 ], wind[[ 35, 140 ]].map { _1.round(3) }
  end

  test "まだ取得していない格子点を先に、次に取得が古い格子点を選ぶ" do
    never_fetched = WindGrid::POINTS.first(60)
    fetched_long_ago = WindGrid::POINTS[60, 60]
    store_points(fetched_long_ago, fetched_at: 2.hours.ago)
    store_points(WindGrid::POINTS.drop(120), fetched_at: 1.minute.ago)

    points = WindGrid.stalest_points

    assert_equal WindGrid::BATCH_SIZE, points.size
    assert_empty never_fetched - points
    assert_empty points - never_fetched - fetched_long_ago
  end

  test "取得していない格子点があれば、間隔を待たずに取得する" do
    store_points(WindGrid::POINTS.drop(1), fetched_at: 1.minute.ago)

    assert WindGrid.fetch_due?
  end

  test "全ての格子点がそろっていれば、前回の取得から20分たつまで取得しない" do
    store_points(WindGrid::POINTS, fetched_at: 19.minutes.ago)

    assert_not WindGrid.fetch_due?
  end

  test "全ての格子点がそろっていても、前回の取得から20分たてば取得する" do
    store_points(WindGrid::POINTS, fetched_at: 21.minutes.ago)

    assert WindGrid.fetch_due?
  end

  test "格子点の間では、周りの4点の風を距離で重み付けして求める" do
    wind = { [ 35, 140 ] => [ 0.0, 0.0 ], [ 36, 140 ] => [ 4.0, 0.0 ], [ 35, 141 ] => [ 0.0, 8.0 ], [ 36, 141 ] => [ 4.0, 8.0 ] }

    assert_equal [ 2.0, 2.0 ], WindGrid.velocity(wind, 35.5, 140.25)
  end

  test "まだ風を取得していない格子点では、初期値の風を使う" do
    wind = { [ 35, 140 ] => [ 4.0, 4.0 ] }
    default_east, default_north = WindGrid.default_velocity

    east, north = WindGrid.velocity(wind, 35.5, 140.5)

    assert_in_delta 1.0 + 0.75 * default_east, east, 0.000001
    assert_in_delta 1.0 + 0.75 * default_north, north, 0.000001
  end

  test "初期値の風は、吹いてくる向きと速さから求める" do
    assert_equal [ 5.0, 0.0 ], WindGrid.to_velocity(speed: 5, direction: 270).map { _1.round(6) }
  end

  test "格子の外では、いちばん近い端の風を使う" do
    wind = WindGrid::POINTS.to_h { [ _1, [ 1.0, 2.0 ] ] }

    assert_equal [ 1.0, 2.0 ], WindGrid.velocity(wind, 10.0, 160.0)
  end

  private
    def import_forecast(speed:, direction:, valid_time: Time.current.beginning_of_hour, returned_lat: 35.0, returned_lng: 140.0)
      forecast = {
        "latitude" => returned_lat, "longitude" => returned_lng,
        "hourly" => { "time" => [ valid_time.utc.strftime("%Y-%m-%dT%H:%M") ], "wind_speed_10m" => [ speed ], "wind_direction_10m" => [ direction ] }
      }
      WindGrid.import!([ [ 35, 140 ] ], [ forecast ], fetched_at: Time.current)
    end

    def store_points(points, fetched_at:, valid_time: Time.current.beginning_of_hour)
      WindGrid.insert_all(points.map { |lat, lng| { lat:, lng:, valid_time:, speed_east: 0, speed_north: 0, fetched_at: } })
    end
end
