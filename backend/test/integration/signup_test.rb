require "test_helper"

class SignupTest < ActionDispatch::IntegrationTest
  test "登録すると token と利用者を返す" do
    assert_difference [ "User.count", "AuthToken.count" ], 1 do
      post "/auth/signup", params: { email: "bob@example.com", password: "password123" }, as: :json
    end

    assert_response :created
    assert json["token"].present?
    assert_equal "bob@example.com", json.dig("user", "email")
    assert_equal %w[created_at email id], json["user"].keys.sort
  end

  test "返った token で /me を呼べる" do
    post "/auth/signup", params: { email: "bob@example.com", password: "password123" }, as: :json

    get "/me", headers: auth_header(json["token"])

    assert_response :ok
    assert_equal "bob@example.com", json["email"]
  end

  test "パスワードは平文で保存しない" do
    post "/auth/signup", params: { email: "bob@example.com", password: "password123" }, as: :json

    digest = User.find_by!(email: "bob@example.com").password_digest
    assert digest.start_with?("$argon2id$")
  end

  test "メールアドレスは前後の空白を除き、小文字にそろえる" do
    post "/auth/signup", params: { email: "  Bob@Example.COM ", password: "password123" }, as: :json

    assert_response :created
    assert_equal "bob@example.com", json.dig("user", "email")
  end

  test "登録済みのメールアドレスなら 409" do
    assert_no_difference "User.count" do
      post "/auth/signup", params: { email: "ALICE@example.com", password: "password123" }, as: :json
    end

    assert_response :conflict
    assert_equal "email_taken", json["code"]
  end

  test "パスワードが短ければ 422" do
    post "/auth/signup", params: { email: "bob@example.com", password: "short" }, as: :json

    assert_response :unprocessable_content
    assert_equal "validation_failed", json["code"]
    assert_equal "パスワードは8文字以上で入力してください", json["message"]
  end

  test "メールアドレスの形式が正しくなければ 422" do
    post "/auth/signup", params: { email: "not-an-email", password: "password123" }, as: :json

    assert_response :unprocessable_content
    assert_equal "メールアドレスの形式が正しくありません", json["message"]
  end

  test "パスワードがなければ 422" do
    post "/auth/signup", params: { email: "bob@example.com" }, as: :json

    assert_response :unprocessable_content
    assert_equal "パスワードは8文字以上で入力してください", json["message"]
  end
end
