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
  # 飛ばした場所の近くの港で乗らないのは、港町から飛ばした風船が、飛んですぐ遠くの港へ運ばれてしまうから。
  # 降りた港だけでなくその近くの港も除くのは、港の並ぶ所で隣の港からすぐ乗り直し、風で漂わなくなるから
  def self.port_near(from, to, origin:, except: nil)
    ignored = [ origin, (POINTS[except] if except) ].compact
    PORTS.each_index
      .reject { |port| ignored.any? { meters_between(POINTS[port], _1) <= ARRIVAL_METERS } }
      .map { |port| [ port, distance_to_segment(POINTS[port], from, to) ] }
      .select { |_, meters| meters <= ARRIVAL_METERS }
      .min_by { |_, meters| meters }&.first
  end

  def self.pick(port, random: Random)
    (JAPAN_SEA.include?(port) ? PACIFIC : JAPAN_SEA).sample(random:)
  end

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

  # 乗ったときに求めた道を風船に持たせないのは、出た港と行き先の港が同じなら道も同じで、組ごとに覚えれば足りるから
  def self.path(from, to)
    (@paths ||= {})[[ from, to ]] ||= shortest_path(from, to)
  end

  # 点は数百しかないので、優先度つきキューを使わず、毎回いちばん近い点を探す
  def self.shortest_path(from, to)
    meters = { from => 0.0 }
    previous = {}
    open = [ from ]
    loop do
      point = open.min_by { meters[_1] } or raise ArgumentError, "港 #{from} から #{to} へ海の上の道がない"
      break if point == to

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

  private_class_method :path, :shortest_path, :distance_to_segment, :meters_between, :offset_meters
end
