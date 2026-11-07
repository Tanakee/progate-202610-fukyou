require "test_helper"

class BalloonsChannelTest < ActionCable::Channel::TestCase
  test "接続すると全員向けの配信を受け取り、その場で snapshot が届く" do
    subscribe

    assert subscription.confirmed?
    assert_has_stream "balloons"
    snapshot = transmissions.last
    assert_equal "balloons.snapshot", snapshot["event"]
    assert_equal 1.0, snapshot["speed_scale"]
  end

  test "snapshot には飛行中の風船だけを載せ、飛ばした人は載せない" do
    subscribe

    flying = balloons(:flying)
    assert_equal [ { "id" => flying.id, "track_id" => flying.track_id, "lat" => 33.5, "lng" => 130.5, "ve" => 0.0, "vn" => 0.0 } ],
      transmissions.last["balloons"]
  end

  test "定期処理からの snapshot を全員向けに配信する" do
    assert_broadcasts("balloons", 1) { BalloonsChannel.broadcast_snapshot }
  end
end
