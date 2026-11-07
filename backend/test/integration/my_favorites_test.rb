require "test_helper"

class MyFavoritesTest < ActionDispatch::IntegrationTest
  test "自分が回収した風船を、曲と一緒に新しい順に返す" do
    older = users(:alice).favorites.create!(balloon: balloons(:lost), collected_on: Date.yesterday, created_at: 1.day.ago)
    newer = users(:alice).favorites.create!(balloon: balloons(:bob_flying), collected_on: Date.current)
    users(:bob).favorites.create!(balloon: balloons(:flying), collected_on: Date.current)

    get "/me/favorites", headers: auth_header("alice-token")

    assert_response :ok
    assert_equal [ newer.id, older.id ], json.map { _1["id"] }
    assert_equal({ "id" => newer.id, "balloon_id" => balloons(:bob_flying).id, "collected_on" => Date.current.to_s,
                   "track" => { "id" => tracks(:bob_song).id, "title" => "空の向こう", "artist" => "推しバンド", "mp3_url" => "https://storage.example.com/tracks/bob_song.mp3" } },
      json.first)
  end

  test "お気に入りがなければ空の配列を返す" do
    get "/me/favorites", headers: auth_header("alice-token")

    assert_equal [], json
  end

  test "token がなければ 401" do
    get "/me/favorites"

    assert_response :unauthorized
  end
end
