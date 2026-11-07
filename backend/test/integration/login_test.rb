require "test_helper"

class LoginTest < ActionDispatch::IntegrationTest
  test "メールアドレスとパスワードが合えば、新しい token を返す" do
    assert_difference "AuthToken.count", 1 do
      post "/auth/login", params: { email: "alice@example.com", password: "password123" }, as: :json
    end

    assert_response :ok
    assert json["token"].present?
    assert_equal users(:alice).id, json.dig("user", "id")
  end

  test "メールアドレスの大文字と小文字は区別しない" do
    post "/auth/login", params: { email: "Alice@Example.com", password: "password123" }, as: :json

    assert_response :ok
  end

  test "パスワードが違えば 401" do
    post "/auth/login", params: { email: "alice@example.com", password: "wrong-password" }, as: :json

    assert_response :unauthorized
    assert_equal "invalid_credentials", json["code"]
  end

  test "登録されていないメールアドレスも、同じ 401" do
    post "/auth/login", params: { email: "nobody@example.com", password: "password123" }, as: :json

    assert_response :unauthorized
    assert_equal "invalid_credentials", json["code"]
  end
end
