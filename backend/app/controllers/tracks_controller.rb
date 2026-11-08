class TracksController < ApplicationController
  skip_before_action :authenticate, only: :show

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

  def create
    if params[:file]
      create_from_file
    else
      create_from_youtube
    end
  end

  private
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
