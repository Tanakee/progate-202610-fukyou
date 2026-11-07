require "test_helper"

class BalloonTest < ActiveSupport::TestCase
  WEST_WIND = WindGrid::POINTS.to_h { [ _1, [ 10.0, 0.0 ] ] }
  AOMORI = SeaRoutes::PORTS.index { _1["name"] == "青森" }
  HAKODATE = SeaRoutes::PORTS.index { _1["name"] == "函館" }
  AOMORI_TO_HAKODATE = SeaRoutes::ROUTES.index { _1["from"] == AOMORI && _1["to"] == HAKODATE }

  test "飛行中の風船を、前回からの経過時間だけ風で進める" do
    balloon = balloons(:flying)

    Balloon.move_flying!(wind: WEST_WIND, speed_scale: 1, now: balloon.moved_at + 100.seconds)

    balloon.reload
    meters_east = (balloon.lng - 130.5) * Balloon::METERS_PER_DEGREE * Math.cos(33.5 * Math::PI / 180)
    assert_in_delta 1000, meters_east, 0.01
    assert_in_delta 33.5, balloon.lat, 0.000001
    assert_equal [ 10.0, 0.0 ], [ balloon.speed_east, balloon.speed_north ]
    assert_equal Time.utc(2026, 11, 7, 0, 1, 40), balloon.moved_at
  end

  test "速度の倍率だけ速く進める" do
    balloon = balloons(:flying)

    Balloon.move_flying!(wind: WEST_WIND, speed_scale: 3, now: balloon.moved_at + 100.seconds)

    meters_east = (balloon.reload.lng - 130.5) * Balloon::METERS_PER_DEGREE * Math.cos(33.5 * Math::PI / 180)
    assert_in_delta 3000, meters_east, 0.01
  end

  test "飛行中でない風船は動かさない" do
    assert_no_changes -> { balloons(:lost).reload.attributes } do
      Balloon.move_flying!(wind: WEST_WIND, speed_scale: 1, now: Time.current)
    end
  end

  test "風データがなければ、その場にとどまる" do
    balloon = balloons(:flying)

    Balloon.move_flying!(wind: {}, speed_scale: 1, now: balloon.moved_at + 100.seconds)

    assert_equal [ 33.5, 130.5 ], [ balloon.reload.lat, balloon.lng ]
  end

  test "日本の排他的経済水域の外へ出た風船は割れる" do
    balloon = balloons(:flying)
    balloon.update!(lat: 35.0, lng: 157.0)

    Balloon.move_flying!(wind: WEST_WIND, speed_scale: 1, now: balloon.moved_at + 100.seconds)

    balloon.reload
    assert_equal "lost", balloon.status
    assert_equal Time.utc(2026, 11, 7, 0, 1, 40), balloon.ended_at
  end

  test "排他的経済水域の中にいる風船は飛び続ける" do
    Balloon.move_flying!(wind: WEST_WIND, speed_scale: 1, now: balloons(:flying).moved_at + 100.seconds)

    assert_equal "flying", balloons(:flying).reload.status
  end

  test "港から10km以内に来た風船は、その港から出る航路に乗り、港へ移る" do
    balloon = balloons(:flying)
    balloon.update!(lat: port(AOMORI)["lat"] + 0.045, lng: port(AOMORI)["lng"])

    Balloon.move_flying!(wind: {}, speed_scale: 1, now: balloon.moved_at + 5.seconds)

    balloon.reload
    assert_equal AOMORI_TO_HAKODATE, balloon.sea_route
    assert_equal balloon.moved_at, balloon.boarded_at
    assert_equal [ port(AOMORI)["lat"], port(AOMORI)["lng"] ], [ balloon.lat, balloon.lng ]
  end

  test "港から10kmより遠ければ、航路に乗らない" do
    balloon = balloons(:flying)
    balloon.update!(lat: port(AOMORI)["lat"] + 0.1, lng: port(AOMORI)["lng"])

    Balloon.move_flying!(wind: {}, speed_scale: 1, now: balloon.moved_at + 5.seconds)

    assert_nil balloon.reload.sea_route
  end

  test "風が速くて港を通り過ぎても、通った線の近くに港があれば航路に乗る" do
    balloon = balloons(:flying)
    balloon.update!(lat: port(AOMORI)["lat"], lng: port(AOMORI)["lng"] - 0.2)

    Balloon.move_flying!(wind: WEST_WIND, speed_scale: 1, now: balloon.moved_at + 3400.seconds)

    assert_equal AOMORI_TO_HAKODATE, balloon.reload.sea_route
  end

  test "航路に乗った風船は、風に関係なく、距離によらず1分で航路を進む" do
    balloon = sailing_balloon

    Balloon.move_flying!(wind: WEST_WIND, speed_scale: 300, now: balloon.boarded_at + 30.seconds)

    balloon.reload
    assert_in_delta (port(AOMORI)["lat"] + port(HAKODATE)["lat"]) / 2, balloon.lat, 0.0001
    assert_in_delta (port(AOMORI)["lng"] + port(HAKODATE)["lng"]) / 2, balloon.lng, 0.0001
    assert_equal AOMORI_TO_HAKODATE, balloon.sea_route
  end

  test "端末が速度の倍率をかけて補えるよう、航路の上の速さは倍率で割って保存する" do
    balloon = sailing_balloon

    Balloon.move_flying!(wind: {}, speed_scale: 300, now: balloon.boarded_at + 30.seconds)

    route_meters = Math.hypot((port(HAKODATE)["lat"] - port(AOMORI)["lat"]) * Balloon::METERS_PER_DEGREE,
                              (port(HAKODATE)["lng"] - port(AOMORI)["lng"]) * Balloon::METERS_PER_DEGREE * Math.cos(port(AOMORI)["lat"] * Math::PI / 180))
    balloon.reload
    assert_in_delta route_meters / 60 / 300, Math.hypot(balloon.speed_east, balloon.speed_north), 0.001
  end

  test "1分たつと行き先の港で降り、また風で漂う" do
    balloon = sailing_balloon

    Balloon.move_flying!(wind: {}, speed_scale: 1, now: balloon.boarded_at + 1.minute)

    balloon.reload
    assert_nil balloon.sea_route
    assert_equal HAKODATE, balloon.last_port
    assert_equal [ port(HAKODATE)["lat"], port(HAKODATE)["lng"] ], [ balloon.lat, balloon.lng ]
  end

  test "降りた港では、すぐに航路に乗り直さない" do
    balloon = balloons(:flying)
    balloon.update!(lat: port(HAKODATE)["lat"], lng: port(HAKODATE)["lng"], last_port: HAKODATE)

    Balloon.move_flying!(wind: {}, speed_scale: 1, now: balloon.moved_at + 5.seconds)

    assert_nil balloon.reload.sea_route
  end

  private
    def port(index)
      SeaRoutes::PORTS[index]
    end

    def sailing_balloon
      balloons(:flying).tap do |balloon|
        balloon.update!(lat: port(AOMORI)["lat"], lng: port(AOMORI)["lng"], sea_route: AOMORI_TO_HAKODATE, boarded_at: balloon.moved_at)
      end
    end
end
