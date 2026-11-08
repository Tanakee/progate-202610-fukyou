require "test_helper"

class TracksTest < ActionDispatch::IntegrationTest
  setup do
    @token = users(:alice).auth_tokens.create!.token
  end

  test "曲の mp3_url は、ストレージの音声を直接指す" do
    get "/tracks/#{tracks(:alice_song).id}"

    assert_response :ok
    assert_match %r{/rails/active_storage/disk/.+/song\.mp3\z}, json["mp3_url"]
    get json["mp3_url"]
    assert_equal file_fixture("song.mp3").binread, response.body
  end

  test "音声ファイルを送ると、128kbps の固定ビットレートで、ジャケット画像を除いた MP3 にして保存する" do
    assert_difference -> { users(:alice).tracks.count } do
      upload file: fixture_file_upload("vbr_with_cover.mp3", "audio/mpeg"), title: "夜明け", artist: "推しバンド"
    end

    assert_response :created
    track = users(:alice).tracks.find(json["id"])
    assert_equal [ "夜明け", "推しバンド", "vbr_with_cover.mp3", "audio/mpeg" ],
                 [ track.title, track.artist, track.audio.filename.to_s, track.audio.content_type ]
    assert_equal [ [ "audio", "mp3", "128000" ] ], streams(track)
  end

  test "音声として読めないファイルは保存しない" do
    assert_no_difference -> { Track.count } do
      upload file: fixture_file_upload("not_audio.mp3", "audio/mpeg"), title: "夜明け", artist: "推しバンド"
    end

    assert_response :unprocessable_entity
    assert_equal "invalid_file", json["code"]
  end

  test "曲名がなければ、曲も音声も保存しない" do
    assert_no_difference [ -> { Track.count }, -> { ActiveStorage::Blob.count } ] do
      upload file: fixture_file_upload("song.mp3", "audio/mpeg"), artist: "推しバンド"
    end

    assert_response :unprocessable_entity
    assert_equal "invalid_track", json["code"]
  end

  private
    def upload(**params)
      post "/tracks", params:, headers: { "Authorization" => "Bearer #{@token}" }
    end

    def streams(track)
      track.audio.open do |file|
        stdout, = Open3.capture2("ffprobe", "-v", "error", "-show_entries", "stream=codec_type,codec_name,bit_rate", "-of", "csv=p=0", file.path)
        stdout.lines.map { _1.strip.split(",").values_at(1, 0, 2) }
      end
    end
end
