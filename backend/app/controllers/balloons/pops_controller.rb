module Balloons
  class PopsController < ApplicationController
    def create
      @balloon = Balloon.find(params[:balloon_id])
      # create! で一意制約のエラーを返さないのは、再送でも成功として扱いたいから
      current_user.pops.create_or_find_by!(balloon: @balloon) { |pop| pop.popped_at = Time.current }
    end
  end
end
