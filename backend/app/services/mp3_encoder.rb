require "open3"
require "tmpdir"

class Mp3Encoder
  class Error < StandardError; end

  # 受け取ったファイルをそのまま保存しないのは、VBR だと AVPlayer が再生時間やシーク位置を見誤り、
  # 先頭に大きなジャケット画像があると、鳴り始めるまでに読む量が増えるから
  def self.with_cbr(source)
    Dir.mktmpdir("mp3-encoder-") do |directory|
      path = File.join(directory, "audio.mp3")

      _stdout, stderr, status = Open3.capture3(
        "ffmpeg", "-nostdin", "-loglevel", "error",
        "-i", source,
        "-map", "0:a:0", "-codec:a", "libmp3lame", "-b:a", "128k",
        path
      )

      unless status.success?
        warn stderr
        raise Error, "音声を読み込めませんでした"
      end

      yield path
    end
  end
end
