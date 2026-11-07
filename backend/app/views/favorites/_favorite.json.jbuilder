json.extract! favorite, :id, :balloon_id, :collected_on
json.track favorite.track, partial: "tracks/track", as: :track
