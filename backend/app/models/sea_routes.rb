class SeaRoutes
  data = JSON.parse(Rails.root.join("config/sea_routes.json").read)
  PORTS = data.fetch("ports")
  ROUTES = data.fetch("routes")
  ROUTES_FROM = ROUTES.each_index.group_by { ROUTES[_1]["from"] }

  ARRIVAL_METERS = 10_000
  # 距離に合わせた速さにしないのは、遠い航路ほど着くまで待たされ、船に乗った感じが薄れるから
  VOYAGE = 1.minute

  # 動いた後の点ではなく、5秒で動いた線分で判定するのは、風が速いと港を飛び越してしまうから
  def self.port_near(from, to, except: nil)
    ROUTES_FROM.keys.excluding(except)
      .map { |port| [ port, distance_to_segment(PORTS[port], from, to) ] }
      .select { |_, meters| meters <= ARRIVAL_METERS }
      .min_by { |_, meters| meters }&.first
  end

  def self.pick(port, random: Random)
    routes = ROUTES_FROM.fetch(port)
    ticket = random.rand * routes.sum { ROUTES[_1]["per_week"] }
    routes.find { (ticket -= ROUTES[_1]["per_week"]) < 0 } || routes.last
  end

  # 航路の折れ線を VOYAGE で進んだときの、位置と東・北向きの速さ（m/s）
  def self.at(route, fraction)
    segments = ROUTES[route]["path"].map(&:reverse).each_cons(2).map { |a, b| [ a, b, meters_between(a, b) ] }
    total = segments.sum(&:last)
    traveled = total * fraction.clamp(0, 1)

    a, b, length = segments.find do |segment|
      next true if traveled <= segment.last || segment.equal?(segments.last)
      traveled -= segment.last
      false
    end
    ratio = (traveled / length).clamp(0, 1)
    north, east = offset_meters(a, b)
    speed = total / VOYAGE.to_f
    [ a[0] + (b[0] - a[0]) * ratio, a[1] + (b[1] - a[1]) * ratio, speed * east / length, speed * north / length ]
  end

  def self.distance_to_segment(port, from, to)
    origin = [ port["lat"], port["lng"] ]
    ay, ax = offset_meters(origin, from)
    by, bx = offset_meters(origin, to)
    dx, dy = bx - ax, by - ay
    t = dx.zero? && dy.zero? ? 0 : (-(ax * dx + ay * dy) / (dx * dx + dy * dy)).clamp(0, 1)
    Math.hypot(ax + dx * t, ay + dy * t)
  end

  def self.meters_between(a, b)
    Math.hypot(*offset_meters(a, b))
  end

  # 港の周り数十kmと1本の航路の中だけで使うので、地球の丸みは緯度ごとの経度の縮みだけで足りる
  def self.offset_meters((lat1, lng1), (lat2, lng2))
    [ (lat2 - lat1) * Balloon::METERS_PER_DEGREE,
      (lng2 - lng1) * Balloon::METERS_PER_DEGREE * Math.cos(lat1 * Math::PI / 180) ]
  end

  private_class_method :distance_to_segment, :meters_between, :offset_meters
end
