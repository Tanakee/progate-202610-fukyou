require "open3"
require "uri"
require "json"

class YoutubeVideoInfo
  class Error < StandardError; end

  def self.fetch(url)
    video_url = normalize_url(url)

    output, _, status = Open3.capture3(
      "yt-dlp",
      "--ignore-config",
      "--no-playlist",
      "--skip-download",
      "--dump-single-json",
      "--socket-timeout", "10",
      "--retries", "0",
      "--extractor-retries", "0",
      "--",
      video_url
    )

    unless status.success?
      raise Error, "動画情報を取得できませんでした"
    end

    info = JSON.parse(output)

    if %w[is_live is_upcoming post_live].include?(info["live_status"])
      raise Error, "ライブ配信中・配信予定の動画は登録できません"
    end

    info.merge("source_url" => video_url)
  rescue JSON::ParserError
    raise Error, "動画情報を読み取れませんでした"
  end

  def self.normalize_url(url)
    unless url.is_a?(String) && url.present?
      raise Error, "YouTubeのURLを入力してください"
    end

    uri = URI.parse(url.strip)

    unless uri.is_a?(URI::HTTPS) && uri.userinfo.nil? && uri.port == 443
      raise Error, "HTTPSのYouTube動画URLを指定してください"
    end

    video_id =
      case uri.host&.downcase
      when "youtu.be"
        uri.path.delete_prefix("/")
      when "youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com"
        if uri.path == "/watch"
          URI.decode_www_form(uri.query.to_s).to_h["v"]
        else
          uri.path.match(%r{\A/(?:shorts|embed|live)/([^/]+)/?\z})&.[](1)
        end
      end

    unless video_id&.match?(/\A[A-Za-z0-9_-]{11}\z/)
      raise Error, "YouTubeの動画URLを指定してください"
    end

    "https://www.youtube.com/watch?v=#{video_id}"
  rescue URI::InvalidURIError, ArgumentError
    raise Error, "正しいYouTube動画URLを指定してください"
  end

  private_class_method :normalize_url
end