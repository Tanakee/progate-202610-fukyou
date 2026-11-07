# 風データの最初の一周（約3時間）が終わるまで風船が止まらないよう、2026年11月7日の Open-Meteo の風（CC BY 4.0）を初期データとして入れる。
# 日時を古くしておくのは、実際の予報がある地点ではそちらを優先させ、取得もこの地点から先に置き換えさせるため
seeded_at = Time.utc(2000, 1, 1)
wind = JSON.parse(Rails.root.join("db/seeds/wind_grid.json").read, symbolize_names: true)
WindGrid.upsert_all(wind.map { |point| point.merge(valid_time: seeded_at, fetched_at: seeded_at) })
