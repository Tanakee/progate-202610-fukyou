require "open3"
require "tmpdir"

class YoutubeAudioDownloader
  class Error < StandardError; end

  def self.with_audio(video_info)
    Dir.mktmpdir("youtube-audio-") do |directory|
      output_template = File.join(directory, "audio.%(ext)s")

      stdout, stderr, status = Open3.capture3(
        "yt-dlp",
        "--ignore-config",
        "--no-playlist",
        "--no-progress",
        "--match-filters", "!is_live",
        "-x",
        "--audio-format", "mp3",
        "--audio-quality", "128K",
        "--socket-timeout", "10",
        "--retries", "0",
        "--extractor-retries", "0",
        "-o", output_template,
        "--",
        video_info.fetch("source_url")
      )

      path = File.join(directory, "audio.mp3")

      unless status.success? && File.file?(path)
        warn "yt-dlp exit code: #{status.exitstatus}"
        warn stderr
        warn stdout
        raise Error, "音声を取得・変換できませんでした"
      end

      unless File.size(path).positive? && File.size(path) <= 20.megabytes
        raise Error, "変換後の音声は20MiB以内にしてください"
      end

      yield path
    end
  end
end