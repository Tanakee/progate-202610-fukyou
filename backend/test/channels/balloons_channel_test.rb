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
    assert sent.all? { _1.keys.sort == %w[id lat lng track_id ve vn] }
  end

  test "定期処理からの snapshot を全員向けに配信する" do
    assert_broadcasts("balloons", 1) { BalloonsChannel.broadcast_snapshot }
  end
end
