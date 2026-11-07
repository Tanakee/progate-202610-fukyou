module Balloons
  class PopsController < ApplicationController
    def create
      @balloon = Balloon.find(params[:balloon_id])
      # 再送しても成功として返すため、すでに割っていれば作らない
      current_user.pops.create_or_find_by!(balloon: @balloon) { |pop| pop.popped_at = Time.current }
    end
  end
end
