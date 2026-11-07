require "test_helper"

class PlaysTest < ActionDispatch::IntegrationTest
  test "初めて再生した風船の回数を1増やす" do
    post "/balloons/#{balloons(:bob_flying).id}/plays", headers: auth_header("alice-token")

    assert_response :ok
    assert_equal({ "play_count" => 4 }, json)
  end

  test "同じ人が同じ風船を再生しても、2回目からは増やさずに成功を返す" do
    2.times { post "/balloons/#{balloons(:bob_flying).id}/plays", headers: auth_header("alice-token") }

    assert_response :ok
    assert_equal 4, json["play_count"]
  end

  test "旅が終わった風船は、増やさずに成功を返す" do
    post "/balloons/#{balloons(:lost).id}/plays", headers: auth_header("bob-token")

    assert_response :ok
    assert_equal 0, json["play_count"]
  end

  test "token がなければ 401" do
    post "/balloons/#{balloons(:bob_flying).id}/plays"

    assert_response :unauthorized
    assert_equal 3, balloons(:bob_flying).reload.play_count
  end

  test "存在しない風船なら 404" do
    post "/balloons/0/plays", headers: auth_header("alice-token")

    assert_response :not_found
    assert_equal "not_found", json["code"]
  end
end
