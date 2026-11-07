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
    # ファイルがなければ、既存のYouTube取り込みを使う
    return create_from_youtube unless params[:file].present?

    input = params.permit(:title, :artist, :file)
    file = input[:file]

    unless file.is_a?(ActionDispatch::Http::UploadedFile)
      return render_error :unprocessable_entity,
        code: "invalid_file",
        message: "MP3ファイルを選んでください"
    end

    # サイズ・拡張子・申告されたContent-Typeを確認する
    valid_file =
      file.size.positive? &&
      file.size <= 20.megabytes &&
      File.extname(file.original_filename).downcase == ".mp3" &&
      %w[audio/mpeg audio/mp3].include?(file.content_type)

    unless valid_file
      return render_error :unprocessable_entity,
        code: "invalid_file",
        message: "20MB以下のMP3ファイルを選んでください"
    end

    if input[:title].blank? || input[:artist].blank?
      return render_error :unprocessable_entity,
        code: "invalid_track",
        message: "曲名とアーティスト名を入力してください"
    end

    blob = nil
    track = nil

    begin
      blob = ActiveStorage::Blob.build_after_unfurling(
        io: file.tempfile,
        filename: file.original_filename,
        content_type: "audio/mpeg",
        identify: false
      )

      blob.save!
      file.tempfile.rewind
      blob.upload_without_unfurling(file.tempfile)

      track = current_user.tracks.new(
        title: input[:title],
        artist: input[:artist],
        mp3_url: rails_blob_url(blob, disposition: "inline")
      )

      track.audio.attach(blob)
      track.save!

      @track = track
      render :show, status: :created
    rescue ActiveRecord::RecordInvalid
      render_error :unprocessable_entity,
        code: "invalid_track",
        message: "曲情報を保存できませんでした"
    ensure
      # 曲の保存に失敗した場合は、アップロードしたファイルも削除する
      blob.purge if blob&.persisted? && !track&.persisted?
    end
  end

  def create_from_youtube
    input = params.permit(:youtube_url)
    info = YoutubeVideoInfo.fetch(input[:youtube_url])

    YoutubeAudioDownloader.with_audio(info) do |path|
      File.open(path, "rb") do |file|
        blob = ActiveStorage::Blob.build_after_unfurling(
          io: file,
          filename: "#{info.fetch('id')}.mp3",
          content_type: "audio/mpeg",
          identify: false
        )

        blob.save!
        file.rewind
        blob.upload_without_unfurling(file)

        @track = current_user.tracks.new(
          title: info["track"].presence || info["title"].presence || "タイトル不明",
          artist: info["artist"].presence || info["uploader"].presence || "不明",
          mp3_url: rails_blob_url(blob, disposition: "inline")
        )

        @track.audio.attach(blob)
        @track.save!
      ensure
        blob.purge if blob&.persisted? && !@track&.persisted?
      end
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
end