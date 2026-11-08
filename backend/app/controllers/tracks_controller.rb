class TracksController < ApplicationController
  skip_before_action :authenticate, only: [ :show, :audio ]

  def show
    @track = Track.find_by(id: params[:id])

    unless @track
      render_error :not_found,
        code: "not_found",
        message: "曲が見つかりません"
    end
  end

  def mine
    @tracks = current_user.tracks.order(id: :desc)
  end

  # 音源をRails経由で返し、実機からMinIOへ直接つながなくて済むようにする。
  # AVPlayerが先頭だけを取得してすぐ再生したりシークしたりできるよう、単一のRangeリクエストに対応する。
  def audio
    track = Track.find(params[:id])
    blob = track.audio.blob
    range = requested_range(blob.byte_size)

    return range_not_satisfiable(blob.byte_size) if range == :invalid

    response.headers["Accept-Ranges"] = "bytes"
    response.headers["Content-Type"] = "audio/mpeg"

    if request.head?
      response.headers["Content-Length"] = blob.byte_size.to_s
      return head :ok
    end

    if range
      response.headers["Content-Range"] = "bytes #{range.begin}-#{range.end}/#{blob.byte_size}"
      send_data blob.download_chunk(range), type: "audio/mpeg", disposition: :inline,
        filename: blob.filename.to_s, status: :partial_content
    else
      send_data blob.download, type: "audio/mpeg", disposition: :inline, filename: blob.filename.to_s
    end
  end

  def create
    if params[:file]
      create_from_file
    else
      create_from_youtube
    end
  end

  private
    def requested_range(size)
      header = request.headers["Range"]
      return nil if header.blank?

      match = /\Abytes=(\d*)-(\d*)\z/.match(header)
      return :invalid unless match && (match[1].present? || match[2].present?)

      if match[1].present?
        first = match[1].to_i
        return :invalid if first >= size

        last = match[2].present? ? [ match[2].to_i, size - 1 ].min : size - 1
        return :invalid if last < first
      else
        suffix_size = match[2].to_i
        return :invalid if suffix_size <= 0

        first = [ size - suffix_size, 0 ].max
        last = size - 1
      end

      first..last
    end

    def range_not_satisfiable(size)
      response.headers["Accept-Ranges"] = "bytes"
      response.headers["Content-Range"] = "bytes */#{size}"
      head :range_not_satisfiable
    end

    def create_from_file
      input = params.permit(:title, :artist, :file)

      # 拡張子や Content-Type で MP3 か確かめないのは、どちらも送る側が自由に決められるから。読めるかは ffmpeg に任せる
      unless input[:file].is_a?(ActionDispatch::Http::UploadedFile) && input[:file].size <= 20.megabytes
        return render_error :unprocessable_entity,
          code: "invalid_file",
          message: "20MB以下の音声ファイルを選んでください"
      end

      Mp3Encoder.with_cbr(input[:file].path) do |path|
        save_track(path, title: input[:title], artist: input[:artist],
                         filename: "#{File.basename(input[:file].original_filename, '.*')}.mp3")
      end

      render :show, status: :created
    rescue Mp3Encoder::Error => error
      render_error :unprocessable_entity,
        code: "invalid_file",
        message: error.message
    rescue ActiveRecord::RecordInvalid
      render_error :unprocessable_entity,
        code: "invalid_track",
        message: "曲名とアーティスト名を入力してください"
    end

    def create_from_youtube
      input = params.permit(:youtube_url)
      info = YoutubeVideoInfo.fetch(input[:youtube_url])

      YoutubeAudioDownloader.with_audio(info) do |path|
        save_track(path, title: info["track"].presence || info["title"].presence || "タイトル不明",
                         artist: info["artist"].presence || info["uploader"].presence || "不明",
                         filename: "#{info.fetch('id')}.mp3")
      end

      render :show, status: :created
    rescue YoutubeVideoInfo::Error, YoutubeAudioDownloader::Error => error
      render_error :unprocessable_entity,
        code: "youtube_import_failed",
        message: error.message
    rescue ActiveRecord::RecordInvalid
      render_error :unprocessable_entity,
        code: "invalid_track",
        message: "曲情報を保存できませんでした"
    end

    def save_track(path, title:, artist:, filename:)
      File.open(path, "rb") do |file|
        @track = current_user.tracks.new(title:, artist:)
        @track.audio.attach(io: file, filename:, content_type: "audio/mpeg", identify: false)
        @track.save!
      end
    end
end
