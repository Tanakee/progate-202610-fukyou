require "test_helper"

class LogoutTest < ActionDispatch::IntegrationTest
  test "ログアウトすると、その token は使えなくなる" do
    delete "/auth/session", headers: auth_header("alice-token")
    assert_response :no_content

    get "/me", headers: auth_header("alice-token")
    assert_response :unauthorized
  end

  test "他の端末の token は残る" do
    other_token = users(:alice).auth_tokens.create!.token

    delete "/auth/session", headers: auth_header("alice-token")

    get "/me", headers: auth_header(other_token)
    assert_response :ok
  end

  test "token がなければ 401" do
    delete "/auth/session"

    assert_response :unauthorized
  end
end
