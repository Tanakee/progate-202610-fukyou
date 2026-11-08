module Balloons
  class LandingsController < ApplicationController
    def create
      # 他の人の風船を 403 ではなく 404 にするのは、回収と違って他の人の風船に下ろす操作はないから
      @balloon = current_user.balloons.find(params[:balloon_id])
      @balloon.land!
    rescue Balloon::NotFlying
      render_error :conflict, code: "balloon_not_flying", message: "この風船はもう飛んでいません"
    end
  end
end
