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
    attributes = params.permit(:title, :artist)
    file = params[:file]

    if attributes[:title].blank? || attributes[:artist].blank?
      return render_error :unprocessable_entity,
        code: "invalid_track",
        message: "曲名とアーティスト名を入力してください"
    end

    unless file.is_a?(ActionDispatch::Http::UploadedFile)
      return render_error :unprocessable_entity,
        code: "invalid_file",
        message: "MP3ファイルを選んでください"
    end

    unless file.size.positive? && file.size <= 20.megabytes
      return render_error :unprocessable_entity,
        code: "invalid_file",
        message: "空でない20MB以内のMP3ファイルを選んでください"
    end

    content_type = Marcel::MimeType.for(file.tempfile)
    file.tempfile.rewind

    unless content_type == "audio/mpeg"
      return render_error :unprocessable_entity,
        code: "invalid_file",
        message: "MP3ファイルを選んでください"
    end

    blob = ActiveStorage::Blob.build_after_unfurling(
      io: file.tempfile,
      filename: file.original_filename,
      content_type: content_type,
      identify: false
    )
    blob.save!
    file.tempfile.rewind
    blob.upload_without_unfurling(file.tempfile)

    @track = current_user.tracks.new(attributes)
    @track.audio.attach(blob)
    @track.mp3_url = rails_blob_url(blob, disposition: "inline")
    @track.save!

    render :show, status: :created
  rescue ActiveRecord::RecordInvalid
    render_error :unprocessable_entity,
      code: "invalid_track",
      message: "曲情報を保存できませんでした"
  ensure
    blob.purge if blob&.persisted? && !@track&.persisted?
  end
end