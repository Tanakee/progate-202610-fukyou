require "test_helper"

class JapanEezTest < ActiveSupport::TestCase
  test "陸地も排他的経済水域の中として扱う" do
    assert JapanEez.cover?(35.68, 139.76)
    assert JapanEez.cover?(43.06, 141.35)
    assert JapanEez.cover?(26.21, 127.68)
  end

  test "日本の沖合の海は中に入る" do
    assert JapanEez.cover?(34.9, 139.9)
  end

  test "他の国や遠い外洋は外になる" do
    assert_not JapanEez.cover?(37.56, 126.97)
    assert_not JapanEez.cover?(31.23, 121.47)
    assert_not JapanEez.cover?(30.0, 160.0)
  end
end
