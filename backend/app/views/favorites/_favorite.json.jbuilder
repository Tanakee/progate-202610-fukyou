json.extract! favorite, :id, :balloon_id, :collected_on, :daily_limit_exempt
json.track favorite.track, partial: "tracks/track", as: :track
