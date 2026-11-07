require "test_helper"

class BalloonsChannelTest < ActionCable::Channel::TestCase
  test "接続すると全員向けの配信を受け取り、その場で snapshot が届く" do
    subscribe

    assert subscription.confirmed?
    assert_has_stream "balloons"
    snapshot = transmissions.last
    assert_equal "balloons.snapshot", snapshot["event"]
    assert_equal Rails.configuration.x.speed_scale, snapshot["speed_scale"]
  end

  test "snapshot には飛行中の風船だけを載せ、飛ばした人は載せない" do
    subscribe

    sent = transmissions.last["balloons"]
    assert_equal Balloon.flying.ids.sort, sent.map { _1["id"] }.sort
    assert_not_includes sent.map { _1["id"] }, balloons(:lost).id
    flying = balloons(:flying)
    assert_includes sent, { "id" => flying.id, "track_id" => flying.track_id, "lat" => 33.5, "lng" => 130.5, "ve" => 0.0, "vn" => 0.0 }
  end

  test "定期処理からの snapshot を全員向けに配信する" do
    assert_broadcasts("balloons", 1) { BalloonsChannel.broadcast_snapshot }
  end
end
