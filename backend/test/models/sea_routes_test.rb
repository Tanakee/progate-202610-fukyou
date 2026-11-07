require "test_helper"

class SeaRoutesTest < ActiveSupport::TestCase
  test "太平洋側の港からは日本海側の港を、日本海側の港からは太平洋側の港を、ランダムに選ぶ" do
    tokyo = SeaRoutes::PORTS.index { _1["name"] == "東京" }
    niigata = SeaRoutes::PORTS.index { _1["name"] == "新潟" }
    random = Random.new(1)

    from_pacific = 100.times.map { SeaRoutes.pick(tokyo, random:) }
    from_japan_sea = 100.times.map { SeaRoutes.pick(niigata, random:) }

    assert_empty from_pacific - SeaRoutes::JAPAN_SEA
    assert_operator from_pacific.uniq.size, :>, 10
    assert_empty from_japan_sea - SeaRoutes::PACIFIC
    assert_operator from_japan_sea.uniq.size, :>, 10
  end

  test "道は出た港から始まり、行き先の港で終わる" do
    tokyo = SeaRoutes::PORTS.index { _1["name"] == "東京" }
    niigata = SeaRoutes::PORTS.index { _1["name"] == "新潟" }

    assert_equal SeaRoutes::POINTS[tokyo], SeaRoutes.at(tokyo, niigata, 0).first(2)
    assert_equal SeaRoutes::POINTS[niigata].map { _1.round(6) }, SeaRoutes.at(tokyo, niigata, 1).first(2).map { _1.round(6) }
  end

  test "どの港からも、海の上の道でほかのすべての港へ行ける" do
    reached = [ 0 ]
    reached.each { |point| reached.concat(SeaRoutes::LINKS[point] - reached) }

    assert_empty SeaRoutes::PORTS.each_index.to_a - reached
  end

  test "日本の港だけを持つ" do
    assert SeaRoutes::PORTS.all? { JapanEez.cover?(_1["lat"], _1["lng"]) }
  end
end
