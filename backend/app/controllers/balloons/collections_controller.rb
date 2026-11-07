module Balloons
  class CollectionsController < ApplicationController
    def create
      @balloon = Balloon.find(params[:balloon_id])

      if @balloon.user_id == current_user.id
        render_error :forbidden, code: "own_balloon", message: "自分の風船は回収できません"
      else
        # 回収済みの本人の再送は、通信が切れて結果を受け取れなかった場合なので、成功として同じ結果を返す
        @favorite = current_user.favorites.find_by(balloon: @balloon) || @balloon.collect_by!(current_user)
      end
    rescue Balloon::NotFlying
      render_error :conflict, code: "balloon_not_flying", message: "この風船はもう飛んでいません"
    rescue ActiveRecord::RecordNotUnique
      render_error :too_many_requests, code: "daily_limit_reached", message: "回収は1日1回までです"
    end
  end
end
