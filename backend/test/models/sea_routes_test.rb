require "test_helper"

class SeaRoutesTest < ActiveSupport::TestCase
  test "港から出る航路は、週の便数が多いほど選ばれやすい" do
    hakodate = SeaRoutes::PORTS.index { _1["name"] == "函館" }
    random = Random.new(1)

    picked = 1000.times.map { SeaRoutes::PORTS[SeaRoutes::ROUTES[SeaRoutes.pick(hakodate, random:)]["to"]]["name"] }.tally

    assert_equal %w[大間 青森], picked.keys.sort
    assert_operator picked["青森"], :>, picked["大間"] * 4
  end

  test "日本の港どうしの航路だけを持つ" do
    assert SeaRoutes::PORTS.all? { JapanEez.cover?(_1["lat"], _1["lng"]) }
  end
end
