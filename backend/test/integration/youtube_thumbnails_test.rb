require "test_helper"
require "tmpdir"

class YoutubeThumbnailsTest < ActionDispatch::IntegrationTest
  test "YouTubeの画像を保存し、作成・取得・一覧で画像URLを返す" do
    with_youtube_downloader do
      assert_difference -> { Track.count } do
        assert_difference -> { ActiveStorage::Blob.count }, 2 do
          post "/tracks", params: { youtube_url: "https://youtu.be/U6BDbXIah-Y" }, headers: auth_header("alice-token")
        end
      end
    end

    assert_response :created
    track = Track.find(json["id"])
    assert track.audio.attached?
    assert track.thumbnail.attached?
    assert_equal "image/jpeg", track.thumbnail.content_type
    assert_equal "U6BDbXIah-Y.jpg", track.thumbnail.filename.to_s
    assert_equal file_fixture("thumbnail.jpg").binread, track.thumbnail.download
    url = json["thumbnail_url"]
    assert_equal "http://www.example.com/tracks/#{track.id}/thumbnail", url

    get "/tracks/#{track.id}"
    assert_equal url, json["thumbnail_url"]
    get "/me/tracks", headers: auth_header("alice-token")
    assert_equal url, json.find { _1["id"] == track.id }["thumbnail_url"]

    get url
    assert_response :ok
    assert_equal "image/jpeg", response.media_type
    assert_equal file_fixture("thumbnail.jpg").binread, response.body
    assert_match(/inline/, response.headers["Content-Disposition"])
  end

  test "画像がない既存曲はnullを返し、画像取得は404" do
    get "/tracks/#{tracks(:alice_song).id}"
    assert_response :ok
    assert_nil json["thumbnail_url"]

    get "/tracks/#{tracks(:alice_song).id}/thumbnail"
    assert_response :not_found
    get "/tracks/0/thumbnail"
    assert_response :not_found
  end

  test "画像を取得できなければ曲やBlobを保存しない" do
    with_youtube_downloader(thumbnail: false) do
      assert_no_difference [ -> { Track.count }, -> { ActiveStorage::Blob.count } ] do
        post "/tracks", params: { youtube_url: "https://youtu.be/U6BDbXIah-Y" }, headers: auth_header("alice-token")
      end
    end

    assert_response :unprocessable_entity
    assert_equal "youtube_import_failed", json["code"]
  end

  private
    # 外部通信の代わりにyt-dlpの実行ファイルを差し替え、実際の保存・配信処理を通す。
    def with_youtube_downloader(thumbnail: true)
      original_path = ENV.fetch("PATH")
      Dir.mktmpdir("fake-yt-dlp-") do |directory|
        script = File.join(directory, "yt-dlp")
        File.write(script, <<~RUBY)
          #!/usr/bin/env ruby
          require "json"
          require "fileutils"
          if ARGV.include?("--dump-single-json")
            puts JSON.generate(id: "U6BDbXIah-Y", title: "Test song", uploader: "Test artist")
          else
            template = ARGV.fetch(ARGV.index("-o") + 1)
            FileUtils.cp(#{file_fixture("song.mp3").to_s.inspect}, template.sub("%(ext)s", "mp3"))
            if #{thumbnail} && ARGV.include?("--write-thumbnail") && ARGV.include?("--convert-thumbnails")
              FileUtils.cp(#{file_fixture("thumbnail.jpg").to_s.inspect}, template.sub("%(ext)s", "jpg"))
            end
          end
        RUBY
        File.chmod(0o755, script)
        ENV["PATH"] = "#{directory}#{File::PATH_SEPARATOR}#{original_path}"
        yield
      end
    ensure
      ENV["PATH"] = original_path
    end
end
