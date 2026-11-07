class BalloonsController < ApplicationController
  def create
    track = current_user.tracks.find_by(id: params[:track_id])
    return render_error :forbidden, code: "forbidden_track", message: "自分の曲だけを飛ばせます" unless track

    @balloon = current_user.balloons.build(params.permit(:origin_label, :origin_lat, :origin_lng).merge(track: track))

    if @balloon.save
      render :create, status: :created
    elsif @balloon.errors.of_kind?(:origin_lat, :in) || @balloon.errors.of_kind?(:origin_lng, :in)
      render_error :unprocessable_content, code: "origin_out_of_range", message: "この場所からは飛ばせません"
    else
      render_error :unprocessable_content, code: "validation_failed", message: @balloon.errors.full_messages.first
    end
  # validates :uniqueness にしないのは、同時に2回送られると両方とも検証を通ってしまうから。DB の一意制約で止める
  rescue ActiveRecord::RecordNotUnique
    render_error :conflict, code: "balloon_already_flying", message: "飛行中の風船があります"
  end
end
