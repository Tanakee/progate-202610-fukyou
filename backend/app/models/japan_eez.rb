class JapanEez
  # EEZ の形は陸地が穴になっているので、外側の輪だけを使って陸地も中に含める
  RINGS = JSON.parse(Rails.root.join("config/japan_eez.json").read).fetch("rings")

  def self.cover?(lat, lng)
    RINGS.any? do |ring|
      ring.each_cons(2).count do |(lng1, lat1), (lng2, lat2)|
        (lat1 > lat) != (lat2 > lat) && lng < (lng2 - lng1) * (lat - lat1) / (lat2 - lat1) + lng1
      end.odd?
    end
  end
end
