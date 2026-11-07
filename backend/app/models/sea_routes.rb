class SeaRoutes
  data = JSON.parse(Rails.root.join("config/sea_routes.json").read)
  PORTS = data.fetch("ports")
  POINTS = PORTS.map { [ _1["lat"], _1["lng"] ] } + data.fetch("waypoints")
  LINKS = data.fetch("links").each_with_object(Hash.new { |links, point| links[point] = [] }) do |(a, b), links|
    links[a] << b
    links[b] << a
  end
  JAPAN_SEA, PACIFIC = PORTS.each_index.partition { PORTS[_1]["side"] == "japan_sea" }

  ARRIVAL_METERS = 10_000
  # 距離に合わせた速さにしないのは、遠い港ほど着くまで待たされ、船に乗った感じが薄れるから
  VOYAGE = 1.minute

  # 動いた後の点ではなく、5秒で動いた線分で判定するのは、風が速いと港を飛び越してしまうから。
  # 飛ばした場所の近くの港で乗らないのは、港町から飛ばした風船が、飛んですぐ遠くの港へ運ばれてしまうから
  def self.port_near(from, to, origin:, except: nil)
    PORTS.each_index.excluding(except)
      .reject { meters_between(POINTS[_1], origin) <= ARRIVAL_METERS }
      .map { |port| [ port, distance_to_segment(POINTS[port], from, to) ] }
      .select { |_, meters| meters <= ARRIVAL_METERS }
      .min_by { |_, meters| meters }&.first
  end

  def self.pick(port, random: Random)
    (JAPAN_SEA.include?(port) ? PACIFIC : JAPAN_SEA).sample(random:)
  end

  # 港から港へ、海の上の道を VOYAGE で進んだときの、位置と東・北向きの速さ（m/s）
  def self.at(from, to, fraction)
    segments = path(from, to).each_cons(2).map { |a, b| [ a, b, meters_between(a, b) ] }
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

  # 点は数百しかないので、優先度つきキューを使わず、毎回いちばん近い点を探す
  def self.path(from, to)
    meters = { from => 0.0 }
    previous = {}
    open = [ from ]
    until (point = open.min_by { meters[_1] }) == to
      open.delete(point)
      LINKS[point].each do |link|
        through = meters[point] + meters_between(POINTS[point], POINTS[link])
        next if meters[link] && meters[link] <= through

        open << link unless meters.key?(link)
        meters[link] = through
        previous[link] = point
      end
    end
    [ to ].tap { |points| points.unshift(previous[points.first]) until points.first == from }.map { POINTS[_1] }
  end

  def self.distance_to_segment(point, from, to)
    ay, ax = offset_meters(point, from)
    by, bx = offset_meters(point, to)
    dx, dy = bx - ax, by - ay
    t = dx.zero? && dy.zero? ? 0 : (-(ax * dx + ay * dy) / (dx * dx + dy * dy)).clamp(0, 1)
    Math.hypot(ax + dx * t, ay + dy * t)
  end

  def self.meters_between(a, b)
    Math.hypot(*offset_meters(a, b))
  end

  # 地球の丸みは緯度ごとの経度の縮みだけで足りる。中継点の間は長くても数百kmで、ずれは道の見た目にしか効かない
  def self.offset_meters((lat1, lng1), (lat2, lng2))
    [ (lat2 - lat1) * Balloon::METERS_PER_DEGREE,
      (lng2 - lng1) * Balloon::METERS_PER_DEGREE * Math.cos(lat1 * Math::PI / 180) ]
  end

  private_class_method :path, :distance_to_segment, :meters_between, :offset_meters
end
