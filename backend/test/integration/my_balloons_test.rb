require "test_helper"

class MyBalloonsTest < ActionDispatch::IntegrationTest
  test "飛行中の自分の風船だけを返す" do
    get "/me/balloons", headers: auth_header("alice-token")

    assert_response :ok
    assert_equal [ balloons(:flying).id ], json.map { _1["id"] }
    assert_equal %w[ended_at id lat launched_at lng origin_label origin_lat origin_lng play_count speed_east speed_north status track_id],
      json.first.keys.sort
  end

  test "飛行中の風船がなければ空の配列を返す" do
    balloons(:flying).update!(status: "lost")

    get "/me/balloons", headers: auth_header("alice-token")

    assert_equal [], json
  end

  test "token がなければ 401" do
    get "/me/balloons"

    assert_response :unauthorized
  end
end
