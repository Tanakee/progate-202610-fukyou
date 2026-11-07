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