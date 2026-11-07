require "test_helper"

class PopsTest < ActionDispatch::IntegrationTest
  test "割った風船の ID を返し、自分の世界からだけ消す" do
    post "/balloons/#{balloons(:bob_flying).id}/pop", headers: auth_header("alice-token")

    assert_response :ok
    assert_equal({ "balloon_id" => balloons(:bob_flying).id }, json)
    assert users(:alice).pops.exists?(balloon: balloons(:bob_flying))
    assert_equal "flying", balloons(:bob_flying).reload.status
  end

  test "再送しても成功を返す" do
    2.times { post "/balloons/#{balloons(:bob_flying).id}/pop", headers: auth_header("alice-token") }

    assert_response :ok
    assert_equal 1, users(:alice).pops.count
  end

  test "token がなければ 401" do
    post "/balloons/#{balloons(:bob_flying).id}/pop"

    assert_response :unauthorized
  end
end
