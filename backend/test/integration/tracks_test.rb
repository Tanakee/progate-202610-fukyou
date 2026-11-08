require "test_helper"

class TracksTest < ActionDispatch::IntegrationTest
  setup do
    @token = users(:alice).auth_tokens.create!.token
  end

  test "曲の mp3_url は、Railsの音源取得APIを指す" do
    get "/tracks/#{tracks(:alice_song).id}"

    assert_response :ok
    assert_equal "http://www.example.com/tracks/#{tracks(:alice_song).id}/audio", json["mp3_url"]
    get json["mp3_url"]
    assert_equal file_fixture("song.mp3").binread, response.body
    assert_equal "audio/mpeg", response.media_type
    assert_equal "bytes", response.headers["Accept-Ranges"]
  end

  test "音源の一部をRangeで取得できる" do
    audio = file_fixture("song.mp3").binread

    get "/tracks/#{tracks(:alice_song).id}/audio", headers: { "Range" => "bytes=10-109" }

    assert_response :partial_content
    assert_equal audio.byteslice(10..109), response.body
    assert_equal "bytes 10-109/#{audio.bytesize}", response.headers["Content-Range"]
    assert_equal "100", response.headers["Content-Length"]
  end

  test "末尾からのRangeで音源を取得できる" do
    audio = file_fixture("song.mp3").binread

    get "/tracks/#{tracks(:alice_song).id}/audio", headers: { "Range" => "bytes=-64" }

    assert_response :partial_content
    assert_equal audio.byteslice(-64, 64), response.body
    assert_equal "bytes #{audio.bytesize - 64}-#{audio.bytesize - 1}/#{audio.bytesize}", response.headers["Content-Range"]
  end

  test "音源の範囲外を要求すると416を返す" do
    size = file_fixture("song.mp3").size

    get "/tracks/#{tracks(:alice_song).id}/audio", headers: { "Range" => "bytes=#{size}-" }

    assert_response :range_not_satisfiable
    assert_equal "bytes */#{size}", response.headers["Content-Range"]
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
