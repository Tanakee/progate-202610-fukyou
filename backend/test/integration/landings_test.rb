require "test_helper"

class LandingsTest < ActionDispatch::IntegrationTest
  test "自分の風船を下ろすと旅を終え、次の風船を飛ばせる" do
    balloon = balloons(:flying)

    post "/balloons/#{balloon.id}/land", headers: auth_header("alice-token")

    assert_response :ok
    assert_equal "landed", json["status"]
    assert_equal "landed", balloon.reload.status
    assert balloon.ended_at
    assert_not_includes BalloonsChannel.snapshot[:balloons].map { _1[:id] }, balloon.id

    post "/balloons", params: { track_id: tracks(:alice_song).id, origin_lat: 35.68, origin_lng: 139.76, origin_label: "千代田区" },
      headers: auth_header("alice-token")
    assert_response :created
  end

  test "他の人の風船は下ろせない" do
    post "/balloons/#{balloons(:bob_flying).id}/land", headers: auth_header("alice-token")

    assert_response :not_found
    assert_equal "flying", balloons(:bob_flying).reload.status
  end

  test "飛んでいない風船は 409" do
    post "/balloons/#{balloons(:lost).id}/land", headers: auth_header("alice-token")

    assert_response :conflict
    assert_equal "balloon_not_flying", json["code"]
  end

  test "token がなければ 401" do
    post "/balloons/#{balloons(:flying).id}/land"

    assert_response :unauthorized
  end
end
