json.extract! track, :id, :title, :artist
json.mp3_url audio_track_url(track)
json.thumbnail_url track.thumbnail.attached? ? thumbnail_track_url(track) : nil
