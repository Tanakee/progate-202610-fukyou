require "test_helper"

class BalloonTest < ActiveSupport::TestCase
  WEST_WIND = WindGrid::POINTS.to_h { [ _1, [ 10.0, 0.0 ] ] }

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

  test "風データがまだなければ動かさない" do
    assert_no_changes -> { balloons(:flying).reload.attributes } do
      Balloon.move_flying!(wind: {}, speed_scale: 1, now: Time.current)
    end
  end

  test "範囲の南東の角から出た風船は、北西の角の側から戻る" do
    balloon = balloons(:flying)
    balloon.update!(lat: 20.001, lng: 147.999)
    south_east_wind = WindGrid::POINTS.to_h { [ _1, [ 10.0, -10.0 ] ] }

    Balloon.move_flying!(wind: south_east_wind, speed_scale: 1, now: balloon.moved_at + 100.seconds)

    balloon.reload
    assert_in_delta 49.992, balloon.lat, 0.001
    assert_in_delta 122.008, balloon.lng, 0.001
  end
end
