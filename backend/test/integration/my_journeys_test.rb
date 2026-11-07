require "test_helper"

class MyJourneysTest < ActionDispatch::IntegrationTest
  test "自分の風船の旅の記録を新しい順に返す" do
    balloons(:flying).update!(status: "collected", ended_at: Time.current)
    newer = balloons(:flying).create_journey!(end_reason: "collected", end_label: "福岡県福岡市", end_lat: 33.6, end_lng: 130.4,
                                              duration_seconds: 3600, play_count: 5)
    balloons(:bob_flying).create_journey!(end_reason: "lost", end_label: "北海道札幌市", end_lat: 43.0, end_lng: 141.3,
                                          duration_seconds: 60, play_count: 0)

    get "/me/journeys", headers: auth_header("alice-token")

    assert_response :ok
    assert_equal [ newer.id, journeys(:lost).id ], json.map { _1["id"] }
    assert_equal({ "id" => journeys(:lost).id, "balloon_id" => balloons(:lost).id, "end_reason" => "lost", "end_label" => "大阪府大阪市",
                   "end_lat" => 34.5, "end_lng" => 135.5, "duration_seconds" => 86400, "play_count" => 2,
                   "created_at" => journeys(:lost).created_at.as_json },
      json.last)
  end

  test "旅の記録がなければ空の配列を返す" do
    get "/me/journeys", headers: auth_header("bob-token")

    assert_equal [], json
  end

  test "token がなければ 401" do
    get "/me/journeys"

    assert_response :unauthorized
  end
end
