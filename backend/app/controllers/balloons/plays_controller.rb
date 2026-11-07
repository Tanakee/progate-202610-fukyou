module Balloons
  class PlaysController < ApplicationController
    def create
      @balloon = Balloon.find(params[:balloon_id])
      play = current_user.plays.create_or_find_by!(balloon: @balloon) { |play| play.played_at = Time.current }
      # 再送や終了済みの風船でも成功として返すため、エラーにせず回数だけ増やさない
      Balloon.flying.where(id: @balloon).update_counters(play_count: 1) if play.previously_new_record?
      @balloon.reload
    end
  end
end
