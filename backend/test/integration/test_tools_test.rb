require "test_helper"

class TestToolsTest < ActionDispatch::IntegrationTest
  include ActionCable::TestHelper

  test "両APIは認証が必要で、未認証ではデータを変更しない" do
    favorite = users(:alice).favorites.create!(balloon: balloons(:lost), collected_on: Date.current)
    positions = Balloon.order(:id).pluck(:lat, :lng, :moved_at)

    post "/test_reset_favorite_limit"
    assert_response :unauthorized
    assert_not favorite.reload.daily_limit_exempt

    post "/test_reposition_balloons"
    assert_response :unauthorized
    assert_equal positions, Balloon.order(:id).pluck(:lat, :lng, :moved_at)
  end

  test "履歴と他人の上限を残したまま、当日の回収上限を何度でもリセットできる" do
    favorite = users(:alice).favorites.create!(balloon: balloons(:lost), collected_on: Date.current)
    other = users(:bob).favorites.create!(balloon: balloons(:flying), collected_on: Date.current)

    post "/balloons/#{balloons(:bob_flying).id}/collect", headers: auth_header("alice-token")
    assert_response :too_many_requests

    assert_no_difference "Favorite.count" do
      post "/test_reset_favorite_limit", headers: auth_header("alice-token")
    end
    assert_response :ok
    assert_equal 1, json["reset_count"]
    assert favorite.reload.daily_limit_exempt
    assert_equal Date.current, favorite.collected_on
    assert_not other.reload.daily_limit_exempt

    post "/balloons/#{balloons(:bob_flying).id}/collect", headers: auth_header("alice-token")
    assert_response :ok
    assert_not Favorite.find(json["id"]).daily_limit_exempt

    post "/test_reset_favorite_limit", headers: auth_header("alice-token")
    assert_equal 1, json["reset_count"]
    post "/test_reset_favorite_limit", headers: auth_header("alice-token")
    assert_equal 0, json["reset_count"]
  end

  test "過去の回収履歴は上限リセットで変更しない" do
    favorite = users(:alice).favorites.create!(balloon: balloons(:lost), collected_on: Date.yesterday)

    post "/test_reset_favorite_limit", headers: auth_header("alice-token")

    assert_response :ok
    assert_equal 0, json["reset_count"]
    assert_not favorite.reload.daily_limit_exempt
  end

  test "飛行中だけを陸上へ移し、航路と速度を解除して更新後の位置を配信する" do
    balloon = balloons(:bob_flying)
    balloon.update!(bound_for: 1, last_port: 0, boarded_at: 1.minute.ago, speed_east: 20)
    lost = balloons(:lost).attributes
    origins = Balloon.flying.order(:id).pluck(:origin_lat, :origin_lng, :launched_at)

    travel_to Time.current.change(usec: 0) do
      assert_broadcasts("balloons", 1) do
        post "/test_reposition_balloons", headers: auth_header("alice-token")
      end
      assert_response :ok
      assert_equal 2, json["updated_count"]

      Balloon.flying.order(:id).each_with_index do |item, index|
        assert_equal TestBalloonPlacement::POINTS[index], [ item.lat, item.lng ]
        assert JapanEez.cover?(item.lat, item.lng)
        assert_equal Time.current, item.moved_at
        assert_equal [ 0.0, 0.0 ], [ item.speed_east, item.speed_north ]
        assert_nil item.last_port
        assert_nil item.bound_for
        assert_nil item.boarded_at
      end

      message = JSON.parse(broadcasts("balloons").last)
      assert_equal "balloons.snapshot", message["event"]
      assert_equal Balloon.flying.count, message["balloons"].size
      # 次の定期処理でも元の航路へ戻らない。
      Balloon.move_flying!(wind: {}, speed_scale: 1, now: Time.current + 5.seconds)
      assert_nil balloon.reload.bound_for
      assert_equal "flying", balloon.status
    end

    assert_equal lost, balloons(:lost).reload.attributes
    assert_equal origins, Balloon.flying.order(:id).pluck(:origin_lat, :origin_lng, :launched_at)
  end

  test "飛行中が0件でも成功する" do
    Balloon.flying.update_all(status: "lost", ended_at: Time.current)
    post "/test_reposition_balloons", headers: auth_header("alice-token")
    assert_response :ok
    assert_equal 0, json["updated_count"]
  end

  test "すべての配置候補は日本の対象地域内にある" do
    TestBalloonPlacement::POINTS.each do |lat, lng|
      assert JapanEez.cover?(lat, lng), "対象地域の外: #{lat}, #{lng}"
    end
  end

  test "本番環境では認証済みでも実行できない" do
    original_env = Rails.env
    Rails.env = "production"
    post "/test_reset_favorite_limit", headers: auth_header("alice-token")
    assert_response :not_found
    post "/test_reposition_balloons", headers: auth_header("alice-token")
    assert_response :not_found
  ensure
    Rails.env = original_env
  end
end
