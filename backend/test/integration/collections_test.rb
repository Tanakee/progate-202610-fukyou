require "test_helper"

class CollectionsTest < ActionDispatch::IntegrationTest
  test "他の人の風船を回収すると、お気に入りに入れて風船の旅を終える" do
    balloon = balloons(:bob_flying)

    post "/balloons/#{balloon.id}/collect", headers: auth_header("alice-token")

    assert_response :ok
    assert_equal balloon.id, json["balloon_id"]
    assert_equal Date.current.to_s, json["collected_on"]
    assert_equal({ "id" => tracks(:bob_song).id, "title" => "空の向こう", "artist" => "推しバンド", "mp3_url" => "https://storage.example.com/tracks/bob_song.mp3" }, json["track"])
    assert_equal "collected", balloon.reload.status
    assert balloon.ended_at
  end

  test "回収済みの本人が再送したら、同じお気に入りを返す" do
    2.times { post "/balloons/#{balloons(:bob_flying).id}/collect", headers: auth_header("alice-token") }

    assert_response :ok
    assert_equal 1, users(:alice).favorites.count
  end

  test "自分の風船は回収できない" do
    post "/balloons/#{balloons(:flying).id}/collect", headers: auth_header("alice-token")

    assert_response :forbidden
    assert_equal "own_balloon", json["code"]
    assert_equal "flying", balloons(:flying).reload.status
  end

  test "飛行中でない風船は 409 で、回収回数を消費しない" do
    post "/balloons/#{balloons(:lost).id}/collect", headers: auth_header("bob-token")
    assert_response :conflict
    assert_equal "balloon_not_flying", json["code"]

    post "/balloons/#{balloons(:flying).id}/collect", headers: auth_header("bob-token")
    assert_response :ok
  end

  test "今日すでに回収していれば 429 で、風船は飛んだまま" do
    users(:alice).favorites.create!(balloon: balloons(:lost), collected_on: Date.current)

    post "/balloons/#{balloons(:bob_flying).id}/collect", headers: auth_header("alice-token")

    assert_response :too_many_requests
    assert_equal "daily_limit_reached", json["code"]
    assert_equal "flying", balloons(:bob_flying).reload.status
  end

  test "1日の区切りは日本時間の0時" do
    travel_to Time.zone.parse("2026-11-08 00:30") do
      users(:alice).favorites.create!(balloon: balloons(:lost), collected_on: Date.new(2026, 11, 7))

      post "/balloons/#{balloons(:bob_flying).id}/collect", headers: auth_header("alice-token")

      assert_response :ok
      assert_equal "2026-11-08", json["collected_on"]
    end
  end
end
