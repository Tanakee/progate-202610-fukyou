require "test_helper"

class BalloonTest < ActiveSupport::TestCase
  WEST_WIND = WindGrid::POINTS.to_h { [ _1, [ 10.0, 0.0 ] ] }
  TOKYO = SeaRoutes::PORTS.index { _1["name"] == "東京" }
  NIIGATA = SeaRoutes::PORTS.index { _1["name"] == "新潟" }
  HAKATA = SeaRoutes::PORTS.index { _1["name"] == "博多" }
  MEINOHAMA = SeaRoutes::PORTS.index { _1["name"] == "姪浜" }

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

  test "太平洋側の港から10km以内に来た風船は、その港から日本海側の港へ向かう船に乗る" do
    balloon = balloons(:flying)
    balloon.update!(lat: port(TOKYO)["lat"] + 0.045, lng: port(TOKYO)["lng"])

    Balloon.move_flying!(wind: {}, speed_scale: 1, now: balloon.moved_at + 5.seconds)

    balloon.reload
    assert_equal TOKYO, balloon.last_port
    assert_includes SeaRoutes::JAPAN_SEA, balloon.bound_for
    assert_equal balloon.moved_at, balloon.boarded_at
    assert_equal [ port(TOKYO)["lat"], port(TOKYO)["lng"] ], [ balloon.lat, balloon.lng ]
  end

  test "日本海側の港に来た風船は、太平洋側の港へ向かう船に乗る" do
    balloon = balloons(:flying)
    balloon.update!(lat: port(NIIGATA)["lat"], lng: port(NIIGATA)["lng"])

    Balloon.move_flying!(wind: {}, speed_scale: 1, now: balloon.moved_at + 5.seconds)

    assert_includes SeaRoutes::PACIFIC, balloon.reload.bound_for
  end

  test "港から10kmより遠ければ、船に乗らない" do
    balloon = balloons(:flying)
    balloon.update!(lat: port(TOKYO)["lat"] + 0.1, lng: port(TOKYO)["lng"])

    Balloon.move_flying!(wind: {}, speed_scale: 1, now: balloon.moved_at + 5.seconds)

    assert_nil balloon.reload.bound_for
  end

  test "風が速くて港を通り過ぎても、通った線の近くに港があれば船に乗る" do
    balloon = balloons(:flying)
    balloon.update!(lat: port(TOKYO)["lat"], lng: port(TOKYO)["lng"] - 0.2)

    Balloon.move_flying!(wind: WEST_WIND, speed_scale: 1, now: balloon.moved_at + 3400.seconds)

    assert_equal TOKYO, balloon.reload.last_port
  end

  test "飛ばした場所から10km以内の港では、船に乗らない" do
    balloon = balloons(:flying)
    balloon.update!(origin_lat: port(NIIGATA)["lat"] + 0.045, origin_lng: port(NIIGATA)["lng"], lat: port(NIIGATA)["lat"], lng: port(NIIGATA)["lng"])

    Balloon.move_flying!(wind: {}, speed_scale: 1, now: balloon.moved_at + 5.seconds)

    assert_nil balloon.reload.bound_for
  end

  test "船に乗った風船は、風に関係なく進む" do
    positions = [ WEST_WIND, {} ].map do |wind|
      balloon = sailing_balloon
      Balloon.move_flying!(wind:, speed_scale: 1, now: balloon.boarded_at + 30.seconds)
      balloon.reload.then { [ _1.lat, _1.lng ] }
    end

    assert_equal positions.first, positions.last
    assert_not_equal [ port(TOKYO)["lat"], port(TOKYO)["lng"] ], positions.first
  end

  test "端末が速度の倍率をかけて補えるよう、船の速さは倍率で割って保存する" do
    speeds = [ 1, 300 ].map do |speed_scale|
      balloon = sailing_balloon
      Balloon.move_flying!(wind: {}, speed_scale:, now: balloon.boarded_at + 30.seconds)
      balloon.reload.then { Math.hypot(_1.speed_east, _1.speed_north) }
    end

    assert_in_delta speeds.first / 300, speeds.last, 0.000001
  end

  test "港までの距離によらず、1分で行き先の港に着いて降り、また風で漂う" do
    balloon = sailing_balloon

    Balloon.move_flying!(wind: {}, speed_scale: 1, now: balloon.boarded_at + 59.seconds)
    assert_equal NIIGATA, balloon.reload.bound_for

    Balloon.move_flying!(wind: {}, speed_scale: 1, now: balloon.boarded_at + 1.minute)
    balloon.reload
    assert_nil balloon.bound_for
    assert_equal NIIGATA, balloon.last_port
    assert_equal [ port(NIIGATA)["lat"], port(NIIGATA)["lng"] ], [ balloon.lat, balloon.lng ]
  end

  test "降りた港では、すぐに船に乗り直さない" do
    balloon = balloons(:flying)
    balloon.update!(lat: port(NIIGATA)["lat"], lng: port(NIIGATA)["lng"], last_port: NIIGATA)

    Balloon.move_flying!(wind: {}, speed_scale: 1, now: balloon.moved_at + 5.seconds)

    assert_nil balloon.reload.bound_for
  end

  test "降りた港から10km以内のほかの港でも、すぐに船に乗り直さない" do
    balloon = balloons(:flying)
    balloon.update!(lat: port(MEINOHAMA)["lat"], lng: port(MEINOHAMA)["lng"], last_port: HAKATA)

    Balloon.move_flying!(wind: {}, speed_scale: 1, now: balloon.moved_at + 5.seconds)

    assert_nil balloon.reload.bound_for
  end

  private
    def port(index)
      SeaRoutes::PORTS[index]
    end

    def sailing_balloon
      balloons(:flying).tap do |balloon|
        balloon.update!(lat: port(TOKYO)["lat"], lng: port(TOKYO)["lng"], moved_at: Time.utc(2026, 11, 7),
                        last_port: TOKYO, bound_for: NIIGATA, boarded_at: Time.utc(2026, 11, 7))
      end
    end
end
