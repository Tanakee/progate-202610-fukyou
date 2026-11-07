module Balloons
  class PlaysController < ApplicationController
    def create
      @balloon = Balloon.find(params[:balloon_id])
      play = current_user.plays.create_or_find_by!(balloon: @balloon) { |play| play.played_at = Time.current }
      # 再送や旅の終わった風船をエラーにしないのは、再生できたことに変わりはないから。回数だけ増やさない
      Balloon.flying.where(id: @balloon).update_counters(play_count: 1) if play.previously_new_record?
      @balloon.reload
    end
  end
end
