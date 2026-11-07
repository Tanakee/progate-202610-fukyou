require "test_helper"

class MyPopsTest < ActionDispatch::IntegrationTest
  test "自分が割った風船の ID を新しい順に返す" do
    users(:alice).pops.create!(balloon: balloons(:bob_flying), popped_at: 1.hour.ago)
    users(:alice).pops.create!(balloon: balloons(:lost), popped_at: Time.current)
    users(:bob).pops.create!(balloon: balloons(:flying), popped_at: Time.current)

    get "/me/popped", headers: auth_header("alice-token")

    assert_response :ok
    assert_equal [ balloons(:lost).id, balloons(:bob_flying).id ], json
  end

  test "割った風船がなければ空の配列を返す" do
    get "/me/popped", headers: auth_header("alice-token")

    assert_equal [], json
  end

  test "token がなければ 401" do
    get "/me/popped"

    assert_response :unauthorized
  end
end
