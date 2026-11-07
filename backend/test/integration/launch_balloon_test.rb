require "test_helper"

class LaunchBalloonTest < ActionDispatch::IntegrationTest
  setup do
    @bob = User.create!(email: "bob@example.com", password: "password123")
    @bob_token = @bob.auth_tokens.create!.token
    @bob_song = @bob.tracks.create!(title: "夜の風", artist: "推しバンド", mp3_url: "https://storage.example.com/tracks/bob_song.mp3")
  end

  test "飛ばすと、出発地点にいる飛行中の風船を返す" do
    assert_difference "@bob.balloons.count", 1 do
      post "/balloons", params: launch_params(track_id: @bob_song.id), headers: auth_header(@bob_token), as: :json
    end

    assert_response :created
    assert_equal %w[ended_at id lat launched_at lng origin_label origin_lat origin_lng play_count speed_east speed_north status track_id], json.keys.sort
    assert_equal "flying", json["status"]
    assert_equal @bob_song.id, json["track_id"]
    assert_equal "福岡市中央区", json["origin_label"]
    assert_equal [ 33.59, 130.4 ], [ json["lat"], json["lng"] ]
    assert_equal 0, json["play_count"]
    assert_nil json["ended_at"]
  end

  test "飛行中の風船があれば 409" do
    assert_no_difference "Balloon.count" do
      post "/balloons", params: launch_params(track_id: tracks(:alice_song).id), headers: auth_header("alice-token"), as: :json
    end

    assert_response :conflict
    assert_equal "balloon_already_flying", json["code"]
  end

  test "前の風船の旅が終わっていれば、また飛ばせる" do
    balloons(:flying).update!(status: "collected", ended_at: Time.current)

    post "/balloons", params: launch_params(track_id: tracks(:alice_song).id), headers: auth_header("alice-token"), as: :json

    assert_response :created
  end

  test "他の人の曲なら 403" do
    assert_no_difference "Balloon.count" do
      post "/balloons", params: launch_params(track_id: tracks(:alice_song).id), headers: auth_header(@bob_token), as: :json
    end

    assert_response :forbidden
    assert_equal "forbidden_track", json["code"]
  end

  test "出発地点が日本周辺の外なら 422" do
    post "/balloons", params: launch_params(track_id: @bob_song.id, origin_lat: 10.0), headers: auth_header(@bob_token), as: :json

    assert_response :unprocessable_content
    assert_equal "origin_out_of_range", json["code"]
  end

  test "地名がなければ 422" do
    post "/balloons", params: launch_params(track_id: @bob_song.id, origin_label: ""), headers: auth_header(@bob_token), as: :json

    assert_response :unprocessable_content
    assert_equal "validation_failed", json["code"]
    assert_equal "出発地点の地名を入力してください", json["message"]
  end

  test "ログインしていなければ 401" do
    post "/balloons", params: launch_params(track_id: @bob_song.id), as: :json

    assert_response :unauthorized
  end

  private
    def launch_params(**overrides)
      { origin_lat: 33.59, origin_lng: 130.40, origin_label: "福岡市中央区" }.merge(overrides)
    end
end
