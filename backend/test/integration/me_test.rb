require "test_helper"

class MeTest < ActionDispatch::IntegrationTest
  test "token の持ち主を返す" do
    get "/me", headers: auth_header("alice-token")

    assert_response :ok
    assert_equal users(:alice).id, json["id"]
    assert_equal "alice@example.com", json["email"]
    assert_nil json["password_digest"]
  end

  test "Authorization ヘッダーがなければ 401" do
    get "/me"

    assert_response :unauthorized
    assert_equal({ "code" => "unauthorized", "message" => "ログインしてください" }, json)
  end

  test "token が無効なら 401" do
    get "/me", headers: auth_header("unknown-token")

    assert_response :unauthorized
  end

  test "Bearer 以外の形式なら 401" do
    get "/me", headers: { "Authorization" => "Basic alice-token" }

    assert_response :unauthorized
  end
end
